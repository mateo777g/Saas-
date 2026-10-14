-- Pruebas de empleados y aparatos con PIN (migración empleados; libreta 5, pieza 2). Trae las
-- pruebas de aislamiento de la libreta 2 que tocan al personal (1, 2, 3, 4, 5, 7, 8, 13, 16, 18,
-- el resto de la 20, 21 y 22; cada descripción empieza con su número) y lo decidido el 14 de
-- octubre de 2026: quien no es gerente solo funciona desde la sesión de su aparato, el gerente da
-- solo mesero, caja y cocina, el código de 6 letras, los 5 intentos y el bloqueo del mismo día.
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


-- Como el Worker: service_role, sin sesión de nadie. Así llama a las funciones del aparato.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

-- La huella del secreto de un aparato, como la guarda la base.
create function tests.huella(p_token text)
returns text
language sql
as $$
  select encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas, con ids fijos. En A: dos gerentes (Gerente A y
-- Gerente A2), Pepe (mesero), Lupita (caja), Beto (cocina, bloqueado hasta que lo desbloqueen) y
-- un mesero dado de baja; la tableta compartida de la caja (la sesión de Lupita), el celular de
-- Pepe (su sesión) y una tableta ya desligada. B, con su tableta y su mesero; C, pausado, con su
-- tableta; D venció ayer y E vence hoy. Tres cuentas nuevas del personal, todavía sin
-- restaurante, y una cuenta normal. Los PIN ya mezclados son 64 caracteres: el de todos es «1».
-- La hora de corte de A queda 12 horas lejos de ahora, para que «el mismo día de negocio» no
-- cambie a media prueba.

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  d uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  e uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  hoy date := privado.dia_local('America/Mexico_City');
  pin text := extensions.crypt(repeat('1', 64), extensions.gen_salt('bf', 4));
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('gerente2_a', 'gerente2.a@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@personal.prueba.test');
  perform tests.create_supabase_user('lupita', 'lupita@personal.prueba.test');
  perform tests.create_supabase_user('beto', 'beto@personal.prueba.test');
  perform tests.create_supabase_user('baja_a', 'baja.a@personal.prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('mesero_b', 'mesero.b@personal.prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('mesero_c', 'mesero.c@personal.prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');
  perform tests.create_supabase_user('gerente_e', 'gerente.e@prueba.test');
  perform tests.create_supabase_user('nuevo1', 'nuevo1@personal.prueba.test');
  perform tests.create_supabase_user('nuevo2', 'nuevo2@personal.prueba.test');
  perform tests.create_supabase_user('nuevo3', 'nuevo3@personal.prueba.test');
  perform tests.create_supabase_user('normal', 'normal@prueba.test');

  -- Las cuentas que crea el Worker van marcadas como del personal.
  update auth.users set raw_app_meta_data = '{"personal": true}'
  where raw_user_meta_data ->> 'test_identifier' in ('nuevo1', 'nuevo2', 'nuevo3');

  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, hora_corte) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30,
       ((extract(hour from now() at time zone 'America/Mexico_City')::int + 12) % 24)::smallint),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, 6),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30, 6),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1, 6),
    (e, 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy, 6);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo, pin_hash, bloqueado_hasta)
  overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true, null, null),
    (102, a, tests.get_supabase_uid('gerente2_a'), 'Gerente A2', '{gerente}', true, pin, null),
    (103, a, tests.get_supabase_uid('pepe'), 'Pepe Martínez', '{mesero}', true, pin, null),
    (104, a, tests.get_supabase_uid('lupita'), 'Lupita Ramírez', '{caja}', true, pin, null),
    (105, a, tests.get_supabase_uid('beto'), 'Beto Sánchez', '{cocina}', true, pin, 'infinity'),
    (106, a, tests.get_supabase_uid('baja_a'), 'Toño García', '{mesero}', false, pin, null),
    (201, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true, null, null),
    (202, b, tests.get_supabase_uid('mesero_b'), 'Mesero B', '{mesero}', true, pin, null),
    (301, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true, null, null),
    (302, c, tests.get_supabase_uid('mesero_c'), 'Mesero C', '{mesero}', true, pin, null),
    (401, d, tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true, null, null),
    (501, e, tests.get_supabase_uid('gerente_e'), 'Gerente E', '{gerente}', true, null, null);

  insert into public.dispositivos (id, restaurante_id, nombre, miembro_id, token_hash, sesion_id, vinculado_por, revocado_at) values
    ('d0000000-0000-4000-8000-000000000001', a, 'Tableta caja', null, tests.huella(repeat('A', 43)), '5e5e0000-0000-4000-8000-000000000001', 101, null),
    ('d0000000-0000-4000-8000-000000000002', a, 'Celular de Pepe', 103, tests.huella(repeat('B', 43)), '5e5e0000-0000-4000-8000-000000000002', 101, null),
    ('d0000000-0000-4000-8000-000000000003', a, 'Tableta vieja', null, tests.huella(repeat('C', 43)), '5e5e0000-0000-4000-8000-000000000003', 101, now() - interval '1 day'),
    ('d0000000-0000-4000-8000-000000000004', b, 'Tableta B', null, tests.huella(repeat('D', 43)), '5e5e0000-0000-4000-8000-000000000004', 201, null),
    ('d0000000-0000-4000-8000-000000000005', c, 'Tableta C', null, tests.huella(repeat('E', 43)), '5e5e0000-0000-4000-8000-000000000005', 301, null);
end;
$$;

select plan(140);


-- ─── 1 · La estructura ────────────────────────────────────────────────────────

select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.dispositivos'::regclass, 'public.codigos_vinculo'::regclass)),
  '1 · dispositivos y codigos_vinculo tienen RLS'
);

select is_empty(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('puedo_cambiar_equipo', 'alta_empleado', 'asignar_pin', 'desbloquear_miembro',
                         'crear_codigo_vinculo', 'desligar_aparato', 'vincular_aparato',
                         'nombres_del_aparato', 'entrar_con_pin', 'registrar_sesion')
       and has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  '1 · anon no ejecuta ninguna función de empleados'
);

select is_empty(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('vincular_aparato', 'nombres_del_aparato', 'entrar_con_pin', 'registrar_sesion')
       and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
            or not has_function_privilege('service_role', p.oid, 'EXECUTE')) $$,
  '1 · Las funciones del aparato solo las ejecuta el Worker (service_role)'
);

select ok(
  not has_column_privilege('authenticated', 'public.miembros', 'pin_hash', 'SELECT')
  and not has_column_privilege('authenticated', 'public.miembros', 'intentos_fallidos', 'SELECT')
  and not has_column_privilege('authenticated', 'public.dispositivos', 'token_hash', 'SELECT')
  and not has_column_privilege('authenticated', 'public.dispositivos', 'sesion_id', 'SELECT'),
  '13 · Nadie con sesión puede leer pin_hash, intentos_fallidos, token_hash ni sesion_id'
);

select ok(
  not has_column_privilege('authenticated', 'public.miembros', 'pin_hash', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.miembros', 'intentos_fallidos', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.miembros', 'bloqueado_hasta', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.miembros', 'usuario_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.miembros', 'restaurante_id', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.miembros', 'INSERT, DELETE'),
  '20 · En miembros, quien tiene sesión solo puede cambiar nombre, roles y activo'
);

select ok(
  not has_table_privilege('authenticated', 'public.dispositivos', 'INSERT, UPDATE, DELETE')
  and not has_any_column_privilege('authenticated', 'public.dispositivos', 'INSERT, UPDATE')
  and not has_any_column_privilege('authenticated', 'public.codigos_vinculo', 'SELECT, INSERT, UPDATE'),
  'Nadie escribe directo en dispositivos, y nadie toca codigos_vinculo'
);

select is(
  privado.dia_de_negocio('America/Mexico_City', 6::smallint, '2026-10-17 06:40+00'),
  '2026-10-16'::date,
  'El día de negocio: a las 00:40 del sábado, con corte a las 6, todavía es viernes'
);

select is(
  privado.dia_de_negocio('America/Mexico_City', 0::smallint, '2026-10-17 06:40+00'),
  '2026-10-17'::date,
  'Con corte a las 0, ya es sábado'
);


-- ─── Solo desde su aparato ────────────────────────────────────────────────────

select tests.authenticate_as('pepe');

select is_empty(
  'select id::text from public.miembros union all select id::text from public.restaurantes',
  'Sin la sesión de un aparato, Pepe no ve nada'
);

select tests.en_aparato('5e5e0000-0000-4000-8000-000000000002');

select results_eq(
  'select id from public.restaurantes',
  array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid],
  'Desde su celular, Pepe ve su restaurante'
);

select set_eq(
  'select nombre from public.miembros',
  array['Gerente A', 'Gerente A2', 'Pepe Martínez', 'Lupita Ramírez', 'Beto Sánchez', 'Toño García'],
  '2 · Y a su equipo, solo el de A'
);

select is_empty(
  'select id from public.dispositivos',
  'El mesero no ve los aparatos'
);

select tests.en_aparato('5e5e0000-0000-4000-8000-000000000004');

select is_empty(
  'select id from public.miembros',
  'Con la sesión de la tableta de B, Pepe no ve nada de A'
);

select tests.en_aparato('5e5e0000-0000-4000-8000-0000000000ff');

select is_empty(
  'select id from public.miembros',
  'Con una sesión que no es de ningún aparato, tampoco'
);

select tests.authenticate_as('lupita');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000001');

select isnt_empty(
  'select id from public.miembros',
  'Lupita funciona desde la tableta compartida'
);

select tests.en_aparato('5e5e0000-0000-4000-8000-000000000002');

select is_empty(
  'select id from public.miembros',
  'En el celular de Pepe, nadie más funciona'
);

select tests.authenticate_as('beto');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000003');

select is_empty(
  'select id from public.miembros',
  'Desde una tableta desligada no se ve nada'
);

select tests.authenticate_as('mesero_c');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000005');

select is_empty(
  'select id from public.miembros',
  '8 · Con la licencia pausada, ni desde su tableta'
);

select tests.authenticate_as('gerente_a');

select isnt_empty(
  'select id from public.miembros',
  'El gerente no necesita aparato: entra con su correo'
);


-- ─── Lo que lee el gerente ────────────────────────────────────────────────────

select set_eq(
  'select nombre from public.dispositivos',
  array['Tableta caja', 'Celular de Pepe', 'Tableta vieja'],
  '2 · Gerente A ve los aparatos de A, ninguno de B'
);

select results_eq(
  $$ select tiene_pin, bloqueado_hasta from public.miembros where id in (101, 105) order by id $$,
  $$ values (false, null::timestamptz), (true, 'infinity'::timestamptz) $$,
  'Lee si cada quien tiene PIN y si está bloqueado'
);

select throws_ok(
  'select pin_hash from public.miembros',
  '42501', null,
  '13 · Gerente A no lee pin_hash'
);

select throws_ok(
  'select token_hash from public.dispositivos',
  '42501', null,
  '13 · Ni token_hash'
);

select throws_ok(
  'select codigo from public.codigos_vinculo',
  '42501', null,
  'Ni los códigos'
);


-- ─── El gerente corrige a su equipo ───────────────────────────────────────────

select is(
  tests.filas($$ update public.miembros set nombre = '  Lupita Ramírez López ' where id = 104 $$),
  1,
  'Gerente A corrige el nombre de Lupita'
);

select is(
  (select nombre from public.miembros where id = 104),
  'Lupita Ramírez López',
  'Y se guarda sin espacios sobrantes'
);

select is(
  tests.filas($$ update public.miembros set roles = '{mesero,caja}' where id = 103 $$),
  1,
  'Le da a Pepe también el rol de caja'
);

select throws_ok(
  $$ update public.miembros set roles = '{mesero,gerente}' where id = 103 $$,
  '42501', null,
  'No lo puede hacer gerente'
);

select is(
  tests.filas($$ update public.miembros set nombre = 'Otro' where id = 102 $$),
  0,
  'No edita a otro gerente'
);

select is(
  tests.filas($$ update public.miembros set nombre = 'Yo mismo' where id = 101 $$),
  0,
  'Ni se edita a sí mismo aquí: su nombre va en Perfil'
);

select throws_ok(
  $$ update public.miembros set pin_hash = 'x' where id = 103 $$,
  '42501', null,
  '20 · No escribe pin_hash directo'
);

select throws_ok(
  $$ update public.miembros set intentos_fallidos = 0, bloqueado_hasta = null where id = 105 $$,
  '42501', null,
  '20 · Ni intentos_fallidos ni bloqueado_hasta'
);

select throws_ok(
  $$ update public.miembros set restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where id = 103 $$,
  '42501', null,
  '5 · No pasa a Pepe a B'
);

select throws_ok(
  $$ delete from public.miembros where id = 103 $$,
  '42501', null,
  'No borra a nadie'
);

select is(
  tests.filas($$ update public.miembros set nombre = 'Hackeado' where id = 202 $$),
  0,
  '4 · No cambia a nadie de B'
);

select throws_ok(
  $$ update public.miembros set nombre = 'pepe martínez' where id = 104 $$,
  '23505', null,
  'Dos activos no se llaman igual, aunque cambien las mayúsculas'
);

select is(
  tests.filas($$ update public.miembros set nombre = 'Toño García' where id = 104 $$),
  1,
  'El nombre de alguien de baja sí se puede volver a usar'
);

update public.miembros set nombre = 'Lupita Ramírez' where id = 104;

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000002');

select is(
  tests.filas($$ update public.miembros set nombre = 'Pepe el mejor' where id = 103 $$),
  0,
  'Pepe no edita al equipo, ni a sí mismo'
);

select tests.authenticate_as('gerente_c');

select is(
  tests.filas($$ update public.miembros set nombre = 'Otro' where id = 302 $$),
  0,
  '8 · Gerente C, con la licencia pausada, no edita a su equipo'
);


-- ─── Agregar empleado ─────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select ok(
  public.puedo_cambiar_equipo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  and not public.puedo_cambiar_equipo('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'El Worker pregunta: Gerente A puede cambiar el equipo de A, no el de B'
);

select ok(
  public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('nuevo1'),
                       ' Doña Mari ', '{cocina}', repeat('3', 64)) > 0,
  'Gerente A da de alta a Doña Mari'
);

select is(
  (select roles from public.miembros where nombre = 'Doña Mari'),
  '{cocina}'::text[],
  'Con su nombre limpio y su rol'
);

select lives_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Rosa', '{caja,mesero,mesero}', %L) $$,
         tests.get_supabase_uid('nuevo2'), repeat('4', 64)),
  'Los roles pueden venir en cualquier orden y repetidos'
);

select is(
  (select roles from public.miembros where nombre = 'Rosa'),
  '{mesero,caja}'::text[],
  'Y se guardan en orden, sin repetir'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Jefe', '{gerente}', %L) $$,
         tests.get_supabase_uid('nuevo3'), repeat('5', 64)),
  '22023', 'Elige al menos un rol: mesero, caja o cocina',
  'No se da de alta a un gerente'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Nadie', '{}', %L) $$,
         tests.get_supabase_uid('nuevo3'), repeat('5', 64)),
  '22023', 'Elige al menos un rol: mesero, caja o cocina',
  'Ni sin roles'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Chava', '{mesero}', '1234') $$,
         tests.get_supabase_uid('nuevo3')),
  '22023', 'Falta el PIN',
  'El PIN llega mezclado por el Worker: un PIN tal cual no entra'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Chava', '{mesero}', %L) $$,
         tests.get_supabase_uid('normal'), repeat('5', 64)),
  '42501', 'Esa cuenta no es una cuenta nueva del personal',
  'Una cuenta que no es del personal no se da de alta'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Chava', '{mesero}', %L) $$,
         tests.get_supabase_uid('nuevo1'), repeat('5', 64)),
  '42501', 'Esa cuenta no es una cuenta nueva del personal',
  'Ni una del personal que ya está en un restaurante'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'pepe martínez', '{mesero}', %L) $$,
         tests.get_supabase_uid('nuevo3'), repeat('5', 64)),
  '23505', null,
  'Un nombre repetido no entra'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Chava', '{mesero}', %L) $$,
         tests.get_supabase_uid('nuevo3'), repeat('5', 64)),
  '42501', null,
  '7 · Gerente B no da de alta en A'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000002');

select ok(
  not public.puedo_cambiar_equipo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'Pepe no puede cambiar el equipo'
);

select throws_ok(
  format($$ select public.alta_empleado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, 'Chava', '{mesero}', %L) $$,
         tests.get_supabase_uid('nuevo3'), repeat('5', 64)),
  '42501', null,
  '7 · Ni da de alta'
);

select tests.authenticate_as('gerente_c');

select throws_ok(
  format($$ select public.alta_empleado('cccccccc-cccc-4ccc-8ccc-cccccccccccc', %L, 'Chava', '{mesero}', %L) $$,
         tests.get_supabase_uid('nuevo3'), repeat('5', 64)),
  '42501', null,
  '8 · Gerente C, con la licencia pausada, no da de alta'
);

reset role;

select ok(
  (select extensions.crypt(repeat('3', 64), pin_hash) = pin_hash from public.miembros where nombre = 'Doña Mari'),
  'Se guardó la huella bcrypt del PIN, no el PIN'
);


-- ─── PIN nuevo y desbloquear ──────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.asignar_pin(105, $$ || quote_literal(repeat('7', 64)) || $$) $$,
  'Gerente A le pone PIN nuevo a Beto'
);

reset role;

select results_eq(
  'select intentos_fallidos, bloqueado_hasta from public.miembros where id = 105',
  $$ values (0::smallint, null::timestamptz) $$,
  'Y con el PIN nuevo, Beto queda desbloqueado'
);

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.asignar_pin(101, $$ || quote_literal(repeat('8', 64)) || $$) $$,
  'Gerente A pone su propio PIN'
);

select ok(
  (select tiene_pin from public.miembros where id = 101),
  'Y ya tiene PIN'
);

select throws_ok(
  $$ select public.asignar_pin(102, $$ || quote_literal(repeat('8', 64)) || $$) $$,
  '42501', null,
  '20 · No cambia el PIN de otro gerente'
);

select throws_ok(
  $$ select public.asignar_pin(106, $$ || quote_literal(repeat('8', 64)) || $$) $$,
  '42501', null,
  'Ni el de alguien dado de baja'
);

select throws_ok(
  'select public.asignar_pin(103, ''1234'')',
  '22023', 'Falta el PIN',
  'Un PIN sin mezclar no entra'
);

reset role;
update public.miembros set bloqueado_hasta = 'infinity' where id = 105;
select tests.authenticate_as('gerente_a');

select lives_ok(
  'select public.desbloquear_miembro(105)',
  'Gerente A desbloquea a Beto'
);

select is(
  (select bloqueado_hasta from public.miembros where id = 105),
  null::timestamptz,
  'Y Beto ya no está bloqueado'
);

select lives_ok(
  'select public.desbloquear_miembro(101)',
  'Se puede desbloquear a sí mismo'
);

select throws_ok(
  'select public.desbloquear_miembro(102)',
  '42501', null,
  'A otro gerente, no'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.asignar_pin(103, $$ || quote_literal(repeat('8', 64)) || $$) $$,
  '42501', null,
  '7 · Gerente B no cambia PINs de A'
);

select throws_ok(
  'select public.desbloquear_miembro(105)',
  '42501', null,
  '7 · Ni desbloquea en A'
);

select tests.authenticate_as('lupita');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.asignar_pin(103, $$ || quote_literal(repeat('8', 64)) || $$) $$,
  '42501', null,
  'La caja no cambia PINs'
);


-- ─── Vincular aparato: el código ──────────────────────────────────────────────

reset role;

insert into public.codigos_vinculo (restaurante_id, codigo, nombre, creado_por, expira_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'VVVVVV', 'Vencido', 101, now() - interval '1 minute');

select tests.como_worker();

select throws_ok(
  format('select public.vincular_aparato(%L, %L)', 'VVVVVV', repeat('F', 43)),
  'P0002', 'Ese código no existe o ya venció. Pídele otro a tu gerente.',
  'Un código vencido no sirve'
);

select tests.authenticate_as('gerente_a');

select matches(
  (select codigo from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', ' Tableta cocina ', null)),
  '^[A-HJKMNP-Z]{6}$',
  'Gerente A pide un código: 6 letras, sin I, L ni O'
);

reset role;

select ok(
  (select expira_at between now() + interval '9 minutes 59 seconds' and now() + interval '10 minutes'
   from public.codigos_vinculo where nombre = 'Tableta cocina'),
  'Que vence en 10 minutos'
);

select is_empty(
  $$ select id from public.codigos_vinculo where codigo = 'VVVVVV' $$,
  'Y los vencidos se limpian'
);

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Celular de Lupita', 104) $$,
  'Pide otro para el celular de Lupita'
);

select lives_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Tableta vieja', null) $$,
  'El nombre de un aparato desligado se puede volver a usar'
);

select throws_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'tableta caja', null) $$,
  '23505', 'Ya tienes un aparato que se llama «tableta caja»',
  'No se repite el nombre de un aparato ligado'
);

select throws_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Celular del jefe', 102) $$,
  '22023', 'Ese aparato solo puede ser de alguien activo de tu equipo',
  'Un aparato no es de un gerente'
);

select throws_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Celular ajeno', 202) $$,
  '22023', 'Ese aparato solo puede ser de alguien activo de tu equipo',
  'Ni de alguien de B'
);

select throws_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  ', null) $$,
  '22023', 'Escribe el nombre del aparato',
  'Sin nombre no hay código'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select * from public.crear_codigo_vinculo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Intruso', null) $$,
  '42501', null,
  '7 · Gerente B no pide códigos de A'
);

select tests.authenticate_as('gerente_d');

select throws_ok(
  $$ select * from public.crear_codigo_vinculo('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Tableta D', null) $$,
  '42501', null,
  '22 · Gerente D, que venció ayer, no liga aparatos'
);


-- ─── Vincular aparato: el aparato escribe el código ───────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  format('select public.vincular_aparato(%L, %L)', 'AAAAAA', repeat('F', 43)),
  '42501', null,
  'Con sesión de usuario nadie llama a vincular_aparato'
);

select tests.como_worker();

select throws_ok(
  format('select public.vincular_aparato(%L, %L)',
         (select codigo from public.codigos_vinculo where nombre = 'Tableta cocina'), 'corto'),
  '22023', 'El secreto del aparato no es válido',
  'El secreto del aparato tiene que ser largo'
);

select is(
  public.vincular_aparato(
    lower(' ' || (select codigo from public.codigos_vinculo where nombre = 'Tableta cocina') || ' '),
    repeat('F', 43)
  ) - 'dispositivo_id',
  '{"aparato": "Tableta cocina", "compartido": true}'::jsonb,
  'La tableta escribe el código (en minúsculas y con espacios) y queda ligada'
);

reset role;

select results_eq(
  $$ select token_hash, vinculado_por, miembro_id from public.dispositivos where nombre = 'Tableta cocina' $$,
  $$ values (tests.huella(repeat('F', 43)), 101::bigint, null::bigint) $$,
  'Con la huella de su secreto y el gerente que la ligó'
);

select is_empty(
  $$ select id from public.codigos_vinculo where nombre = 'Tableta cocina' $$,
  'El código sirvió una vez y se borró'
);

update public.miembros set activo = false where id = 104;

select tests.como_worker();

select throws_ok(
  format('select public.vincular_aparato(%L, %L)',
         (select codigo from public.codigos_vinculo where nombre = 'Celular de Lupita'), repeat('G', 43)),
  '22023', 'La persona de este aparato ya no está en el equipo. Pídele otro código a tu gerente.',
  'Si su dueña ya se dio de baja, el código no liga el aparato'
);

reset role;

update public.miembros set activo = true where id = 104;
insert into public.codigos_vinculo (restaurante_id, codigo, nombre, creado_por, expira_at)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'CCCCCC', 'Tableta C2', 301, now() + interval '5 minutes');

select tests.como_worker();

select throws_ok(
  format('select public.vincular_aparato(%L, %L)', 'CCCCCC', repeat('H', 43)),
  '42501', 'La suscripción de este restaurante no está vigente. Avísale a tu gerente.',
  '8 · Con la licencia pausada no se liga nada'
);


-- ─── ¿Quién eres? ─────────────────────────────────────────────────────────────

select is(
  public.nombres_del_aparato(repeat('A', 43)) - 'personas',
  '{"restaurante": "Restaurante A", "aparato": "Tableta caja", "compartido": true}'::jsonb,
  'La tableta compartida sabe de qué restaurante es'
);

select is(
  jsonb_path_query_array(public.nombres_del_aparato(repeat('A', 43)), '$.personas[*].nombre'),
  '["Beto Sánchez", "Doña Mari", "Lupita Ramírez", "Pepe Martínez", "Rosa"]'::jsonb,
  'En la tableta compartida sale el equipo activo con PIN, sin gerentes ni bajas, por nombre'
);

select is(
  jsonb_path_query_array(public.nombres_del_aparato(repeat('B', 43)), '$.personas[*].nombre'),
  '["Pepe Martínez"]'::jsonb,
  'En el celular de Pepe solo sale Pepe'
);

select throws_ok(
  format('select public.nombres_del_aparato(%L)', repeat('C', 43)),
  'P0002', 'Este aparato ya no está ligado. Pídele a tu gerente un código nuevo.',
  'Una tableta desligada ya no tiene lista'
);

select throws_ok(
  format('select public.nombres_del_aparato(%L)', repeat('Z', 43)),
  'P0002', null,
  'Un secreto que no es de ningún aparato, tampoco'
);

select throws_ok(
  format('select public.nombres_del_aparato(%L)', repeat('E', 43)),
  '42501', null,
  '8 · Ni la tableta de un restaurante pausado'
);


-- ─── Entrar con PIN ───────────────────────────────────────────────────────────

select is(
  public.entrar_con_pin(repeat('B', 43), 103, repeat('1', 64)) - 'usuario_id',
  '{"ok": true, "correo": "pepe@personal.prueba.test"}'::jsonb,
  'Pepe entra en su celular con su PIN'
);

reset role;

select ok(
  (select ultimo_uso_at > now() - interval '1 minute' from public.dispositivos where nombre = 'Celular de Pepe'),
  'Y su celular anota cuándo se usó'
);

select tests.como_worker();

select throws_ok(
  format('select public.entrar_con_pin(%L, 104, %L)', repeat('B', 43), repeat('1', 64)),
  '42501', 'Esa persona no puede entrar en este aparato',
  'Lupita no entra en el celular de Pepe'
);

select throws_ok(
  format('select public.entrar_con_pin(%L, 102, %L)', repeat('A', 43), repeat('1', 64)),
  '42501', null,
  'Un gerente no entra con PIN en un aparato'
);

select throws_ok(
  format('select public.entrar_con_pin(%L, 202, %L)', repeat('A', 43), repeat('1', 64)),
  '42501', null,
  'El mesero de B no entra en la tableta de A'
);

select throws_ok(
  format('select public.entrar_con_pin(%L, 106, %L)', repeat('A', 43), repeat('1', 64)),
  '42501', null,
  'Quien está de baja no entra'
);

select is(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)),
  '{"ok": false, "motivo": "pin", "quedan": 4}'::jsonb,
  'Un PIN equivocado: le quedan 4 intentos'
);

select is(
  public.entrar_con_pin(repeat('A', 43), 104, '1234') ->> 'quedan',
  '3',
  'Un PIN sin mezclar cuenta como equivocado'
);

select is(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)) ->> 'quedan',
  '2',
  'Le quedan 2'
);

select is(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)) ->> 'quedan',
  '1',
  'Le queda 1'
);

select ok(
  (select (r ->> 'motivo') = 'bloqueado'
          and (r ->> 'hasta')::timestamptz between now() + interval '14 minutes 59 seconds' and now() + interval '15 minutes'
   from public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)) as r),
  'Al quinto, Lupita queda bloqueada 15 minutos'
);

select is(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('1', 64)) ->> 'motivo',
  'bloqueado',
  'Mientras está bloqueada, ni con su PIN entra'
);

select is(
  jsonb_path_query_first(public.nombres_del_aparato(repeat('A', 43)), '$.personas[*] ? (@.nombre == "Lupita Ramírez").bloqueado'),
  'true'::jsonb,
  'En la tableta sale bloqueada'
);

reset role;

-- Pasaron los 15 minutos, el mismo día de negocio.
update public.miembros set bloqueado_hasta = now() - interval '1 minute' where id = 104;

select tests.como_worker();

select ok(
  (select bool_and(public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)) ->> 'motivo' = 'pin')
   from generate_series(1, 4)),
  'Ya puede volver a intentar'
);

select is(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)),
  '{"ok": false, "motivo": "bloqueado", "hasta": null}'::jsonb,
  'Si se vuelve a bloquear el mismo día, es hasta que su gerente la desbloquee'
);

reset role;

select is(
  (select bloqueado_hasta from public.miembros where id = 104),
  'infinity'::timestamptz,
  'Guardado como infinity'
);

-- El bloqueo anterior fue ayer.
update public.miembros set bloqueado_hasta = now() - interval '1 day', intentos_fallidos = 4 where id = 104;

select tests.como_worker();

select isnt(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('2', 64)) ->> 'hasta',
  null::text,
  'Si el bloqueo anterior fue otro día, vuelven a ser 15 minutos'
);

reset role;

update public.miembros set bloqueado_hasta = null, intentos_fallidos = 3 where id = 104;

select tests.como_worker();

select is(
  public.entrar_con_pin(repeat('A', 43), 104, repeat('1', 64)) ->> 'ok',
  'true',
  'Lupita entra bien'
);

reset role;

select is(
  (select intentos_fallidos from public.miembros where id = 104),
  0::smallint,
  'Y sus intentos vuelven a 0'
);


-- ─── La sesión de cada aparato ────────────────────────────────────────────────

select tests.como_worker();

select lives_ok(
  format('select public.registrar_sesion(%L, 103, %L)', repeat('B', 43), '5e5e0000-0000-4000-8000-0000000000b2'),
  'El Worker registra la sesión nueva de Pepe en su celular'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000002');

select is_empty(
  'select id from public.miembros',
  'La sesión anterior de Pepe ya no funciona'
);

select tests.en_aparato('5e5e0000-0000-4000-8000-0000000000b2');

select isnt_empty(
  'select id from public.miembros',
  'La nueva sí'
);

select tests.como_worker();

select lives_ok(
  format('select public.registrar_sesion(%L, 105, %L)', repeat('A', 43), '5e5e0000-0000-4000-8000-0000000000a5'),
  'En la tableta compartida entra Beto'
);

select tests.authenticate_as('lupita');
select tests.en_aparato('5e5e0000-0000-4000-8000-000000000001');

select is_empty(
  'select id from public.miembros',
  'Cambiar de persona: la sesión de Lupita en la tableta deja de funcionar'
);

select tests.como_worker();

select throws_ok(
  format('select public.registrar_sesion(%L, 104, %L)', repeat('B', 43), '5e5e0000-0000-4000-8000-0000000000c4'),
  '42501', null,
  'No se registra a Lupita en el celular de Pepe'
);

select throws_ok(
  format('select public.registrar_sesion(%L, 105, null)', repeat('A', 43)),
  '22023', 'Falta la sesión',
  'Sin sesión no hay nada que registrar'
);

select throws_ok(
  format('select public.registrar_sesion(%L, 105, %L)', repeat('C', 43), '5e5e0000-0000-4000-8000-0000000000c5'),
  'P0002', null,
  'En una tableta desligada no se registra nada'
);


-- ─── Desligar y dar de baja ───────────────────────────────────────────────────

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.desligar_aparato('d0000000-0000-4000-8000-000000000001') $$,
  '42501', null,
  '7 · Gerente B no desliga aparatos de A'
);

select tests.authenticate_as('beto');
select tests.en_aparato('5e5e0000-0000-4000-8000-0000000000a5');

select throws_ok(
  $$ select public.desligar_aparato('d0000000-0000-4000-8000-000000000001') $$,
  '42501', null,
  'La cocina no desliga aparatos'
);

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.desligar_aparato('d0000000-0000-4000-8000-000000000001') $$,
  'Gerente A desliga la tableta de la caja'
);

select tests.authenticate_as('beto');
select tests.en_aparato('5e5e0000-0000-4000-8000-0000000000a5');

select is_empty(
  'select id from public.miembros',
  'Quien estaba adentro sale en su siguiente consulta'
);

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.desligar_aparato('d0000000-0000-4000-8000-000000000001') $$,
  '42501', null,
  'Una ya desligada no se vuelve a desligar'
);

select is(
  tests.filas($$ update public.miembros set activo = false where id = 103 $$),
  1,
  'Gerente A da de baja a Pepe'
);

reset role;

select results_eq(
  $$ select revocado_at is not null, sesion_id from public.dispositivos where nombre = 'Celular de Pepe' $$,
  $$ values (true, null::uuid) $$,
  'Y el celular de Pepe queda desligado'
);

select is(
  (select revocado_at from public.dispositivos where nombre = 'Tableta cocina'),
  null::timestamptz,
  'La tableta de la cocina sigue ligada'
);

select tests.authenticate_as('gerente_a');

select is(
  tests.filas($$ update public.miembros set activo = true where id = 103 $$),
  0,
  'Quien está de baja no se reactiva: se da de alta otra vez'
);


-- ─── Aislamiento ──────────────────────────────────────────────────────────────

select throws_ok(
  $$ insert into public.dispositivos (restaurante_id, nombre, token_hash)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Directo', repeat('0', 64)) $$,
  '42501', null,
  '3 · Gerente A no inserta aparatos directo'
);

select throws_ok(
  $$ update public.dispositivos set revocado_at = null where nombre = 'Tableta caja' $$,
  '42501', null,
  'Ni los reactiva directo'
);

reset role;

select throws_ok(
  $$ insert into public.dispositivos (restaurante_id, nombre, token_hash, vinculado_por)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cruzado', repeat('1', 64), 201) $$,
  '23503', null,
  '21 · Un aparato de A no lo pudo ligar un gerente de B'
);

select throws_ok(
  $$ insert into public.dispositivos (restaurante_id, nombre, token_hash, miembro_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cruzado', repeat('2', 64), 202) $$,
  '23503', null,
  '21 · Ni es de un mesero de B'
);

select throws_ok(
  $$ insert into public.codigos_vinculo (restaurante_id, codigo, nombre, creado_por, expira_at)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'QQQQQQ', 'Cruzado', 201, now()) $$,
  '23503', null,
  '21 · Ni un código de A lo pidió un gerente de B'
);

select tests.clear_authentication();

select throws_ok(
  'select id from public.dispositivos',
  '42501', null,
  '16 · El cliente sin sesión no lee aparatos'
);

select throws_ok(
  format('select public.entrar_con_pin(%L, 104, %L)', repeat('A', 43), repeat('1', 64)),
  '42501', null,
  '16 · Ni entra con PIN sin pasar por el Worker'
);

select tests.authenticate_as('fragmentless');

select is_empty(
  'select id from public.dispositivos',
  '18 · Fragmentless no ve los aparatos de nadie'
);

select tests.authenticate_as('gerente_c');

select is_empty(
  'select id from public.dispositivos',
  '8 · Gerente C, con la licencia pausada, no ve sus aparatos'
);

select tests.authenticate_as('gerente_e');

select ok(
  public.puedo_cambiar_equipo('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
  '22 · Gerente E, que vence hoy, sí cambia su equipo'
);


select * from finish();

rollback;
