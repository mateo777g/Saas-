-- Pruebas de la migración terminal (16 de noviembre de 2026; planes/trabajo/terminal/): conectar Mercado Pago con
-- la contraseña otra vez y su pase de un solo uso, apartar un cobro para la Point, los candados mientras espera, lo
-- que dice Mercado Pago (pagado, no se cobró, revisa la terminal), el ticket, devolver y «Devuelto desde Mercado Pago».
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
-- Se siembra como postgres, con ids fijos. A es La Fonda de Don Chuy: Pepe y Toño son meseros, Lupita es la caja,
-- cada quien en su aparato. B es La Fonda · Norte, de otro gerente. La Mesa 3 de A pide 2 alambres, 2 gringas, un
-- agua y un arroz con leche: $445. El chicle cuesta $4, para el mínimo de $5.

-- Entra alguien, en su aparato si no es gerente.
create function tests.entrar(p_quien text)
returns void as $$
begin
  perform tests.authenticate_as(p_quien);
  if p_quien = 'pepe' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
  elsif p_quien = 'lupita' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
  elsif p_quien = 'tono' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
  end if;
end
$$ language plpgsql;

-- La sesión dice que puso su contraseña hace p_segundos.
create function tests.con_contrasena(p_segundos integer)
returns void as $$
begin
  perform set_config('request.jwt.claims',
    (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
      || jsonb_build_object('amr', jsonb_build_array(jsonb_build_object(
           'method', 'password', 'timestamp', extract(epoch from now())::bigint - p_segundos))))::text, true);
end
$$ language plpgsql;

-- Una cuenta nueva de Pepe en una mesa, con sus renglones.
create function tests.cuenta(p_mesa bigint, p_renglones jsonb)
returns bigint
language sql
as $$
  select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), p_renglones,
                                p_mesa_id => p_mesa, p_tipo => 'mesa')
$$;

-- Lo que el Worker dice de un cobro, con la cuenta de Mercado Pago de La Fonda.
create function tests.resultado(p_cobro text, p_orden text, p_estado text, p_motivo text default null,
                                p_monto numeric default null)
returns jsonb
language sql
as $$
  select public.resultado_cobro(tests.id(p_cobro), '123456', p_orden, p_estado, p_motivo, p_monto)
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

set local time zone 'UTC';

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
begin
  perform tests.create_supabase_user('chuy', 'chuy@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('lupita', 'lupita@prueba.test');
  perform tests.create_supabase_user('tono', 'tono@prueba.test');
  perform tests.create_supabase_user('norte', 'norte@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30),
    (b, 'La Fonda · Norte', 'fonda-norte', true, hoy - 30, hoy + 30);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('chuy'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('pepe'), 'Pepe', '{mesero}', true),
    (103, a, tests.get_supabase_uid('lupita'), 'Lupita', '{caja}', true),
    (104, a, tests.get_supabase_uid('tono'), 'Toño', '{mesero}', true),
    (111, b, tests.get_supabase_uid('norte'), 'Gerente Norte', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, privado.huella_aparato(repeat('P', 43)), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta de Lupita', 103, privado.huella_aparato(repeat('L', 43)), '5e5e5e5e-0000-4000-8000-000000000002'),
    (a, 'Celular de Toño', 104, privado.huella_aparato(repeat('T', 43)), '5e5e5e5e-0000-4000-8000-000000000003');

  insert into public.mesas (id, restaurante_id, nombre, orden) overriding system value values
    (701, a, 'Mesa 3', 1), (702, a, 'Mesa 4', 2), (703, a, 'Mesa 5', 3), (704, a, 'Mesa 6', 4), (705, a, 'Mesa 7', 5);

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Tacos', 'taco', null);

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Alambre', 120, true),
    (502, a, 601, 'Gringa', 65, true),
    (503, a, 601, 'Agua de jamaica', 35, true),
    (504, a, 601, 'Arroz con leche', 40, true),
    (505, a, 601, 'Chicle', 4, true),
    (506, a, 601, 'Salsa extra', 0, true);
end;
$$;

select plan(102);


-- ─── Las tablas y quién las lee ───────────────────────────────────────────────

select has_table('public', 'mercado_pago', 'Hay tabla de la conexión de cada sucursal');
select has_table('public', 'cobros_terminal', 'Hay tabla de los cobros mandados a la terminal');

select ok(
  not has_table_privilege('authenticated', 'public.llaves_mercado_pago', 'select')
  and not has_table_privilege('service_role', 'public.llaves_mercado_pago', 'select')
  and not has_table_privilege('anon', 'public.llaves_mercado_pago', 'select'),
  'Las llaves no las lee nadie directo, ni el Worker'
);

select ok(
  not has_table_privilege('authenticated', 'public.pases_mercado_pago', 'select')
  and not has_table_privilege('service_role', 'public.pases_mercado_pago', 'select'),
  'Los pases tampoco'
);

select ok(
  not has_column_privilege('authenticated', 'public.mercado_pago', 'cuenta_id', 'select')
  and has_column_privilege('authenticated', 'public.mercado_pago', 'terminal_id', 'select'),
  'De la conexión, la app lee la Point pero no el número de la cuenta'
);

select ok(
  not has_table_privilege('authenticated', 'public.cobros_terminal', 'insert')
  and not has_table_privilege('authenticated', 'public.cobros_terminal', 'update')
  and not has_table_privilege('authenticated', 'public.mercado_pago', 'update'),
  'Nadie escribe directo la conexión ni los cobros'
);

select ok(
  not has_function_privilege('authenticated', 'public.resultado_cobro(bigint, text, text, text, text, numeric)', 'execute')
  and not has_function_privilege('authenticated', 'public.conectar_mercado_pago(uuid, uuid, text, text, text, text, smallint, timestamptz, text[])', 'execute')
  and not has_function_privilege('authenticated', 'public.cobro_para_el_worker(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.pago_devuelto(bigint, bigint, bigint, text)', 'execute'),
  'Lo del Worker no lo llama la app'
);

select ok(
  not has_function_privilege('anon', 'public.apartar_cobro_terminal(bigint, uuid, numeric, integer, numeric)', 'execute')
  and not has_function_privilege('service_role', 'public.apartar_cobro_terminal(bigint, uuid, numeric, integer, numeric)', 'execute'),
  'Apartar un cobro va con la sesión de quien cobra, nunca anónimo ni con la llave del Worker'
);


-- ─── La contraseña otra vez ───────────────────────────────────────────────────

select tests.entrar('chuy');

select throws_ok(
  $$ select public.puedo_conectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Vuelve a escribir tu contraseña',
  'Conectar sin haber puesto la contraseña pide ponerla otra vez'
);

select tests.con_contrasena(301);

select throws_ok(
  $$ select public.puedo_conectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Vuelve a escribir tu contraseña',
  'Puesta hace más de 5 minutos, también'
);

select tests.con_contrasena(60);

select is(
  public.puedo_conectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  tests.get_supabase_uid('chuy'),
  'Puesta hace un minuto, el gerente puede conectar'
);

select throws_ok(
  $$ select public.puedo_conectar_mercado_pago('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  '42501', 'Solo los gerentes de esta sucursal conectan Mercado Pago',
  'Pero no la sucursal de otro'
);

select tests.entrar('pepe');
select tests.con_contrasena(10);

select throws_ok(
  $$ select public.puedo_conectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo los gerentes de esta sucursal conectan Mercado Pago',
  'Pepe no conecta Mercado Pago'
);


-- ─── El pase ──────────────────────────────────────────────────────────────────

reset role;
select tests.como_worker();

select public.guardar_pase_mercado_pago(repeat('a', 64), tests.get_supabase_uid('chuy'),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', repeat('v', 43), 'http://localhost:8125');

select is(
  public.usar_pase_mercado_pago(repeat('a', 64)) ->> 'verificador',
  repeat('v', 43),
  'El pase de regreso trae el verificador…'
);

select is(
  public.usar_pase_mercado_pago(repeat('a', 64)),
  null,
  '… y sirve una sola vez'
);

select is(public.usar_pase_mercado_pago(repeat('b', 64)), null, 'Un pase inventado no sirve');

reset role;
insert into public.pases_mercado_pago (huella, restaurante_id, usuario_id, verificador, origen, vence_at)
values (repeat('c', 64), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('chuy'), repeat('v', 43),
        'http://localhost:8125', now() - interval '1 second');
select tests.como_worker();

select is(public.usar_pase_mercado_pago(repeat('c', 64)), null, 'Un pase vencido tampoco');

select throws_ok(
  $$ select public.guardar_pase_mercado_pago(repeat('d', 64), tests.get_supabase_uid('pepe'),
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', repeat('v', 43), 'http://localhost:8125') $$,
  '42501', 'Solo los gerentes de esta sucursal conectan Mercado Pago',
  'El Worker no le da pase a quien no es gerente'
);


-- ─── Conectar ─────────────────────────────────────────────────────────────────

select is(
  public.conectar_mercado_pago(tests.get_supabase_uid('chuy'), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '123456',
    'Jesús Hernández', 'acceso-cifrado', 'renovar-cifrado', 1::smallint, now() + interval '180 days',
    '{NEWLAND_N950__N950NCB801234821}'),
  '{"ligada": true, "terminal_id": "NEWLAND_N950__N950NCB801234821"}'::jsonb,
  'Con una sola Point en la cuenta, se liga sola'
);

select is(
  public.conectar_mercado_pago(tests.get_supabase_uid('chuy'), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '123456',
    'Jesús Hernández', 'acceso-cifrado-2', 'renovar-cifrado-2', 1::smallint, now() + interval '180 days',
    '{NEWLAND_N950__N950NCB801234821,NEWLAND_N950__N950NCB807310}'),
  '{"ligada": false, "terminal_id": "NEWLAND_N950__N950NCB801234821"}'::jsonb,
  'Conectar otra vez la misma cuenta conserva su Point'
);

select is(
  public.llaves_de_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'acceso',
  'acceso-cifrado-2',
  'Y guarda sus llaves nuevas'
);

select is(
  public.conectar_mercado_pago(tests.get_supabase_uid('norte'), 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '123456',
    'Jesús Hernández', 'acceso-norte', 'renovar-norte', 1::smallint, now() + interval '20 days',
    '{NEWLAND_N950__N950NCB801234821}'),
  '{"ligada": false, "terminal_id": null}'::jsonb,
  'Una Point que ya está en otra sucursal no se liga sola'
);

select is(
  public.conectar_mercado_pago(tests.get_supabase_uid('norte'), 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '123456',
    'Jesús Hernández', 'acceso-norte', 'renovar-norte', 1::smallint, now() + interval '20 days',
    '{NEWLAND_N950__N950NCB807310,NEWLAND_N950__N950NCB802296}'),
  '{"ligada": false, "terminal_id": null}'::jsonb,
  'Con varias Point libres, ninguna se liga sola: se elige de la lista'
);

select is(
  public.terminales_en_otra_sucursal('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '{NEWLAND_N950__N950NCB801234821,NEWLAND_N950__N950NCB807310}'),
  '{"NEWLAND_N950__N950NCB801234821": "La Fonda de Don Chuy"}'::jsonb,
  'La lista dice en qué otra sucursal está cada Point'
);

select throws_ok(
  $$ select public.ligar_terminal('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'NEWLAND_N950__N950NCB801234821') $$,
  '23505', 'Esa Point ya está en otra sucursal',
  'Una Point está en una sola sucursal'
);

select lives_ok(
  $$ select public.ligar_terminal('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'NEWLAND_N950__N950NCB807310') $$,
  'La Norte liga la otra'
);

select is(
  (select count(*)::int from jsonb_array_elements(public.llaves_por_renovar()) x
   where x ->> 'restaurante_id' = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  1,
  'Al Cron le toca renovar la que vence en 20 días…'
);

select is(
  (select count(*)::int from jsonb_array_elements(public.llaves_por_renovar()) x
   where x ->> 'restaurante_id' = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  '… y no la que vence en 180'
);

select is(
  public.llaves_por_cuenta('123456') ->> 'restaurante_id',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Para un aviso, las llaves de la cuenta son las que vencen más tarde'
);

reset role;

select is(
  (select detalle ->> 'cuenta_nombre' from public.bitacora
   where accion = 'conectar_mercado_pago' and restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
   order by id desc limit 1),
  'Jesús Hernández',
  'Conectar queda en la bitácora'
);

select tests.entrar('pepe');

select results_eq(
  $$ select terminal_id, imprimir_ticket from public.mercado_pago $$,
  $$ values ('NEWLAND_N950__N950NCB801234821'::text, true) $$,
  'Pepe ve la Point de su sucursal (y nada de la otra); el ticket nace prendido'
);

select throws_ok(
  $$ select public.fijar_imprimir_ticket('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false) $$,
  '42501', 'Solo los gerentes de esta sucursal cambian el ticket',
  'Pepe no apaga el ticket'
);

select tests.entrar('chuy');
select public.fijar_imprimir_ticket('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false);
select public.fijar_imprimir_ticket('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

select is(
  (select imprimir_ticket from public.mercado_pago),
  true,
  'Don Chuy lo apaga y lo prende'
);

select is(public.puedo_ver_terminales('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), true, 'Don Chuy puede elegir su Point');


-- ─── Apartar un cobro ─────────────────────────────────────────────────────────

select tests.entrar('pepe');

select tests.guardar('mesa3', tests.cuenta(701,
  '[{"producto_id": 501, "cantidad": 2}, {"producto_id": 502, "cantidad": 2},
    {"producto_id": 503, "cantidad": 1}, {"producto_id": 504, "cantidad": 1}]'));

select throws_ok(
  $$ select public.apartar_cobro_terminal(tests.id('mesa3'), gen_random_uuid(), 445, 10) $$,
  '55000', 'La caja no está abierta',
  'Sin turno abierto no se manda nada'
);

select tests.entrar('lupita');
select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500);
select tests.entrar('pepe');

select throws_ok(
  $$ select public.apartar_cobro_terminal(tests.id('mesa3'), gen_random_uuid(), 4, 10) $$,
  '22023', 'Menos de $5.00 no se puede mandar a la terminal',
  'Pagar $4 con su propina ($4.40) no va a la terminal'
);

select throws_ok(
  $$ select public.apartar_cobro_terminal(tests.id('mesa3'), gen_random_uuid(), 446) $$,
  '22023', 'No puede pasar de lo que falta ($445.00)',
  'Ni más de lo que falta'
);

select is(
  (public.apartar_cobro_terminal(tests.id('mesa3'), 'c0c0c0c0-0000-4000-8000-000000000001', 445, 10)
     - 'cobro_id'),
  '{"ok": true, "estado": "mandando", "monto": 489.50, "motivo": null, "orden_id": null,
    "terminal_id": "NEWLAND_N950__N950NCB801234821"}'::jsonb,
  'La Mesa 3 con 10 % de propina manda $489.50 a la Point de la sucursal'
);

select tests.guardar('c1', (public.apartar_cobro_terminal(tests.id('mesa3'), 'c0c0c0c0-0000-4000-8000-000000000001', 445, 10)
  ->> 'cobro_id')::bigint);

select is(
  (select count(*)::int from public.cobros_terminal),
  1,
  'Con la misma clave regresa el mismo cobro: pulsar dos veces no manda dos'
);

select results_eq(
  $$ select monto, propina, mandado_por, vence_at - created_at from public.cobros_terminal where id = tests.id('c1') $$,
  $$ values (489.50::numeric(12,2), 44.50::numeric(12,2), 102::bigint, interval '5 minutes') $$,
  'El cobro guarda la propina adentro, quién lo mandó y vence a los 5 minutos'
);

select throws_ok(
  $$ select public.apartar_cobro_terminal(tests.id('mesa3'), gen_random_uuid(), 100) $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'La misma cuenta no manda otro mientras espera'
);

select tests.guardar('mesa4', tests.cuenta(702, '[{"producto_id": 501, "cantidad": 1}]'));

select is(
  public.apartar_cobro_terminal(tests.id('mesa4'), gen_random_uuid(), 120),
  '{"ok": false, "motivo": "ocupada"}'::jsonb,
  'Otra cuenta tampoco: la terminal está atendiendo otro cobro'
);


-- ─── Mientras espera, la cuenta no cambia ─────────────────────────────────────

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
       '[{"producto_id": 503, "cantidad": 1}]', p_venta_id => tests.id('mesa3')) $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'No se agregan productos'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
       '[{"producto_id": 506, "cantidad": 1}]', p_venta_id => tests.id('mesa3')) $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'Ni uno de $0, que no cambia el total'
);

select throws_ok(
  $$ select public.cobrar(tests.id('mesa3'), gen_random_uuid(), 'efectivo', 100, p_recibido => 100) $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'No se cobra otra parte por otro lado'
);

select lives_ok(
  $$ select public.pedir_cuenta(tests.id('mesa3')) $$,
  'Pedir la cuenta sí se puede'
);

select tests.entrar('chuy');

select throws_ok(
  $$ select public.descontar(tests.id('mesa3'), null, 'porcentaje', 10, 'Cliente frecuente') $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'No se descuenta'
);

select throws_ok(
  $$ select public.cancelar_cuenta(tests.id('mesa3'), 'Se fueron') $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'No se cancela'
);

select throws_ok(
  $$ select public.juntar_mesas(tests.id('mesa4'), tests.id('mesa3')) $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'No se le junta otra'
);

select throws_ok(
  $$ select public.cancelar_renglon((select min(id) from public.venta_items where venta_id = tests.id('mesa3')),
       1, 'Se equivocó') $$,
  '55000', 'Esta cuenta tiene un cobro esperando en la terminal',
  'No se cancela un renglón'
);

select tests.entrar('lupita');

select throws_ok(
  $$ select public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500, 0, 0) $$,
  '55000', 'Hay un cobro esperando en la terminal',
  'Lupita no puede cerrar la caja'
);

select tests.entrar('chuy');
select tests.con_contrasena(30);

select throws_ok(
  $$ select public.desconectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '55000', 'No se puede desconectar mientras un cobro espera en la terminal',
  'Don Chuy no puede desconectar Mercado Pago'
);

select throws_ok(
  $$ select public.puedo_conectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '55000', 'No se puede cambiar la cuenta mientras un cobro espera en la terminal',
  'Ni conectar otra cuenta'
);


-- ─── Quién revisa y quién cancela ─────────────────────────────────────────────

select tests.entrar('tono');

select is(
  public.puedo_tocar_cobro(tests.id('c1'), 'revisar'),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  'Toño puede preguntar cómo va'
);

select throws_ok(
  $$ select public.puedo_tocar_cobro(tests.id('c1'), 'cancelar') $$,
  '42501', 'Lo cancela quien lo mandó, la caja o el gerente',
  'Pero no cancelar el cobro de Pepe'
);

select tests.entrar('lupita');

select is(
  public.puedo_tocar_cobro(tests.id('c1'), 'cancelar'),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
  'La caja sí lo cancela'
);

select tests.entrar('norte');

select throws_ok(
  $$ select public.puedo_tocar_cobro(tests.id('c1'), 'revisar') $$,
  '23503', 'Ese cobro ya no está',
  'El gerente de otra sucursal ni lo ve'
);


-- ─── Lo que dice Mercado Pago ─────────────────────────────────────────────────

reset role;
select tests.como_worker();

select throws_ok(
  $$ select public.resultado_cobro(tests.id('c1'), '999', 'ORD01JQ1', 'esperando') $$,
  '42501', 'Ese cobro no es de esa cuenta de Mercado Pago',
  'Un aviso de otra cuenta no mueve el cobro'
);

select is(
  tests.resultado('c1', 'ORD01JQ1', 'esperando') ->> 'estado',
  'esperando',
  'La orden existe: esperando'
);

select is(
  (tests.resultado('c1', 'ORD01JQ1', 'tomado') ->> 'tomado')::boolean,
  true,
  'La Point lo tomó'
);

select throws_ok(
  $$ select tests.resultado('c1', 'ORD01OTRA', 'pagado', null, 489.50) $$,
  '22023', 'Esa orden no es de ese cobro',
  'Otra orden no paga este cobro'
);

select throws_ok(
  $$ select tests.resultado('c1', 'ORD01JQ1', 'pagado', null, 48.95) $$,
  '22023', 'El monto de la orden no es el del cobro',
  'Ni con otro monto'
);

select is(
  tests.resultado('c1', 'ORD01JQ1', 'pagado', null, 489.50) - 'venta_id' - 'restaurante_id' - 'ticket',
  '{"cambio": true, "estado": "pagado", "motivo": null, "cerrada": true, "folio": 1}'::jsonb,
  'Pagado: la cuenta se cierra sola con su folio'
);

select is(
  tests.resultado('c1', 'ORD01JQ1', 'pagado', null, 489.50) ->> 'cambio',
  'false',
  'Un aviso repetido lo encuentra hecho y no cambia nada'
);

reset role;

select results_eq(
  $$ select p.metodo, p.monto, p.propina, p.cobrado_por, p.referencia, p.turno_id = c.turno_id
     from public.pagos p join public.cobros_terminal c on c.pago_id = p.id where c.id = tests.id('c1') $$,
  $$ values ('tarjeta'::text, 445.00::numeric(12,2), 44.50::numeric(12,2), 102::bigint, 'ORD01JQ1'::text, true) $$,
  'El pago queda como tarjeta, a nombre de Pepe, con la orden de referencia, en el turno abierto'
);

select is(
  (select count(*)::int from public.ventas where id = tests.id('mesa3') and estado = 'cerrada'),
  1,
  'La Mesa 3 quedó cerrada'
);


-- ─── El ticket ────────────────────────────────────────────────────────────────

select tests.entrar('pepe');
select tests.guardar('mesa5', tests.cuenta(703, '[{"producto_id": 501, "cantidad": 1}, {"producto_id": 503, "cantidad": 2}]'));
select tests.guardar('c2', (public.apartar_cobro_terminal(tests.id('mesa5'), gen_random_uuid(), 190) ->> 'cobro_id')::bigint);
reset role;
select tests.como_worker();

select is(
  (tests.resultado('c2', 'ORD01JQ2', 'pagado', null, 190) -> 'ticket') - 'cerrada_at' - 'zona',
  '{"restaurante": "La Fonda de Don Chuy", "cuenta": "Mesa 5", "atendio": "Pepe", "descuento": 0.00,
    "propina": 0.00, "total": 190.00, "folio": 2,
    "renglones": [{"cantidad": 1, "nombre": "Alambre", "importe": 120.00},
                  {"cantidad": 2, "nombre": "Agua de jamaica", "importe": 70.00}]}'::jsonb,
  'Con el ticket prendido, al cerrar regresa lo que imprime la Point'
);


-- ─── Lo que no se cobró ───────────────────────────────────────────────────────

reset role;
select tests.entrar('pepe');
select tests.guardar('c3', (public.apartar_cobro_terminal(tests.id('mesa4'), gen_random_uuid(), 120) ->> 'cobro_id')::bigint);
reset role;
select tests.como_worker();

select throws_ok(
  $$ select tests.resultado('c3', 'ORD01JQ3', 'no_se_cobro', 'no_alcanzo') $$,
  '22023', 'Ese motivo no existe',
  'Un motivo inventado no se guarda'
);

select is(
  tests.resultado('c3', 'ORD01JQ3', 'no_se_cobro', 'rechazada') ->> 'motivo',
  'rechazada',
  'La tarjeta se rechazó: no se cobró, con su porqué'
);

reset role;
select tests.entrar('pepe');

select lives_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
       '[{"producto_id": 505, "cantidad": 1}]', p_venta_id => tests.id('mesa4')) $$,
  'Sin cobro esperando, la cuenta vuelve a cambiar'
);

select tests.guardar('c4', (public.apartar_cobro_terminal(tests.id('mesa4'), gen_random_uuid(), 124) ->> 'cobro_id')::bigint);
reset role;
select tests.como_worker();

select is(
  tests.resultado('c4', null, 'no_se_cobro', 'sin_conexion') ->> 'estado',
  'no_se_cobro',
  'Si Mercado Pago nunca creó la orden, se termina sin ella'
);

select throws_ok(
  $$ select tests.resultado('c4', null, 'revisar') $$,
  '22023', 'Esa orden no es de ese cobro',
  'Pero sin orden no hay nada que revisar'
);


-- ─── «Revisa la terminal» ─────────────────────────────────────────────────────

reset role;
select tests.entrar('pepe');
select tests.guardar('c5', (public.apartar_cobro_terminal(tests.id('mesa4'), gen_random_uuid(), 100) ->> 'cobro_id')::bigint);
reset role;
select tests.como_worker();
select tests.resultado('c5', 'ORD01JQ5', 'revisar');
reset role;
select tests.entrar('lupita');

select throws_ok(
  $$ select public.confirmar_cobro_terminal(tests.id('c5'), true) $$,
  '42501', 'Lo resuelve quien lo mandó',
  'Lupita no resuelve el cobro de Pepe'
);

select tests.entrar('pepe');

select is(
  public.confirmar_cobro_terminal(tests.id('c5'), false),
  '{"estado": "no_se_cobro", "cerrada": false, "folio": null}'::jsonb,
  'Pepe mira la Point: no se pagó'
);

select tests.guardar('c6', (public.apartar_cobro_terminal(tests.id('mesa4'), gen_random_uuid(), 124) ->> 'cobro_id')::bigint);
reset role;
select tests.como_worker();
select tests.resultado('c6', 'ORD01JQ6', 'revisar');
reset role;
select tests.entrar('pepe');

select is(
  public.confirmar_cobro_terminal(tests.id('c6'), true) ->> 'cerrada',
  'true',
  'Sí se pagó: se anota el pago y la cuenta se cierra'
);

select throws_ok(
  $$ select public.confirmar_cobro_terminal(tests.id('c6'), true) $$,
  '55000', 'Ese cobro ya no está por revisar',
  'Y no se confirma dos veces'
);

reset role;

select results_eq(
  $$ select detalle ->> 'pagado', miembro_id from public.bitacora where accion = 'confirmar_terminal' order by id $$,
  $$ values ('false'::text, 102::bigint), ('true', 102) $$,
  'Los dos quedan en la bitácora, a nombre de Pepe'
);

select is(
  (select confirmado_por from public.cobros_terminal where id = tests.id('c6')),
  102::bigint,
  'El cobro dice quién lo confirmó a mano'
);


-- ─── Devolver ─────────────────────────────────────────────────────────────────

select tests.entrar('lupita');

select throws_ok(
  $$ select public.cancelar_pago((select pago_id from public.cobros_terminal where id = tests.id('c1')), 'Se equivocó') $$,
  '55000', 'Ese pago se cobró en la terminal: se cancela devolviendo el dinero',
  'Un pago de la terminal no se cancela sin devolverlo'
);

select is(
  public.revisar_devolucion((select pago_id from public.cobros_terminal where id = tests.id('c1')), 'Se equivocó')
    - 'cobro_id',
  '{"ok": true, "autoriza": 103, "miembro": 103, "orden_id": "ORD01JQ1", "monto": 489.50, "motivo": "Se equivocó"}'::jsonb,
  'La caja revisa la devolución con su propia autorización'
);

select is(
  (select devuelto_desde from public.cobros_terminal where id = tests.id('c1')),
  'sistema',
  'La devolución queda apartada mientras Mercado Pago contesta'
);

reset role;
select tests.como_worker();

select is(
  public.devuelto_desde_mercado_pago(tests.id('c1'), '123456', 'ORD01JQ1', 489.50),
  false,
  'Su aviso no se cuenta como devolución desde la app'
);

select is(
  public.pago_devuelto(tests.id('c1'), 103, 103, 'Se equivocó'),
  '{"ok": true, "reabierta": true}'::jsonb,
  'Mercado Pago devolvió: el pago se cancela y la cuenta se reabre'
);

reset role;

select results_eq(
  $$ select p.cancelado_por, c.devuelto_desde, c.devuelto_monto, v.estado
     from public.cobros_terminal c join public.pagos p on p.id = c.pago_id join public.ventas v on v.id = c.venta_id
     where c.id = tests.id('c1') $$,
  $$ values (103::bigint, 'sistema'::text, 489.50::numeric(12,2), 'abierta'::text) $$,
  'Cancelado por Lupita, devuelto desde el sistema, la Mesa 3 abierta otra vez'
);

select is(
  (select detalle ->> 'terminal' from public.bitacora where accion = 'cancelar_pago' order by id desc limit 1),
  'true',
  'La bitácora dice que fue un pago de la terminal'
);

select tests.entrar('lupita');

select throws_ok(
  $$ select public.revisar_devolucion((select pago_id from public.cobros_terminal where id = tests.id('c1')), 'Otra vez') $$,
  '55000', 'Ese pago ya está cancelado',
  'No se devuelve dos veces'
);

select tests.guardar('d2', (public.revisar_devolucion((select pago_id from public.cobros_terminal where id = tests.id('c2')),
  'Prueba') ->> 'cobro_id')::bigint);
reset role;
select tests.como_worker();
select public.devolucion_no_salio(tests.id('d2'));
reset role;

select is(
  (select devuelto_desde from public.cobros_terminal where id = tests.id('c2')),
  null,
  'Si Mercado Pago no devolvió, la devolución se suelta'
);


-- ─── Devuelto desde Mercado Pago ──────────────────────────────────────────────

select tests.como_worker();

select is(
  public.devuelto_desde_mercado_pago(tests.id('c2'), '123456', 'ORD01JQ2', 50),
  true,
  'Don Chuy devolvió $50 desde su app: queda anotado'
);

select is(
  public.devuelto_desde_mercado_pago(tests.id('c2'), '123456', 'ORD01JQ2', 50),
  false,
  'El aviso repetido no lo anota otra vez'
);

select throws_ok(
  $$ select public.devuelto_desde_mercado_pago(tests.id('c2'), '999', 'ORD01JQ2', 50) $$,
  '42501', 'Ese cobro no es de esa cuenta de Mercado Pago',
  'Un aviso de otra cuenta no se cree'
);

reset role;

select is(
  (select estado from public.ventas where id = tests.id('mesa5')),
  'cerrada',
  'No reabre la cuenta'
);

select tests.entrar('chuy');

select is(
  (select x -> 'detalle' ->> 'monto' from jsonb_array_elements(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'otros') x
   where x ->> 'accion' = 'devuelto_mercado_pago'),
  '50.00',
  'Cortes y reportes de hoy dice «Devuelto desde Mercado Pago · $50»'
);


-- ─── La caja y desconectar ────────────────────────────────────────────────────

select tests.entrar('lupita');

select lives_ok(
  $$ select public.cerrar_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500, 314, 0) $$,
  'Sin cobros esperando, la caja cierra'
);

select tests.entrar('chuy');
select tests.con_contrasena(400);

select throws_ok(
  $$ select public.desconectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Vuelve a escribir tu contraseña',
  'Desconectar también pide la contraseña'
);

select tests.con_contrasena(20);
select public.desconectar_mercado_pago('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
reset role;

select is(
  (select count(*)::int from public.mercado_pago where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  + (select count(*)::int from public.llaves_mercado_pago where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  0,
  'Desconectar borra la conexión y sus llaves'
);

select is(
  (select count(*)::int from public.bitacora where accion = 'desconectar_mercado_pago'),
  1,
  'Y queda en la bitácora'
);

select tests.entrar('pepe');

select throws_ok(
  $$ select public.apartar_cobro_terminal(tests.id('mesa3'), gen_random_uuid(), 445) $$,
  '55000', 'Mercado Pago no está conectado en esta sucursal',
  'Sin conexión no se manda nada'
);


-- ─── Se desconectó ────────────────────────────────────────────────────────────

reset role;
select tests.como_worker();
select public.mercado_pago_se_desconecto('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

reset role;

select is(
  (select count(*)::int from public.llaves_mercado_pago where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  0,
  'Se desconectó: sus llaves ya no sirven y se borran'
);

select ok(
  (select desconectada_at is not null and terminal_id is not null from public.mercado_pago
   where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'La fila se queda con su fecha, para el aviso de «Se desconectó»'
);

select tests.como_worker();

select is(
  public.conectar_mercado_pago(tests.get_supabase_uid('norte'), 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '123456',
    'Jesús Hernández', 'acceso-norte-2', 'renovar-norte-2', 1::smallint, now() + interval '180 days',
    '{NEWLAND_N950__N950NCB807310}'),
  '{"ligada": false, "terminal_id": "NEWLAND_N950__N950NCB807310"}'::jsonb,
  '«Conectar otra vez» la deja funcionando con su misma Point'
);

reset role;

select is(
  (select desconectada_at from public.mercado_pago where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  null,
  'Y sin el aviso'
);

select is(
  (select sum(p.monto + p.propina) from public.pagos p where p.cancelado_at is null and p.metodo = 'tarjeta'
     and p.restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  314.00::numeric,
  'En la caja quedan las dos tarjetas que siguen pagadas: $190 y $124'
);


select * from finish();

rollback;
