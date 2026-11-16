-- Pruebas de la migración logo_del_aparato (16 de noviembre de 2026; planes/trabajo/aparato-logo/): «¿Quién eres?»
-- (nombres_del_aparato) dice también el logo del restaurante del aparato, para que /equipo enseñe el logo del cliente
-- en vez de la estrella de Fragmentless. Lo demás de su respuesta no cambia (lo prueban empleados y pedidos).
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


-- Como el Worker: service_role, sin sesión de nadie. Así llama a las funciones del aparato.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

-- La huella del secreto de un aparato, como la guarda la base.
create function tests.huella(p_token text)
returns text
language sql
as $$
  select encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas, con ids fijos. A tiene logo, con su tableta compartida y el celular de
-- Pepe; B, sin logo, con su tableta; C, con logo pero pausado, con su tableta; y una tableta de A ya desligada.

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  hoy date := privado.dia_local('America/Mexico_City');
  pin text := extensions.crypt(repeat('1', 64), extensions.gen_salt('bf', 4));
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@personal.prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, logo_ruta) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30,
       'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/logo/0123456789abcdef0123456789abcdef.webp'),
    (b, 'Café Luna', 'cafe-luna', true, hoy - 30, hoy + 30, null),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30,
       'restaurantes/cccccccc-cccc-4ccc-8ccc-cccccccccccc/logo/fedcba9876543210fedcba9876543210.webp');

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo, pin_hash) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true, null),
    (102, a, tests.get_supabase_uid('pepe'), 'Pepe Martínez', '{mesero}', true, pin),
    (201, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true, null),
    (301, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true, null);

  insert into public.dispositivos (id, restaurante_id, nombre, miembro_id, token_hash, sesion_id, vinculado_por, revocado_at) values
    ('d0000000-0000-4000-8000-000000000001', a, 'Tableta de la entrada', null, tests.huella(repeat('A', 43)), null, 101, null),
    ('d0000000-0000-4000-8000-000000000002', a, 'Celular de Pepe', 102, tests.huella(repeat('B', 43)), null, 101, null),
    ('d0000000-0000-4000-8000-000000000003', b, 'Caja', null, tests.huella(repeat('C', 43)), null, 201, null),
    ('d0000000-0000-4000-8000-000000000004', c, 'Tableta C', null, tests.huella(repeat('D', 43)), null, 301, null),
    ('d0000000-0000-4000-8000-000000000005', a, 'Tableta vieja', null, tests.huella(repeat('E', 43)), null, 101, now() - interval '1 day');
end;
$$;

select plan(10);


-- ─── Quién la ejecuta ─────────────────────────────────────────────────────────

select ok(
  has_function_privilege('service_role', 'public.nombres_del_aparato(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.nombres_del_aparato(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.nombres_del_aparato(text)', 'EXECUTE'),
  'Reemplazarla conserva sus permisos: solo el Worker'
);


-- ─── El logo ──────────────────────────────────────────────────────────────────

select tests.como_worker();

select is(
  public.nombres_del_aparato(repeat('A', 43)) ->> 'logo',
  'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/logo/0123456789abcdef0123456789abcdef.webp',
  'La tableta compartida dice el logo de su restaurante'
);

select is(
  public.nombres_del_aparato(repeat('B', 43)) ->> 'logo',
  'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/logo/0123456789abcdef0123456789abcdef.webp',
  'El celular de Pepe también'
);

select ok(
  (public.nombres_del_aparato(repeat('C', 43)) ? 'logo')
  and public.nombres_del_aparato(repeat('C', 43)) -> 'logo' = 'null'::jsonb,
  'Sin logo, la llave va con null (el aparato enseña solo el nombre)'
);

select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.nombres_del_aparato(repeat('A', 43))) k),
  array['aparato', 'compartido', 'logo', 'pedidos_por_confirmar', 'personas', 'restaurante'],
  'La respuesta trae lo de antes y el logo, nada más'
);

select is(
  public.nombres_del_aparato(repeat('A', 43)) - 'logo' - 'personas' - 'pedidos_por_confirmar',
  '{"restaurante": "La Fonda de Don Chuy", "aparato": "Tableta de la entrada", "compartido": true}'::jsonb,
  'Lo demás sigue igual'
);

select is(
  jsonb_path_query_array(public.nombres_del_aparato(repeat('B', 43)), '$.personas[*].nombre'),
  '["Pepe Martínez"]'::jsonb,
  'En el celular de Pepe solo sale Pepe, como antes'
);


-- ─── Cuando no se puede ───────────────────────────────────────────────────────

select throws_ok(
  format('select public.nombres_del_aparato(%L)', repeat('D', 43)),
  '42501', 'La suscripción de este restaurante no está vigente. Avísale a tu gerente.',
  'Un restaurante pausado no enseña su logo'
);

select throws_ok(
  format('select public.nombres_del_aparato(%L)', repeat('E', 43)),
  'P0002', 'Este aparato ya no está ligado. Pídele a tu gerente un código nuevo.',
  'Una tableta desligada, tampoco'
);


-- ─── Cambia con «Tu restaurante» ──────────────────────────────────────────────

reset role;
update public.restaurantes set logo_ruta = null where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.como_worker();

select is(
  public.nombres_del_aparato(repeat('A', 43)) -> 'logo',
  'null'::jsonb,
  'Si el gerente quita el logo, el aparato ya no lo dice'
);


select * from finish();

rollback;
