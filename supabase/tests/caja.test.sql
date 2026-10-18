-- Pruebas de la caja (migración caja, parte 4b del punto de venta). Trae las pruebas de
-- aislamiento de la libreta 2 que tocan turnos, pagos, movimientos y cortes (7, 10, 11 y 12; cada
-- descripción empieza con su número) y lo decidido el 13 y el 17 de octubre de 2026: abrir la
-- caja con su fondo, cobrar (la propina y el cambio los calcula Postgres, entre 3, la cuenta se
-- cierra sola con su folio, la de $0 sin pago, la misma clave no anota dos veces), el efectivo
-- que trae el mesero, entradas y salidas, propinas, el corte a ciegas, el inicio del día de
-- negocio y que una cuenta con pagos no se junta.
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

-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, con ids fijos. A tiene gerente, mesero (con su celular), caja y
-- cocina (en tabletas compartidas) y una caja sin aparato; sus cuentas abiertas: la Mesa 1 de
-- $445, la Mesa 2 de $210, un para llevar de $132 que abrió la caja, la Mesa 3 de $0 y las
-- Mesas 4 y 5 de $50 cada una. B tiene gerente y una cuenta de $25. C (pausado) y D (venció
-- ayer) tienen gerente; C, además, una caja abierta con un pago y una salida.

grant execute on function tests.guardar(text, bigint), tests.id(text) to anon, authenticated;

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
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('cocina_a', 'cocina.a@prueba.test');
  perform tests.create_supabase_user('caja_sin_aparato_a', 'caja.sin.aparato.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Mesero A', '{mesero}', true),
    (103, a, tests.get_supabase_uid('caja_a'), 'Caja A', '{caja}', true),
    (104, a, tests.get_supabase_uid('cocina_a'), 'Cocina A', '{cocina}', true),
    (105, a, tests.get_supabase_uid('caja_sin_aparato_a'), 'Caja A sin aparato', '{caja}', true),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    (131, d, tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular del mesero', 102, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta caja', null, repeat('2', 64), '5e5e5e5e-0000-4000-8000-000000000002'),
    (a, 'Tableta cocina', null, repeat('3', 64), '5e5e5e5e-0000-4000-8000-000000000003');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Platos', 'taco'), (611, b, 'Platos B', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Parrillada', 445, true),
    (502, a, 601, 'Torta', 105, true),
    (503, a, 601, 'Combo', 132, true),
    (504, a, 601, 'Agua de cortesía', 0, true),
    (505, a, 601, 'Orden de tacos', 50, true),
    (511, b, 611, 'Taco B', 25, true);

  insert into public.mesas (id, restaurante_id, nombre) overriding system value values
    (701, a, 'Mesa 1'), (702, a, 'Mesa 2'), (703, a, 'Mesa 3'), (704, a, 'Mesa 4'), (705, a, 'Mesa 5'),
    (711, b, 'Mesa B');

  insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, cliente_nombre, abierta_por) overriding system value values
    (8001, a, 'mesa', 701, 'Mesa 1', null, 102),
    (8002, a, 'mesa', 702, 'Mesa 2', null, 102),
    (8003, a, 'para_llevar', null, null, 'Sr. Ramírez', 103),
    (8004, a, 'mesa', 703, 'Mesa 3', null, 102),
    (8005, a, 'mesa', 704, 'Mesa 4', null, 102),
    (8006, a, 'mesa', 705, 'Mesa 5', null, 102),
    (8101, b, 'mesa', 711, 'Mesa B', null, 111);
  insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio) values
    (a, 8001, 501, 'Parrillada', 445, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001'),
    (a, 8002, 502, 'Torta', 105, 2, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000002'),
    (a, 8003, 503, 'Combo', 132, 1, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000003'),
    (a, 8004, 504, 'Agua de cortesía', 0, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000004'),
    (a, 8005, 505, 'Orden de tacos', 50, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000005'),
    (a, 8006, 505, 'Orden de tacos', 50, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000006'),
    (b, 8101, 511, 'Taco B', 25, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000001');

  -- C quedó con su caja abierta, un pago y una salida de antes de pausarse.
  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial) overriding system value values (9301, c, 121, 100);
  -- Una cuenta de $10 (desde la 4c, lo pagado nunca pasa del total).
  insert into public.ventas (id, restaurante_id, tipo, cliente_nombre, abierta_por, subtotal, total) overriding system value values (8301, c, 'para_llevar', 'Cliente C', 121, 10, 10);
  insert into public.pagos (restaurante_id, venta_id, turno_id, metodo, monto, recibido, cobrado_por, clave)
  values (c, 8301, 9301, 'efectivo', 10, 10, 121, 'c0c0c0c0-0000-4000-8000-000000000001');
  insert into public.movimientos_caja (restaurante_id, turno_id, tipo, monto, motivo, registrado_por, clave)
  values (c, 9301, 'retiro', 5, 'Algo de C', 121, 'c0c0c0c0-0000-4000-8000-000000000002');
end;
$$;

select plan(122);


-- ─── 1 · Permisos ─────────────────────────────────────────────────────────────

select is_empty(
  $$ select t.tabla || ' ' || p.permiso
     from unnest(array['public.turnos', 'public.pagos', 'public.folios', 'public.movimientos_caja', 'public.cortes_caja']) as t(tabla),
          unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) as p(permiso)
     where has_table_privilege('authenticated', t.tabla, p.permiso)
        or (p.permiso in ('INSERT', 'UPDATE') and has_any_column_privilege('authenticated', t.tabla, p.permiso)) $$,
  '1 · Nadie con sesión escribe directo turnos, pagos, folios, movimientos ni cortes: lo hacen las funciones'
);

select is_empty(
  $$ select t from unnest(array['public.turnos', 'public.pagos', 'public.folios', 'public.movimientos_caja', 'public.cortes_caja']) as t
     where has_any_column_privilege('anon', t, 'SELECT') $$,
  '1 · Sin sesión no se lee ninguna de las cinco tablas'
);

select is_empty(
  $$ select c.relname from pg_class c
     where c.oid in ('public.turnos'::regclass, 'public.pagos'::regclass, 'public.folios'::regclass,
                     'public.movimientos_caja'::regclass, 'public.cortes_caja'::regclass)
       and not c.relrowsecurity $$,
  '1 · Las cinco tablas tienen RLS'
);

select ok(
  not has_any_column_privilege('authenticated', 'public.folios', 'SELECT')
  and not has_column_privilege('authenticated', 'public.pagos', 'clave', 'SELECT')
  and not has_column_privilege('authenticated', 'public.movimientos_caja', 'clave', 'SELECT'),
  'Nadie con sesión lee los folios ni las claves de los pagos y movimientos'
);

select ok(
  has_column_privilege('authenticated', 'public.ventas', 'folio', 'SELECT')
  and has_column_privilege('authenticated', 'public.ventas', 'pagado', 'SELECT')
  and not has_column_privilege('authenticated', 'public.ventas', 'pagado', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.ventas', 'folio', 'UPDATE'),
  'La cuenta enseña su folio y lo pagado, y nadie los escribe directo'
);

select is_empty(
  $$ select f from unnest(array[
       'public.abrir_turno(uuid, numeric)',
       'public.resumen_cuenta(bigint, numeric, integer, integer, numeric, numeric)',
       'public.cobrar(bigint, uuid, text, numeric, integer, numeric, numeric, text)',
       'public.movimiento_caja(uuid, uuid, text, numeric, text, bigint)',
       'public.cerrar_turno(uuid, numeric, numeric, numeric)',
       'public.resumen_turno(bigint)',
       'public.mi_efectivo(uuid)',
       'public.inicio_del_dia(uuid)',
       'public.juntar_mesas(bigint, bigint)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE') $$,
  '1 · Las funciones de la caja las llama quien tiene sesión, y cada una revisa quién es; sin sesión no'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.inicio_dia_de_negocio(text, smallint, timestamptz)', 'privado.pesos(numeric)',
       'privado.recalcular_pagado()', 'privado.propina(numeric, integer, numeric)',
       'privado.partes(numeric, integer)', 'privado.turno_abierto(uuid)',
       'privado.propinas_del_turno(bigint)', 'privado.esperado(bigint, text)'
     ]) as f
     where has_function_privilege('authenticated', f, 'EXECUTE') $$,
  '1 · Los ayudantes de privado no se llaman desde la API'
);


-- ─── El día de negocio ────────────────────────────────────────────────────────

select is(
  privado.inicio_dia_de_negocio('America/Mexico_City', 6::smallint, '2026-10-18 06:40+00'),
  '2026-10-17 12:00+00'::timestamptz,
  'El sábado a las 00:40 todavía es el viernes: el día empezó el viernes a las 6:00'
);

select is(
  privado.inicio_dia_de_negocio('America/Mexico_City', 6::smallint, '2026-10-18 13:00+00'),
  '2026-10-18 12:00+00'::timestamptz,
  'El sábado a las 7:00 el día empezó el sábado a las 6:00'
);

select set_config('pruebas.inicio', privado.inicio_dia_de_negocio('America/Mexico_City', 6::smallint)::text, true);
select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  public.inicio_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  current_setting('pruebas.inicio')::timestamptz,
  'inicio_del_dia da el inicio del día de negocio de hoy, con la hora de corte del restaurante'
);

select is(
  public.inicio_del_dia('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  null,
  '12 · El inicio del día de otro restaurante no sale'
);

reset role;


-- ─── Cómo reparte Postgres ────────────────────────────────────────────────────

select is(privado.partes(445, 3), array[148.34, 148.33, 148.33]::numeric[], '$445 entre 3 son $148.34, $148.33 y $148.33');
select is(privado.partes(110, 3), array[36.67, 36.67, 36.66]::numeric[], '$110 entre 3: los primeros se llevan el centavo que sobra');
select is(privado.propina(148.34, 10, null), 14.83::numeric, 'El 10 % de $148.34 es $14.83');
select is(privado.propina(445, 15, null), 66.75::numeric, 'El 15 % de $445 es $66.75');
select is(privado.propina(100, null, 25.555), 25.56::numeric, 'Otra cantidad se redondea al centavo');
select is(privado.propina(100, null, null), 0::numeric, 'Sin propina es $0');
select throws_ok($$ select privado.propina(100, 20, null) $$, '22023', 'La propina sugerida es de 10 % o de 15 %',
  'Solo hay botones de 10 % y 15 %');
select throws_ok($$ select privado.propina(100, 10, 5) $$, '22023', 'La propina es un porcentaje u otra cantidad, no las dos',
  'La propina no es un porcentaje y otra cantidad a la vez');


-- ─── Sin caja abierta nadie cobra ─────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000000', 'efectivo', 445, null, null, 500) $$,
  '55000', 'La caja no está abierta',
  'Sin caja abierta, la app dice «La caja no está abierta»'
);

select is(public.mi_efectivo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 0::numeric, 'Sin caja abierta, el mesero no trae efectivo');


-- ─── Abrir la caja ────────────────────────────────────────────────────────────

select throws_ok(
  $$ select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500) $$,
  '42501', 'Solo la caja y los gerentes de este restaurante abren la caja',
  'El mesero no abre la caja'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500) $$,
  '42501', null, 'La cocina no abre la caja'
);

select tests.authenticate_as('caja_sin_aparato_a');
select throws_ok(
  $$ select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500) $$,
  '42501', null, 'La caja sin su aparato ligado no abre la caja'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  $$ select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', -1) $$,
  '22023', 'Escribe con cuánto efectivo arranca la caja',
  'El fondo no puede ser negativo'
);

select isnt(
  tests.guardar('t1', public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500)),
  null,
  'Lupita abre la caja con $500'
);

select throws_ok(
  $$ select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 300) $$,
  '23505', 'La caja ya está abierta',
  'Hay un solo turno abierto por restaurante'
);

reset role;

select results_eq(
  $$ select estado, abierto_por, fondo_inicial, cerrado_por is null and cerrado_at is null
     from public.turnos where id = tests.id('t1') $$,
  $$ values ('abierto'::text, 103::bigint, 500.00::numeric(12,2), true) $$,
  'El turno nace abierto, a nombre de quien lo abrió, con su fondo'
);

select tests.authenticate_as('gerente_b');
select lives_ok(
  $$ select tests.guardar('tb', public.abrir_turno('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 100)) $$,
  'El gerente de B abre su caja sin aparato'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select results_eq(
  $$ select restaurante_id::text, estado from public.turnos $$,
  $$ values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::text, 'abierto'::text) $$,
  '7 · El mesero ve que su caja está abierta, y no ve la caja de B'
);


-- ─── La hoja de cobro, antes de anotar ────────────────────────────────────────

select results_eq(
  $$ select r->>'total', r->>'pagado', r->>'falta', r->'partes', r->>'propina_10', r->>'propina_15'
     from (select public.resumen_cuenta(8001) as r) x $$,
  $$ values ('445.00', '0.00', '445.00', '[445.00]'::jsonb, '44.50', '66.75') $$,
  'La hoja de la Mesa 1 dice total, pagado, falta y las propinas de 10 y 15 %'
);

select results_eq(
  $$ select r->'partes', r->>'monto', r->>'propina_10'
     from (select public.resumen_cuenta(8001, null, 3) as r) x $$,
  $$ values ('[148.34, 148.33, 148.33]'::jsonb, '148.34', '14.83') $$,
  'Entre 3: las partes, la primera como monto y su 10 %'
);

select results_eq(
  $$ select r->>'propina', r->>'cobrar', r->>'cambio', (r->>'cabe')::boolean
     from (select public.resumen_cuenta(8001, 100, 1, 10, null, 500) as r) x $$,
  $$ values ('10.00', '110.00', '390.00', true) $$,
  'Paga $100 con 10 % de propina y un billete de $500: se cobran $110 y el cambio es $390'
);

select is(
  (public.resumen_cuenta(8001, 500) ->> 'cabe')::boolean,
  false,
  'La hoja avisa cuando el monto pasa de lo que falta'
);

select throws_ok(
  $$ select public.resumen_cuenta(8101) $$,
  '23503', 'Esa cuenta ya no está',
  '12 · El mesero de A no ve la hoja de una cuenta de B'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.resumen_cuenta(8001) $$,
  '42501', null, 'La cocina no cobra'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000001', 'efectivo', 445, null, null, 500) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante cobran',
  'La cocina no anota pagos'
);


-- ─── Cobrar: lo que no se deja ────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.cobrar(8001, null, 'efectivo', 445, null, null, 500) $$,
  '22023', 'Falta la clave del pago', 'Cada pago lleva su clave'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000002', 'cheque', 445) $$,
  '22023', 'Elige si pagó en efectivo, con tarjeta o por transferencia', 'Solo efectivo, tarjeta o transferencia'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000003', 'en_linea', 445) $$,
  '22023', 'Elige si pagó en efectivo, con tarjeta o por transferencia', 'El punto de venta no anota pagos en línea'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000004', 'tarjeta', 445.01) $$,
  '22023', 'No puede pasar de lo que falta ($445.00)', 'Los pagos nunca suman más que el total'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000005', 'efectivo', 445) $$,
  '22023', 'Escribe con cuánto paga el cliente', 'En efectivo se escribe con cuánto pagó'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000006', 'efectivo', 445, 10, null, 480) $$,
  '22023', 'No alcanza: son $489.50 con la propina', 'El billete tiene que cubrir el pago y la propina'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000007', 'tarjeta', 445, null, null, 500) $$,
  '22023', 'Con cuánto paga solo se anota en efectivo', 'Con tarjeta no se escribe billete'
);
select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000008', 'tarjeta', 0) $$,
  '22023', 'Escribe cuánto paga', 'Un pago es de más de $0'
);


-- ─── Cobrar entre 3 ───────────────────────────────────────────────────────────

select results_eq(
  $$ select r->>'cerrada', r->>'folio', r->>'falta', r->>'cambio'
     from (select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000011', 'tarjeta', 148.34, 10, null, null, ' 4417 ') as r) x $$,
  $$ values ('false', null, '296.66', '0.00') $$,
  'Pepe anota la primera parte con tarjeta y 10 %: la cuenta sigue abierta y falta $296.66'
);

reset role;

select results_eq(
  $$ select metodo, monto, propina, recibido, cambio, referencia, cobrado_por, turno_id = tests.id('t1')
     from public.pagos where clave = 'c0b0a000-0000-4000-8000-000000000011' $$,
  $$ values ('tarjeta'::text, 148.34::numeric(12,2), 14.83::numeric(12,2), null::numeric(12,2), null::numeric(12,2), '4417'::text, 102::bigint, true) $$,
  'El pago guarda el método, el monto, la propina que calculó Postgres, la referencia limpia, quién y el turno'
);

select results_eq(
  $$ select estado, pagado, folio from public.ventas where id = 8001 $$,
  $$ values ('abierta'::text, 148.34::numeric(12,2), null::integer) $$,
  'Lo pagado lo suma el trigger; sin cubrir el total no hay folio'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  (public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000011', 'tarjeta', 148.34, 10, null, null, '4417') ->> 'falta'),
  '296.66',
  'El mismo pago otra vez (doble toque) regresa lo mismo'
);

reset role;
select is(
  (select count(*) from public.pagos where venta_id = 8001)::integer, 1,
  'y no se anota dos veces'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select results_eq(
  $$ select r->>'cerrada', r->>'falta', r->>'cambio'
     from (select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000012', 'efectivo', 148.33, null, 20, 200, 'algo') as r) x $$,
  $$ values ('false', '148.33', '31.67') $$,
  'Lupita anota la segunda en efectivo con $20 de propina y un billete de $200: el cambio es $31.67'
);

reset role;
select results_eq(
  $$ select recibido, cambio, referencia from public.pagos where clave = 'c0b0a000-0000-4000-8000-000000000012' $$,
  $$ values (200.00::numeric(12,2), 31.67::numeric(12,2), null::text) $$,
  'En efectivo se guarda el billete y el cambio, y nunca una referencia'
);

select tests.authenticate_as('gerente_a');
select results_eq(
  $$ select r->>'cerrada', r->>'folio', r->>'falta'
     from (select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000013', 'transferencia', 148.33) as r) x $$,
  $$ values ('true', '1', '0.00') $$,
  'Don Chuy anota la última por transferencia: la cuenta se cierra sola con el folio 1'
);

reset role;
select results_eq(
  $$ select estado, folio, cerrada_por, turno_id = tests.id('t1'), cerrada_at is not null, pagado = total
     from public.ventas where id = 8001 $$,
  $$ values ('cerrada'::text, 1, 101::bigint, true, true, true) $$,
  'La cuenta cerrada lleva su folio, quién la cerró, el turno y la hora, y lo pagado es el total'
);

select is((select ultimo from public.folios where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'El folio de A va en 1');

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000014', 'efectivo', 1, null, null, 1) $$,
  '55000', 'Esa cuenta ya no está abierta', 'Una cuenta cerrada no se vuelve a cobrar'
);

select results_eq(
  $$ select r->>'cerrada', r->>'folio'
     from (select public.cobrar(8001, 'c0b0a000-0000-4000-8000-000000000013', 'transferencia', 148.33) as r) x $$,
  $$ values ('true', '1') $$,
  'Repetir el último pago ya cerrada la cuenta regresa la cuenta cerrada con su folio'
);


-- ─── Otras cuentas: folios seguidos, la de $0, y B por su lado ────────────────

select results_eq(
  $$ select r->>'cerrada', r->>'folio', r->>'cambio'
     from (select public.cobrar(8002, 'c0b0a000-0000-4000-8000-000000000021', 'efectivo', 210, null, null, 500) as r) x $$,
  $$ values ('true', '2', '290.00') $$,
  'Pepe cobra la Mesa 2 completa en efectivo: folio 2 y $290 de cambio'
);

select results_eq(
  $$ select r->>'cerrada', r->>'folio', r->>'pago_id'
     from (select public.cobrar(8004, 'c0b0a000-0000-4000-8000-000000000022', null, null) as r) x $$,
  $$ values ('true', '3', null) $$,
  'Una cuenta de $0 se cierra con «Cobrar» sin anotar ningún pago'
);

reset role;
select is((select count(*) from public.pagos where venta_id = 8004)::integer, 0, 'La cuenta de $0 no tiene pagos');

select tests.authenticate_as('gerente_b');
select is(
  public.cobrar(8101, 'c0b0b000-0000-4000-8000-000000000001', 'efectivo', 25, null, null, 25) ->> 'folio',
  '1',
  'El folio es por restaurante: la primera cuenta de B también es la 1'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.cobrar(8101, 'c0b0a000-0000-4000-8000-000000000023', 'efectivo', 1, null, null, 1) $$,
  '55000', 'Esa cuenta ya no está abierta', '12 · La caja de A no cobra cuentas de B'
);


-- ─── El efectivo que trae el mesero, y quién ve qué ───────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is(public.mi_efectivo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 210.00::numeric, 'Pepe trae $210 en efectivo para la caja');

select results_eq(
  $$ select count(*)::integer, count(*) filter (where restaurante_id <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')::integer from public.pagos $$,
  $$ values (4, 0) $$,
  '7 · El mesero lee los pagos de su restaurante y no los de B'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(public.mi_efectivo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 168.33::numeric, 'Lupita cobró $168.33 en efectivo, con propina');


-- ─── Juntar mesas con pagos ───────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select lives_ok(
  $$ select public.cobrar(8005, 'c0b0a000-0000-4000-8000-000000000031', 'tarjeta', 20) $$,
  'La Mesa 4 paga $20 de su cuenta'
);
select throws_ok(
  $$ select public.juntar_mesas(8005, 8006) $$,
  '55000', 'Mesa 4 ya tiene pagos. Cóbrala antes de juntarla.',
  'Una cuenta con pagos no se junta'
);
select lives_ok($$ select public.juntar_mesas(8006, 8005) $$, 'Sí se junta otra mesa con la que ya tiene pagos');

reset role;
select results_eq(
  $$ select total, pagado, estado from public.ventas where id = 8005 $$,
  $$ values (100.00::numeric(12,2), 20.00::numeric(12,2), 'abierta'::text) $$,
  'La Mesa 4 recibe lo de la 5 y conserva su pago'
);


-- ─── Entradas y salidas ───────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000001', 'retiro', 300, 'Tortillas') $$,
  '42501', 'Solo la caja y los gerentes de este restaurante sacan o meten efectivo',
  'El mesero no saca efectivo del cajón'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000002', 'retiro', 300, '  ') $$,
  '22023', 'Escribe el motivo', 'Una salida lleva su motivo'
);
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000003', 'prestamo', 300, 'Algo') $$,
  '22023', 'Elige si el efectivo entra o sale', 'Solo entra o sale'
);
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000004', 'retiro', 0, 'Algo') $$,
  '22023', 'Escribe cuánto', 'Una salida es de más de $0'
);
select isnt(
  tests.guardar('m1', public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000005', 'retiro', 300, ' Pago al de las tortillas ')),
  null,
  'Lupita saca $300 para el de las tortillas'
);
select is(
  public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000005', 'retiro', 300, 'Pago al de las tortillas'),
  tests.id('m1'),
  'La misma salida otra vez (doble toque) regresa la misma'
);

select tests.authenticate_as('gerente_a');
select lives_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000006', 'ingreso', 200, 'Monedas para cambio') $$,
  'Don Chuy mete $200 en monedas'
);

reset role;
select results_eq(
  $$ select tipo, monto, motivo, registrado_por, mesero_id, turno_id = tests.id('t1')
     from public.movimientos_caja where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' order by id $$,
  $$ values ('retiro'::text, 300.00::numeric(12,2), 'Pago al de las tortillas'::text, 103::bigint, null::bigint, true),
            ('ingreso'::text, 200.00::numeric(12,2), 'Monedas para cambio'::text, 101::bigint, null::bigint, true) $$,
  'Cada movimiento queda una vez, con su motivo limpio, quién lo hizo y el turno'
);

select results_eq(
  $$ select accion, miembro_id, tabla, detalle->>'monto', detalle->>'motivo' from public.bitacora where tabla = 'movimientos_caja' order by id $$,
  $$ values ('retiro'::text, 103::bigint, 'movimientos_caja'::text, '300.00'::text, 'Pago al de las tortillas'::text),
            ('ingreso'::text, 101::bigint, 'movimientos_caja'::text, '200.00'::text, 'Monedas para cambio'::text) $$,
  'Las entradas y salidas quedan en la bitácora'
);


-- ─── Las propinas ─────────────────────────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select results_eq(
  $$ select x->>'miembro_id', x->>'total', x->>'pagado', x->>'falta'
     from jsonb_array_elements(public.resumen_turno(tests.id('t1')) -> 'propinas') x $$,
  $$ values ('102', '34.83', '0.00', '34.83') $$,
  'Las propinas son de quien abrió la cuenta: a Pepe le tocan $34.83, aunque una la cobró Lupita'
);

select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000011', 'retiro', 40, null, 102) $$,
  '22023', 'A Mesero A le faltan $34.83 de propinas en este turno',
  'No se le paga más de lo que le falta'
);
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000012', 'ingreso', 10, null, 102) $$,
  '22023', 'Las propinas salen del cajón', 'Las propinas son una salida'
);
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000013', 'retiro', 10, null, 111) $$,
  '23503', 'Esa persona no es de este restaurante', '12 · No se pagan propinas a alguien de B'
);
select lives_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000014', 'retiro', 30, 'esto no cuenta', 102) $$,
  'Lupita le paga $30 de propinas a Pepe'
);

reset role;
select results_eq(
  $$ select tipo, monto, motivo, mesero_id from public.movimientos_caja where clave = 'd0b0a000-0000-4000-8000-000000000014' $$,
  $$ values ('retiro'::text, 30.00::numeric(12,2), 'Propinas de Mesero A'::text, 102::bigint) $$,
  'El pago de propinas es una salida a su nombre, con el motivo que pone Postgres'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select results_eq(
  $$ select x->>'pagado', x->>'falta'
     from jsonb_array_elements(public.resumen_turno(tests.id('t1')) -> 'propinas') x $$,
  $$ values ('30.00', '4.83') $$,
  'Y el resumen dice lo pagado y lo que le falta'
);


-- ─── El corte es a ciegas ─────────────────────────────────────────────────────

select ok(
  not (public.resumen_turno(tests.id('t1')) ?| array['cortes', 'por_persona', 'movimientos']),
  'Con la caja abierta, el resumen no enseña lo esperado ni quién cobró qué'
);
select is(
  (public.resumen_turno(tests.id('t1')) ->> 'cuentas_abiertas')::integer, 2,
  'El resumen dice cuántas cuentas siguen abiertas'
);
select is((select count(*) from public.movimientos_caja)::integer, 3, 'La caja lee los movimientos de su turno');

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is((select count(*) from public.movimientos_caja)::integer, 0, 'El mesero no lee los movimientos de la caja');
select throws_ok(
  $$ select public.resumen_turno(tests.id('t1')) $$,
  '42501', 'Solo la caja y los gerentes de este restaurante ven el corte', 'El mesero no ve el corte'
);
select throws_ok(
  $$ select public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0, 0, 0) $$,
  '42501', 'Solo la caja y los gerentes de este restaurante cierran la caja', 'El mesero no cierra la caja'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 700, null, 0) $$,
  '22023', 'Escribe lo que contaste de efectivo, tarjeta y transferencia, aunque sea $0',
  'En el corte se escriben los tres montos'
);
select throws_ok(
  $$ select public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 700, -1, 0) $$,
  '22023', null, 'Lo contado no es negativo'
);

-- Esperado: efectivo 500 + 168.33 + 210 + 200 − 300 − 30 = 748.33; tarjeta 163.17 + 20 = 183.17;
-- transferencia 148.33.
select is(
  public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 708.33, 183.17, 150),
  tests.id('t1'),
  'Lupita cierra la caja con lo que contó'
);

select results_eq(
  $$ select metodo, esperado, contado, diferencia from public.cortes_caja
     where turno_id = tests.id('t1') order by array_position(array['efectivo', 'tarjeta', 'transferencia'], metodo) $$,
  $$ values ('efectivo'::text, 748.33::numeric(12,2), 708.33::numeric(12,2), -40.00::numeric(12,2)),
            ('tarjeta'::text, 183.17::numeric(12,2), 183.17::numeric(12,2), 0.00::numeric(12,2)),
            ('transferencia'::text, 148.33::numeric(12,2), 150.00::numeric(12,2), 1.67::numeric(12,2)) $$,
  'El corte guarda lo esperado que calcula Postgres, lo contado y la diferencia: faltan $40 en efectivo'
);

reset role;
select results_eq(
  $$ select estado, cerrado_por, cerrado_at is not null from public.turnos where id = tests.id('t1') $$,
  $$ values ('cerrado'::text, 103::bigint, true) $$,
  'El turno queda cerrado a nombre de quien hizo el corte'
);

select tests.authenticate_as('gerente_a');
select results_eq(
  $$ select x->>'nombre', x->>'total', x->>'efectivo', x->>'tarjeta', x->>'transferencia'
     from jsonb_array_elements(public.resumen_turno(tests.id('t1')) -> 'por_persona') x $$,
  $$ values ('Mesero A', '393.17', '210.00', '183.17', '0.00'),
            ('Caja A', '168.33', '168.33', '0.00', '0.00'),
            ('Gerente A', '148.33', '0.00', '0.00', '148.33') $$,
  'Ya cerrada, el corte dice quién cobró qué, con propinas'
);
select is(
  jsonb_array_length(public.resumen_turno(tests.id('t1')) -> 'movimientos'), 3,
  'y las entradas y salidas del turno'
);
select is(
  jsonb_array_length(public.resumen_turno(tests.id('t1')) -> 'cortes'), 3,
  'y los tres métodos del corte'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is((select count(*) from public.cortes_caja)::integer, 0, 'El mesero no lee el corte');

select tests.authenticate_as('caja_sin_aparato_a');
select is(
  (select count(*) from public.cortes_caja)::integer + (select count(*) from public.movimientos_caja)::integer, 0,
  'La caja, fuera de su aparato ligado, no lee el corte ni los movimientos'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is((select count(*) from public.cortes_caja)::integer, 3, 'La caja, desde su aparato, sí lee el corte');
select throws_ok(
  $$ select public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0, 0, 0) $$,
  '55000', 'La caja no está abierta', 'Una caja cerrada no se vuelve a cerrar: el corte no se corrige'
);
select throws_ok(
  $$ select public.movimiento_caja('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0b0a000-0000-4000-8000-000000000021', 'retiro', 10, 'Algo') $$,
  '55000', 'La caja no está abierta', 'Con la caja cerrada no sale efectivo'
);
select throws_ok(
  $$ select public.cobrar(8005, 'c0b0a000-0000-4000-8000-000000000041', 'tarjeta', 80) $$,
  '55000', 'La caja no está abierta', 'Con la caja cerrada nadie cobra'
);


-- ─── El siguiente turno ───────────────────────────────────────────────────────

select isnt(
  tests.guardar('t2', public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500)),
  null,
  'Se abre otro turno'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is(public.mi_efectivo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 0::numeric, 'En el turno nuevo, Pepe arranca sin efectivo');
select results_eq(
  $$ select r->>'cerrada', r->>'folio'
     from (select public.cobrar(8005, 'c0b0a000-0000-4000-8000-000000000042', 'tarjeta', 80) as r) x $$,
  $$ values ('true', '4') $$,
  'La Mesa 4 termina de pagar en el turno nuevo: folio 4'
);

reset role;
select results_eq(
  $$ select turno_id = tests.id('t2'), (select array_agg(p.turno_id = tests.id('t1') order by p.id) from public.pagos p where p.venta_id = 8005)
     from public.ventas where id = 8005 $$,
  $$ values (true, array[true, false]) $$,
  'La cuenta se cierra en el turno nuevo, y cada pago se queda en el turno en que se anotó'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(
  public.resumen_turno(tests.id('t2')) -> 'propinas', '[]'::jsonb,
  'Las propinas del turno pasado no pasan al nuevo'
);


-- ─── Licencia y aislamiento ───────────────────────────────────────────────────

select tests.authenticate_as('gerente_c');
select throws_ok(
  $$ select public.abrir_turno('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 500) $$,
  '42501', null, '10 · Un restaurante pausado no abre la caja'
);

select results_eq(
  $$ select (select count(*) from public.turnos)::integer, (select count(*) from public.pagos)::integer,
            (select count(*) from public.movimientos_caja)::integer $$,
  $$ values (0, 0, 0) $$,
  '10 · Un restaurante pausado no ve su caja, sus pagos ni sus salidas'
);

select tests.authenticate_as('gerente_d');
select throws_ok(
  $$ select public.abrir_turno('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 500) $$,
  '42501', null, '11 · Un restaurante vencido no abre la caja'
);

select tests.authenticate_as('gerente_a');
select results_eq(
  $$ select (select count(*) from public.turnos where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')::integer,
            (select count(*) from public.pagos where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')::integer $$,
  $$ values (0, 0) $$,
  '7 · El gerente de A no ve los turnos ni los pagos de B'
);
select throws_ok(
  $$ select public.resumen_turno(tests.id('tb')) $$,
  '23503', 'Ese turno no está', '12 · El gerente de A no ve el corte de B'
);
select throws_ok(
  $$ select public.cerrar_turno('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 0, 0, 0) $$,
  '42501', null, '12 · El gerente de A no cierra la caja de B'
);
select throws_ok(
  $$ insert into public.pagos (restaurante_id, venta_id, turno_id, metodo, monto, cobrado_por, clave)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 8003, tests.id('t2'), 'tarjeta', 132, 101, gen_random_uuid()) $$,
  '42501', null, 'Ni el gerente anota un pago directo en la tabla'
);
select throws_ok(
  $$ update public.ventas set pagado = 132 where id = 8003 $$,
  '42501', null, 'Ni el gerente escribe lo pagado'
);

reset role;


-- ─── Las reglas de la tabla ───────────────────────────────────────────────────

select throws_ok(
  $$ update public.ventas set estado = 'cerrada' where id = 8003 $$,
  '23514', null, 'Una cuenta no se cierra sin folio'
);
select throws_ok(
  $$ insert into public.pagos (restaurante_id, venta_id, turno_id, metodo, monto, recibido, cobrado_por, clave)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 8003, tests.id('t2'), 'efectivo', 132, 100, 103, gen_random_uuid()) $$,
  '23514', null, 'En efectivo, el billete cubre el pago y la propina'
);
select throws_ok(
  $$ insert into public.pagos (restaurante_id, venta_id, turno_id, metodo, monto, cobrado_por, clave)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 8003, null, 'tarjeta', 132, 103, gen_random_uuid()) $$,
  '23514', null, 'Un pago del punto de venta va en un turno'
);
select throws_ok(
  $$ insert into public.movimientos_caja (restaurante_id, turno_id, tipo, monto, motivo, mesero_id, registrado_por, clave)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('t2'), 'ingreso', 10, 'Propinas', 102, 103, gen_random_uuid()) $$,
  '23514', null, 'Las propinas solo salen del cajón'
);


select * from finish();

rollback;
