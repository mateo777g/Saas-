-- Pruebas de la migración mi_menu (6 y 7 de noviembre de 2026): el dólar de todos, que pone el Cron del
-- Worker, y el inglés que traduce la IA. Vacío quiere decir que falta traducir: si cambia el español y el
-- inglés no, se vacía; si cambian los dos, se queda. pendientes_de_traducir va con la sesión del gerente y
-- guardar_traducciones solo lo llama el Worker, que nunca pisa lo que el gerente cambió o escribió.
--
-- Todo corre en una transacción que se deshace al final.

begin;

create extension if not exists pgtap with schema extensions;


-- ─── Ayudantes de basejump ────────────────────────────────────────────────────
-- Copiados de supabase-test-helpers 0.0.6 (github.com/usebasejump/supabase-test-helpers,
-- commit d90a51f), sin las funciones de congelar el tiempo.
--
-- Copyright 2023 usebasejump.com
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this
-- software and associated documentation files (the "Software"), to deal in the Software
-- without restriction, including without limitation the rights to use, copy, modify,
-- merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to the following
-- conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies
-- or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
-- PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
-- HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
-- CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
-- OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

create schema tests;

create function tests.create_supabase_user(identifier text, email text default null, phone text default null, metadata jsonb default null)
returns uuid
security definer
set search_path = auth, pg_temp
as $$
declare
  user_id uuid;
begin
  user_id := extensions.uuid_generate_v4();
  insert into auth.users (id, email, phone, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
  values (user_id, coalesce(email, concat(user_id, '@test.com')), phone, jsonb_build_object('test_identifier', identifier) || coalesce(metadata, '{}'::jsonb), '{}'::jsonb, now(), now())
  returning id into user_id;
  return user_id;
end;
$$ language plpgsql;

create function tests.get_supabase_user(identifier text)
returns json
security definer
set search_path = auth, pg_temp
as $$
declare
  supabase_user json;
begin
  select json_build_object(
    'id', id,
    'email', email,
    'phone', phone,
    'raw_user_meta_data', raw_user_meta_data,
    'raw_app_meta_data', raw_app_meta_data
  ) into supabase_user
  from auth.users
  where raw_user_meta_data ->> 'test_identifier' = identifier limit 1;

  if supabase_user is null or supabase_user -> 'id' is null then
    raise exception 'User with identifier % not found', identifier;
  end if;
  return supabase_user;
end;
$$ language plpgsql;

create function tests.get_supabase_uid(identifier text)
returns uuid
security definer
set search_path = auth, pg_temp
as $$
declare
  supabase_user uuid;
begin
  select id into supabase_user from auth.users where raw_user_meta_data ->> 'test_identifier' = identifier limit 1;
  if supabase_user is null then
    raise exception 'User with identifier % not found', identifier;
  end if;
  return supabase_user;
end;
$$ language plpgsql;

create function tests.authenticate_as(identifier text)
returns void
as $$
declare
  user_data json;
  original_auth_data text;
begin
  original_auth_data := current_setting('request.jwt.claims', true);
  user_data := tests.get_supabase_user(identifier);

  if user_data is null or user_data ->> 'id' is null then
    raise exception 'User with identifier % not found', identifier;
  end if;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', user_data ->> 'id',
    'email', user_data ->> 'email',
    'phone', user_data ->> 'phone',
    'user_metadata', user_data -> 'raw_user_meta_data',
    'app_metadata', user_data -> 'raw_app_meta_data'
  )::text, true);
exception
  when others then
    set local role authenticated;
    set local "request.jwt.claims" to original_auth_data;
    raise;
end
$$ language plpgsql;

create function tests.clear_authentication()
returns void as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

-- La sesión de un aparato ligado: quien no es gerente solo funciona desde ahí (migración
-- empleados). Se suma a la sesión de tests.authenticate_as.
create function tests.en_aparato(p_sesion uuid)
returns void as $$
begin
  perform set_config('request.jwt.claims',
    (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
      || jsonb_build_object('session_id', p_sesion))::text, true);
end
$$ language plpgsql;

grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;


-- Cuántas filas cambió una orden, para las que RLS deja pasar sin error y sin efecto.
create function tests.filas(p_sql text)
returns integer
language plpgsql
as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function tests.filas(text) to anon, authenticated;


create table tests.ids (nombre text primary key, id bigint not null);
grant select on tests.ids to anon, authenticated;

-- Guarda un id con nombre, para usarlo en pruebas que corren con otra sesión.
create function tests.guardar(p_nombre text, p_id bigint)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into tests.ids (nombre, id) values (p_nombre, p_id)
  on conflict (nombre) do update set id = excluded.id
  returning id;
$$;

create function tests.id(p_nombre text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from tests.ids where nombre = p_nombre;
$$;

grant execute on function tests.guardar(text, bigint), tests.id(text) to anon, authenticated;
-- El Worker llama a hacer_pedido como service_role, con la llave secreta.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, con ids fijos. A es la fonda de Don Chuy, con tope de 10 dólares; B
-- nació con tope 0; C ya gastó el sobre de su menú este mes; D tiene 25 categorías sin inglés, para
-- ver que se traducen de 20 en 20.

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Como en producción, la sesión corre en UTC: así una hora sin zona se notaría.
set local time zone 'UTC';

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  d uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, tope_ia_usd_mes) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, 10),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, 0),
    (c, 'Restaurante C', 'restaurante-c', true, hoy - 30, hoy + 30, 10),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 30, hoy + 30, 10);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    (131, d, tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true);

  -- El menú de A: Tacos ya traducida, Bebidas sin inglés y Temporada archivada.
  insert into public.categorias (id, restaurante_id, nombre, nombre_en, icono) overriding system value values
    (601, a, 'Tacos', 'Tacos', 'taco'),
    (602, a, 'Bebidas', null, 'refresco'),
    (603, a, 'Temporada', null, 'especialidad'),
    (611, b, 'Tacos B', null, 'taco'),
    (621, c, 'Tacos C', null, 'taco');

  insert into public.productos (id, restaurante_id, categoria_id, nombre, nombre_en, descripcion, descripcion_en, precio)
  overriding system value values
    (501, a, 601, 'Taco al pastor', 'Al pastor taco', 'Con piña y cilantro', 'With pineapple and cilantro', 22),
    (502, a, 601, 'Gringa', null, 'Tortilla de harina con queso', null, 65),
    (503, a, 601, 'Quesadilla', 'Quesadilla', 'De maíz', null, 40),
    (504, a, 602, 'Agua de horchata', null, null, null, 25),
    (506, a, 601, 'Taco viejo', null, null, null, 20),
    (507, a, 603, 'Elote', null, null, null, 30),
    (511, b, 611, 'Taco B', null, null, null, 25),
    (521, c, 621, 'Taco C', null, null, null, 25);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, es_envio) overriding system value values
    (505, a, 602, 'Envío', 30, true);
  update public.productos set archivado_at = now() where id = 506;
  update public.categorias set archivado_at = now() where id = 603;

  insert into public.grupos_opciones (id, restaurante_id, nombre, nombre_en, minimo, maximo) overriding system value values
    (901, a, 'Salsa', 'Salsa', 0, 1),
    (902, a, 'Tortilla', null, 1, 1);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, nombre_en, precio_extra, orden) overriding system value values
    (9011, a, 901, 'Verde', 'Green', 0, 1),
    (9012, a, 901, 'Roja', null, 0, 2),
    (9021, a, 902, 'Maíz', null, 0, 1),
    (9022, a, 902, 'Harina', null, 5, 2);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values
    (a, 501, 901), (a, 502, 901), (a, 502, 902);

  insert into public.mesas (id, restaurante_id, nombre) overriding system value values (801, a, 'Mesa 1');

  -- D: 25 categorías sin inglés, en su orden.
  insert into public.categorias (restaurante_id, nombre, icono)
  select d, 'Categoría ' || lpad(n::text, 2, '0'), 'comida' from generate_series(1, 25) as n;

  -- C ya gastó los 2 dólares de su menú este mes.
  insert into public.uso_ia (restaurante_id, mes, costo_menu_usd)
  values (c, privado.mes_ia('America/Mexico_City'), 2);
end;
$$;

-- Lo que falta traducir de A, como lo ve el Worker con la sesión de Don Chuy.
create function tests.pendientes(p_restaurante uuid)
returns jsonb
language sql
as $$
  select public.pendientes_de_traducir(p_restaurante)
$$;

grant execute on function tests.pendientes(uuid) to authenticated;

select plan(74);


-- ─── Estructura y permisos ────────────────────────────────────────────────────

select ok(
  (select relrowsecurity from pg_class where oid = 'public.tipo_de_cambio'::regclass),
  'tipo_de_cambio tiene RLS'
);

select ok(
  not has_any_column_privilege('anon', 'public.tipo_de_cambio', 'SELECT, INSERT, UPDATE')
  and not has_any_column_privilege('authenticated', 'public.tipo_de_cambio', 'SELECT, INSERT, UPDATE')
  and not has_any_column_privilege('service_role', 'public.tipo_de_cambio', 'SELECT, INSERT, UPDATE')
  and not has_table_privilege('authenticated', 'public.tipo_de_cambio', 'DELETE')
  and not has_table_privilege('service_role', 'public.tipo_de_cambio', 'DELETE'),
  'Nadie lee ni escribe tipo_de_cambio directo: ni con sesión, ni sin ella, ni el Worker'
);

select results_eq(
  $$ select moneda, pesos from public.tipo_de_cambio $$,
  $$ values ('USD'::text, 18.7040::numeric) $$,
  'La migración pone el primer dólar, así que siempre hay uno: una sola fila, en USD'
);

select throws_ok(
  $$ insert into public.tipo_de_cambio (moneda, pesos) values ('EUR', 20) $$,
  '23514', null,
  'Solo hay dólares: otra moneda no entra'
);

select throws_ok(
  $$ insert into public.tipo_de_cambio (moneda, pesos) values ('USD', 20) $$,
  '23505', null,
  'Ni un segundo dólar: la fila es una'
);

select throws_ok(
  $$ update public.tipo_de_cambio set pesos = -1 $$,
  '23514', null,
  'El dólar vale más que cero pesos'
);

select ok(
  to_regprocedure('public.guardar_menu_en_linea(uuid, text, text, numeric, boolean)') is null
  and not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'restaurantes' and column_name = 'tipo_cambio_usd'),
  'El tipo de cambio de cada restaurante ya no existe, ni el «Guardar» que lo recibía'
);

select ok(
  has_function_privilege('service_role', 'public.fijar_tipo_de_cambio(numeric)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.fijar_tipo_de_cambio(numeric)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.fijar_tipo_de_cambio(numeric)', 'EXECUTE'),
  'fijar_tipo_de_cambio solo lo llama el Worker, con la llave secreta'
);

select ok(
  has_function_privilege('authenticated', 'public.pendientes_de_traducir(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.pendientes_de_traducir(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.pendientes_de_traducir(uuid)', 'EXECUTE'),
  'pendientes_de_traducir va con la sesión del gerente: sin sesión no, ni con la llave del Worker'
);

select ok(
  has_function_privilege('service_role', 'public.guardar_traducciones(uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.guardar_traducciones(uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.guardar_traducciones(uuid, jsonb)', 'EXECUTE'),
  'guardar_traducciones solo lo llama el Worker'
);

select ok(
  not has_function_privilege('anon', 'privado.traducciones_que_llegan(jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'privado.traducciones_que_llegan(jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role', 'privado.traducciones_que_llegan(jsonb)', 'EXECUTE'),
  'La limpieza de lo que llega no la llama nadie de fuera'
);

select ok(
  has_function_privilege('authenticated', 'public.guardar_menu_en_linea(uuid, text, text, boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.guardar_menu_en_linea(uuid, text, text, boolean)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.guardar_menu_en_linea(uuid, text, text, boolean)', 'EXECUTE'),
  'El «Guardar» de Cómo se ve, sin el dólar, va con la sesión del gerente'
);


-- ─── El dólar del día (el Cron del Worker) ────────────────────────────────────

select tests.como_worker();

select is(
  public.fijar_tipo_de_cambio(19.12345),
  19.1235::numeric,
  'El Worker pone el dólar del día y le regresa lo que quedó, a 4 decimales'
);

reset role;

select results_eq(
  $$ select moneda, pesos, updated_at = now() from public.tipo_de_cambio $$,
  $$ values ('USD'::text, 19.1235::numeric, true) $$,
  'Reemplaza al de ayer: sigue una sola fila, con la hora en que se puso'
);

select tests.como_worker();

select throws_ok(
  $$ select public.fijar_tipo_de_cambio(0) $$,
  '22023', 'El tipo de cambio va en pesos por dólar, como 18.7040',
  'Un dólar de cero pesos no se guarda'
);

select throws_ok(
  $$ select public.fijar_tipo_de_cambio(-18.7) $$,
  '22023', 'El tipo de cambio va en pesos por dólar, como 18.7040',
  'Ni uno negativo'
);

select throws_ok(
  $$ select public.fijar_tipo_de_cambio(null) $$,
  '22023', 'El tipo de cambio va en pesos por dólar, como 18.7040',
  'Ni uno vacío'
);

select throws_ok(
  $$ select public.fijar_tipo_de_cambio(10000) $$,
  '22023', 'El tipo de cambio va en pesos por dólar, como 18.7040',
  'Ni uno que no cabe'
);

reset role;

select is(
  (select pesos from public.tipo_de_cambio),
  19.1235::numeric,
  'Si lo que llega no sirve, se queda el último'
);


-- ─── El menú que ve la clienta ────────────────────────────────────────────────

select tests.como_worker();
select public.fijar_tipo_de_cambio(20);
reset role;

select is(
  array[(public.menu_publico('fonda-don-chuy') -> 'restaurante' ->> 'tipo_cambio_usd')::numeric,
        (public.menu_publico('restaurante-b') -> 'restaurante' ->> 'tipo_cambio_usd')::numeric],
  array[20, 20]::numeric[],
  'Todos los menús traen el mismo dólar, el del día'
);

select results_eq(
  $$ select (p ->> 'id')::bigint, (p ->> 'precio_usd')::numeric
     from jsonb_array_elements(public.menu_publico('fonda-don-chuy') -> 'categorias') c,
          jsonb_array_elements(c -> 'productos') p
     order by 1 $$,
  $$ values (501::bigint, 1.10::numeric), (502, 3.25), (503, 2.00), (504, 1.25) $$,
  'Los precios en dólares salen del dólar de todos, al centavo'
);

select is(
  (select jsonb_agg(jsonb_build_object('id', o -> 'id', 'usd', o -> 'precio_extra_usd') order by o ->> 'id')
   from jsonb_array_elements(public.menu_publico('fonda-don-chuy') -> 'categorias') c,
        jsonb_array_elements(c -> 'productos') p,
        jsonb_array_elements(p -> 'grupos') g,
        jsonb_array_elements(g -> 'opciones') o
   where p ->> 'id' = '502'),
  '[{"id": 9011, "usd": 0}, {"id": 9012, "usd": 0}, {"id": 9021, "usd": 0}, {"id": 9022, "usd": 0.25}]'::jsonb,
  'Y lo que suma cada opción, también'
);

select ok(
  (select (p ->> 'precio_usd')::numeric
   from jsonb_array_elements(public.menu_publico('restaurante-b') -> 'categorias') c,
        jsonb_array_elements(c -> 'productos') p) = 1.25,
  'Un restaurante que nunca escribió su tipo de cambio ya trae dólares'
);


-- ─── Lo que falta traducir ────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  tests.pendientes('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true, "motivo": null, "quedan": 8, "pendientes": [
     {"tipo": "categoria", "id": 602, "nombre": "Bebidas"},
     {"tipo": "producto", "id": 502, "nombre": "Gringa", "descripcion": "Tortilla de harina con queso"},
     {"tipo": "producto", "id": 503, "nombre": "Quesadilla", "descripcion": "De maíz"},
     {"tipo": "producto", "id": 504, "nombre": "Agua de horchata"},
     {"tipo": "grupo", "id": 902, "nombre": "Tortilla"},
     {"tipo": "opcion", "id": 9012, "nombre": "Roja", "grupo": "Salsa"},
     {"tipo": "opcion", "id": 9021, "nombre": "Maíz", "grupo": "Tortilla"},
     {"tipo": "opcion", "id": 9022, "nombre": "Harina", "grupo": "Tortilla"}]}'::jsonb,
  'Don Chuy tiene 8 por traducir, en el orden de su menú: sin lo traducido, el envío, lo archivado ni lo de una categoría archivada; la descripción solo si le falta, y cada opción con su grupo'
);

select throws_ok(
  $$ select tests.pendientes('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  '42501', 'Solo el gerente de este restaurante traduce su menú',
  'Don Chuy no ve lo que le falta a otro restaurante'
);

select tests.authenticate_as('gerente_b');

select is(
  tests.pendientes('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  '{"puede": false, "motivo": "sin_ia", "quedan": 2, "pendientes": []}'::jsonb,
  'Con el tope en 0 no se traduce: dice cuántos faltan, sin mandarlos'
);

select tests.authenticate_as('gerente_c');

select is(
  tests.pendientes('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  '{"puede": false, "motivo": "limite", "quedan": 2, "pendientes": []}'::jsonb,
  'Con el sobre del menú gastado, tampoco'
);

select tests.authenticate_as('gerente_d');

select is(
  (select jsonb_build_object('quedan', x -> 'quedan', 'van', jsonb_array_length(x -> 'pendientes'),
                             'primera', x -> 'pendientes' -> 0 -> 'nombre', 'ultima', x -> 'pendientes' -> 19 -> 'nombre')
   from tests.pendientes('dddddddd-dddd-4ddd-8ddd-dddddddddddd') x),
  '{"quedan": 25, "van": 20, "primera": "Categoría 01", "ultima": "Categoría 20"}'::jsonb,
  'Van de 20 en 20, las primeras de su menú, y quedan dice todas las que faltan'
);

reset role;


-- ─── Lo que tradujo la IA ─────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[]') $$,
  '42501', null,
  'Don Chuy no escribe traducciones directo, aunque sean de su menú'
);

reset role;
select tests.como_worker();

select is(
  public.guardar_traducciones('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '[
    {"tipo": "categoria", "id": 602, "nombre": "Bebidas", "nombre_en": "Drinks"},
    {"tipo": "producto", "id": 504, "nombre": "Agua de horchata", "nombre_en": "Horchata"},
    {"tipo": "grupo", "id": 902, "nombre": "Tortilla", "nombre_en": "Tortilla"},
    {"tipo": "opcion", "id": 9021, "nombre": "Maíz", "nombre_en": "Corn"}]'),
  0,
  'Con otro restaurante, lo de A no se escribe'
);

select is(
  public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', ('[
    {"tipo": "categoria", "id": 602, "nombre": "Refrescos", "nombre_en": "Sodas"},
    {"tipo": "categoria", "id": 601, "nombre": "Tacos", "nombre_en": "Taquitos"},
    {"tipo": "categoria", "id": 603, "nombre": "Temporada", "nombre_en": "Seasonal"},
    {"tipo": "producto", "id": 505, "nombre": "Envío", "nombre_en": "Delivery"},
    {"tipo": "producto", "id": 506, "nombre": "Taco viejo", "nombre_en": "Old taco"},
    {"tipo": "producto", "id": 504, "nombre": "Agua de horchata", "nombre_en": "   "},
    {"tipo": "grupo", "id": 902, "nombre": "Tortilla", "nombre_en": null},
    {"tipo": "opcion", "id": 9012, "nombre": "Roja", "nombre_en": "' || repeat('x', 201) || '"},
    {"tipo": "mesa", "id": 801, "nombre": "Mesa 1", "nombre_en": "Table 1"},
    {"tipo": "opcion", "id": "9021; drop table x", "nombre": "Maíz", "nombre_en": "Corn"},
    {"tipo": "producto", "id": 511, "nombre": "Taco B", "nombre_en": "Taco B"},
    {"tipo": "producto", "id": 503, "nombre": "Quesadilla", "descripcion": "De trigo", "descripcion_en": "Wheat"},
    {"tipo": "producto", "id": 504, "nombre": "Agua de jamaica", "nombre_en": "Hibiscus water"},
    {"tipo": "grupo", "id": 902, "nombre": "Tortillas", "nombre_en": "Tortillas"},
    {"tipo": "grupo", "id": 901, "nombre": "Salsa", "nombre_en": "Sauce"},
    {"tipo": "opcion", "id": 9022, "nombre": "Harinas", "nombre_en": "Flours"},
    {"tipo": "opcion", "id": 9011, "nombre": "Verde", "nombre_en": "Green sauce"},
    "no es un objeto"]')::jsonb),
  0,
  'Nada de lo que no viene bien se escribe: español que ya cambió, inglés que ya existe, archivados, el envío, un inglés en blanco, vacío o demasiado largo, un tipo o un id que no existen, algo de otro restaurante'
);

select throws_ok(
  $$ select public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '{"tipo": "categoria"}') $$,
  '22023', 'Las traducciones van en una lista, con su restaurante',
  'Las traducciones van en una lista'
);

select throws_ok(
  $$ select public.guardar_traducciones(null, '[]') $$,
  '22023', 'Las traducciones van en una lista, con su restaurante',
  '… y con su restaurante'
);

reset role;

select results_eq(
  $$ select (select count(*) from public.categorias where nombre_en is not null)::integer,
            (select count(*) from public.productos where nombre_en is not null or descripcion_en is not null)::integer,
            (select count(*) from public.grupos_opciones where nombre_en is not null)::integer,
            (select count(*) from public.opciones where nombre_en is not null)::integer,
            (select nombre_en from public.categorias where id = 601),
            (select nombre_en from public.grupos_opciones where id = 901),
            (select nombre_en from public.opciones where id = 9011) $$,
  $$ values (1, 2, 1, 1, 'Tacos'::text, 'Salsa'::text, 'Green'::text) $$,
  'Y de verdad nada cambió'
);

select tests.como_worker();

select is(
  public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
    {"tipo": "categoria", "id": 602, "nombre": "Bebidas", "nombre_en": " Drinks "},
    {"tipo": "producto", "id": 502, "nombre": "Gringa", "descripcion": "Tortilla de harina",
     "nombre_en": "Gringa", "descripcion_en": "Flour tortilla"},
    {"tipo": "producto", "id": 503, "nombre": "Quesadilla", "descripcion": "De maíz",
     "nombre_en": "Cheese quesadilla", "descripcion_en": "Corn tortilla"},
    {"tipo": "producto", "id": 504, "nombre": "Agua de horchata", "nombre_en": "Horchata"},
    {"tipo": "grupo", "id": 902, "nombre": "Tortilla", "nombre_en": "Tortilla"},
    {"tipo": "opcion", "id": 9012, "nombre": "Roja", "nombre_en": "Red"},
    {"tipo": "opcion", "id": "9021", "nombre": "Maíz", "nombre_en": "Corn"},
    {"tipo": "opcion", "id": 9022, "nombre": "Harina", "nombre_en": "Flour"}]'),
  8,
  'Lo que viene bien se escribe, y dice cuántos renglones: 8'
);

reset role;

select results_eq(
  $$ select 'categoria', id, nombre_en, null::text from public.categorias where id = 602
     union all
     select 'producto', id, nombre_en, descripcion_en from public.productos where id in (501, 502, 503, 504)
     union all
     select 'grupo', id, nombre_en, null from public.grupos_opciones where id = 902
     union all
     select 'opcion', id, nombre_en, null from public.opciones where id in (9011, 9012, 9021, 9022)
     order by 1, 2 $$,
  $$ values ('categoria'::text, 602::bigint, 'Drinks'::text, null::text),
            ('grupo', 902, 'Tortilla', null),
            ('opcion', 9011, 'Green', null), ('opcion', 9012, 'Red', null),
            ('opcion', 9021, 'Corn', null), ('opcion', 9022, 'Flour', null),
            ('producto', 501, 'Al pastor taco', 'With pineapple and cilantro'),
            ('producto', 502, 'Gringa', null),
            ('producto', 503, 'Quesadilla', 'Corn tortilla'),
            ('producto', 504, 'Horchata', null) $$,
  'Cada inglés quedó en su lugar, sin espacios; el nombre de la Quesadilla, que ya tenía, no se pisó, y de la Gringa solo su nombre: su descripción se tradujo de un español viejo'
);

select tests.authenticate_as('gerente_a');

select is(
  tests.pendientes('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true, "motivo": null, "quedan": 1, "pendientes": [
     {"tipo": "producto", "id": 502, "nombre": "Gringa", "descripcion": "Tortilla de harina con queso"}]}'::jsonb,
  'Así la Gringa sigue pendiente, solo por su descripción'
);

reset role;
select tests.como_worker();

select is(
  public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
    {"tipo": "producto", "id": 502, "nombre": "Gringa", "descripcion": "Tortilla de harina con queso",
     "nombre_en": "Gringa sandwich", "descripcion_en": "Flour tortilla with cheese"}]'),
  1,
  'La siguiente vuelta la escribe'
);

reset role;

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where id = 502 $$,
  $$ values ('Gringa'::text, 'Flour tortilla with cheese'::text) $$,
  '… sin pisar el nombre que ya tenía'
);

select tests.authenticate_as('gerente_a');

select is(
  tests.pendientes('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true, "motivo": null, "quedan": 0, "pendientes": []}'::jsonb,
  'Ya no le falta nada a Don Chuy'
);

reset role;
select tests.como_worker();

select is(
  public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '[{"tipo": "categoria", "id": 602, "nombre": "Bebidas", "nombre_en": "Beverages"}]'),
  0,
  'Una traducción que llega tarde no pisa la que ya está'
);

select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu_sin_respuesta', 'gpt-5.6-luna', 1000, 0, 0, 500)
    ->> 'puede',
  'true',
  'El Worker anota el gasto de traducir como gasto del menú, sin contar una pregunta'
);

reset role;

select results_eq(
  $$ select consultas_menu, costo_menu_usd, costo_agente_usd, costo_anuncios_usd from public.uso_ia
     where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  $$ values (0, 0.0008::numeric, 0::numeric, 0::numeric) $$,
  'Entra al sobre del asistente del menú: no hay renglón nuevo, y el agente y los anuncios no cambian'
);


-- ─── Vacío quiere decir que falta traducir ────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  tests.filas($$ update public.categorias set nombre = 'Tacos de la casa', nombre_en = 'Tacos' where id = 601 $$),
  1,
  'Don Chuy cambia el nombre de Tacos y deja el inglés como estaba'
);

select is(
  (select nombre_en from public.categorias where id = 601),
  null,
  '… y el inglés se vacía, para volver a traducirlo'
);

select is(
  tests.pendientes('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'pendientes',
  '[{"tipo": "categoria", "id": 601, "nombre": "Tacos de la casa"}]'::jsonb,
  'Así vuelve a la lista de lo que falta'
);

select is(
  tests.filas($$ update public.categorias set nombre = 'Aguas', nombre_en = 'Waters' where id = 602 $$),
  1,
  'Cambia el nombre de Bebidas y también su inglés'
);

select is(
  (select nombre_en from public.categorias where id = 602),
  'Waters',
  '… y se queda lo que él escribió'
);

select is(
  tests.filas($$ update public.categorias set nombre_en = 'Our drinks' where id = 602 $$),
  1,
  'Corrige solo el inglés'
);

select is(
  (select nombre || ' · ' || nombre_en from public.categorias where id = 602),
  'Aguas · Our drinks',
  '… y se respeta'
);

select is(
  tests.filas($$ update public.categorias set nombre = '  Aguas  ', nombre_en = 'Our drinks' where id = 602 $$),
  1,
  'Guarda con espacios de más, sin cambiar nada'
);

select is(
  (select nombre || ' · ' || nombre_en from public.categorias where id = 602),
  'Aguas · Our drinks',
  '… y el inglés no se toca: el español es el mismo'
);

select lives_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 601, 'Taco de pastor',
       'Con piña y cilantro', 22, null, array[901]::bigint[], 'Al pastor taco', 'With pineapple and cilantro') $$,
  'Cambia el nombre del Taco al pastor y deja lo demás'
);

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where id = 501 $$,
  $$ values (null::text, 'With pineapple and cilantro'::text) $$,
  '… y solo se vacía el inglés del nombre'
);

select is(
  tests.pendientes('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'pendientes',
  '[{"tipo": "categoria", "id": 601, "nombre": "Tacos de la casa"},
    {"tipo": "producto", "id": 501, "nombre": "Taco de pastor"}]'::jsonb,
  'Así vuelve a la lista, sin su descripción, que ya tiene inglés'
);

reset role;
select tests.como_worker();

select is(
  public.guardar_traducciones('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
    {"tipo": "producto", "id": 501, "nombre": "Taco de pastor", "descripcion": "Con piña y cilantro",
     "nombre_en": "Pastor taco", "descripcion_en": "Pineapple"}]'),
  1,
  'La IA lo vuelve a traducir'
);

reset role;

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where id = 501 $$,
  $$ values ('Pastor taco'::text, 'With pineapple and cilantro'::text) $$,
  '… y solo escribe el nombre: la descripción en inglés que ya estaba no se pisa'
);

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 502, 601, 'Gringa',
       'Tortilla de harina con queso y pastor', 65, null, array[901, 902]::bigint[], 'Gringa', 'Flour tortilla with cheese') $$,
  'Cambia solo la descripción de la Gringa'
);

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where id = 502 $$,
  $$ values ('Gringa'::text, null::text) $$,
  '… y solo se vacía la descripción en inglés'
);

select lives_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 503, 601, 'Quesadilla',
       ' ', 40, null, '{}', 'Quesadilla', 'Corn tortilla') $$,
  'Le borra la descripción a la Quesadilla'
);

select results_eq(
  $$ select descripcion, descripcion_en from public.productos where id = 503 $$,
  $$ values (null::text, null::text) $$,
  '… y sin descripción en español no queda la de inglés'
);

select tests.guardar('jamaica', public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 602, 'Jamaica',
  null, 28, null, '{}', 'Hibiscus', 'Hibiscus water'));

select is(
  (select descripcion_en from public.productos where id = tests.id('jamaica')),
  null,
  'Un producto nuevo tampoco lleva descripción en inglés sin la de español'
);

select lives_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 504, 602, 'Horchata',
       'De arroz', 25, null, '{}', 'Rice horchata', 'Rice and cinnamon') $$,
  'Cambia el nombre y la descripción de la horchata, con su inglés'
);

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where id = 504 $$,
  $$ values ('Rice horchata'::text, 'Rice and cinnamon'::text) $$,
  '… y se queda lo que escribió'
);

select lives_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Salsas', 0, 1,
       '[{"id": 9011, "nombre": "Verde cruda", "nombre_en": "Green"},
         {"id": 9012, "nombre": "Roja", "nombre_en": "Red"}]',
       array[501, 502]::bigint[], 'Salsa') $$,
  'Cambia el nombre del grupo y el de la salsa verde, con el inglés de antes'
);

select results_eq(
  $$ select 'grupo', id, nombre_en from public.grupos_opciones where id = 901
     union all
     select 'opcion', id, nombre_en from public.opciones where id in (9011, 9012)
     order by 1, 2 $$,
  $$ values ('grupo'::text, 901::bigint, null::text), ('opcion', 9011, null), ('opcion', 9012, 'Red') $$,
  '… y se vacían el inglés del grupo y el de la verde; el de la roja, que no cambió, se queda'
);

reset role;

select is(
  tests.filas($$ update public.productos set visible = false where id = 502 $$),
  1,
  'Ocultar un producto…'
);

select is(
  (select nombre_en from public.productos where id = 502),
  'Gringa',
  '… no toca su inglés'
);

select lives_ok(
  $$ update public.mesas set nombre = '  Terraza 1  ' where id = 801 $$,
  'Las mesas se siguen limpiando con la misma función, aunque no tienen inglés'
);

select is(
  (select nombre from public.mesas where id = 801),
  'Terraza 1',
  '… sin espacios de más'
);

select lives_ok(
  $$ update public.areas_preparacion set nombre = '  Barra  '
     where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'Y las áreas'
);

select is(
  (select nombre from public.areas_preparacion where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'Barra',
  '… también sin espacios'
);


-- ─── Cómo se ve, sin el dólar ─────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'oscuro', '#b3261e', true) $$,
  'Don Chuy guarda Cómo se ve sin escribir el dólar'
);

select results_eq(
  $$ select menu_tema, menu_color, hace_envios from public.restaurantes $$,
  $$ values ('oscuro'::text, '#B3261E'::text, true) $$,
  'El tema, el color y «Hago envíos» se guardan'
);

reset role;

select * from finish();
rollback;
