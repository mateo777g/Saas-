-- Pruebas del asistente del menú, parte 6c (migración asistente_menu): lo decidido el 26 de octubre
-- de 2026 en las respuestas de la 6c, el Diccionario (rev 104) y la maqueta. El sobre del menú es la
-- quinta parte del tope y el agente del panel tiene lo demás; cada uno se pausa solo al gastar lo
-- suyo. preguntar_al_asistente solo lo llama el Worker: revisa el sobre y los límites (20 por hora
-- desde cada celular y 60 desde cada conexión, a cada restaurante), cuenta la pregunta y da el menú
-- que ve la clienta. El costo va a uso_ia. El menú solo sabe si el asistente contesta; Don Chuy, si
-- contesta y por qué no; Fragmentless ve cada sobre en «Tope de IA».
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


create table tests.ids (nombre text primary key, id bigint not null);
grant select on tests.ids to anon, authenticated;

-- Guarda un id con nombre, para usarlo en pruebas que corren con otra sesión.
create function tests.guardar(p_nombre text, p_id bigint)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into tests.ids (nombre, id) values (p_nombre, p_id)
  on conflict (nombre) do update set id = excluded.id
  returning id;
$$;

create function tests.id(p_nombre text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from tests.ids where nombre = p_nombre;
$$;

grant execute on function tests.guardar(text, bigint), tests.id(text) to anon, authenticated;
-- El Worker llama a hacer_pedido como service_role, con la llave secreta.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, con ids fijos. A es la fonda de Don Chuy, cliente directo con tope de
-- 10 dólares; B nació con tope 0 y es cliente de Juanito; C tiene tope pero la licencia pausada;
-- E tiene un tope de 7.77, para ver el redondeo. Fragmentless pone los topes.

-- Una pregunta como la manda el Worker, cada vez desde un celular y una conexión nuevos, salvo
-- que se digan.
create function tests.preguntar(
  p_slug text,
  p_celular text default encode(extensions.gen_random_bytes(32), 'hex'),
  p_conexion text default encode(extensions.gen_random_bytes(32), 'hex')
)
returns jsonb
language sql
as $$
  select public.preguntar_al_asistente(p_slug, p_celular, p_conexion)
$$;

-- El menú que ve ella, para compararlo con lo que recibe el Worker (que no llama a menu_publico).
create function tests.menu_de(p_slug text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.menu_publico(p_slug)
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Como en producción, la sesión corre en UTC: así una hora sin zona se notaría.
set local time zone 'UTC';

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  e uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));
  insert into public.distribuidores (id, nombre) overriding system value values (1, 'Juanito');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, telefono,
                                   distribuidor_id, tope_ia_usd_mes) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, '2221234567', null, 10),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, '2227654321', 1, 0),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30, '2221112222', null, 10),
    (e, 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy + 30, '2223334444', null, 7.77);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true);

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Tacos', 'taco'), (611, b, 'Tacos B', 'taco'), (651, e, 'Tacos E', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, descripcion) overriding system value values
    (501, a, 601, 'Taco al pastor', 22, 'Con piña y cilantro'),
    (502, a, 601, 'Taco oculto', 22, null),
    (511, b, 611, 'Taco B', 25, null),
    (551, e, 651, 'Taco E', 25, null);
  update public.productos set visible = false where id = 502;
end;
$$;

select plan(60);


-- ─── Estructura y permisos ────────────────────────────────────────────────────

select ok(
  (select relrowsecurity from pg_class where oid = 'public.preguntas_menu'::regclass),
  'preguntas_menu tiene RLS'
);

select ok(
  not has_any_column_privilege('anon', 'public.preguntas_menu', 'SELECT, INSERT, UPDATE')
  and not has_any_column_privilege('authenticated', 'public.preguntas_menu', 'SELECT, INSERT, UPDATE')
  and not has_any_column_privilege('service_role', 'public.preguntas_menu', 'SELECT, INSERT, UPDATE')
  and not has_table_privilege('authenticated', 'public.preguntas_menu', 'DELETE')
  and not has_table_privilege('service_role', 'public.preguntas_menu', 'DELETE'),
  'Nadie lee ni escribe preguntas_menu directo, ni con sesión, ni sin ella, ni el Worker'
);

select ok(
  not has_any_column_privilege('authenticated', 'public.uso_ia', 'SELECT, INSERT, UPDATE')
  and not has_any_column_privilege('anon', 'public.uso_ia', 'SELECT, INSERT, UPDATE')
  and not has_column_privilege('service_role', 'public.uso_ia', 'costo_menu_usd', 'SELECT'),
  'uso_ia sigue sin leerse directo, también lo del menú'
);

select ok(
  has_function_privilege('service_role', 'public.preguntar_al_asistente(text, text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.preguntar_al_asistente(text, text, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.preguntar_al_asistente(text, text, text)', 'EXECUTE'),
  'preguntar_al_asistente solo lo llama el Worker, con la llave secreta: ni el menú sin sesión ni alguien con sesión'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.parte_del_tope(numeric, text)',
       'privado.saldo_ia(uuid, text)',
       'privado.borrar_preguntas_viejas()'
     ]) as f
     where has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Lo que se cuenta una sola vez no lo llama nadie de fuera'
);

select ok(
  to_regprocedure('privado.saldo_agente(uuid)') is null,
  'privado.saldo_agente ya no existe: los dos sobres se cuentan con privado.saldo_ia'
);

select is(
  (select schedule || ' · ' || command from cron.job where jobname = 'borrar-preguntas-del-menu'),
  '0 * * * * · select privado.borrar_preguntas_viejas()',
  'pg_cron borra las preguntas viejas cada hora en punto'
);

select is(
  (select schedule from cron.job where jobname = 'rechazar-pedidos-sin-confirmar'),
  '0 * * * *',
  '… y el cierre de los pedidos sigue igual'
);

select ok(
  not exists (select 1 from pg_publication_tables where tablename = 'preguntas_menu'),
  'Las preguntas no van por el tiempo real'
);


-- ─── El reparto del tope ──────────────────────────────────────────────────────

select is(
  array[privado.parte_del_tope(10, 'menu'), privado.parte_del_tope(10, 'agente'),
        privado.parte_del_tope(5, 'menu'), privado.parte_del_tope(5, 'agente'),
        privado.parte_del_tope(7.77, 'menu'), privado.parte_del_tope(7.77, 'agente')],
  array[2.00, 8.00, 1.00, 4.00, 1.55, 6.22]::numeric[],
  'El menú tiene la quinta parte del tope y el agente lo demás: con 10, 2 y 8; con 5, 1 y 4; con 7.77, 1.55 y 6.22'
);

select is(
  array[privado.parte_del_tope(0, 'menu'), privado.parte_del_tope(0, 'agente'),
        privado.parte_del_tope(0.01, 'menu'), privado.parte_del_tope(0.01, 'agente')],
  array[0, 0, 0, 0.01]::numeric[],
  'Con tope 0 los dos valen 0; con 1 centavo, el centavo es del agente'
);

select ok(
  (select bool_and(privado.parte_del_tope(t / 100.0, 'menu') + privado.parte_del_tope(t / 100.0, 'agente') = t / 100.0)
   from generate_series(0, 1000) as t),
  'Con cualquier tope de 0 a 10 dólares, las dos partes suman el tope exacto'
);


-- ─── El menú que ve la clienta ────────────────────────────────────────────────

select tests.clear_authentication();

select is(
  array[(public.menu_publico('fonda-don-chuy') ->> 'asistente_contesta')::boolean,
        (public.menu_publico('restaurante-b') ->> 'asistente_contesta')::boolean],
  array[true, false],
  'El menú de Don Chuy dice que el asistente contesta; el de B, con tope 0, que no'
);

select is(
  jsonb_typeof(public.menu_publico('fonda-don-chuy') -> 'asistente_contesta'),
  'boolean',
  'Solo dice sí o no: ningún número del gasto llega al menú'
);


-- ─── La pregunta ──────────────────────────────────────────────────────────────

select tests.como_worker();

select is(
  tests.preguntar('fonda-don-chuy'),
  jsonb_build_object('ok', true, 'restaurante_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                     'menu', tests.menu_de('fonda-don-chuy')),
  'Se puede: Postgres le da al Worker el restaurante y el mismo menú que ve la señora Ramírez'
);

select is(
  tests.preguntar('  Fonda-Don-Chuy ') ->> 'ok',
  'true',
  'El slug se busca sin espacios ni mayúsculas, como en el menú'
);

select is(
  array[tests.preguntar('restaurante-b'), tests.preguntar('restaurante-c'), tests.preguntar('no-existe')],
  array['{"ok": false, "motivo": "sin_ia"}', '{"ok": false, "motivo": "sin_ia"}', '{"ok": false, "motivo": "sin_ia"}']::jsonb[],
  'Con tope 0, con la licencia pausada o con un slug que no existe: sin IA'
);

select throws_ok(
  $$ select tests.preguntar('fonda-don-chuy', 'abc') $$,
  '22023', 'Faltan las marcas de la pregunta',
  'Sin las marcas del celular y de la conexión no se pregunta'
);

select throws_ok(
  $$ select tests.preguntar('fonda-don-chuy', repeat('a', 64), null) $$,
  '22023', 'Faltan las marcas de la pregunta',
  'Ni sin la de la conexión'
);

reset role;

select is(
  (select array[count(*) filter (where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
                count(*) filter (where restaurante_id <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')]
   from public.preguntas_menu),
  array[2, 0]::bigint[],
  'Cada pregunta que se pudo cuenta una fila; sin IA no cuenta'
);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'preguntas_menu'
      and column_name not in ('id', 'restaurante_id', 'marca_celular', 'marca_conexion', 'created_at')),
  'preguntas_menu no tiene dónde guardar la pregunta, la respuesta ni la conexión'
);


-- ─── Los límites ──────────────────────────────────────────────────────────────

select tests.como_worker();

select is(
  (select count(*) from generate_series(1, 20) as g
   where (tests.preguntar('fonda-don-chuy', repeat('a', 64)) ->> 'ok')::boolean),
  20::bigint,
  'Desde un celular se hacen 20 preguntas en una hora, cada una desde otra conexión'
);

select is(
  tests.preguntar('fonda-don-chuy', repeat('a', 64)),
  '{"ok": false, "motivo": "limite_celular"}'::jsonb,
  'La 21 desde ese celular no: el menú pone el aviso'
);

select is(
  tests.preguntar('restaurante-e', repeat('a', 64)) ->> 'ok',
  'true',
  'Ese mismo celular sí le pregunta a otro restaurante: el límite es de cada uno'
);

select is(
  (select count(*) from generate_series(1, 60) as g
   where (tests.preguntar('fonda-don-chuy', p_conexion => repeat('b', 64)) ->> 'ok')::boolean),
  60::bigint,
  'Desde una conexión se hacen 60 preguntas en una hora, cada una desde otro celular'
);

select is(
  tests.preguntar('fonda-don-chuy', p_conexion => repeat('b', 64)),
  '{"ok": false, "motivo": "limite_conexion"}'::jsonb,
  'La 61 desde esa conexión no'
);

select is(
  tests.preguntar('fonda-don-chuy', repeat('a', 64), repeat('b', 64)),
  '{"ok": false, "motivo": "limite_celular"}'::jsonb,
  'Con los dos límites pasados, el aviso es el del celular'
);

reset role;

select is(
  (select count(*) from public.preguntas_menu
   where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and marca_celular = repeat('a', 64)),
  20::bigint,
  'Lo que el límite frenó no cuenta'
);

-- Las 20 del celular pasan a tener una hora exacta: ya no cuentan.
update public.preguntas_menu set created_at = now() - interval '1 hour'
where marca_celular = repeat('a', 64) and restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.como_worker();
select is(
  tests.preguntar('fonda-don-chuy', repeat('a', 64)) ->> 'ok',
  'true',
  'Una pregunta de hace una hora exacta ya no cuenta: el celular vuelve a preguntar'
);
reset role;

-- Una de hace 59 minutos sí cuenta.
update public.preguntas_menu set created_at = now() - interval '59 minutes'
where marca_conexion = repeat('b', 64);
select tests.como_worker();
select is(
  tests.preguntar('fonda-don-chuy', p_conexion => repeat('b', 64)) ->> 'motivo',
  'limite_conexion',
  'Las de hace 59 minutos todavía cuentan'
);
reset role;

select is(
  privado.borrar_preguntas_viejas(),
  20,
  'La limpieza de cada hora borra las que tienen una hora o más'
);

select is(
  (select count(*) from public.preguntas_menu where created_at <= now() - interval '1 hour'),
  0::bigint,
  '… y no queda ninguna vieja'
);

select is(
  (select count(*) from public.preguntas_menu where marca_conexion = repeat('b', 64)),
  60::bigint,
  '… y deja las de la última hora'
);


-- ─── El gasto del menú ────────────────────────────────────────────────────────

select tests.como_worker();

select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 'gpt-5.6-luna', 10000, 8000, 0, 300),
  '{"costo": 0.0009, "puede": true}'::jsonb,
  'Una pregunta del menú: 2,000 de entrada a $0.20, 8,000 de caché a $0.02 y 300 de salida a $1.20 por millón'
);

select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu_sin_respuesta', 'gpt-5.6-luna', 10000, 8000, 0, 300),
  '{"costo": 0.0009, "puede": true}'::jsonb,
  'Si OpenAI cobró y no mandó qué enseñar, también se anota su costo'
);

select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pregunta', 'gpt-6.1-sol', 10000, 4000, 2000, 640),
  '{"costo": 0.0198, "puede": true}'::jsonb,
  'Una pregunta del agente se anota igual que antes'
);

select throws_ok(
  $$ select public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'flyer', 'gpt-6.1-sol', 100, 0, 0, 10) $$,
  '22023', 'El uso de IA es pregunta, saludo, menu o menu_sin_respuesta',
  'Los flyers todavía no existen'
);

reset role;

select is(
  (select jsonb_build_object('consultas_menu', consultas_menu, 'menu', costo_menu_usd,
                             'consultas_agente', consultas_agente, 'agente', costo_agente_usd, 'total', costo_usd)
   from public.uso_ia where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"consultas_menu": 1, "menu": 0.0018, "consultas_agente": 1, "agente": 0.0198, "total": 0.0216}'::jsonb,
  'Cada costo va a su sobre; consultas_menu cuenta solo la que contestó, y costo_usd suma los sobres'
);

select is(
  (select costo_usd from public.uso_ia where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
   and costo_usd = costo_agente_usd + costo_anuncios_usd + costo_menu_usd),
  0.0216,
  'costo_usd es la suma de costo_agente_usd, costo_anuncios_usd y costo_menu_usd'
);


-- ─── Cada sobre se pausa solo ─────────────────────────────────────────────────

-- Un bot se come el sobre del menú de Don Chuy: llega a sus 2 dólares.
update public.uso_ia set costo_menu_usd = 1.9995 where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 'gpt-5.6-luna', 10000, 8000, 0, 300),
  '{"costo": 0.0009, "puede": false}'::jsonb,
  'Con la pregunta que pasa de $2.00, el menú ya no puede: solo la última se pasa por centavos'
);
select is(
  tests.preguntar('fonda-don-chuy'),
  '{"ok": false, "motivo": "sin_ia"}'::jsonb,
  'La siguiente pregunta ya no pasa, y no cuenta para el límite'
);
reset role;

select is(
  (public.menu_publico('fonda-don-chuy') ->> 'asistente_contesta')::boolean,
  false,
  'El menú dice que el asistente ya no contesta'
);

select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true}'::jsonb,
  'Pero Don Chuy sigue preguntándole a su agente: el bot solo pausó el asistente del menú'
);
select is(
  public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'asistente',
  jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', false,
                     'vuelve', (date_trunc('month', (now() at time zone 'America/Mexico_City')::date) + interval '1 month')::date),
  'Tu menú en línea le avisa a Don Chuy que su asistente llegó a su límite, sin distribuidor, y cuándo vuelve'
);
reset role;

-- Y al revés: el agente gasta sus 8 dólares y el menú tiene otra vez con qué contestar.
update public.uso_ia set costo_agente_usd = 7.9999, costo_menu_usd = 1.99
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"puede": true}'::jsonb,
  'Con $7.9999 de sus 8, el agente todavía puede'
);
reset role;

update public.uso_ia set costo_agente_usd = 8 where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.authenticate_as('gerente_a');
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'motivo',
  'limite',
  'Con sus 8 gastados, el agente se pausa aunque el tope sea de 10: ya no gasta el tope completo'
);
select is(
  public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'asistente',
  '{"puede": true}'::jsonb,
  'Y el asistente del menú sigue contestando'
);
reset role;

select is(
  (public.menu_publico('fonda-don-chuy') ->> 'asistente_contesta')::boolean,
  true,
  'El menú dice otra vez que contesta'
);


-- ─── El tope cambia ───────────────────────────────────────────────────────────

select tests.authenticate_as('fragmentless');
select lives_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 5) $$,
  'Fragmentless baja el tope de Don Chuy a 5'
);
reset role;
select is(
  (public.menu_publico('fonda-don-chuy') ->> 'asistente_contesta')::boolean,
  false,
  'Su menú tiene ahora $1.00 y ya gastó $1.99: deja de contestar en ese momento'
);

select tests.authenticate_as('fragmentless');
select is(
  public.uso_ia_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'mes',
  '{"tope": 5.00, "gastado": 9.99, "sobre_agente": 4.00, "gastado_agente": 8.0000, "consultas_agente": 1,
    "saludos": 0, "agente_en_limite": true, "sobre_menu": 1.00, "gastado_menu": 1.9900, "consultas_menu": 2,
    "menu_en_limite": true, "distribuidor_id": null, "distribuidor": null}'::jsonb,
  'La ventana «Tope de IA» trae cada sobre en su renglón: su parte, lo gastado, cuántas preguntas y si llegó a lo suyo'
);
select is(
  public.uso_ia_cliente('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee') - 'mes' - 'distribuidor_id' - 'distribuidor',
  '{"tope": 7.77, "gastado": 0, "sobre_agente": 6.22, "gastado_agente": 0, "consultas_agente": 0, "saludos": 0,
    "agente_en_limite": false, "sobre_menu": 1.55, "gastado_menu": 0, "consultas_menu": 0,
    "menu_en_limite": false}'::jsonb,
  'Con 7.77, 6.22 para el agente y 1.55 para el menú, ya calculados'
);
select is(
  public.uso_ia_cliente('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') ->> 'menu_en_limite',
  'false',
  'Con tope 0 ningún sobre «llegó a lo suyo»: la ventana dice que nació en 0'
);
select lives_ok(
  $$ select public.fijar_tope_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10) $$,
  'Fragmentless se lo vuelve a subir a 10'
);
reset role;
select is(
  (public.menu_publico('fonda-don-chuy') ->> 'asistente_contesta')::boolean,
  true,
  '… y el asistente contesta otra vez en ese momento'
);

-- Con 1 centavo de tope, el menú no tiene parte: es «sin IA», no «llegó a su límite».
select tests.authenticate_as('fragmentless');
select lives_ok(
  $$ select public.fijar_tope_ia('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 0.01) $$,
  'Fragmentless le pone 1 centavo a E'
);
reset role;
select is(
  privado.saldo_ia('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'menu') ->> 'motivo',
  'sin_ia',
  'Un sobre que vale 0 es sin IA'
);


-- ─── Los avisos de Don Chuy ───────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');
select is(
  public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'estado' - 'asistente',
  '{"a_la_vista": 1, "productos": 2}'::jsonb,
  'Lo demás de Tu menú en línea sigue igual'
);
reset role;

select tests.authenticate_as('gerente_b');
select is(
  public.estado_menu_en_linea('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'asistente',
  jsonb_build_object('puede', false, 'motivo', 'sin_ia', 'con_distribuidor', true,
                     'vuelve', (date_trunc('month', (now() at time zone 'America/Mexico_City')::date) + interval '1 month')::date),
  'Con tope 0, el gerente de B ve que su asistente no está activo y que se lo pida a Juanito'
);
select throws_ok(
  $$ select public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null,
  'Y no ve el de Don Chuy'
);
reset role;


select * from finish();
rollback;
