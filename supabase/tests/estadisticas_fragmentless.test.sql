-- Pruebas de la migración estadisticas_fragmentless (rediseño del panel, 5 de noviembre de 2026): la foto de
-- cada día de las licencias y panel_estadisticas, lo que dibuja el Inicio de Fragmentless.
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


-- ─── La primera foto ──────────────────────────────────────────────────────────
-- Sin restaurantes todavía: la migración ya tomó la foto de hoy, en ceros.

select plan(45);

select results_eq(
  $$select dia, funcionan, sin_funcionar from public.fotos_licencias$$,
  $$values (privado.dia_local('America/Mexico_City'), 0, 0)$$,
  'La migración toma la primera foto, la de hoy');

select results_eq(
  $$select schedule, command from cron.job where jobname = 'foto-de-licencias'$$,
  $$values ('55 5 * * *'::text, 'select privado.tomar_foto_licencias()'::text)$$,
  'La foto se toma a las 23:55 de México');

select ok((select relrowsecurity from pg_class where oid = 'public.fotos_licencias'::regclass), 'fotos_licencias tiene RLS');
select ok(not has_table_privilege('authenticated', 'public.fotos_licencias', 'select'), 'Con sesión no se lee');
select ok(not has_table_privilege('authenticated', 'public.fotos_licencias', 'insert'), 'Con sesión no se escribe');
select ok(not has_table_privilege('anon', 'public.fotos_licencias', 'select'), 'Sin sesión no se lee');
select ok(not has_table_privilege('service_role', 'public.fotos_licencias', 'select'), 'El Worker no la lee');
select ok(not has_table_privilege('service_role', 'public.fotos_licencias', 'insert'), 'El Worker no la escribe');
select ok(not has_function_privilege('authenticated', 'privado.tomar_foto_licencias()', 'execute'), 'Con sesión no se toma la foto');
select ok(not has_function_privilege('service_role', 'privado.tomar_foto_licencias()', 'execute'), 'El Worker no toma la foto');
select ok(not has_function_privilege('anon', 'public.panel_estadisticas()', 'execute'), 'Sin sesión no se llama panel_estadisticas');
select ok(not has_function_privilege('service_role', 'public.panel_estadisticas()', 'execute'), 'El Worker no llama panel_estadisticas');
select ok(has_function_privilege('authenticated', 'public.panel_estadisticas()', 'execute'), 'Con sesión sí se puede llamar: la función revisa quién');

select throws_ok(
  $$insert into public.fotos_licencias values ('2020-01-01', -1, 0)$$, '23514', null, 'funcionan no es negativo');
select throws_ok(
  $$insert into public.fotos_licencias values ('2020-01-01', 0, -1)$$, '23514', null, 'sin_funcionar no es negativo');


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Funcionan: A, B, C, D, E y K. Sin funcionar: F, G y H.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  hoy_k date := privado.dia_local('Pacific/Kiritimati');
  mes date := date_trunc('month', privado.dia_local('America/Mexico_City')::timestamp)::date;
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');

  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));
  insert into public.distribuidores (nombre, usuario_id, activo) values ('Juanito', tests.get_supabase_uid('juanito'), true);

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A vigente', 'a-vigente', true, hoy - 30, hoy + 30),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B vence hoy', 'b-vence-hoy', true, hoy - 30, hoy),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'C vence en 3', 'c-vence-en-3', true, hoy - 30, hoy + 3),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'D vence en 7', 'd-vence-en-7', true, hoy - 30, hoy + 7),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'E vence en 8', 'e-vence-en-8', true, hoy - 30, hoy + 8),
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'F venció ayer', 'f-vencio-ayer', true, hoy - 31, hoy - 1),
    ('11111111-1111-4111-8111-111111111111', 'G pausado', 'g-pausado', false, hoy - 30, hoy + 30),
    ('22222222-2222-4222-8222-222222222222', 'H pausado y vence hoy', 'h-pausado-vence-hoy', false, hoy - 30, hoy);

  insert into public.restaurantes (id, nombre, slug, zona_horaria, licencia_activa, licencia_inicio, licencia_fin) values
    ('33333333-3333-4333-8333-333333333333', 'K en Kiritimati', 'k-kiritimati', 'Pacific/Kiritimati', true, hoy_k - 30, hoy_k);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}');

  insert into public.uso_ia (restaurante_id, mes, costo_agente_usd, costo_anuncios_usd, costo_menu_usd) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', mes, 1.5, 2, 0.25),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', mes, 1.25, 0, 0),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (mes - interval '1 month')::date, 0.5, 0, 0),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (mes - interval '5 months')::date, 2, 0, 0),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (mes - interval '6 months')::date, 9, 0, 0);
end;
$$;


-- ─── Tomar la foto ────────────────────────────────────────────────────────────

select privado.tomar_foto_licencias();

select results_eq(
  $$select dia, funcionan, sin_funcionar from public.fotos_licencias$$,
  $$values (privado.dia_local('America/Mexico_City'), 6, 3)$$,
  'Otra foto el mismo día reemplaza la anterior, sin otro renglón');


-- ─── Quién puede leer ─────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select throws_ok('select public.panel_estadisticas()', '42501', 'Solo Fragmentless puede hacer esto', 'Un gerente no lee las estadísticas');
select throws_ok('select dia from public.fotos_licencias', '42501', null, 'Un gerente no lee las fotos');

select tests.authenticate_as('juanito');
select throws_ok('select public.panel_estadisticas()', '42501', 'Solo Fragmentless puede hacer esto', 'Un distribuidor no lee las estadísticas');

select tests.authenticate_as('fragmentless');
select throws_ok('select dia from public.fotos_licencias', '42501', null, 'Fragmentless tampoco lee la tabla directo: solo con la función');


-- ─── Sin historia: solo el renglón de hoy ─────────────────────────────────────

select is(jsonb_array_length(public.panel_estadisticas() -> 'fotos'), 1, 'Sin fotos viejas, solo sale hoy');
select is((public.panel_estadisticas() ->> 'hoy')::date, public.panel_hoy(), 'hoy es el día de México');
select tests.authenticate_as('fragmentless');
select is(public.panel_estadisticas() ->> 'hora', to_char(now() at time zone 'America/Mexico_City', 'HH24:MI'), 'hora es la hora de México');


-- ─── El gasto ─────────────────────────────────────────────────────────────────

select is(jsonb_array_length(public.panel_estadisticas() -> 'gasto'), 6, 'El gasto son 6 meses');
select is((public.panel_estadisticas() -> 'gasto' -> 0 ->> 'mes')::date,
  (date_trunc('month', public.panel_hoy()::timestamp) - interval '5 months')::date,
  'Empieza hace 5 meses');
select is((public.panel_estadisticas() -> 'gasto' -> 5 ->> 'mes')::date,
  date_trunc('month', public.panel_hoy()::timestamp)::date, 'Termina en este mes');
select is((public.panel_estadisticas() -> 'gasto' -> 5 ->> 'gastado')::numeric, 5.00, 'Este mes suma agente, anuncios y menú de todos');
select is((public.panel_estadisticas() -> 'gasto' -> 4 ->> 'gastado')::numeric, 0.50, 'El mes pasado');
select is((public.panel_estadisticas() -> 'gasto' -> 3 ->> 'gastado')::numeric, 0.00, 'Un mes sin gasto sale en 0');
select is((public.panel_estadisticas() -> 'gasto' -> 0 ->> 'gastado')::numeric, 2.00, 'El mes más viejo cuenta; el de antes, no');


-- ─── Lo que vence ─────────────────────────────────────────────────────────────

select is(jsonb_array_length(public.panel_estadisticas() -> 'vencen'), 8, 'De hoy a dentro de 7 días son 8 renglones');
select is((public.panel_estadisticas() -> 'vencen' -> 0 ->> 'dia')::date, public.panel_hoy(), 'Empieza hoy');
select is((public.panel_estadisticas() -> 'vencen' -> 7 ->> 'dia')::date, public.panel_hoy() + 7, 'Termina en 7 días');
select is((public.panel_estadisticas() -> 'vencen' -> 0 ->> 'cuantos')::integer, 2, 'Hoy: B y K, cada una en su zona; el pausado no');
select is((public.panel_estadisticas() -> 'vencen' -> 1 ->> 'cuantos')::integer, 0, 'Un día sin nada sale en 0');
select is((public.panel_estadisticas() -> 'vencen' -> 3 ->> 'cuantos')::integer, 1, 'En 3 días, C');
select is((public.panel_estadisticas() -> 'vencen' -> 7 ->> 'cuantos')::integer, 1, 'En 7 días, D');
select is(
  (select sum((e ->> 'cuantos')::integer)::integer from jsonb_array_elements(public.panel_estadisticas() -> 'vencen') e),
  (select r.vencen_pronto from public.panel_resumen() r),
  'Sumado da lo mismo que la tarjeta: E, en 8 días, no entra');


-- ─── Las fotos ────────────────────────────────────────────────────────────────
-- Hoy guarda una foto vieja a propósito: tiene que ganar lo que está en vivo.

reset role;
do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
begin
  update public.fotos_licencias set funcionan = 99, sin_funcionar = 99 where dia = hoy;
  insert into public.fotos_licencias (dia, funcionan, sin_funcionar) values
    (hoy - 30, 11, 11),
    (hoy - 29, 2, 1),
    (hoy - 1, 5, 2);
end;
$$;
select tests.authenticate_as('fragmentless');

select is(jsonb_array_length(public.panel_estadisticas() -> 'fotos'), 3, 'Salen los días con foto de los últimos 30, sin el 31');
select is((public.panel_estadisticas() -> 'fotos' -> 0 ->> 'dia')::date, public.panel_hoy() - 29, 'De lo más viejo a hoy');
select is((public.panel_estadisticas() -> 'fotos' -> 0 ->> 'funcionan')::integer, 2, 'La foto vieja dice cuántos funcionaban');
select is((public.panel_estadisticas() -> 'fotos' -> 1 ->> 'sin_funcionar')::integer, 2, 'Y cuántos no');
select is((public.panel_estadisticas() -> 'fotos' -> 2 ->> 'dia')::date, public.panel_hoy(), 'El último renglón es hoy');
select is((public.panel_estadisticas() -> 'fotos' -> 2 ->> 'funcionan')::integer, (select r.funcionan from public.panel_resumen() r), 'Hoy sale en vivo, igual que la tarjeta');
select is((public.panel_estadisticas() -> 'fotos' -> 2 ->> 'sin_funcionar')::integer, (select r.sin_funcionar from public.panel_resumen() r), 'Y sin funcionar también');

select * from finish();
rollback;
