-- Pruebas de Cortes y reportes (migración reportes, pieza 5 del punto de venta). Lo decidido el 18
-- de octubre de 2026: una cuenta es del día de negocio en que se abrió, con la hora de corte que
-- tenga el restaurante al leer (cambiarla reacomoda lo pasado y queda en la bitácora); Mesas ahora
-- con lo que falta por cobrar; Tus meseros con los meseros activos y quien vendió hoy; y el reporte
-- de un día: el corte de cada turno (sin lo esperado mientras la caja está abierta), sus pagos
-- cancelados, y los descuentos, las cancelaciones y los otros cambios de las cuentas de ese día.
-- Solo el gerente lee todo esto.
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


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, con ids fijos y con horas medidas desde el inicio del día de negocio
-- de hoy (i0, a la hora de corte, 6:00), para que el día de cada cuenta no dependa de la hora en
-- que corren las pruebas. A tiene a Don Chuy (gerente), Pepe, Beto y Karla (meseros), Lupita
-- (caja), el taquero (cocina), y Tono y Ex (meseros dados de baja). Hoy: la Mesa 1 abierta de Pepe
-- ($113: 4 tacos con $5 de descuento y una jamaica; otra jamaica cancelada), la Mesa 2 abierta de
-- Lupita ($445 con $200 pagados), una cuenta reabierta de Pepe con folio 3 (su pago se canceló),
-- la Mesa 4 cerrada de Pepe ($90: 5 tacos con $10 de descuento y 10 % a la cuenta), un para llevar
-- cerrado de Lupita ($110, y una gringa con descuento que se canceló), la Mesa 3 de Karla cancelada completa ($60, antes se canceló un taco),
-- la Mesa 5 que se juntó con la Mesa 1, una cuenta de Pepe abierta justo a las 6:00 ($30) y una de
-- Tono ($22). Ayer: tres cuentas cerradas de Pepe (una 30 minutos antes del corte de hoy) y una
-- cancelada. La caja de ayer (9100) se cortó; la de hoy (9101) está abierta. B tiene gerente y una
-- cuenta de hoy.

create table tests.anclas (nombre text primary key, dia date, momento timestamptz);
grant select on tests.anclas to anon, authenticated, service_role;

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  hoy date := privado.dia_local('America/Mexico_City');
  d0 date := privado.dia_de_negocio('America/Mexico_City', 6::smallint);
  i0 timestamptz := privado.inicio_de_dia('America/Mexico_City', 6::smallint, d0);
begin
  insert into tests.anclas values ('d0', d0, i0);

  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('cocina_a', 'cocina.a@prueba.test');
  perform tests.create_supabase_user('beto_a', 'beto.a@prueba.test');
  perform tests.create_supabase_user('karla_a', 'karla.a@prueba.test');
  perform tests.create_supabase_user('tono_a', 'tono.a@prueba.test');
  perform tests.create_supabase_user('ex_a', 'ex.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true),
    (103, a, tests.get_supabase_uid('caja_a'), 'Lupita', '{caja}', true),
    (104, a, tests.get_supabase_uid('cocina_a'), 'Taquero', '{cocina}', true),
    (105, a, tests.get_supabase_uid('beto_a'), 'Beto', '{mesero}', true),
    (106, a, tests.get_supabase_uid('karla_a'), 'Karla', '{mesero}', true),
    (107, a, tests.get_supabase_uid('tono_a'), 'Tono', '{mesero}', false),
    (108, a, tests.get_supabase_uid('ex_a'), 'Ex', '{mesero}', false),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta caja', null, repeat('2', 64), '5e5e5e5e-0000-4000-8000-000000000002');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Platos', 'taco'), (611, b, 'Platos B', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco de pastor', 22, true),
    (502, a, 601, 'Jamaica', 30, true),
    (503, a, 601, 'Parrillada', 445, true),
    (504, a, 601, 'Gringa', 55, true),
    (511, b, 611, 'Taco B', 25, true);

  -- La base pone cada mesa nueva al final; la Mesa 2 se sube al primer lugar.
  insert into public.mesas (id, restaurante_id, nombre, archivado_at) overriding system value values
    (701, a, 'Mesa 1', null), (702, a, 'Mesa 2', null), (703, a, 'Mesa 3', null),
    (704, a, 'Mesa 4', null), (705, a, 'Mesa 5', now()), (711, b, 'Mesa B', null);
  update public.mesas set orden = case id when 701 then 2 when 702 then 1 end where id in (701, 702);

  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial, estado, cerrado_por, cerrado_at, created_at) overriding system value values
    (9100, a, 103, 500, 'cerrado', 103, i0 - interval '15 minutes', i0 - interval '10 hours'),
    (9101, a, 103, 500, 'abierto', null, null, i0 + interval '1 minute');

  -- Cada cuenta nace ya en su estado: cerradas con su folio y su turno, canceladas con su motivo.
  -- Así no chocan con la regla de una cuenta abierta por mesa.
  insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, cliente_nombre, abierta_por, created_at,
                             estado, folio, cerrada_por, turno_id, cerrada_at, cancelada_motivo,
                             descuento_tipo, descuento_valor, descuento_motivo) overriding system value values
    (8001, a, 'mesa', 701, 'Mesa 1', null, 102, i0 + interval '10 minutes', 'abierta', null, null, null, null, null, null, null, null),
    (8002, a, 'mesa', 702, 'Mesa 2', null, 103, i0 + interval '20 minutes', 'abierta', null, null, null, null, null, null, null, null),
    (8003, a, 'mesa', 703, 'Mesa 3', null, 102, i0 + interval '30 minutes', 'abierta', 3, null, null, null, null, null, null, null),
    (8004, a, 'mesa', 704, 'Mesa 4', null, 102, i0 + interval '40 minutes', 'cerrada', 1, 102, 9101, i0 + interval '90 minutes', null, 'porcentaje', 10, 'Cliente de siempre'),
    (8005, a, 'mesa', 704, 'Mesa 4', null, 102, i0 - interval '2 hours', 'cerrada', 2, 103, 9100, i0 - interval '100 minutes', null, null, null, null),
    (8006, a, 'para_llevar', null, null, 'Sr. Ramirez', 103, i0 + interval '50 minutes', 'cerrada', 4, 103, 9101, i0 + interval '95 minutes', null, null, null, null),
    (8007, a, 'mesa', 703, 'Mesa 3', null, 106, i0 + interval '60 minutes', 'cancelada', null, null, null, null, 'Se fue sin pagar', null, null, null),
    (8008, a, 'mesa', 705, 'Mesa 5', null, 102, i0 + interval '70 minutes', 'cancelada', null, null, null, null, 'Se juntó con «Mesa 1»', null, null, null),
    (8009, a, 'mesa', 702, 'Mesa 2', null, 102, i0 - interval '3 hours', 'cancelada', null, null, null, null, 'Se fue sin pagar', null, null, null),
    (8010, a, 'mesa', 701, 'Mesa 1', null, 102, i0, 'cerrada', 5, 102, 9101, i0 + interval '20 minutes', null, null, null, null),
    (8011, a, 'mesa', 701, 'Mesa 1', null, 102, i0 - interval '1 microsecond', 'cerrada', 6, 103, 9100, i0 - interval '20 minutes', null, null, null, null),
    (8012, a, 'mesa', 704, 'Mesa 4', null, 107, i0 + interval '80 minutes', 'cerrada', 7, 107, 9101, i0 + interval '100 minutes', null, null, null, null),
    (8013, a, 'mesa', 702, 'Mesa 2', null, 102, i0 - interval '30 minutes', 'cerrada', 8, 103, 9100, i0 - interval '16 minutes', null, null, null, null),
    (8101, b, 'mesa', 711, 'Mesa B', null, 111, i0 + interval '5 minutes', 'abierta', null, null, null, null, null, null, null, null);

  insert into public.venta_items (id, restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio,
                                  descuento_tipo, descuento_valor, descuento_motivo,
                                  estado, cancelado_por, autorizado_por, cancelado_motivo, cancelado_at) overriding system value values
    (9001, a, 8001, 501, 'Taco de pastor', 22, 4, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001', 'pesos', 5, 'Cortesia', 'activo', null, null, null, null),
    (9002, a, 8001, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001', null, null, null, 'activo', null, null, null, null),
    (9009, a, 8001, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001', null, null, null, 'cancelado', 102, 103, 'Era de horchata', i0 + interval '15 minutes'),
    (9003, a, 8002, 503, 'Parrillada', 445, 1, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000002', null, null, null, 'activo', null, null, null, null),
    (9004, a, 8003, 502, 'Jamaica', 30, 2, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000003', null, null, null, 'activo', null, null, null, null),
    (9005, a, 8004, 501, 'Taco de pastor', 22, 5, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000004', 'pesos', 10, 'Cortesia', 'activo', null, null, null, null),
    (9006, a, 8005, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000005', null, null, null, 'activo', null, null, null, null),
    (9007, a, 8006, 504, 'Gringa', 55, 2, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000006', null, null, null, 'activo', null, null, null, null),
    (9016, a, 8006, 504, 'Gringa', 55, 1, 16, 103, 'a0a0a0a0-0000-4000-8000-000000000006', 'pesos', 5, 'Cortesia', 'cancelado', 103, 103, 'Se equivoco', i0 + interval '52 minutes'),
    (9010, a, 8007, 501, 'Taco de pastor', 22, 1, 16, 106, 'a0a0a0a0-0000-4000-8000-000000000007', null, null, null, 'cancelado', 106, 103, 'Eran de suadero', i0 + interval '65 minutes'),
    (9008, a, 8007, 502, 'Jamaica', 30, 2, 16, 106, 'a0a0a0a0-0000-4000-8000-000000000007', null, null, null, 'cancelado', 106, 101, 'Se fue sin pagar', i0 + interval '3 hours'),
    (9011, a, 8009, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000009', null, null, null, 'cancelado', 102, 103, 'Se fue sin pagar', i0 - interval '150 minutes'),
    (9012, a, 8010, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000010', null, null, null, 'activo', null, null, null, null),
    (9013, a, 8011, 501, 'Taco de pastor', 22, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000011', null, null, null, 'activo', null, null, null, null),
    (9014, a, 8012, 501, 'Taco de pastor', 22, 1, 16, 107, 'a0a0a0a0-0000-4000-8000-000000000012', null, null, null, 'activo', null, null, null, null),
    (9015, a, 8013, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000013', null, null, null, 'activo', null, null, null, null),
    (9201, b, 8101, 511, 'Taco B', 25, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000001', null, null, null, 'activo', null, null, null, null);

  insert into public.pagos (id, restaurante_id, venta_id, turno_id, metodo, monto, propina, recibido, cobrado_por, clave,
                            cancelado_at, cancelado_por, autorizado_por, cancelado_motivo) overriding system value values
    (9601, a, 8002, 9101, 'tarjeta', 200, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000001', null, null, null, null),
    (9602, a, 8004, 9101, 'efectivo', 90, 0, 100, 102, 'c0c0c0c0-0000-4000-8000-000000000002', null, null, null, null),
    (9603, a, 8003, 9101, 'tarjeta', 60, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000003', i0 + interval '45 minutes', 103, 103, 'Era efectivo'),
    (9604, a, 8006, 9101, 'tarjeta', 110, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000004', null, null, null, null),
    (9605, a, 8010, 9101, 'efectivo', 30, 0, 30, 102, 'c0c0c0c0-0000-4000-8000-000000000005', null, null, null, null),
    (9606, a, 8012, 9101, 'efectivo', 22, 0, 22, 107, 'c0c0c0c0-0000-4000-8000-000000000006', null, null, null, null),
    (9501, a, 8005, 9100, 'efectivo', 30, 0, 30, 103, 'c0c0c0c0-0000-4000-8000-000000000007', null, null, null, null),
    (9502, a, 8011, 9100, 'efectivo', 22, 0, 22, 103, 'c0c0c0c0-0000-4000-8000-000000000008', null, null, null, null),
    (9503, a, 8013, 9100, 'efectivo', 30, 0, 30, 103, 'c0c0c0c0-0000-4000-8000-000000000009', null, null, null, null);

  insert into public.folios (restaurante_id, ultimo) values (a, 8);

  insert into public.movimientos_caja (restaurante_id, turno_id, tipo, monto, motivo, registrado_por, clave, created_at) values
    (a, 9101, 'ingreso', 200, 'Monedas para cambio', 103, 'd0d0d0d0-0000-4000-8000-000000000001', i0 + interval '5 minutes');
  insert into public.cortes_caja (restaurante_id, turno_id, metodo, esperado, contado) values
    (a, 9100, 'efectivo', 582, 572), (a, 9100, 'tarjeta', 0, 0), (a, 9100, 'transferencia', 0, 0);

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle, created_at) values
    (a, 106, 101, 'descontar', 'venta_items', '9005', '{"venta_id": 8004}', i0 + interval '35 minutes'),
    (a, 102, 103, 'descontar', 'venta_items', '9005', '{"venta_id": 8004}', i0 + interval '41 minutes'),
    (a, 101, 101, 'descontar', 'ventas', '8004', '{"venta_id": 8004}', i0 + interval '42 minutes'),
    (a, 102, 103, 'descontar', 'venta_items', '9001', '{"venta_id": 8001}', i0 + interval '11 minutes'),
    (a, 106, 101, 'cancelar_cuenta', 'ventas', '8007', '{"cuenta": "Mesa 3", "total": 60, "motivo": "Se fue sin pagar"}', i0 + interval '3 hours'),
    (a, 102, 103, 'cancelar_cuenta', 'ventas', '8009', '{"cuenta": "Mesa 2", "total": 30, "motivo": "Se fue sin pagar"}', i0 - interval '150 minutes'),
    (a, 102, null, 'cambiar_mesa', 'ventas', '8001', '{"de": "Mesa 3", "a": "Mesa 1"}', i0 + interval '12 minutes'),
    (a, 102, null, 'quitar_descuento', 'venta_items', '9002', '{"venta_id": 8001, "tipo": "pesos", "valor": 5}', i0 + interval '14 minutes'),
    (a, 102, null, 'juntar_mesas', 'ventas', '8008', '{"de": "Mesa 5", "a": "Mesa 1", "a_venta": 8001}', i0 + interval '75 minutes'),
    (a, 102, null, 'cambiar_mesa', 'ventas', '8005', '{"de": "Mesa 2", "a": "Mesa 4"}', i0 - interval '110 minutes');
end;
$$;

select plan(60);


-- ─── Permisos ─────────────────────────────────────────────────────────────────

select is_empty(
  $$ select f from unnest(array[
       'public.fijar_hora_corte(uuid, integer)',
       'public.mesas_ahora(uuid)',
       'public.tus_meseros(uuid)',
       'public.reporte_del_dia(uuid, date)']) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Las funciones de los reportes y la hora de corte son de quien tiene sesión; sin sesión, nada'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.inicio_de_dia(text, smallint, date)',
       'privado.cuentas_del_dia(uuid, date, date)']) as f,
       unnest(array['anon', 'authenticated', 'service_role']) as r
     where has_function_privilege(r, f, 'EXECUTE') $$,
  'Las funciones privadas del día de negocio no las llama nadie desde afuera'
);


-- ─── El día de cada cuenta ────────────────────────────────────────────────────

select set_eq(
  $$ select id from privado.cuentas_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia from tests.anclas), (select dia from tests.anclas)) $$,
  array[8001, 8002, 8003, 8004, 8006, 8007, 8008, 8010, 8012]::bigint[],
  'Las cuentas de hoy son las que se abrieron desde las 6:00, en cualquier estado; la de las 6:00 en punto es de hoy'
);

select set_eq(
  $$ select id from privado.cuentas_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas), (select dia - 1 from tests.anclas)) $$,
  array[8005, 8009, 8011, 8013]::bigint[],
  'Lo que se abrió antes de las 6:00, aunque sea un instante antes, es de ayer'
);

select is_empty(
  $$ select v.id
     from public.ventas v
     join public.restaurantes r on r.id = v.restaurante_id
     where not exists (
       select 1
       from privado.cuentas_del_dia(r.id, privado.dia_de_negocio(r.zona_horaria, r.hora_corte, v.created_at),
                                    privado.dia_de_negocio(r.zona_horaria, r.hora_corte, v.created_at)) x
       where x.id = v.id) $$,
  'Cada cuenta sale en el día que dice privado.dia_de_negocio: una sola forma de contar el día'
);

select set_eq(
  $$ select id from privado.cuentas_del_dia('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', (select dia from tests.anclas), (select dia from tests.anclas)) $$,
  array[8101]::bigint[],
  'Las cuentas de un día son solo las de ese restaurante'
);


-- ─── Mesas ahora ──────────────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus mesas así',
  'Pepe, desde su celular, no lee Mesas ahora'
);
select throws_ok(
  $$ select public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven a su equipo así',
  'Pepe, desde su celular, no lee Tus meseros'
);
select throws_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 5) $$,
  '42501', 'Solo los gerentes de este restaurante cambian la hora de corte',
  'Pepe no cambia la hora de corte'
);
reset role;

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven los cortes y reportes',
  'Lupita, en la tableta de la caja, no lee Cortes y reportes'
);
select throws_ok(
  $$ select public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus mesas así',
  'Lupita tampoco lee Mesas ahora'
);
reset role;

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven sus mesas así',
  'El gerente de B no lee las mesas de A'
);
select throws_ok(
  $$ select public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven a su equipo así',
  'El gerente de B no lee el equipo de A'
);
select throws_ok(
  $$ select public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven los cortes y reportes',
  'El gerente de B no lee los reportes de A'
);
select throws_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 5) $$,
  '42501', 'Solo los gerentes de este restaurante cambian la hora de corte',
  'El gerente de B no cambia la hora de corte de A'
);
select is(
  jsonb_path_query_array(public.mesas_ahora('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), '$.mesas[*].venta_id'),
  '[8101]'::jsonb,
  'El gerente de B ve solo su mesa, con su cuenta'
);
reset role;

select tests.authenticate_as('gerente_a');

select is(
  jsonb_path_query_array(public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.mesas[*].id'),
  '[702, 701, 703, 704]'::jsonb,
  'Mesas ahora trae las mesas en su orden, sin la archivada'
);
select is(
  jsonb_path_query_array(public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.mesas[*].venta_id'),
  '[8002, 8001, null, null]'::jsonb,
  'Cada mesa con su cuenta abierta; la reabierta y la cancelada no ocupan la Mesa 3'
);
select is(
  public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'ocupadas',
  '2'::jsonb,
  'Hay 2 mesas ocupadas'
);
select is(
  jsonb_path_query_first(public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.mesas[1].total'),
  '113.00'::jsonb,
  'La Mesa 1 lleva $113: su descuento resta y lo cancelado no suma'
);
select is(
  (public.mesas_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'por_cobrar')::numeric,
  358.00,
  'Por cobrar es lo que falta en las mesas ocupadas: $245 de la Mesa 2 y $113 de la Mesa 1'
);


-- ─── Tus meseros ──────────────────────────────────────────────────────────────

select is(
  jsonb_path_query_array(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.personas[*].nombre'),
  '["Pepe", "Lupita", "Tono", "Beto", "Karla"]'::jsonb,
  'Salen los meseros activos y quien vendió hoy, de más a menos vendido; ni Ex, ni el gerente, ni la cocina'
);
select is(
  jsonb_path_query_first(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.personas[0]') - 'roles' - 'miembro_id',
  '{"nombre": "Pepe", "abiertas": 2, "ventas": 2, "vendido": 120.00}'::jsonb,
  'Pepe trae 2 cuentas abiertas (una reabierta) y cerró hoy 2 por $120; lo de ayer no cuenta'
);
select is(
  jsonb_path_query_first(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.personas[1]') - 'miembro_id',
  '{"nombre": "Lupita", "roles": ["caja"], "abiertas": 1, "ventas": 1, "vendido": 110.00}'::jsonb,
  'Lupita, de la caja, sale porque abrió cuentas: la Mesa 2 y un para llevar de $110'
);
select is(
  jsonb_path_query_first(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.personas[2]') - 'roles' - 'miembro_id',
  '{"nombre": "Tono", "abiertas": 0, "ventas": 1, "vendido": 22.00}'::jsonb,
  'Tono ya está de baja, pero vendió hoy: sale'
);
select is(
  jsonb_path_query_array(public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.personas[3 to 4].vendido'),
  '[0, 0]'::jsonb,
  'Beto y Karla salen en $0: la cuenta cancelada de Karla no es venta'
);
select is(
  public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'equipo',
  '{"meseros": 3, "caja": 1, "cocina": 1}'::jsonb,
  'El equipo cuenta solo a los activos de cada rol'
);
select is(
  (public.tus_meseros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'hoy')::date,
  (select dia from tests.anclas),
  'Tus meseros cuenta el día de negocio de hoy'
);


-- ─── Cortes y reportes ────────────────────────────────────────────────────────

select throws_ok(
  $$ select public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia + 1 from tests.anclas)) $$,
  '22023', 'Ese día todavía no llega',
  'Un día que no ha llegado no tiene reporte'
);
select is(
  (public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'dia')::date,
  (select dia from tests.anclas),
  'Sin decir el día, el reporte es de hoy'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.turnos[*].id'),
  '[9101]'::jsonb,
  'Hoy sale el turno que se abrió hoy'
);
select ok(
  not (public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'turnos' -> 0 ?| array['cortes', 'por_persona']),
  'Con la caja abierta el reporte no trae lo esperado ni quién cobró, tampoco al gerente'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.turnos[0].movimientos[*].motivo'),
  '["Monedas para cambio"]'::jsonb,
  'Con la caja abierta sí trae sus entradas y salidas'
);
select is(
  jsonb_path_query_first(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.turnos[0].pagos_cancelados[0]')
    - 'pago_id' - 'cancelado_at' - 'propina',
  '{"folio": 3, "cuenta": "Mesa 3", "metodo": "tarjeta", "monto": 60.00, "motivo": "Era efectivo",
    "pidio_id": 103, "pidio": "Lupita", "autorizo_id": 103, "autorizo": "Lupita"}'::jsonb,
  'Los pagos cancelados van en su turno, con su folio, su motivo y quién lo hizo'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.turnos[0].pagos_cancelados[*].folio'),
  '[3]'::jsonb,
  'Y solo los cancelados: los demás pagos del turno no salen ahí'
);
select is(
  (public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'descuentos') - 'lista',
  '{"total": 20.00, "cuentas": 1}'::jsonb,
  'Se regalaron $20 en una cuenta cerrada: $10 del renglón y 10 % de la cuenta; ni el de la Mesa 1, abierta, ni el de la gringa cancelada'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    '$.descuentos.lista[*] ? (@.venta_id == 8004).pidio'),
  '["Pepe", "Don Chuy"]'::jsonb,
  'Cada descuento dice quién lo pidió la última vez: el de Karla se reemplazó'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    '$.descuentos.lista[*].autorizo'),
  '["Lupita", "Don Chuy"]'::jsonb,
  'Y quién lo autorizó: Lupita el de Pepe; Don Chuy, el suyo'
);
select is(
  (public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'cancelaciones') - 'lista',
  '{"total": 162.00, "renglones": 3, "cuentas": 1}'::jsonb,
  'Se cancelaron $162: la jamaica de la Mesa 1, la gringa ($50 con su descuento), el taco y luego toda la cuenta de la Mesa 3'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    '$.cancelaciones.lista[*] ? (@.venta_id == 8007).importe'),
  '[22.00, 60.00]'::jsonb,
  'Los renglones que se cancelaron con su cuenta no salen aparte: la cuenta vale lo que tenía al cancelarla'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    '$.cancelaciones.lista[*] ? (@.venta_id == 8008)'),
  '[]'::jsonb,
  'Una cuenta que se juntó con otra no es una cancelación'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.cancelaciones.lista[*].autorizo_id'),
  '[103, 103, 103, 101]'::jsonb,
  'Cada cancelación dice quién la autorizó'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.otros[*].accion'),
  '["cambiar_mesa", "quitar_descuento", "juntar_mesas"]'::jsonb,
  'Otros cambios trae los de las cuentas de hoy, en orden; el cambio de mesa de ayer no'
);

select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas)), '$.turnos[*].id'),
  '[9100]'::jsonb,
  'Ayer sale el turno que se abrió ayer'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas)), '$.turnos[0].cortes[*].diferencia'),
  '[-10.00, 0.00, 0.00]'::jsonb,
  'Con la caja cerrada trae el corte de cada método'
);
select is(
  jsonb_build_object(
    'descuentos', public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas)) -> 'descuentos',
    'cancelaciones', (public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas)) -> 'cancelaciones') - 'lista'),
  '{"descuentos": {"total": 0, "cuentas": 0, "lista": []}, "cancelaciones": {"total": 30.00, "renglones": 0, "cuentas": 1}}'::jsonb,
  'Ayer: sin descuentos y una cuenta cancelada de $30'
);
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas)), '$.otros[*].detalle.a'),
  '["Mesa 4"]'::jsonb,
  'Ayer: su cambio de mesa'
);
select is(
  public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 5 from tests.anclas))
    - 'dia' - 'hoy' - 'zona' - 'hora_corte',
  '{"turnos": [], "descuentos": {"total": 0, "cuentas": 0, "lista": []},
    "cancelaciones": {"total": 0, "renglones": 0, "cuentas": 0, "lista": []}, "otros": []}'::jsonb,
  'Un día sin nada trae todo vacío y en cero'
);


-- ─── La hora de corte ─────────────────────────────────────────────────────────

select throws_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 24) $$,
  '22023', 'La hora de corte va de 0 a 23',
  'La hora de corte no pasa de 23'
);
select throws_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', -1) $$,
  '22023', 'La hora de corte va de 0 a 23',
  'Ni baja de 0'
);
select throws_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null) $$,
  '22023', 'La hora de corte va de 0 a 23',
  'Ni va vacía'
);
select lives_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 6) $$,
  'Poner la misma hora no es un error'
);
reset role;
select is(
  (select count(*) from public.bitacora where accion = 'cambiar_hora_corte')::integer, 0,
  'Y no deja nada en la bitácora'
);

select tests.authenticate_as('gerente_a');
select lives_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 5) $$,
  'Don Chuy cambia el corte a las 5:00'
);
reset role;
select is(
  (select hora_corte from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 5::smallint,
  'El restaurante queda con su corte a las 5:00'
);
select is(
  (select jsonb_build_object('miembro_id', miembro_id, 'tabla', tabla, 'registro_id', registro_id, 'detalle', detalle)
   from public.bitacora where accion = 'cambiar_hora_corte'),
  '{"miembro_id": 101, "tabla": "restaurantes", "registro_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "detalle": {"de": 6, "a": 5}}'::jsonb,
  'El cambio queda en la bitácora, con quién y la hora de antes y la nueva'
);
select ok(
  8013 in (select id from privado.cuentas_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia from tests.anclas), (select dia from tests.anclas)))
  and 8013 not in (select id from privado.cuentas_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (select dia - 1 from tests.anclas), (select dia - 1 from tests.anclas))),
  'Con el corte a las 5:00, la cuenta de las 5:30 pasa de ayer a hoy: lo pasado se reacomoda'
);

select tests.authenticate_as('gerente_a');
select is(
  jsonb_path_query_array(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '$.otros[*] ? (@.accion == "cambiar_hora_corte").quien'),
  '["Don Chuy"]'::jsonb,
  'El cambio de hora sale en Otros cambios del día en que se hizo'
);
reset role;


-- ─── Sin licencia ─────────────────────────────────────────────────────────────

update public.restaurantes set licencia_activa = false where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.authenticate_as('gerente_a');
select throws_ok(
  $$ select public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de este restaurante ven los cortes y reportes',
  'Con la licencia apagada, el gerente ya no lee los reportes'
);
select throws_ok(
  $$ select public.fijar_hora_corte('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 7) $$,
  '42501', 'Solo los gerentes de este restaurante cambian la hora de corte',
  'Ni cambia la hora de corte'
);
reset role;


select * from finish();
rollback;
