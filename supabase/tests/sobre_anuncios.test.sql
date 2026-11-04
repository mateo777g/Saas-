-- Pruebas de la migración sobre_anuncios (parte 7b-3): el reparto del tope (una quinta parte para el
-- menú, dos para los anuncios y dos para el agente), cuántos anuncios caben, «Te quedan N de M», que
-- cada sobre se pausa por su lado, que cada gasto va al suyo y la ventana «Tope de IA».
--
-- Escenario: Fragmentless, La Fonda de Don Chuy con 10 dólares, y cinco restaurantes más con 5, 2.50,
-- 1, 0.20 y 0.
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

-- Los ayudantes de estas pruebas.

-- El uuid de cada restaurante por su letra: 'a' → aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.
create function tests.r(p text)
returns uuid
language sql
immutable
as $$
  select (repeat(p, 8) || '-' || repeat(p, 4) || '-4' || repeat(p, 3) || '-8' || repeat(p, 3) || '-' || repeat(p, 12))::uuid;
$$;

create function tests.hoy()
returns date
language sql
stable
as $$
  select (now() at time zone 'America/Mexico_City')::date;
$$;

create function tests.mes()
returns date
language sql
stable
as $$
  select date_trunc('month', tests.hoy())::date;
$$;

create function tests.vuelve()
returns date
language sql
stable
as $$
  select (tests.mes() + interval '1 month')::date;
$$;

create function tests.e(p_clave text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.estilos where clave = p_clave;
$$;

-- Lo gastado este mes, como su dueño: nadie con sesión lo escribe.
create function tests.gastos(p_restaurante uuid, p_anuncios integer, p_agente numeric, p_anuncios_usd numeric, p_menu numeric)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.uso_ia (restaurante_id, mes, anuncios, costo_agente_usd, costo_anuncios_usd, costo_menu_usd)
  values (p_restaurante, date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date,
          p_anuncios, p_agente, p_anuncios_usd, p_menu)
  on conflict (restaurante_id, mes) do update
  set anuncios = excluded.anuncios, costo_agente_usd = excluded.costo_agente_usd,
      costo_anuncios_usd = excluded.costo_anuncios_usd, costo_menu_usd = excluded.costo_menu_usd;
$$;

create function tests.uso(p_restaurante uuid)
returns public.uso_ia
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.uso_ia
  where restaurante_id = p_restaurante
    and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
$$;

-- El Worker con la llave secreta.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

create table tests.ids (nombre text primary key, id bigint not null);
grant select, insert on tests.ids to authenticated, service_role;

create function tests.id(p_nombre text)
returns bigint
language sql
stable
as $$
  select id from tests.ids where nombre = p_nombre;
$$;

-- Aparta un Clásico de su único producto con la sesión de quien llama.
create function tests.apartar(p_nombre text, p_restaurante uuid, p_producto bigint)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  v := public.apartar_anuncio(p_restaurante, tests.e('clasico'), 'post', array[p_producto], null, null, true, null);
  if p_nombre is not null and (v ->> 'ok')::boolean then
    insert into tests.ids values (p_nombre, (v ->> 'anuncio_id')::bigint);
  end if;
  return v;
end;
$$;

-- Lo que ve Don Chuy al entrar: «Te quedan N de M» y si la IA puede.
create function tests.contador(p_restaurante uuid)
returns jsonb
language sql
as $$
  select public.crear_contenido(p_restaurante) - 'productos' - 'restaurante' - 'resultado';
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres. La Fonda de Don Chuy tiene el tope de 10 dólares y no tiene distribuidor.
-- El B (de Juanito) tiene 5; el C, 2.50; el D, 1; el E, 0.20, tan chico que no cabe ni un anuncio; y
-- el F (de Juanito), 0. Cada uno tiene su gerente y un producto. El Clásico sale hoy.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  j bigint;
  x record;
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));
  insert into public.distribuidores (nombre, usuario_id) values ('Juanito', tests.get_supabase_uid('juanito'))
  returning id into j;

  for x in
    select * from (values
      ('a', 'La Fonda de Don Chuy', 'don_chuy', 10.00, null::bigint, 501),
      ('b', 'Restaurante B', 'gerente_b', 5.00, j, 502),
      ('c', 'Restaurante C', 'gerente_c', 2.50, null, 503),
      ('d', 'Restaurante D', 'gerente_d', 1.00, null, 504),
      ('e', 'Restaurante E', 'gerente_e', 0.20, null, 505),
      ('f', 'Restaurante F', 'gerente_f', 0.00, j, 506)
    ) as t (letra, nombre, gerente, tope, distribuidor, producto)
  loop
    perform tests.create_supabase_user(x.gerente, x.gerente || '@prueba.test');
    insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, zona_horaria,
                                     distribuidor_id, tope_ia_usd_mes)
    values (tests.r(x.letra), x.nombre, 'restaurante-' || x.letra, true, hoy - 30, hoy + 30, 'America/Mexico_City',
            x.distribuidor, x.tope);
    insert into public.miembros (restaurante_id, usuario_id, nombre, roles)
    values (tests.r(x.letra), tests.get_supabase_uid(x.gerente), x.gerente, '{gerente}');
    insert into public.categorias (id, restaurante_id, nombre, icono, orden) overriding system value
    values (x.producto + 100, tests.r(x.letra), 'Tacos', 'taco', 1);
    insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, orden, visible, es_envio) overriding system value
    values (x.producto, tests.r(x.letra), x.producto + 100, 'Taco al pastor', 25, 1, true, false);
  end loop;

  update public.estilos
  set prendido = true,
      muestra_post_ruta = 'estilos/' || clave || '/' || repeat('a', 32) || '.webp',
      muestra_historia_ruta = 'estilos/' || clave || '/' || repeat('b', 32) || '.webp',
      muestra_cartel_ruta = 'estilos/' || clave || '/' || repeat('c', 32) || '.webp'
  where clave = 'clasico';
end;
$$;

select plan(58);


-- ─── El reparto ───────────────────────────────────────────────────────────────

create function tests.partes(p_tope numeric)
returns numeric[]
language sql
security definer
set search_path = ''
as $$
  select array[privado.parte_del_tope(p_tope, 'menu'), privado.parte_del_tope(p_tope, 'anuncios'),
               privado.parte_del_tope(p_tope, 'agente')];
$$;
grant execute on function tests.partes(numeric) to anon, authenticated, service_role;

select is(tests.partes(10), array[2.00, 4.00, 4.00]::numeric[], 'Con 10 dólares: 2 para el menú, 4 para los anuncios y 4 para el agente');
select is(tests.partes(5), array[1.00, 2.00, 2.00]::numeric[], 'Con 5, en la misma proporción: 1, 2 y 2');
select is(tests.partes(2.50), array[0.50, 1.00, 1.00]::numeric[], 'Con 2.50: 0.50, 1 y 1');
select is(tests.partes(7.77), array[1.55, 3.11, 3.11]::numeric[], 'Con 7.77: 1.55, 3.11 y 3.11, redondeados a centavos');
select is(tests.partes(7.76), array[1.55, 3.10, 3.11]::numeric[], 'Con 7.76: el agente se queda con el centavo que sobra');
select is(tests.partes(0), array[0, 0, 0]::numeric[], 'Con tope 0, los tres valen 0');
select is(tests.partes(0.01), array[0, 0, 0.01]::numeric[], 'Con 1 centavo, el centavo es del agente');

select ok(
  (select bool_and((tests.partes(t / 100.0))[1] + (tests.partes(t / 100.0))[2] + (tests.partes(t / 100.0))[3] = t / 100.0
                   and (tests.partes(t / 100.0))[1] >= 0 and (tests.partes(t / 100.0))[2] >= 0
                   and (tests.partes(t / 100.0))[3] >= 0)
   from generate_series(0, 1000) as t),
  'Con cualquier tope de 0 a 10 dólares, las tres partes suman el tope exacto y ninguna es negativa'
);


-- ─── Cuántos anuncios caben ───────────────────────────────────────────────────

select is(
  array[privado.anuncios_que_caben(10), privado.anuncios_que_caben(5), privado.anuncios_que_caben(2.50),
        privado.anuncios_que_caben(1), privado.anuncios_que_caben(0)],
  array[40, 20, 10, 4, 0],
  'Caben lo de los anuncios entre 0.10: con 10, 40; con 5, 20; con 2.50, 10; con 1, 4; con 0, ninguno'
);
select is(
  array[privado.anuncios_que_caben(7.77), privado.anuncios_que_caben(0.24), privado.anuncios_que_caben(0.23)],
  array[31, 1, 0],
  'Se redondea hacia abajo: con 7.77, 31; con 0.24 cabe 1; con 0.23, ninguno'
);
select is(privado.anuncios_que_caben(20), 40, 'Nunca más de 40, aunque algún día suba el tope');

select ok(
  not has_function_privilege('anon', 'privado.anuncios_que_caben(numeric)', 'execute')
  and not has_function_privilege('authenticated', 'privado.anuncios_que_caben(numeric)', 'execute')
  and not has_function_privilege('service_role', 'privado.anuncios_que_caben(numeric)', 'execute'),
  'Nadie la llama de fuera: solo las funciones de Postgres'
);


-- ─── «Te quedan N de M» ───────────────────────────────────────────────────────

select tests.authenticate_as('don_chuy');
select is(
  tests.contador(tests.r('a')),
  jsonb_build_object('de', 40, 'quedan', 40, 'vuelve', tests.vuelve(), 'ia', jsonb_build_object('puede', true)),
  'Con 10 dólares: Te quedan 40 de 40'
);
select tests.authenticate_as('gerente_b');
select is(tests.contador(tests.r('b')) - 'vuelve' - 'ia', '{"de": 20, "quedan": 20}'::jsonb, 'Con 5: Te quedan 20 de 20');
select tests.authenticate_as('gerente_c');
select is(tests.contador(tests.r('c')) - 'vuelve' - 'ia', '{"de": 10, "quedan": 10}'::jsonb, 'Con 2.50: Te quedan 10 de 10');
select tests.authenticate_as('gerente_d');
select is(tests.contador(tests.r('d')) - 'vuelve' - 'ia', '{"de": 4, "quedan": 4}'::jsonb, 'Con 1: Te quedan 4 de 4');


-- ─── Un tope tan chico que no cabe ni un anuncio ──────────────────────────────

select tests.authenticate_as('gerente_e');
select is(
  tests.contador(tests.r('e')),
  jsonb_build_object('de', 0, 'quedan', 0, 'vuelve', tests.vuelve(),
                     'ia', jsonb_build_object('puede', false, 'motivo', 'sin_ia', 'con_distribuidor', false, 'vuelve', tests.vuelve())),
  'Con 0.20 no cabe ni uno: los anuncios dicen que la IA no está activa'
);
select is(
  tests.apartar(null, tests.r('e'), 505),
  jsonb_build_object('ok', false, 'motivo', 'sin_ia', 'con_distribuidor', false, 'vuelve', tests.vuelve()),
  'Y no aparta'
);
select is(public.estado_ia(tests.r('e')), '{"puede": true}'::jsonb, 'Pero el agente usa lo suyo');
select is(public.estado_menu_en_linea(tests.r('e')) -> 'asistente', '{"puede": true}'::jsonb, 'Y el menú también');

select tests.authenticate_as('gerente_f');
select is(
  tests.contador(tests.r('f')) -> 'ia',
  jsonb_build_object('puede', false, 'motivo', 'sin_ia', 'con_distribuidor', true, 'vuelve', tests.vuelve()),
  'Con tope 0 tampoco hay anuncios, y sabe que tiene distribuidor'
);


-- ─── Cada sobre por su lado ───────────────────────────────────────────────────

-- El agente gastó todo lo suyo: los anuncios y el menú siguen.
reset role;
select tests.gastos(tests.r('a'), 0, 4, 0, 0);
select tests.authenticate_as('don_chuy');
select is(public.estado_ia(tests.r('a')) ->> 'motivo', 'limite', 'El agente llegó a sus 4 dólares');
select is(tests.contador(tests.r('a')) -> 'ia', '{"puede": true}'::jsonb, 'Los anuncios siguen');
select is(
  public.datos_para_anuncio(tests.r('a'), tests.e('clasico'), array[501]::bigint[]) ->> 'ok',
  'true',
  'Y su paso de texto también'
);
select is(public.estado_menu_en_linea(tests.r('a')) -> 'asistente', '{"puede": true}'::jsonb, 'Y el menú también');

-- Los anuncios gastaron casi todo lo suyo.
reset role;
select tests.gastos(tests.r('a'), 0, 0, 3.9999, 0);
select tests.authenticate_as('don_chuy');
select is(tests.contador(tests.r('a')) -> 'ia', '{"puede": true}'::jsonb, 'Con $3.9999 de sus 4, los anuncios todavía pueden');

-- Ya lo gastaron todo: el agente y el menú siguen.
reset role;
select tests.gastos(tests.r('a'), 0, 0, 4, 0);
select tests.authenticate_as('don_chuy');
select is(
  tests.contador(tests.r('a')) -> 'ia',
  jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', false, 'vuelve', tests.vuelve()),
  'Con sus 4 gastados, los anuncios llegaron a su límite, sin distribuidor y con el día en que vuelven'
);
select is(
  tests.apartar(null, tests.r('a'), 501),
  jsonb_build_object('ok', false, 'motivo', 'limite', 'con_distribuidor', false, 'vuelve', tests.vuelve()),
  'Y no aparta'
);
select is(
  public.datos_para_anuncio(tests.r('a'), tests.e('clasico'), array[501]::bigint[]) ->> 'motivo',
  'limite',
  'Ni hace el paso de texto'
);
select is(public.estado_ia(tests.r('a')), '{"puede": true}'::jsonb, 'Pero el agente sigue');
select is(public.estado_menu_en_linea(tests.r('a')) -> 'asistente', '{"puede": true}'::jsonb, 'Y el menú también');

select tests.como_worker();
select is(
  public.anotar_uso_ia(tests.r('a'), 'palabras', 'gpt-5.6-luna', 0, 0, 0, 0) ->> 'puede',
  'false',
  'Al Worker le dice que el sobre de los anuncios ya no puede'
);
select is(
  public.anotar_uso_ia(tests.r('a'), 'pregunta', 'gpt-5.6-luna', 0, 0, 0, 0) ->> 'puede',
  'true',
  'Y que el del agente sí'
);

-- El menú gastó todo lo suyo: los otros dos siguen.
reset role;
select tests.gastos(tests.r('a'), 0, 0, 0, 2);
select tests.authenticate_as('don_chuy');
select is(public.estado_menu_en_linea(tests.r('a')) -> 'asistente' ->> 'motivo', 'limite', 'El menú llegó a sus 2 dólares');
select is(tests.contador(tests.r('a')) -> 'ia', '{"puede": true}'::jsonb, 'Los anuncios siguen');
select is(public.estado_ia(tests.r('a')), '{"puede": true}'::jsonb, 'Y el agente también');

-- Con distribuidor, el mismo aviso le dice a quién pedirle más.
reset role;
select tests.gastos(tests.r('b'), 0, 0, 2, 0);
select tests.authenticate_as('gerente_b');
select is(
  tests.contador(tests.r('b')) -> 'ia',
  jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', true, 'vuelve', tests.vuelve()),
  'Con 5 dólares, los anuncios llegan a su límite con 2'
);

-- Lo del mes pasado no cuenta.
reset role;
select tests.gastos(tests.r('b'), 0, 0, 0, 0);
insert into public.uso_ia (restaurante_id, mes, anuncios, costo_anuncios_usd)
values (tests.r('b'), (tests.mes() - interval '1 month')::date, 20, 2);
select tests.authenticate_as('gerente_b');
select is(
  tests.contador(tests.r('b')) - 'vuelve',
  '{"de": 20, "quedan": 20, "ia": {"puede": true}}'::jsonb,
  'Lo del mes pasado no se acumula: ni lo gastado ni los anuncios'
);


-- ─── Cada gasto va a su sobre ─────────────────────────────────────────────────

reset role;
select tests.gastos(tests.r('a'), 0, 0, 0, 0);
select tests.como_worker();
select public.anotar_uso_ia(tests.r('a'), 'pregunta', 'gpt-5.6-luna', 1000, 0, 0, 500);
select public.anotar_uso_ia(tests.r('a'), 'palabras', 'gpt-5.6-luna', 1000, 0, 0, 500);
select is(
  array[(tests.uso(tests.r('a'))).costo_agente_usd, (tests.uso(tests.r('a'))).costo_anuncios_usd,
        (tests.uso(tests.r('a'))).costo_menu_usd],
  array[0.0008, 0.0008, 0]::numeric[],
  'La pregunta va al agente y el paso de texto, a los anuncios'
);


-- ─── Los que le caben ─────────────────────────────────────────────────────────

reset role;
select tests.gastos(tests.r('a'), 39, 0, 0, 0);
select tests.authenticate_as('don_chuy');
select is(tests.contador(tests.r('a')) ->> 'quedan', '1', 'Con 39 hechos, le queda 1');
select is(tests.apartar('ultimo', tests.r('a'), 501) - 'anuncio_id', '{"ok": true}'::jsonb, 'Hace el último');
select is(tests.contador(tests.r('a')) ->> 'quedan', '0', 'Mientras se hace, le quedan 0');

select tests.como_worker();
select is(
  public.terminar_anuncio(tests.id('ultimo'), 'restaurantes/' || tests.r('a') || '/biblioteca/' || repeat('a', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 0, 0, 0) ->> 'ok',
  'true',
  'Sale'
);

select tests.authenticate_as('don_chuy');
select is(
  tests.apartar(null, tests.r('a'), 501),
  jsonb_build_object('ok', false, 'motivo', 'cupo', 'vuelve', tests.vuelve()),
  'Con los 40 hechos ya no aparta: «Ya hiciste tus 40 anuncios de este mes.»'
);
select is(
  tests.contador(tests.r('a')) - 'vuelve',
  '{"de": 40, "quedan": 0, "ia": {"puede": true}}'::jsonb,
  'Le quedan 0 de 40, con dinero en su sobre'
);

-- Las dos cosas a la vez: la lectura trae las dos, y la app enseña la de los 40.
reset role;
select tests.gastos(tests.r('a'), 40, 0, 4, 0);
select tests.authenticate_as('don_chuy');
select is(
  tests.contador(tests.r('a')) - 'vuelve',
  jsonb_build_object('de', 40, 'quedan', 0,
                     'ia', jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', false, 'vuelve', tests.vuelve())),
  'Con los 40 hechos y sin dinero, trae las dos cosas'
);


-- ─── Le bajan el tope a medio mes ─────────────────────────────────────────────

reset role;
select tests.gastos(tests.r('a'), 30, 0, 0, 0);
select tests.authenticate_as('fragmentless');
select public.fijar_tope_ia(tests.r('a'), 5);
select tests.authenticate_as('don_chuy');
select is(tests.contador(tests.r('a')) ->> 'de', '20', 'Con el tope en 5, ahora le caben 20');
select is(tests.contador(tests.r('a')) ->> 'quedan', '0', 'Ya hizo 30: le quedan 0, nunca menos');
select is(
  tests.apartar(null, tests.r('a'), 501),
  jsonb_build_object('ok', false, 'motivo', 'cupo', 'vuelve', tests.vuelve()),
  'Y no aparta'
);
reset role;
select is((tests.uso(tests.r('a'))).anuncios, 30, 'No se borra nada de lo hecho');

select tests.authenticate_as('fragmentless');
select public.fijar_tope_ia(tests.r('a'), 10);
select tests.authenticate_as('don_chuy');
select is(tests.contador(tests.r('a')) ->> 'quedan', '10', 'Se lo suben a 10 y le quedan 10 de sus 40');


-- ─── «Tope de IA» ─────────────────────────────────────────────────────────────

reset role;
select tests.gastos(tests.r('a'), 16, 1.50, 1.25, 0.50);
select tests.authenticate_as('fragmentless');
select is(
  public.uso_ia_cliente(tests.r('a')) - 'mes' - 'consultas_agente' - 'saludos' - 'consultas_menu' - 'distribuidor_id' - 'distribuidor',
  '{"tope": 10.00, "gastado": 3.2500, "sobre_agente": 4.00, "gastado_agente": 1.5000, "agente_en_limite": false,
    "sobre_anuncios": 4.00, "gastado_anuncios": 1.2500, "anuncios": 16, "anuncios_caben": 40, "anuncios_en_limite": false,
    "sobre_menu": 2.00, "gastado_menu": 0.5000, "menu_en_limite": false}'::jsonb,
  'Cada sobre con lo suyo, y lo del agente ya no suma los anuncios'
);

reset role;
select tests.gastos(tests.r('a'), 16, 0, 4, 0);
select tests.authenticate_as('fragmentless');
select is(
  array[public.uso_ia_cliente(tests.r('a')) ->> 'anuncios_en_limite', public.uso_ia_cliente(tests.r('a')) ->> 'agente_en_limite',
        public.uso_ia_cliente(tests.r('a')) ->> 'menu_en_limite'],
  array['true', 'false', 'false'],
  'Solo los anuncios llegaron a lo suyo'
);

select is(
  array[public.uso_ia_cliente(tests.r('e')) ->> 'anuncios_caben', public.uso_ia_cliente(tests.r('e')) ->> 'sobre_anuncios',
        public.uso_ia_cliente(tests.r('e')) ->> 'anuncios_en_limite'],
  array['0', '0.08', 'false'],
  'Con 0.20 no cabe ninguno: no es que llegó a su límite'
);

select public.fijar_tope_ia(tests.r('a'), 7.76);
select is(
  array[public.uso_ia_cliente(tests.r('a')) ->> 'sobre_agente', public.uso_ia_cliente(tests.r('a')) ->> 'sobre_anuncios',
        public.uso_ia_cliente(tests.r('a')) ->> 'sobre_menu', public.uso_ia_cliente(tests.r('a')) ->> 'anuncios_caben'],
  array['3.11', '3.10', '1.55', '31'],
  'Con 7.76, cada renglón trae lo suyo: el agente, el centavo que sobra'
);

-- Con 7.76, cada sobre se acaba justo en su parte, ni un centavo después.
reset role;
select tests.gastos(tests.r('a'), 0, 3.10, 3.10, 0);
select tests.authenticate_as('don_chuy');
select is(public.estado_ia(tests.r('a')), '{"puede": true}'::jsonb, 'Con 3.10 de sus 3.11, el agente todavía puede');
select is(tests.contador(tests.r('a')) -> 'ia' ->> 'motivo', 'limite', 'Con 3.10 de sus 3.10, los anuncios ya no');

select tests.authenticate_as('don_chuy');
select throws_ok(
  $$ select public.uso_ia_cliente(tests.r('a')) $$,
  '42501', 'Solo Fragmentless puede hacer esto',
  'Don Chuy no ve lo que gasta'
);

select * from finish();
rollback;
