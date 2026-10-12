-- Pruebas de la migración distribuidores: quién puede llamar sus 5 funciones, qué hace
-- cada una, sus errores en español (los de la maqueta del panel de Fragmentless) y una
-- cuenta, un panel, también en ligar_gerente.
--
-- Escenario: Fragmentless; Juanito Pérez con 3 clientes (la fonda de Don Chuy vigente,
-- Pollos Doña Mary pausado y Mariscos El Faro vencido); Lupita Gómez con 1 (Birria Don
-- Beto); Paty Ruiz de baja; Memo Castillo, todavía sin cuenta ligada, y la cuenta de
-- Memo, que ya existe; Tacos El Güero, cliente directo; Don Chuy, gerente de su fonda, y
-- un mesero de la fonda dado de baja.
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
-- Se siembra como postgres, dueño de las tablas.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('lupita', 'lupita@prueba.test');
  perform tests.create_supabase_user('paty', 'paty@prueba.test');
  perform tests.create_supabase_user('memo', 'memo@prueba.test');
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');
  perform tests.create_supabase_user('mesero_baja', 'mesero.baja@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, telefono, correo, usuario_id, activo) values
    ('Juanito Pérez', '55 0000 0001', 'juanito@prueba.test', tests.get_supabase_uid('juanito'), true),
    ('Lupita Gómez',  '55 0000 0002', 'lupita@prueba.test',  tests.get_supabase_uid('lupita'),  true),
    ('Paty Ruiz',     '55 0000 0006', 'paty@prueba.test',    tests.get_supabase_uid('paty'),    false),
    ('Memo Castillo', '55 0000 0004', 'memo@prueba.test',    null,                              true);

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La fonda de Don Chuy', 'fonda-don-chuy',   true,  hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Juanito Pérez')),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Pollos Doña Mary',     'pollos-dona-mary', false, hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Juanito Pérez')),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Mariscos El Faro',     'mariscos-el-faro', true,  hoy - 31, hoy - 1,
      (select id from public.distribuidores where nombre = 'Juanito Pérez')),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Birria Don Beto',      'birria-don-beto',  true,  hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Lupita Gómez')),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Tacos El Güero',       'tacos-el-guero',   true,  hoy - 30, hoy + 30, null);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('don_chuy'),    'Don Chuy',               '{gerente}', true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('mesero_baja'), 'Mesero dado de baja',    '{mesero}',  false);
end;
$$;

-- El id de un distribuidor por su nombre, para escribir las llamadas como las haría el
-- panel. security definer porque un gerente no lee distribuidores.
create function tests.distribuidor(p_nombre text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.distribuidores where nombre = p_nombre;
$$;

grant execute on function tests.distribuidor(text) to anon, authenticated;

select plan(65);


-- ─── Quién puede llamarlas ────────────────────────────────────────────────────

select is_empty(
  $$ select f from unnest(array[
       'public.alta_distribuidor(text, text, text)',
       'public.ligar_distribuidor(bigint, text)',
       'public.editar_distribuidor(bigint, text, text, text)',
       'public.asignar_distribuidor(uuid, bigint)',
       'public.fijar_distribuidor_activo(bigint, boolean)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE') $$,
  'Con sesión se pueden llamar las 5 funciones'
);

select is_empty(
  $$ select f || ': ' || r
     from unnest(array[
       'public.alta_distribuidor(text, text, text)',
       'public.ligar_distribuidor(bigint, text)',
       'public.editar_distribuidor(bigint, text, text, text)',
       'public.asignar_distribuidor(uuid, bigint)',
       'public.fijar_distribuidor_activo(bigint, boolean)',
       'public.ligar_gerente(uuid, text, text)'
     ]) as f,
     unnest(array['anon', 'service_role']) as r
     where has_function_privilege(r, f, 'EXECUTE') $$,
  'anon y service_role no llaman ninguna, ni ligar_gerente después de volverla a crear'
);

select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'privado' and p.proname = 'cuenta_de_restaurante_o_admin'
       and has_function_privilege('authenticated', p.oid, 'EXECUTE') $$,
  'privado.cuenta_de_restaurante_o_admin no la llama nadie con sesión'
);

select tests.clear_authentication();

select throws_ok(
  $$ select public.alta_distribuidor('Chema Torres', null, null) $$,
  '42501', null,
  'Sin sesión no se da de alta un distribuidor'
);

select tests.authenticate_as('don_chuy');

select throws_ok(
  $$ select public.alta_distribuidor('Chema Torres', null, null) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no da de alta distribuidores'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), 'don.chuy@prueba.test') $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no liga cuentas de distribuidor'
);

select throws_ok(
  $$ select public.editar_distribuidor(tests.distribuidor('Juanito Pérez'), 'Juan', null, null) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no corrige los datos de un distribuidor'
);

select throws_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Don Chuy no se quita a su distribuidor'
);

select throws_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Paty Ruiz'), true) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no da de baja ni reactiva distribuidores'
);

select tests.authenticate_as('juanito');

select throws_ok(
  $$ select public.asignar_distribuidor('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.distribuidor('Juanito Pérez')) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Juanito no se asigna el cliente de Lupita'
);

select throws_ok(
  $$ select public.editar_distribuidor(tests.distribuidor('Juanito Pérez'), 'Juanito', null, null) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Juanito no corrige sus propios datos'
);

select tests.authenticate_as('fragmentless');


-- ─── Dar de baja a quien todavía tiene clientes ───────────────────────────────

select throws_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Juanito Pérez'), false) $$,
  '55000', 'Juanito Pérez todavía tiene 3 clientes; quítaselos primero',
  'Juanito no se da de baja con 3 clientes, aunque uno esté pausado y otro vencido'
);

select throws_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Lupita Gómez'), false) $$,
  '55000', 'Lupita Gómez todavía tiene 1 cliente; quítaselo primero',
  'Con 1 cliente el mensaje va en singular'
);

select results_eq(
  $$ select activo from public.distribuidores where nombre in ('Juanito Pérez', 'Lupita Gómez') $$,
  array[true, true],
  'Los dos siguen activos'
);


-- ─── Nuevo distribuidor ───────────────────────────────────────────────────────

select lives_ok(
  $$ select set_config('pruebas.chema', public.alta_distribuidor('  Chema Torres  ', ' 55 0000 0007 ', '   ')::text, true) $$,
  'Fragmentless da de alta a Chema'
);

select results_eq(
  $$ select nombre, telefono, correo, activo, usuario_id
     from public.distribuidores where id = current_setting('pruebas.chema')::bigint $$,
  $$ values ('Chema Torres', '55 0000 0007', null::text, true, null::uuid) $$,
  'Regresa su id; nace sin espacios de más, sin correo (estaba en blanco), activo y sin cuenta'
);

select results_eq(
  $$ select cuenta_ligada, clientes from public.panel_distribuidores() where nombre = 'Chema Torres' $$,
  $$ values (false, 0) $$,
  'En la lista sale sin cuenta y con 0 clientes'
);

select throws_ok(
  $$ select public.alta_distribuidor('   ', '55 0000 0008', null) $$,
  '22023', 'Falta el nombre',
  'Sin nombre no hay alta'
);

select throws_ok(
  $$ select public.alta_distribuidor(null, null, null) $$,
  '22023', 'Falta el nombre',
  'Con el nombre vacío tampoco'
);


-- ─── Corregir datos ───────────────────────────────────────────────────────────

select lives_ok(
  $$ select public.editar_distribuidor(tests.distribuidor('Chema Torres'), ' José María Torres ', '  ', ' chema@prueba.test ') $$,
  'Fragmentless corrige los datos de Chema'
);

select results_eq(
  $$ select nombre, telefono, correo
     from public.distribuidores where id = current_setting('pruebas.chema')::bigint $$,
  $$ values ('José María Torres', null::text, 'chema@prueba.test') $$,
  'Queda con su nombre nuevo, sin teléfono (estaba en blanco) y con su correo, sin espacios'
);

select lives_ok(
  $$ select public.editar_distribuidor(tests.distribuidor('Juanito Pérez'), 'Juanito Pérez', '55 0000 0001', 'juanito.nuevo@prueba.test') $$,
  'Fragmentless cambia el correo de contacto de Juanito'
);

select results_eq(
  $$ select correo, usuario_id from public.distribuidores where nombre = 'Juanito Pérez' $$,
  format($$ values ('juanito.nuevo@prueba.test', %L::uuid) $$, tests.get_supabase_uid('juanito')),
  'Cambiar su correo de contacto no cambia la cuenta con la que entra'
);

select throws_ok(
  $$ select public.editar_distribuidor(tests.distribuidor('Juanito Pérez'), '  ', null, null) $$,
  '22023', 'Falta el nombre',
  'No se le puede borrar el nombre'
);

select throws_ok(
  $$ select public.editar_distribuidor(999999, 'Nadie', null, null) $$,
  'P0002', 'No existe el distribuidor 999999',
  'Corregir a un distribuidor que no existe da error'
);


-- ─── Ligar cuenta ─────────────────────────────────────────────────────────────

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), '   ') $$,
  '22023', 'Falta el correo',
  'Sin correo no se liga'
);

select throws_ok(
  $$ select public.ligar_distribuidor(999999, 'memo@prueba.test') $$,
  'P0002', 'No existe el distribuidor 999999',
  'Ligar a un distribuidor que no existe da error'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Juanito Pérez'), 'memo@prueba.test') $$,
  '23505', 'Juanito Pérez ya tiene su cuenta ligada',
  'Quien ya tiene cuenta no se liga otra'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), 'nadie@prueba.test') $$,
  'P0002', 'No hay ninguna cuenta con el correo nadie@prueba.test; créala primero en Authentication → Add user',
  'Un correo sin cuenta da error'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), 'lupita@prueba.test') $$,
  '23505', 'La cuenta lupita@prueba.test ya está ligada a Lupita Gómez',
  'La cuenta de Lupita no se le liga a Memo'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), 'don.chuy@prueba.test') $$,
  '23505', 'Esa cuenta ya se usa en otro panel; crea otra para su panel de distribuidor',
  'Una cuenta, un panel: la de un gerente no se liga a un distribuidor'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), 'mesero.baja@prueba.test') $$,
  '23505', 'Esa cuenta ya se usa en otro panel; crea otra para su panel de distribuidor',
  'Ni la de un mesero dado de baja, que se puede reactivar'
);

select throws_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), 'fragmentless@prueba.test') $$,
  '23505', 'Esa cuenta ya se usa en otro panel; crea otra para su panel de distribuidor',
  'Ni la de Fragmentless'
);

select is(
  (select usuario_id from public.distribuidores where nombre = 'Memo Castillo'),
  null::uuid,
  'Después de esos errores, Memo sigue sin cuenta'
);

select lives_ok(
  $$ select public.ligar_distribuidor(tests.distribuidor('Memo Castillo'), '  Memo@Prueba.test ') $$,
  'Fragmentless liga la cuenta de Memo (sin importar mayúsculas ni espacios)'
);

select results_eq(
  $$ select usuario_id from public.distribuidores where nombre = 'Memo Castillo' $$,
  format('select %L::uuid', tests.get_supabase_uid('memo')),
  'Memo queda ligado a su cuenta'
);

select results_eq(
  $$ select cuenta_ligada from public.panel_distribuidores() where nombre = 'Memo Castillo' $$,
  array[true],
  'En la lista ya sale con cuenta ligada'
);

select tests.authenticate_as('memo');

select results_eq(
  'select nombre from public.distribuidores',
  array['Memo Castillo'],
  'Memo entra con su cuenta y lee su propia fila'
);

select tests.authenticate_as('fragmentless');


-- ─── Ligar gerente: una cuenta, un panel ──────────────────────────────────────

select throws_ok(
  $$ select public.ligar_gerente('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'juanito@prueba.test', 'Juanito Pérez') $$,
  '23505', 'Esa cuenta ya se usa en otro panel; crea otra para su restaurante',
  'La cuenta de Juanito no se liga como gerente de una taquería'
);

select throws_ok(
  $$ select public.ligar_gerente('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'paty@prueba.test', 'Paty Ruiz') $$,
  '23505', 'Esa cuenta ya se usa en otro panel; crea otra para su restaurante',
  'Ni la de Paty, de baja, que se puede reactivar'
);

select throws_ok(
  $$ select public.ligar_gerente('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'fragmentless@prueba.test', 'Fragmentless') $$,
  '23505', 'Esa cuenta ya se usa en otro panel; crea otra para su restaurante',
  'Ni la de Fragmentless'
);

select lives_ok(
  $$ select public.ligar_gerente('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'don.chuy@prueba.test', 'Don Chuy') $$,
  'Don Chuy, gerente de su fonda, sí se liga como gerente de otro restaurante'
);


-- ─── Asignar y quitar clientes ────────────────────────────────────────────────

select lives_ok(
  $$ select public.asignar_distribuidor('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.distribuidor('Juanito Pérez')) $$,
  'Fragmentless le asigna a Juanito Tacos El Güero, que era directo'
);

select lives_ok(
  $$ select public.asignar_distribuidor('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.distribuidor('Juanito Pérez')) $$,
  'Y la birria, que era de Lupita, en un solo paso'
);

select results_eq(
  $$ select distribuidor_nombre from public.panel_clientes()
     where slug in ('tacos-el-guero', 'birria-don-beto') order by slug $$,
  array['Juanito Pérez', 'Juanito Pérez'],
  'Las dos ya salen con Juanito en Clientes'
);

select results_eq(
  $$ select nombre, clientes from public.panel_distribuidores()
     where nombre in ('Juanito Pérez', 'Lupita Gómez') order by nombre $$,
  $$ values ('Juanito Pérez', 5), ('Lupita Gómez', 0) $$,
  'Juanito queda con 5 clientes y Lupita con 0'
);

select lives_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null) $$,
  'Fragmentless le quita a Juanito la fonda de Don Chuy'
);

select results_eq(
  $$ select distribuidor_id, distribuidor_nombre from public.panel_clientes() where slug = 'fonda-don-chuy' $$,
  $$ values (null::bigint, null::text) $$,
  'La fonda pasa a ser cliente directo'
);

select lives_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null) $$,
  'Quitarle el distribuidor a un cliente directo no da error'
);

select throws_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.distribuidor('Paty Ruiz')) $$,
  '55000', 'Paty Ruiz está de baja; primero usa Reactivar',
  'A quien está de baja no se le asigna nada'
);

select throws_ok(
  $$ select public.asignar_distribuidor('00000000-0000-4000-8000-000000000000', tests.distribuidor('Juanito Pérez')) $$,
  'P0002', 'No existe el restaurante 00000000-0000-4000-8000-000000000000',
  'Asignar un restaurante que no existe da error'
);

select throws_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 999999) $$,
  'P0002', 'No existe el distribuidor 999999',
  'Asignar a un distribuidor que no existe da error'
);

select results_eq(
  $$ select distribuidor_id from public.restaurantes where slug = 'fonda-don-chuy' $$,
  array[null::bigint],
  'Después de esos errores, la fonda sigue siendo directa'
);

select results_eq(
  $$ select licencia_activa, licencia_fin from public.restaurantes where slug = 'pollos-dona-mary' $$,
  $$ select false, (now() at time zone 'America/Mexico_City')::date + 30 $$,
  'Asignar y quitar no tocan la licencia: Pollos Doña Mary sigue pausado con su misma fecha'
);


-- ─── Dar de baja y reactivar ──────────────────────────────────────────────────

select lives_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Lupita Gómez'), false) $$,
  'Sin clientes, Lupita sí se da de baja'
);

select results_eq(
  $$ select activo, usuario_id from public.distribuidores where nombre = 'Lupita Gómez' $$,
  format($$ values (false, %L::uuid) $$, tests.get_supabase_uid('lupita')),
  'Queda de baja y conserva su cuenta'
);

select results_eq(
  $$ select nombre, activo from public.panel_distribuidores() order by activo, nombre $$,
  $$ values ('Lupita Gómez', false), ('Paty Ruiz', false),
            ('José María Torres', true), ('Juanito Pérez', true), ('Memo Castillo', true) $$,
  'En la lista sale de baja, junto con Paty'
);

select throws_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.distribuidor('Lupita Gómez')) $$,
  '55000', 'Lupita Gómez está de baja; primero usa Reactivar',
  'De baja, a Lupita ya no se le asignan clientes'
);

select lives_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Lupita Gómez'), true) $$,
  'Fragmentless reactiva a Lupita'
);

select lives_ok(
  $$ select public.asignar_distribuidor('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.distribuidor('Lupita Gómez')) $$,
  'Reactivada, se le vuelve a asignar un cliente'
);

select results_eq(
  $$ select activo, clientes from public.panel_distribuidores() where nombre = 'Lupita Gómez' $$,
  $$ values (true, 1) $$,
  'Lupita queda activa con 1 cliente'
);

select lives_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Memo Castillo'), true) $$,
  'Reactivar a quien ya está activo no da error'
);

select throws_ok(
  $$ select public.fijar_distribuidor_activo(999999, false) $$,
  'P0002', 'No existe el distribuidor 999999',
  'Dar de baja a un distribuidor que no existe da error'
);

select lives_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Paty Ruiz'), false) $$,
  'Dar de baja a quien ya está de baja no da error'
);

select tests.authenticate_as('paty');

select results_eq(
  'select nombre, activo from public.distribuidores',
  $$ values ('Paty Ruiz', false) $$,
  'De baja, Paty sigue leyendo su propia fila'
);


select * from finish();

rollback;
