-- Pruebas de la migración datos_de_clientes (21 de noviembre de 2026; planes/trabajo/datos-de-clientes/): el nombre
-- legal en Tu restaurante y en el menú; la marca de «datos borrados» en los pedidos y las cuentas, con las reglas de
-- teléfono y dirección que siguen protegiendo lo nuevo; lo que vacía el pg_cron cada noche (90 días, 7 si se
-- rechazó; nunca un pedido por confirmar ni una cuenta abierta), y «Borrar los datos de un cliente» de Ajustes, solo
-- del gerente, por sucursal, con su renglón en la bitácora sin el teléfono.
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
-- Se siembra como postgres, con ids fijos. A es la fonda de Don Chuy (México, corte a las 6): recibe pedidos ahora
-- (su horario va de 3 horas antes a 3 horas después de este momento), hace envíos. En A: Don Chuy (gerente), Pepe
-- (mesero) y Lupita (caja), los dos en su aparato. B es otro restaurante con su gerente.
-- Rosa pide con el 222 987 6543; Mario con el 555 123 4567. Los pedidos y las cuentas de días pasados se siembran
-- directo, con su día: el de los pedidos es su columna dia; el de las cuentas, el día de negocio de su created_at.

-- Un momento del día de negocio p_dia de A: dos horas después de su corte.
create function tests.momento(p_dia date)
returns timestamptz
language sql
stable
as $$
  select privado.inicio_de_dia('America/Mexico_City', 6::smallint, p_dia) + interval '2 hours'
$$;

-- Lo que guarda un pedido de quien pidió, y si lleva la marca.
create function tests.pedido(p_id bigint)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object('telefono', cliente_telefono, 'direccion', cliente_direccion,
                            'referencias', cliente_referencias, 'borrado', datos_borrados_at is not null)
  from public.pedidos_en_linea where id = p_id
$$;

-- Lo mismo de una cuenta.
create function tests.cuenta(p_id bigint)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object('telefono', cliente_telefono, 'direccion', cliente_direccion,
                            'borrado', datos_borrados_at is not null)
  from public.ventas where id = p_id
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Como en producción, la sesión corre en UTC: así una hora sin zona se notaría.
set local time zone 'UTC';

do $$
declare
  hoy date := privado.dia_de_negocio('America/Mexico_City', 6::smallint);
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_local timestamp := now() at time zone 'America/Mexico_City';
  r text := '2229876543';
  m text := '5551234567';
  x text := repeat('a', 64);
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, telefono,
                                   direccion, hace_envios) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 300, hoy + 30, '2221234567', 'Av. Juárez 10, Puebla', true),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 300, hoy + 30, '2227654321', null, false);

  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select a, d, date_trunc('minute', v_local - interval '3 hours')::time, date_trunc('minute', v_local + interval '3 hours')::time
  from generate_series(1, 7) as d;

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo, pin_hash) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true, null),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true, 'pin'),
    (103, a, tests.get_supabase_uid('caja_a'), 'Lupita', '{caja}', true, 'pin'),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true, null);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, privado.huella_aparato(repeat('P', 43)), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Caja de Lupita', 103, privado.huella_aparato(repeat('L', 43)), '5e5e5e5e-0000-4000-8000-000000000003');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values (601, a, 'Tacos', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio) overriding system value values
    (501, a, 601, 'Taco al pastor', 22);
  insert into public.mesas (id, restaurante_id, nombre) overriding system value values (801, a, 'Mesa 1');

  -- Un turno viejo, ya cerrado, para las cuentas cerradas del punto de venta.
  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial, estado, cerrado_por, cerrado_at, created_at)
  overriding system value values (901, a, 101, 500, 'cerrado', 101, tests.momento(hoy - 200), tests.momento(hoy - 200));

  -- Las cuentas. Del menú en línea: 1001 a domicilio de hace 90 días y 1002 para llevar de hace 89, cerradas; 1006 a
  -- domicilio de hace 120, todavía abierta. Del punto de venta, a domicilio: 1008 abierta en el último segundo del día
  -- de hace 90 y cerrada al día siguiente, con el teléfono escrito con espacios; 1009 cancelada de hace 91, con +52; 1010 cerrada en el primer
  -- segundo del día de hace 89; 1012 abierta de hace 150; 1013 cerrada de hace 3, de Mario. 1011 en mesa, de hace 200,
  -- sin nada que vaciar. En B: 1101 para llevar del menú, de hace 10, cerrada, de Rosa.
  insert into public.ventas (id, restaurante_id, origen, tipo, mesa_id, mesa_nombre, cliente_nombre, cliente_telefono,
                             cliente_direccion, estado, folio, cerrada_at, cerrada_por, turno_id, pedido_numero,
                             cancelada_motivo, abierta_por, created_at)
  overriding system value values
    (1001, a, 'menu_en_linea', 'domicilio', null, null, 'Rosa Ramírez', r, 'Calle 1 · Portón verde', 'cerrada', 9001,
     tests.momento(hoy - 90), null, null, 91, null, 101, tests.momento(hoy - 90)),
    (1002, a, 'menu_en_linea', 'para_llevar', null, null, 'Rosa Ramírez', r, null, 'cerrada', 9002,
     tests.momento(hoy - 89), null, null, 92, null, 101, tests.momento(hoy - 89)),
    (1006, a, 'menu_en_linea', 'domicilio', null, null, 'Rosa Ramírez', r, 'Calle 6', 'abierta', null,
     null, null, null, 96, null, 101, tests.momento(hoy - 120)),
    (1008, a, 'punto_de_venta', 'domicilio', null, null, 'Sra. Ramírez', '222 987 6543', 'Calle 8', 'cerrada', 9008,
     privado.inicio_de_dia('America/Mexico_City', 6::smallint, hoy - 89) + interval '1 hour', 101, 901, null, null, 101,
     privado.inicio_de_dia('America/Mexico_City', 6::smallint, hoy - 89) - interval '1 second'),
    (1009, a, 'punto_de_venta', 'domicilio', null, null, 'Sra. Ramírez', '+52 222 987 6543', 'Calle 9', 'cancelada', null,
     null, null, null, null, 'No llegó', 101, tests.momento(hoy - 91)),
    (1010, a, 'punto_de_venta', 'domicilio', null, null, 'Sra. Ramírez', '222-987-6543', 'Calle 10', 'cerrada', 9010,
     tests.momento(hoy - 89), 101, 901, null, null, 101,
     privado.inicio_de_dia('America/Mexico_City', 6::smallint, hoy - 89)),
    (1011, a, 'punto_de_venta', 'mesa', 801, 'Mesa 1', null, null, null, 'cerrada', 9011,
     tests.momento(hoy - 200), 101, 901, null, null, 101, tests.momento(hoy - 200)),
    (1012, a, 'punto_de_venta', 'domicilio', null, null, 'Sra. Ramírez', r, 'Calle 12', 'abierta', null,
     null, null, null, null, null, 101, tests.momento(hoy - 150)),
    (1013, a, 'punto_de_venta', 'domicilio', null, null, 'Mario', m, 'Calle 13', 'cerrada', 9013,
     tests.momento(hoy - 3), 101, 901, null, null, 101, tests.momento(hoy - 3)),
    (1101, b, 'menu_en_linea', 'para_llevar', null, null, 'Rosa Ramírez', r, null, 'cerrada', 9101,
     tests.momento(hoy - 10), null, null, 11, null, 111, tests.momento(hoy - 10));

  -- Los pedidos. De Rosa: 2001 a domicilio confirmado hace 90 días (cuenta 1001), 2002 para llevar confirmado hace 89
  -- (1002), 2005 por confirmar de hoy, 2006 a domicilio confirmado hace 120 con su cuenta abierta (1006), 2007 para
  -- llevar rechazado hace 2. De Mario: 2003 a domicilio rechazado hace 7, 2004 para llevar rechazado hace 6, 2015 para
  -- llevar por confirmar de hace 95 (el cierre del día nunca pasó). En B: 2101 a domicilio rechazado hace 30 y 2102
  -- para llevar confirmado hace 10 (1101), de Rosa.
  insert into public.pedidos_en_linea (id, restaurante_id, dia, numero, tipo, cliente_nombre, cliente_telefono,
                                       cliente_direccion, cliente_referencias, paga_con, total, estado, venta_id,
                                       atendido_por, atendido_at, rechazo_motivo, clave, marca_celular, marca_conexion)
  overriding system value values
    (2001, a, hoy - 90, 91, 'domicilio', 'Rosa Ramírez', r, 'Calle 1', 'Portón verde', 200, 100, 'confirmado', 1001,
     101, tests.momento(hoy - 90), null, gen_random_uuid(), x, x),
    (2002, a, hoy - 89, 92, 'para_llevar', 'Rosa Ramírez', r, null, null, null, 50, 'confirmado', 1002,
     101, tests.momento(hoy - 89), null, gen_random_uuid(), x, x),
    (2003, a, hoy - 7, 93, 'domicilio', 'Mario', m, 'Calle 3', null, null, 80, 'rechazado', null,
     101, tests.momento(hoy - 7), 'Sin repartidor', gen_random_uuid(), x, x),
    (2004, a, hoy - 6, 94, 'para_llevar', 'Mario', m, null, null, null, 40, 'rechazado', null,
     null, tests.momento(hoy - 6), 'No se confirmó', gen_random_uuid(), x, x),
    (2005, a, hoy, 95, 'domicilio', 'Rosa Ramírez', r, 'Calle 5', 'Casa roja', null, 60, 'por_confirmar', null,
     null, null, null, gen_random_uuid(), x, x),
    (2006, a, hoy - 120, 96, 'domicilio', 'Rosa Ramírez', r, 'Calle 6', null, null, 70, 'confirmado', 1006,
     101, tests.momento(hoy - 120), null, gen_random_uuid(), x, x),
    (2007, a, hoy - 2, 97, 'para_llevar', 'Rosa Ramírez', r, null, null, null, 30, 'rechazado', null,
     101, tests.momento(hoy - 2), 'Ya cerramos', gen_random_uuid(), x, x),
    (2015, a, hoy - 95, 98, 'para_llevar', 'Mario', m, null, null, null, 25, 'por_confirmar', null,
     null, null, null, gen_random_uuid(), x, x),
    (2101, b, hoy - 30, 11, 'domicilio', 'Rosa Ramírez', r, 'Calle B', null, null, 90, 'rechazado', null,
     null, tests.momento(hoy - 30), 'No se confirmó', gen_random_uuid(), x, x),
    (2102, b, hoy - 10, 12, 'para_llevar', 'Rosa Ramírez', r, null, null, null, 35, 'confirmado', 1101,
     111, tests.momento(hoy - 10), null, gen_random_uuid(), x, x);
end;
$$;

select plan(83);


-- ─── Las columnas, sus reglas y sus permisos ──────────────────────────────────

select ok(
  has_column_privilege('authenticated', 'public.restaurantes', 'nombre_legal', 'SELECT')
  and has_column_privilege('authenticated', 'public.pedidos_en_linea', 'datos_borrados_at', 'SELECT')
  and has_column_privilege('authenticated', 'public.ventas', 'datos_borrados_at', 'SELECT'),
  'El equipo lee el nombre legal y la marca de los pedidos y las cuentas (cada tabla, con su RLS)'
);

select ok(
  not has_column_privilege('authenticated', 'public.restaurantes', 'nombre_legal', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.pedidos_en_linea', 'datos_borrados_at', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.ventas', 'datos_borrados_at', 'UPDATE')
  and not has_column_privilege('anon', 'public.restaurantes', 'nombre_legal', 'SELECT'),
  'Nadie las escribe directo, y sin sesión no se leen'
);

select throws_ok(
  $$ update public.restaurantes set nombre_legal = '   ' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '23514', 'new row for relation "restaurantes" violates check constraint "restaurantes_nombre_legal_formato"',
  'El nombre legal no va en blanco (en blanco es nulo)'
);

select throws_ok(
  $$ update public.restaurantes set nombre_legal = repeat('a', 121) where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '23514', 'new row for relation "restaurantes" violates check constraint "restaurantes_nombre_legal_formato"',
  'Hasta 120 letras'
);

select lives_ok(
  $$ update public.restaurantes set nombre_legal = repeat('a', 120) where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'Con 120 sí'
);

select throws_ok(
  $$ update public.pedidos_en_linea set datos_borrados_at = now() where id = 2003 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_datos_borrados"',
  'Un pedido con la marca ya no lleva teléfono, dirección ni referencias'
);

select throws_ok(
  $$ update public.pedidos_en_linea set datos_borrados_at = now() where id = 2004 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_datos_borrados"',
  'Ni el teléfono solo'
);

select throws_ok(
  $$ update public.pedidos_en_linea set cliente_telefono = null, cliente_direccion = null, datos_borrados_at = now()
     where id = 2001 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_datos_borrados"',
  'Ni las referencias solas'
);

select throws_ok(
  $$ update public.pedidos_en_linea set cliente_referencias = null, cliente_direccion = null, cliente_telefono = null,
       datos_borrados_at = now() where id = 2005 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_datos_borrados"',
  'Uno por confirmar nunca lleva la marca'
);

select throws_ok(
  $$ update public.pedidos_en_linea set cliente_telefono = null, cliente_direccion = null where id = 2003 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_domicilio"',
  'Sin la marca, a domicilio sigue pidiendo teléfono y dirección'
);

select throws_ok(
  $$ update public.pedidos_en_linea set cliente_telefono = null where id = 2004 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_telefono_para_llevar"',
  'Y para llevar, el teléfono'
);

select throws_ok(
  $$ insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, total, estado, atendido_at,
                                          rechazo_motivo, clave, marca_celular, marca_conexion, datos_borrados_at)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', current_date, 80, 'domicilio', 'Sin datos', 25, 'rechazado', now(),
             'Falso', gen_random_uuid(), repeat('e', 64), repeat('e', 64), null) $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_domicilio"',
  'Un pedido nuevo a domicilio sin teléfono ni dirección no entra'
);

select throws_ok(
  $$ update public.pedidos_en_linea set paga_con = 100, cliente_telefono = null, datos_borrados_at = now() where id = 2004 $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_domicilio"',
  'Con la marca, para llevar sigue sin «paga con»'
);

select throws_ok(
  $$ update public.ventas set datos_borrados_at = now() where id = 1013 $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_datos_borrados"',
  'Una cuenta con la marca ya no lleva teléfono ni dirección'
);

select throws_ok(
  $$ update public.ventas set datos_borrados_at = now() where id = 1002 $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_datos_borrados"',
  'Ni el teléfono solo'
);

select throws_ok(
  $$ update public.ventas set cliente_telefono = null, cliente_direccion = null where id = 1013 $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_domicilio"',
  'Sin la marca, una cuenta a domicilio sigue pidiendo teléfono y dirección'
);

select throws_ok(
  $$ update public.ventas set cliente_direccion = 'Calle' where id = 1011 $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_domicilio"',
  'Una cuenta de mesa no lleva dirección'
);

select throws_ok(
  $$ update public.ventas set cliente_direccion = 'Calle', datos_borrados_at = now() where id = 1011 $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_datos_borrados"',
  'Ni con la marca una cuenta de mesa lleva dirección'
);

select is(
  (select array[schedule, command] from cron.job where jobname = 'vaciar-datos-de-clientes'),
  array['0 9 * * *', 'select privado.vaciar_datos_viejos()'],
  'El pg_cron vacía los datos viejos cada noche, a las 9:00 UTC (las 3:00 en México)'
);

select is(
  array[privado.dias_que_se_guardan(false), privado.dias_que_se_guardan(true)],
  array[90, 7],
  'Se guardan 90 días; los de un pedido rechazado, 7'
);


-- ─── Los permisos de las funciones ────────────────────────────────────────────

select is_empty(
  $$ select f from unnest(array[
       'public.buscar_datos_cliente(uuid, text)',
       'public.borrar_datos_cliente(uuid, text)',
       'public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean, text)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Las tres del gerente las llama quien tiene sesión, y cada una revisa quién es; sin sesión ni el Worker'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.dias_que_se_guardan(boolean)',
       'privado.vaciar_datos_viejos()',
       'privado.datos_de_un_cliente(uuid, text)',
       'privado.telefono_del_cliente(text)'
     ]) as f, unnest(array['anon', 'authenticated', 'service_role']) as rol
     where has_function_privilege(rol, f, 'EXECUTE') $$,
  'Las de adentro no las llama nadie de afuera'
);

select ok(
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'guardar_restaurante' and p.pronargs <> 8),
  'guardar_restaurante tiene una sola forma, la de 8'
);


-- ─── Lo que vacía el pg_cron cada noche ───────────────────────────────────────

select is(privado.vaciar_datos_viejos(), 6, 'La primera noche vacía 3 pedidos y 3 cuentas');

select is(tests.pedido(2001), '{"telefono": null, "direccion": null, "referencias": null, "borrado": true}'::jsonb,
          'El pedido a domicilio confirmado hace 90 días se vacía');
select is((select jsonb_build_object('nombre', cliente_nombre, 'paga_con', paga_con, 'total', total, 'numero', numero,
                                     'estado', estado, 'venta', venta_id)
           from public.pedidos_en_linea where id = 2001),
          '{"nombre": "Rosa Ramírez", "paga_con": 200, "total": 100, "numero": 91, "estado": "confirmado", "venta": 1001}'::jsonb,
          'Y se queda con su nombre, «paga con», su total, su número y su cuenta');
select is(tests.cuenta(1001), '{"telefono": null, "direccion": null, "borrado": true}'::jsonb,
          'Su cuenta de hace 90 días también');
select is((select jsonb_build_object('nombre', cliente_nombre, 'folio', folio, 'estado', estado)
           from public.ventas where id = 1001),
          '{"nombre": "Rosa Ramírez", "folio": 9001, "estado": "cerrada"}'::jsonb,
          'La cuenta nunca se borra: nombre, folio y estado se quedan');
select is(tests.pedido(2002), '{"telefono": "2229876543", "direccion": null, "referencias": null, "borrado": false}'::jsonb,
          'El confirmado de hace 89 días se queda');
select is(tests.cuenta(1002), '{"telefono": "2229876543", "direccion": null, "borrado": false}'::jsonb,
          'Su cuenta de hace 89 también');
select is(tests.pedido(2003), '{"telefono": null, "direccion": null, "referencias": null, "borrado": true}'::jsonb,
          'El rechazado de hace 7 días se vacía');
select is(tests.pedido(2004), '{"telefono": "5551234567", "direccion": null, "referencias": null, "borrado": false}'::jsonb,
          'El rechazado de hace 6 se queda');
select is(tests.pedido(2015), '{"telefono": "5551234567", "direccion": null, "referencias": null, "borrado": false}'::jsonb,
          'Uno por confirmar no se toca, aunque sea viejo');
select is(tests.pedido(2006), '{"telefono": "2229876543", "direccion": "Calle 6", "referencias": null, "borrado": false}'::jsonb,
          'Ni el confirmado cuya cuenta sigue abierta');
select is(tests.cuenta(1006), '{"telefono": "2229876543", "direccion": "Calle 6", "borrado": false}'::jsonb,
          'Ni esa cuenta abierta');
select is(tests.cuenta(1012), '{"telefono": "2229876543", "direccion": "Calle 12", "borrado": false}'::jsonb,
          'Ni una abierta del punto de venta de hace 150 días');
select is(tests.cuenta(1008), '{"telefono": null, "direccion": null, "borrado": true}'::jsonb,
          'Una del punto de venta abierta en el último segundo del día de hace 90 se vacía, aunque se cerró al otro día');
select is(tests.cuenta(1010), '{"telefono": "222-987-6543", "direccion": "Calle 10", "borrado": false}'::jsonb,
          'La del primer segundo del día de hace 89 se queda');
select is(tests.cuenta(1009), '{"telefono": null, "direccion": null, "borrado": true}'::jsonb,
          'Una cancelada de hace 91 se vacía');
select is(tests.cuenta(1011), '{"telefono": null, "direccion": null, "borrado": false}'::jsonb,
          'Una de mesa no tenía nada que vaciar: no lleva la marca');
select is(tests.pedido(2101), '{"telefono": null, "direccion": null, "referencias": null, "borrado": true}'::jsonb,
          'En B, con su propio día, el rechazado de hace 30 se vacía');
select is(tests.pedido(2005), '{"telefono": "2229876543", "direccion": "Calle 5", "referencias": "Casa roja", "borrado": false}'::jsonb,
          'El de hoy por confirmar, intacto');

select is(privado.vaciar_datos_viejos(), 0, 'La noche siguiente no hay nada más que vaciar');

select is(
  (select count(*)::integer from public.bitacora where accion = 'borrar_datos_cliente'),
  0,
  'Lo del pg_cron no va a la bitácora'
);


-- ─── «Borrar los datos de un cliente»: quién ──────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');

select throws_ok(
  $$ select public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543') $$,
  '42501', 'Solo el gerente de este restaurante ve los datos de sus clientes',
  'La caja no busca los datos de un cliente'
);

select throws_ok(
  $$ select public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543') $$,
  '42501', 'Solo el gerente de este restaurante borra los datos de sus clientes',
  'Ni los borra'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543') $$,
  '42501', 'Solo el gerente de este restaurante borra los datos de sus clientes',
  'Ni el mesero'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543') $$,
  '42501', 'Solo el gerente de este restaurante ve los datos de sus clientes',
  'El gerente de otro restaurante no busca en A'
);

select tests.clear_authentication();

select throws_ok(
  $$ select public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543') $$,
  '42501', 'permission denied for function buscar_datos_cliente',
  'Sin sesión, nada'
);

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '222 987 654') $$,
  '22023', 'El teléfono lleva 10 dígitos, como 222 123 4567.',
  'El teléfono va con sus 10 dígitos'
);

select throws_ok(
  $$ select public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null) $$,
  '22023', 'El teléfono lleva 10 dígitos, como 222 123 4567.',
  'Y no vacío'
);


-- ─── «Borrar los datos de un cliente»: qué ────────────────────────────────────
-- A Rosa le quedan en A: 2002 con su cuenta 1002 (un pedido), 2007 rechazado, y las cuentas del punto de venta 1010
-- (con guiones). 2005 está por confirmar; 2006 y 1006, 1012 siguen abiertas.

select is(public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '(222) 987-6543'), 3,
          'Don Chuy encuentra 3 pedidos de Rosa: un pedido y su cuenta cuentan como uno');

select is(public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '9999999999'), 0,
          'Con un teléfono que nadie usó, ninguno');

select is(public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '222 987 6543'), 3,
          'Los borra y dice cuántos');

select is(tests.pedido(2002), '{"telefono": null, "direccion": null, "referencias": null, "borrado": true}'::jsonb,
          'Su pedido para llevar de hace 89 días se vacía antes de tiempo');
select is(tests.cuenta(1002), '{"telefono": null, "direccion": null, "borrado": true}'::jsonb,
          'Y su cuenta');
select is(tests.pedido(2007), '{"telefono": null, "direccion": null, "referencias": null, "borrado": true}'::jsonb,
          'El rechazado de hace 2 días también');
select is(tests.cuenta(1010), '{"telefono": null, "direccion": null, "borrado": true}'::jsonb,
          'Y la del punto de venta, aunque la caja escribió el teléfono con guiones');
select is(tests.pedido(2005), '{"telefono": "2229876543", "direccion": "Calle 5", "referencias": "Casa roja", "borrado": false}'::jsonb,
          'El de hoy por confirmar no se toca: todavía hace falta para entregarlo');
select is(jsonb_build_array(tests.pedido(2006) ->> 'borrado', tests.cuenta(1006) ->> 'borrado', tests.cuenta(1012) ->> 'borrado'),
          '["false", "false", "false"]'::jsonb,
          'Ni las cuentas abiertas ni el pedido de una cuenta abierta');
select is(tests.cuenta(1013), '{"telefono": "5551234567", "direccion": "Calle 13", "borrado": false}'::jsonb,
          'Mario no se toca');
select is(jsonb_build_array(tests.pedido(2102) ->> 'telefono', tests.cuenta(1101) ->> 'telefono'),
          '["2229876543", "2229876543"]'::jsonb,
          'Ni lo de Rosa en B: es por sucursal');

reset role;

select is(
  (select jsonb_build_object('miembro', miembro_id, 'tabla', tabla, 'registro', registro_id, 'detalle', detalle)
   from public.bitacora where accion = 'borrar_datos_cliente'),
  '{"miembro": 101, "tabla": "restaurantes", "registro": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "detalle": {"pedidos": 2, "cuentas": 2}}'::jsonb,
  'Queda en la bitácora: Don Chuy, 2 pedidos y 2 cuentas, sin el teléfono'
);

select tests.authenticate_as('gerente_a');

select is(public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543'), 0,
          'Buscarla otra vez ya no encuentra nada que vaciar');
select is(public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2229876543'), 0,
          'Y borrar otra vez no vacía nada');

reset role;

select is((select count(*)::integer from public.bitacora where accion = 'borrar_datos_cliente'), 1,
          'Sin nada que vaciar, no se anota otra vez');

select tests.authenticate_as('gerente_b');

select is(public.borrar_datos_cliente('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2229876543'), 1,
          'El gerente de B vacía lo de Rosa en B: su pedido y su cuenta son uno');

reset role;

select is(jsonb_build_array(tests.pedido(2102) ->> 'borrado', tests.cuenta(1101) ->> 'borrado'), '["true", "true"]'::jsonb,
          'En B, el pedido y su cuenta');


-- ─── Con las funciones de siempre: pedir, confirmar, cobrar ───────────────────
-- Marta pide a domicilio por el menú; Don Chuy lo confirma. Mientras la cuenta está abierta no se borra; cobrada sí, y
-- si después se cancela el pago, la cuenta reabierta conserva su marca.

select tests.como_worker();

select ok(
  (public.hacer_pedido('fonda-don-chuy', gen_random_uuid(), 'domicilio', 'Marta Díaz', '333 111 2222', 'Calle 20',
                       'Casa azul', 100, '[{"producto_id": 501, "cantidad": 2, "precio": 22}]',
                       repeat('b', 64), repeat('b', 64)) ->> 'ok')::boolean,
  'Marta pide a domicilio'
);

reset role;
select tests.guardar('pedido_marta', (select id from public.pedidos_en_linea where cliente_nombre = 'Marta Díaz'));

select tests.authenticate_as('gerente_a');
select tests.guardar('venta_marta', public.confirmar_pedido(tests.id('pedido_marta')));

select is(public.buscar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '3331112222'), 0,
          'Con su cuenta abierta, no hay nada que vaciar todavía');

select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500);
select lives_ok(
  format($$ select public.cobrar(%s, gen_random_uuid(), 'efectivo', 44, p_recibido => 100) $$, tests.id('venta_marta')),
  'Se cobra'
);

select is(public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '3331112222'), 1,
          'Cobrada, se vacía: un pedido');

reset role;

select is(jsonb_build_array(tests.pedido(tests.id('pedido_marta')), tests.cuenta(tests.id('venta_marta'))),
          '[{"telefono": null, "direccion": null, "referencias": null, "borrado": true},
            {"telefono": null, "direccion": null, "borrado": true}]'::jsonb,
          'Su pedido y su cuenta, sin teléfono, dirección ni referencias');

select tests.authenticate_as('gerente_a');

select lives_ok(
  format($$ select public.cancelar_pago((select id from public.pagos where venta_id = %s), 'Se equivocó') $$,
         tests.id('venta_marta')),
  'Cancelar el pago reabre la cuenta, ya sin sus datos'
);

reset role;

select is((select jsonb_build_object('estado', estado, 'borrado', datos_borrados_at is not null, 'telefono', cliente_telefono)
           from public.ventas where id = tests.id('venta_marta')),
          '{"estado": "abierta", "borrado": true, "telefono": null}'::jsonb,
          'Reabierta, conserva su marca');


-- ─── «Guardar» de Tu restaurante, con el nombre legal ─────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', '2221234567',
       'Av. Juárez 10, Puebla', null, '[]', null, '  Jesús Pérez López ') $$,
  'Don Chuy guarda Tu restaurante con su nombre legal'
);

reset role;
select is((select nombre_legal from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
          'Jesús Pérez López', 'Se guarda sin espacios a los lados');
select tests.authenticate_as('gerente_a');

select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', '2221234567',
       'Av. Juárez 10, Puebla', null, '[]', true);

reset role;
select is((select nombre_legal from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
          'Jesús Pérez López', 'Sin mandarlo (la app de antes), se queda como estaba');

select tests.clear_authentication();

select is(public.menu_publico('fonda-don-chuy') -> 'restaurante' -> 'nombre_legal', '"Jesús Pérez López"'::jsonb,
          'El menú lo recibe, para el aviso de privacidad');
select is(public.menu_publico('restaurante-b') -> 'restaurante' -> 'nombre_legal', 'null'::jsonb,
          'Sin nombre legal llega nulo: el aviso dice solo el nombre');

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', null, null, null,
       '[]', null, repeat('a', 121)) $$,
  '22023', 'El nombre legal puede tener hasta 120 letras',
  'Hasta 120 letras, también aquí'
);

select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', '2221234567',
       'Av. Juárez 10, Puebla', null, '[]', null, '   ');

reset role;
select is((select nombre_legal from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
          null::text, 'En blanco lo quita');

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Robado', null, null, null, '[]', null, 'Otro') $$,
  '42501', 'Solo el gerente de este restaurante puede cambiar sus datos',
  'El gerente de otro restaurante no lo cambia'
);

reset role;

select * from finish();
rollback;
