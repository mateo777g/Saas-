-- Pruebas del agente IA (migración agente; libreta 1, rev 54; libreta 3, rev 18). Lo decidido el 19
-- de octubre de 2026: el modelo no suma, pide herramientas, y cada una es una función de Postgres
-- que cuenta como Cortes y reportes y Tus meseros (solo las cuentas cerradas, del día de negocio en
-- que se abrieron; lo cancelado no suma; una reabierta no cuenta hasta que se vuelve a cerrar).
-- La hora y el día de la semana van en promedio; la proyección, con los mismos días de la semana;
-- la sexta herramienta, con las mismas partes que reporte_del_dia. Inicio sale de las mismas
-- piezas. El gasto lo anota solo el Worker, Postgres saca el costo, y el agente tiene el tope
-- menos la parte del menú (migración asistente_menu). Solo el gerente pregunta.
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
-- Se siembra como postgres, con ids fijos. Las horas de A se miden desde el inicio del día de
-- negocio de hoy (i0, a las 6:00), y las de «ayer a esta hora», desde ahora, para que nada dependa
-- de la hora en que corren las pruebas.
--   A (cliente directo, corte a las 6): Don Chuy (gerente, apodo «Chuy»), Pepe, Beto y Karla
--     (meseros), Lupita (caja), Tono (mesero de baja). Hoy cerradas: Terraza $90 (5 tacos con $10
--     de descuento y 10 % a la cuenta) y $22, un para llevar de $110 (2 gringas; otra cancelada),
--     Mesa 1 $30 (abierta a las 6:00 en punto), un domicilio de Karla $60 y la Barra (archivada)
--     $22: $334. Abiertas: Mesa 1 $113, Mesa 2 $445 con $200 pagados y una reabierta de $60 con su
--     pago cancelado. Canceladas: la Mesa 3 de Karla ($60) y la Mesa 5, que se juntó. Ayer: Y1 $25
--     (una jamaica con $5 de descuento) y Y3 $30, cerradas antes de esta hora de ayer, y Y2 $22,
--     cerrada después; y una cancelada: $77.
--     El taco se llama hoy «Taco al pastor» (se vendió como «Taco de pastor»), la Gringa y el Sope
--     están archivados, el Agua fresca está oculta, y la Mesa 4 hoy se llama «Terraza».
--   B: su gerente, una cuenta abierta y una cerrada hoy de $80: una pieza de cada producto (Zanahoria
--     B $30, Taco B $25, Agua B $15, Bolillo B $10), para ver el desempate por dinero.
--   C (con distribuidor): septiembre de 2026, un taco de $100 cada martes a las 20:00 (5 martes) y
--     un refresco de $120 cada viernes (4), el último el sábado 26 a las 00:40; los lunes cerró.
--   P: del viernes 28 de noviembre de 2025 al 2 de enero de 2026, cada día vende 100 × su día de
--     la semana (martes $200 … domingo $700); los lunes cierra. El 2 de enero lleva $50.

create table tests.anclas (nombre text primary key, dia date, momento timestamptz);
grant select on tests.anclas to anon, authenticated, service_role;

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  p uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  hoy date := privado.dia_local('America/Mexico_City');
  d0 date := privado.dia_de_negocio('America/Mexico_City', 6::smallint);
  i0 timestamptz := privado.inicio_de_dia('America/Mexico_City', 6::smallint, d0);
  -- Ayer a esta hora: lo cerrado hasta y1 cuenta, lo cerrado en y2 no.
  y1 timestamptz := i0 - interval '1 day' + (now() - i0) / 2;
  y2 timestamptz := now() - interval '1 day' + (i0 - (now() - interval '1 day')) / 2;
  d date;
  n integer := 0;
begin
  insert into tests.anclas values ('d0', d0, i0);

  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('beto_a', 'beto.a@prueba.test');
  perform tests.create_supabase_user('karla_a', 'karla.a@prueba.test');
  perform tests.create_supabase_user('tono_a', 'tono.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_p', 'gerente.p@prueba.test');
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));
  insert into public.distribuidores (id, nombre) overriding system value values (1, 'Juanito');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30, null),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, null),
    (c, 'Restaurante C', 'restaurante-c', true, hoy - 30, hoy + 30, 1),
    (p, 'Restaurante P', 'restaurante-p', true, hoy - 30, hoy + 30, null);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true),
    (103, a, tests.get_supabase_uid('caja_a'), 'Lupita', '{caja}', true),
    (105, a, tests.get_supabase_uid('beto_a'), 'Beto', '{mesero}', true),
    (106, a, tests.get_supabase_uid('karla_a'), 'Karla', '{mesero}', true),
    (107, a, tests.get_supabase_uid('tono_a'), 'Tono', '{mesero}', false),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    (131, p, tests.get_supabase_uid('gerente_p'), 'Gerente P', '{gerente}', true);
  insert into public.perfiles (usuario_id, apodo) values (tests.get_supabase_uid('gerente_a'), 'Chuy');

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Platos', 'taco'), (602, a, 'Bebidas', 'agua'), (611, b, 'Platos B', 'taco'),
    (621, c, 'Todo C', 'taco'), (631, p, 'Todo P', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, archivado_at) overriding system value values
    (501, a, 601, 'Taco al pastor', 22, true, null),
    (502, a, 602, 'Jamaica', 30, true, null),
    (503, a, 601, 'Parrillada', 445, true, null),
    (504, a, 601, 'Gringa', 55, true, now()),
    (505, a, 601, 'Sope', 20, true, now()),
    (506, a, 602, 'Agua fresca', 25, false, null),
    (511, b, 611, 'Taco B', 25, true, null),
    (512, b, 611, 'Agua B', 15, true, null),
    (513, b, 611, 'Bolillo B', 10, true, null),
    (514, b, 611, 'Zanahoria B', 30, true, null),
    (521, c, 621, 'Taco C', 100, true, null),
    (522, c, 621, 'Refresco C', 120, true, null),
    (531, p, 631, 'Comida P', 100, true, null);

  insert into public.mesas (id, restaurante_id, nombre, archivado_at) overriding system value values
    (701, a, 'Mesa 1', null), (702, a, 'Mesa 2', null), (703, a, 'Mesa 3', null),
    (704, a, 'Terraza', null), (705, a, 'Mesa 5', now()), (706, a, 'Barra', now()),
    (711, b, 'Mesa B', null), (721, c, 'Mesa C', null), (731, p, 'Mesa P', null);
  update public.mesas set orden = case id when 701 then 2 when 702 then 1 end where id in (701, 702);

  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial, estado, cerrado_por, cerrado_at, created_at) overriding system value values
    (9100, a, 103, 500, 'cerrado', 103, i0 - interval '15 minutes', i0 - interval '23 hours'),
    (9101, a, 103, 500, 'abierto', null, null, i0 + interval '1 minute'),
    (9200, c, 121, 0, 'cerrado', 121, '2026-09-30 23:00-06', '2026-09-01 08:00-06'),
    (9400, b, 111, 0, 'abierto', null, null, i0 + interval '2 minutes'),
    (9300, p, 131, 0, 'cerrado', 131, '2026-01-02 23:00-06', '2025-11-28 08:00-06');

  insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, cliente_nombre, cliente_telefono, cliente_direccion,
                             abierta_por, created_at, estado, folio, cerrada_por, turno_id, cerrada_at, cancelada_motivo,
                             descuento_tipo, descuento_valor, descuento_motivo) overriding system value values
    (8001, a, 'mesa', 701, 'Mesa 1', null, null, null, 102, i0 + interval '10 minutes', 'abierta', null, null, null, null, null, null, null, null),
    (8002, a, 'mesa', 702, 'Mesa 2', null, null, null, 103, i0 + interval '20 minutes', 'abierta', null, null, null, null, null, null, null, null),
    (8003, a, 'mesa', 703, 'Mesa 3', null, null, null, 102, i0 + interval '30 minutes', 'abierta', 3, null, null, null, null, null, null, null),
    (8004, a, 'mesa', 704, 'Mesa 4', null, null, null, 102, i0 + interval '40 minutes', 'cerrada', 1, 102, 9101, i0 + interval '90 minutes', null, 'porcentaje', 10, 'Cliente de siempre'),
    (8006, a, 'para_llevar', null, null, 'Sr. Ramirez', null, null, 103, i0 + interval '50 minutes', 'cerrada', 4, 103, 9101, i0 + interval '95 minutes', null, null, null, null),
    (8007, a, 'mesa', 703, 'Mesa 3', null, null, null, 106, i0 + interval '60 minutes', 'cancelada', null, null, null, null, 'Se fue sin pagar', null, null, null),
    (8008, a, 'mesa', 705, 'Mesa 5', null, null, null, 102, i0 + interval '70 minutes', 'cancelada', null, null, null, null, 'Se juntó con «Mesa 1»', null, null, null),
    (8010, a, 'mesa', 701, 'Mesa 1', null, null, null, 102, i0, 'cerrada', 5, 102, 9101, i0 + interval '20 minutes', null, null, null, null),
    (8012, a, 'mesa', 704, 'Mesa 4', null, null, null, 107, i0 + interval '80 minutes', 'cerrada', 7, 107, 9101, i0 + interval '100 minutes', null, null, null, null),
    (8020, a, 'domicilio', null, null, 'Sra. Lopez', '5551234', 'Calle Uno 1', 106, i0 + interval '85 minutes', 'cerrada', 9, 106, 9101, i0 + interval '110 minutes', null, null, null, null),
    (8021, a, 'mesa', 706, 'Barra', null, null, null, 102, i0 + interval '86 minutes', 'cerrada', 10, 102, 9101, i0 + interval '111 minutes', null, null, null, null),
    (8031, a, 'mesa', 701, 'Mesa 1', null, null, null, 102, i0 - interval '24 hours', 'cerrada', 11, 103, 9100, y1, null, null, null, null),
    (8032, a, 'mesa', 702, 'Mesa 2', null, null, null, 102, i0 - interval '24 hours', 'cerrada', 12, 103, 9100, y2, null, null, null, null),
    (8033, a, 'mesa', 703, 'Mesa 3', null, null, null, 105, i0 - interval '24 hours', 'cerrada', 13, 103, 9100, y1, null, null, null, null),
    (8034, a, 'mesa', 704, 'Mesa 4', null, null, null, 102, i0 - interval '3 hours', 'cancelada', null, null, null, null, 'Se fue sin pagar', null, null, null),
    (8101, b, 'mesa', 711, 'Mesa B', null, null, null, 111, i0 + interval '5 minutes', 'abierta', null, null, null, null, null, null, null, null),
    (8102, b, 'para_llevar', null, null, 'Cliente B', null, null, 111, i0 + interval '6 minutes', 'cerrada', 1, 111, 9400, i0 + interval '7 minutes', null, null, null, null);

  insert into public.venta_items (id, restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio,
                                  descuento_tipo, descuento_valor, descuento_motivo,
                                  estado, cancelado_por, autorizado_por, cancelado_motivo, cancelado_at, opciones) overriding system value values
    (9001, a, 8001, 501, 'Taco de pastor', 22, 4, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001', 'pesos', 5, 'Cortesia', 'activo', null, null, null, null, '[]'),
    (9002, a, 8001, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001', null, null, null, 'activo', null, null, null, null, '[]'),
    (9009, a, 8001, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001', null, null, null, 'cancelado', 102, 103, 'Era de horchata', i0 + interval '15 minutes', '[]'),
    (9003, a, 8002, 503, 'Parrillada', 445, 1, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000002', null, null, null, 'activo', null, null, null, null, '[]'),
    (9004, a, 8003, 502, 'Jamaica', 30, 2, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000003', null, null, null, 'activo', null, null, null, null, '[]'),
    (9005, a, 8004, 501, 'Taco de pastor', 22, 5, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000004', 'pesos', 10, 'Cortesia', 'activo', null, null, null, null,
       '[{"grupo": "Salsa", "opcion": "Verde", "precio_extra": 0}]'),
    (9007, a, 8006, 504, 'Gringa', 55, 2, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000006', null, null, null, 'activo', null, null, null, null, '[]'),
    (9016, a, 8006, 504, 'Gringa', 55, 1, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000006', 'pesos', 5, 'Cortesia', 'cancelado', 103, 103, 'Se equivoco', i0 + interval '52 minutes', '[]'),
    (9010, a, 8007, 501, 'Taco de pastor', 22, 1, 16, 106, 'a0a0a0a0-0000-4000-8000-000000000007', null, null, null, 'cancelado', 106, 103, 'Eran de suadero', i0 + interval '65 minutes', '[]'),
    (9008, a, 8007, 502, 'Jamaica', 30, 2, 16, 106, 'a0a0a0a0-0000-4000-8000-000000000007', null, null, null, 'cancelado', 106, 101, 'Se fue sin pagar', i0 + interval '3 hours', '[]'),
    (9012, a, 8010, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000010', null, null, null, 'activo', null, null, null, null, '[]'),
    (9014, a, 8012, 501, 'Taco de pastor', 22, 1, 16, 107, 'a0a0a0a0-0000-4000-8000-000000000012', null, null, null, 'activo', null, null, null, null, '[]'),
    (9020, a, 8020, 502, 'Jamaica', 30, 2, 16, 106, 'a0a0a0a0-0000-4000-8000-000000000020', null, null, null, 'activo', null, null, null, null, '[]'),
    (9021, a, 8021, 501, 'Taco de pastor', 22, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000021', null, null, null, 'activo', null, null, null, null, '[]'),
    (9031, a, 8031, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000031', 'pesos', 5, 'Cortesia', 'activo', null, null, null, null, '[]'),
    (9032, a, 8032, 501, 'Taco de pastor', 22, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000032', null, null, null, 'activo', null, null, null, null, '[]'),
    (9033, a, 8033, 502, 'Jamaica', 30, 1, 16, 105, 'a0a0a0a0-0000-4000-8000-000000000033', null, null, null, 'activo', null, null, null, null, '[]'),
    (9034, a, 8034, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000034', null, null, null, 'cancelado', 102, 103, 'Se fue sin pagar', i0 - interval '150 minutes', '[]'),
    (9201, b, 8101, 511, 'Taco B', 25, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000001', null, null, null, 'activo', null, null, null, null, '[]'),
    (9202, b, 8102, 512, 'Agua B', 15, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000002', null, null, null, 'activo', null, null, null, null, '[]'),
    (9203, b, 8102, 511, 'Taco B', 25, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000002', null, null, null, 'activo', null, null, null, null, '[]'),
    (9204, b, 8102, 513, 'Bolillo B', 10, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000002', null, null, null, 'activo', null, null, null, null, '[]'),
    (9205, b, 8102, 514, 'Zanahoria B', 30, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000002', null, null, null, 'activo', null, null, null, null, '[]');

  insert into public.pagos (id, restaurante_id, venta_id, turno_id, metodo, monto, propina, recibido, cobrado_por, clave,
                            cancelado_at, cancelado_por, autorizado_por, cancelado_motivo) overriding system value values
    (9601, a, 8002, 9101, 'tarjeta', 200, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000001', null, null, null, null),
    (9602, a, 8004, 9101, 'efectivo', 90, 10, 100, 102, 'c0c0c0c0-0000-4000-8000-000000000002', null, null, null, null),
    (9603, a, 8003, 9101, 'tarjeta', 60, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000003', i0 + interval '45 minutes', 103, 103, 'Era efectivo'),
    (9604, a, 8006, 9101, 'tarjeta', 110, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000004', null, null, null, null),
    (9605, a, 8010, 9101, 'efectivo', 30, 0, 30, 102, 'c0c0c0c0-0000-4000-8000-000000000005', null, null, null, null),
    (9607, a, 8020, 9101, 'tarjeta', 60, 6, null, 106, 'c0c0c0c0-0000-4000-8000-000000000007', null, null, null, null),
    (9501, a, 8031, 9100, 'efectivo', 25, 0, 25, 103, 'c0c0c0c0-0000-4000-8000-000000000011', null, null, null, null);

  insert into public.folios (restaurante_id, ultimo) values (a, 13);
  insert into public.movimientos_caja (restaurante_id, turno_id, tipo, monto, motivo, mesero_id, registrado_por, clave, created_at) values
    (a, 9101, 'retiro', 5, 'Propina de Pepe', 102, 103, 'd0d0d0d0-0000-4000-8000-000000000001', i0 + interval '5 minutes');

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle, created_at) values
    (a, 106, 101, 'descontar', 'venta_items', '9005', '{"venta_id": 8004}', i0 + interval '35 minutes'),
    (a, 102, 103, 'descontar', 'venta_items', '9005', '{"venta_id": 8004}', i0 + interval '41 minutes'),
    (a, 101, 101, 'descontar', 'ventas', '8004', '{"venta_id": 8004}', i0 + interval '42 minutes'),
    (a, 102, 103, 'descontar', 'venta_items', '9001', '{"venta_id": 8001}', i0 + interval '11 minutes'),
    (a, 106, 101, 'cancelar_cuenta', 'ventas', '8007', '{"cuenta": "Mesa 3", "total": 60, "motivo": "Se fue sin pagar"}', i0 + interval '3 hours'),
    (a, 102, 103, 'cancelar_cuenta', 'ventas', '8034', '{"cuenta": "Mesa 4", "total": 30, "motivo": "Se fue sin pagar"}', i0 - interval '150 minutes'),
    (a, 102, null, 'juntar_mesas', 'ventas', '8008', '{"de": "Mesa 5", "a": "Mesa 1", "a_venta": 8001}', i0 + interval '75 minutes'),
    (a, 102, 103, 'descontar', 'venta_items', '9031', '{"venta_id": 8031}', i0 - interval '23 hours');

  -- C: septiembre de 2026.
  for d in select x::date from generate_series(date '2026-09-01', date '2026-09-30', interval '1 day') as x loop
    if extract(isodow from d) in (2, 5) then
      n := n + 1;
      insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, abierta_por, created_at, estado, folio, cerrada_por, turno_id, cerrada_at)
      overriding system value values
        (82000 + n, c, 'mesa', 721, 'Mesa C', 121,
         case when d = date '2026-09-25' then (date '2026-09-26' + time '00:40') at time zone 'America/Mexico_City'
              else (d + time '20:00') at time zone 'America/Mexico_City' end,
         'cerrada', n, 121, 9200, (d + time '23:00') at time zone 'America/Mexico_City' + interval '2 hours');
      insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio)
      values (c, 82000 + n, case when extract(isodow from d) = 2 then 521 else 522 end,
              case when extract(isodow from d) = 2 then 'Taco C' else 'Refresco C' end,
              case when extract(isodow from d) = 2 then 100 else 120 end, 1, 16, 121, extensions.uuid_generate_v4());
    end if;
  end loop;

  -- P: del 28 de noviembre de 2025 al 2 de enero de 2026; los lunes cierra.
  n := 0;
  for d in select x::date from generate_series(date '2025-11-28', date '2026-01-02', interval '1 day') as x loop
    if extract(isodow from d) <> 1 then
      n := n + 1;
      insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, abierta_por, created_at, estado, folio, cerrada_por, turno_id, cerrada_at)
      overriding system value values
        (83000 + n, p, 'mesa', 731, 'Mesa P', 131, (d + time '12:00') at time zone 'America/Mexico_City',
         'cerrada', n, 131, 9300, (d + time '13:00') at time zone 'America/Mexico_City');
      insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio)
      values (p, 83000 + n, 531, 'Comida P',
              case when d = date '2026-01-02' then 50 else 100 * extract(isodow from d) end, 1, 16, 131,
              extensions.uuid_generate_v4());
    end if;
  end loop;
end;
$$;

-- El dinero escrito, para armar lo esperado con la sesión de un gerente (que no llama a privado).
create function tests.dinero(p_monto numeric)
returns text
language sql
security definer
set search_path = ''
as $$
  select privado.dinero(p_monto);
$$;
grant execute on function tests.dinero(numeric) to authenticated;

select plan(105);


-- ─── Permisos ─────────────────────────────────────────────────────────────────

select is_empty(
  $$ select f from unnest(array[
       'public.agente_herramienta(uuid, text, jsonb)',
       'public.contexto_agente(uuid)',
       'public.cifras_de_inicio(uuid)',
       'public.estado_ia(uuid)',
       'public.fijar_tope_ia(uuid, numeric)',
       'public.uso_ia_cliente(uuid)']) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Las funciones del agente, de Inicio y del tope son de quien tiene sesión; sin sesión, nada'
);

select ok(
  has_function_privilege('service_role', 'public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)', 'EXECUTE'),
  'El gasto lo anota solo el Worker, con la llave secreta'
);

select is_empty(
  $$ select p.oid::regprocedure::text || ' ' || r
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
          unnest(array['anon', 'authenticated', 'service_role']) as r
     where n.nspname = 'privado'
       and has_function_privilege(r, p.oid, 'EXECUTE')
       and not (r = 'authenticated' and p.proname in ('soy_admin', 'mis_membresias', 'mis_restaurantes',
                                                       'mis_restaurantes_gerente', 'mis_restaurantes_caja')) $$,
  'Nadie llama desde afuera a ninguna función privada, salvo las cinco de las reglas de RLS'
);

select is_empty(
  $$ select t || ' ' || r || ' ' || q
     from unnest(array['public.precios_ia', 'public.uso_ia']) as t,
          unnest(array['anon', 'authenticated', 'service_role']) as r,
          unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as q
     where has_table_privilege(r, t, q) $$,
  'Nadie con sesión lee ni escribe precios_ia ni uso_ia directo'
);

select ok(
  (select bool_and(relrowsecurity) from pg_class where oid in ('public.precios_ia'::regclass, 'public.uso_ia'::regclass)),
  'precios_ia y uso_ia tienen RLS'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-10-01", "hasta": "2026-10-01"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Pepe, desde su celular, no le pregunta al agente'
);
select throws_ok(
  $$ select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus cifras',
  'Ni ve las cifras de Inicio'
);
select throws_ok(
  $$ select public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Ni el estado de la IA'
);
reset role;

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-10-01", "hasta": "2026-10-01"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'El gerente de B no le pregunta por A: error, nunca 0 renglones'
);
select throws_ok(
  $$ select public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Ni lee el contexto de A'
);
select throws_ok(
  $$ select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus cifras',
  'Ni las cifras de A'
);
select throws_ok(
  $$ select public.fijar_tope_ia('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 5) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no se pone tope de IA, ni al suyo'
);
select throws_ok(
  $$ select public.uso_ia_cliente('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Ni ve lo gastado'
);
select is(
  public.agente_herramienta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'resumen',
    jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) ->> 'total',
  '$80',
  'El gerente de B solo ve lo suyo: su cuenta cerrada de $80; la abierta no es venta'
);
select is(
  (select jsonb_agg(g ->> 'nombre' order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'ranking',
          jsonb_build_object('agrupar_por', 'producto', 'medir_por', 'unidades',
                             'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) -> 'grupos') as g),
  '["Zanahoria B", "Taco B", "Agua B", "Bolillo B"]'::jsonb,
  'A igualdad de piezas, primero el que dejó más dinero'
);
select is(
  (select jsonb_agg(x ->> 'nombre') from jsonb_array_elements(public.cifras_de_inicio('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'lo_mas_vendido') as x),
  '["Zanahoria B", "Taco B", "Agua B"]'::jsonb,
  'Lo más vendido de Inicio desempata igual, por dinero, también para decidir quién entra a los 3'
);
reset role;


-- ─── Las palabras ─────────────────────────────────────────────────────────────

select is(
  array[privado.dinero(4270), privado.dinero(22.5), privado.dinero(-60), privado.dinero(0), privado.dinero(1234567.891)],
  array['$4,270', '$22.50', '−$60', '$0', '$1,234,567.89'],
  'El dinero va escrito como en la maqueta: sin centavos si es entero'
);
select is(
  array[privado.periodo('2026-10-19', '2026-10-19', '2026-10-19'),
        privado.periodo('2026-10-18', '2026-10-18', '2026-10-19'),
        privado.periodo('2026-10-17', '2026-10-17', '2026-10-19'),
        privado.periodo('2026-10-19', '2026-10-25', '2026-10-21'),
        privado.periodo('2026-10-12', '2026-10-18', '2026-10-21'),
        privado.periodo('2026-10-01', '2026-10-19', '2026-10-19'),
        privado.periodo('2026-09-01', '2026-09-30', '2026-10-19'),
        privado.periodo('2025-12-01', '2025-12-31', '2026-10-19'),
        privado.periodo('2026-01-01', '2026-10-19', '2026-10-19'),
        privado.periodo('2025-01-01', '2025-12-31', '2026-10-19'),
        privado.periodo('2026-10-12', '2026-10-15', '2026-10-19'),
        privado.periodo('2026-09-28', '2026-10-03', '2026-10-19'),
        privado.periodo('2025-12-28', '2026-01-03', '2026-10-19')],
  array['hoy', 'ayer', 'el sábado 17 de octubre', 'esta semana', 'la semana pasada', 'este mes', 'septiembre',
        'diciembre de 2025', 'este año', '2025', 'del 12 al 15 de octubre', 'del 28 de septiembre al 3 de octubre',
        'del 28 de diciembre de 2025 al 3 de enero de 2026'],
  'Los periodos se dicen como los dice la gente'
);
select is(
  array[privado.periodo('2026-10-17', '2026-10-17', '2026-10-19', 'de'),
        privado.periodo('2026-10-19', '2026-10-19', '2026-10-19', 'de'),
        privado.periodo('2026-09-01', '2026-09-30', '2026-10-19', 'de'),
        privado.periodo('2026-10-12', '2026-10-15', '2026-10-19', 'de'),
        privado.periodo('2026-09-01', '2026-09-30', '2026-10-19', 'en'),
        privado.periodo('2026-10-19', '2026-10-19', '2026-10-19', 'en')],
  array['del sábado 17 de octubre', 'de hoy', 'de septiembre', 'del 12 al 15 de octubre', 'en septiembre', 'hoy'],
  'Y con «de» o «en» delante, según la frase'
);


-- ─── ventas_agrupadas: el día de negocio ──────────────────────────────────────

select is(
  (select jsonb_agg(jsonb_build_array(x.clave, x.importe) order by x.clave)
   from privado.ventas_agrupadas('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '2026-09-25', '2026-09-26', 'dia') x),
  '[["2026-09-25", 120.00]]'::jsonb,
  'Con el corte a las 6, la cuenta del sábado a las 00:40 es del viernes'
);
update public.restaurantes set hora_corte = 0 where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
select is(
  (select jsonb_agg(jsonb_build_array(x.clave, x.importe) order by x.clave)
   from privado.ventas_agrupadas('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '2026-09-25', '2026-09-26', 'dia') x),
  '[["2026-09-26", 120.00]]'::jsonb,
  'Con el corte a las 0, la misma cuenta pasa al sábado: cambiar la hora de corte la mueve'
);
update public.restaurantes set hora_corte = 6 where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
select is(
  (select count(*)::integer from privado.ventas_agrupadas('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '2026-08-01', '2026-08-31', 'total')),
  0,
  'Un rango sin ventas regresa 0 renglones'
);


-- ─── Herramienta 1 · resumen ──────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen',
    jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) - 'desde' - 'hasta',
  '{"cuentas": 6, "unidades": 12, "total": "$334", "ticket_promedio": "$55.67", "dias_abiertos": 1,
    "promedio_por_dia_abierto": "$334", "incluye_hoy_parcial": true,
    "leido": {"icono": "datos", "texto": "Lo vendido hoy"}}'::jsonb,
  'Hoy se vendieron $334 en 6 cuentas cerradas: ni las abiertas, ni la reabierta, ni las canceladas, ni lo cancelado'
);
select is(
  (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen',
    jsonb_build_object('desde', (select dia - 1 from tests.anclas), 'hasta', (select dia from tests.anclas))) ->> 'total'),
  '$411',
  'Ayer y hoy juntos son la suma de sus días: $77 + $334'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2020-01-01", "hasta": "2020-01-31"}')
    - 'leido',
  '{"desde": "2020-01-01", "hasta": "2020-01-31", "sin_ventas": true, "incluye_hoy_parcial": false}'::jsonb,
  'Un rango sin ventas dice sin_ventas, nunca un error ni una división entre cero'
);
select is(
  (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen',
     jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) ->> 'total'),
  (select '$' || to_char(sum((x ->> 'vendido')::numeric), 'FM999,999,990')
   from jsonb_array_elements(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'personas') as x),
  'El resumen de hoy cuadra con la suma de «Vendido» en Tus meseros'
);

-- Los argumentos mal puestos.
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-13-01", "hasta": "2026-10-01"}') $$,
  '22023', 'La fecha 2026-13-01 no existe. Usa AAAA-MM-DD.',
  'Una fecha imposible es un error que el modelo puede corregir'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-02-30", "hasta": "2026-03-01"}') $$,
  '22023', 'La fecha 2026-02-30 no existe. Usa AAAA-MM-DD.',
  'El 30 de febrero tampoco existe'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-10-05", "hasta": "2026-10-01"}') $$,
  '22023', 'desde (2026-10-05) va después de hasta (2026-10-01).',
  'Un rango al revés se rechaza antes de sumar'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-10-01"}') $$,
  '22023', 'Falta hasta: un día de negocio en AAAA-MM-DD.',
  'Sin hasta no hay resumen'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-10-01", "hasta": "2026-10-01", "mesa": "Mesa 1"}') $$,
  '22023', 'resumen no lleva «mesa». Lleva: desde, hasta.',
  'Un argumento de más se dice, con los que sí lleva'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sumar', '{}') $$,
  '22023', 'No hay una herramienta «sumar». Las que hay: resumen, ranking, comparar, detalle, proyeccion_mes, cancelaciones_descuentos_propinas.',
  'Una herramienta que no existe es un error con las que hay'
);


-- ─── Herramienta 2 · ranking ──────────────────────────────────────────────────

select is(
  (select jsonb_agg(jsonb_build_array(g ->> 'nombre', g -> 'valor', g -> 'unidades', g -> 'participacion') order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
          jsonb_build_object('agrupar_por', 'producto', 'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) -> 'grupos') as g),
  '[["Taco al pastor", "$144", 7, 41.9], ["Gringa", "$110", 2, 32.0], ["Jamaica", "$90", 3, 26.2],
    ["Agua fresca", "$0", 0, 0.0], ["Parrillada", "$0", 0, 0.0]]'::jsonb,
  'Por producto: con el nombre de hoy, la Gringa archivada porque vendió, y los de 0; el Sope archivado sin ventas no sale'
);
select is(
  (select jsonb_build_object('oculto', g -> 'oculto', 'descuento', r -> 'descuento_a_la_cuenta', 'total', r -> 'total')
   from (select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
           jsonb_build_object('agrupar_por', 'producto', 'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) as r) x,
        jsonb_array_elements(x.r -> 'grupos') as g
   where g ->> 'nombre' = 'Agua fresca'),
  '{"oculto": true, "descuento": {"importe": "−$10", "cuentas": 1},
    "total": {"cuentas": 6, "unidades": 12, "importe": "$334", "dias_abiertos": 1}}'::jsonb,
  'El oculto sale marcado, y los productos ($344) más «Descuento a la cuenta» (−$10) dan el total de resumen: $334'
);
select is(
  (select jsonb_agg(g ->> 'nombre' order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
          jsonb_build_object('agrupar_por', 'producto', 'medir_por', 'unidades', 'orden', 'menor',
                             'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) -> 'grupos') as g),
  '["Agua fresca", "Parrillada", "Gringa", "Jamaica", "Taco al pastor"]'::jsonb,
  'Lo que menos se vende por piezas empieza por lo que no se vendió'
);
select is(
  (select jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'valor', g -> 'cuentas') order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
          jsonb_build_object('agrupar_por', 'mesa', 'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) -> 'grupos') as g),
  '[["Terraza", "$112", 2], ["Para llevar", "$110", 1], ["A domicilio", "$60", 1], ["Mesa 1", "$30", 1],
    ["Barra", "$22", 1], ["Mesa 2", "$0", 0], ["Mesa 3", "$0", 0]]'::jsonb,
  'Por mesa: la Mesa 4 con su nombre de hoy, la Barra archivada con el suyo, y para llevar y domicilio en su renglón'
);
select is(
  (select jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'valor') order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
          jsonb_build_object('agrupar_por', 'mesero', 'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) -> 'grupos') as g),
  (select jsonb_agg(jsonb_build_array(x ->> 'nombre', tests.dinero((x ->> 'vendido')::numeric))
                    order by (x ->> 'vendido')::numeric desc, x ->> 'nombre')
   from jsonb_array_elements(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'personas') as x),
  'Por mesero dice lo mismo que Tus meseros: cada cuenta es de quien la abrió'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
    jsonb_build_object('agrupar_por', 'producto', 'categoria', 'bebidas', 'limite', 1,
                       'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) - 'desde' - 'hasta' - 'grupos',
  '{"agrupar_por": "producto", "medir_por": "importe", "orden": "mayor", "promedio": false, "incluye_hoy_parcial": true,
    "resto": {"grupos": 1, "importe": "$0", "unidades": 0},
    "total": {"cuentas": 2, "unidades": 3, "importe": "$90", "dias_abiertos": 1},
    "leido": {"icono": "datos", "texto": "Lo vendido hoy, por producto, solo Bebidas"}}'::jsonb,
  'Con filtro de categoría cuenta por renglón y sin descuento a la cuenta; después del límite va el resto'
);
select is(
  (select jsonb_build_object('primero', r -> 'grupos' -> 0 ->> 'nombre', 'total', r -> 'total' ->> 'importe', 'leido', r -> 'leido' ->> 'texto')
   from (select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
           jsonb_build_object('agrupar_por', 'producto', 'mesa', 'para llevar',
                              'desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) as r) x),
  '{"primero": "Gringa", "total": "$110", "leido": "Lo vendido hoy, por producto, para llevar"}'::jsonb,
  'Con el filtro «Para llevar» solo cuentan los pedidos para llevar'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking', '{"agrupar_por": "mesa", "desde": "2026-10-01", "hasta": "2026-10-01", "mesa": "Mesa 9"}') $$,
  '22023', 'No hay una mesa «Mesa 9». Las que hay: Mesa 2, Mesa 1, Mesa 3, Terraza, Para llevar, A domicilio.',
  'Una mesa que no existe es un error con las que sí hay'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking', '{"agrupar_por": "hora", "desde": "2026-10-01", "hasta": "2026-10-01", "producto_id": 99}') $$,
  '22023', 'No hay producto #99 en el menú.',
  'Un producto que no existe también'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking', '{"agrupar_por": "producto", "desde": "2026-10-01", "hasta": "2026-10-01", "producto_id": 511}') $$,
  '22023', 'No hay producto #511 en el menú.',
  'Ni uno de otro restaurante'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking', '{"agrupar_por": "platillo", "desde": "2026-10-01", "hasta": "2026-10-01"}') $$,
  '22023', '«platillo» no es una opción de agrupar_por. Opciones: producto, categoria, mesa, mesero, hora, dia_semana, dia, semana, mes.',
  'Una opción que no existe es un error con las que hay'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking', '{"agrupar_por": "producto", "desde": "2026-10-01", "hasta": "2026-10-01", "limite": 51}') $$,
  '22023', 'limite va de 1 a 50.',
  'El límite va de 1 a 50'
);
reset role;

select tests.authenticate_as('gerente_c');
select is(
  (select jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'valor', g -> 'veces') order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'ranking',
          '{"agrupar_por": "dia_semana", "desde": "2026-09-01", "hasta": "2026-09-30"}') -> 'grupos') as g),
  '[["viernes", "$120", 4], ["martes", "$100", 5], ["domingo", "$0", 4], ["jueves", "$0", 4],
    ["lunes", "$0", 4], ["miércoles", "$0", 5], ["sábado", "$0", 4]]'::jsonb,
  'Septiembre: el viernes ($480 en 4) le gana al martes ($500 en 5) porque van en promedio; los lunes cerrados valen 0'
);
select is(
  (select g -> 'veces'
   from jsonb_array_elements(public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'ranking',
          '{"agrupar_por": "dia_semana", "desde": "2026-08-15", "hasta": "2026-09-30"}') -> 'grupos') as g
   where g ->> 'nombre' = 'martes'),
  '5'::jsonb,
  'El rango efectivo empieza con la primera venta: los martes de agosto, antes de abrir, no cuentan'
);
select is(
  (select jsonb_build_object('grupos', jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'valor') order by (g ->> 'lugar')::integer),
                             'dias', min(r ->> 'dias_abiertos_en_el_rango'))
   from (select public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'ranking',
           '{"agrupar_por": "hora", "orden": "cronologico", "desde": "2026-09-01", "hasta": "2026-09-30"}') as r) x,
        jsonb_array_elements(x.r -> 'grupos') as g),
  '{"grupos": [["20:00", "$95.56"], ["00:00", "$13.33"]], "dias": "9"}'::jsonb,
  'La hora se promedia entre los 9 días que abrió, no entre los 30 del mes, y en orden empieza en la hora de corte'
);
select is(
  (select jsonb_build_object('grupos', jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'valor') order by (g ->> 'lugar')::integer),
                             'dias', min(r ->> 'dias_abiertos_en_el_rango'))
   from (select public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'ranking',
           '{"agrupar_por": "hora", "orden": "cronologico", "dia_semana": 5, "desde": "2026-09-01", "hasta": "2026-09-30"}') as r) x,
        jsonb_array_elements(x.r -> 'grupos') as g),
  '{"grupos": [["20:00", "$90"], ["00:00", "$30"]], "dias": "4"}'::jsonb,
  '¿A qué hora vende más los viernes? Entre los 4 viernes que abrió'
);
select is(
  (select jsonb_agg(g ->> 'clave' order by (g ->> 'lugar')::integer)
   from jsonb_array_elements(public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'ranking',
          '{"agrupar_por": "semana", "desde": "2026-09-01", "hasta": "2026-09-30"}') -> 'grupos') as g),
  '["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28"]'::jsonb,
  'Por semana, cada una desde su lunes y en orden cronológico'
);
reset role;


-- ─── Herramienta 3 · comparar ─────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'comparar',
    jsonb_build_object('a_desde', (select dia - 1 from tests.anclas), 'a_hasta', (select dia - 1 from tests.anclas),
                       'b_desde', (select dia from tests.anclas), 'b_hasta', (select dia from tests.anclas)))
    - 'a' - 'b',
  '{"agrupar_por": "total", "medir_por": "importe", "diferencia": "+$257", "cambio_pct": 333.8,
    "cambio_promedio_diario_pct": 333.8, "periodo_b_incompleto": true,
    "leido": {"icono": "datos", "texto": "Ayer contra hoy"}}'::jsonb,
  'Hoy contra ayer: $77 contra $334, y hoy va a medias'
);
select is(
  (select jsonb_build_object(
     'grupos', jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'a', g ->> 'b', g ->> 'diferencia', g -> 'cambio_pct')),
     'descuento', min(r ->> 'descuento_a_la_cuenta'))
   from (select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'comparar',
           jsonb_build_object('a_desde', (select dia - 1 from tests.anclas), 'a_hasta', (select dia - 1 from tests.anclas),
                              'b_desde', (select dia from tests.anclas), 'b_hasta', (select dia from tests.anclas),
                              'agrupar_por', 'producto')) as r) x,
        jsonb_array_elements(x.r -> 'grupos') as g),
  '{"grupos": [["Taco al pastor", "$22", "$144", "+$122", 554.5], ["Gringa", "$0", "$110", "+$110", "nuevo"],
               ["Jamaica", "$55", "$90", "+$35", 63.6]],
    "descuento": "{\"a\": \"$0\", \"b\": \"−$10\", \"diferencia\": \"−$10\"}"}'::jsonb,
  'Por producto, lo que más se movió primero, lo nuevo sin %, y el descuento a la cuenta comparado al final'
);
reset role;

select tests.authenticate_as('gerente_p');
select is(
  public.agente_herramienta('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comparar',
    '{"a_desde": "2025-12-01", "a_hasta": "2025-12-31", "b_desde": "2026-01-01", "b_hasta": "2026-01-02"}')
    - 'leido' - 'agrupar_por' - 'medir_por' - 'periodo_b_incompleto',
  '{"a": {"desde": "2025-12-01", "hasta": "2025-12-31", "cuentas": 26, "unidades": 26, "importe": "$11,300",
          "dias_abiertos": 26, "promedio_por_dia_abierto": "$434.62"},
    "b": {"desde": "2026-01-01", "hasta": "2026-01-02", "cuentas": 2, "unidades": 2, "importe": "$450",
          "dias_abiertos": 2, "promedio_por_dia_abierto": "$225"},
    "diferencia": "−$10,850", "cambio_pct": -96.0, "cambio_promedio_diario_pct": -48.2}'::jsonb,
  'Diciembre contra el 1 y 2 de enero, de un año al otro, con el promedio por día abierto para que sea justo'
);
select throws_ok(
  $$ select public.agente_herramienta('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comparar', '{"a_desde": "2025-12-31", "a_hasta": "2025-12-01", "b_desde": "2026-01-01", "b_hasta": "2026-01-02"}') $$,
  '22023', 'a_desde (2025-12-31) va después de a_hasta (2025-12-01).',
  'Cada periodo se revisa por su lado'
);
reset role;


-- ─── Herramienta 4 · detalle ──────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select is(
  (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"folio": 4}') -> 'cuentas' -> 0) - 'dia' - 'abierta' - 'cerrada',
  '{"folio": 4, "cuenta": "Sr. Ramirez", "tipo": "para llevar", "abrio": "Lupita", "estado": "cerrada", "motivo": null,
    "renglones": [{"texto": "2 × Gringa, $55 c/u", "importe": "$110"},
                  {"texto": "1 × Gringa, $55 c/u", "descuento": "−$5 (Cortesia)", "importe": "$50", "cancelado": "Se equivoco"}],
    "descuento_a_la_cuenta": null, "total": "$110", "pagos": [{"metodo": "tarjeta", "monto": "$110"}]}'::jsonb,
  'El folio 4: sus renglones con su precio, lo cancelado marcado con su motivo, y cómo se pagó'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"folio": 1}') #> '{cuentas,0,renglones,0}',
  '{"texto": "5 × Taco de pastor, $22 c/u", "opciones": "Verde", "descuento": "−$10 (Cortesia)", "importe": "$100"}'::jsonb,
  'Cada renglón trae sus opciones y su descuento'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"folio": 3}') #>> '{cuentas,0,estado}',
  'reabierta',
  'Una cuenta reabierta sale así, con su folio'
);
select is(
  (select jsonb_agg(jsonb_build_array(c ->> 'cuenta', c ->> 'estado', c ->> 'motivo'))
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle',
          jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas), 'estado', 'canceladas')) -> 'cuentas') as c),
  '[["Mesa 5", "juntada", "Se juntó con «Mesa 1»"], ["Mesa 3", "cancelada", "Se fue sin pagar"]]'::jsonb,
  'Las canceladas de hoy, la más reciente primero; la que se juntó dice que se juntó'
);
select ok(
  position('5551234' in public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"folio": 9}')::text) = 0
  and position('Calle' in public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"folio": 9}')::text) = 0
  and public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"folio": 9}') #>> '{cuentas,0,cuenta}' = 'Sra. Lopez',
  'Un pedido a domicilio nunca manda el teléfono ni la dirección: solo el nombre del cliente'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle',
    jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas), 'mesero', 'pepe', 'limite', 1))
    - 'cuentas',
  '{"encontradas": 3, "hay_mas": 2, "leido": {"icono": "historial", "texto": "Las cuentas cerradas de hoy, de Pepe"}}'::jsonb,
  'Sin totales: cuántas encontró y cuántas más hay'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle', '{"desde": "2026-10-01", "hasta": "2026-10-01", "mesero": "Juan"}') $$,
  '22023', 'No hay nadie llamado «Juan» en el equipo. Están: Beto, Don Chuy, Karla, Lupita, Pepe.',
  'Un mesero que no existe es un error con el equipo'
);


-- ─── Herramienta 5 · proyeccion_mes ───────────────────────────────────────────

select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'proyeccion_mes', '{}') ->> 'sin_historia_suficiente',
  'true',
  'Con un día de historia no hay proyección: no se inventa un número'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'proyeccion_mes', '{"mes": "octubre"}') $$,
  '22023', 'proyeccion_mes no lleva argumentos.',
  'La proyección no lleva argumentos: siempre es el mes de hoy'
);
reset role;

select is(
  privado.proyeccion_del_mes('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2026-01-02')
    - 'desglose' - 'mes' - 'hoy' - 'base_desde' - 'base_hasta',
  '{"ya_vendido": 450.00, "hoy_vendido": 50.00, "hoy_promedio": 500.00, "hoy_cuenta_como": 500.00,
    "proyeccion": 12300.00, "estimado_restante": 11850.00, "dias_restantes": 29, "semanas": 4}'::jsonb,
  'El 2 de enero: lo vendido ($450) más hoy a su promedio de viernes ($500 > $50) y cada día que falta a su promedio de las 4 semanas de diciembre: $12,300'
);
select is(
  privado.proyeccion_del_mes('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2026-01-02') -> 'desglose' -> 2,
  '{"fecha": "2026-01-05", "estimado": 0.00}'::jsonb,
  'Un lunes, que cierra, se proyecta en 0'
);
insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, abierta_por, created_at, estado, folio, cerrada_por, turno_id, cerrada_at)
overriding system value values
  (83900, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'mesa', 731, 'Mesa P', 131, '2026-01-02 15:00-06', 'cerrada', 900, 131, 9300, '2026-01-02 16:00-06');
insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 83900, 531, 'Comida P', 550, 1, 16, 131, extensions.uuid_generate_v4());
select is(
  (privado.proyeccion_del_mes('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2026-01-02') ->> 'proyeccion')::numeric,
  12400.00,
  'Si hoy ya lleva $600, más que su promedio, hoy cuenta lo vendido: la proyección no baja por preguntar temprano'
);
select is(
  privado.proyeccion_del_mes('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2025-12-10')
    - 'desglose' - 'mes' - 'hoy' - 'base_desde' - 'base_hasta',
  '{"ya_vendido": 3200.00, "hoy_vendido": 300.00, "hoy_promedio": 300.00, "hoy_cuenta_como": 300.00,
    "proyeccion": 11300.00, "estimado_restante": 8100.00, "dias_restantes": 21, "semanas": 1}'::jsonb,
  'Con menos de 4 semanas de historia se usan las que hay'
);
select is(
  privado.proyeccion_del_mes('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2025-12-01') ->> 'sin_historia_suficiente',
  'true',
  'Con menos de una semana, sin historia suficiente'
);
select is(
  privado.proyeccion_del_mes('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2025-12-31')
    - 'desglose' - 'mes' - 'hoy' - 'base_desde' - 'base_hasta' - 'hoy_vendido' - 'hoy_promedio' - 'semanas',
  '{"ya_vendido": 11300.00, "hoy_cuenta_como": 300.00, "proyeccion": 11300.00, "estimado_restante": 0.00,
    "dias_restantes": 0}'::jsonb,
  'El último día del mes no quedan días: la proyección es lo vendido hasta ayer más lo que cuente hoy'
);


-- ─── Herramienta 6 · cancelaciones, descuentos y propinas ─────────────────────

select tests.authenticate_as('gerente_a');
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
    jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas), 'ver', 'cancelaciones'))
    - 'desde' - 'hasta' - 'resto',
  '{"ver": "cancelaciones", "agrupar_por": "persona", "sin_datos": false,
    "grupos": [{"nombre": "Karla", "veces": 2, "importe": "$82", "motivos": ["Se fue sin pagar", "Eran de suadero"],
                "autorizo": [{"nombre": "Don Chuy", "veces": 1}, {"nombre": "Lupita", "veces": 1}]},
               {"nombre": "Lupita", "veces": 1, "importe": "$50", "motivos": ["Se equivoco"],
                "autorizo": [{"nombre": "Lupita", "veces": 1}]},
               {"nombre": "Pepe", "veces": 1, "importe": "$30", "motivos": ["Era de horchata"],
                "autorizo": [{"nombre": "Lupita", "veces": 1}]}],
    "total": {"veces": 4, "importe": "$162"},
    "leido": {"icono": "corte", "texto": "Las cancelaciones de hoy, por quién las pidió"}}'::jsonb,
  '¿Quién canceló más hoy? Karla, con la cuenta de la Mesa 3; la juntada no es cancelación'
);
select is(
  (select jsonb_build_object(
     'cancelaciones', (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
        jsonb_build_object('desde', d, 'hasta', d, 'ver', 'cancelaciones', 'agrupar_por', 'total')) -> 'total'),
     'descuentos', (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
        jsonb_build_object('desde', d, 'hasta', d, 'ver', 'descuentos', 'agrupar_por', 'total')) -> 'total'),
     'pagos', (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
        jsonb_build_object('desde', d, 'hasta', d, 'ver', 'pagos_cancelados', 'agrupar_por', 'total')) -> 'total' ->> 'importe'),
     'propinas', (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
        jsonb_build_object('desde', d, 'hasta', d, 'ver', 'propinas', 'agrupar_por', 'total')) -> 'total' ->> 'propinas'))
   from (select dia as d from tests.anclas) x),
  (select jsonb_build_object(
     'cancelaciones', jsonb_build_object('veces', (r -> 'cancelaciones' ->> 'renglones')::integer + (r -> 'cancelaciones' ->> 'cuentas')::integer,
                                         'importe', tests.dinero((r -> 'cancelaciones' ->> 'total')::numeric)),
     'descuentos', jsonb_build_object('veces', jsonb_array_length(r -> 'descuentos' -> 'lista'),
                                      'importe', tests.dinero((r -> 'descuentos' ->> 'total')::numeric)),
     'pagos', tests.dinero((select coalesce(sum((pc ->> 'monto')::numeric), 0)
                              from jsonb_array_elements(r -> 'turnos') t, jsonb_array_elements(t -> 'pagos_cancelados') pc)),
     'propinas', tests.dinero((select coalesce(sum((pr ->> 'total')::numeric), 0)
                                 from jsonb_array_elements(r -> 'turnos') t, jsonb_array_elements(t -> 'propinas') pr)))
   from (select public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as r) x),
  'Un día de la sexta herramienta da los mismos totales que Cortes y reportes: cancelaciones, descuentos, pagos cancelados y propinas'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
    jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas), 'ver', 'propinas')) -> 'grupos',
  '[{"nombre": "Pepe", "propinas": "$10", "pagado": "$5", "falta": "$5"},
    {"nombre": "Karla", "propinas": "$6", "pagado": "$0", "falta": "$6"}]'::jsonb,
  '¿Cuánta propina juntó cada quien? Con lo que ya se le pagó de la caja y lo que falta'
);
select is(
  (select jsonb_agg(jsonb_build_array(g ->> 'nombre', g ->> 'importe'))
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
          jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas),
                             'ver', 'descuentos', 'agrupar_por', 'producto')) -> 'grupos') as g),
  '[["A toda la cuenta", "$10"], ["Taco al pastor", "$10"]]'::jsonb,
  'Por producto, lo de toda la cuenta va en su renglón'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
    jsonb_build_object('desde', (select dia - 1 from tests.anclas), 'hasta', (select dia from tests.anclas),
                       'ver', 'cancelaciones', 'agrupar_por', 'total')) -> 'total',
  '{"veces": 5, "importe": "$192"}'::jsonb,
  'Un rango es la suma de sus días: $162 de hoy y la cuenta de $30 de ayer'
);
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas',
    jsonb_build_object('desde', (select dia - 1 from tests.anclas), 'hasta', (select dia from tests.anclas),
                       'ver', 'cancelaciones', 'agrupar_por', 'autorizo')) -> 'grupos',
  '[{"nombre": "Lupita", "veces": 4, "importe": "$132", "motivos": ["Eran de suadero", "Se equivoco", "Era de horchata"]},
    {"nombre": "Don Chuy", "veces": 1, "importe": "$60", "motivos": ["Se fue sin pagar"]}]'::jsonb,
  'Por quién autorizó: Lupita dio su PIN 4 veces; de sus motivos van los 3 más recientes'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas', '{"desde": "2026-10-01", "hasta": "2026-10-01", "ver": "propinas", "agrupar_por": "autorizo"}') $$,
  '22023', 'Las propinas no se autorizan. Con propinas, agrupar_por puede ser: persona, dia, total.',
  'Las propinas no se agrupan por quién autorizó: el error trae las opciones'
);
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cancelaciones_descuentos_propinas', '{"desde": "2026-10-01", "hasta": "2026-10-01", "ver": "pagos_cancelados", "agrupar_por": "producto"}') $$,
  '22023', 'agrupar_por producto solo va con cancelaciones y descuentos. Con pagos_cancelados las opciones son: persona, autorizo, dia, total.',
  'Ni los pagos cancelados por producto'
);


-- ─── Inicio y el contexto ─────────────────────────────────────────────────────

select is(
  public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'vendido_hoy',
  '{"hoy": 334.00, "ayer_a_esta_hora": 55.00, "porcentaje": 507}'::jsonb,
  'Vendido hoy contra lo que ayer ya estaba cerrado a esta hora: $55 (la de $22 se cerró más tarde)'
);
select ok(
  (select tests.dinero((c -> 'semana' ->> 'vendido')::numeric)
            = public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen',
                jsonb_build_object('desde', (select dia - (extract(isodow from dia)::integer - 1) from tests.anclas),
                                   'hasta', (select dia from tests.anclas))) ->> 'total'
          and jsonb_array_length(c -> 'semana' -> 'dias') = 7
          and (select (e ->> 'importe')::numeric from jsonb_array_elements(c -> 'semana' -> 'dias') e
               where (e ->> 'dia')::date = (select dia from tests.anclas)) = 334
          and not exists (select 1 from jsonb_array_elements(c -> 'semana' -> 'dias') e
                          where (e ->> 'dia')::date > (select dia from tests.anclas) and e -> 'importe' <> 'null'::jsonb)
   from (select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as c) x),
  'Esta semana: lo mismo que dice el agente de lunes a hoy, una barra por día, hoy con $334 y los días que faltan vacíos'
);
select is(
  public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'lo_mas_vendido' -> 0 ->> 'nombre',
  'Taco al pastor',
  'Lo más vendido de la semana, por piezas'
);
select ok(
  (select (c -> 'mes' ->> 'vendido')::numeric = (c -> 'mes' -> 'dias' -> -1 ->> 'acumulado')::numeric
          and (c -> 'mes' -> 'dias' -> -1 ->> 'dia')::date = (select dia from tests.anclas)
          and c -> 'mes' -> 'va_para' = 'null'::jsonb
   from (select public.cifras_de_inicio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as c) x),
  'Este mes: día por día hasta hoy, el acumulado cuadra con lo vendido, y sin historia no dice «Va para»'
);
select is(
  (public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'cuentas_abiertas') - 'lista',
  '{"cuentas": 3, "por_cobrar": "$418"}'::jsonb,
  'El contexto trae las cuentas abiertas ahora con lo que falta: $113 + $245 + $60'
);
select is(
  (select jsonb_build_object('como', c -> 'como_llamarlo', 'mesas', c -> 'mesas',
                             'menu', (select jsonb_agg(m ->> 'nombre' || coalesce(' (oculto)', '') order by m ->> 'nombre')
                                      from jsonb_array_elements(c -> 'menu') m where m ? 'oculto'),
                             'productos', jsonb_array_length(c -> 'menu'))
   from (select public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') as c) x),
  '{"como": "Chuy", "mesas": ["Mesa 2", "Mesa 1", "Mesa 3", "Terraza", "Para llevar", "A domicilio"],
    "menu": ["Agua fresca (oculto)"], "productos": 4}'::jsonb,
  'Y cómo lo llaman, las mesas y el menú sin lo archivado, con el oculto marcado'
);
select ok(
  position('5551234' in public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')::text) = 0,
  'El contexto tampoco manda teléfonos'
);


-- ─── La reabierta vuelve a contar al cerrarse ─────────────────────────────────

reset role;
update public.ventas set estado = 'cerrada', cerrada_por = 103, turno_id = 9101, cerrada_at = now() where id = 8003;
select tests.authenticate_as('gerente_a');
select is(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen',
    jsonb_build_object('desde', (select dia from tests.anclas), 'hasta', (select dia from tests.anclas))) ->> 'total',
  '$394',
  'Al volver a cerrarse, la reabierta cuenta otra vez: $334 + $60'
);
reset role;


-- ─── El gasto y el tope ───────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'vuelve',
  '{"puede": false, "motivo": "sin_ia", "con_distribuidor": false}'::jsonb,
  'Un restaurante nace con tope 0: sin IA, y es cliente directo'
);
reset role;

select tests.authenticate_as('fragmentless');
select throws_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10.01) $$,
  '22023', 'El tope de IA va de 0 a 10 dólares',
  'El tope no pasa de 10 dólares, el máximo de Fragmentless'
);
select throws_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', -1) $$,
  '22023', 'El tope de IA va de 0 a 10 dólares',
  'Ni baja de 0'
);
select throws_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 2.005) $$,
  '22023', 'El tope de IA lleva hasta centavos',
  'Va en dólares con centavos'
);
select lives_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0.02) $$,
  'Fragmentless le pone 2 centavos de tope a A'
);
reset role;

select throws_ok(
  $$ update public.restaurantes set tope_ia_usd_mes = 11 where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '23514', null,
  'La base tampoco deja guardar un tope de más de 10'
);

select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true}'::jsonb,
  'Con tope, el gerente puede preguntar; no ve cuánto se ha gastado'
);
reset role;

select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pregunta', 'gpt-6.1-sol', 10000, 4000, 2000, 640),
  '{"costo": 0.0198, "puede": true}'::jsonb,
  'Una pregunta: 4,000 de entrada a $2, 4,000 de caché a $0.10, 2,000 guardados en caché a $2.50 y 640 de salida a $10 por millón'
);
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'saludo', 'gpt-5.6-luna', 600, 0, 0, 40),
  '{"costo": 0.0002, "puede": false}'::jsonb,
  'Un saludo cuesta $0.000168, redondeado a 4 decimales; con él se llega justo a los 2 centavos, y ya no puede'
);
select throws_ok(
  $$ select public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pregunta', 'gpt-6.1-sol', 100, 80, 30, 10) $$,
  '22023', 'Los tokens de caché van dentro de los de entrada',
  'Los de caché no pueden ser más que los de entrada'
);
select throws_ok(
  $$ select public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pregunta', 'gpt-4', 100, 0, 0, 10) $$,
  'P0002', 'No hay precio para el modelo gpt-4',
  'Un modelo sin precio no se anota en silencio'
);
select throws_ok(
  $$ select public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'flyer', 'gpt-6.1-sol', 100, 0, 0, 10) $$,
  '22023', 'El uso de IA es pregunta, saludo, menu o menu_sin_respuesta',
  'Los flyers todavía no existen'
);
reset role;

select is(
  (select jsonb_build_object('mes', mes, 'consultas', consultas_agente, 'saludos', saludos, 'agente', costo_agente_usd,
                             'total', costo_usd)
   from public.uso_ia where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('mes', date_trunc('month', privado.dia_local('America/Mexico_City'))::date,
                     'consultas', 1, 'saludos', 1, 'agente', 0.0200, 'total', 0.0200),
  'uso_ia lleva el mes del calendario, las preguntas, los saludos y su costo en el sobre del agente'
);

select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', false,
                     'vuelve', (date_trunc('month', (now() at time zone 'America/Mexico_City')::date) + interval '1 month')::date),
  'Al llegar al tope, la IA se pausa hasta el día 1 del mes que viene'
);
reset role;

select tests.authenticate_as('fragmentless');
select is(
  public.uso_ia_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'mes',
  '{"tope": 0.02, "gastado": 0.0200, "sobre_agente": 0.02, "gastado_agente": 0.0200, "consultas_agente": 1,
    "saludos": 1, "agente_en_limite": true, "sobre_menu": 0.00, "gastado_menu": 0.0000, "consultas_menu": 0,
    "menu_en_limite": false, "distribuidor_id": null, "distribuidor": null}'::jsonb,
  'La ventana «Tope de IA» trae lo gastado este mes, el tope y quién paga'
);
select is(
  public.uso_ia_cliente('cccccccc-cccc-4ccc-8ccc-cccccccccccc') ->> 'distribuidor',
  'Juanito',
  'Un cliente con distribuidor dice quién'
);
select lives_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10) $$,
  'Subir el tope a 10'
);
reset role;
select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true}'::jsonb,
  '… reactiva la IA en ese momento: el agente tiene sus 8 de los 10'
);
reset role;

select tests.authenticate_as('gerente_c');
select is(
  public.estado_ia('cccccccc-cccc-4ccc-8ccc-cccccccccccc') ->> 'con_distribuidor',
  'true',
  'Con distribuidor, el aviso le dice al gerente que le pida a su distribuidor'
);
reset role;


-- ─── Sin licencia ─────────────────────────────────────────────────────────────

update public.restaurantes set licencia_activa = false where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.authenticate_as('gerente_a');
select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen', '{"desde": "2026-10-01", "hasta": "2026-10-01"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Con la licencia apagada, el gerente ya no le pregunta al agente'
);
select throws_ok(
  $$ select public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Ni ve el estado de la IA'
);
reset role;


select * from finish();
rollback;
