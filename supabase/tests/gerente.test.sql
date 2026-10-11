-- Pruebas de la lectura del gerente (migración gerente_lectura): quién puede llamar
-- mis_sucursales, qué restaurantes le da a cada quien y que cuente bien si funcionan
-- y qué día y qué hora es en la zona de cada uno.
--
-- Escenario, con "hoy" en la hora de México. Don Chuy es gerente de La Fonda (vigente),
-- Norte (venció ayer), Centro (vence hoy), Sur (pausada y vencida), Bodega (pausada sin
-- fecha de fin) y Playa (en Pacific/Kiritimati, UTC+14, vence hoy en su zona); en Norte
-- su nombre es Jesús Hernández. En Fonda Vieja lo dieron de baja. Su hijo es gerente
-- en La Fonda y cajero en Norte; Toño es mesero en La Fonda. Otro gerente tiene Fonda
-- Otra y Fonda Vieja. Juanito es distribuidor y Fragmentless no es gerente de nada.
--
-- Los nombres salen en el mismo orden en Supabase, que ordena como una persona, y en
-- PGlite, que ordena por bytes ("Fonda Vieja" iría antes que "Fonda de Otro").
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
  hoy_k date := privado.dia_local('Pacific/Kiritimati');
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');
  perform tests.create_supabase_user('hijo', 'hijo@prueba.test');
  perform tests.create_supabase_user('tono', 'tono@prueba.test');
  perform tests.create_supabase_user('otro', 'otro@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, usuario_id)
  values ('Juanito', tests.get_supabase_uid('juanito'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Don Chuy Norte', 'don-chuy-norte', true, hoy - 31, hoy - 1),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Don Chuy Centro', 'don-chuy-centro', true, hoy - 30, hoy),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Don Chuy Sur', 'don-chuy-sur', false, hoy - 35, hoy - 5),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Don Chuy Bodega', 'don-chuy-bodega', false, null, null),
    ('11111111-1111-4111-8111-111111111111', 'Fonda Otra', 'fonda-otra', true, hoy - 30, hoy + 30),
    ('22222222-2222-4222-8222-222222222222', 'Fonda Vieja', 'fonda-vieja', true, hoy - 30, hoy + 30);

  insert into public.restaurantes (id, nombre, slug, zona_horaria, licencia_activa, licencia_inicio, licencia_fin) values
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'Don Chuy Playa', 'don-chuy-playa', 'Pacific/Kiritimati', true, hoy_k - 30, hoy_k);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}', true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('hijo'), 'Chuyito', '{gerente}', true),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('tono'), 'Toño', '{mesero}', true),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('don_chuy'), 'Jesús Hernández', '{gerente}', true),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('hijo'), 'Chuyito', '{caja}', true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}', true),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}', true),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}', true),
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}', true),
    ('11111111-1111-4111-8111-111111111111', tests.get_supabase_uid('otro'), 'Otro Gerente', '{gerente}', true),
    ('22222222-2222-4222-8222-222222222222', tests.get_supabase_uid('otro'), 'Otro Gerente', '{gerente}', true),
    ('22222222-2222-4222-8222-222222222222', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}', false);
end;
$$;

select plan(17);


-- ─── Quién puede llamarla ─────────────────────────────────────────────────────

select ok(
  has_function_privilege('authenticated', 'public.mis_sucursales()', 'EXECUTE'),
  'Con sesión se puede llamar mis_sucursales'
);

select ok(
  not has_function_privilege('service_role', 'public.mis_sucursales()', 'EXECUTE'),
  'service_role no la llama: no tiene la sesión de nadie'
);

select tests.clear_authentication();

select throws_ok('select public.mis_sucursales()', '42501', null, 'Sin sesión no se llama mis_sucursales');


-- ─── Lo que ve Don Chuy ───────────────────────────────────────────────────────

select tests.authenticate_as('don_chuy');

select results_eq(
  'select slug from public.mis_sucursales()',
  array['don-chuy-bodega', 'don-chuy-centro', 'don-chuy-norte', 'don-chuy-playa', 'don-chuy-sur',
        'fonda-don-chuy'],
  'Don Chuy ve sus 6 restaurantes, funcionen o no, por nombre; ni Fonda Otra ni Fonda Vieja, donde lo dieron de baja'
);

select results_eq(
  $$ select slug, estado, licencia_fin from public.mis_sucursales() where slug <> 'don-chuy-playa' $$,
  $$ with h as (select (now() at time zone 'America/Mexico_City')::date as hoy)
     select v.slug, v.estado, v.fin
     from h cross join lateral (values
       (1, 'don-chuy-bodega', 'pausada', null::date),
       (2, 'don-chuy-centro', 'funciona', h.hoy),
       (3, 'don-chuy-norte', 'vencida', h.hoy - 1),
       (4, 'don-chuy-sur', 'pausada', h.hoy - 5),
       (5, 'fonda-don-chuy', 'funciona', h.hoy + 30)
     ) as v(orden, slug, estado, fin)
     order by v.orden $$,
  'Centro vence hoy y funciona, Norte venció ayer, Sur pausada aunque también venció, Bodega pausada sin fecha, La Fonda funciona'
);

select results_eq(
  $$ select estado, licencia_fin from public.mis_sucursales() where slug = 'don-chuy-playa' $$,
  $$ values ('funciona', (now() at time zone 'Pacific/Kiritimati')::date) $$,
  'Playa vence hoy en su zona (Kiritimati) y funciona'
);

select results_eq(
  $$ select hoy, hora from public.mis_sucursales() where slug = 'fonda-don-chuy' $$,
  $$ values ((now() at time zone 'America/Mexico_City')::date,
             extract(hour from now() at time zone 'America/Mexico_City')::integer) $$,
  'La Fonda trae la fecha y la hora de ahora en la Ciudad de México'
);

select results_eq(
  $$ select hoy, hora from public.mis_sucursales() where slug = 'don-chuy-playa' $$,
  $$ values ((now() at time zone 'Pacific/Kiritimati')::date,
             extract(hour from now() at time zone 'Pacific/Kiritimati')::integer) $$,
  'Playa trae la fecha y la hora de su zona, no las de México'
);

select results_eq(
  $$ select slug, mi_nombre from public.mis_sucursales() where slug in ('don-chuy-norte', 'fonda-don-chuy') $$,
  $$ values ('don-chuy-norte', 'Jesús Hernández'), ('fonda-don-chuy', 'Don Chuy') $$,
  'Su nombre sale de miembros de cada restaurante'
);


-- ─── Lo que ven los demás ─────────────────────────────────────────────────────

select tests.authenticate_as('hijo');

select results_eq(
  'select slug from public.mis_sucursales()',
  array['fonda-don-chuy'],
  'El hijo ve La Fonda, donde es gerente, y no Norte, donde es cajero'
);

select tests.authenticate_as('tono');

select is_empty('select * from public.mis_sucursales()', 'Toño, que solo es mesero, no recibe ningún restaurante');

select tests.authenticate_as('juanito');

select is_empty('select * from public.mis_sucursales()', 'Juanito, distribuidor, no recibe ningún restaurante');

select tests.authenticate_as('fragmentless');

select is_empty('select * from public.mis_sucursales()', 'Fragmentless no es gerente de ningún restaurante');

select tests.authenticate_as('otro');

select results_eq(
  'select slug from public.mis_sucursales()',
  array['fonda-otra', 'fonda-vieja'],
  'Otro gerente ve solo los suyos'
);


-- ─── Después de un cambio, la lectura ya lo trae ──────────────────────────────

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.extender_licencia('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1) $$,
  'Norte paga un mes'
);

select lives_ok(
  $$ select public.fijar_licencia(id, false, licencia_inicio, licencia_fin)
     from public.restaurantes where slug = 'fonda-don-chuy' $$,
  'Fragmentless pausa La Fonda'
);

select tests.authenticate_as('don_chuy');

select results_eq(
  $$ select slug, estado, licencia_fin from public.mis_sucursales() where slug in ('don-chuy-norte', 'fonda-don-chuy') $$,
  $$ with h as (select (now() at time zone 'America/Mexico_City')::date as hoy)
     select v.slug, v.estado, v.fin
     from h cross join lateral (values
       (1, 'don-chuy-norte', 'funciona', (h.hoy + interval '1 month')::date),
       (2, 'fonda-don-chuy', 'pausada', h.hoy + 30)
     ) as v(orden, slug, estado, fin)
     order by v.orden $$,
  'Don Chuy ve Norte funcionando un mes desde hoy y La Fonda pausada'
);


select * from finish();

rollback;
