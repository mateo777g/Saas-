-- Pruebas de perfiles (migración perfiles): que nadie escriba directo en la tabla, que
-- cada quien lea solo su fila y que guardar_perfil guarde el apodo y corrija el nombre
-- en todas las sucursales, solo para un gerente de un restaurante que funciona.
--
-- Escenario, con "hoy" en la hora de México. Don Chuy, como Jesús Hernández, es gerente
-- de La Fonda (funciona) y de Norte (venció ayer); en Fonda Vieja lo dieron de baja como
-- Jesús Viejo. Su hijo, Chuyito, es gerente en La Fonda y cajero en Norte. Toño es
-- mesero en La Fonda. Otro gerente tiene Fonda Vieja y ya guardó su apodo, Otro. El
-- gerente pausado solo tiene un restaurante pausado. Juanito es distribuidor.
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
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');
  perform tests.create_supabase_user('hijo', 'hijo@prueba.test');
  perform tests.create_supabase_user('tono', 'tono@prueba.test');
  perform tests.create_supabase_user('otro', 'otro@prueba.test');
  perform tests.create_supabase_user('pausado', 'pausado@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');

  insert into public.distribuidores (nombre, usuario_id)
  values ('Juanito', tests.get_supabase_uid('juanito'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Don Chuy Norte', 'don-chuy-norte', true, hoy - 31, hoy - 1),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Fonda Vieja', 'fonda-vieja', true, hoy - 30, hoy + 30),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Fonda Pausada', 'fonda-pausada', false, hoy - 30, hoy + 30);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('don_chuy'), 'Jesús Hernández', '{gerente}', true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('hijo'), 'Chuyito', '{gerente}', true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('tono'), 'Toño', '{mesero}', true),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('don_chuy'), 'Jesús Hernández', '{gerente}', true),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('hijo'), 'Chuyito', '{caja}', true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('otro'), 'Otro Gerente', '{gerente}', true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('don_chuy'), 'Jesús Viejo', '{gerente}', false),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.get_supabase_uid('pausado'), 'Gerente Pausado', '{gerente}', true);

  insert into public.perfiles (usuario_id, apodo)
  values (tests.get_supabase_uid('otro'), 'Otro');
end;
$$;

select plan(23);


-- ─── Permisos ─────────────────────────────────────────────────────────────────

select ok(
  not (has_table_privilege('anon', 'public.perfiles', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       or has_any_column_privilege('anon', 'public.perfiles', 'SELECT, INSERT, UPDATE, REFERENCES')),
  'anon no tiene ningún permiso sobre perfiles'
);

select ok(
  not (has_table_privilege('authenticated', 'public.perfiles', 'INSERT, UPDATE, DELETE, TRUNCATE')
       or has_any_column_privilege('authenticated', 'public.perfiles', 'INSERT, UPDATE')),
  'Nadie con sesión escribe directo en perfiles'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.perfiles'::regclass),
  'perfiles tiene RLS'
);

select ok(
  has_function_privilege('authenticated', 'public.guardar_perfil(text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.guardar_perfil(text, text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.guardar_perfil(text, text)', 'EXECUTE'),
  'Solo con sesión se puede llamar guardar_perfil'
);

select tests.clear_authentication();

select throws_ok($$ select public.guardar_perfil('Alguien', 'Algo') $$, '42501', null,
  'Sin sesión no se llama guardar_perfil');


-- ─── Don Chuy guarda su perfil ────────────────────────────────────────────────

select tests.authenticate_as('don_chuy');

select is_empty('select apodo from public.perfiles',
  'Antes de guardar, Don Chuy no tiene perfil y no ve el de Otro');

select lives_ok(
  $$ select public.guardar_perfil('  Jesús Hernández Ruiz ', '  Don Chuy  ') $$,
  'Don Chuy guarda su nombre y su apodo'
);

select results_eq(
  'select usuario_id, apodo from public.perfiles',
  $$ values (tests.get_supabase_uid('don_chuy'), 'Don Chuy') $$,
  'Ve solo su perfil, con el apodo sin espacios sobrantes'
);

select throws_ok(
  $$ insert into public.perfiles (usuario_id, apodo) values (tests.get_supabase_uid('don_chuy'), 'Otro apodo') $$,
  '42501', null,
  'No puede escribir directo en perfiles'
);

select throws_ok(
  $$ select public.guardar_perfil('Jesús Hernández Ruiz', 'Chuy de la Fonda 1234') $$,
  '22023', 'Cómo te llamamos: máximo 20 letras',
  'Un apodo de 21 letras no entra'
);

select lives_ok(
  $$ select public.guardar_perfil('Jesús Hernández Ruiz', 'Chuy de la Fonda 123') $$,
  'Uno de 20 sí'
);

select throws_ok(
  $$ select public.guardar_perfil('   ', 'Don Chuy') $$,
  '22023', 'Escribe tu nombre completo',
  'El nombre no puede quedar en blanco'
);

select throws_ok(
  $$ select public.guardar_perfil(null, 'Don Chuy') $$,
  '22023', 'Escribe tu nombre completo',
  'Ni vacío'
);

select lives_ok(
  $$ select public.guardar_perfil('Jesús Hernández Ruiz', '') $$,
  'Don Chuy borra su apodo'
);

select results_eq(
  'select apodo from public.perfiles',
  array[null::text],
  'Sin apodo, lo llaman por su nombre'
);

reset role;

select results_eq(
  $$ select r.slug, m.nombre from public.miembros m join public.restaurantes r on r.id = m.restaurante_id
     where m.usuario_id = tests.get_supabase_uid('don_chuy') order by r.slug $$,
  $$ values ('don-chuy-norte', 'Jesús Hernández Ruiz'), ('fonda-don-chuy', 'Jesús Hernández Ruiz'),
            ('fonda-vieja', 'Jesús Viejo') $$,
  'Su nombre se corrigió en La Fonda y en Norte, aunque Norte ya venció; en Fonda Vieja, donde lo dieron de baja, no'
);


-- ─── El hijo, gerente en La Fonda y cajero en Norte ───────────────────────────

select tests.authenticate_as('hijo');

select lives_ok(
  $$ select public.guardar_perfil('Jesús Hernández Jr.', '   ') $$,
  'El hijo corrige su nombre desde La Fonda, sin apodo'
);

reset role;

select results_eq(
  $$ select r.slug, m.nombre, p.apodo
     from public.miembros m
     join public.restaurantes r on r.id = m.restaurante_id
     left join public.perfiles p on p.usuario_id = m.usuario_id
     where m.usuario_id = tests.get_supabase_uid('hijo') order by r.slug $$,
  $$ values ('don-chuy-norte', 'Jesús Hernández Jr.', null::text), ('fonda-don-chuy', 'Jesús Hernández Jr.', null::text) $$,
  'Su nombre cambia también en Norte, donde es cajero, y se queda sin apodo'
);


-- ─── Quién no puede ───────────────────────────────────────────────────────────

select tests.authenticate_as('tono');

select throws_ok(
  $$ select public.guardar_perfil('Antonio', 'Toño') $$,
  '42501', 'Solo el gerente de un restaurante que funciona puede cambiar su perfil',
  'Toño, mesero, no se cambia el nombre solo'
);

select is_empty('select apodo from public.perfiles', 'Toño no ve el perfil de nadie más');

select tests.authenticate_as('pausado');

select throws_ok(
  $$ select public.guardar_perfil('Gerente Pausado', 'Pau') $$,
  '42501', 'Solo el gerente de un restaurante que funciona puede cambiar su perfil',
  'Con su único restaurante pausado, no puede'
);

select tests.authenticate_as('juanito');

select throws_ok(
  $$ select public.guardar_perfil('Juanito', 'Juan') $$,
  '42501', 'Solo el gerente de un restaurante que funciona puede cambiar su perfil',
  'Juanito, distribuidor, no tiene perfil de gerente'
);

select tests.authenticate_as('otro');

select results_eq(
  'select apodo from public.perfiles',
  array['Otro'],
  'Otro gerente ve solo su apodo, no los de Don Chuy ni su hijo'
);


select * from finish();

rollback;
