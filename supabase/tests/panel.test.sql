-- Pruebas de la lectura del panel de Fragmentless (migración panel_lectura): quién
-- puede llamar sus 4 funciones y que cuenten bien la vigencia, las 3 cifras de
-- Inicio, las altas por mes y los clientes de cada distribuidor.
--
-- Escenario, con "hoy" en la hora de México: A vigente (vence en 30 días) y B que
-- vence hoy, los dos de Juanito; C vence en 7 días, de Lupita; D vence en 8; E venció
-- ayer; F pausado; G pausado sin fecha de fin; H pausado y vencido; K en
-- Pacific/Kiritimati (UTC+14) vence hoy en su zona. Los distribuidores: Juanito con
-- cuenta, Lupita y Rafa sin cuenta, Paty de baja. Las altas: A, B, G, H y K este mes,
-- C hace 1 mes, D hace 2, E hace 5 y F hace 6 (fuera de los 6 meses).
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
-- Se siembra como postgres, dueño de las tablas. created_at se fija a mediodía del
-- día 15 de cada mes en la hora de México, lejos de cualquier cambio de mes.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  hoy_k date := privado.dia_local('Pacific/Kiritimati');
  mes date := date_trunc('month', privado.dia_local('America/Mexico_City')::timestamp)::date;
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, usuario_id, activo) values
    ('Juanito', tests.get_supabase_uid('juanito'), true),
    ('Lupita', null, true),
    ('Rafa', null, true),
    ('Paty', null, false);

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, distribuidor_id, created_at) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A vigente', 'a-vigente', true, hoy - 30, hoy + 30,
      (select id from public.distribuidores where nombre = 'Juanito'),
      (mes + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B vence hoy', 'b-vence-hoy', true, hoy - 30, hoy,
      (select id from public.distribuidores where nombre = 'Juanito'),
      (mes + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'C vence en 7', 'c-vence-en-7', true, hoy - 30, hoy + 7,
      (select id from public.distribuidores where nombre = 'Lupita'),
      (mes - interval '1 month' + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'D vence en 8', 'd-vence-en-8', true, hoy - 30, hoy + 8, null,
      (mes - interval '2 months' + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'E venció ayer', 'e-vencio-ayer', true, hoy - 31, hoy - 1, null,
      (mes - interval '5 months' + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'F pausado', 'f-pausado', false, hoy - 30, hoy + 30, null,
      (mes - interval '6 months' + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('11111111-1111-4111-8111-111111111111', 'G pausado sin fin', 'g-pausado-sin-fin', false, null, null, null,
      (mes + interval '14 days 12 hours') at time zone 'America/Mexico_City'),
    ('22222222-2222-4222-8222-222222222222', 'H pausado y vencido', 'h-pausado-vencido', false, hoy - 35, hoy - 5, null,
      (mes + interval '14 days 12 hours') at time zone 'America/Mexico_City');

  insert into public.restaurantes (id, nombre, slug, zona_horaria, licencia_activa, licencia_inicio, licencia_fin, created_at) values
    ('33333333-3333-4333-8333-333333333333', 'K en Kiritimati', 'k-kiritimati', 'Pacific/Kiritimati', true, hoy_k - 30, hoy_k,
      (mes + interval '14 days 12 hours') at time zone 'America/Mexico_City');

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}');
end;
$$;

select plan(33);


-- ─── Quién puede llamar las funciones ─────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok('select public.panel_resumen()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no puede llamar panel_resumen');
select throws_ok('select public.panel_altas_por_mes()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no puede llamar panel_altas_por_mes');
select throws_ok('select public.panel_clientes()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no puede llamar panel_clientes');
select throws_ok('select public.panel_distribuidores()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no puede llamar panel_distribuidores');

select tests.authenticate_as('juanito');

select throws_ok('select public.panel_resumen()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un distribuidor no puede llamar panel_resumen');
select throws_ok('select public.panel_altas_por_mes()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un distribuidor no puede llamar panel_altas_por_mes');
select throws_ok('select public.panel_clientes()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un distribuidor no puede llamar panel_clientes');
select throws_ok('select public.panel_distribuidores()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un distribuidor no puede llamar panel_distribuidores');

select tests.clear_authentication();

select throws_ok('select public.panel_resumen()', '42501', null, 'Sin sesión no se llama panel_resumen');
select throws_ok('select public.panel_altas_por_mes()', '42501', null, 'Sin sesión no se llama panel_altas_por_mes');
select throws_ok('select public.panel_clientes()', '42501', null, 'Sin sesión no se llama panel_clientes');
select throws_ok('select public.panel_distribuidores()', '42501', null, 'Sin sesión no se llama panel_distribuidores');

select tests.authenticate_as('fragmentless');

select throws_ok('select privado.vigencias()', '42501', null,
  'Ni Fragmentless llama privado.vigencias directo: solo la usan las funciones del panel');


-- ─── La vigencia de cada restaurante ──────────────────────────────────────────

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'a-vigente' $$,
  $$ values (30, 'vigente') $$,
  'A, que vence en 30 días, está vigente'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'b-vence-hoy' $$,
  $$ values (0, 'vence_pronto') $$,
  'B vence hoy: 0 días y vence pronto'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'c-vence-en-7' $$,
  $$ values (7, 'vence_pronto') $$,
  'C, que vence en 7 días, todavía cuenta como vence pronto'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'd-vence-en-8' $$,
  $$ values (8, 'vigente') $$,
  'D, que vence en 8 días, ya no: está vigente'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'e-vencio-ayer' $$,
  $$ values (-1, 'vencida') $$,
  'E venció ayer: -1 día y vencida'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'f-pausado' $$,
  $$ values (30, 'pausada') $$,
  'F está pausado aunque le falten 30 días'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'g-pausado-sin-fin' $$,
  $$ values (null::integer, 'pausada') $$,
  'G, pausado y sin fecha de fin, no tiene días restantes'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'h-pausado-vencido' $$,
  $$ values (-5, 'pausada') $$,
  'H, pausado y vencido, cuenta como pausado'
);

select results_eq(
  $$ select dias_restantes, estado from public.panel_clientes() where slug = 'k-kiritimati' $$,
  $$ values (0, 'vence_pronto') $$,
  'K vence hoy en su zona (Kiritimati), no en la de México'
);


-- ─── Lo que lee cada parte del panel ──────────────────────────────────────────

select results_eq(
  'select total, funcionan, vencen_pronto, vencen_hoy, sin_funcionar, vencidos, pausados from public.panel_resumen()',
  $$ values (9, 5, 3, 2, 4, 1, 3) $$,
  'Inicio: 5 de 9 funcionan, 3 vencen en 7 días (2 hoy), 4 sin funcionar (1 vencido, 3 pausados)'
);

select results_eq(
  'select slug from public.panel_clientes()',
  array['h-pausado-vencido', 'e-vencio-ayer', 'b-vence-hoy', 'k-kiritimati', 'c-vence-en-7',
        'd-vence-en-8', 'a-vigente', 'f-pausado', 'g-pausado-sin-fin'],
  'Clientes va por fecha de fin, lo que vence primero arriba y sin fecha al final'
);

select results_eq(
  $$ select slug, distribuidor_nombre from public.panel_clientes()
     where distribuidor_id is not null order by slug $$,
  $$ values ('a-vigente', 'Juanito'), ('b-vence-hoy', 'Juanito'), ('c-vence-en-7', 'Lupita') $$,
  'Cada cliente trae el nombre de su distribuidor; los demás son directos'
);

select set_eq(
  $$ select slug from public.panel_clientes() where estado in ('vencida', 'vence_pronto') $$,
  array['b-vence-hoy', 'c-vence-en-7', 'e-vencio-ayer', 'k-kiritimati'],
  'Vencen pronto: los vencidos y los que vencen en 7 días, sin los pausados'
);

select results_eq(
  'select mes, altas, total_6_meses from public.panel_altas_por_mes()',
  $$ select (date_trunc('month', (now() at time zone 'America/Mexico_City')::date::timestamp)
             - make_interval(months => t.atras))::date,
            t.altas, 8
     from (values (5, 1), (4, 0), (3, 0), (2, 1), (1, 1), (0, 5)) as t(atras, altas) $$,
  'Altas por mes: los 6 meses en orden, los vacíos en 0, sin F (hace 6 meses), 8 en total'
);

select results_eq(
  'select nombre, activo, cuenta_ligada, clientes from public.panel_distribuidores()',
  $$ values ('Juanito', true, true, 2), ('Lupita', true, false, 1), ('Rafa', true, false, 0), ('Paty', false, false, 0) $$,
  'Distribuidores: activos de más a menos clientes, Paty de baja al final, y quién tiene cuenta'
);


-- ─── Después de un cambio, la lectura ya lo trae ──────────────────────────────

select lives_ok(
  $$ select public.extender_licencia('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 1) $$,
  'E paga un mes'
);

select results_eq(
  $$ select estado from public.panel_clientes() where slug = 'e-vencio-ayer' $$,
  array['vigente'],
  'Ya pagado, E sale vigente'
);

select results_eq(
  'select funcionan, sin_funcionar, vencidos from public.panel_resumen()',
  $$ values (6, 3, 0) $$,
  'Y en Inicio ya funcionan 6, sin funcionar quedan 3 y ningún vencido'
);

select lives_ok(
  $$ select public.fijar_licencia(id, false, licencia_inicio, licencia_fin)
     from public.restaurantes where slug = 'a-vigente' $$,
  'Fragmentless pausa A'
);

select results_eq(
  $$ select estado from public.panel_clientes() where slug = 'a-vigente' $$,
  array['pausada'],
  'A sale pausado al momento'
);


select * from finish();

rollback;
