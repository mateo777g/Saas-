-- Pruebas de la migración cifras_graficas (rediseño del panel, 5 de noviembre de 2026): lo que
-- cifras_de_inicio da de más para las gráficas de Inicio, las horas de hoy y de ayer y las piezas por día
-- del producto más vendido.
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

-- El worker y la huella del secreto de un aparato, como en las pruebas de empleados.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

create function tests.huella(p_token text)
returns text
language sql
as $$
  select encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Como en producción, la sesión corre en UTC: así una hora sin zona se notaría.
set local time zone 'UTC';


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- A corta tres horas antes de la hora actual, para que su día de negocio siempre lleve 4 horas en punto
-- (h0, h1, h2 y h3, la actual), corran cuando corran las pruebas.
--   Hoy cerradas: V1 $100 (4 tacos y una langosta de $90, que deja más que todos los tacos; cerrada a
--   h0 + 30 min; lleva 3 tacos cancelados), V2 $50 (2 aguas; a h0 + 90 min), V3 $25 (1 taco; a h2 en punto),
--   V4 $10 (1 salsa; a h3 en punto) y V5 $7 (1 salsa; ahora): $192. Abierta V6 $900 (9 refrescos; reabierta,
--   con la hora en que se había cerrado) y cancelada V7 $300 (con hora de cierre, para que solo la excluya
--   su estado).
--   Ayer cerradas: Y1 $40 (2 tacos; a h0 + 30 min de ayer), Y2 $60 (a h2 en punto de ayer), Y4 $5 (entre
--   h3 y esta hora de ayer) y Y3 $30 (después de esta hora de ayer); cancelada Y6 $80. Y5 $9 se abrió
--   ayer y se cerró hoy, Z1 $77 se abrió antier y se cerró ayer. Las dos no cuentan en ninguna hora.
--   B: una cuenta cerrada hoy de $500, de otro restaurante. C: sin ventas.

create table tests.anclas (nombre text primary key, dia date, momento timestamptz);
grant select on tests.anclas to anon, authenticated, service_role;

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  zona text := 'America/Mexico_City';
  h3_local timestamp := date_trunc('hour', now() at time zone 'America/Mexico_City');
  h0_local timestamp := h3_local - interval '3 hours';
  corte smallint := extract(hour from h0_local)::smallint;
  d0 date := privado.dia_de_negocio(zona, corte);
  -- Las horas de hoy y las mismas de ayer, como instantes.
  i0 timestamptz := h0_local at time zone zona;
  y0 timestamptz := (h0_local - interval '1 day') at time zone zona;
  y3 timestamptz := (h3_local - interval '1 day') at time zone zona;
  ya timestamptz := ((now() at time zone zona) - interval '1 day') at time zone zona;
  uno uuid := extensions.uuid_generate_v4();
begin
  insert into tests.anclas values ('d0', d0, i0);

  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, hora_corte) values
    (a, 'Restaurante A', 'restaurante-a', true, d0 - 30, d0 + 30, corte),
    (b, 'Restaurante B', 'restaurante-b', true, d0 - 30, d0 + 30, corte),
    (c, 'Restaurante C', 'restaurante-c', true, d0 - 30, d0 + 30, corte);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Todo', 'taco'), (611, b, 'Todo B', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco', 25, true), (502, a, 601, 'Agua', 25, true), (503, a, 601, 'Salsa', 10, true),
    (504, a, 601, 'Refresco', 100, true), (505, a, 601, 'Parrillada', 60, true), (506, a, 601, 'Langosta', 90, true),
    (511, b, 611, 'Taco B', 500, true);

  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial, estado, created_at) overriding system value values
    (9101, a, 102, 0, 'abierto', i0 - interval '5 days'), (9102, b, 111, 0, 'abierto', i0 - interval '5 days');

  insert into public.ventas (id, restaurante_id, tipo, cliente_nombre, abierta_por, created_at, estado, folio, cerrada_por, turno_id, cerrada_at, cancelada_motivo)
  overriding system value values
    (1, a, 'para_llevar', 'V1', 102, i0 + interval '5 minutes', 'cerrada', 1, 102, 9101, i0 + interval '30 minutes', null),
    (2, a, 'para_llevar', 'V2', 102, i0 + interval '40 minutes', 'cerrada', 2, 102, 9101, i0 + interval '90 minutes', null),
    (3, a, 'para_llevar', 'V3', 102, i0 + interval '100 minutes', 'cerrada', 3, 102, 9101, i0 + interval '2 hours', null),
    (4, a, 'para_llevar', 'V4', 102, i0 + interval '130 minutes', 'cerrada', 4, 102, 9101, i0 + interval '3 hours', null),
    (5, a, 'para_llevar', 'V5', 102, i0 + interval '150 minutes', 'cerrada', 5, 102, 9101, now(), null),
    (6, a, 'para_llevar', 'V6', 102, i0 + interval '10 minutes', 'abierta', null, null, null, i0 + interval '20 minutes', null),
    (7, a, 'para_llevar', 'V7', 102, i0 + interval '10 minutes', 'cancelada', null, null, null, i0 + interval '20 minutes', 'Se fue'),
    (11, a, 'para_llevar', 'Y1', 102, y0 + interval '5 minutes', 'cerrada', 11, 102, 9101, y0 + interval '30 minutes', null),
    (12, a, 'para_llevar', 'Y2', 102, y0 + interval '40 minutes', 'cerrada', 12, 102, 9101, y0 + interval '2 hours', null),
    (13, a, 'para_llevar', 'Y3', 102, y0 + interval '50 minutes', 'cerrada', 13, 102, 9101, ya + interval '1 minute', null),
    (14, a, 'para_llevar', 'Y4', 102, y0 + interval '60 minutes', 'cerrada', 14, 102, 9101, y3 + (ya - y3) / 2, null),
    (15, a, 'para_llevar', 'Y5', 102, y0 + interval '70 minutes', 'cerrada', 15, 102, 9101, i0 + interval '10 minutes', null),
    (16, a, 'para_llevar', 'Y6', 102, y0 + interval '80 minutes', 'cancelada', null, null, null, y0 + interval '90 minutes', 'Se fue'),
    (17, a, 'para_llevar', 'Z1', 102, y0 - interval '23 hours', 'cerrada', 17, 102, 9101, y0 + interval '10 minutes', null),
    (21, b, 'para_llevar', 'B1', 111, i0 + interval '5 minutes', 'cerrada', 1, 111, 9102, i0 + interval '30 minutes', null);

  insert into public.venta_items (id, restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio,
                                  estado, cancelado_por, autorizado_por, cancelado_motivo, cancelado_at, opciones) overriding system value values
    (101, a, 1, 501, 'Taco', 2.5, 4, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (120, a, 1, 506, 'Langosta', 90, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (119, a, 1, 501, 'Taco', 25, 3, 16, 102, uno, 'cancelado', 102, 102, 'Eran de otra mesa', i0 + interval '20 minutes', '[]'),
    (102, a, 2, 502, 'Agua', 25, 2, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (103, a, 3, 501, 'Taco', 25, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (104, a, 4, 503, 'Salsa', 10, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (105, a, 5, 503, 'Salsa', 7, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (106, a, 6, 504, 'Refresco', 100, 9, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (107, a, 7, 505, 'Parrillada', 60, 5, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (111, a, 11, 501, 'Taco', 20, 2, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (112, a, 12, 505, 'Parrillada', 60, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (113, a, 13, 502, 'Agua', 30, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (114, a, 14, 503, 'Salsa', 5, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (115, a, 15, 503, 'Salsa', 9, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (116, a, 16, 505, 'Parrillada', 80, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (117, a, 17, 505, 'Parrillada', 77, 1, 16, 102, uno, 'activo', null, null, null, null, '[]'),
    (121, b, 21, 511, 'Taco B', 500, 1, 16, 111, uno, 'activo', null, null, null, null, '[]');
end;
$$;

create function tests.h(p_lista jsonb, p_i integer, p_campo text)
returns numeric language sql immutable as $$ select (p_lista -> p_i ->> p_campo)::numeric; $$;
grant execute on function tests.h(jsonb, integer, text) to anon, authenticated, service_role;

select plan(25);


-- ─── Quién las ve ─────────────────────────────────────────────────────────────

select ok(
  has_function_privilege('authenticated', 'public.cifras_de_inicio(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.cifras_de_inicio(uuid)', 'execute'),
  'Solo quien tiene sesión llama a cifras_de_inicio, como antes'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus cifras',
  'Pepe no ve las horas, ni desde su aparato'
);
reset role;

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus cifras',
  'El gerente de B no ve las de A'
);
select is(
  tests.h(public.cifras_de_inicio('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'horas', 3, 'hoy'),
  500.00,
  'Y las suyas no traen nada de A'
);
reset role;


-- ─── Lo que ya daba, igual ────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'vendido_hoy',
  '{"hoy": 192.00, "ayer_a_esta_hora": 105.00, "porcentaje": 83}'::jsonb,
  'vendido_hoy sigue igual: $192 contra lo que ayer ya estaba cerrado a esta hora (40 + 60 + 5)'
);
select ok(
  (select c ?& array['hoy', 'hora', 'vendido_hoy', 'semana', 'lo_mas_vendido', 'mes']
   from (select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as c) x),
  'Las llaves de antes siguen ahí'
);


-- ─── Las horas ────────────────────────────────────────────────────────────────

select is(
  jsonb_array_length(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'horas'),
  4,
  'Una por cada hora en punto, de la hora de corte a la actual: 4'
);
select is(
  (select jsonb_agg(e ->> 'hora') from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'horas') e),
  (select jsonb_agg(to_char(momento at time zone 'America/Mexico_City' + make_interval(hours => n), 'HH24:MI') order by n)
   from tests.anclas, generate_series(0, 3) as n),
  'Cada una con su hora en la zona del restaurante, en orden, y empieza en la hora de corte'
);
select is(
  (select array_agg((e ->> 'hoy')::numeric order by o) from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'horas') with ordinality as t(e, o)),
  array[0, 100, 175, 185]::numeric[],
  'Hoy, acumulado: lo cerrado justo a la hora cuenta en esa hora (V3 en h2, V4 en h3) y V5 todavía no'
);
select is(
  (select array_agg((e ->> 'ayer')::numeric order by o) from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'horas') with ordinality as t(e, o)),
  array[0, 40, 100, 100]::numeric[],
  'Ayer, acumulado y a esas mismas horas: Y2 justo en h2; Y4, Y3, Y5 y Z1 en ninguna'
);
select ok(
  (select tests.h(c -> 'horas', 3, 'hoy') + 7 = (c -> 'vendido_hoy' ->> 'hoy')::numeric
          and tests.h(c -> 'horas', 3, 'ayer') + 5 = (c -> 'vendido_hoy' ->> 'ayer_a_esta_hora')::numeric
   from (select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as c) x),
  'Cuadran con vendido_hoy: de la última hora en punto a ahora solo faltan V5 ($7) y Y4 ($5)'
);
select is(
  (select bool_and(jsonb_typeof(e -> 'hoy') = 'number' and jsonb_typeof(e -> 'ayer') = 'number')
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'horas') e),
  true,
  'Los números van como números'
);


-- ─── Las piezas del más vendido, por día ──────────────────────────────────────

select is(
  public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido' -> 0 ->> 'nombre',
  'Taco',
  'El más vendido es el Taco: no cuentan los 3 cancelados, ni los 9 refrescos de la abierta'
);
select is(
  jsonb_array_length(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias'),
  7,
  'Siete días'
);
select is(
  (select array_agg((e ->> 'dia')::date order by o) from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') with ordinality as t(e, o)),
  (select array_agg(dia - (extract(isodow from dia)::integer - 1) + n order by n) from tests.anclas, generate_series(0, 6) as n),
  'De lunes a domingo'
);
select is(
  (select (e ->> 'unidades')::integer
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') e, tests.anclas a
   where (e ->> 'dia')::date = a.dia),
  5,
  'Hoy, 5 tacos: 4 + 1, sin los 3 cancelados'
);
select is(
  (select (e ->> 'unidades')::integer
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') e, tests.anclas a
   where (e ->> 'dia')::date = a.dia - 1),
  (select case when extract(isodow from dia) = 1 then null else 2 end from tests.anclas),
  'Ayer, 2 tacos, si ayer es de esta semana'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') e, tests.anclas a
   where (e ->> 'dia')::date > a.dia and e -> 'unidades' <> 'null'::jsonb),
  0,
  'Los días que faltan van vacíos'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') e, tests.anclas a
   where (e ->> 'dia')::date < a.dia - 1 and (e ->> 'unidades')::integer is distinct from 0),
  0,
  'Un día de la semana que ya pasó sin tacos dice 0'
);
select ok(
  (select jsonb_typeof(e -> 'unidades') = 'number'
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') e, tests.anclas a
   where (e ->> 'dia')::date = a.dia),
  'Las piezas van como número'
);
reset role;

-- A igualdad de piezas, gana el que dejó más dinero, igual que lo_mas_vendido: la Salsa empata con el Taco
-- y va primero en el abecedario, pero deja menos. Sus 3 de más entran ayer, para que sus días se distingan
-- de los del Taco (si hoy es lunes, ayer no es de esta semana y entran hoy).
insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio)
select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', case when extract(isodow from dia) = 1 then 3 else 14 end, 503, 'Salsa', 0.5, 3, 16, 102, extensions.uuid_generate_v4()
from tests.anclas;

select tests.authenticate_as('gerente_a');
select is(
  public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido' -> 0 ->> 'nombre',
  'Taco',
  'Empatados en piezas, el más vendido sigue siendo el Taco, que dejó más dinero'
);
select is(
  (select (e ->> 'unidades')::integer
   from jsonb_array_elements(public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido_dias') e, tests.anclas a
   where (e ->> 'dia')::date = a.dia),
  5,
  'Y las piezas por día son las suyas, las mismas que lo_mas_vendido'
);
reset role;


-- ─── Un restaurante sin ventas ────────────────────────────────────────────────

select tests.authenticate_as('gerente_c');
select is(
  public.cifras_de_inicio('cccccccc-cccc-4ccc-8ccc-cccccccccccc') -> 'lo_mas_vendido_dias',
  '[]'::jsonb,
  'Sin un más vendido, la lista va vacía'
);
select is(
  (select array_agg((e ->> 'hoy')::numeric + (e ->> 'ayer')::numeric) from jsonb_array_elements(public.cifras_de_inicio('cccccccc-cccc-4ccc-8ccc-cccccccccccc') -> 'horas') e),
  array[0, 0, 0, 0]::numeric[],
  'Y sus horas, en cero: no vacías'
);
select is(
  public.cifras_de_inicio('cccccccc-cccc-4ccc-8ccc-cccccccccccc') -> 'horas' -> 0 -> 'hoy',
  '0.00'::jsonb,
  'El cero también va como número'
);
reset role;


select * from finish();
rollback;
