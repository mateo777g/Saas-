-- Pruebas de las mesas (migración mesas). Trae las pruebas de aislamiento de la libreta 2
-- que tocan las mesas (1, 2, 3, 4, 5, la parte de la 6 entre cuentas y mesas, 8, 9, 16,
-- 18 y 22; cada descripción empieza con su número) y lo decidido con la maqueta de Mesas:
-- el orden con flechas, la mesa nueva al final y el borrar o archivar.
--
-- Escenario: los restaurantes A y B vigentes, C pausado, D venció ayer y E vence hoy; en A
-- un gerente, un mesero y un mesero dado de baja; Fragmentless; y el cliente sin sesión. A
-- tiene la Mesa 1, la Mesa 2 y la Barra; la Mesa 2 ya tuvo cuentas.
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




-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas, con ids fijos para poder nombrar filas
-- que quien prueba no alcanza a leer. tests.cuentas hace de las cuentas de la pieza 4: la
-- mesa que señala ya tuvo cuentas.

create table tests.cuentas (
  restaurante_id uuid not null,
  mesa_id bigint not null,
  foreign key (restaurante_id, mesa_id) references public.mesas (restaurante_id, id)
);

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('mesero_baja_a', 'mesero.baja.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');
  perform tests.create_supabase_user('gerente_e', 'gerente.e@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    (a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true),
    (a, tests.get_supabase_uid('mesero_a'), 'Mesero A', '{mesero}', true),
    (a, tests.get_supabase_uid('mesero_baja_a'), 'Mesero A dado de baja', '{mesero}', false),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.get_supabase_uid('gerente_e'), 'Gerente E', '{gerente}', true);

  -- La tableta compartida de A, con la sesión del mesero: así entra el personal (migración empleados).
  insert into public.dispositivos (restaurante_id, nombre, token_hash, sesion_id)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Tableta caja', repeat('a', 64), '5e5e5e5e-0000-4000-8000-00000000000a');

  insert into public.mesas (id, restaurante_id, nombre) overriding system value values
    (701, a, 'Mesa 1'),
    (702, a, 'Mesa 2'),
    (703, a, 'Barra'),
    (711, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Mesa 1'),
    (721, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Mesa 1'),
    (731, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Mesa 1'),
    (741, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Terraza');

  -- La Mesa 2 de A ya tuvo cuentas.
  insert into tests.cuentas (restaurante_id, mesa_id) values (a, 702);
end;
$$;

select plan(54);


-- ─── 1 · Permisos ─────────────────────────────────────────────────────────────

select ok(
  not has_table_privilege('authenticated', 'public.mesas', 'DELETE'),
  '1 · Nadie con sesión borra mesas directo: lo hace eliminar_mesa'
);

select is_empty(
  $$ select c.columna || ' ' || p.permiso
     from unnest(array['orden', 'archivado_at', 'restaurante_id', 'id', 'created_at', 'updated_at']) as c(columna),
          unnest(array['INSERT', 'UPDATE']) as p(permiso)
     where has_column_privilege('authenticated', 'public.mesas', c.columna, p.permiso)
       and not (c.columna = 'restaurante_id' and p.permiso = 'INSERT') $$,
  '1 · Nadie con sesión escribe el orden, el archivado, el restaurante ni las fechas de una mesa'
);

select ok(
  has_function_privilege('authenticated', 'public.mover_mesa(bigint, text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.eliminar_mesa(bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mover_mesa(bigint, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.eliminar_mesa(bigint)', 'EXECUTE'),
  '1 · mover_mesa y eliminar_mesa las llama quien tiene sesión, y cada una revisa quién es; sin sesión no'
);

select ok(
  not has_table_privilege('anon', 'public.mesas', 'SELECT')
  and not has_table_privilege('anon', 'public.mesas', 'INSERT'),
  '1 · Sin sesión no se toca la tabla'
);


-- ─── 2 y 18 · Quién lee las mesas ─────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select results_eq(
  'select nombre, orden from public.mesas order by orden',
  $$ values ('Mesa 1'::text, 1), ('Mesa 2', 2), ('Barra', 3) $$,
  '2 · Gerente A lee las 3 mesas de A, numeradas en el orden en que se crearon'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select set_eq(
  'select id from public.mesas',
  array[701, 702, 703],
  '2 · El mesero de A también las lee'
);

select tests.authenticate_as('gerente_b');

select set_eq(
  'select id from public.mesas',
  array[711],
  '2 · Gerente B lee solo las suyas'
);

select tests.authenticate_as('fragmentless');

select is_empty(
  'select id from public.mesas',
  '18 · Fragmentless no lee las mesas de ningún cliente'
);


-- ─── 3 · Escribir en un restaurante ajeno, o sin ser gerente ──────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Intrusa') $$,
  '42501', null,
  '3 · Gerente A no agrega mesas en B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Del mesero') $$,
  '42501', null,
  '3 · El mesero de A no agrega mesas en A'
);

select is(
  tests.filas($$ update public.mesas set nombre = 'Mesa del mesero' where id = 701 $$),
  0,
  '3 · Ni las renombra'
);


-- ─── 4 · Cambiar o borrar lo de B ─────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  tests.filas($$ update public.mesas set nombre = 'Hackeada' where id = 711 $$),
  0,
  '4 · Gerente A no renombra la mesa de B'
);

select throws_ok(
  $$ delete from public.mesas where id = 711 $$,
  '42501', null,
  '4 · Ni la borra'
);

select tests.authenticate_as('gerente_b');

select results_eq(
  'select nombre, archivado_at is null from public.mesas',
  $$ values ('Mesa 1'::text, true) $$,
  '4 · Revisada como B, su mesa sigue igual'
);


-- ─── 5 y 6 · Pasar filas a B ──────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ update public.mesas set restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where id = 701 $$,
  '42501', null,
  '5 · Gerente A no pasa una mesa suya a B'
);

select tests.clear_authentication();
set local role postgres;

select throws_ok(
  $$ insert into tests.cuentas (restaurante_id, mesa_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 711) $$,
  '23503', null,
  '6 · Una cuenta de A no puede caer en una mesa de B: la llave es compuesta'
);


-- ─── 8, 9 y 22 · Licencia y bajas ─────────────────────────────────────────────

select tests.authenticate_as('gerente_c');

select is_empty(
  'select id from public.mesas',
  '8 · Gerente C, con la licencia pausada, no ve sus mesas'
);

select throws_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Mesa 2') $$,
  '42501', null,
  '8 · Ni agrega'
);

select throws_ok(
  'select public.eliminar_mesa(721)',
  '42501', null,
  '8 · Ni elimina'
);

select tests.authenticate_as('mesero_baja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select is_empty(
  'select id from public.mesas',
  '9 · El mesero de A dado de baja no ve las mesas'
);

select tests.authenticate_as('gerente_d');

select is_empty(
  'select id from public.mesas',
  '22 · Gerente D, que venció ayer, no ve sus mesas'
);

select tests.authenticate_as('gerente_e');

select set_eq(
  'select nombre from public.mesas',
  array['Terraza'],
  '22 · Gerente E, que vence hoy, todavía ve la suya'
);


-- ─── 16 · Sin sesión ──────────────────────────────────────────────────────────

select tests.clear_authentication();

select throws_ok(
  'select id from public.mesas',
  '42501', null,
  '16 · Sin sesión no se leen las mesas'
);

select throws_ok(
  $$ select public.mover_mesa(701, 'abajo') $$,
  '42501', null,
  '16 · Ni se reacomodan'
);


-- ─── Lo que la base pone sola ─────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  Terraza 1  ') $$,
  'Gerente A agrega una mesa'
);

select results_eq(
  $$ select nombre, orden, archivado_at is null from public.mesas where nombre = 'Terraza 1' $$,
  $$ values ('Terraza 1'::text, 4, true) $$,
  'Se guarda sin espacios sobrantes y al final'
);

select throws_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'mesa 1') $$,
  '23505', null,
  'No hay dos mesas con el mismo nombre, aunque cambien las mayúsculas'
);

select throws_ok(
  $$ update public.mesas set nombre = 'BARRA' where id = 701 $$,
  '23505', null,
  'Ni al renombrar'
);

select throws_ok(
  $$ update public.mesas set nombre = '   ' where id = 701 $$,
  '23514', null,
  'Una mesa no se queda sin nombre'
);

select is(
  tests.filas($$ update public.mesas set nombre = ' Mesa uno ' where id = 701 $$),
  1,
  'Gerente A renombra la Mesa 1'
);

select results_eq(
  'select nombre, orden from public.mesas where id = 701',
  $$ values ('Mesa uno'::text, 1) $$,
  'Sin espacios sobrantes y en su mismo lugar'
);

select tests.authenticate_as('gerente_b');

select lives_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Mesa 2') $$,
  'Cada restaurante numera sus mesas aparte: Gerente B agrega la Mesa 2 de B'
);

select results_eq(
  $$ select orden from public.mesas where nombre = 'Mesa 2' $$,
  array[2],
  'Y queda segunda en B, aunque A ya tenga 4'
);


-- ─── mover_mesa ───────────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.mover_mesa(703, 'arriba') $$,
  'Gerente A sube la Barra'
);

select results_eq(
  'select nombre, orden from public.mesas order by orden',
  $$ values ('Mesa uno'::text, 1), ('Barra', 2), ('Mesa 2', 3), ('Terraza 1', 4) $$,
  'La Barra sube un lugar y la Mesa 2 baja'
);

select lives_ok(
  $$ select public.mover_mesa(701, 'arriba') $$,
  'Subir la primera no da error'
);

select lives_ok(
  $$ select public.mover_mesa(id, 'abajo') from public.mesas where nombre = 'Terraza 1' $$,
  'Ni bajar la última'
);

select results_eq(
  'select nombre, orden from public.mesas order by orden',
  $$ values ('Mesa uno'::text, 1), ('Barra', 2), ('Mesa 2', 3), ('Terraza 1', 4) $$,
  'En las orillas no pasa nada'
);

select throws_ok(
  $$ select public.mover_mesa(703, 'izquierda') $$,
  '22023', null,
  'Una mesa solo se mueve arriba o abajo'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ select public.mover_mesa(701, 'abajo') $$,
  '42501', null,
  'El mesero no reacomoda las mesas'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.mover_mesa(701, 'abajo') $$,
  '42501', null,
  'Gerente B no reacomoda las de A'
);


-- ─── eliminar_mesa ────────────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  'select public.eliminar_mesa(701)',
  '42501', null,
  'El mesero no elimina mesas'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  'select public.eliminar_mesa(701)',
  '42501', null,
  'Gerente B no elimina mesas de A'
);

select tests.authenticate_as('gerente_a');

select results_eq(
  'select public.eliminar_mesa(702)',
  array['archivado'],
  'La Mesa 2 ya tuvo cuentas: se archiva'
);

select results_eq(
  'select archivado_at is not null from public.mesas where id = 702',
  array[true],
  'Y sigue en la tabla, para los reportes'
);

select is(
  tests.filas($$ update public.mesas set nombre = 'Mesa vieja' where id = 702 $$),
  0,
  'Una mesa archivada ya no se renombra'
);

select throws_ok(
  'select public.eliminar_mesa(702)',
  '42501', null,
  'Ni se vuelve a eliminar'
);

select throws_ok(
  $$ select public.mover_mesa(702, 'arriba') $$,
  '42501', null,
  'Ni se mueve'
);

select lives_ok(
  $$ select public.mover_mesa(id, 'arriba') from public.mesas where nombre = 'Terraza 1' $$,
  'Gerente A sube la Terraza 1, que tiene arriba a la Mesa 2 archivada'
);

select results_eq(
  'select nombre from public.mesas where archivado_at is null order by orden',
  array['Mesa uno', 'Terraza 1', 'Barra'],
  'Las flechas saltan la archivada: la Terraza 1 queda arriba de la Barra'
);

select results_eq(
  $$ select public.eliminar_mesa(id) from public.mesas where nombre = 'Terraza 1' $$,
  array['borrado'],
  'La Terraza 1 nunca tuvo cuentas: se borra'
);

select is_empty(
  $$ select id from public.mesas where nombre = 'Terraza 1' $$,
  'Y ya no está'
);

select lives_ok(
  $$ insert into public.mesas (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Mesa 2') $$,
  'El nombre de una mesa archivada se puede volver a usar'
);

select results_eq(
  'select nombre from public.mesas where archivado_at is null order by orden',
  array['Mesa uno', 'Barra', 'Mesa 2'],
  'La nueva Mesa 2 va al final'
);


select * from finish();

rollback;
