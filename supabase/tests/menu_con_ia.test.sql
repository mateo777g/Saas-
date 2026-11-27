-- Pruebas de la migración menu_con_ia (27 de noviembre de 2026): las cartas que lee la IA para armar Mi
-- menú se anotan en uso_ia por su lado, fuera de los sobres (funcionan con tope 0), 3 al mes por
-- restaurante; puedo_leer_carta dice cuántas quedan, y subir_a_mi_menu sube lo revisado todo o nada:
-- solo agrega, una categoría que ya existe recibe sus productos y una nueva va a la primera área.
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
-- Se siembra como postgres, con ids fijos. A es la fonda de Don Chuy, recién dada de alta con tope 0:
-- tiene Tacos y Bebidas, Temporada archivada y tres áreas, la primera (Barra) archivada; el mes pasado
-- ya leyó sus 3 cartas. B tiene tope de 10 y no tiene áreas ni menú. C tiene la licencia vencida. D
-- tiene un tope de 0.05 dólares, para ver que las cartas no salen de sus sobres. Pepe es mesero de A.

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
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, tope_ia_usd_mes) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 1, hoy + 7, 0),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, 10),
    (c, 'Restaurante C', 'restaurante-c', true, hoy - 60, hoy - 1, 10),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 30, hoy + 30, 0.05);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true);

  insert into public.areas_preparacion (id, restaurante_id, nombre) overriding system value values
    (701, a, 'Barra'), (702, a, 'Cocina'), (703, a, 'Postres');
  update public.areas_preparacion set archivado_at = now() where id = 701;

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Tacos', 'taco', 703),
    (602, a, 'Bebidas', 'refresco', null),
    (603, a, 'Temporada', 'especialidad', 702);
  update public.categorias set archivado_at = now() where id = 603;

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio) overriding system value values
    (501, a, 601, 'Taco al pastor', 25),
    (502, a, 601, 'Gringa', 65),
    (503, a, 602, 'Agua de horchata', 35);

  -- El mes pasado A leyó sus 3 cartas: este mes empieza de nuevo.
  insert into public.uso_ia (restaurante_id, mes, cartas, costo_cartas_usd)
  values (a, (privado.mes_ia('America/Mexico_City') - interval '1 month')::date, 3, 0.4500);
end;
$$;

-- Lo que Don Chuy sube, con su sesión.
create function tests.subir(p_restaurante uuid, p_categorias text)
returns jsonb
language sql
as $$
  select public.subir_a_mi_menu(p_restaurante, p_categorias::jsonb)
$$;

-- Cuántas categorías y productos tiene un restaurante, archivados incluidos.
create function tests.menu_de(p_restaurante uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'categorias', (select count(*) from public.categorias where restaurante_id = p_restaurante),
    'productos', (select count(*) from public.productos where restaurante_id = p_restaurante));
$$;

-- El renglón de este mes de uso_ia.
create function tests.uso(p_restaurante uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object('cartas', u.cartas, 'cartas_usd', u.costo_cartas_usd,
                            'consultas_agente', u.consultas_agente, 'saludos', u.saludos,
                            'agente_usd', u.costo_agente_usd, 'consultas_menu', u.consultas_menu,
                            'menu_usd', u.costo_menu_usd, 'anuncios_usd', u.costo_anuncios_usd,
                            'total', u.costo_usd)
  from public.uso_ia u
  where u.restaurante_id = p_restaurante and u.mes = privado.mes_ia('America/Mexico_City');
$$;

-- El día 1 del mes que viene, en la zona de los restaurantes.
create function tests.vuelve()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (privado.mes_ia('America/Mexico_City') + interval '1 month')::date
$$;

grant execute on function tests.subir(uuid, text), tests.menu_de(uuid), tests.uso(uuid), tests.vuelve()
to anon, authenticated, service_role;

select plan(68);


-- ─── Estructura y permisos ────────────────────────────────────────────────────

select col_type_is('public', 'uso_ia', 'cartas', 'integer', 'uso_ia.cartas es un número entero');
select col_default_is('public', 'uso_ia', 'cartas', '0', 'y empieza en 0');
select col_type_is('public', 'uso_ia', 'costo_cartas_usd', 'numeric(10,4)', 'uso_ia.costo_cartas_usd va en dólares con 4 decimales');
select col_default_is('public', 'uso_ia', 'costo_cartas_usd', '0', 'y empieza en 0');

select throws_ok(
  $$ insert into public.uso_ia (restaurante_id, mes, cartas) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2026-01-01', -1) $$,
  '23514', null,
  'Las cartas no bajan de 0'
);
select throws_ok(
  $$ insert into public.uso_ia (restaurante_id, mes, costo_cartas_usd) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2026-01-01', -0.0001) $$,
  '23514', null,
  'Ni su costo'
);

insert into public.uso_ia (restaurante_id, mes, costo_agente_usd, costo_anuncios_usd, costo_menu_usd, costo_cartas_usd)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2026-01-01', 1, 2, 0.5, 0.25);
select is(
  (select costo_usd from public.uso_ia where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and mes = '2026-01-01'),
  3.7500::numeric(10,4),
  'costo_usd es la suma de los tres sobres y las cartas'
);

select ok(
  not has_column_privilege('anon', 'public.uso_ia', 'cartas', 'SELECT')
  and not has_column_privilege('authenticated', 'public.uso_ia', 'cartas', 'SELECT')
  and not has_column_privilege('service_role', 'public.uso_ia', 'cartas', 'SELECT')
  and not has_column_privilege('authenticated', 'public.uso_ia', 'cartas', 'UPDATE')
  and not has_column_privilege('service_role', 'public.uso_ia', 'cartas', 'UPDATE')
  and not has_column_privilege('anon', 'public.uso_ia', 'costo_cartas_usd', 'SELECT')
  and not has_column_privilege('authenticated', 'public.uso_ia', 'costo_cartas_usd', 'SELECT')
  and not has_column_privilege('service_role', 'public.uso_ia', 'costo_cartas_usd', 'SELECT')
  and not has_column_privilege('authenticated', 'public.uso_ia', 'costo_cartas_usd', 'UPDATE')
  and not has_column_privilege('service_role', 'public.uso_ia', 'costo_cartas_usd', 'UPDATE'),
  'Nadie lee ni escribe las cartas directo: solo anotar_uso_ia'
);

select is_empty(
  $$ select f from unnest(array['public.puedo_leer_carta(uuid)', 'public.subir_a_mi_menu(uuid, jsonb)']) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'puedo_leer_carta y subir_a_mi_menu van con la sesión: sin sesión no, ni con la llave del Worker'
);

select ok(
  has_function_privilege('service_role', 'public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)', 'EXECUTE'),
  'anotar_uso_ia sigue siendo solo del Worker'
);

select is_empty(
  $$ select f from unnest(array['privado.cartas_al_mes()', 'privado.cartas_del_mes(uuid)']) as f
     where has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Las cuentas de las cartas no las llama nadie de fuera'
);

select is(privado.cartas_al_mes(), 3, 'Son 3 cartas al mes, en un solo lugar');


-- ─── ¿Puedo leer otra carta? ──────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select is(
  public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('puede', true, 'quedan', 3, 'de', 3,
                     'vuelve', tests.vuelve()),
  'Con tope 0, el día del alta, Don Chuy puede leer sus 3 cartas del mes: las del mes pasado no cuentan'
);
select throws_ok(
  $$ select public.puedo_leer_carta(null) $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'Sin restaurante, nada'
);

select tests.authenticate_as('mesero_a');
select throws_ok(
  $$ select public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'Pepe, el mesero, no lee cartas'
);

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'El gerente de otro restaurante tampoco'
);

select tests.authenticate_as('gerente_c');
select throws_ok(
  $$ select public.puedo_leer_carta('cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'Con la licencia vencida, ni el suyo'
);

select tests.clear_authentication();
select throws_ok(
  $$ select public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null,
  'Sin sesión, nada'
);
reset role;


-- ─── El gasto de las cartas ───────────────────────────────────────────────────
-- gpt-6.1-sol: 2 dólares el millón de entrada, 0.10 lo leído de caché y 10 la salida.

select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carta', 'gpt-6.1-sol', 12000, 2000, 0, 8000),
  '{"costo": 0.1002, "puede": true}'::jsonb,
  'Una carta leída: su costo, y que todavía le quedan'
);
select is(
  tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"cartas": 1, "cartas_usd": 0.1002, "consultas_agente": 0, "saludos": 0, "agente_usd": 0, "consultas_menu": 0,
    "menu_usd": 0, "anuncios_usd": 0, "total": 0.1002}'::jsonb,
  'Suma una carta y su costo, aparte: ni es pregunta ni toca un sobre; el total sí la suma'
);
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carta_sin_lectura', 'gpt-6.1-sol', 3000, 0, 0, 500),
  '{"costo": 0.0110, "puede": true}'::jsonb,
  'Una que falló a medias se anota con lo que cobró OpenAI'
);
select is(
  tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'consultas_agente' - 'saludos' - 'agente_usd' - 'consultas_menu'
    - 'menu_usd' - 'anuncios_usd',
  '{"cartas": 1, "cartas_usd": 0.1112, "total": 0.1112}'::jsonb,
  'pero no cuenta en las 3'
);

select tests.authenticate_as('gerente_a');
select is(
  public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'vuelve',
  '{"puede": true, "quedan": 2, "de": 3}'::jsonb,
  '«Te quedan 2 de 3 este mes»'
);

select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carta', 'gpt-6.1-sol', 12000, 2000, 0, 8000) ->> 'puede',
  'true',
  'La segunda: todavía le queda una'
);
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carta', 'gpt-6.1-sol', 12000, 2000, 0, 8000) ->> 'puede',
  'false',
  'La tercera: ya no le queda ninguna'
);

select tests.authenticate_as('gerente_a');
select is(
  public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('puede', false, 'quedan', 0, 'de', 3,
                     'vuelve', tests.vuelve()),
  '«Ya leíste 3 cartas este mes. Vuelve el 1…»'
);

-- Dos lecturas a la vez desde dos pestañas pueden pasarse de 3 por una: se anota, y le quedan 0.
select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carta', 'gpt-6.1-sol', 12000, 2000, 0, 8000),
  '{"costo": 0.1002, "puede": false}'::jsonb,
  'Una cuarta que se coló se anota igual: lo que cuesta no se pierde'
);
select tests.authenticate_as('gerente_a');
select is(
  (public.puedo_leer_carta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan')::integer,
  0,
  'y le quedan 0, no -1'
);

select tests.como_worker();
select is(
  public.anotar_uso_ia('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'carta', 'gpt-6.1-sol', 12000, 2000, 0, 8000),
  '{"costo": 0.1002, "puede": true}'::jsonb,
  'D, con un tope de 0.05, lee una carta de 0.10: no sale del tope'
);
reset role;
select is(
  array[privado.saldo_ia('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'agente') ->> 'puede',
        privado.saldo_ia('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'menu') ->> 'puede'],
  array['true', 'true'],
  'Su agente y su menú siguen con lo suyo: la carta no tocó sus sobres'
);

select tests.como_worker();
select throws_ok(
  $$ select public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'foto', 'gpt-6.1-sol', 100, 0, 0, 10) $$,
  '22023', 'El uso de IA es pregunta, saludo, menu, menu_sin_respuesta, palabras, carta o carta_sin_lectura',
  'Un uso que no existe no se anota'
);
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu_sin_respuesta', 'gpt-5.6-luna', 1000, 0, 0, 0),
  jsonb_build_object('costo', 0.0002, 'puede', false),
  'Lo demás sigue igual: una traducción con tope 0 va al sobre del menú, que está en 0'
);
reset role;


-- ─── «Tope de IA» en el panel de Fragmentless ────────────────────────────────

select tests.authenticate_as('fragmentless');
select is(
  public.uso_ia_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'mes' - 'distribuidor_id' - 'distribuidor',
  '{"tope": 0.00, "gastado": 0.4120, "sobre_agente": 0.00, "gastado_agente": 0, "consultas_agente": 0, "saludos": 0,
    "agente_en_limite": false, "sobre_anuncios": 0.00, "gastado_anuncios": 0, "anuncios": 0, "anuncios_caben": 0,
    "anuncios_en_limite": false, "sobre_menu": 0.00, "gastado_menu": 0.0002, "consultas_menu": 0,
    "menu_en_limite": false, "cartas": 4, "gastado_cartas": 0.4118}'::jsonb,
  'Las cartas en su renglón: cuántas y cuánto costaron, fuera de los sobres; lo gastado del mes sí las suma'
);
select is(
  public.uso_ia_cliente('dddddddd-dddd-4ddd-8ddd-dddddddddddd') -> 'gastado',
  '0.1002'::jsonb,
  'Aunque pase de su tope, porque no es un sobre'
);
reset role;


-- ─── «Subir a mi menú» ────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select is(
  tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', $j$[
    {"nombre": "TACOS ", "icono": "taco", "productos": [
      {"nombre": "Taco de suadero", "descripcion": "Con cebolla y cilantro", "precio": 28},
      {"nombre": " Gringa ", "descripcion": "", "precio": 65}]},
    {"nombre": "Tortas", "icono": "torta", "productos": [
      {"nombre": "Torta de milanesa", "descripcion": "   ", "precio": 85.5},
      {"nombre": "Torta cubana", "precio": 110}]},
    {"nombre": "Temporada", "icono": "especialidad", "productos": [
      {"nombre": "Elote", "descripcion": null, "precio": 30}]},
    {"nombre": "tortas", "icono": "pan", "productos": [
      {"nombre": "Torta de jamón", "precio": 70.555}]}
  ]$j$),
  '{"categorias_nuevas": 2, "productos": 6}'::jsonb,
  'Sube todo de una vez y dice cuántas categorías nuevas y cuántos productos'
);
reset role;

select results_eq(
  $$ select nombre, descripcion, precio, orden from public.productos where categoria_id = 601 order by orden $$,
  $$ values ('Taco al pastor'::text, null::text, 25.00::numeric, 1), ('Gringa', null, 65.00, 2),
            ('Taco de suadero', 'Con cebolla y cilantro', 28.00, 3), ('Gringa', null, 65.00, 4) $$,
  'Tacos ya existía: sus productos nuevos entran ahí, al final y en el orden de la carta (la Gringa palomeada también)'
);
select results_eq(
  $$ select nombre, icono, area_preparacion_id, archivado_at is null from public.categorias where id = 601 $$,
  $$ values ('Tacos'::text, 'taco'::text, 703::bigint, true) $$,
  'y Tacos se queda como estaba: su nombre, su ícono y su área'
);
select results_eq(
  $$ select nombre, icono, area_preparacion_id, orden from public.categorias
     where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and id not in (601, 602, 603) order by orden $$,
  $$ values ('Tortas'::text, 'torta'::text, 702::bigint, 4), ('Temporada', 'especialidad', 702, 5) $$,
  'Las nuevas van al final, con su ícono y la primera área que no está archivada (Cocina)'
);
select results_eq(
  $$ select p.nombre, p.descripcion, p.precio, p.orden from public.productos p
     join public.categorias c on c.id = p.categoria_id
     where c.restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and c.nombre = 'Tortas' order by p.orden $$,
  $$ values ('Torta de milanesa'::text, null::text, 85.50::numeric, 1), ('Torta cubana', null, 110.00, 2),
            ('Torta de jamón', null, 70.56, 3) $$,
  '«tortas», que llegó dos veces, es una sola; sin descripción si viene vacía; los precios con sus centavos'
);
select ok(
  not exists (select 1 from public.productos where categoria_id = 603)
  and (select archivado_at is not null from public.categorias where id = 603)
  and exists (select 1 from public.productos p join public.categorias c on c.id = p.categoria_id
              where c.restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and c.nombre = 'Temporada'
                and c.archivado_at is null and p.nombre = 'Elote'),
  'Una categoría archivada con el mismo nombre no recibe nada: se crea otra'
);
select is(
  (select count(*)::integer from public.productos
   where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and id not in (501, 502, 503)
     and visible and imagen_ruta is null and nombre_en is null and descripcion_en is null
     and not es_envio and archivado_at is null),
  6,
  'Los 6 entran visibles, sin foto y con su inglés vacío, para que la IA lo traduzca'
);

select tests.authenticate_as('gerente_b');
select is(
  tests.subir('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '[{"nombre": "Bebidas", "icono": "refresco", "productos": [{"nombre": "Agua de jamaica", "precio": 35}]}]'),
  '{"categorias_nuevas": 1, "productos": 1}'::jsonb,
  'B no tiene áreas'
);
reset role;
select is(
  (select area_preparacion_id from public.categorias where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  null::bigint,
  'así que su categoría nueva la sirve el mesero'
);
select tests.guardar('categorias_a', (tests.menu_de('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'categorias')::bigint);
select tests.guardar('productos_a', (tests.menu_de('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'productos')::bigint);


-- ─── Todo o nada ──────────────────────────────────────────────────────────────
-- Cada una empieza con Postres, que sí está bien: si algo falla, tampoco se queda.

select tests.authenticate_as('gerente_a');
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]},
       {"nombre": "Tacos", "icono": "taco", "productos": [{"nombre": "Taco de lengua", "precio": null}]}]') $$,
  '22023', 'Falta el precio de «Taco de lengua»',
  'Un producto sin precio no se sube'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}, {"nombre": "Pay"}]}]') $$,
  '22023', 'Falta el precio de «Pay»',
  'Ni uno al que le falta el precio'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": "45"}]}]') $$,
  '22023', 'Falta el precio de «Flan»',
  'El precio va como número'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": -1}]}]') $$,
  '22023', 'Revisa el precio de «Flan»',
  'Un precio no es negativo'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 10000000000}]}]') $$,
  '22023', 'Revisa el precio de «Flan»',
  'Ni más grande de lo que cabe'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}, {"nombre": "  ", "precio": 40}]}]') $$,
  '22023', 'Un producto de «Postres» no tiene nombre',
  'Un producto sin nombre no se sube'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "descripcion": 5, "precio": 45}]}]') $$,
  '22023', 'Revisa la descripción de «Flan»',
  'La descripción va como texto'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}, "Pay"]}]') $$,
  '22023', 'Cada producto de «Postres» va con su nombre y su precio',
  'Un producto va con su nombre y su precio'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]},
       {"nombre": " ", "icono": "taco", "productos": [{"nombre": "Taco de lengua", "precio": 30}]}]') $$,
  '22023', 'Una categoría no tiene nombre',
  'Una categoría sin nombre no se sube'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]}, "Ensaladas"]') $$,
  '22023', 'Cada categoría va con su nombre y sus productos',
  'Una categoría va con su nombre y sus productos'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '22023', 'Falta el ícono de «Postres»',
  'Una categoría nueva lleva su ícono'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "pastel", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '23514', null,
  'de los 28'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Tacos", "icono": "taco", "productos": [{"nombre": "Taco de lengua", "precio": 30}]},
       {"nombre": "Postres", "icono": "postre", "productos": []}]') $$,
  '22023', '«Postres» no tiene productos',
  'Una categoría sin productos no se sube'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[]') $$,
  '22023', 'No hay nada que subir a tu menú',
  'Sin nada, nada'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '{"nombre": "Postres"}') $$,
  '22023', 'No hay nada que subir a tu menú',
  'Lo que sube es una lista de categorías'
);
select throws_ok(
  $$ select public.subir_a_mi_menu('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null) $$,
  '22023', 'No hay nada que subir a tu menú',
  'Ni vacía'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       (select jsonb_agg(jsonb_build_object('nombre', 'Sección ' || n, 'icono', 'comida',
                                            'productos', jsonb_build_array(jsonb_build_object('nombre', 'Platillo', 'precio', 50))))
        from generate_series(1, 41) n)::text) $$,
  '22023', 'Son muchas categorías de una vez: sube a lo mucho 40',
  'A lo mucho 40 categorías de una vez'
);
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       jsonb_build_array(
         jsonb_build_object('nombre', 'Comida', 'icono', 'comida', 'productos',
           (select jsonb_agg(jsonb_build_object('nombre', 'Platillo ' || n, 'precio', 50)) from generate_series(1, 200) n)),
         jsonb_build_object('nombre', 'Más comida', 'icono', 'comida', 'productos',
           (select jsonb_agg(jsonb_build_object('nombre', 'Platillo ' || n, 'precio', 50)) from generate_series(1, 201) n)))::text) $$,
  '22023', 'Son muchos productos de una vez: sube a lo mucho 400',
  'y 400 productos'
);
reset role;
select is(
  tests.menu_de('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('categorias', tests.id('categorias_a'), 'productos', tests.id('productos_a')),
  'Nada de eso dejó nada a medias: ni Postres, ni el Flan'
);


-- ─── Quién sube ───────────────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'Pepe, el mesero, no sube nada'
);
select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'El gerente de otro restaurante tampoco'
);
select tests.authenticate_as('gerente_c');
select throws_ok(
  $$ select tests.subir('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar su menú',
  'Con la licencia vencida, ni al suyo'
);
select tests.clear_authentication();
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '42501', null,
  'Sin sesión, nada'
);
select tests.como_worker();
select throws_ok(
  $$ select tests.subir('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"nombre": "Postres", "icono": "postre", "productos": [{"nombre": "Flan", "precio": 45}]}]') $$,
  '42501', null,
  'Ni el Worker con su llave: sube Don Chuy, con su sesión'
);
reset role;
select is(
  tests.menu_de('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('categorias', tests.id('categorias_a'), 'productos', tests.id('productos_a')),
  'Y nadie de ellos subió nada'
);

select * from finish();
rollback;
