-- Pruebas de la lectura del panel del distribuidor (migración distribuidor_lectura):
-- quién puede llamar sus 2 funciones, que cada distribuidor vea solo a sus clientes con
-- su vigencia bien contada, y que de baja no reciba nada.
--
-- Escenario, con "hoy" en la hora de México. De Juanito: A vigente (vence en 30 días),
-- B vence hoy, C vence en 7, E venció ayer, F pausado, G pausado sin fecha de fin, H
-- pausado que vence hoy y K en Pacific/Kiritimati (UTC+14), que vence hoy en su zona. D vence en 8 y es directo; L
-- vence en 3 y es de Rafa, que no tiene cuenta. Lupita tiene cuenta y ningún cliente;
-- Paty tiene cuenta y está de baja. Gerente A es gerente de A.
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
  perform tests.create_supabase_user('lupita', 'lupita@prueba.test');
  perform tests.create_supabase_user('paty', 'paty@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, usuario_id, activo) values
    ('Juanito', tests.get_supabase_uid('juanito'), true),
    ('Lupita', tests.get_supabase_uid('lupita'), true),
    ('Paty', tests.get_supabase_uid('paty'), false),
    ('Rafa', null, true);

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A vigente', 'a-vigente', true, hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B vence hoy', 'b-vence-hoy', true, hoy - 30, hoy,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'C vence en 7', 'c-vence-en-7', true, hoy - 30, hoy + 7,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'D vence en 8', 'd-vence-en-8', true, hoy - 30, hoy + 8, null),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'E venció ayer', 'e-vencio-ayer', true, hoy - 31, hoy - 1,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'F pausado', 'f-pausado', false, hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('11111111-1111-4111-8111-111111111111', 'G pausado sin fin', 'g-pausado-sin-fin', false, null, null,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('22222222-2222-4222-8222-222222222222', 'H pausado vence hoy', 'h-pausado-vence-hoy', false, hoy - 30, hoy,
      (select id from public.distribuidores where nombre = 'Juanito')),
    ('44444444-4444-4444-8444-444444444444', 'L de Rafa', 'l-de-rafa', true, hoy - 30, hoy + 3,
      (select id from public.distribuidores where nombre = 'Rafa'));

  insert into public.restaurantes (id, nombre, slug, zona_horaria, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id) values
    ('33333333-3333-4333-8333-333333333333', 'K en Kiritimati', 'k-kiritimati', 'Pacific/Kiritimati', true, hoy_k - 30, hoy_k,
      (select id from public.distribuidores where nombre = 'Juanito'));

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}');
end;
$$;

-- El id de un distribuidor por su nombre, para escribir las llamadas como las haría el
-- panel de Fragmentless.
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

select plan(35);


-- ─── Quién puede llamarlas ────────────────────────────────────────────────────

select is_empty(
  $$ select f from unnest(array['public.distribuidor_resumen()', 'public.distribuidor_clientes()']) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE') $$,
  'Con sesión se pueden llamar las 2 funciones'
);

select is_empty(
  $$ select f || ': ' || r
     from unnest(array['public.distribuidor_resumen()', 'public.distribuidor_clientes()']) as f,
          unnest(array['anon', 'service_role']) as r
     where has_function_privilege(r, f, 'EXECUTE') $$,
  'anon y service_role no llaman ninguna'
);

select ok(
  not has_function_privilege('authenticated', 'privado.mi_distribuidor()', 'EXECUTE'),
  'privado.mi_distribuidor no la llama nadie con sesión: solo la usan las 2 funciones'
);

select tests.clear_authentication();

select throws_ok('select public.distribuidor_resumen()', '42501', null, 'Sin sesión no se llama distribuidor_resumen');
select throws_ok('select public.distribuidor_clientes()', '42501', null, 'Sin sesión no se llama distribuidor_clientes');

select tests.authenticate_as('gerente_a');

select throws_ok('select public.distribuidor_resumen()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Un gerente no puede llamar distribuidor_resumen');
select throws_ok('select public.distribuidor_clientes()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Un gerente no puede llamar distribuidor_clientes');

select tests.authenticate_as('fragmentless');

select throws_ok('select public.distribuidor_resumen()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Fragmentless no es distribuidor: no llama distribuidor_resumen');
select throws_ok('select public.distribuidor_clientes()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Fragmentless no es distribuidor: no llama distribuidor_clientes');

select tests.authenticate_as('paty');

select throws_ok('select public.distribuidor_resumen()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Paty está de baja: distribuidor_resumen no le da nada');
select throws_ok('select public.distribuidor_clientes()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Paty está de baja: distribuidor_clientes no le da nada');

select results_eq(
  'select nombre, activo from public.distribuidores',
  $$ values ('Paty', false) $$,
  'De baja, Paty todavía lee su propia fila: así la app sabe que está de baja'
);


-- ─── Lo que ve Juanito ────────────────────────────────────────────────────────

select tests.authenticate_as('juanito');

select is_empty(
  'select id from public.restaurantes',
  'Juanito no lee la tabla restaurantes directo: sus clientes solo le llegan por las funciones'
);

select results_eq(
  'select total, funcionan, vencen_pronto, vencen_hoy, sin_funcionar, vencidos, pausados from public.distribuidor_resumen()',
  $$ values (8, 4, 3, 2, 4, 1, 3) $$,
  'Inicio: 4 de sus 8 funcionan, 3 vencen en 7 días (2 hoy, sin contar a H pausado), 4 sin funcionar (1 vencido, 3 pausados)'
);

select results_eq(
  'select slug from public.distribuidor_clientes()',
  array['e-vencio-ayer', 'b-vence-hoy', 'h-pausado-vence-hoy', 'k-kiritimati', 'c-vence-en-7', 'a-vigente', 'f-pausado', 'g-pausado-sin-fin'],
  'Solo sus 8 clientes, sin D (directo) ni L (de Rafa), por fecha de fin y sin fecha al final'
);

select set_eq(
  'select slug, dias_restantes, estado from public.distribuidor_clientes()',
  $$ values ('a-vigente', 30, 'vigente'),
            ('b-vence-hoy', 0, 'vence_pronto'),
            ('c-vence-en-7', 7, 'vence_pronto'),
            ('e-vencio-ayer', -1, 'vencida'),
            ('f-pausado', 30, 'pausada'),
            ('g-pausado-sin-fin', null::integer, 'pausada'),
            ('h-pausado-vence-hoy', 0, 'pausada'),
            ('k-kiritimati', 0, 'vence_pronto') $$,
  'Cada cliente con sus días restantes y su vigencia; K vence hoy en su zona, no en la de México'
);

select results_eq(
  $$ select nombre, licencia_activa, licencia_inicio, licencia_fin
     from public.distribuidor_clientes() where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff' $$,
  $$ select 'F pausado', false, hoy - 30, hoy + 30
     from (select (now() at time zone 'America/Mexico_City')::date as hoy) h $$,
  'Cada cliente trae su nombre, si su licencia está prendida y sus fechas de inicio y fin'
);

select set_eq(
  $$ select slug from public.distribuidor_clientes() where estado in ('vencida', 'vence_pronto') $$,
  array['b-vence-hoy', 'c-vence-en-7', 'e-vencio-ayer', 'k-kiritimati'],
  'Vencen pronto: sus vencidos y los que vencen en 7 días, sin los pausados'
);


-- ─── Lupita, sin clientes ─────────────────────────────────────────────────────

select tests.authenticate_as('lupita');

select results_eq(
  'select total, funcionan, vencen_pronto, vencen_hoy, sin_funcionar, vencidos, pausados from public.distribuidor_resumen()',
  $$ values (0, 0, 0, 0, 0, 0, 0) $$,
  'Sin clientes, las 3 cifras de Lupita salen en 0'
);

select is_empty('select id from public.distribuidor_clientes()', 'Y su lista sale vacía');


-- ─── De baja y reactivada ─────────────────────────────────────────────────────

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Lupita'), false) $$,
  'Fragmentless da de baja a Lupita'
);

select tests.authenticate_as('lupita');

select throws_ok('select public.distribuidor_resumen()', '42501', 'Solo un distribuidor activo puede ver esto',
  'De baja, Lupita ya no recibe sus cifras');
select throws_ok('select public.distribuidor_clientes()', '42501', 'Solo un distribuidor activo puede ver esto',
  'Ni su lista');

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.fijar_distribuidor_activo(tests.distribuidor('Lupita'), true) $$,
  'Fragmentless reactiva a Lupita'
);

select tests.authenticate_as('lupita');

select lives_ok('select public.distribuidor_clientes()', 'Reactivada, Lupita vuelve a leer su lista');


-- ─── Después de un cambio, la lectura ya lo trae ──────────────────────────────

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.asignar_distribuidor('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.distribuidor('Juanito')) $$,
  'Fragmentless le asigna D a Juanito'
);

select lives_ok(
  $$ select public.asignar_distribuidor('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.distribuidor('Lupita')) $$,
  'Y pasa C de Juanito a Lupita'
);

select lives_ok(
  $$ select public.extender_licencia('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 1) $$,
  'E paga un mes'
);

select tests.authenticate_as('juanito');

select set_eq(
  'select slug from public.distribuidor_clientes()',
  array['a-vigente', 'b-vence-hoy', 'd-vence-en-8', 'e-vencio-ayer', 'f-pausado', 'g-pausado-sin-fin', 'h-pausado-vence-hoy', 'k-kiritimati'],
  'Juanito ya ve a D y ya no ve a C'
);

select results_eq(
  $$ select estado from public.distribuidor_clientes() where slug = 'e-vencio-ayer' $$,
  array['vigente'],
  'Ya pagado, E le sale vigente'
);

select results_eq(
  'select total, funcionan, vencen_pronto, vencen_hoy, sin_funcionar, vencidos, pausados from public.distribuidor_resumen()',
  $$ values (8, 5, 2, 2, 3, 0, 3) $$,
  'Y en su Inicio: 5 de 8 funcionan, 2 vencen hoy, 3 pausados y ningún vencido'
);

select tests.authenticate_as('lupita');

select results_eq(
  'select slug, estado from public.distribuidor_clientes()',
  $$ values ('c-vence-en-7', 'vence_pronto') $$,
  'Lupita ya ve a C, con su vigencia'
);

select results_eq(
  'select total, funcionan, vencen_pronto from public.distribuidor_resumen()',
  $$ values (1, 1, 1) $$,
  'Y sus cifras cuentan a C'
);

select tests.authenticate_as('fragmentless');

select lives_ok(
  $$ select public.fijar_licencia(id, false, licencia_inicio, licencia_fin)
     from public.restaurantes where slug = 'c-vence-en-7' $$,
  'Fragmentless pausa C'
);

select tests.authenticate_as('lupita');

select results_eq(
  $$ select estado from public.distribuidor_clientes() where slug = 'c-vence-en-7' $$,
  array['pausada'],
  'A Lupita, C le sale pausado al momento'
);


select * from finish();

rollback;
