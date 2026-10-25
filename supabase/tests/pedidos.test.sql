-- Pruebas de los pedidos del menú en línea, parte 6b (migración pedidos): lo decidido el 20 de
-- octubre de 2026 en las libretas 6 y 5, el Diccionario y las decisiones de la 6b, con su maqueta.
-- hacer_pedido solo lo llama el Worker, revisa licencia, horario, pausa, teléfono, «Hago envíos»,
-- lo agotado, los límites y los precios, y si algo cambió no guarda nada; el número corto vuelve
-- a 1 cada día de negocio. Solo la caja y el gerente ven, confirman, rechazan y pausan; confirmar
-- abre la cuenta con los precios del pedido y el envío elegido, sin comanda para el envío; lo que
-- nadie confirma se rechaza al cierre del día. El envío no sale en el menú ni llega a la cocina.
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
-- Se siembra como postgres, con ids fijos. A recibe pedidos ahora (su horario va de 3 horas antes
-- a 3 horas después de este momento, todos los días) y hace envíos; B también recibe, sin envíos;
-- C tiene la licencia pausada; D no tiene teléfono; E no tiene horario, y F está cerrado ahora. En
-- A: Don Chuy (gerente), Pepe (mesero, en su celular), Lupita (caja, en la tableta de la caja) y
-- una caja sin aparato. El menú de A: Tacos (va a la cocina), Aguas (lo sirve el mesero) y Envíos
-- (con área de cocina, para ver que el envío no llega ahí).

-- Un pedido como lo manda el Worker: para llevar, a nombre de Rosa Ramírez, y cada vez desde un
-- celular y una conexión nuevos, salvo que se digan.
create function tests.pedir(
  p_slug text,
  p_renglones jsonb,
  p_clave uuid default gen_random_uuid(),
  p_tipo text default 'para_llevar',
  p_nombre text default 'Rosa Ramírez',
  p_telefono text default null,
  p_direccion text default null,
  p_referencias text default null,
  p_paga_con numeric default null,
  p_celular text default encode(extensions.gen_random_bytes(32), 'hex'),
  p_conexion text default encode(extensions.gen_random_bytes(32), 'hex')
)
returns jsonb
language sql
as $$
  select public.hacer_pedido(p_slug, p_clave, p_tipo, p_nombre, p_telefono, p_direccion, p_referencias,
                             p_paga_con, p_renglones, p_celular, p_conexion)
$$;

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
  e uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  f uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  v_local timestamp := now() at time zone 'America/Mexico_City';
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('caja_sin_aparato_a', 'caja.sin.aparato.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, telefono, hace_envios) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30, '2221234567', true),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, '2227654321', false),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30, '2221112222', true),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 30, hoy + 30, null, true),
    (e, 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy + 30, '2223334444', true),
    (f, 'Restaurante F', 'restaurante-f', true, hoy - 30, hoy + 30, '2225556666', true);

  -- Abiertos ahora: de 3 horas antes a 3 horas después (si pasa de medianoche, cuenta como del día
  -- en que abrió). F abre dentro de 6 horas.
  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select r, x, date_trunc('minute', v_local - interval '3 hours')::time, date_trunc('minute', v_local + interval '3 hours')::time
  from unnest(array[a, b, c, d]) as r, generate_series(1, 7) as x;
  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select f, x, date_trunc('minute', v_local + interval '6 hours')::time, date_trunc('minute', v_local + interval '7 hours')::time
  from generate_series(1, 7) as x;

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo, pin_hash) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true, null),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true, 'pin'),
    (103, a, tests.get_supabase_uid('caja_a'), 'Lupita', '{caja}', true, 'pin'),
    (104, a, tests.get_supabase_uid('caja_sin_aparato_a'), 'Caja sin aparato', '{caja}', true, null),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true, null),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true, null);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, privado.huella_aparato(repeat('P', 43)), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta caja', null, privado.huella_aparato(repeat('C', 43)), '5e5e5e5e-0000-4000-8000-000000000002');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Tacos', 'taco'), (602, a, 'Aguas', 'agua'), (603, a, 'Envíos', 'especialidad'),
    (611, b, 'Tacos B', 'taco'), (621, c, 'Tacos C', 'taco');
  update public.categorias c
  set area_preparacion_id = (select ar.id from public.areas_preparacion ar where ar.restaurante_id = c.restaurante_id)
  where c.id in (601, 603, 611, 621);
  update public.categorias set area_preparacion_id = null where id = 602;

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, imagen_ruta, nombre_en, es_envio)
  overriding system value values
    (501, a, 601, 'Taco al pastor', 22, null, null, false),
    (502, a, 601, 'Gringa', 75, null, null, false),
    (503, a, 601, 'Taco oculto', 22, null, null, false),
    (504, a, 602, 'Horchata', 30, null, null, false),
    (505, a, 603, 'Envío', 30, null, null, true),
    (506, a, 603, 'Envío lejos', 50, null, null, true),
    (507, a, 601, 'Taco viejo', 20, null, null, false),
    (508, a, 601, 'Quesadilla', 40, null, null, false),
    (509, a, 602, 'Flan', 35, 'restaurantes/' || a || '/menu/' || repeat('0', 31) || '1.webp', 'Flan', false),
    (511, b, 611, 'Taco B', 25, null, null, false),
    (521, c, 621, 'Taco C', 25, null, null, false);
  update public.productos set visible = false where id = 503;
  update public.productos set archivado_at = now() where id = 507;

  -- Salsa (obligatoria, el habanero agotado), Extras (hasta 2) y Tortilla (la única opción
  -- agotada: la quesadilla está agotada por su grupo).
  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Salsa', 1, 1), (902, a, 'Extras', 0, 2), (903, a, 'Tortilla', 1, 1);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Verde', 0, true, 1), (9012, a, 901, 'Roja', 0, true, 2), (9013, a, 901, 'Habanero', 0, false, 3),
    (9021, a, 902, 'Queso', 10, true, 1), (9022, a, 902, 'Aguacate', 12, true, 2),
    (9031, a, 903, 'Maíz', 0, false, 1);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values
    (a, 501, 901), (a, 501, 902), (a, 508, 903), (a, 509, 902);
end;
$$;

select plan(113);


-- ─── Estructura y permisos ────────────────────────────────────────────────────

select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.pedidos_en_linea'::regclass, 'public.pedido_items'::regclass)),
  'Los pedidos y sus renglones tienen RLS'
);

select ok(
  not has_column_privilege('authenticated', 'public.pedidos_en_linea', 'clave', 'SELECT')
  and not has_column_privilege('authenticated', 'public.pedidos_en_linea', 'marca_celular', 'SELECT')
  and not has_column_privilege('authenticated', 'public.pedidos_en_linea', 'marca_conexion', 'SELECT')
  and has_column_privilege('authenticated', 'public.pedidos_en_linea', 'cliente_nombre', 'SELECT')
  and has_column_privilege('authenticated', 'public.pedido_items', 'opciones', 'SELECT'),
  'Con sesión se leen los pedidos, pero nunca su clave ni sus marcas'
);

select ok(
  not has_any_column_privilege('authenticated', 'public.pedidos_en_linea', 'INSERT, UPDATE')
  and not has_any_column_privilege('authenticated', 'public.pedido_items', 'INSERT, UPDATE')
  and not has_table_privilege('authenticated', 'public.pedidos_en_linea', 'DELETE')
  and not has_table_privilege('authenticated', 'public.pedido_items', 'DELETE')
  and not has_any_column_privilege('anon', 'public.pedidos_en_linea', 'SELECT, INSERT, UPDATE')
  and not has_any_column_privilege('anon', 'public.pedido_items', 'SELECT, INSERT, UPDATE'),
  'Nadie escribe los pedidos directo, y sin sesión ni se leen'
);

select ok(
  has_function_privilege('service_role', 'public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text)', 'EXECUTE'),
  'hacer_pedido solo lo llama el Worker, con la llave secreta: ni el menú sin sesión ni alguien con sesión'
);

select is_empty(
  $$ select f from unnest(array[
       'public.pedidos_del_dia(uuid)',
       'public.confirmar_pedido(bigint, bigint)',
       'public.rechazar_pedido(bigint, text)',
       'public.pausar_pedidos(uuid, boolean)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE') $$,
  'Las 4 funciones de Pedidos las llama quien tiene sesión, y cada una revisa quién es; sin sesión no'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.pedidos_pausados(uuid, timestamptz)',
       'privado.recibe_pedidos(uuid, timestamptz)',
       'privado.pedido_en_json(bigint)',
       'privado.rechazar_sin_confirmar()',
       'privado.productos_a_la_vista(uuid)'
     ]) as f
     where has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Lo que se cuenta una sola vez no lo llama nadie de fuera'
);

select is(
  (select schedule || ' · ' || command from cron.job where jobname = 'rechazar-pedidos-sin-confirmar'),
  '0 * * * * · select privado.rechazar_sin_confirmar()',
  'pg_cron rechaza lo que nadie confirmó, cada hora en punto'
);

select ok(
  not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
  or exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos_en_linea'),
  'Los pedidos llegan por el tiempo real de Supabase'
);


-- ─── El menú que ve la clienta ────────────────────────────────────────────────

select tests.clear_authentication();

select is(
  jsonb_build_object('recibe', m -> 'recibe_pedidos', 'pausados', m -> 'pedidos_pausados',
                     'envios', m -> 'restaurante' -> 'hace_envios'),
  '{"recibe": true, "pausados": false, "envios": true}'::jsonb,
  'El menú de A dice que recibe pedidos ahora y que hace envíos'
)
from (select public.menu_publico('restaurante-a') as m) x;

select is(
  (select jsonb_agg(p -> 'id' order by p ->> 'id')
   from jsonb_array_elements(public.menu_publico('restaurante-a') -> 'categorias') c,
        jsonb_array_elements(c -> 'productos') p),
  '[501, 502, 504, 509]'::jsonb,
  'Los envíos no salen en el menú'
);

select is(
  (select jsonb_agg(c -> 'nombre') from jsonb_array_elements(public.menu_publico('restaurante-a') -> 'categorias') c),
  '["Tacos", "Aguas"]'::jsonb,
  'Ni la categoría que solo tiene envíos'
);

select is(
  array[(public.menu_publico('restaurante-b') ->> 'recibe_pedidos')::boolean,
        (public.menu_publico('restaurante-d') ->> 'recibe_pedidos')::boolean,
        (public.menu_publico('restaurante-e') ->> 'recibe_pedidos')::boolean,
        (public.menu_publico('restaurante-f') ->> 'recibe_pedidos')::boolean],
  array[true, false, false, false],
  'B recibe pedidos; sin teléfono (D), sin horario (E) o fuera de su horario (F), el menú no recibe'
);

select is(
  (public.menu_publico('restaurante-b') -> 'restaurante' ->> 'hace_envios')::boolean,
  false,
  'B no hace envíos'
);

select tests.authenticate_as('gerente_a');

select is(
  public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'estado',
  '{"a_la_vista": 4, "productos": 6}'::jsonb,
  '«4 de 6 productos a la vista» no cuenta los envíos en ninguno de los dos números'
);


-- ─── «Hacer pedido» ───────────────────────────────────────────────────────────

select tests.como_worker();

select is(
  tests.pedir('restaurante-a',
    '[{"producto_id": 501, "cantidad": 2, "opciones": [9021, 9011], "nota": "  Sin cebolla ", "precio": 32},
      {"producto_id": 504, "cantidad": 1, "precio": 30}]',
    p_clave => '0000000a-0000-4000-8000-000000000001', p_telefono => '222 123 4567', p_direccion => 'No va')
    - 'created_at',
  '{"ok": true, "numero": 1, "tipo": "para_llevar", "cliente_nombre": "Rosa Ramírez", "cliente_telefono": null,
    "cliente_direccion": null, "cliente_referencias": null, "paga_con": null, "total": 94, "renglones": [
      {"nombre": "Taco al pastor", "cantidad": 2, "precio_unitario": 32, "importe": 64, "nota": "Sin cebolla",
       "opciones": [{"grupo": "Salsa", "opcion": "Verde", "precio_extra": 0}, {"grupo": "Extras", "opcion": "Queso", "precio_extra": 10}]},
      {"nombre": "Horchata", "cantidad": 1, "precio_unitario": 30, "importe": 30, "nota": null, "opciones": []}]}'::jsonb,
  'Para llevar: Postgres pone los precios, el total y el #1; no guarda teléfono ni dirección'
);

reset role;

select tests.guardar('pedido_1', (select id from public.pedidos_en_linea where clave = '0000000a-0000-4000-8000-000000000001'));

select is(
  (select jsonb_build_object('estado', estado, 'hoy', dia = privado.dia_de_negocio('America/Mexico_City', 6::smallint),
                             'atendido_at', atendido_at, 'total', total)
   from public.pedidos_en_linea where id = tests.id('pedido_1')),
  '{"estado": "por_confirmar", "hoy": true, "atendido_at": null, "total": 94}'::jsonb,
  'Queda «Por confirmar», en el día de negocio de hoy'
);

select tests.como_worker();

select is(
  (tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]',
               p_clave => '0000000a-0000-4000-8000-000000000001') ->> 'numero')::int,
  1,
  'La misma clave otra vez (doble toque) regresa el mismo #1'
);

reset role;

select is(
  (select count(*)::int from public.pedidos_en_linea where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1,
  'Y no guarda otro'
);

select tests.como_worker();

select is(
  (tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]',
               p_clave => '0000000a-0000-4000-8000-000000000002') ->> 'numero')::int,
  2,
  'El siguiente es el #2'
);

select is(
  (tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 2, "precio": 25}]') ->> 'numero')::int,
  1,
  'Cada restaurante lleva sus números: el primero de B es el #1'
);

select is(
  tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 2, "nota": "Sin crema", "precio": 75}]',
    p_clave => '0000000a-0000-4000-8000-000000000003', p_tipo => 'domicilio', p_telefono => '(222) 123-4567',
    p_direccion => ' Av. Juárez 140 ', p_referencias => 'Portón verde', p_paga_con => 500)
    - 'created_at' - 'renglones',
  '{"ok": true, "numero": 3, "tipo": "domicilio", "cliente_nombre": "Rosa Ramírez", "cliente_telefono": "2221234567",
    "cliente_direccion": "Av. Juárez 140", "cliente_referencias": "Portón verde", "paga_con": 500, "total": 150}'::jsonb,
  'A domicilio: el teléfono queda en sus 10 dígitos, con la dirección, las referencias y con cuánto paga'
);

select throws_ok(
  $$ select tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]',
       p_tipo => 'domicilio', p_telefono => '2221234567', p_direccion => 'Av. Juárez 140') $$,
  '22023', 'Por ahora no hacemos envíos. Puedes pedir para llevar.',
  'Sin «Hago envíos» no se pide a domicilio'
);

select is(
  tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 70}, {"producto_id": 504, "cantidad": 2, "precio": 30}]'),
  '{"ok": false, "motivo": "cambios", "cambios": [{"renglon": 1, "cambio": "precio", "precio": 75}], "total": 135}'::jsonb,
  'Si cambió un precio no se guarda nada: dice el precio nuevo y el total nuevo'
);

select is(
  tests.pedir('restaurante-a', '[
     {"producto_id": 503, "cantidad": 1, "precio": 22},
     {"producto_id": 505, "cantidad": 1, "precio": 30},
     {"producto_id": 507, "cantidad": 1, "precio": 20},
     {"producto_id": 508, "cantidad": 1, "opciones": [9031], "precio": 40},
     {"producto_id": 501, "cantidad": 1, "opciones": [9013], "precio": 22},
     {"producto_id": 501, "cantidad": 1, "opciones": [9011, 9031], "precio": 22},
     {"producto_id": 501, "cantidad": 1, "opciones": [], "precio": 22},
     {"producto_id": 501, "cantidad": 1, "opciones": [9011, 9012], "precio": 22},
     {"producto_id": 511, "cantidad": 1, "precio": 25},
     {"producto_id": 504, "cantidad": 1, "precio": 30}]'),
  '{"ok": false, "motivo": "cambios", "total": 30, "cambios": [
     {"renglon": 1, "cambio": "agotado"}, {"renglon": 2, "cambio": "agotado"}, {"renglon": 3, "cambio": "agotado"},
     {"renglon": 4, "cambio": "agotado"}, {"renglon": 5, "cambio": "agotado", "opcion": "Habanero"},
     {"renglon": 6, "cambio": "opciones"}, {"renglon": 7, "cambio": "opciones"}, {"renglon": 8, "cambio": "opciones"},
     {"renglon": 9, "cambio": "agotado"}]}'::jsonb,
  'Lo oculto, un envío, lo archivado, lo agotado por su grupo, una opción agotada, una de otro producto, sin salsa, dos salsas y un producto de otro restaurante: no se guarda nada'
);

reset role;

select is(
  (select count(*)::int from public.pedidos_en_linea where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  3,
  'Con cambios no se guardó nada: A sigue con 3 pedidos'
);

select tests.como_worker();

select is(
  array[tests.pedir('restaurante-c', r) ->> 'motivo', tests.pedir('restaurante-d', r) ->> 'motivo',
        tests.pedir('restaurante-e', r) ->> 'motivo', tests.pedir('restaurante-f', r) ->> 'motivo',
        tests.pedir('no-existe', r) ->> 'motivo'],
  array['no_recibe', 'no_recibe', 'no_recibe', 'no_recibe', 'no_recibe'],
  'Con la licencia pausada, sin teléfono, sin horario, fuera del horario o con un slug que no existe: no se guarda nada'
)
from (select '[{"producto_id": 521, "cantidad": 1, "precio": 25}]'::jsonb as r) x;

-- Los límites, en B: 3 por hora desde un celular y 10 desde una conexión.
do $$
begin
  perform tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]', p_celular => repeat('c', 64))
  from generate_series(1, 3);
end;
$$;

select throws_ok(
  $$ select tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]', p_celular => repeat('c', 64)) $$,
  '22023', 'Ya mandaste 3 pedidos en la última hora. Si quieres algo más, escríbele al restaurante por WhatsApp.',
  'Un celular manda hasta 3 pedidos por hora a un restaurante'
);

select is(
  (tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_celular => repeat('c', 64),
               p_clave => '0000000a-0000-4000-8000-000000000004') ->> 'numero')::int,
  4,
  'El mismo celular todavía le puede pedir a otro restaurante'
);

reset role;
update public.pedidos_en_linea set created_at = now() - interval '61 minutes'
where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and marca_celular = repeat('c', 64);
select tests.como_worker();

select is(
  (tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]', p_celular => repeat('c', 64)) ->> 'ok')::boolean,
  true,
  'Los de hace más de una hora ya no cuentan'
);

reset role;
insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, total, clave, marca_celular, marca_conexion)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', privado.dia_de_negocio('America/Mexico_City', 6::smallint), 100 + x,
       'para_llevar', 'Oficina', 25, gen_random_uuid(), encode(extensions.gen_random_bytes(32), 'hex'), repeat('d', 64)
from generate_series(1, 10) as x;
select tests.como_worker();

select throws_ok(
  $$ select tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]', p_conexion => repeat('d', 64)) $$,
  '22023', 'Desde esta conexión ya se mandaron 10 pedidos en la última hora. Si quieres algo más, escríbele al restaurante por WhatsApp.',
  'Una conexión manda hasta 10 pedidos por hora a un restaurante'
);

select is(
  (tests.pedir('restaurante-a', '[{"producto_id": 504, "cantidad": 1, "precio": 30}]',
               p_clave => '0000000a-0000-4000-8000-000000000005', p_tipo => 'domicilio',
               p_telefono => '2225550000', p_direccion => 'Calle 5') ->> 'numero')::int,
  5,
  'A domicilio, sin referencias ni con cuánto paga, también se puede'
);

-- Lo que no se puede pedir así.
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_tipo => 'mesa') $$,
  '22023', 'Elige para llevar o a domicilio', 'Para comer ahí no se pide por el menú'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_nombre => '   ') $$,
  '22023', 'Escribe tu nombre y apellido', 'Sin nombre no hay pedido'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_nombre => repeat('a', 61)) $$,
  '22023', 'Tu nombre puede tener hasta 60 letras', 'El nombre llega hasta 60 letras'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_tipo => 'domicilio',
       p_telefono => '+52 222 123 4567', p_direccion => 'Av. Juárez 140') $$,
  '22023', 'Tu teléfono lleva 10 dígitos, como 222 123 4567.', 'A domicilio, el teléfono lleva 10 dígitos'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_tipo => 'domicilio',
       p_telefono => '2221234567', p_direccion => '  ') $$,
  '22023', 'Escribe la dirección para el envío', 'A domicilio, sin dirección no hay pedido'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_tipo => 'domicilio',
       p_telefono => '2221234567', p_direccion => repeat('a', 201)) $$,
  '22023', 'La dirección puede tener hasta 200 letras', 'La dirección llega hasta 200 letras'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]', p_tipo => 'domicilio',
       p_telefono => '2221234567', p_direccion => 'Av. Juárez 140', p_referencias => repeat('a', 121)) $$,
  '22023', 'Las referencias pueden tener hasta 120 letras', 'Las referencias llegan hasta 120 letras'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 2, "precio": 75}]', p_tipo => 'domicilio',
       p_telefono => '2221234567', p_direccion => 'Av. Juárez 140', p_paga_con => 100) $$,
  '22023', 'Con $100.00 no alcanza: tu pedido es de $150.00', 'Con cuánto paga no puede ser menos que el total'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[]') $$,
  '22023', 'Tu pedido está vacío', 'Un pedido vacío no se guarda'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', (select jsonb_agg('{"producto_id": 504, "cantidad": 1, "precio": 30}'::jsonb)
                                         from generate_series(1, 31))) $$,
  '22023', 'Un pedido lleva hasta 30 renglones', 'Hasta 30 renglones'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 504, "cantidad": 100, "precio": 30}]') $$,
  '22023', 'Pide de 1 a 99 de cada producto', 'Hasta 99 de cada producto'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 504, "cantidad": 0, "precio": 30}]') $$,
  '22023', 'Pide de 1 a 99 de cada producto', 'Y al menos 1'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', jsonb_build_array(jsonb_build_object('producto_id', 504, 'cantidad', 1, 'precio', 30, 'nota', repeat('a', 141)))) $$,
  '22023', 'Cada nota puede tener hasta 140 letras', 'Cada nota llega hasta 140 letras'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 504, "cantidad": 1}]') $$,
  '22023', 'Falta el precio de un renglón', 'Cada renglón trae el precio que vio, para compararlo'
);
select throws_ok(
  $$ select tests.pedir('restaurante-a', '[{"producto_id": 504, "cantidad": 1, "precio": 30}]', p_conexion => '187.190.1.1') $$,
  '22023', 'Faltan las marcas del pedido', 'La conexión nunca se guarda: solo su marca'
);

-- El número corto vuelve a 1 cada día de negocio.
reset role;
update public.pedidos_en_linea set dia = dia - 1 where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
update public.folios set pedidos_dia = pedidos_dia - 1 where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
select tests.como_worker();

select is(
  (tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]') ->> 'numero')::int,
  1,
  'Al día de negocio siguiente, el primer pedido es otra vez el #1'
);

reset role;
update public.folios set pedidos_dia = pedidos_dia + 1 where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
select tests.como_worker();

select is(
  (tests.pedir('restaurante-b', '[{"producto_id": 511, "cantidad": 1, "precio": 25}]') ->> 'numero')::int,
  2,
  'Un día que vuelve (si cambió la hora de corte) sigue después de su último número'
);


-- ─── «Pausar pedidos» ─────────────────────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select lives_ok(
  $$ select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  'Lupita, en la tableta de la caja, pausa los pedidos'
);

select tests.clear_authentication();

select is(
  jsonb_build_array(m -> 'recibe_pedidos', m -> 'pedidos_pausados'),
  '[false, true]'::jsonb,
  'Con la pausa, el menú no recibe pedidos y dice que es por la pausa'
)
from (select public.menu_publico('restaurante-a') as m) x;

select tests.como_worker();

select is(
  tests.pedir('restaurante-a', '[{"producto_id": 502, "cantidad": 1, "precio": 75}]'),
  '{"ok": false, "motivo": "no_recibe"}'::jsonb,
  'Y «Hacer pedido» no guarda nada'
);

reset role;
update public.restaurantes set pedidos_pausados_at = now() - interval '1 minute'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
reset role;

select is(
  (select pedidos_pausados_at from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  now() - interval '1 minute',
  'Pausar otra vez el mismo día conserva desde cuándo'
);

update public.restaurantes
set pedidos_pausados_at = privado.inicio_dia_de_negocio('America/Mexico_City', 6::smallint) - interval '1 minute'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.clear_authentication();

select is(
  (public.menu_publico('restaurante-a') ->> 'recibe_pedidos')::boolean,
  true,
  'Una pausa de ayer ya no cuenta: al empezar el día de negocio se quita sola'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false);
reset role;

select is(
  (select pedidos_pausados_at from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  null::timestamptz,
  '«Reanudar» quita la pausa'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  '42501', 'Solo la caja y el gerente de este restaurante pausan sus pedidos',
  'Pepe, mesero, no pausa los pedidos'
);

select tests.authenticate_as('caja_sin_aparato_a');
select throws_ok(
  $$ select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  '42501', 'Solo la caja y el gerente de este restaurante pausan sus pedidos',
  'La caja, fuera de su aparato, tampoco'
);

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.pausar_pedidos('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  '42501', 'Solo la caja y el gerente de este restaurante pausan sus pedidos',
  'Ni el gerente de B'
);


-- ─── Quién lee los pedidos ────────────────────────────────────────────────────

reset role;
select tests.guardar('pedidos_a', (select count(*) from public.pedidos_en_linea where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
select tests.guardar('renglones_a', (select count(*) from public.pedido_items where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, total, clave, marca_celular, marca_conexion)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', privado.dia_de_negocio('America/Mexico_City', 6::smallint), 1,
        'para_llevar', 'En C', 25, gen_random_uuid(), repeat('e', 64), repeat('e', 64));

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select is(
  array[(select count(*) from public.pedidos_en_linea), (select count(*) from public.pedido_items)],
  array[tests.id('pedidos_a'), tests.id('renglones_a')],
  'Lupita, en su tableta, lee los pedidos de A y sus renglones, y nada de B ni de C'
);

select tests.authenticate_as('gerente_a');

select is(
  (select count(*) from public.pedidos_en_linea),
  tests.id('pedidos_a'),
  'Don Chuy también los lee'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  (select count(*)::int from public.pedidos_en_linea) + (select count(*)::int from public.pedido_items),
  0,
  'Pepe, mesero, no ve los pedidos: no cuentan hasta confirmarse'
);

select tests.authenticate_as('caja_sin_aparato_a');

select is(
  (select count(*)::int from public.pedidos_en_linea),
  0,
  'La caja, fuera de su aparato, tampoco'
);

select tests.authenticate_as('gerente_c');

select is(
  (select count(*)::int from public.pedidos_en_linea),
  0,
  'Con la licencia pausada, Gerente C no lee los de C'
);


-- ─── La lista de Pedidos ──────────────────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select is(
  jsonb_path_query_array(public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.por_confirmar[*].numero'),
  '[1, 2, 3, 4, 5]'::jsonb,
  'Lupita ve los «Por confirmar» de hoy, del más viejo al más nuevo'
);

select is(
  (public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'por_confirmar' -> 2) - 'id' - 'created_at',
  '{"numero": 3, "tipo": "domicilio", "cliente_nombre": "Rosa Ramírez", "cliente_telefono": "2221234567",
    "cliente_direccion": "Av. Juárez 140", "cliente_referencias": "Portón verde", "paga_con": 500, "total": 150,
    "renglones": [{"nombre": "Gringa", "cantidad": 2, "precio_unitario": 75, "importe": 150, "nota": "Sin crema", "opciones": []}]}'::jsonb,
  'Cada uno completo: a domicilio, con su dirección, sus referencias, con cuánto paga y sus renglones'
);

select is(
  jsonb_build_object('pausado', p -> 'pausado', 'pausado_at', p -> 'pausado_at', 'recibe', p -> 'recibe',
                     'abierto', p -> 'estado' -> 'abierto', 'atendidos', p -> 'atendidos',
                     'ahora', (p ->> 'ahora')::timestamptz = now()),
  '{"pausado": false, "pausado_at": null, "recibe": true, "abierto": true, "atendidos": [], "ahora": true}'::jsonb,
  'Dice si está en pausa, si recibe pedidos y si está abierto, y la hora de Postgres; todavía no hay atendidos'
)
from (select public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as p) x;

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo la caja y el gerente de este restaurante ven sus pedidos',
  'Pepe no ve la lista de Pedidos'
);

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo la caja y el gerente de este restaurante ven sus pedidos',
  'Ni el gerente de B'
);


-- ─── «Confirmar» ──────────────────────────────────────────────────────────────
-- Antes, la horchata sube a $35 y la gringa se agota.

reset role;
update public.productos set precio = 35 where id = 504;
update public.productos set visible = false where id = 502;
select tests.guardar('pedido_2', (select id from public.pedidos_en_linea where clave = '0000000a-0000-4000-8000-000000000002'));
select tests.guardar('pedido_3', (select id from public.pedidos_en_linea where clave = '0000000a-0000-4000-8000-000000000003'));
select tests.guardar('pedido_4', (select id from public.pedidos_en_linea where clave = '0000000a-0000-4000-8000-000000000004'));
select tests.guardar('pedido_5', (select id from public.pedidos_en_linea where clave = '0000000a-0000-4000-8000-000000000005'));

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  format('select public.confirmar_pedido(%s)', tests.id('pedido_1')),
  '42501', 'Solo la caja y el gerente de este restaurante confirman sus pedidos',
  'Pepe, mesero, no confirma pedidos'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select tests.guardar('venta_1', public.confirmar_pedido(tests.id('pedido_1')));
reset role;

select is(
  (select jsonb_build_object('origen', origen, 'tipo', tipo, 'cliente_nombre', cliente_nombre, 'telefono', cliente_telefono,
                             'direccion', cliente_direccion, 'pedido_numero', pedido_numero, 'abierta_por', abierta_por,
                             'total', total, 'estado', estado)
   from public.ventas where id = tests.id('venta_1')),
  '{"origen": "menu_en_linea", "tipo": "para_llevar", "cliente_nombre": "Rosa Ramírez", "telefono": null, "direccion": null,
    "pedido_numero": 1, "abierta_por": 103, "total": 94, "estado": "abierta"}'::jsonb,
  '«Confirmar» abre una cuenta para llevar a nombre de Lupita, con el #1 y los precios del pedido, aunque la horchata ya cueste $35'
);

select results_eq(
  format($$ select nombre, precio_unitario, cantidad, opciones, nota, agregado_por, clave_envio, comanda_id is not null
            from public.venta_items where venta_id = %s order by id $$, tests.id('venta_1')),
  $$ values ('Taco al pastor'::text, 32.00::numeric, 2,
             '[{"grupo": "Salsa", "opcion": "Verde", "precio_extra": 0}, {"grupo": "Extras", "opcion": "Queso", "precio_extra": 10}]'::jsonb,
             'Sin cebolla'::text, 103::bigint, '0000000a-0000-4000-8000-000000000001'::uuid, true),
            ('Horchata', 30.00, 1, '[]'::jsonb, null, 103, '0000000a-0000-4000-8000-000000000001', false) $$,
  'Los renglones van como llegaron, a nombre de Lupita: los tacos a la cocina y la horchata, que sirve el mesero, sin comanda'
);

select is(
  (select jsonb_agg(jsonb_build_object('area', ar.nombre, 'enviada_por', c.enviada_por))
   from public.comandas c
   join public.areas_preparacion ar on ar.restaurante_id = c.restaurante_id and ar.id = c.area_preparacion_id
   where c.venta_id = tests.id('venta_1')),
  '[{"area": "Cocina", "enviada_por": 103}]'::jsonb,
  'Va a cocina en ese momento: una comanda, enviada por Lupita'
);

select is(
  (select jsonb_build_object('estado', estado, 'su_cuenta', venta_id = tests.id('venta_1'), 'atendido_por', atendido_por,
                             'atendido', atendido_at is not null)
   from public.pedidos_en_linea where id = tests.id('pedido_1')),
  '{"estado": "confirmado", "su_cuenta": true, "atendido_por": 103, "atendido": true}'::jsonb,
  'El pedido queda confirmado, ligado a su cuenta, con quién y cuándo'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select is(
  public.confirmar_pedido(tests.id('pedido_1')),
  tests.id('venta_1'),
  'Confirmarlo otra vez (doble toque) regresa la misma cuenta'
);

reset role;

select is(
  (select count(*)::int from public.ventas
   where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and pedido_numero = 1),
  1,
  'Y no abre otra'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select tests.guardar('venta_2', public.confirmar_pedido(tests.id('pedido_2')));
reset role;

select is(
  (select total from public.ventas where id = tests.id('venta_2')),
  75.00,
  'Lo agotado no frena la confirmación: la gringa entra, y se cancela ya como cuenta'
);

select tests.authenticate_as('gerente_a');
select tests.guardar('venta_3', public.confirmar_pedido(tests.id('pedido_3'), 506));
reset role;

select is(
  (select jsonb_build_object('tipo', tipo, 'telefono', cliente_telefono, 'direccion', cliente_direccion, 'total', total,
                             'abierta_por', abierta_por, 'pedido_numero', pedido_numero)
   from public.ventas where id = tests.id('venta_3')),
  '{"tipo": "domicilio", "telefono": "2221234567", "direccion": "Av. Juárez 140 · Portón verde", "total": 200,
    "abierta_por": 101, "pedido_numero": 3}'::jsonb,
  'Don Chuy confirma el #3 a domicilio con «Envío lejos»: la dirección lleva las referencias, y el total, el envío'
);

select results_eq(
  format($$ select nombre, precio_unitario, comanda_id is null from public.venta_items where venta_id = %s order by id $$,
         tests.id('venta_3')),
  $$ values ('Gringa'::text, 75.00::numeric, false), ('Envío lejos', 50.00, true) $$,
  'El envío entra a la misma cuenta sin comanda, aunque su categoría tenga área'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  format('select public.confirmar_pedido(%s, 505)', tests.id('pedido_4')),
  '22023', 'Solo un pedido a domicilio lleva envío',
  'Un pedido para llevar no lleva envío'
);

select throws_ok(
  format('select public.confirmar_pedido(%s, 502)', tests.id('pedido_5')),
  '23503', 'Ese envío ya no está en tu menú',
  'Como envío solo va un producto de envío'
);

reset role;
update public.productos set archivado_at = now() where id = 505;
select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  format('select public.confirmar_pedido(%s, 505)', tests.id('pedido_5')),
  '23503', 'Ese envío ya no está en tu menú',
  'Ni uno archivado'
);

select tests.guardar('venta_5', public.confirmar_pedido(tests.id('pedido_5')));
reset role;

select is(
  (select jsonb_build_object('total', v.total, 'renglones', (select count(*) from public.venta_items i where i.venta_id = v.id),
                             'direccion', v.cliente_direccion)
   from public.ventas v where v.id = tests.id('venta_5')),
  '{"total": 30, "renglones": 1, "direccion": "Calle 5"}'::jsonb,
  '«Sin envío»: la cuenta lleva solo lo pedido, y sin referencias la dirección va sola'
);

-- Un pedido de ayer que se quedó «Por confirmar» (pg_cron todavía no pasa).
insert into public.pedidos_en_linea (id, restaurante_id, dia, numero, tipo, cliente_nombre, total, clave, marca_celular, marca_conexion)
overriding system value
values (9901, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', privado.dia_de_negocio('America/Mexico_City', 6::smallint) - 1, 1,
        'para_llevar', 'Ayer', 30, gen_random_uuid(), repeat('e', 64), repeat('e', 64));
insert into public.pedido_items (restaurante_id, pedido_id, producto_id, nombre, precio_unitario, cantidad)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 9901, 504, 'Horchata', 30, 1);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select is(
  public.confirmar_pedido(9901),
  null::bigint,
  'Un pedido de un día de negocio que ya terminó ya no se confirma: regresa vacío'
);

reset role;

select is(
  (select jsonb_build_object('estado', estado, 'motivo', rechazo_motivo, 'quien', atendido_por, 'atendido', atendido_at is not null)
   from public.pedidos_en_linea where id = 9901),
  '{"estado": "rechazado", "motivo": "No se confirmó", "quien": null, "atendido": true}'::jsonb,
  'Y queda rechazado ahí mismo con «No se confirmó», sin quién, aunque pg_cron no haya pasado'
);

select tests.authenticate_as('gerente_b');
select throws_ok(
  format('select public.confirmar_pedido(%s)', tests.id('pedido_4')),
  '42501', 'Solo la caja y el gerente de este restaurante confirman sus pedidos',
  'El gerente de B no confirma pedidos de A'
);

select tests.authenticate_as('caja_sin_aparato_a');
select throws_ok(
  format('select public.confirmar_pedido(%s)', tests.id('pedido_4')),
  '42501', 'Solo la caja y el gerente de este restaurante confirman sus pedidos',
  'Ni la caja fuera de su aparato'
);


-- ─── «Rechazar» ───────────────────────────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select lives_ok(
  format($$ select public.rechazar_pedido(%s, '  Pedido falso  ') $$, tests.id('pedido_4')),
  'Lupita rechaza el #4 con su motivo'
);

reset role;

select is(
  (select jsonb_build_object('estado', estado, 'motivo', rechazo_motivo, 'quien', atendido_por, 'venta', venta_id)
   from public.pedidos_en_linea where id = tests.id('pedido_4')),
  '{"estado": "rechazado", "motivo": "Pedido falso", "quien": 103, "venta": null}'::jsonb,
  'El rechazo se queda en el pedido, con quién y su motivo'
);

select is(
  (select count(*)::int from public.bitacora where tabla = 'pedidos_en_linea'),
  0,
  'Y no va a la bitácora: no toca dinero'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  format($$ select public.rechazar_pedido(%s, '   ') $$, tests.id('pedido_4')),
  '22023', 'Escribe el motivo del rechazo', 'Rechazar pide un motivo'
);

select throws_ok(
  format($$ select public.rechazar_pedido(%s, '%s') $$, tests.id('pedido_4'), repeat('a', 141)),
  '22023', 'El motivo puede tener hasta 140 letras', 'El motivo llega hasta 140 letras'
);

select public.rechazar_pedido(tests.id('pedido_4'), 'Otro motivo');
reset role;

select is(
  (select rechazo_motivo from public.pedidos_en_linea where id = tests.id('pedido_4')),
  'Pedido falso',
  'Rechazar otra vez uno ya rechazado no cambia nada'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  format($$ select public.rechazar_pedido(%s, 'Ya cerramos') $$, tests.id('pedido_1')),
  '55000', 'El #1 ya se confirmó: cancélalo ya como cuenta',
  'Uno confirmado ya no se rechaza: se cancela como cuenta'
);

select throws_ok(
  format('select public.confirmar_pedido(%s)', tests.id('pedido_4')),
  '55000', 'El #4 ya se rechazó',
  'Y uno rechazado ya no se confirma'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  format($$ select public.rechazar_pedido(%s, 'Pedido falso') $$, tests.id('pedido_5')),
  '42501', 'Solo la caja y el gerente de este restaurante rechazan sus pedidos',
  'Pepe, mesero, no rechaza pedidos'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select is(
  jsonb_build_object(
    'por_confirmar', p -> 'por_confirmar',
    'atendidos', jsonb_path_query_array(p, '$.atendidos[*].numero'),
    'el_4', (p -> 'atendidos' -> 1) - 'id' - 'atendido_at',
    'el_3', (p -> 'atendidos' -> 2) - 'id' - 'atendido_at' - 'venta_id'),
  '{"por_confirmar": [], "atendidos": [5, 4, 3, 2, 1],
    "el_4": {"numero": 4, "tipo": "para_llevar", "cliente_nombre": "Rosa Ramírez", "total": 75, "estado": "rechazado",
             "venta_id": null, "atendido_por": "Lupita", "rechazo_motivo": "Pedido falso"},
    "el_3": {"numero": 3, "tipo": "domicilio", "cliente_nombre": "Rosa Ramírez", "total": 150, "estado": "confirmado",
             "atendido_por": "Don Chuy", "rechazo_motivo": null}}'::jsonb,
  '«Atendidos hoy», del más reciente al más viejo, con quién y el motivo; el de ayer no sale'
)
from (select public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as p) x;


-- ─── El cierre del día ────────────────────────────────────────────────────────

select tests.como_worker();
select tests.guardar('pedido_6', (tests.pedir('restaurante-a', '[{"producto_id": 501, "cantidad": 1, "opciones": [9012], "precio": 22}]',
                                              p_clave => '0000000a-0000-4000-8000-000000000006') ->> 'numero')::bigint);
reset role;
select tests.guardar('ayer_b', (select count(*) from public.pedidos_en_linea
                                where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and estado = 'por_confirmar'
                                  and dia < privado.dia_de_negocio('America/Mexico_City', 6::smallint)));

select is(
  privado.rechazar_sin_confirmar()::bigint,
  tests.id('ayer_b'),
  'El cierre del día rechaza lo que se quedó «Por confirmar» de un día que ya terminó'
);

select is(
  (select jsonb_build_object('quedan', count(*) filter (where estado = 'por_confirmar' and dia < privado.dia_de_negocio('America/Mexico_City', 6::smallint)),
                             'sin_quien', bool_and(atendido_por is null) filter (where rechazo_motivo = 'No se confirmó'))
   from public.pedidos_en_linea),
  '{"quedan": 0, "sin_quien": true}'::jsonb,
  'Con «No se confirmó» y sin quién'
);

select is(
  (select estado from public.pedidos_en_linea where clave = '0000000a-0000-4000-8000-000000000006'),
  'por_confirmar',
  'El de hoy sigue esperando'
);

select is(
  (select count(*)::int from public.pedidos_en_linea where estado = 'confirmado'),
  4,
  'Y los confirmados no cambian'
);


-- ─── «¿Quién eres?» también suena ─────────────────────────────────────────────

select tests.como_worker();

select is(
  public.nombres_del_aparato(repeat('C', 43)) -> 'pedidos_por_confirmar',
  '1'::jsonb,
  'La tableta de la caja sabe cuántos pedidos esperan, aunque nadie haya entrado'
);

select is(
  public.nombres_del_aparato(repeat('P', 43)) -> 'pedidos_por_confirmar',
  'null'::jsonb,
  'En el celular de Pepe, mesero, no'
);


-- ─── El envío en el punto de venta ────────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select tests.guardar('venta_pos', public.mandar_a_cocina(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
  '[{"producto_id": 501, "cantidad": 1, "opciones": [9012]}, {"producto_id": 506, "cantidad": 1}]',
  p_tipo => 'domicilio', p_cliente_nombre => 'Sr. López', p_cliente_telefono => '2229876543',
  p_cliente_direccion => 'Reforma 10'));
reset role;

select results_eq(
  format($$ select nombre, comanda_id is null from public.venta_items where venta_id = %s order by id $$, tests.id('venta_pos')),
  $$ values ('Taco al pastor'::text, false), ('Envío lejos', true) $$,
  'En el punto de venta, el envío también entra sin comanda'
);

select throws_ok(
  format('update public.ventas set pedido_numero = 9 where id = %s', tests.id('venta_pos')),
  '23514', null,
  'Una cuenta del punto de venta no lleva número de pedido'
);


-- ─── Mi menú: «Es un costo de envío» ──────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select tests.guardar('envio_cerca', public.guardar_producto(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 603, 'Envío cerca', null, 20, null, '{}', p_es_envio => true));
reset role;

select is(
  (select es_envio from public.productos where id = tests.id('envio_cerca')),
  true,
  'Don Chuy crea un envío con «Es un costo de envío»'
);

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 603, 'Envío con salsa', null, 20, null,
       '{901}', p_es_envio => true) $$,
  '22023', 'Un envío no lleva opciones',
  'Un envío no lleva opciones'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 603, 'Envío con foto', null, 20,
       'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('0', 31) || '2.webp', '{}', p_es_envio => true) $$,
  '22023', 'Un envío no lleva foto ni su parte en inglés',
  'Ni foto'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 603, 'Envío', null, 20, null, '{}',
       'Delivery', null, true) $$,
  '22023', 'Un envío no lleva foto ni su parte en inglés',
  'Ni su parte en inglés'
);

select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 509, 602, 'Flan', null, 35, null, '{}',
                               p_es_envio => true);
reset role;

select is(
  (select jsonb_build_object('es_envio', p.es_envio, 'foto', p.imagen_ruta, 'nombre_en', p.nombre_en,
                             'grupos', (select count(*) from public.producto_grupos g where g.producto_id = p.id))
   from public.productos p where p.id = 509),
  '{"es_envio": true, "foto": null, "nombre_en": null, "grupos": 0}'::jsonb,
  'Volver envío un producto le quita la foto, el inglés y sus grupos'
);

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 902, 'Extras', 0, 2,
       '[{"id": 9021, "nombre": "Queso", "precio_extra": 10}, {"id": 9022, "nombre": "Aguacate", "precio_extra": 12}]',
       '{501, 506}') $$,
  '22023', '«Envío lejos» es un envío: un envío no lleva opciones',
  'Un grupo no se le pone a un envío'
);

select throws_ok(
  $$ update public.productos
     set imagen_ruta = 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('0', 31) || '3.webp'
     where id = 506 $$,
  '23514', null,
  'Ni se le pone foto directo: lo cuida la tabla'
);

select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('envio_cerca'), 603, 'Envío cerca', null, 20,
                               null, '{}');
reset role;

select is(
  (select es_envio from public.productos where id = tests.id('envio_cerca')),
  false,
  'Guardar sin «Es un costo de envío» lo apaga'
);


-- ─── Tu menú en línea: «Hago envíos» ──────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'oscuro', '#B3261E', 18.50, false);
reset role;

select is(
  (select hace_envios from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  false,
  '«Hago envíos» se apaga con el «Guardar» de Cómo se ve'
);

select tests.authenticate_as('gerente_a');
select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'oscuro', '#B3261E', 18.50, true);
select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'claro', null, null);
reset role;

select is(
  (select jsonb_build_object('envios', hace_envios, 'tema', menu_tema)
   from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"envios": true, "tema": "claro"}'::jsonb,
  'Sin decir nada de «Hago envíos», guardar lo deja como estaba (prendido)'
);

select * from finish();
rollback;
