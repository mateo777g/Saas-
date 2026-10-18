-- Pruebas de lo que pide PIN (migración cancelaciones, parte 4c del punto de venta). Lo decidido
-- el 13 y el 18 de octubre de 2026: cancelar lo mandado entero o una parte, la cuenta completa o
-- un pago (que reabre la cuenta cerrada con su folio, sin ocupar su mesa, y solo mientras su turno
-- sigue abierto); descuentos en % o en pesos a un renglón o a la cuenta, sin tope, y quitarlos sin
-- PIN; el PIN de la caja o de un gerente en el aparato de otro, que cuenta para su bloqueo; lo
-- cancelado no suma y nada deja el total abajo de lo pagado; todo en la bitácora.
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
-- Se siembra como postgres, con ids fijos. A tiene a Don Chuy (gerente, con PIN), Pepe y Toño
-- (meseros, con PIN), Lupita (caja, con PIN) y el taquero (cocina); el celular de Pepe y las
-- tabletas compartidas de la caja (con su secreto, para entrar con PIN) y de la cocina. La caja
-- está abierta (turno 9101) y el turno de ayer (9100) ya se cortó. Sus cuentas: la Mesa 1 con 4
-- tacos de $22 y una jamaica de $30 ($118); la Mesa 2, una parrillada de $445 con $200 pagados
-- con tarjeta; la Mesa 3, 2 jamaicas ($60); la Mesa 6, una jamaica; la Mesa 7, 2 jamaicas; la
-- Mesa 4, cerrada hoy con folio 1 ($110: $60 en efectivo y $50 con tarjeta más $5 de propina,
-- los dos de Pepe); y la Mesa 5, cerrada ayer con folio 2. B tiene gerente y una cuenta.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  pin_gerente text := extensions.crypt(repeat('a', 64), extensions.gen_salt('bf', 4));
  pin_caja text := extensions.crypt(repeat('c', 64), extensions.gen_salt('bf', 4));
  pin_mesero text := extensions.crypt(repeat('1', 64), extensions.gen_salt('bf', 4));
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('cocina_a', 'cocina.a@prueba.test');
  perform tests.create_supabase_user('mesero2_a', 'mesero2.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo, pin_hash) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true, pin_gerente),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true, pin_mesero),
    (103, a, tests.get_supabase_uid('caja_a'), 'Lupita', '{caja}', true, pin_caja),
    (104, a, tests.get_supabase_uid('cocina_a'), 'Taquero', '{cocina}', true, null),
    (106, a, tests.get_supabase_uid('mesero2_a'), 'Toño', '{mesero}', true, pin_mesero),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true, pin_gerente);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta caja', null, tests.huella(repeat('T', 43)), '5e5e5e5e-0000-4000-8000-000000000002'),
    (a, 'Tableta cocina', null, repeat('3', 64), '5e5e5e5e-0000-4000-8000-000000000003');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Platos', 'taco'), (611, b, 'Platos B', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco de pastor', 22, true),
    (502, a, 601, 'Jamaica', 30, true),
    (503, a, 601, 'Parrillada', 445, true),
    (511, b, 611, 'Taco B', 25, true);

  insert into public.mesas (id, restaurante_id, nombre) overriding system value values
    (701, a, 'Mesa 1'), (702, a, 'Mesa 2'), (703, a, 'Mesa 3'), (704, a, 'Mesa 4'), (705, a, 'Mesa 5'),
    (706, a, 'Mesa 6'), (707, a, 'Mesa 7'), (711, b, 'Mesa B');

  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial, estado, cerrado_por, cerrado_at, created_at) overriding system value values
    (9100, a, 103, 500, 'cerrado', 103, now() - interval '20 hours', now() - interval '1 day'),
    (9101, a, 103, 500, 'abierto', null, null, now() - interval '2 hours');

  insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, abierta_por) overriding system value values
    (8001, a, 'mesa', 701, 'Mesa 1', 102),
    (8002, a, 'mesa', 702, 'Mesa 2', 102),
    (8003, a, 'mesa', 703, 'Mesa 3', 102),
    (8004, a, 'mesa', 704, 'Mesa 4', 102),
    (8005, a, 'mesa', 705, 'Mesa 5', 102),
    (8006, a, 'mesa', 706, 'Mesa 6', 102),
    (8007, a, 'mesa', 707, 'Mesa 7', 102),
    (8101, b, 'mesa', 711, 'Mesa B', 111);
  insert into public.venta_items (id, restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio) overriding system value values
    (9001, a, 8001, 501, 'Taco de pastor', 22, 4, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001'),
    (9002, a, 8001, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000001'),
    (9003, a, 8002, 503, 'Parrillada', 445, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000002'),
    (9004, a, 8003, 502, 'Jamaica', 30, 2, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000003'),
    (9005, a, 8004, 501, 'Taco de pastor', 22, 5, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000004'),
    (9006, a, 8006, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000006'),
    (9007, a, 8005, 502, 'Jamaica', 30, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000005'),
    (9008, a, 8007, 502, 'Jamaica', 30, 2, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000007'),
    (9201, b, 8101, 511, 'Taco B', 25, 1, 16, 111, 'b0b0b0b0-0000-4000-8000-000000000001');

  insert into public.pagos (id, restaurante_id, venta_id, turno_id, metodo, monto, propina, recibido, cobrado_por, clave) overriding system value values
    (9601, a, 8002, 9101, 'tarjeta', 200, 0, null, 103, 'c0c0c0c0-0000-4000-8000-000000000001'),
    (9501, a, 8004, 9101, 'efectivo', 60, 0, 60, 102, 'c0c0c0c0-0000-4000-8000-000000000002'),
    (9502, a, 8004, 9101, 'tarjeta', 50, 5, null, 102, 'c0c0c0c0-0000-4000-8000-000000000003'),
    (9503, a, 8005, 9100, 'efectivo', 30, 0, 30, 103, 'c0c0c0c0-0000-4000-8000-000000000004');
  update public.ventas set estado = 'cerrada', folio = 1, cerrada_por = 102, turno_id = 9101, cerrada_at = now() - interval '1 hour'
  where id = 8004;
  update public.ventas set estado = 'cerrada', folio = 2, cerrada_por = 103, turno_id = 9100, cerrada_at = now() - interval '21 hours'
  where id = 8005;
  insert into public.folios (restaurante_id, ultimo) values (a, 2);
end;
$$;

select plan(99);


-- ─── Permisos ─────────────────────────────────────────────────────────────────

select is_empty(
  $$ select f from unnest(array[
       'public.cancelar_renglon(bigint, integer, text, bigint, text)',
       'public.cancelar_cuenta(bigint, text, bigint, text)',
       'public.cancelar_pago(bigint, text, bigint, text)',
       'public.descontar(bigint, bigint, text, numeric, text, bigint, text)',
       'public.quitar_descuento(bigint, bigint)']) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Cancelar, descontar y quitar un descuento son de quien tiene sesión; sin sesión, nada'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.descuento(numeric, text, numeric)',
       'privado.recalcular_venta(uuid, bigint)',
       'privado.revisar_pin(bigint, text)',
       'privado.autoriza(uuid, bigint, bigint, text)']) as f,
       unnest(array['anon', 'authenticated', 'service_role']) as r
     where has_function_privilege(r, f, 'EXECUTE') $$,
  'Las funciones privadas del descuento, el total y el PIN no las llama nadie desde afuera'
);

select ok(
  has_column_privilege('authenticated', 'public.venta_items', 'estado', 'SELECT')
  and has_column_privilege('authenticated', 'public.venta_items', 'cancelado_motivo', 'SELECT')
  and has_column_privilege('authenticated', 'public.venta_items', 'descuento', 'SELECT')
  and has_column_privilege('authenticated', 'public.ventas', 'subtotal', 'SELECT')
  and has_column_privilege('authenticated', 'public.ventas', 'descuento_motivo', 'SELECT')
  and has_column_privilege('authenticated', 'public.pagos', 'cancelado_at', 'SELECT')
  and not has_column_privilege('authenticated', 'public.venta_items', 'estado', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.ventas', 'descuento_tipo', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.pagos', 'cancelado_at', 'UPDATE'),
  'Lo cancelado y lo descontado se lee, y nadie lo escribe directo'
);


-- ─── Cómo se cuenta un descuento ──────────────────────────────────────────────

select is(privado.descuento(105, 'porcentaje', 10), 10.50::numeric, 'El 10 % de $105 son $10.50');
select is(privado.descuento(33.33, 'porcentaje', 15), 5.00::numeric, 'El 15 % de $33.33 se redondea a $5');
select is(privado.descuento(30, 'pesos', 50), 30.00::numeric, 'Un descuento en pesos no pasa de lo que cuesta');
select is(privado.descuento(30, null, null), 0.00::numeric, 'Sin descuento es $0');


-- ─── Cancelar lo mandado ──────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.cancelar_renglon(9001, 1, 'Eran de suadero') $$,
  '22023', 'Falta quién autoriza con su PIN',
  'Pepe no cancela solo: pide quién autoriza'
);

select throws_ok(
  $$ select public.cancelar_renglon(9001, 1, 'Eran de suadero', 106, repeat('1', 64)) $$,
  '42501', 'Esa persona no puede autorizar: solo la caja o un gerente con PIN',
  'Otro mesero no autoriza, aunque su PIN sea bueno'
);
select throws_ok(
  $$ select public.cancelar_renglon(9001, 1, 'Eran de suadero', 111, repeat('a', 64)) $$,
  '42501', 'Esa persona no puede autorizar: solo la caja o un gerente con PIN',
  '12 · El gerente de otro restaurante no autoriza en A, aunque su PIN sea bueno'
);

select is(
  public.cancelar_renglon(9001, 1, 'Eran de suadero', 103, repeat('0', 64)),
  '{"ok": false, "motivo": "pin", "quedan": 4}'::jsonb,
  'Un PIN equivocado no es un error: dice cuántos intentos quedan'
);

reset role;
select is((select intentos_fallidos from public.miembros where id = 103), 1::smallint, 'El PIN equivocado cuenta para el bloqueo de Lupita');
select is((select cantidad from public.venta_items where id = 9001), 4, 'Con el PIN equivocado no se canceló nada');

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  public.cancelar_renglon(9001, 1, 'Eran de suadero', 103, repeat('c', 64)),
  '{"ok": true, "autoriza": 103}'::jsonb,
  'Con el PIN de Lupita, Pepe cancela 1 de los 4 tacos'
);

reset role;
select tests.guardar('cancelado', (select id from public.venta_items where venta_id = 8001 and estado = 'cancelado'));
select ok(
  exists (select 1 from public.venta_items where id = 9001 and cantidad = 3 and estado = 'activo'),
  'El renglón baja a 3'
);
select ok(
  exists (select 1 from public.venta_items v, public.venta_items o
          where v.id = tests.id('cancelado') and o.id = 9001
            and v.cantidad = 1 and v.precio_unitario = 22 and v.nombre = 'Taco de pastor'
            and v.clave_envio = o.clave_envio and v.created_at = o.created_at
            and v.comanda_id is not distinct from o.comanda_id
            and v.cancelado_por = 102 and v.autorizado_por = 103 and v.cancelado_motivo = 'Eran de suadero'
            and v.cancelado_at is not null),
  'Nace un renglón con 1, ya cancelado, con el mismo precio, clave y comanda, quién lo pidió, quién autorizó y por qué'
);
select is(
  (select subtotal::text || ' / ' || total::text from public.ventas where id = 8001),
  '96.00 / 96.00',
  'Lo cancelado no suma: la Mesa 1 queda en $96'
);
select is((select intentos_fallidos from public.miembros where id = 103), 0::smallint, 'El PIN bien puesto deja en 0 los intentos de Lupita');
select ok(
  exists (select 1 from public.bitacora
          where accion = 'cancelar_renglon' and miembro_id = 102 and autorizado_por = 103
            and registro_id = tests.id('cancelado')::text and detalle ->> 'motivo' = 'Eran de suadero'
            and (detalle ->> 'cantidad')::int = 1 and (detalle ->> 'importe')::numeric = 22),
  'La bitácora guarda quién lo pidió, quién autorizó, qué, cuánto y por qué'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.cancelar_renglon(tests.id('cancelado'), 1, 'Otra vez', 103, repeat('c', 64)) $$,
  '55000', '«Taco de pastor» ya está cancelado',
  'Lo cancelado no se vuelve a cancelar'
);
select throws_ok(
  $$ select public.cancelar_renglon(9001, 4, 'Todos', 103, repeat('c', 64)) $$,
  '22023', 'De «Taco de pastor» se cancelan de 1 a 3',
  'No se cancelan más de los que hay'
);
select throws_ok(
  $$ select public.cancelar_renglon(9001, 1, '   ', 103, repeat('c', 64)) $$,
  '22023', 'Escribe el motivo',
  'Sin motivo no se cancela'
);
select throws_ok(
  $$ select public.cancelar_renglon(9003, 1, 'Ya no la quieren', 103, repeat('0', 64)) $$,
  '55000', 'Ya se pagaron $200.00. Cancela antes un pago.',
  'La Mesa 2 ya pagó $200: cancelar la parrillada la dejaría abajo de lo pagado'
);

reset role;
select is((select intentos_fallidos from public.miembros where id = 103), 0::smallint, 'Si no cabe, el PIN ni se revisa: no cuenta como intento');

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select is(
  public.cancelar_renglon(9002, 1, 'Se anotó mal'),
  '{"ok": true, "autoriza": 103}'::jsonb,
  'Lupita es de la caja: cancela sin otro PIN y queda a su nombre'
);

reset role;
select ok(
  exists (select 1 from public.venta_items
          where id = 9002 and cantidad = 1 and estado = 'cancelado' and cancelado_por = 103 and autorizado_por = 103)
  and (select count(*) from public.venta_items where venta_id = 8001) = 3,
  'Cancelar todo un renglón no crea otro: el mismo queda cancelado'
);
select is((select total from public.ventas where id = 8001), 66.00::numeric, 'La Mesa 1 queda en $66');

select tests.authenticate_as('gerente_a');
select is(
  public.cancelar_renglon(9008, 1, 'Se derramó'),
  '{"ok": true, "autoriza": 101}'::jsonb,
  'Don Chuy, desde su panel, cancela sin PIN'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('c', 64)) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante cancelan',
  'La cocina no cancela'
);

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.cancelar_renglon(9008, 1, 'Probando') $$,
  '23503', 'Ese producto ya no está en la cuenta',
  '12 · El gerente de B no cancela lo de A'
);

select tests.authenticate_as('mesero_a');
select throws_ok(
  $$ select public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('c', 64)) $$,
  '23503', 'Ese producto ya no está en la cuenta',
  'Fuera de su celular, Pepe no cancela nada'
);


-- ─── Descuentos ───────────────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  public.descontar(8001, 9001, 'porcentaje', 10, 'Cliente de siempre', 101, repeat('a', 64)),
  '{"ok": true, "autoriza": 101}'::jsonb,
  'Con el PIN de Don Chuy, Pepe le hace 10 % a los tacos'
);

reset role;
select is(
  (select descuento::text || ' / ' || importe::text from public.venta_items where id = 9001),
  '6.60 / 59.40',
  'El 10 % de 3 tacos ($66) son $6.60, y el renglón queda en $59.40'
);
select is(
  (select subtotal::text || ' / ' || descuento::text || ' / ' || total::text from public.ventas where id = 8001),
  '59.40 / 0.00 / 59.40',
  'El subtotal ya trae el descuento del renglón'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(
  public.descontar(8001, null, 'porcentaje', 10, 'Cumpleaños'),
  '{"ok": true, "autoriza": 103}'::jsonb,
  'Lupita le hace 10 % a toda la cuenta'
);

reset role;
select is(
  (select subtotal::text || ' / ' || descuento::text || ' / ' || total::text from public.ventas where id = 8001),
  '59.40 / 5.94 / 53.46',
  'El 10 % de la cuenta va sobre el subtotal: $5.94'
);

-- Pepe manda otro taco (lo hace mandar_a_cocina; aquí, como postgres).
insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, agregado_por, clave_envio)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 8001, 501, 'Taco de pastor', 22, 1, 16, 102, 'a0a0a0a0-0000-4000-8000-000000000011');
select is(
  (select subtotal::text || ' / ' || descuento::text || ' / ' || total::text from public.ventas where id = 8001),
  '81.40 / 8.14 / 73.26',
  'Lo que se agrega después también lleva el 10 % de la cuenta'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  $$ select public.descontar(8001, 9001, 'pesos', 100, 'Promoción') $$,
  '22023', 'El descuento no puede pasar de $66.00',
  'Un descuento en pesos no pasa de lo que cuesta el renglón'
);
select throws_ok(
  $$ select public.descontar(8001, null, 'porcentaje', 120, 'Promoción') $$,
  '22023', 'El descuento va de 1 a 100 %',
  'Un descuento en % no pasa de 100'
);
select throws_ok(
  $$ select public.descontar(8001, null, '2x1', 10, 'Promoción') $$,
  '22023', 'Elige si el descuento es en % o en pesos',
  'Solo hay descuentos en % o en pesos'
);
select throws_ok(
  $$ select public.descontar(8001, null, 'porcentaje', 10, '') $$,
  '22023', 'Escribe el motivo',
  'Sin motivo no hay descuento'
);
select throws_ok(
  $$ select public.descontar(8002, 9003, 'porcentaje', 100, 'Regalo') $$,
  '55000', 'Ya se pagaron $200.00. Cancela antes un pago.',
  'Un descuento tampoco deja la cuenta abajo de lo pagado'
);
select is(
  public.descontar(8006, 9006, 'porcentaje', 100, 'Cliente de siempre'),
  '{"ok": true, "autoriza": 103}'::jsonb,
  'Regalar la jamaica es 100 %'
);
select is(
  public.descontar(8001, null, 'pesos', 5, 'Cambio de opinión'),
  '{"ok": true, "autoriza": 103}'::jsonb,
  'Un descuento nuevo a la cuenta, ahora en pesos'
);

reset role;
select is((select total from public.ventas where id = 8006), 0.00::numeric, 'La Mesa 6 queda en $0');
select is(
  (select descuento_tipo || ' / ' || descuento::text || ' / ' || total::text from public.ventas where id = 8001),
  'pesos / 5.00 / 76.40',
  'El descuento nuevo reemplaza al anterior'
);
select ok(
  exists (select 1 from public.bitacora
          where accion = 'descontar' and tabla = 'ventas' and registro_id = '8001' and miembro_id = 103
            and detalle ->> 'tipo' = 'pesos' and detalle ->> 'antes' = 'porcentaje'),
  'La bitácora guarda el descuento y el que había antes'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select lives_ok($$ select public.quitar_descuento(8001) $$, 'Pepe quita el descuento de la cuenta sin PIN');

reset role;
select is(
  (select coalesce(descuento_tipo, 'sin descuento') || ' / ' || total::text from public.ventas where id = 8001),
  'sin descuento / 81.40',
  'Sin el descuento, la cuenta vuelve a $81.40'
);
select ok(
  exists (select 1 from public.bitacora
          where accion = 'quitar_descuento' and miembro_id = 102 and autorizado_por is null
            and detalle ->> 'tipo' = 'pesos' and detalle ->> 'motivo' = 'Cambio de opinión'),
  'Quitarlo queda en la bitácora, con el que había'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.quitar_descuento(8001) $$,
  '55000', 'Esta cuenta no tiene descuento',
  'No se quita un descuento que no hay'
);
select throws_ok(
  $$ select public.descontar(8001, tests.id('cancelado'), 'porcentaje', 10, 'Promoción', 101, repeat('a', 64)) $$,
  '55000', '«Taco de pastor» está cancelado: no se descuenta',
  'Lo cancelado no se descuenta'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(
  public.cancelar_renglon(9001, 1, 'Eran dos'),
  '{"ok": true, "autoriza": 103}'::jsonb,
  'Lupita cancela 1 de los 3 tacos con 10 %'
);

reset role;
select ok(
  exists (select 1 from public.venta_items
          where venta_id = 8001 and estado = 'cancelado' and cancelado_motivo = 'Eran dos' and cantidad = 1
            and descuento_tipo = 'porcentaje' and descuento_valor = 10 and importe = 19.80),
  'El renglón cancelado se lleva el 10 %: valía $19.80'
);
select is(
  (select importe::text || ' / ' || v.total::text from public.venta_items i join public.ventas v on v.id = i.venta_id where i.id = 9001),
  '39.60 / 61.60',
  'Los 2 tacos que siguen quedan en $39.60 y la cuenta en $61.60'
);


-- ─── Cancelar la cuenta ───────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  public.cancelar_cuenta(8003, 'Se fue sin pagar', 101, repeat('a', 64)),
  '{"ok": true, "autoriza": 101}'::jsonb,
  'Con el PIN de Don Chuy, Pepe cancela la Mesa 3'
);

reset role;
select ok(
  exists (select 1 from public.ventas where id = 8003 and estado = 'cancelada' and cancelada_motivo = 'Se fue sin pagar' and total = 0)
  and not exists (select 1 from public.venta_items where venta_id = 8003 and estado = 'activo')
  and exists (select 1 from public.venta_items where venta_id = 8003 and cancelado_motivo = 'Se fue sin pagar' and autorizado_por = 101),
  'La cuenta queda cancelada con su motivo, y todos sus renglones también'
);
select ok(
  exists (select 1 from public.bitacora
          where accion = 'cancelar_cuenta' and registro_id = '8003' and miembro_id = 102 and autorizado_por = 101
            and (detalle ->> 'total')::numeric = 60 and detalle ->> 'cuenta' = 'Mesa 3'),
  'La bitácora guarda la cuenta, cuánto era y por qué'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.cancelar_cuenta(8002, 'Se fue', 101, repeat('a', 64)) $$,
  '55000', 'Esta cuenta tiene pagos ($200.00). Cancélalos antes.',
  'Una cuenta con pagos no se cancela'
);
select throws_ok(
  $$ select public.cancelar_cuenta(8003, 'Otra vez', 101, repeat('a', 64)) $$,
  '55000', 'Esa cuenta ya no está abierta',
  'Una cuenta cancelada no se vuelve a cancelar'
);
select isnt(
  public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0d0d0d0-0000-4000-8000-000000000001',
                         '[{"producto_id": 501, "cantidad": 1}]', null, 703),
  8003::bigint,
  'La Mesa 3 quedó libre: el siguiente pedido abre otra cuenta'
);


-- ─── Cancelar un pago ─────────────────────────────────────────────────────────

select throws_ok(
  $$ select public.cancelar_pago(9502, 'Era efectivo') $$,
  '22023', 'Falta quién autoriza con su PIN',
  'Pepe no cancela un pago solo'
);
select is(public.mi_efectivo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 60.00::numeric, 'Pepe trae los $60 en efectivo de la Mesa 4');

select tests.authenticate_as('gerente_b');
select throws_ok(
  $$ select public.cancelar_pago(9601, 'Probando') $$,
  '23503', 'Ese pago ya no está',
  '12 · El gerente de B no cancela los pagos de A'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(
  public.cancelar_pago(9502, 'Era efectivo, no tarjeta'),
  '{"ok": true, "autoriza": 103, "reabierta": true}'::jsonb,
  'Lupita cancela la tarjeta de la Mesa 4, que ya estaba cerrada, y la cuenta se reabre'
);

reset role;
select ok(
  exists (select 1 from public.ventas
          where id = 8004 and estado = 'abierta' and folio = 1 and pagado = 60
            and cerrada_at is null and cerrada_por is null and turno_id is null),
  'Se reabre con el mismo folio, y le faltan $50'
);
select ok(
  exists (select 1 from public.pagos
          where id = 9502 and cancelado_at is not null and cancelado_por = 103 and autorizado_por = 103
            and cancelado_motivo = 'Era efectivo, no tarjeta'),
  'El pago queda cancelado, con quién, quién autorizó y por qué'
);
select is(privado.esperado(9101, 'tarjeta'), 200.00::numeric, 'El pago cancelado no cuenta en lo esperado del corte');
select ok(
  not exists (select 1 from privado.propinas_del_turno(9101) where miembro_id = 102),
  'Su propina de $5 deja de contar para Pepe'
);
select ok(
  exists (select 1 from public.bitacora
          where accion = 'cancelar_pago' and registro_id = '9502' and miembro_id = 103
            and (detalle ->> 'reabierta')::boolean and (detalle ->> 'folio')::int = 1 and (detalle ->> 'monto')::numeric = 50),
  'La bitácora guarda el pago cancelado y que la cuenta se reabrió'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select isnt(
  public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0d0d0d0-0000-4000-8000-000000000002',
                         '[{"producto_id": 501, "cantidad": 1}]', null, 704),
  8004::bigint,
  'La cuenta reabierta no ocupa la Mesa 4: la familia nueva abre la suya'
);
select throws_ok(
  $$ select public.cambiar_mesa(8004, 705) $$,
  '55000', 'Una cuenta reabierta ya no ocupa mesa: se cobra desde la caja',
  'Una cuenta reabierta no cambia de mesa'
);
select throws_ok(
  $$ select public.juntar_mesas(8004, 8001) $$,
  '55000', 'Una cuenta reabierta no se junta con otra',
  'Una cuenta reabierta no se junta'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(
  public.cancelar_pago(9501, 'Se anotó dos veces') ->> 'reabierta',
  'false',
  'Cancelar un pago de una cuenta abierta no la reabre: ya lo estaba'
);
select throws_ok(
  $$ select public.cancelar_pago(9502, 'Otra vez') $$,
  '55000', 'Ese pago ya está cancelado',
  'Un pago cancelado no se vuelve a cancelar'
);
select throws_ok(
  $$ select public.cancelar_pago(9503, 'Era tarjeta') $$,
  '55000', 'Ese pago es de un turno que ya se cortó',
  'Un pago de un turno ya cortado no se cancela: el corte no cambia'
);
select is(
  public.cobrar(8004, 'c0b0a000-0000-4000-8000-000000000001', 'efectivo', 110, null, null, 110) ->> 'folio',
  '1',
  'Con el pago correcto, la cuenta reabierta se cierra con su mismo folio'
);

reset role;
select is((select ultimo from public.folios where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 2, 'El folio no avanza');

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is(public.mi_efectivo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 0.00::numeric, 'Pepe ya no trae los $60 del pago cancelado');


-- ─── El bloqueo al quinto PIN equivocado ──────────────────────────────────────

select is(public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('0', 64)) ->> 'quedan', '4', 'Primer PIN equivocado: quedan 4');
select is(public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('0', 64)) ->> 'quedan', '3', 'Segundo: quedan 3');
select is(public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('0', 64)) ->> 'quedan', '2', 'Tercero: quedan 2');
select is(public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('0', 64)) ->> 'quedan', '1', 'Cuarto: queda 1');
select is(public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('0', 64)) ->> 'motivo', 'bloqueado', 'Al quinto, Lupita queda con bloqueo');

reset role;
select ok(
  (select bloqueado_hasta > now() and bloqueado_hasta <= now() + interval '15 minutes' from public.miembros where id = 103),
  'El bloqueo dura 15 minutos'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is(
  public.cancelar_renglon(9008, 1, 'Probando', 103, repeat('c', 64)) ->> 'motivo',
  'bloqueado',
  'Con el bloqueo, ni su PIN bueno autoriza'
);

select tests.como_worker();
select is(
  public.entrar_con_pin(repeat('T', 43), 103, repeat('c', 64)) ->> 'motivo',
  'bloqueado',
  'El bloqueo también le cierra la tableta de la caja'
);

reset role;
select ok(
  exists (select 1 from public.venta_items where id = 9008 and cantidad = 1 and estado = 'activo'),
  'Ningún PIN equivocado canceló nada'
);


-- ─── Quién lee lo cancelado ───────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is(
  (select count(*) from public.venta_items where venta_id = 8001 and estado = 'cancelado'),
  3::bigint,
  'Pepe ve lo cancelado de la Mesa 1, para tacharlo'
);
select is(
  (select cancelado_motivo from public.pagos where id = 9502),
  'Era efectivo, no tarjeta',
  'Y el pago cancelado, con su motivo'
);
select is((select count(*) from public.bitacora), 0::bigint, 'La bitácora no la lee el mesero');

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select is(
  (select cancelado_motivo from public.venta_items where id = 9002),
  'Se anotó mal',
  'La cocina lee el motivo de lo cancelado'
);

select tests.authenticate_as('gerente_a');
select is(
  (select count(*) from public.bitacora where accion in ('cancelar_renglon', 'cancelar_cuenta', 'cancelar_pago', 'descontar', 'quitar_descuento')),
  12::bigint,
  'Don Chuy ve en la bitácora todo lo que se canceló y descontó'
);

select tests.authenticate_as('gerente_b');
select is(
  (select count(*) from public.venta_items where estado = 'cancelado'),
  0::bigint,
  '12 · El gerente de B no ve lo cancelado de A'
);


-- ─── Lo que la base no deja aunque se escriba directo ─────────────────────────

reset role;
select throws_ok(
  $$ update public.ventas set pagado = 1000 where id = 8001 $$,
  '23514', null,
  'Lo pagado nunca pasa del total'
);
select throws_ok(
  $$ update public.ventas set total = 1 where id = 8001 $$,
  '23514', null,
  'El total siempre es el subtotal menos el descuento'
);
select throws_ok(
  $$ update public.venta_items set estado = 'cancelado' where id = 9008 $$,
  '23514', null,
  'Un renglón no se cancela sin quién lo pidió, quién autorizó, motivo y hora'
);
select throws_ok(
  $$ update public.pagos set cancelado_at = now() where id = 9601 $$,
  '23514', null,
  'Un pago no se cancela sin quién, quién autorizó y motivo'
);
select throws_ok(
  $$ update public.ventas set descuento_tipo = 'porcentaje', descuento_valor = 150, descuento_motivo = 'x' where id = 8001 $$,
  '23514', null,
  'Un descuento en % no pasa de 100'
);

select * from finish();
rollback;
