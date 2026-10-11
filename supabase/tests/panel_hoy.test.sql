-- Pruebas de panel_hoy (migración panel_hoy): quién puede llamarla y que dé el día de
-- hoy en la hora de México, la zona con la que nace todo restaurante, aunque la sesión
-- esté en otra zona.
--
-- Escenario: Fragmentless, Juanito (distribuidor) y el gerente de La Fonda.
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
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, usuario_id)
  values ('Juanito', tests.get_supabase_uid('juanito'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}');
end;
$$;

select plan(7);


-- ─── Quién puede llamarla ─────────────────────────────────────────────────────

select ok(
  has_function_privilege('authenticated', 'public.panel_hoy()', 'EXECUTE'),
  'Con sesión se puede llamar panel_hoy'
);

select ok(
  not has_function_privilege('service_role', 'public.panel_hoy()', 'EXECUTE'),
  'service_role no la llama: no tiene la sesión de nadie'
);

select tests.clear_authentication();

select throws_ok('select public.panel_hoy()', '42501', null, 'Sin sesión no se llama panel_hoy');

select tests.authenticate_as('don_chuy');

select throws_ok('select public.panel_hoy()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no puede llamar panel_hoy');

select tests.authenticate_as('juanito');

select throws_ok('select public.panel_hoy()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un distribuidor no puede llamar panel_hoy');


-- ─── Qué día da ───────────────────────────────────────────────────────────────

select tests.authenticate_as('fragmentless');

select is(
  public.panel_hoy(),
  (now() at time zone 'America/Mexico_City')::date,
  'Fragmentless recibe el día de hoy en la Ciudad de México'
);

-- Kiritimati va 20 horas adelante de México: casi siempre ya es mañana allá.
set local timezone = 'Pacific/Kiritimati';

select is(
  public.panel_hoy(),
  (now() at time zone 'America/Mexico_City')::date,
  'Aunque la sesión esté en Kiritimati, el día sigue siendo el de México'
);


select * from finish();

rollback;
