-- Pruebas del menú en línea, parte 6a (migración menu_en_linea): lo decidido el 20 de octubre de
-- 2026 en la libreta 6 y en el Diccionario, con la maqueta de la 6a. menu_publico es lo único que
-- se ejecuta sin sesión y solo entrega lo que está a la vista de un restaurante cuya licencia
-- funciona; si está abierto se cuenta con la hora del restaurante; «Tu restaurante», «Tu menú en
-- línea» y los carteles los cambia solo el gerente; el inglés de Mi menú se guarda limpio.
--
-- Escenario: los restaurantes A y B vigentes, C pausado, D venció ayer y E vence hoy; en A un
-- gerente y un mesero con su aparato; y el cliente sin sesión.
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



-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas, con ids fijos. A tiene su logo, su color, su
-- tipo de cambio (18.50), su horario (lunes a viernes de 9:00 a 18:00, el sábado de 9:00 a 1:00,
-- el domingo cerrado), dos carteles y un menú con lo que sale y lo que no: un producto oculto, uno
-- archivado, uno con un grupo obligatorio sin opciones a la vista (agotado), una categoría con
-- todo oculto, una vacía y una archivada. B no tiene horario, ni carteles, ni tipo de cambio.
-- tests.ruta arma una ruta de R2 con su carpeta y un número como nombre.

create function tests.ruta(p_restaurante_id uuid, p_carpeta text, p_n integer)
returns text
language sql
immutable
as $$
  select 'restaurantes/' || p_restaurante_id || '/' || p_carpeta || '/' || lpad(p_n::text, 32, '0') || '.webp'
$$;

-- Un producto del menú en línea, como lo ve la página (con el rol de quien llama).
create function tests.producto(p_slug text, p_id bigint)
returns jsonb
language sql
as $$
  select p
  from jsonb_array_elements(public.menu_publico(p_slug) -> 'categorias') c,
       jsonb_array_elements(c -> 'productos') p
  where (p ->> 'id')::bigint = p_id
$$;

-- Todos los productos del menú en línea, en el orden en que salen.
create function tests.productos(p_slug text)
returns table (categoria text, id bigint, producto jsonb)
language sql
as $$
  select c ->> 'nombre', (p ->> 'id')::bigint, p
  from jsonb_array_elements(public.menu_publico(p_slug) -> 'categorias') with ordinality as x (c, i),
       jsonb_array_elements(x.c -> 'productos') with ordinality as y (p, j)
  order by x.i, y.j
$$;

-- Lo que solo postgres puede calcular, guardado para compararlo después sin sesión.
create table tests.esperado (clave text primary key, valor jsonb);

grant execute on function
  tests.ruta(uuid, text, integer), tests.producto(text, bigint), tests.productos(text)
to anon, authenticated;
grant select on tests.esperado to anon, authenticated;

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  d uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  e uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (
    id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin,
    telefono, direccion, logo_ruta, menu_color, tipo_cambio_usd
  ) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30,
     '2221234567', 'Av. Juárez 123, Centro', tests.ruta(a, 'logo', 1), '#B3261E', 18.50),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, null, null, null, null, null),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30, null, null, null, null, null),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1, null, null, null, null, null),
    (e, 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy, null, null, null, null, null);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    (a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true),
    (a, tests.get_supabase_uid('mesero_a'), 'Mesero A', '{mesero}', true),
    (b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    (d, tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true);

  -- La tableta compartida de A, con la sesión del mesero: así entra el personal (migración empleados).
  insert into public.dispositivos (restaurante_id, nombre, token_hash, sesion_id)
  values (a, 'Tableta caja', repeat('a', 64), '5e5e5e5e-0000-4000-8000-00000000000a');

  insert into public.horarios (restaurante_id, dia, abre, cierra) values
    (a, 1, '9:00', '18:00'), (a, 2, '9:00', '18:00'), (a, 3, '9:00', '18:00'),
    (a, 4, '9:00', '18:00'), (a, 5, '9:00', '18:00'), (a, 6, '9:00', '1:00'),
    (c, 1, '9:00', '18:00'),
    (d, 4, '9:00', '14:00'),
    (e, 2, '9:00', '18:00'), (e, 3, '18:00', '0:00');

  -- Los carteles de A, el 702 primero.
  insert into public.carteles (id, restaurante_id, imagen_ruta, orden) overriding system value values
    (701, a, tests.ruta(a, 'carteles', 1), 2),
    (702, a, tests.ruta(a, 'carteles', 2), 1),
    (711, b, tests.ruta(b, 'carteles', 1), 1),
    (721, c, tests.ruta(c, 'carteles', 1), 1);

  -- Las categorías de A en su orden: Aguas, Tacos, Postres (todo oculto), Temporada (archivada)
  -- y Bebidas (vacía). El orden lo pone la base al insertar.
  insert into public.categorias (id, restaurante_id, nombre, nombre_en, icono) overriding system value values
    (602, a, 'Aguas', 'Drinks', 'agua'),
    (601, a, 'Tacos', null, 'taco'),
    (603, a, 'Postres', 'Desserts', 'postre'),
    (604, a, 'Temporada', null, 'especialidad'),
    (605, a, 'Bebidas', null, 'refresco'),
    (611, b, 'Tacos B', null, 'taco'),
    (621, c, 'Tacos C', null, 'taco');

  -- Los productos, en el orden en que salen dentro de su categoría.
  insert into public.productos (
    id, restaurante_id, categoria_id, nombre, nombre_en, descripcion, descripcion_en, precio, imagen_ruta
  ) overriding system value values
    (502, a, 601, 'Gringa', null, null, null, 75, null),
    (501, a, 601, 'Taco al pastor', 'Pastor taco', 'Con piña y cilantro', 'With pineapple and cilantro', 22,
     tests.ruta(a, 'menu', 1)),
    (503, a, 601, 'Taco oculto', null, null, null, 22, null),
    (504, a, 601, 'Taco viejo', null, null, null, 20, null),
    (505, a, 601, 'Taco de tortilla', null, null, null, 25, null),
    (506, a, 601, 'Taco sencillo', null, null, null, 18, null),
    (507, a, 602, 'Horchata', null, null, null, 30, null),
    (508, a, 602, 'Jamaica', null, null, null, 28, null),
    (509, a, 603, 'Flan', null, null, null, 40, null),
    (510, a, 604, 'Elote', null, null, null, 30, null),
    (511, b, 611, 'Taco B', null, null, null, 25, null),
    (521, c, 621, 'Taco C', null, null, null, 25, null);
  update public.productos set visible = false where id in (503, 509);
  update public.productos set archivado_at = now() where id = 504;
  update public.categorias set archivado_at = now() where id = 604;

  -- Los grupos de A, en el orden de Opciones: Extras, Salsa, Tamaño, Tortilla, Picante, Vaso.
  insert into public.grupos_opciones (id, restaurante_id, nombre, nombre_en, minimo, maximo) overriding system value values
    (902, a, 'Extras', 'Extras', 0, 3),
    (901, a, 'Salsa', 'Sauce', 1, 1),
    (903, a, 'Tamaño', null, 1, 1),
    (904, a, 'Tortilla', null, 1, 1),
    (905, a, 'Picante', null, 0, 1),
    (906, a, 'Vaso', null, 1, 1);

  insert into public.opciones (id, restaurante_id, grupo_id, nombre, nombre_en, precio_extra, visible, orden) overriding system value values
    (9021, a, 902, 'Queso', 'Cheese', 10, true, 1),
    (9022, a, 902, 'Aguacate', null, 12, true, 2),
    (9011, a, 901, 'Verde', 'Green', 0, true, 2),
    (9012, a, 901, 'Roja', null, 0, true, 1),
    (9013, a, 901, 'Habanero', null, 0, false, 3),
    (9031, a, 903, 'Normal', null, 0, true, 1),
    (9032, a, 903, 'Grande', null, 20, true, 2),
    (9041, a, 904, 'Maíz', null, 0, false, 1),
    (9042, a, 904, 'Harina', null, 5, false, 2),
    (9051, a, 905, 'Chile', null, 0, false, 1),
    (9061, a, 906, 'Medio litro', null, 0, true, 1),
    (9062, a, 906, 'Litro', null, 15, true, 2);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values
    (a, 501, 901), (a, 501, 902), (a, 502, 903), (a, 505, 904), (a, 506, 905), (a, 507, 906);

  insert into tests.esperado values ('estado_a', privado.horario_ahora(a));
end;
$$;

select plan(127);


-- ─── Permisos ─────────────────────────────────────────────────────────────────

select ok(
  has_function_privilege('anon', 'public.menu_publico(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.menu_publico(text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.menu_publico(text)', 'EXECUTE'),
  'menu_publico la ejecuta solo quien no tiene sesión: la página del menú'
);

select is_empty(
  $$ select t.tabla || ' ' || p.permiso
     from unnest(array['public.restaurantes', 'public.horarios', 'public.carteles']) as t(tabla),
          unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(permiso)
     where has_table_privilege('anon', t.tabla, p.permiso)
        or (p.permiso <> 'DELETE' and has_any_column_privilege('anon', t.tabla, p.permiso)) $$,
  'Sin sesión no se lee ni se escribe restaurantes, horarios ni carteles: solo se pide menu_publico'
);

select is_empty(
  $$ select t.tabla || ' ' || p.permiso
     from unnest(array['public.horarios', 'public.carteles']) as t(tabla),
          unnest(array['INSERT', 'UPDATE', 'DELETE']) as p(permiso)
     where has_table_privilege('authenticated', t.tabla, p.permiso)
        or (p.permiso <> 'DELETE' and has_any_column_privilege('authenticated', t.tabla, p.permiso)) $$,
  'Nadie con sesión escribe directo el horario ni los carteles: lo hacen las funciones'
);

select ok(
  has_column_privilege('authenticated', 'public.categorias', 'nombre_en', 'SELECT')
  and has_column_privilege('authenticated', 'public.categorias', 'nombre_en', 'INSERT')
  and has_column_privilege('authenticated', 'public.categorias', 'nombre_en', 'UPDATE'),
  'El inglés de una categoría se lee y se escribe con la categoría'
);

select ok(
  has_column_privilege('authenticated', 'public.productos', 'nombre_en', 'SELECT')
  and has_column_privilege('authenticated', 'public.productos', 'descripcion_en', 'SELECT')
  and has_column_privilege('authenticated', 'public.grupos_opciones', 'nombre_en', 'SELECT')
  and has_column_privilege('authenticated', 'public.opciones', 'nombre_en', 'SELECT')
  and not has_column_privilege('authenticated', 'public.productos', 'nombre_en', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.productos', 'descripcion_en', 'INSERT')
  and not has_column_privilege('authenticated', 'public.opciones', 'nombre_en', 'UPDATE'),
  'El inglés de productos, grupos y opciones se lee; se escribe con guardar_producto y guardar_grupo'
);

select ok(
  has_column_privilege('authenticated', 'public.restaurantes', 'menu_tema', 'SELECT')
  and has_column_privilege('authenticated', 'public.restaurantes', 'menu_color', 'SELECT')
  and has_column_privilege('authenticated', 'public.restaurantes', 'tipo_cambio_usd', 'SELECT')
  and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'restaurantes' and column_name = 'pagina_web'),
  'El tema, el color y el tipo de cambio se leen; la página web ya no existe'
);

select is_empty(
  $$ select f from unnest(array[
       'public.guardar_restaurante(uuid, text, text, text, text, jsonb)',
       'public.guardar_menu_en_linea(uuid, text, text, numeric)',
       'public.estado_menu_en_linea(uuid)',
       'public.agregar_cartel(uuid, text)',
       'public.cambiar_cartel(bigint, text)',
       'public.mover_cartel(bigint, text)',
       'public.quitar_cartel(bigint)',
       'public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[], text, text)',
       'public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[], text)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE') $$,
  'Las 9 funciones del gerente las llama quien tiene sesión, y cada una revisa quién es; sin sesión no'
);

select is_empty(
  $$ select f from unnest(array[
       'privado.horario_ahora(uuid, timestamptz)',
       'privado.productos_a_la_vista(uuid)'
     ]) as f
     where has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Las cuentas de adentro (el horario y lo que está a la vista) no las llama nadie directo'
);


-- ─── Las reglas de las columnas ───────────────────────────────────────────────

select throws_ok(
  $$ update public.restaurantes set menu_color = '#b3261e' where slug = 'restaurante-b' $$,
  '23514', null,
  'El color va como #RRGGBB en mayúsculas'
);

select throws_ok(
  $$ update public.restaurantes set menu_tema = 'gris' where slug = 'restaurante-b' $$,
  '23514', null,
  'El tema es claro u oscuro'
);

select throws_ok(
  $$ update public.restaurantes set tipo_cambio_usd = 0 where slug = 'restaurante-b' $$,
  '23514', null,
  'El tipo de cambio es mayor que cero'
);

select throws_ok(
  $$ update public.restaurantes set telefono = '222123456' where slug = 'restaurante-b' $$,
  '23514', null,
  'El teléfono son 10 dígitos'
);

select throws_ok(
  $$ update public.restaurantes set nombre = repeat('a', 61) where slug = 'restaurante-b' $$,
  '23514', null,
  'El nombre tiene hasta 60 letras'
);

select throws_ok(
  $$ update public.restaurantes set direccion = repeat('a', 201) where slug = 'restaurante-b' $$,
  '23514', null,
  'La dirección tiene hasta 200 letras'
);

select throws_ok(
  $$ insert into public.horarios (restaurante_id, dia, abre, cierra)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 8, '9:00', '18:00') $$,
  '23514', null,
  'Un día del horario va de 1 (lunes) a 7 (domingo)'
);

select throws_ok(
  $$ insert into public.horarios (restaurante_id, dia, abre, cierra)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1, '9:00', '9:00') $$,
  '23514', null,
  'Un día no abre y cierra a la misma hora'
);

select throws_ok(
  $$ insert into public.carteles (restaurante_id, imagen_ruta, orden)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
             tests.ruta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'menu', 7), 2) $$,
  '23514', null,
  'Un cartel vive en la carpeta de carteles de su restaurante'
);


-- ─── ¿Está abierto? ───────────────────────────────────────────────────────────
-- Con la hora del restaurante (México, UTC−6). El 19 de octubre de 2026 es lunes.

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-19 10:00-06'),
  '{"abierto": true, "cierra": "18:00"}'::jsonb,
  'El lunes a las 10:00 A está abierto y cierra a las 18:00'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-19 09:00-06'),
  '{"abierto": true, "cierra": "18:00"}'::jsonb,
  'A las 9:00 en punto ya abrió'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-19 18:00-06'),
  '{"abierto": false, "abre": {"dia": 2, "hora": "9:00", "en_dias": 1}}'::jsonb,
  'A las 18:00 en punto ya cerró, y abre mañana martes a las 9:00'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-19 07:00-06'),
  '{"abierto": false, "abre": {"dia": 1, "hora": "9:00", "en_dias": 0}}'::jsonb,
  'A las 7:00 está cerrado y abre hoy a las 9:00'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-19 00:30-06'),
  '{"abierto": false, "abre": {"dia": 1, "hora": "9:00", "en_dias": 0}}'::jsonb,
  'El lunes a las 0:30 está cerrado: el domingo no abrió'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-23 20:00-06'),
  '{"abierto": false, "abre": {"dia": 6, "hora": "9:00", "en_dias": 1}}'::jsonb,
  'El viernes a las 20:00 está cerrado y abre el sábado a las 9:00'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-24 23:00-06'),
  '{"abierto": true, "cierra": "1:00"}'::jsonb,
  'El sábado a las 23:00 está abierto y cierra a la 1:00'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-25 00:30-06'),
  '{"abierto": true, "cierra": "1:00"}'::jsonb,
  'El domingo a las 0:30 sigue abierto: esas horas son del sábado'
);

select is(
  privado.horario_ahora('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2026-10-25 01:00-06'),
  '{"abierto": false, "abre": {"dia": 1, "hora": "9:00", "en_dias": 1}}'::jsonb,
  'El domingo a la 1:00 ya cerró, y abre mañana lunes'
);

select is(
  privado.horario_ahora('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '2026-10-19 10:00-06'),
  null,
  'Sin horario no se sabe: null'
);

select is(
  privado.horario_ahora('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '2026-10-22 15:00-06'),
  '{"abierto": false, "abre": {"dia": 4, "hora": "9:00", "en_dias": 7}}'::jsonb,
  'Si solo abre los jueves y ya cerró, abre el jueves que viene'
);

select is(
  privado.horario_ahora('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', '2026-10-21 23:59-06'),
  '{"abierto": true, "cierra": "0:00"}'::jsonb,
  'De 18:00 a 0:00, a las 23:59 está abierto y cierra a las 0:00'
);

select is(
  privado.horario_ahora('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', '2026-10-22 00:00-06'),
  '{"abierto": false, "abre": {"dia": 2, "hora": "9:00", "en_dias": 5}}'::jsonb,
  'Y a las 0:00 ya cerró; abre el martes'
);

select is(
  privado.horario_ahora('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', '2026-10-20 19:00-06'),
  '{"abierto": false, "abre": {"dia": 3, "hora": "18:00", "en_dias": 1}}'::jsonb,
  'El martes a las 19:00 abre mañana a las 18:00'
);


-- ─── El menú sin sesión ───────────────────────────────────────────────────────

select tests.clear_authentication();

select ok(
  public.menu_publico('restaurante-a') is not null and public.menu_publico('  Restaurante-A ') is not null,
  'Sin sesión, el menú de A sale por su slug, también con mayúsculas o espacios de más'
);

select is(
  array[public.menu_publico('no-existe'), public.menu_publico('restaurante-c'),
        public.menu_publico('restaurante-d'), public.menu_publico(null)],
  array[null, null, null, null]::jsonb[],
  'Un slug que no existe, una licencia pausada y una vencida dan lo mismo: nada'
);

select ok(
  public.menu_publico('restaurante-e') is not null,
  'La licencia que vence hoy todavía funciona'
);

select is(
  public.menu_publico('restaurante-a') -> 'restaurante',
  jsonb_build_object(
    'nombre', 'Restaurante A', 'telefono', '2221234567', 'direccion', 'Av. Juárez 123, Centro',
    'logo_ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 1),
    'tema', 'claro', 'color', '#B3261E', 'tipo_cambio_usd', 18.50),
  'Del restaurante sale su nombre, teléfono, dirección, logo, tema, color y tipo de cambio; nada de su licencia'
);

select is(
  public.menu_publico('restaurante-a') -> 'ahora',
  jsonb_build_object(
    'fecha', to_char(now() at time zone 'America/Mexico_City', 'YYYY-MM-DD'),
    'dia', extract(isodow from now() at time zone 'America/Mexico_City')::integer,
    'hora', to_char(now() at time zone 'America/Mexico_City', 'HH24:MI')),
  'La fecha, el día y la hora son los del restaurante'
);

select is(
  public.menu_publico('restaurante-a') -> 'estado',
  (select valor from tests.esperado where clave = 'estado_a'),
  'Si está abierto lo dice horario_ahora, con la hora de ahora'
);

select is(
  public.menu_publico('restaurante-a') -> 'horario',
  '[{"dia": 1, "abre": "9:00", "cierra": "18:00"}, {"dia": 2, "abre": "9:00", "cierra": "18:00"},
    {"dia": 3, "abre": "9:00", "cierra": "18:00"}, {"dia": 4, "abre": "9:00", "cierra": "18:00"},
    {"dia": 5, "abre": "9:00", "cierra": "18:00"}, {"dia": 6, "abre": "9:00", "cierra": "1:00"}]'::jsonb,
  'El horario va por día, con las horas como 9:00; el domingo no sale: está cerrado'
);

select is(
  public.menu_publico('restaurante-a') -> 'carteles',
  jsonb_build_array(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2),
                    tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 1)),
  'Los carteles van en su orden'
);

select is(
  (select jsonb_agg(jsonb_build_object('nombre', c ->> 'nombre', 'nombre_en', c -> 'nombre_en', 'icono', c ->> 'icono') order by i)
   from jsonb_array_elements(public.menu_publico('restaurante-a') -> 'categorias') with ordinality as x (c, i)),
  '[{"nombre": "Aguas", "nombre_en": "Drinks", "icono": "agua"}, {"nombre": "Tacos", "nombre_en": null, "icono": "taco"}]'::jsonb,
  'Solo salen las categorías con algo a la vista, en su orden: ni la archivada, ni la vacía, ni la de todo oculto'
);

select results_eq(
  $$ select categoria, id from tests.productos('restaurante-a') $$,
  $$ values ('Aguas'::text, 507::bigint), ('Aguas', 508), ('Tacos', 502), ('Tacos', 501), ('Tacos', 506) $$,
  'Los productos salen en su orden; el oculto, el archivado y el agotado por su grupo no'
);

select is(
  tests.producto('restaurante-a', 501) - 'grupos',
  jsonb_build_object(
    'id', 501, 'nombre', 'Taco al pastor', 'nombre_en', 'Pastor taco',
    'descripcion', 'Con piña y cilantro', 'descripcion_en', 'With pineapple and cilantro',
    'precio', 22, 'precio_usd', 1.19, 'imagen_ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 1),
    'desde', false),
  'Cada producto con su inglés, su precio, su precio en dólares y su foto'
);

select is(
  tests.producto('restaurante-a', 501) -> 'grupos',
  '[{"nombre": "Extras", "nombre_en": "Extras", "minimo": 0, "maximo": 3, "opciones": [
      {"nombre": "Queso", "nombre_en": "Cheese", "precio_extra": 10, "precio_extra_usd": 0.54},
      {"nombre": "Aguacate", "nombre_en": null, "precio_extra": 12, "precio_extra_usd": 0.65}]},
    {"nombre": "Salsa", "nombre_en": "Sauce", "minimo": 1, "maximo": 1, "opciones": [
      {"nombre": "Roja", "nombre_en": null, "precio_extra": 0, "precio_extra_usd": 0},
      {"nombre": "Verde", "nombre_en": "Green", "precio_extra": 0, "precio_extra_usd": 0}]}]'::jsonb,
  'Sus grupos van en el orden de Opciones, con sus opciones a la vista en su orden: el habanero agotado no sale'
);

select results_eq(
  $$ select id, (producto ->> 'precio')::numeric, (producto ->> 'precio_usd')::numeric
     from tests.productos('restaurante-a') order by id $$,
  $$ values (501::bigint, 22::numeric, 1.19::numeric), (502, 75, 4.05), (506, 18, 0.97), (507, 30, 1.62), (508, 28, 1.51) $$,
  'Los dólares los calcula Postgres, redondeados al centavo'
);

select is(
  array[(tests.producto('restaurante-a', 501) ->> 'desde')::boolean,
        (tests.producto('restaurante-a', 502) ->> 'desde')::boolean,
        (tests.producto('restaurante-a', 507) ->> 'desde')::boolean,
        (tests.producto('restaurante-a', 508) ->> 'desde')::boolean],
  array[false, true, true, false],
  '«Desde» solo cuando un grupo obligatorio tiene una opción que sube el precio; los extras opcionales no cuentan'
);

select is(
  tests.producto('restaurante-a', 506) -> 'grupos',
  '[]'::jsonb,
  'Un grupo opcional sin opciones a la vista no sale, y su producto sí'
);

select is(
  (select jsonb_agg(c ->> 'nombre') from jsonb_array_elements(public.menu_publico('restaurante-b') -> 'categorias') c),
  '["Tacos B"]'::jsonb,
  'El menú de B solo trae lo de B'
);

select ok(
  tests.producto('restaurante-b', 511) ->> 'precio_usd' is null
  and public.menu_publico('restaurante-b') ->> 'estado' is null
  and public.menu_publico('restaurante-b') -> 'horario' = '[]'
  and public.menu_publico('restaurante-e') -> 'carteles' = '[]',
  'Sin tipo de cambio no hay dólares; sin horario, ni estado ni días; sin carteles, una lista vacía'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Robado', null, null, null, '[]') $$,
  '42501', null,
  'Sin sesión no se cambia nada'
);

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.menu_publico('restaurante-a') $$,
  '42501', null,
  'Con sesión, menu_publico no se llama: el panel lee sus tablas'
);


-- ─── Quién lee el horario y los carteles ──────────────────────────────────────

select results_eq(
  $$ select (select count(*) from public.horarios), (select count(*) from public.carteles) $$,
  $$ values (6::bigint, 2::bigint) $$,
  'Gerente A lee su horario y sus carteles, y nada de B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select results_eq(
  $$ select (select count(*) from public.horarios), (select count(*) from public.carteles) $$,
  $$ values (6::bigint, 2::bigint) $$,
  'Mesero A, en su aparato, también los lee'
);

select tests.authenticate_as('mesero_a');

select results_eq(
  $$ select (select count(*) from public.horarios) + (select count(*) from public.carteles) $$,
  $$ values (0::bigint) $$,
  'Fuera de su aparato, nada'
);

select tests.authenticate_as('gerente_c');

select results_eq(
  $$ select (select count(*) from public.horarios) + (select count(*) from public.carteles) $$,
  $$ values (0::bigint) $$,
  'Con la licencia pausada, el gerente no lee nada'
);


-- ─── Tu restaurante ───────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  La Fonda de Don Chuy ', '(222) 123-4567',
    ' Av. Juárez 123 ', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 1),
    '[{"dia": 1, "abre": "9:00", "cierra": "18:00"}, {"dia": 5, "abre": "18:00", "cierra": "02:00"}]'),
  null,
  'Gerente A guarda Tu restaurante; con el mismo logo no hay nada que borrar'
);

select results_eq(
  $$ select nombre, telefono, direccion from public.restaurantes $$,
  $$ values ('La Fonda de Don Chuy'::text, '2221234567'::text, 'Av. Juárez 123'::text) $$,
  'Se guarda sin espacios de más, y el teléfono solo con sus 10 dígitos'
);

select results_eq(
  $$ select dia::integer, abre, cierra from public.horarios order by dia $$,
  $$ values (1, '09:00'::time, '18:00'::time), (5, '18:00', '02:00') $$,
  'El horario se reescribe completo: los días que no llegan quedan cerrados'
);

select is(
  public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', '', '',
    tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 2), '[]'),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 1),
  'Con otro logo, regresa el anterior para borrarlo de R2'
);

select results_eq(
  $$ select telefono, direccion, logo_ruta, (select count(*) from public.horarios) from public.restaurantes $$,
  $$ values (null::text, null::text, tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 2), 0::bigint) $$,
  'Teléfono y dirección en blanco quedan vacíos, y sin días el horario queda vacío'
);

select is(
  public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', null, null, ' ', '[]'),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 2),
  'Sin logo, también regresa el que se quitó'
);

select is(
  (select logo_ruta from public.restaurantes),
  null,
  'Y el restaurante se queda sin logo'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', '222 123 456', null, null, '[]') $$,
  '22023', 'El teléfono lleva 10 dígitos, como 222 123 4567.',
  'Un teléfono de 9 dígitos no se guarda'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '   ', null, null, null, '[]') $$,
  '22023', 'El nombre de tu restaurante es obligatorio',
  'Sin nombre, tampoco'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', repeat('a', 61), null, null, null, '[]') $$,
  '22023', 'El nombre puede tener hasta 60 letras',
  'Ni con un nombre de 61 letras'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, repeat('a', 201), null, '[]') $$,
  '22023', 'La dirección puede tener hasta 200 letras',
  'Ni con una dirección de 201'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null, null,
       '[{"dia": 2, "abre": "9:00", "cierra": "18:00"}, {"dia": 2, "abre": "19:00", "cierra": "22:00"}]') $$,
  '22023', 'Cada día va una sola vez en tu horario',
  'Un día no va dos veces en el horario'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null, null,
       '[{"dia": 2, "abre": "9:00", "cierra": "9:00"}]') $$,
  '22023', 'El martes abre y cierra a la misma hora',
  'Ni abre y cierra a la misma hora'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null, null,
       '[{"dia": 1, "abre": "25:00", "cierra": "9:00"}]') $$,
  '22023', 'Revisa las horas del lunes',
  'Una hora que no existe no se guarda'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null, null,
       '[{"dia": 8, "abre": "9:00", "cierra": "18:00"}]') $$,
  '22023', 'El horario va de lunes a domingo',
  'Ni un día 8'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null, null, null) $$,
  '22023', 'Falta el horario',
  'Sin horario, ni siquiera vacío, no se guarda'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null,
       tests.ruta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'logo', 3), '[]') $$,
  '23514', null,
  'El logo de otro restaurante no se pone'
);

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null,
       tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 3), '[]') $$,
  '23514', null,
  'Ni una foto de la carpeta del menú: el logo vive en su carpeta'
);

select throws_ok(
  $$ select public.guardar_restaurante('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B', null, null, null, '[]') $$,
  '42501', null,
  'Gerente A no cambia los datos de B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null, null, '[]') $$,
  '42501', null,
  'Mesero A, ni en su aparato, cambia los datos del restaurante'
);

select tests.authenticate_as('gerente_c');

select throws_ok(
  $$ select public.guardar_restaurante('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'C', null, null, null, '[]') $$,
  '42501', null,
  'Con la licencia pausada, el gerente no cambia sus datos'
);

select tests.authenticate_as('gerente_d');

select throws_ok(
  $$ select public.guardar_restaurante('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'D', null, null, null, '[]') $$,
  '42501', null,
  'Ni con la licencia vencida'
);


-- ─── Tu menú en línea: cómo se ve ─────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'oscuro', ' #f2b705 ', 17.256) $$,
  'Gerente A guarda el tema, el color y el tipo de cambio'
);

select results_eq(
  $$ select menu_tema, menu_color, tipo_cambio_usd from public.restaurantes $$,
  $$ values ('oscuro'::text, '#F2B705'::text, 17.26::numeric) $$,
  'El color se guarda en mayúsculas y el tipo de cambio al centavo'
);

select lives_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'claro', '', null) $$,
  'Y los puede quitar'
);

select results_eq(
  $$ select menu_tema, menu_color, tipo_cambio_usd from public.restaurantes $$,
  $$ values ('claro'::text, null::text, null::numeric) $$,
  'Sin color, la barra neutra; sin tipo de cambio, solo pesos'
);

select throws_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'gris', null, null) $$,
  '22023', 'El menú se ve claro u oscuro',
  'El tema es claro u oscuro'
);

select throws_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'claro', 'rojo', null) $$,
  '22023', 'Ese color no se entiende; escríbelo como #B3261E',
  'Un color que no es #RRGGBB no se guarda'
);

select throws_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'claro', null, 0) $$,
  '22023', 'Escribe a cuánto tomas el dólar, como 18.50',
  'Ni un tipo de cambio de cero'
);

select throws_ok(
  $$ select public.guardar_menu_en_linea('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'claro', null, null) $$,
  '42501', null,
  'Gerente A no cambia el menú de B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ select public.guardar_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'oscuro', null, null) $$,
  '42501', null,
  'Ni Mesero A'
);


-- ─── Tu menú en línea: los carteles ───────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select ok(
  public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 3)) is not null
  and public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 4)) is not null
  and public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 5)) is not null,
  'Gerente A agrega tres carteles'
);

select results_eq(
  $$ select right(imagen_ruta, 6) from public.carteles order by orden, id $$,
  $$ values ('2.webp'), ('1.webp'), ('3.webp'), ('4.webp'), ('5.webp') $$,
  'Cada cartel nuevo va al final'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 6)) $$,
  '55000', 'Ya tienes 5 carteles. Quita uno para agregar otro.',
  'Con 5 ya no cabe otro'
);

select lives_ok(
  $$ select public.mover_cartel(701, 'arriba') $$,
  'Sube un cartel'
);

select lives_ok(
  $$ select public.mover_cartel(701, 'arriba') $$,
  'En la orilla no pasa nada'
);

select results_eq(
  $$ select right(imagen_ruta, 6), orden from public.carteles order by orden, id $$,
  $$ values ('1.webp', 1), ('2.webp', 2), ('3.webp', 3), ('4.webp', 4), ('5.webp', 5) $$,
  'Y quedan numerados en el orden en que se ven'
);

select throws_ok(
  $$ select public.mover_cartel(701, 'izquierda') $$,
  '22023', 'El cartel solo se mueve arriba o abajo',
  'Solo se mueve arriba o abajo'
);

select is(
  public.cambiar_cartel(702, tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 7)),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2),
  'Cambiar la imagen regresa la anterior para borrarla de R2'
);

select results_eq(
  $$ select imagen_ruta from public.carteles where orden = 2 $$,
  $$ values (tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 7)) $$,
  'Y el cartel se queda en su lugar'
);

select is(
  public.quitar_cartel(701),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 1),
  'Quitar un cartel regresa su imagen para borrarla de R2'
);

select results_eq(
  $$ select count(*) from public.carteles $$,
  $$ values (4::bigint) $$,
  'Y ya no está'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'carteles', 8)) $$,
  '23514', null,
  'Un cartel de la carpeta de otro restaurante no se agrega'
);

select throws_ok(
  $$ select public.agregar_cartel('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.ruta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'carteles', 8)) $$,
  '42501', null,
  'Gerente A no agrega carteles a B'
);

select throws_ok(
  $$ select public.quitar_cartel(711) $$,
  '42501', null,
  'Ni quita los de B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 8)) $$,
  '42501', null,
  'Mesero A no agrega carteles'
);

select throws_ok(
  $$ select public.mover_cartel(702, 'abajo') $$,
  '42501', null,
  'Ni los mueve'
);

select throws_ok(
  $$ select public.cambiar_cartel(702, tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 8)) $$,
  '42501', null,
  'Ni los cambia'
);

select throws_ok(
  $$ select public.quitar_cartel(702) $$,
  '42501', null,
  'Ni los quita'
);

select tests.authenticate_as('gerente_c');

select throws_ok(
  $$ select public.agregar_cartel('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.ruta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'carteles', 1)) $$,
  '42501', null,
  'Con la licencia pausada, el gerente no agrega carteles'
);


-- ─── ¿Se puede borrar esta imagen de R2? ──────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A', null, null,
       tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 4), '[]') $$,
  'Gerente A pone otra vez un logo'
);

select is(
  array[public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 4)),
        public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 7)),
        public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 1))],
  array[false, false, false],
  'El logo en uso, un cartel y la foto de un producto no se borran'
);

select is(
  array[public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 1)),
        public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 1)),
        public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 9))],
  array[true, true, true],
  'El logo anterior, el cartel quitado y una foto que nada usa sí'
);

select is(
  array[public.puedo_borrar_foto(tests.ruta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'logo', 9)),
        public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'biblioteca', 9)),
        public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/logo/../menu/' || repeat('0', 32) || '.webp')],
  array[false, false, false],
  'Ni la carpeta de otro restaurante, ni otra carpeta, ni una ruta con trampa'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select is(
  public.puedo_borrar_foto(tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'logo', 1)),
  false,
  'Mesero A no borra imágenes'
);


-- ─── Mi menú en inglés ────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 508, 602, 'Jamaica', null, 28, null, '{}',
    '  Hibiscus water ', '   '),
  508::bigint,
  'Gerente A guarda un producto con su inglés'
);

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where id = 508 $$,
  $$ values ('Hibiscus water'::text, null::text) $$,
  'El inglés se guarda sin espacios de más, y en blanco queda vacío'
);

select lives_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 601, 'Taco al pastor',
       'Con piña y cilantro', 22, null, '{901,902}') $$,
  'Una llamada sin inglés sigue funcionando'
);

select results_eq(
  $$ select nombre_en, descripcion_en, imagen_ruta from public.productos where id = 501 $$,
  $$ values (null::text, null::text, tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 1)) $$,
  'Y deja el inglés vacío; la foto se queda'
);

select ok(
  public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 601, 'Taco de bistec', null, 24,
                          null, '{}', 'Steak taco', 'Grilled') is not null,
  'Gerente A agrega un producto con su inglés'
);

select results_eq(
  $$ select nombre_en, descripcion_en from public.productos where nombre = 'Taco de bistec' $$,
  $$ values ('Steak taco'::text, 'Grilled'::text) $$,
  'Y nace con él'
);

select is(
  public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 903, 'Tamaño', 1, 1,
    '[{"id": 9031, "nombre": "Normal", "nombre_en": "Regular"},
      {"id": 9032, "nombre": "Grande", "nombre_en": " ", "precio_extra": 20},
      {"nombre": "Chico", "nombre_en": "Small"}]',
    '{502}', ' Size '),
  903::bigint,
  'Gerente A guarda un grupo con su inglés y el de sus opciones'
);

select results_eq(
  $$ select g.nombre_en, o.nombre, o.nombre_en
     from public.opciones o join public.grupos_opciones g on g.id = o.grupo_id
     where o.grupo_id = 903 order by o.orden $$,
  $$ values ('Size'::text, 'Normal'::text, 'Regular'::text), ('Size', 'Grande', null), ('Size', 'Chico', 'Small') $$,
  'Se guardan sin espacios de más, y el que va en blanco queda vacío'
);

select lives_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 906, 'Vaso', 1, 1,
       '[{"id": 9061, "nombre": "Medio litro"}, {"id": 9062, "nombre": "Litro", "precio_extra": 15}]', '{507}') $$,
  'Una llamada sin inglés sigue funcionando'
);

select lives_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono, nombre_en)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Postres caseros', 'postre', ' Homemade desserts ') $$,
  'Gerente A agrega una categoría con su inglés'
);

select is(
  tests.filas($$ update public.categorias set nombre_en = '  ' where id = 602 $$),
  1,
  'Y se lo cambia'
);

select results_eq(
  $$ select nombre, nombre_en from public.categorias where id = 602 or nombre = 'Postres caseros' order by nombre $$,
  $$ values ('Aguas'::text, null::text), ('Postres caseros', 'Homemade desserts') $$,
  'Sin espacios de más, y en blanco queda vacío'
);

select tests.clear_authentication();

select results_eq(
  $$ select tests.producto('restaurante-a', 508) ->> 'nombre_en', tests.producto('restaurante-a', 502) -> 'grupos' -> 0 ->> 'nombre_en' $$,
  $$ values ('Hibiscus water'::text, 'Size'::text) $$,
  'El menú en línea enseña el inglés en cuanto se guarda'
);

select is(
  (select count(*)::integer from tests.productos('restaurante-a')),
  6,
  'Y enseña 6 productos: los mismos que cuenta el chip de abajo'
);


-- ─── El chip de Tu menú en línea ──────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('estado', null, 'a_la_vista', 6, 'productos', 9),
  'Gerente A ve cuántos productos están a la vista de los que tiene; sin horario, sin estado'
);

select throws_ok(
  $$ select public.estado_menu_en_linea('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  '42501', null,
  'Gerente A no ve el de B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ select public.estado_menu_en_linea('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null,
  'Ni Mesero A'
);


-- ─── La licencia apaga el menú ────────────────────────────────────────────────

reset role;
select set_config('request.jwt.claims', null, true);
update public.restaurantes set licencia_activa = false where slug = 'restaurante-a';
select tests.clear_authentication();

select is(
  public.menu_publico('restaurante-a'),
  null,
  'Con la licencia pausada, el menú de A ya no sale, como si no existiera'
);


select * from finish();

rollback;
