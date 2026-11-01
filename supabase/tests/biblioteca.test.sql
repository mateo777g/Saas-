-- Pruebas de la migración biblioteca (parte 7b-2): Mi biblioteca (lo que ven los gerentes de la
-- sucursal, en su orden, con su día y «Se borra en…» del calendario de su restaurante), Eliminar
-- (si se puede, y el renglón después de R2), el borrado de los 30 días (los vencidos, hasta 1,000
-- por día, también de un restaurante pausado o con la licencia vencida) y que borrar no toca uso_ia.
--
-- Escenario: Fragmentless, La Fonda de Don Chuy con dos gerentes (Don Chuy y su socia Rosa) y Pepe
-- de mesero, el Restaurante B, el C con la licencia vencida, y el K y el P en Kiritimati y Pago Pago.
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

-- Los ayudantes de estas pruebas. Los estilos, los anuncios y uso_ia se leen como su dueño, porque
-- nadie con sesión los lee completos.

create function tests.e(p_clave text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.estilos where clave = p_clave;
$$;

create function tests.anuncio(p_id bigint)
returns public.anuncios
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.anuncios where id = p_id;
$$;

create function tests.uso(p_restaurante_id uuid)
returns public.uso_ia
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.uso_ia
  where restaurante_id = p_restaurante_id
    and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
$$;

create function tests.miembro(p_nombre text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.miembros where nombre = p_nombre;
$$;

-- El id de cada anuncio que siembran las pruebas, por su nombre.
create table tests.ids (nombre text primary key, id bigint not null);

create function tests.id(p_nombre text)
returns bigint
language sql
stable
as $$
  select id from tests.ids where nombre = p_nombre;
$$;

create function tests.ids_de(p_nombres text[])
returns bigint[]
language sql
stable
as $$
  select coalesce(array_agg(i.id order by n), '{}')
  from unnest(p_nombres) with ordinality as u (nombre, n)
  join tests.ids i on i.nombre = u.nombre;
$$;

-- Los ids de una lista de anuncios, en su orden.
create function tests.lista(p_lista jsonb)
returns bigint[]
language sql
immutable
as $$
  select coalesce(array_agg((x ->> 'id')::bigint order by n), '{}')
  from jsonb_array_elements(p_lista) with ordinality as e (x, n);
$$;

-- Esos anuncios del más viejo al más nuevo por su día de vencer, como su dueño.
create function tests.del_mas_viejo(p_nombres text[])
returns bigint[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(a.id order by a.vence, a.id), '{}')
  from public.anuncios a
  where a.id in (select i.id from tests.ids i where i.nombre = any (p_nombres));
$$;

-- Cuántos de esos siguen en la tabla, como su dueño.
create function tests.quedan(p_nombres text[])
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.anuncios a
  where a.id in (select i.id from tests.ids i where i.nombre = any (p_nombres));
$$;

-- Hoy en el calendario de una zona, y un momento de un día a una hora de esa zona.
create function tests.hoy(p_zona text default 'America/Mexico_City')
returns date
language sql
stable
as $$
  select (now() at time zone p_zona)::date;
$$;

create function tests.a_las(p_dia date, p_hora time, p_zona text default 'America/Mexico_City')
returns timestamptz
language sql
immutable
as $$
  select (p_dia + p_hora) at time zone p_zona;
$$;

-- El archivo de un anuncio sembrado: su nombre en md5, en la biblioteca de su restaurante.
create function tests.ruta(p_restaurante uuid, p_nombre text)
returns text
language sql
immutable
as $$
  select 'restaurantes/' || p_restaurante || '/biblioteca/' || md5(p_nombre) || '.jpg';
$$;

-- Siembra un anuncio como lo dejan apartar_anuncio, terminar_anuncio y fallar_anuncio: listo con su
-- archivo, «fallo» sin archivo o «haciendo» sin terminar. Uno terminado vence el día en que terminó
-- en el calendario de su restaurante más 29. Se llama como su dueño.
create function tests.sembrar(
  p_nombre text, p_restaurante uuid, p_quien text, p_estilo text, p_formato text, p_productos jsonb,
  p_estado text, p_terminado timestamptz
)
returns bigint
language plpgsql
as $$
declare
  v_id bigint;
  v_zona text;
begin
  select zona_horaria into v_zona from public.restaurantes where id = p_restaurante;
  insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, motivo, ruta,
                               terminado_at, vence, created_at)
  values (p_restaurante, tests.e(p_estilo), p_formato, p_productos, tests.miembro(p_quien), p_estado,
          case when p_estado = 'fallo' then 'no_salio' end,
          case when p_estado = 'listo' then tests.ruta(p_restaurante, p_nombre) end,
          p_terminado,
          case when p_estado <> 'haciendo' then privado.dia_local(v_zona, p_terminado) + 29 end,
          coalesce(p_terminado - interval '1 minute', now()))
  returning id into v_id;
  insert into tests.ids values (p_nombre, v_id);
  return v_id;
end;
$$;

-- La sesión del aparato ligado de Pepe, como en las pruebas de empleados.
create function tests.en_aparato(p_sesion uuid)
returns void as $$
begin
  perform set_config('request.jwt.claims',
    (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
      || jsonb_build_object('session_id', p_sesion))::text, true);
end
$$ language plpgsql;

-- El Worker con la llave secreta.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

grant select on tests.ids to authenticated, service_role;
grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres. La Fonda de Don Chuy (hora de México) tiene dos gerentes, Don Chuy y su
-- socia Rosa, y a Pepe de mesero; lleva 7 anuncios este mes. El Restaurante B es de otro gerente;
-- el C tiene la licencia vencida. El K está en Kiritimati (UTC+14) y el P en Pago Pago (UTC−11):
-- entre los dos hay 25 horas, así que su día nunca es el mismo, y una sola zona para todos no puede
-- acertarle a los dos.
--
-- Los anuncios de La Fonda se siembran en un orden distinto al de la hora en que terminaron:
--   viejo           cartel   Don Chuy  terminó hace 29 días: hoy es su último día
--   de_hoy_tarde    post     Rosa      hoy a las 15:26
--   de_ayer         historia Rosa      ayer a las 21:40
--   de_hoy          post     Don Chuy  hoy a las 09:05
--   vencido_a       post     Don Chuy  hace 30 días: su último día fue ayer
--   no_salio_a      post     Don Chuy  hoy, no salió
--   no_salio_viejo  historia Rosa      hace 32 días, no salió
--   haciendo_a      cartel   Rosa      se está haciendo desde hace 90 segundos

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  k uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  p uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');
  perform tests.create_supabase_user('rosa', 'rosa@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_k', 'gerente.k@prueba.test');
  perform tests.create_supabase_user('gerente_p', 'gerente.p@prueba.test');

  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, zona_horaria,
                                   tope_ia_usd_mes) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, 'America/Mexico_City', 10),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, 'America/Mexico_City', 10),
    (c, 'Restaurante C', 'restaurante-c', true, hoy - 60, hoy - 2, 'America/Mexico_City', 10),
    (k, 'Restaurante K', 'restaurante-k', true, hoy - 30, hoy + 30, 'Pacific/Kiritimati', 10),
    (p, 'Restaurante P', 'restaurante-p', true, hoy - 30, hoy + 30, 'Pacific/Pago_Pago', 10);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    (a, tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}'),
    (a, tests.get_supabase_uid('rosa'), 'Rosa', '{gerente}'),
    (a, tests.get_supabase_uid('pepe'), 'Pepe', '{mesero}'),
    (b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}'),
    (c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}'),
    (k, tests.get_supabase_uid('gerente_k'), 'Gerente K', '{gerente}'),
    (p, tests.get_supabase_uid('gerente_p'), 'Gerente P', '{gerente}');

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id)
  select restaurante_id, 'Celular de Pepe', id, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'
  from public.miembros where nombre = 'Pepe';

  perform tests.sembrar('viejo', a, 'Don Chuy', 'banderitas', 'cartel',
                        '[{"id": 501, "nombre": "Taco al pastor"}]', 'listo', tests.a_las(hoy - 29, '12:00'));
  perform tests.sembrar('de_hoy_tarde', a, 'Rosa', 'clasico', 'post',
                        '[{"id": 503, "nombre": "Gringa"}, {"id": 502, "nombre": "Torta"}, {"id": 508, "nombre": "Jamaica"}]',
                        'listo', tests.a_las(hoy, '15:26'));
  perform tests.sembrar('de_ayer', a, 'Rosa', 'banderitas', 'historia',
                        '[{"id": 502, "nombre": "Torta"}]', 'listo', tests.a_las(hoy - 1, '21:40'));
  perform tests.sembrar('de_hoy', a, 'Don Chuy', 'banderitas', 'post',
                        '[{"id": 501, "nombre": "Taco al pastor"}, {"id": 502, "nombre": "Torta"}]',
                        'listo', tests.a_las(hoy, '09:05'));
  perform tests.sembrar('vencido_a', a, 'Don Chuy', 'cuadros', 'post',
                        '[{"id": 501, "nombre": "Taco al pastor"}]', 'listo', tests.a_las(hoy - 30, '10:00'));
  perform tests.sembrar('no_salio_a', a, 'Don Chuy', 'clasico', 'post',
                        '[{"id": 501, "nombre": "Taco al pastor"}]', 'fallo', tests.a_las(hoy, '08:00'));
  perform tests.sembrar('no_salio_viejo', a, 'Rosa', 'cuadros', 'historia',
                        '[{"id": 501, "nombre": "Taco al pastor"}]', 'fallo', tests.a_las(hoy - 32, '10:00'));
  perform tests.sembrar('haciendo_a', a, 'Rosa', 'banderitas', 'cartel',
                        '[{"id": 503, "nombre": "Gringa"}, {"id": 508, "nombre": "Jamaica"}]', 'haciendo', null);
  update public.anuncios set created_at = now() - interval '90 seconds' where id = tests.id('haciendo_a');

  perform tests.sembrar('de_b', b, 'Gerente B', 'clasico', 'post', '[{"id": 511, "nombre": "Taco B"}]',
                        'listo', tests.a_las(hoy, '11:00'));
  perform tests.sembrar('vencido_b', b, 'Gerente B', 'clasico', 'post', '[{"id": 511, "nombre": "Taco B"}]',
                        'listo', tests.a_las(hoy - 31, '11:00'));
  perform tests.sembrar('haciendo_b', b, 'Gerente B', 'clasico', 'post', '[{"id": 511, "nombre": "Taco B"}]',
                        'haciendo', null);

  perform tests.sembrar('de_c', c, 'Gerente C', 'clasico', 'post', '[{"id": 521, "nombre": "Taco C"}]',
                        'listo', tests.a_las(hoy, '11:00'));
  perform tests.sembrar('vencido_c', c, 'Gerente C', 'clasico', 'post', '[{"id": 521, "nombre": "Taco C"}]',
                        'listo', tests.a_las(hoy - 34, '11:00'));

  -- En K, uno de hoy a las 7:15 de su hora y uno cuyo último día fue ayer en su calendario; en P, uno
  -- cuyo último día es hoy en el suyo.
  perform tests.sembrar('de_k', k, 'Gerente K', 'clasico', 'post', '[{"id": 531, "nombre": "Taco K"}]',
                        'listo', tests.a_las(tests.hoy('Pacific/Kiritimati'), '07:15', 'Pacific/Kiritimati'));
  perform tests.sembrar('vencido_k', k, 'Gerente K', 'clasico', 'post', '[{"id": 531, "nombre": "Taco K"}]',
                        'listo', tests.a_las(tests.hoy('Pacific/Kiritimati') - 30, '12:00', 'Pacific/Kiritimati'));
  perform tests.sembrar('ultimo_p', p, 'Gerente P', 'clasico', 'post', '[{"id": 541, "nombre": "Taco P"}]',
                        'listo', tests.a_las(tests.hoy('Pacific/Pago_Pago') - 29, '12:00', 'Pacific/Pago_Pago'));

  insert into public.uso_ia (restaurante_id, mes, anuncios, costo_anuncios_usd)
  values (a, date_trunc('month', hoy)::date, 7, 0.5500);
end;
$$;

select plan(72);


-- ─── Quién llama a qué ────────────────────────────────────────────────────────

select is(
  array(
    select f from unnest(array['public.mi_biblioteca(uuid)', 'public.puedo_borrar_anuncio(bigint)']) f
    where not has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('service_role', f, 'execute')
  ),
  '{}'::text[],
  'Las dos de Don Chuy, solo con sesión'
);

select is(
  array(
    select f from unnest(array['public.borrar_anuncio(bigint,text)', 'public.anuncios_vencidos()',
                               'public.borrar_vencidos(bigint[])']) f
    where not has_function_privilege('service_role', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('authenticated', f, 'execute')
  ),
  '{}'::text[],
  'Las que borran, solo con la llave secreta'
);

select ok(
  not (has_table_privilege('anon', 'public.anuncios', 'delete')
       or has_table_privilege('authenticated', 'public.anuncios', 'delete')
       or has_table_privilege('service_role', 'public.anuncios', 'delete')),
  'Nadie borra la tabla directo: solo con sus funciones'
);


-- ─── Mi biblioteca: lo que ve Don Chuy ────────────────────────────────────────

select tests.authenticate_as('don_chuy');

select is(
  public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'hoy',
  to_jsonb(tests.hoy()),
  'Trae hoy en el calendario del restaurante, para «HOY» y «AYER»'
);

select is(
  tests.lista(public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios'),
  tests.ids_de(array['haciendo_a', 'de_hoy_tarde', 'de_hoy', 'de_ayer', 'viejo']),
  'Primero el que se está haciendo; luego del más nuevo al más viejo por la hora en que terminó, de los dos gerentes; sin los que no salieron ni el que ya venció'
);

select is(
  public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios' -> 0,
  jsonb_build_object('id', tests.id('haciendo_a'), 'estado', 'haciendo', 'formato', 'cartel', 'estilo', 'Banderitas',
                     'productos', '["Gringa", "Jamaica"]'::jsonb, 'segundos', 90),
  'El que se está haciendo, de Rosa: su formato, su estilo, sus productos y los segundos que lleva, de Postgres'
);

select is(
  public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios' -> 1,
  jsonb_build_object('id', tests.id('de_hoy_tarde'), 'estado', 'listo', 'formato', 'post', 'estilo', 'Clásico',
                     'productos', '["Gringa", "Torta", "Jamaica"]'::jsonb,
                     'ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'de_hoy_tarde'),
                     'dia', tests.hoy(), 'hora', '15:26', 'dias_restantes', 29),
  'Uno listo: su formato, su estilo, sus productos en su orden, su archivo, su día, su hora y 29 días, aunque lo hizo Rosa'
);

select is(
  public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios' -> 2 ->> 'hora',
  '09:05',
  'La hora como en Flet: 09:05'
);

select is(
  (public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios' -> 3) - 'id' - 'ruta' - 'productos',
  jsonb_build_object('estado', 'listo', 'formato', 'historia', 'estilo', 'Banderitas', 'dia', tests.hoy() - 1,
                     'hora', '21:40', 'dias_restantes', 28),
  'El de ayer cae en AYER: su día es el que terminó, y le quedan 28'
);

select is(
  (public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios' -> 4) - 'id' - 'ruta' - 'productos'
    - 'estado' - 'formato' - 'estilo' - 'hora',
  jsonb_build_object('dia', tests.hoy() - 29, 'dias_restantes', 0),
  'El que terminó hace 29 días sigue: es su último día, «Se borra hoy»'
);

select ok(
  (select bool_and((x ->> 'dia')::date + 29 = (tests.anuncio((x ->> 'id')::bigint)).vence
                   and (x ->> 'dias_restantes')::integer = (tests.anuncio((x ->> 'id')::bigint)).vence - tests.hoy())
   from jsonb_array_elements(public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios') x
   where x ->> 'estado' = 'listo'),
  'Su día y «Se borra en…» salen del mismo número: su día de vencer'
);

select tests.authenticate_as('rosa');
select is(
  tests.lista(public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios'),
  tests.ids_de(array['haciendo_a', 'de_hoy_tarde', 'de_hoy', 'de_ayer', 'viejo']),
  'Rosa ve los mismos: todos los de la sucursal (encuesta 1)'
);

-- Fragmentless le cambia el nombre a un estilo.
reset role;
update public.estilos set nombre = 'Banderitas de fiesta' where clave = 'banderitas';
select tests.authenticate_as('don_chuy');
select is(
  array(select x ->> 'estilo'
        from jsonb_array_elements(public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios') x
        where (x ->> 'id')::bigint in (tests.id('haciendo_a'), tests.id('de_hoy'))),
  array['Banderitas de fiesta', 'Banderitas de fiesta'],
  'El nombre de su estilo es el de hoy'
);
reset role;
update public.estilos set nombre = 'Banderitas' where clave = 'banderitas';


-- ─── Quién la lee ─────────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_b');
select is(
  tests.lista(public.mi_biblioteca('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'anuncios'),
  tests.ids_de(array['haciendo_b', 'de_b']),
  'Cada sucursal tiene su biblioteca'
);
select throws_ok(
  $$ select public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante ve su biblioteca',
  'El gerente de otro restaurante no ve la de La Fonda'
);

select tests.authenticate_as('gerente_c');
select throws_ok(
  $$ select public.mi_biblioteca('cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  '42501', 'Solo el gerente de este restaurante ve su biblioteca',
  'Con la licencia vencida no se ve'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante ve su biblioteca',
  'Pepe, el mesero, no la ve ni desde su aparato'
);

select tests.clear_authentication();
select throws_ok(
  $$ select public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null,
  'Sin sesión, nada'
);

select tests.authenticate_as('don_chuy');
select throws_ok(
  $$ select public.mi_biblioteca(null) $$,
  '42501', 'Solo el gerente de este restaurante ve su biblioteca',
  'Sin restaurante, nada'
);


-- ─── El calendario de cada restaurante ────────────────────────────────────────

select tests.authenticate_as('gerente_k');
select is(
  (public.mi_biblioteca('dddddddd-dddd-4ddd-8ddd-dddddddddddd') ->> 'hoy')::date,
  tests.hoy('Pacific/Kiritimati'),
  'En Kiritimati, hoy es el de su calendario'
);
select is(
  tests.lista(public.mi_biblioteca('dddddddd-dddd-4ddd-8ddd-dddddddddddd') -> 'anuncios'),
  tests.ids_de(array['de_k']),
  'Y el que su último día fue ayer en su calendario ya no sale'
);
select is(
  (public.mi_biblioteca('dddddddd-dddd-4ddd-8ddd-dddddddddddd') -> 'anuncios' -> 0) - 'id' - 'ruta' - 'productos'
    - 'estado' - 'formato' - 'estilo',
  jsonb_build_object('dia', tests.hoy('Pacific/Kiritimati'), 'hora', '07:15', 'dias_restantes', 29),
  'Su día y su hora, en su hora'
);

select tests.authenticate_as('gerente_p');
select is(
  (public.mi_biblioteca('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee') ->> 'hoy')::date,
  tests.hoy('Pacific/Pago_Pago'),
  'En Pago Pago, el suyo'
);
select is(
  (public.mi_biblioteca('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee') -> 'anuncios' -> 0) - 'id' - 'ruta' - 'productos'
    - 'estado' - 'formato' - 'estilo' - 'hora' - 'dia',
  '{"dias_restantes": 0}'::jsonb,
  'Y el que hoy es su último día ahí, sigue'
);


-- ─── Eliminar: puedo_borrar_anuncio ───────────────────────────────────────────

select tests.authenticate_as('don_chuy');
select is(
  public.puedo_borrar_anuncio(tests.id('de_hoy_tarde')),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'de_hoy_tarde'),
  'Don Chuy puede borrar el que hizo Rosa: regresa su archivo para el Worker'
);
select throws_ok(
  format('select public.puedo_borrar_anuncio(%s)', tests.id('haciendo_a')),
  '22023', 'Tu anuncio todavía se está haciendo.',
  'Uno que se está haciendo no se borra'
);
select is(public.puedo_borrar_anuncio(tests.id('no_salio_a')), null, 'Uno que no salió no está en su biblioteca: null');
select is(public.puedo_borrar_anuncio(tests.id('de_b')), null, 'Uno de otro restaurante: null');
select is(
  public.puedo_borrar_anuncio(tests.id('haciendo_b')),
  null,
  'Aunque se esté haciendo allá: primero se ve que no es suyo'
);
select is(public.puedo_borrar_anuncio(999999), null, 'Uno que ya no existe: null, y la app lo quita');

select tests.authenticate_as('rosa');
select is(
  public.puedo_borrar_anuncio(tests.id('de_hoy')),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'de_hoy'),
  'Rosa puede borrar el de Don Chuy'
);

select tests.authenticate_as('gerente_b');
select is(public.puedo_borrar_anuncio(tests.id('de_hoy')), null, 'El gerente de otro restaurante, no');

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is(public.puedo_borrar_anuncio(tests.id('de_hoy')), null, 'Pepe, tampoco');

select tests.authenticate_as('gerente_c');
select is(public.puedo_borrar_anuncio(tests.id('de_c')), null, 'Con la licencia vencida, tampoco');


-- ─── Eliminar: borrar_anuncio, después de R2 ──────────────────────────────────

select tests.como_worker();
select is(
  public.borrar_anuncio(tests.id('de_hoy'), tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'de_hoy_tarde')),
  false,
  'Con otro archivo no se borra'
);
select is(public.borrar_anuncio(tests.id('de_hoy'), null), false, 'Ni sin archivo');
select is(tests.quedan(array['de_hoy']), 1, 'El anuncio sigue');
select is(
  public.borrar_anuncio(tests.id('de_hoy'), tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'de_hoy')),
  true,
  'R2 ya borró su archivo: se borra su renglón'
);
select is(tests.quedan(array['de_hoy']), 0, 'Y ya no está');
select is(
  public.borrar_anuncio(tests.id('de_hoy'), tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'de_hoy')),
  false,
  'Al reintentar, no pasa nada'
);
select is(public.borrar_anuncio(tests.id('no_salio_a'), null), false, 'Uno que no salió no se borra por aquí');
select is(public.borrar_anuncio(tests.id('haciendo_a'), null), false, 'Ni uno que se está haciendo');
select is(tests.quedan(array['no_salio_a', 'haciendo_a']), 2, 'Los dos siguen');

select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd],
  array[7, 0.5500]::numeric[],
  'Borrar no toca uso_ia: sigue contando en sus 20 y su costo se queda'
);

select tests.authenticate_as('don_chuy');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan',
  '12',
  'No le regresa a sus 20 del mes: 7 hechos y uno haciéndose, Te quedan 12'
);
select is(
  tests.lista(public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios'),
  tests.ids_de(array['haciendo_a', 'de_hoy_tarde', 'de_ayer', 'viejo']),
  'Ya no sale en su biblioteca'
);

select tests.authenticate_as('rosa');
select is(public.puedo_borrar_anuncio(tests.id('de_hoy')), null, 'Si Rosa lo intenta después, null: ya quedó borrado');


-- ─── Uno atorado ──────────────────────────────────────────────────────────────

reset role;
update public.anuncios set created_at = now() - interval '15 minutes' where id = tests.id('haciendo_a');
select tests.authenticate_as('don_chuy');
select is(
  tests.lista(public.mi_biblioteca('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'anuncios'),
  tests.ids_de(array['de_hoy_tarde', 'de_ayer', 'viejo']),
  'A los 15 minutos, la biblioteca lo suelta antes de leer: ya no sale'
);
select ok(
  (tests.anuncio(tests.id('haciendo_a'))).estado = 'fallo'
  and (tests.anuncio(tests.id('haciendo_a'))).motivo = 'no_salio'
  and (tests.anuncio(tests.id('haciendo_a'))).vence = tests.hoy() + 29,
  'Cuenta como que no salió, con sus 30 días'
);


-- ─── El borrado de los 30 días ────────────────────────────────────────────────

-- El Restaurante B se pausa, y su anuncio que se estaba haciendo se atora sin que nadie lo mire.
reset role;
update public.restaurantes set licencia_activa = false where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
update public.anuncios set created_at = now() - interval '16 minutes' where id = tests.id('haciendo_b');

select tests.authenticate_as('fragmentless');
select throws_ok(
  format('select public.eliminar_estilo(%s)', tests.e('cuadros')),
  '55000', 'Este estilo ya se usó: apágalo.',
  'Cuadros todavía tiene anuncios: no se borra'
);

select tests.como_worker();
select is(
  tests.lista(public.anuncios_vencidos()),
  tests.del_mas_viejo(array['vencido_a', 'no_salio_viejo', 'vencido_b', 'vencido_c', 'vencido_k']),
  'Los vencidos, los más viejos primero: los listos y los que no salieron, también del pausado y del de la licencia vencida, cada uno con su calendario'
);
select is(
  tests.lista(public.anuncios_vencidos()),
  tests.ids_de(array['vencido_c', 'no_salio_viejo', 'vencido_b'])
    || tests.del_mas_viejo(array['vencido_a', 'vencido_k']),
  'Del más viejo al más nuevo por su día de vencer, no por cuándo se sembraron'
);
select ok(
  (tests.anuncio(tests.id('haciendo_b'))).estado = 'fallo'
  and (tests.anuncio(tests.id('haciendo_b'))).motivo = 'no_salio'
  and (tests.anuncio(tests.id('haciendo_b'))).vence = tests.hoy() + 29,
  'Primero soltó el atorado del Restaurante B, aunque nadie lo miró; queda con sus 30 días, no vencido'
);
select is(
  (select x from jsonb_array_elements(public.anuncios_vencidos()) x where (x ->> 'id')::bigint = tests.id('vencido_c')),
  jsonb_build_object('id', tests.id('vencido_c'), 'ruta', tests.ruta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'vencido_c')),
  'Cada uno con su id y su archivo, para borrarlo de R2'
);
select is(
  (select x from jsonb_array_elements(public.anuncios_vencidos()) x where (x ->> 'id')::bigint = tests.id('no_salio_viejo')),
  jsonb_build_object('id', tests.id('no_salio_viejo'), 'ruta', null),
  'Uno que no salió, sin archivo'
);

select is(
  public.borrar_vencidos(tests.ids_de(array['vencido_a', 'no_salio_viejo', 'vencido_b', 'vencido_c', 'vencido_k',
                                            'viejo', 'de_hoy_tarde', 'ultimo_p', 'no_salio_a', 'haciendo_b'])),
  5,
  'R2 ya borró sus archivos: borra los 5 vencidos'
);
select is(
  tests.quedan(array['vencido_a', 'no_salio_viejo', 'vencido_b', 'vencido_c', 'vencido_k']),
  0,
  'Ya no están'
);
select is(
  tests.quedan(array['viejo', 'de_hoy_tarde', 'ultimo_p', 'no_salio_a', 'haciendo_b']),
  5,
  'Uno que no está vencido se queda, aunque venga en la lista: tampoco el que hoy es su último día'
);
select is(public.anuncios_vencidos(), '[]'::jsonb, 'Ya no queda ninguno vencido');
select is(public.borrar_vencidos(null), 0, 'Sin ids, no borra nada');
select is(public.borrar_vencidos('{}'), 0, 'Con la lista vacía, tampoco');
select is(public.borrar_vencidos(tests.ids_de(array['vencido_a'])), 0, 'Repetido, no pasa nada');

select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd],
  array[7, 0.5500]::numeric[],
  'El borrado de los 30 días tampoco toca uso_ia'
);

select tests.authenticate_as('fragmentless');
select lives_ok(
  format('select public.eliminar_estilo(%s)', tests.e('cuadros')),
  'Ya sin anuncios, Cuadros se puede borrar: la llave foránea no cambia'
);
select is(tests.e('cuadros'), null, 'Y ya no está');


-- ─── Hasta 1,000 por día ──────────────────────────────────────────────────────

reset role;
insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, ruta, terminado_at, vence)
select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.e('clasico'), 'post', '[{"id": 521, "nombre": "Taco C"}]',
       tests.miembro('Gerente C'), 'listo', tests.ruta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'lote ' || g),
       now() - (129 + g) * interval '1 day', tests.hoy() - 100 - g
from generate_series(1, 1001) g;

select tests.como_worker();
select is(jsonb_array_length(public.anuncios_vencidos()), 1000, 'Con 1,001 vencidos, regresa 1,000');
select is(
  public.anuncios_vencidos() -> 0 ->> 'ruta',
  tests.ruta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'lote 1001'),
  'Empieza por el más viejo'
);
select ok(
  not exists (select 1 from jsonb_array_elements(public.anuncios_vencidos()) x
              where x ->> 'ruta' = tests.ruta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'lote 1')),
  'Y el más nuevo se queda para el otro día'
);
select is(
  public.borrar_vencidos(tests.lista(public.anuncios_vencidos())),
  1000,
  'Borra esos 1,000'
);
select is(
  public.anuncios_vencidos() -> 0 ->> 'ruta',
  tests.ruta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'lote 1'),
  'Al otro día sale el que faltaba'
);
select is(jsonb_array_length(public.anuncios_vencidos()), 1, 'Solo él');
select is(public.borrar_vencidos(tests.lista(public.anuncios_vencidos())), 1, 'Y se borra');

select * from finish();
rollback;
