-- Pruebas de la migración estadisticas_distribuidor (8 de noviembre de 2026): la foto de cada día de los
-- clientes de cada distribuidor y distribuidor_estadisticas, lo que dibuja el Inicio del distribuidor.
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


-- ─── La tabla y quién la toca ─────────────────────────────────────────────────

select plan(64);

select is((select count(*)::integer from public.fotos_distribuidores), 0,
  'Sin distribuidores todavía, la primera foto no deja renglones');

select results_eq(
  $$select schedule, command from cron.job where jobname = 'foto-de-licencias'$$,
  $$values ('55 5 * * *'::text, 'select privado.tomar_foto_licencias()'::text)$$,
  'La foto se sigue tomando a las 23:55 de México, con la misma llamada');

select ok((select relrowsecurity from pg_class where oid = 'public.fotos_distribuidores'::regclass), 'fotos_distribuidores tiene RLS');
select ok(not has_table_privilege('authenticated', 'public.fotos_distribuidores', 'select'), 'Con sesión no se lee');
select ok(not has_table_privilege('authenticated', 'public.fotos_distribuidores', 'insert'), 'Con sesión no se escribe');
select ok(not has_table_privilege('anon', 'public.fotos_distribuidores', 'select'), 'Sin sesión no se lee');
select ok(not has_table_privilege('service_role', 'public.fotos_distribuidores', 'select'), 'El Worker no la lee');
select ok(not has_table_privilege('service_role', 'public.fotos_distribuidores', 'insert'), 'El Worker no la escribe');
select ok(not has_function_privilege('authenticated', 'privado.tomar_foto_licencias()', 'execute'), 'Con sesión no se toma la foto');
select ok(not has_function_privilege('service_role', 'privado.tomar_foto_licencias()', 'execute'), 'El Worker no toma la foto');
select ok(not has_function_privilege('anon', 'public.distribuidor_estadisticas()', 'execute'), 'Sin sesión no se llama distribuidor_estadisticas');
select ok(not has_function_privilege('service_role', 'public.distribuidor_estadisticas()', 'execute'), 'El Worker no la llama');
select ok(has_function_privilege('authenticated', 'public.distribuidor_estadisticas()', 'execute'), 'Con sesión sí se puede llamar: la función revisa quién');


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Juanito: A vigente, B vence hoy, C vence en 3, F venció ayer, G pausado, H pausado y vence hoy.
-- Rosa: D vence en 7, E vence en 8. Pepa (de baja): P vigente. Lalo: sin clientes.
-- Sin distribuidor: K vigente y M vence hoy.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  mes date := date_trunc('month', privado.dia_local('America/Mexico_City')::timestamp)::date;
  juanito bigint;
  rosa bigint;
  pepa bigint;
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('rosa', 'rosa@prueba.test');
  perform tests.create_supabase_user('pepa', 'pepa@prueba.test');
  perform tests.create_supabase_user('lalo', 'lalo@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');

  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));
  insert into public.distribuidores (nombre, usuario_id, activo) values ('Juanito', tests.get_supabase_uid('juanito'), true)
    returning id into juanito;
  insert into public.distribuidores (nombre, usuario_id, activo) values ('Rosa', tests.get_supabase_uid('rosa'), true)
    returning id into rosa;
  insert into public.distribuidores (nombre, usuario_id, activo) values ('Pepa', tests.get_supabase_uid('pepa'), false)
    returning id into pepa;
  insert into public.distribuidores (nombre, usuario_id, activo) values ('Lalo', tests.get_supabase_uid('lalo'), true);

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A vigente', 'a-vigente', true, hoy - 30, hoy + 30, juanito),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B vence hoy', 'b-vence-hoy', true, hoy - 30, hoy, juanito),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'C vence en 3', 'c-vence-en-3', true, hoy - 30, hoy + 3, juanito),
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'F venció ayer', 'f-vencio-ayer', true, hoy - 31, hoy - 1, juanito),
    ('11111111-1111-4111-8111-111111111111', 'G pausado', 'g-pausado', false, hoy - 30, hoy + 30, juanito),
    ('22222222-2222-4222-8222-222222222222', 'H pausado y vence hoy', 'h-pausado-vence-hoy', false, hoy - 30, hoy, juanito),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'D vence en 7', 'd-vence-en-7', true, hoy - 30, hoy + 7, rosa),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'E vence en 8', 'e-vence-en-8', true, hoy - 30, hoy + 8, rosa),
    ('44444444-4444-4444-8444-444444444444', 'P de Pepa', 'p-de-pepa', true, hoy - 30, hoy + 30, pepa),
    ('33333333-3333-4333-8333-333333333333', 'K sin distribuidor', 'k-sin-distribuidor', true, hoy - 30, hoy + 30, null),
    ('55555555-5555-4555-8555-555555555555', 'M sin distribuidor vence hoy', 'm-sin-distribuidor', true, hoy - 30, hoy, null);

  -- Las altas: A, B, H y D, este mes; C hace 2 meses, F hace 5 y G hace 6 (ya no entra).
  update public.restaurantes
     set created_at = ((mes - interval '2 months' + interval '10 days')::timestamp) at time zone 'America/Mexico_City'
   where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  update public.restaurantes
     set created_at = ((mes - interval '5 months' + interval '10 days')::timestamp) at time zone 'America/Mexico_City'
   where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  update public.restaurantes
     set created_at = ((mes - interval '6 months' + interval '10 days')::timestamp) at time zone 'America/Mexico_City'
   where id = '11111111-1111-4111-8111-111111111111';

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}');

  insert into public.uso_ia (restaurante_id, mes, costo_agente_usd, costo_anuncios_usd, costo_menu_usd) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', mes, 1.5, 2, 0.25),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', mes, 1.25, 0, 0),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', mes, 4, 0, 0),
    ('33333333-3333-4333-8333-333333333333', mes, 7, 0, 0),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (mes - interval '1 month')::date, 0.5, 0, 0),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (mes - interval '5 months')::date, 2, 0, 0),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', (mes - interval '6 months')::date, 9, 0, 0);
end;
$$;

select throws_ok(
  $$insert into public.fotos_distribuidores values ((select id from public.distribuidores where nombre = 'Lalo'), '2020-01-01', -1, 0)$$,
  '23514', null, 'funcionan no es negativo');
select throws_ok(
  $$insert into public.fotos_distribuidores values ((select id from public.distribuidores where nombre = 'Lalo'), '2020-01-01', 0, -1)$$,
  '23514', null, 'sin_funcionar no es negativo');
select throws_ok(
  $$insert into public.fotos_distribuidores values (999999, '2020-01-01', 0, 0)$$,
  '23503', null, 'Solo de un distribuidor que existe');


-- ─── Tomar la foto ────────────────────────────────────────────────────────────

select privado.tomar_foto_licencias();
update public.fotos_distribuidores set funcionan = 77, sin_funcionar = 77;
select privado.tomar_foto_licencias();

select results_eq(
  $$select d.nombre, f.dia, f.funcionan, f.sin_funcionar
    from public.fotos_distribuidores f join public.distribuidores d on d.id = f.distribuidor_id
    order by d.nombre$$,
  $$values ('Juanito'::text, privado.dia_local('America/Mexico_City'), 3, 3),
           ('Lalo'::text, privado.dia_local('America/Mexico_City'), 0, 0),
           ('Pepa'::text, privado.dia_local('America/Mexico_City'), 1, 0),
           ('Rosa'::text, privado.dia_local('America/Mexico_City'), 2, 0)$$,
  'Una fila por distribuidor, también sin clientes y de baja; tomarla otra vez la reemplaza');

select results_eq(
  $$select dia, funcionan, sin_funcionar from public.fotos_licencias$$,
  $$values (privado.dia_local('America/Mexico_City'), 8, 3)$$,
  'La foto de todos sigue igual: un renglón por día, con todos los restaurantes');


-- ─── Quién puede leer ─────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select throws_ok('select public.distribuidor_estadisticas()', '42501', 'Solo un distribuidor activo puede ver esto', 'Un gerente no la lee');

select tests.authenticate_as('fragmentless');
select throws_ok('select public.distribuidor_estadisticas()', '42501', 'Solo un distribuidor activo puede ver esto', 'Fragmentless tampoco: la suya es panel_estadisticas');

select tests.authenticate_as('pepa');
select throws_ok('select public.distribuidor_estadisticas()', '42501', 'Solo un distribuidor activo puede ver esto', 'Un distribuidor de baja no la lee');

select tests.authenticate_as('juanito');
select throws_ok('select dia from public.fotos_distribuidores', '42501', null, 'Ni el distribuidor lee la tabla directo: solo con la función');


-- ─── Hoy, la hora y sin historia ──────────────────────────────────────────────

select is((public.distribuidor_estadisticas() ->> 'hoy')::date, (now() at time zone 'America/Mexico_City')::date, 'hoy es el día de México');
select is(public.distribuidor_estadisticas() ->> 'hora', to_char(now() at time zone 'America/Mexico_City', 'HH24:MI'), 'hora es la hora de México');
select is(jsonb_array_length(public.distribuidor_estadisticas() -> 'fotos'), 1, 'Sin fotos viejas, solo sale hoy');


-- ─── El gasto ─────────────────────────────────────────────────────────────────

select is(jsonb_array_length(public.distribuidor_estadisticas() -> 'gasto'), 6, 'El gasto son 6 meses');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 0 ->> 'mes')::date,
  (date_trunc('month', now() at time zone 'America/Mexico_City') - interval '5 months')::date, 'Empieza hace 5 meses');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 5 ->> 'mes')::date,
  date_trunc('month', now() at time zone 'America/Mexico_City')::date, 'Termina en este mes');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 5 ->> 'gastado')::numeric, 5.00,
  'Este mes suma agente, anuncios y menú de sus clientes; ni los de Rosa ni los sin distribuidor');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 4 ->> 'gastado')::numeric, 0.50, 'El mes pasado');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 3 ->> 'gastado')::numeric, 0.00, 'Un mes sin gasto sale en 0');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 0 ->> 'gastado')::numeric, 2.00, 'El mes más viejo cuenta; el de antes, no');


-- ─── Las altas ────────────────────────────────────────────────────────────────

select is(jsonb_array_length(public.distribuidor_estadisticas() -> 'altas'), 6, 'Las altas son 6 meses');
select is((public.distribuidor_estadisticas() -> 'altas' -> 0 ->> 'mes')::date,
  (date_trunc('month', now() at time zone 'America/Mexico_City') - interval '5 months')::date, 'Empiezan hace 5 meses');
select is((public.distribuidor_estadisticas() -> 'altas' -> 5 ->> 'mes')::date,
  date_trunc('month', now() at time zone 'America/Mexico_City')::date, 'Terminan en este mes');
select is((public.distribuidor_estadisticas() -> 'altas' -> 5 ->> 'altas')::integer, 3, 'Este mes: A, B y H; D es de Rosa');
select is((public.distribuidor_estadisticas() -> 'altas' -> 3 ->> 'altas')::integer, 1, 'Hace 2 meses: C');
select is((public.distribuidor_estadisticas() -> 'altas' -> 4 ->> 'altas')::integer, 0, 'Un mes sin altas sale en 0');
select is((public.distribuidor_estadisticas() -> 'altas' -> 0 ->> 'altas')::integer, 1, 'Hace 5 meses: F; G, de hace 6, ya no');
select is((public.distribuidor_estadisticas() -> 'altas' -> 5 ->> 'total_6_meses')::integer, 5, 'El total de los 6 meses');
select is((public.distribuidor_estadisticas() -> 'altas' -> 0 ->> 'total_6_meses')::integer, 5, 'El mismo total en cada renglón');


-- ─── Lo que vence ─────────────────────────────────────────────────────────────

select is(jsonb_array_length(public.distribuidor_estadisticas() -> 'vencen'), 8, 'De hoy a dentro de 7 días son 8 renglones');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 0 ->> 'dia')::date, (now() at time zone 'America/Mexico_City')::date, 'Empieza hoy');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 7 ->> 'dia')::date, (now() at time zone 'America/Mexico_City')::date + 7, 'Termina en 7 días');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 0 ->> 'cuantos')::integer, 1, 'Hoy: B; ni H, pausado, ni M, sin distribuidor');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 1 ->> 'cuantos')::integer, 0, 'Un día sin nada sale en 0');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 3 ->> 'cuantos')::integer, 1, 'En 3 días, C');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 7 ->> 'cuantos')::integer, 0, 'En 7 días vence D, pero es de Rosa');
select is(
  (select sum((e ->> 'cuantos')::integer)::integer from jsonb_array_elements(public.distribuidor_estadisticas() -> 'vencen') e),
  (select r.vencen_pronto from public.distribuidor_resumen() r),
  'Sumado da lo mismo que su tarjeta');


-- ─── Las fotos ────────────────────────────────────────────────────────────────
-- Hoy guarda una foto vieja a propósito: tiene que ganar lo que está en vivo.

reset role;
do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  juanito bigint := (select id from public.distribuidores where nombre = 'Juanito');
  rosa bigint := (select id from public.distribuidores where nombre = 'Rosa');
begin
  update public.fotos_distribuidores set funcionan = 99, sin_funcionar = 99 where distribuidor_id = juanito and dia = hoy;
  insert into public.fotos_distribuidores (distribuidor_id, dia, funcionan, sin_funcionar) values
    (juanito, hoy - 30, 11, 11),
    (juanito, hoy - 29, 2, 1),
    (juanito, hoy - 1, 5, 2),
    (rosa, hoy - 2, 9, 9);
end;
$$;
select tests.authenticate_as('juanito');

select is(jsonb_array_length(public.distribuidor_estadisticas() -> 'fotos'), 3, 'Salen sus días con foto de los últimos 30, sin el 31 ni los de Rosa');
select is((public.distribuidor_estadisticas() -> 'fotos' -> 0 ->> 'dia')::date, (now() at time zone 'America/Mexico_City')::date - 29, 'De lo más viejo a hoy');
select is((public.distribuidor_estadisticas() -> 'fotos' -> 0 ->> 'funcionan')::integer, 2, 'La foto vieja dice cuántos funcionaban');
select is((public.distribuidor_estadisticas() -> 'fotos' -> 1 ->> 'sin_funcionar')::integer, 2, 'Y cuántos no');
select is((public.distribuidor_estadisticas() -> 'fotos' -> 2 ->> 'dia')::date, (now() at time zone 'America/Mexico_City')::date, 'El último renglón es hoy');
select is((public.distribuidor_estadisticas() -> 'fotos' -> 2 ->> 'funcionan')::integer,
  (select r.funcionan from public.distribuidor_resumen() r), 'Hoy sale en vivo, igual que su tarjeta');
select is((public.distribuidor_estadisticas() -> 'fotos' -> 2 ->> 'sin_funcionar')::integer,
  (select r.sin_funcionar from public.distribuidor_resumen() r), 'Y sin funcionar también');


-- ─── Cada quien lo suyo ───────────────────────────────────────────────────────

select tests.authenticate_as('rosa');
select is((public.distribuidor_estadisticas() -> 'gasto' -> 5 ->> 'gastado')::numeric, 4.00, 'Rosa ve el gasto de los suyos');
select is((public.distribuidor_estadisticas() -> 'altas' -> 5 ->> 'altas')::integer, 2, 'Y sus altas: D y E');
select is(jsonb_array_length(public.distribuidor_estadisticas() -> 'fotos'), 2, 'Y sus fotos');
select is((public.distribuidor_estadisticas() -> 'vencen' -> 7 ->> 'cuantos')::integer, 1, 'Y lo que le vence: D en 7 días');

select tests.authenticate_as('lalo');
select is(
  (select sum((e ->> 'gastado')::numeric) from jsonb_array_elements(public.distribuidor_estadisticas() -> 'gasto') e), 0::numeric,
  'Sin clientes, el gasto sale en 0');
select is((public.distribuidor_estadisticas() -> 'altas' -> 0 ->> 'total_6_meses')::integer, 0, 'Sin altas');
select is(public.distribuidor_estadisticas() -> 'fotos',
  jsonb_build_array(jsonb_build_object('dia', (now() at time zone 'America/Mexico_City')::date, 'funcionan', 0, 'sin_funcionar', 0)),
  'Hoy, en 0');
select is(
  (select sum((e ->> 'cuantos')::integer)::integer from jsonb_array_elements(public.distribuidor_estadisticas() -> 'vencen') e), 0,
  'Nada por vencer');

select * from finish();
rollback;
