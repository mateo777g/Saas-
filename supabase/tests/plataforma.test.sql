-- Pruebas de aislamiento de la migración de plataforma (libreta 2, "Pruebas de
-- aislamiento"). Trae la 1, 2, 3, 4, 5, 8, 9, 14, 16 y 17, la 18 leyendo miembros
-- en vez de ventas, la parte de la 20 del último gerente y de la 22 a la 26. Cada
-- descripción empieza con el número de su prueba en la libreta.
--
-- Escenario: los restaurantes A y B vigentes, C pausado, D venció ayer y E vence
-- hoy; un mesero de A dado de baja; Fragmentless; dos distribuidores (Juanito tiene
-- asignado a A); una cuenta de Don Chuy sin ligar todavía; y el cliente sin sesión.
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

grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas. Las fechas de A a E se cuentan en
-- su zona (America/Mexico_City, la de default), igual que la licencia.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('pedro', 'pedro@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('mesero_baja_a', 'mesero.baja.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('mesero_b', 'mesero.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');
  perform tests.create_supabase_user('gerente_e', 'gerente.e@prueba.test');
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, usuario_id) values
    ('Juanito', tests.get_supabase_uid('juanito')),
    ('Pedro', tests.get_supabase_uid('pedro'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Restaurante A', 'restaurante-a', true,  hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Restaurante B', 'restaurante-b', true,  hoy - 30, hoy + 30, null),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30, null),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Restaurante D', 'restaurante-d', true,  hoy - 31, hoy - 1,  null),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Restaurante E', 'restaurante-e', true,  hoy - 30, hoy,      null);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('gerente_a'),     'Gerente A',           '{gerente}', true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('mesero_a'),      'Mesero A',            '{mesero}',  true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('mesero_baja_a'), 'Mesero A dado de baja', '{mesero}', false),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('gerente_b'),     'Gerente B',           '{gerente}', true),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('mesero_b'),      'Mesero B',            '{mesero}',  true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('gerente_c'),     'Gerente C',           '{gerente}', true),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.get_supabase_uid('gerente_d'),     'Gerente D',           '{gerente}', true),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.get_supabase_uid('gerente_e'),     'Gerente E',           '{gerente}', true);
end;
$$;

select plan(96);


-- ─── 1 · La prueba misma revisa tablas y funciones ────────────────────────────

select is_empty(
  $$ select c.relname
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity $$,
  '1 · Todas las tablas de public tienen RLS'
);

select is_empty(
  $$ select c.relname
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and c.relname not in ('restaurantes', 'plataforma_admins', 'distribuidores')
       and not exists (
         select 1 from pg_attribute a
         where a.attrelid = c.oid and a.attname = 'restaurante_id' and not a.attisdropped
       ) $$,
  '1 · Todas las tablas, salvo restaurantes, plataforma_admins y distribuidores, llevan restaurante_id'
);

select is_empty(
  $$ select c.relname || ': ' || r.rol || ' ' || p.permiso
     from pg_class c join pg_namespace n on n.oid = c.relnamespace,
          unnest(array['anon', 'authenticated']) as r(rol),
          unnest(array['TRUNCATE', 'TRIGGER', 'REFERENCES', 'MAINTAIN']) as p(permiso)
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and (has_table_privilege(r.rol, c.oid, p.permiso)
            or (p.permiso = 'REFERENCES' and has_any_column_privilege(r.rol, c.oid, 'REFERENCES'))) $$,
  '1 · Ninguna tabla le da a anon ni a authenticated truncate, trigger, references ni maintain'
);

select is_empty(
  $$ select c.relname
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
       and (has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE')
            or has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE')) $$,
  '1 · anon no tiene ningún permiso sobre las tablas'
);

select is_empty(
  $$ select c.relname
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('restaurantes', 'plataforma_admins', 'distribuidores', 'miembros')
       and (has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE')
            or has_any_column_privilege('authenticated', c.oid, 'INSERT, UPDATE')) $$,
  '1 · Nadie con sesión escribe directo en las 4 tablas de la plataforma'
);

-- Cuando llegue menu_publico, será la única excepción.
select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'privado') and has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  '1 · Ninguna función de public ni de privado se puede ejecutar como anon'
);

select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and not (p.prosecdef and coalesce(p.proconfig, '{}') @> array['search_path=""']) $$,
  '1 · Las funciones de public son security definer con search_path vacío'
);

select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'privado'
       and not coalesce(p.proconfig, '{}') @> array['search_path=""'] $$,
  '1 · Las funciones de privado tienen search_path vacío'
);


-- ─── 2 · Gerente A lee cada tabla ─────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select results_eq(
  'select id from public.restaurantes',
  array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid],
  '2 · Gerente A lee solo la fila de A en restaurantes'
);

select set_eq(
  'select nombre from public.miembros',
  array['Gerente A', 'Mesero A', 'Mesero A dado de baja'],
  '2 · Gerente A lee los 3 miembros de A y ninguno de B ni de C'
);

select is_empty(
  'select id from public.distribuidores',
  '2 · Gerente A no lee distribuidores'
);

select is_empty(
  'select usuario_id from public.plataforma_admins',
  '2 · Gerente A no lee plataforma_admins'
);

select tests.authenticate_as('mesero_a');

select results_eq(
  'select id from public.restaurantes',
  array['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid],
  '2 · El mesero de A también lee solo su restaurante'
);

select set_eq(
  'select nombre from public.miembros',
  array['Gerente A', 'Mesero A', 'Mesero A dado de baja'],
  '2 · El mesero de A lee solo los miembros de A'
);


-- ─── 3 · Gerente A inserta filas ajenas ───────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  format(
    'insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values (%L, %L, %L, %L)',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('gerente_a'), 'Intruso', '{gerente}'
  ),
  '42501', null,
  '3 · Gerente A no puede meterse como miembro de B'
);

select throws_ok(
  format(
    'insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values (%L, %L, %L, %L)',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{mesero}'
  ),
  '42501', null,
  '3 · Gerente A tampoco agrega miembros a A directo: nadie escribe en la tabla'
);

select throws_ok(
  $$ insert into public.restaurantes (nombre, slug) values ('Otro local', 'otro-local') $$,
  '42501', null,
  '3 · Gerente A no puede crear restaurantes'
);

select throws_ok(
  $$ insert into public.distribuidores (nombre) values ('Yo mismo') $$,
  '42501', null,
  '3 · Gerente A no puede crear distribuidores'
);


-- ─── 4 · Gerente A cambia o borra filas de B ──────────────────────────────────

select throws_ok(
  $$ update public.restaurantes set nombre = 'Hackeado' where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '42501', null,
  '4 · Gerente A no puede cambiar el restaurante B'
);

select throws_ok(
  $$ delete from public.restaurantes where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '42501', null,
  '4 · Gerente A no puede borrar el restaurante B'
);

select throws_ok(
  $$ update public.miembros set nombre = 'Hackeado' where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '42501', null,
  '4 · Gerente A no puede cambiar miembros de B'
);

select throws_ok(
  $$ delete from public.miembros where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '42501', null,
  '4 · Gerente A no puede borrar miembros de B'
);

select tests.authenticate_as('gerente_b');

select results_eq(
  'select nombre from public.restaurantes',
  array['Restaurante B'],
  '4 · Revisado como B, su restaurante sigue igual'
);

select set_eq(
  'select nombre from public.miembros',
  array['Gerente B', 'Mesero B'],
  '4 · Revisado como B, sus miembros siguen igual'
);


-- ─── 5 · Gerente A pasa una fila suya a B ─────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ update public.miembros set restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where nombre = 'Mesero A' $$,
  '42501', null,
  '5 · Gerente A no puede pasar a su mesero a B'
);


-- ─── 8 · Gerente C, con la licencia pausada ───────────────────────────────────

select tests.authenticate_as('gerente_c');

select results_eq(
  'select id, licencia_activa from public.restaurantes',
  $$ values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid, false) $$,
  '8 · Gerente C solo ve la fila de su restaurante, pausado'
);

select is_empty(
  $$ select id::text from public.miembros
     union all select id::text from public.distribuidores
     union all select usuario_id::text from public.plataforma_admins $$,
  '8 · Gerente C ve 0 filas en lo demás, ni su propio miembro'
);

select throws_ok(
  $$ update public.restaurantes set nombre = 'Otro nombre' where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' $$,
  '42501', null,
  '8 · Gerente C no puede escribir en su restaurante'
);

select throws_ok(
  $$ update public.miembros set nombre = 'Otro nombre' where restaurante_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' $$,
  '42501', null,
  '8 · Gerente C no puede escribir en sus miembros'
);


-- ─── 9 · Mesero de A dado de baja ─────────────────────────────────────────────

select tests.authenticate_as('mesero_baja_a');

select is_empty(
  $$ select id::text from public.restaurantes
     union all select id::text from public.miembros
     union all select id::text from public.distribuidores
     union all select usuario_id::text from public.plataforma_admins $$,
  '9 · El mesero dado de baja ve 0 filas en todo, ni su restaurante'
);


-- ─── 22 · Gerente D (venció ayer) y gerente E (vence hoy) ────────────────────

select tests.authenticate_as('gerente_d');

select results_eq(
  'select id from public.restaurantes',
  array['dddddddd-dddd-4ddd-8ddd-dddddddddddd'::uuid],
  '22 · Gerente D solo ve la fila de su restaurante'
);

select is_empty(
  'select id from public.miembros',
  '22 · Gerente D ve 0 filas en lo demás'
);

select tests.authenticate_as('gerente_e');

select results_eq(
  'select id from public.restaurantes',
  array['eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid],
  '22 · Gerente E ve su restaurante'
);

select set_eq(
  'select nombre from public.miembros',
  array['Gerente E'],
  '22 · Gerente E todavía ve sus miembros el día que vence'
);

-- El día se cuenta en la zona del restaurante: en CDMX (UTC-6) el 8 de octubre
-- dura hasta las 05:59:59 UTC del 9.
reset role;

select is(
  privado.dia_local('America/Mexico_City', '2026-10-09 05:59:59+00'),
  '2026-10-08'::date,
  '22 · A las 11:59:59 pm del 8 de octubre en CDMX todavía es el día 8'
);

select is(
  privado.dia_local('America/Mexico_City', '2026-10-09 06:00:00+00'),
  '2026-10-09'::date,
  '22 · A la medianoche en CDMX ya es el día 9'
);


-- ─── 14 · Gerente A intenta tocar su licencia o su tope de IA ─────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ update public.restaurantes set licencia_activa = true where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null,
  '14 · Gerente A no puede prender su licencia'
);

select throws_ok(
  $$ update public.restaurantes set licencia_fin = '2099-12-31' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null,
  '14 · Gerente A no puede mover su fecha de fin'
);

select throws_ok(
  $$ update public.restaurantes set tope_ia_usd_mes = 1000 where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null,
  '14 · Gerente A no puede subir su tope de IA'
);

select throws_ok(
  $$ select public.extender_licencia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 12) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  '14 · Gerente A no puede extender su licencia'
);

select throws_ok(
  $$ select public.fijar_licencia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true, '2026-01-01', '2099-12-31') $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  '14 · Gerente A no puede fijar su licencia'
);

select throws_ok(
  $$ select public.alta_restaurante('Mi otro local', 'mi-otro-local', '2026-10-08', 12) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  '14 · Gerente A no puede dar de alta restaurantes'
);

select throws_ok(
  $$ select public.ligar_gerente('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'gerente.a@prueba.test', 'Gerente A') $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  '14 · Gerente A no puede ligarse como gerente de B'
);


-- ─── 16 · Cliente sin sesión ──────────────────────────────────────────────────

select tests.clear_authentication();

select throws_ok('select id from public.restaurantes', '42501', null, '16 · Sin sesión no se lee restaurantes');
select throws_ok('select usuario_id from public.plataforma_admins', '42501', null, '16 · Sin sesión no se lee plataforma_admins');
select throws_ok('select id from public.distribuidores', '42501', null, '16 · Sin sesión no se lee distribuidores');
select throws_ok('select id from public.miembros', '42501', null, '16 · Sin sesión no se lee miembros');

select throws_ok(
  $$ insert into public.restaurantes (nombre, slug) values ('Pirata', 'pirata') $$,
  '42501', null,
  '16 · Sin sesión no se escribe en ninguna tabla'
);

select throws_ok(
  $$ select public.alta_restaurante('Pirata', 'pirata', '2026-10-08', 12) $$,
  '42501', null,
  '16 · Sin sesión no se llama alta_restaurante'
);

select throws_ok(
  $$ select public.ligar_gerente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pirata@prueba.test', 'Pirata') $$,
  '42501', null,
  '16 · Sin sesión no se llama ligar_gerente'
);

select throws_ok(
  $$ select public.extender_licencia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 12) $$,
  '42501', null,
  '16 · Sin sesión no se llama extender_licencia'
);

select throws_ok(
  $$ select public.fijar_licencia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false, null, null) $$,
  '42501', null,
  '16 · Sin sesión no se llama fijar_licencia'
);

select throws_ok(
  'select privado.mis_restaurantes()',
  '42501', null,
  '16 · Sin sesión no se llama nada de privado'
);


-- ─── 23 · Distribuidor ────────────────────────────────────────────────────────

select tests.authenticate_as('juanito');

select results_eq(
  'select nombre from public.distribuidores',
  array['Juanito'],
  '23 · Juanito solo lee su propia fila de distribuidores'
);

select is_empty(
  $$ select id::text from public.restaurantes
     union all select id::text from public.miembros
     union all select usuario_id::text from public.plataforma_admins $$,
  '23 · Juanito no lee restaurantes (ni el que tiene asignado), miembros ni plataforma_admins'
);


-- ─── 24 · Agregarse a plataforma_admins desde la API ──────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  format('insert into public.plataforma_admins (usuario_id) values (%L)', tests.get_supabase_uid('gerente_a')),
  '42501', null,
  '24 · Gerente A no puede agregarse a plataforma_admins'
);

select tests.authenticate_as('juanito');

select throws_ok(
  format('insert into public.plataforma_admins (usuario_id) values (%L)', tests.get_supabase_uid('juanito')),
  '42501', null,
  '24 · Juanito no puede agregarse a plataforma_admins'
);

select tests.authenticate_as('fragmentless');

select throws_ok(
  format('insert into public.plataforma_admins (usuario_id) values (%L)', tests.get_supabase_uid('pedro')),
  '42501', null,
  '24 · Ni Fragmentless agrega admins desde la API'
);

select tests.clear_authentication();

select throws_ok(
  format('insert into public.plataforma_admins (usuario_id) values (%L)', tests.get_supabase_uid('don_chuy')),
  '42501', null,
  '24 · Sin sesión tampoco'
);


-- ─── 18 · Fragmentless lee la plataforma, pero no los miembros ────────────────

select tests.authenticate_as('fragmentless');

select is_empty(
  'select id from public.miembros',
  '18 · Fragmentless no lee miembros de ningún restaurante'
);

select set_eq(
  'select slug from public.restaurantes',
  array['restaurante-a', 'restaurante-b', 'restaurante-c', 'restaurante-d', 'restaurante-e'],
  '18 · Fragmentless lee todos los restaurantes'
);

select set_eq(
  'select nombre from public.distribuidores',
  array['Juanito', 'Pedro'],
  '18 · Fragmentless lee todos los distribuidores'
);

select results_eq(
  'select usuario_id from public.plataforma_admins',
  format('select %L::uuid', tests.get_supabase_uid('fragmentless')),
  '18 · Fragmentless lee plataforma_admins'
);


-- ─── 17 · Fragmentless pausa la licencia de A ─────────────────────────────────

select lives_ok(
  $$ select public.fijar_licencia(id, false, licencia_inicio, licencia_fin)
     from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '17 · Fragmentless pausa la licencia de A'
);

select tests.authenticate_as('gerente_a');

select is_empty(
  'select id from public.miembros',
  '17 · En la siguiente consulta, A ya no ve sus miembros'
);

select results_eq(
  'select licencia_activa from public.restaurantes',
  array[false],
  '17 · Gerente A ve su restaurante pausado'
);

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.fijar_licencia(id, true, licencia_inicio, licencia_fin)
     from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '17 · Fragmentless vuelve a prender la licencia de A'
);

select tests.authenticate_as('gerente_a');

select set_eq(
  'select nombre from public.miembros',
  array['Gerente A', 'Mesero A', 'Mesero A dado de baja'],
  '17 · Al prenderla, A vuelve a ver sus miembros'
);


-- ─── 25 · Fragmentless da de alta y suma meses ────────────────────────────────

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.alta_restaurante('Fonda Don Chuy', 'fonda-don-chuy', '2026-10-08', 1) $$,
  '25 · Fragmentless da de alta la fonda de Don Chuy por 1 mes'
);

select results_eq(
  $$ select licencia_activa, licencia_inicio, licencia_fin, zona_horaria, tope_ia_usd_mes
     from public.restaurantes where slug = 'fonda-don-chuy' $$,
  $$ values (true, '2026-10-08'::date, '2026-11-08'::date, 'America/Mexico_City', 0::numeric) $$,
  '25 · Alta el 8 de octubre con 1 mes: prendida, fin el 8 de noviembre y tope de IA en 0'
);

select lives_ok(
  $$ select public.alta_restaurante('Taquería El Güero', 'taqueria-el-guero', '2026-10-08', 12) $$,
  '25 · Fragmentless da de alta la taquería por 12 meses'
);

select results_eq(
  $$ select licencia_fin from public.restaurantes where slug = 'taqueria-el-guero' $$,
  array['2027-10-08'::date],
  '25 · Alta el 8 de octubre con 12 meses: fin el 8 de octubre de 2027'
);

select lives_ok(
  $$ select public.fijar_licencia('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', true, '2026-10-01', '2099-01-15') $$,
  '25 · Fragmentless corrige las fechas de B'
);

select is(
  public.extender_licencia('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1),
  '2099-02-15'::date,
  '25 · Pago antes de vencer: el mes se suma a su fecha de fin'
);

select is(
  public.extender_licencia('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 1),
  ((now() at time zone 'America/Mexico_City')::date + interval '1 month')::date,
  '25 · Pago después de vencer: el mes cuenta desde hoy, el día que paga'
);

select tests.authenticate_as('gerente_d');

select set_eq(
  'select nombre from public.miembros',
  array['Gerente D'],
  '25 · Ya pagado, el gerente de D vuelve a ver sus datos'
);


-- ─── 26 · Errores de Fragmentless ─────────────────────────────────────────────

select tests.authenticate_as('fragmentless');

select throws_ok(
  $$ select public.ligar_gerente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'nadie@prueba.test', 'Nadie') $$,
  'P0002', null,
  '26 · Ligar un correo sin cuenta da error'
);

select lives_ok(
  $$ select public.ligar_gerente(id, 'Don.Chuy@prueba.test', 'Don Chuy')
     from public.restaurantes where slug = 'fonda-don-chuy' $$,
  '26 · Ligar a Don Chuy como gerente de su fonda funciona (sin importar mayúsculas)'
);

select throws_ok(
  $$ select public.ligar_gerente(id, 'don.chuy@prueba.test', 'Don Chuy')
     from public.restaurantes where slug = 'fonda-don-chuy' $$,
  '23505', 'La cuenta don.chuy@prueba.test ya está ligada a este restaurante',
  '26 · Ligar otra vez a la misma persona da error'
);

select tests.authenticate_as('don_chuy');

select results_eq(
  'select slug from public.restaurantes',
  array['fonda-don-chuy'],
  '26 · Don Chuy entra y ve su fonda'
);

reset role;

select is(
  (select roles from public.miembros where nombre = 'Don Chuy'),
  array['gerente'],
  '26 · Don Chuy quedó ligado como gerente'
);

select tests.authenticate_as('fragmentless');

select throws_ok(
  $$ select public.fijar_licencia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true, '2026-10-01', null) $$,
  '23514', null,
  '26 · No se puede prender una licencia sin fecha de fin'
);

select throws_ok(
  $$ select public.alta_restaurante('Fonda Don Chuy', 'Fonda Don Chuy', '2026-10-08', 1) $$,
  '23514', null,
  '26 · El slug "Fonda Don Chuy" da error'
);

select throws_ok(
  $$ select public.alta_restaurante('Otra fonda', 'fonda-don-chuy', '2026-10-08', 1) $$,
  '23505', null,
  '26 · Un slug repetido da error'
);

select throws_ok(
  $$ select public.alta_restaurante('Otra fonda', 'otra-fonda', '2026-10-08', 0) $$,
  '22023', 'Los meses deben ser 1 o más',
  '26 · Dar de alta con 0 meses da error'
);

select throws_ok(
  $$ select public.extender_licencia('00000000-0000-4000-8000-000000000000', 1) $$,
  'P0002', null,
  '26 · Extender un restaurante que no existe da error'
);

-- Ninguna función de Fragmentless recibe la zona todavía: se prueba el trigger
-- directo, como dueño de la tabla.
reset role;

select throws_ok(
  $$ update public.restaurantes set zona_horaria = 'America/Mexico_Cty' where slug = 'restaurante-e' $$,
  '22023', 'Zona horaria desconocida: America/Mexico_Cty',
  '26 · Una zona horaria mal escrita da error'
);

select lives_ok(
  $$ update public.restaurantes set zona_horaria = 'America/Cancun' where slug = 'restaurante-e' $$,
  '26 · Una zona horaria bien escrita se acepta'
);


-- ─── 20 · Siempre queda un gerente ────────────────────────────────────────────
-- Como dueño de la tabla, porque hoy nadie más escribe en miembros.

select throws_ok(
  $$ update public.miembros set activo = false where nombre = 'Gerente A' $$,
  'P0001', 'No se puede quitar al último gerente activo del restaurante',
  '20 · No se puede dar de baja al último gerente'
);

select throws_ok(
  $$ update public.miembros set roles = '{caja}' where nombre = 'Gerente A' $$,
  'P0001', 'No se puede quitar al último gerente activo del restaurante',
  '20 · No se le puede quitar el rol al último gerente'
);

select throws_ok(
  $$ delete from public.miembros where nombre = 'Gerente A' $$,
  'P0001', 'No se puede quitar al último gerente activo del restaurante',
  '20 · No se puede borrar al último gerente'
);

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.ligar_gerente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'gerente.b@prueba.test', 'Gerente B en A') $$,
  '20 · El gerente de B también puede ser gerente de A'
);

reset role;

select throws_ok(
  $$ update public.miembros set activo = false
     where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and 'gerente' = any (roles) $$,
  'P0001', 'No se puede quitar al último gerente activo del restaurante',
  '20 · Dar de baja a los dos gerentes de A en una sola orden da error'
);

select lives_ok(
  $$ update public.miembros set activo = false where nombre = 'Gerente A' $$,
  '20 · Con otro gerente activo, sí se puede dar de baja a uno'
);

select lives_ok(
  $$ delete from public.restaurantes where slug = 'restaurante-b' $$,
  '20 · Borrar el restaurante B completo sí se lleva a su último gerente'
);

select is_empty(
  $$ select id from public.miembros where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '20 · B ya no tiene miembros'
);


select * from finish();

rollback;
