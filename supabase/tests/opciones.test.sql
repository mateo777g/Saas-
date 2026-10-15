-- Pruebas de opciones y áreas (migración opciones). Trae las pruebas de aislamiento de la
-- libreta 2 que tocan las áreas, los grupos, las opciones y sus ligas (1, 2, 3, 4, 5, 6, 8, 9,
-- 16, 18 y 22; cada descripción empieza con su número) y lo decidido el 15 de octubre de 2026
-- con la maqueta de Opciones y áreas: «Cocina» al nacer, eliminar un área, el área de cada
-- categoría, guardar un grupo o un producto todo junto, el orden de los grupos y eliminarlos.
--
-- Escenario: los restaurantes A y B vigentes, C pausado, D venció ayer y E vence hoy; en A
-- un gerente, un mesero y un mesero dado de baja; Fragmentless; y el cliente sin sesión. A
-- tiene Cocina, Barra (con Aguas), Parrilla (solo con una categoría archivada), Plancha (ya
-- recibió comandas) y un área archivada; los grupos Salsa, Extras y Tamaño con sus opciones,
-- puestos en sus productos. B tiene su Cocina, su Barra y su grupo Salsa B.
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
-- Se siembra como postgres, dueño de las tablas, con ids fijos para poder nombrar filas
-- que quien prueba no alcanza a leer. Cada restaurante nace con su «Cocina» (el trigger);
-- tests.ids guarda sus ids. tests.comandas hace de las comandas de la pieza 4: el área que
-- señala ya recibió comandas.

create table tests.ids (nombre text primary key, id bigint not null);
grant select on tests.ids to anon, authenticated;

create table tests.comandas (
  restaurante_id uuid not null,
  area_preparacion_id bigint not null,
  foreign key (restaurante_id, area_preparacion_id) references public.areas_preparacion (restaurante_id, id)
);

-- Lo que nadie con sesión alcanza a ver: las áreas de un restaurante sin miembros.
create function tests.areas_de(p_restaurante_id uuid)
returns setof text
language sql
security definer
set search_path = ''
as $$
  select nombre from public.areas_preparacion where restaurante_id = p_restaurante_id order by id
$$;
grant execute on function tests.areas_de(uuid) to anon, authenticated;

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('mesero_baja_a', 'mesero.baja.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');
  perform tests.create_supabase_user('gerente_e', 'gerente.e@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    (a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true),
    (a, tests.get_supabase_uid('mesero_a'), 'Mesero A', '{mesero}', true),
    (a, tests.get_supabase_uid('mesero_baja_a'), 'Mesero A dado de baja', '{mesero}', false),
    (b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.get_supabase_uid('gerente_e'), 'Gerente E', '{gerente}', true);

  -- La tableta compartida de A, con la sesión del mesero: así entra el personal (migración empleados).
  insert into public.dispositivos (restaurante_id, nombre, token_hash, sesion_id)
  values (a, 'Tableta caja', repeat('a', 64), '5e5e5e5e-0000-4000-8000-00000000000a');

  insert into tests.ids (nombre, id)
  select 'cocina_' || lower(right(r.nombre, 1)), ap.id
  from public.areas_preparacion ap join public.restaurantes r on r.id = ap.restaurante_id;

  -- Las áreas de A: Cocina, Barra (con Aguas), Parrilla (solo con una categoría archivada),
  -- Plancha (ya recibió comandas) y una archivada. B: Cocina y Barra.
  insert into public.areas_preparacion (id, restaurante_id, nombre, archivado_at) overriding system value values
    (802, a, 'Barra', null),
    (803, a, 'Parrilla', null),
    (804, a, 'Terraza vieja', now()),
    (805, a, 'Plancha', null),
    (812, b, 'Barra', null);
  insert into tests.comandas values (a, 805);

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id, archivado_at) overriding system value values
    (601, a, 'Tacos', 'taco', (select id from tests.ids where nombre = 'cocina_a'), null),
    (602, a, 'Aguas', 'agua', 802, null),
    (603, a, 'Refrescos', 'refresco', null, null),
    (611, b, 'Tacos B', 'taco', (select id from tests.ids where nombre = 'cocina_b'), null),
    (621, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Tacos C', 'taco', null, null),
    (631, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Tacos D', 'taco', null, null);
  -- Una categoría de temporada, ya archivada, que iba a la Parrilla (se archiva después:
  -- ninguna categoría entra a un área archivada, pero la Parrilla no lo está).
  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value
  values (604, a, 'Temporada', 'especialidad', 803);
  update public.categorias set archivado_at = now() where id = 604;

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, imagen_ruta, archivado_at) overriding system value values
    (501, a, 601, 'Taco al pastor', 22, 'restaurantes/' || a || '/menu/' || repeat('ab', 16) || '.webp', null),
    (502, a, 601, 'Taco de suadero', 22, null, null),
    (503, a, 602, 'Horchata', 30, null, null),
    (504, a, 603, 'Coca-Cola', 30, null, null),
    (505, a, 601, 'Taco viejo', 20, null, now()),
    (511, b, 611, 'Taco B', 25, null, null),
    (521, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 621, 'Taco C', 25, null, null),
    (531, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 631, 'Taco D', 25, null, null);

  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Salsa', 1, 1),
    (902, a, 'Extras', 0, 3),
    (903, a, 'Tamaño', 1, 1),
    (911, b, 'Salsa B', 1, 1),
    (921, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Salsa C', 1, 1),
    (931, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Salsa D', 1, 1);

  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Verde', 0, true, 1),
    (9012, a, 901, 'Roja', 0, true, 2),
    (9013, a, 901, 'Habanero', 0, false, 3),
    (9021, a, 902, 'Queso', 15, true, 1),
    (9022, a, 902, 'Aguacate', 12, true, 2),
    (9031, a, 903, 'Medio litro', 0, true, 1),
    (9032, a, 903, 'Litro', 15, true, 2),
    (9111, b, 911, 'Verde B', 0, true, 1),
    (9211, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 921, 'Verde C', 0, true, 1),
    (9311, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 931, 'Verde D', 0, true, 1);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values
    (a, 501, 901), (a, 502, 901), (a, 501, 902), (a, 503, 903), (a, 505, 901),
    (b, 511, 911),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 521, 921),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 531, 931);
end;
$$;

select plan(118);


-- ─── 1 · Permisos ─────────────────────────────────────────────────────────────

select is_empty(
  $$ select t.tabla || ' ' || p.permiso
     from unnest(array['public.grupos_opciones', 'public.opciones', 'public.producto_grupos']) as t(tabla),
          unnest(array['INSERT', 'UPDATE', 'DELETE']) as p(permiso)
     where has_table_privilege('authenticated', t.tabla, p.permiso)
        or (p.permiso <> 'DELETE' and has_any_column_privilege('authenticated', t.tabla, p.permiso)) $$,
  '1 · Nadie con sesión escribe directo grupos, opciones ni ligas: lo hacen las funciones'
);

select ok(
  not has_table_privilege('authenticated', 'public.areas_preparacion', 'DELETE'),
  '1 · Nadie con sesión borra áreas directo: lo hace eliminar_area'
);

select is_empty(
  $$ select c.columna || ' ' || p.permiso
     from unnest(array['archivado_at', 'restaurante_id', 'id', 'created_at', 'updated_at']) as c(columna),
          unnest(array['INSERT', 'UPDATE']) as p(permiso)
     where has_column_privilege('authenticated', 'public.areas_preparacion', c.columna, p.permiso)
       and not (c.columna = 'restaurante_id' and p.permiso = 'INSERT') $$,
  '1 · Nadie con sesión escribe el archivado, el restaurante ni las fechas de un área'
);

select ok(
  has_column_privilege('authenticated', 'public.categorias', 'area_preparacion_id', 'SELECT')
  and has_column_privilege('authenticated', 'public.categorias', 'area_preparacion_id', 'INSERT')
  and has_column_privilege('authenticated', 'public.categorias', 'area_preparacion_id', 'UPDATE'),
  '1 · El área de una categoría se lee y se escribe con la categoría'
);

select is_empty(
  $$ select f from unnest(array[
       'public.eliminar_area(bigint)',
       'public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[])',
       'public.mover_grupo(bigint, text)',
       'public.eliminar_grupo(bigint)',
       'public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[])'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE') $$,
  '1 · Las 5 funciones las llama quien tiene sesión, y cada una revisa quién es; sin sesión no'
);


-- ─── Cada restaurante nace con «Cocina» ───────────────────────────────────────

insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin)
values ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'Restaurante F', 'restaurante-f', false, null, null);

select results_eq(
  $$ select * from tests.areas_de('ffffffff-ffff-4fff-8fff-ffffffffffff') $$,
  array['Cocina'],
  'Un restaurante nuevo nace con su área «Cocina», y solo esa'
);


-- ─── 2 · Quién lee ────────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select set_eq(
  'select id from public.areas_preparacion',
  $$ select id from tests.ids where nombre = 'cocina_a' union all values (802), (803), (804), (805) $$,
  '2 · Gerente A lee sus áreas, también la archivada; ninguna de B'
);

select set_eq(
  'select id from public.grupos_opciones',
  array[901, 902, 903]::bigint[],
  '2 · Gerente A lee sus grupos y ninguno de B'
);

select set_eq(
  'select id from public.opciones',
  array[9011, 9012, 9013, 9021, 9022, 9031, 9032]::bigint[],
  '2 · Y sus opciones, también la agotada'
);

select set_eq(
  'select producto_id, grupo_id from public.producto_grupos',
  $$ values (501::bigint, 901::bigint), (502, 901), (501, 902), (503, 903), (505, 901) $$,
  '2 · Y qué grupos lleva cada uno de sus productos'
);

select results_eq(
  $$ select id, area_preparacion_id from public.categorias where id in (602, 603) order by id $$,
  $$ values (602::bigint, 802::bigint), (603, null) $$,
  '2 · Y el área de cada categoría; vacía es «Lo sirve el mesero»'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select results_eq(
  $$ select (select count(*) from public.areas_preparacion), (select count(*) from public.grupos_opciones),
            (select count(*) from public.opciones), (select count(*) from public.producto_grupos) $$,
  $$ values (5::bigint, 3::bigint, 7::bigint, 5::bigint) $$,
  '2 · Mesero A, en su aparato, lee las áreas, los grupos, las opciones y las ligas: el punto de venta las usa'
);

select tests.authenticate_as('mesero_a');

select results_eq(
  $$ select (select count(*) from public.areas_preparacion) + (select count(*) from public.grupos_opciones)
          + (select count(*) from public.opciones) + (select count(*) from public.producto_grupos) $$,
  $$ values (0::bigint) $$,
  '2 · Fuera de su aparato no lee nada'
);

select tests.authenticate_as('gerente_b');

select set_eq(
  'select nombre from public.grupos_opciones',
  array['Salsa B'],
  '2 · Gerente B lee solo lo suyo'
);


-- ─── 3, 4, 5 y 6 · Gerente A contra lo de B ───────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Parrilla') $$,
  '42501', null,
  '3 · Gerente A no agrega un área a B'
);

select throws_ok(
  $$ select public.guardar_grupo('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', null, 'Tamaño', 1, 1,
       '[{"nombre": "Grande"}]', '{}') $$,
  '42501', null,
  '3 · Ni un grupo'
);

select throws_ok(
  $$ select public.guardar_producto('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', null, 611, 'Taco ajeno', null, 20, null, '{}') $$,
  '42501', null,
  '3 · Ni un producto'
);

select is(
  tests.filas($$ update public.areas_preparacion set nombre = 'Mía' where id = 812 $$),
  0,
  '4 · Gerente A no renombra el área de B: 0 filas'
);

select throws_ok(
  'select public.eliminar_area(812)',
  '42501', null,
  '4 · Ni la elimina'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 911, 'Mío', 1, 1, '[{"nombre": "Verde"}]', '{}') $$,
  '23503', 'Ese grupo ya no está en tu menú',
  '4 · Ni cambia el grupo de B haciéndolo pasar por suyo'
);

select throws_ok(
  'select public.eliminar_grupo(911)',
  '42501', null,
  '4 · Ni lo elimina'
);

select throws_ok(
  $$ select public.mover_grupo(911, 'abajo') $$,
  '42501', null,
  '4 · Ni lo mueve'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 511, 601, 'Mío', null, 1, null, '{}') $$,
  '23503', 'Ese producto ya no está en tu menú',
  '4 · Ni cambia un producto de B'
);

select throws_ok(
  $$ update public.areas_preparacion set restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where id = 802 $$,
  '42501', null,
  '5 · Gerente A no pasa su área a B'
);

select throws_ok(
  $$ update public.categorias set area_preparacion_id = 812 where id = 602 $$,
  '23503', null,
  '6 · Una categoría de A no va al área de B: la llave compuesta lo impide'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Salsa', 1, 1,
       '[{"id": 9011, "nombre": "Verde"}]', '{511}') $$,
  '23503', 'Uno de esos productos ya no está en tu menú',
  '6 · Un grupo de A no se pone en un producto de B'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 601, 'Taco al pastor', null, 22, null, '{911}') $$,
  '23503', 'Uno de esos grupos ya no está en tu menú',
  '6 · Ni un producto de A lleva un grupo de B'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Salsa', 1, 1,
       '[{"id": 9111, "nombre": "Verde B"}]', '{}') $$,
  '23503', 'Una de esas opciones ya no está en este grupo',
  '6 · Ni se queda con una opción de B'
);

select tests.authenticate_as('gerente_b');

select results_eq(
  $$ select g.nombre, o.nombre, (select count(*) from public.producto_grupos), (select a.nombre from public.areas_preparacion a where a.id = 812)
     from public.grupos_opciones g join public.opciones o on o.grupo_id = g.id $$,
  $$ values ('Salsa B'::text, 'Verde B'::text, 1::bigint, 'Barra'::text) $$,
  '4 · Revisado como B: su grupo, su opción, su liga y su área siguen igual'
);


-- ─── 8, 9, 16, 18 y 22 · Quien no debe ────────────────────────────────────────

select tests.authenticate_as('gerente_c');

select results_eq(
  $$ select (select count(*) from public.areas_preparacion) + (select count(*) from public.grupos_opciones)
          + (select count(*) from public.opciones) + (select count(*) from public.producto_grupos) $$,
  $$ values (0::bigint) $$,
  '8 · Gerente C, con la licencia pausada, no ve sus áreas, grupos, opciones ni ligas'
);

select throws_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Barra') $$,
  '42501', null,
  '8 · Ni agrega una'
);

select throws_ok(
  $$ select public.guardar_grupo('cccccccc-cccc-4ccc-8ccc-cccccccccccc', null, 'Salsa', 1, 1, '[{"nombre": "Verde"}]', '{}') $$,
  '42501', null,
  '8 · Ni arma un grupo'
);

select tests.authenticate_as('mesero_baja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select results_eq(
  $$ select (select count(*) from public.areas_preparacion) + (select count(*) from public.grupos_opciones)
          + (select count(*) from public.opciones) + (select count(*) from public.producto_grupos) $$,
  $$ values (0::bigint) $$,
  '9 · El mesero de A dado de baja no lee nada'
);

select tests.authenticate_as('gerente_d');

select results_eq(
  $$ select (select count(*) from public.areas_preparacion) + (select count(*) from public.grupos_opciones)
          + (select count(*) from public.opciones) + (select count(*) from public.producto_grupos) $$,
  $$ values (0::bigint) $$,
  '22 · Gerente D, que venció ayer, no ve sus áreas, grupos, opciones ni ligas'
);

select tests.authenticate_as('gerente_e');

select set_eq(
  'select nombre from public.areas_preparacion',
  array['Cocina'],
  '22 · Gerente E, que vence hoy, todavía ve la suya'
);

select tests.authenticate_as('fragmentless');

select results_eq(
  $$ select (select count(*) from public.areas_preparacion) + (select count(*) from public.grupos_opciones)
          + (select count(*) from public.opciones) + (select count(*) from public.producto_grupos) $$,
  $$ values (0::bigint) $$,
  '18 · Fragmentless no lee el menú de sus clientes'
);

select tests.clear_authentication();

select throws_ok(
  'select id from public.grupos_opciones',
  '42501', null,
  '16 · Sin sesión no se leen los grupos'
);

select throws_ok(
  'select id from public.areas_preparacion',
  '42501', null,
  '16 · Ni las áreas'
);

select throws_ok(
  'select public.eliminar_grupo(901)',
  '42501', null,
  '16 · Ni se elimina un grupo'
);


-- ─── El mesero no cambia el menú ──────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Barra 2') $$,
  '42501', null,
  'Mesero A no agrega áreas'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Salsa', 1, 1, '[{"id": 9011, "nombre": "Verde"}]', '{}') $$,
  '42501', null,
  'Ni cambia un grupo'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 601, 'Taco', null, 1, null, '{}') $$,
  '42501', null,
  'Ni un producto'
);

select is(
  tests.filas($$ update public.categorias set area_preparacion_id = null where id = 602 $$),
  0,
  'Ni el área de una categoría: 0 filas'
);

select throws_ok(
  $$ select public.mover_grupo(902, 'arriba') $$,
  '42501', null,
  'Ni el orden de los grupos'
);

select throws_ok(
  'select public.eliminar_grupo(902)',
  '42501', null,
  'Ni elimina un grupo'
);

select throws_ok(
  'select public.eliminar_area(802)',
  '42501', null,
  'Ni un área'
);


-- ─── Áreas ────────────────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  Caja fría  ') $$,
  'Gerente A agrega un área'
);

select results_eq(
  $$ select nombre, archivado_at is null from public.areas_preparacion where nombre = 'Caja fría' $$,
  $$ values ('Caja fría'::text, true) $$,
  'Se guarda sin espacios sobrantes'
);

select throws_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'barra') $$,
  '23505', null,
  'No hay dos áreas con el mismo nombre, aunque cambien las mayúsculas'
);

select lives_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Terraza vieja') $$,
  'El nombre de un área archivada se puede volver a usar'
);

select throws_ok(
  $$ insert into public.areas_preparacion (restaurante_id, nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '   ') $$,
  '23514', null,
  'Un área sin nombre no se guarda'
);

select is(
  tests.filas($$ update public.areas_preparacion set nombre = 'Barra fría' where id = 802 $$),
  1,
  'Gerente A renombra un área'
);

select is(
  tests.filas($$ update public.areas_preparacion set nombre = 'Otra' where id = 804 $$),
  0,
  'Pero no una archivada: 0 filas'
);

select throws_ok(
  'select public.eliminar_area(802)',
  '55000', 'Barra fría todavía tiene 1 categoría; cámbiala de área primero',
  'Un área con categorías no se elimina: primero se cambian de área'
);

select is(
  public.eliminar_area(803),
  'borrado',
  'Un área a la que solo iba una categoría archivada se borra'
);

select results_eq(
  $$ select area_preparacion_id from public.categorias where id = 604 $$,
  $$ values (null::bigint) $$,
  'Y esa categoría archivada se queda sin área'
);

select is(
  public.eliminar_area(805),
  'archivado',
  'Un área que ya recibió comandas se archiva en vez de borrarse'
);

select results_eq(
  $$ select archivado_at is not null from public.areas_preparacion where id = 805 $$,
  $$ values (true) $$,
  'Y queda archivada'
);

select throws_ok(
  'select public.eliminar_area(804)',
  '42501', null,
  'Un área ya archivada no se vuelve a eliminar'
);

select is(
  tests.filas($$ update public.categorias set area_preparacion_id = 802 where id = 601 $$),
  1,
  '«Cocina» es como las demás: se le quitan sus categorías…'
);

select is(
  public.eliminar_area((select id from tests.ids where nombre = 'cocina_a')),
  'borrado',
  '… y se elimina'
);

select tests.authenticate_as('gerente_e');

select throws_ok(
  $$ select public.eliminar_area((select id from tests.ids where nombre = 'cocina_e')) $$,
  '55000', 'Necesitas al menos un área. Crea otra antes de eliminar «Cocina».',
  'La última área que queda no se elimina'
);


-- ─── El área de cada categoría ────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono, area_preparacion_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cervezas', 'cerveza', 802) $$,
  'Una categoría nueva elige su área'
);

select lives_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Postres', 'postre') $$,
  'O ninguna: la sirve el mesero'
);

select throws_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono, area_preparacion_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Café', 'cafe', 804) $$,
  '23503', 'Esa área ya no está en tu menú',
  'Ninguna categoría va a un área archivada'
);

select throws_ok(
  $$ update public.categorias set area_preparacion_id = 805 where id = 603 $$,
  '23503', 'Esa área ya no está en tu menú',
  'Ni se cambia a una'
);

select is(
  tests.filas($$ update public.categorias set area_preparacion_id = 802 where id = 603 $$),
  1,
  'Gerente A cambia el área de una categoría'
);


-- ─── guardar_grupo ────────────────────────────────────────────────────────────

select is(
  public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '  Término  ', 1, 1,
    '[{"nombre": "Medio"}, {"nombre": " Tres cuartos ", "precio_extra": 0}, {"nombre": "Bien cocido", "precio_extra": 5.5}]',
    '{501, 504}') > 0,
  true,
  'Gerente A arma un grupo nuevo con sus opciones y sus productos'
);

select results_eq(
  $$ select nombre, minimo, maximo, orden from public.grupos_opciones where nombre = 'Término' $$,
  $$ values ('Término'::text, 1::smallint, 1::smallint, 4) $$,
  'El grupo nuevo va al final, sin espacios sobrantes'
);

select results_eq(
  $$ select o.nombre, o.precio_extra, o.visible, o.orden
     from public.opciones o join public.grupos_opciones g on g.id = o.grupo_id
     where g.nombre = 'Término' order by o.orden $$,
  $$ values ('Medio'::text, 0.00::numeric(12,2), true, 1), ('Tres cuartos', 0.00, true, 2), ('Bien cocido', 5.50, true, 3) $$,
  'Sus opciones quedan en el orden en que llegaron, con su precio extra'
);

select set_eq(
  $$ select pg.producto_id from public.producto_grupos pg join public.grupos_opciones g on g.id = pg.grupo_id
     where g.nombre = 'Término' $$,
  array[501, 504]::bigint[],
  'Y queda puesto en sus productos'
);

select is(
  public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Salsas', 1, 2,
    '[{"id": 9012, "nombre": "Roja"}, {"id": 9011, "nombre": "Verde", "visible": false}, {"nombre": "Chipotle", "precio_extra": 5}]',
    '{501, 503}'),
  901::bigint,
  'Gerente A cambia un grupo: renombra, reacomoda, agota, agrega y quita opciones'
);

select results_eq(
  $$ select id is not null, nombre, precio_extra, visible, orden from public.opciones where grupo_id = 901 order by orden $$,
  $$ values (true, 'Roja'::text, 0.00::numeric(12,2), true, 1), (true, 'Verde', 0.00, false, 2), (true, 'Chipotle', 5.00, true, 3) $$,
  'Sus opciones quedan como llegaron'
);

select results_eq(
  $$ select array_agg(id order by orden) from public.opciones where grupo_id = 901 and id in (9011, 9012) $$,
  $$ values (array[9012, 9011]::bigint[]) $$,
  'Las opciones que ya existían conservan su id'
);

select is_empty(
  'select id from public.opciones where id = 9013',
  'La opción que no llegó se borra'
);

select results_eq(
  $$ select nombre, minimo, maximo from public.grupos_opciones where id = 901 $$,
  $$ values ('Salsas'::text, 1::smallint, 2::smallint) $$,
  'El grupo guarda su nombre y cuántas se eligen'
);

select set_eq(
  'select producto_id from public.producto_grupos where grupo_id = 901',
  array[501, 503]::bigint[],
  'Y los productos que lo llevan: se quitó de los que no llegaron y se puso en los nuevos'
);

select lives_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Salsas', 1, 2,
       '[{"id": 9012, "nombre": "Verde"}, {"id": 9011, "nombre": "Roja"}, {"nombre": "Chipotle"}]', '{501, 503}');
     set constraints all immediate $$,
  'Dos opciones pueden intercambiar sus nombres en una sola vez'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '   ', 1, 1, '[{"nombre": "Uno"}]', '{}') $$,
  '22023', 'El nombre del grupo es obligatorio',
  'Un grupo sin nombre no se guarda'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Vacío', 0, 1, '[]', '{}') $$,
  '22023', 'Agrega al menos una opción',
  'Ni uno sin opciones'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Salsa', 1, 1, '[{"nombre": "Verde"}, {"nombre": "  "}]', '{}') $$,
  '22023', 'Cada opción necesita su nombre',
  'Ni con una opción sin nombre'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Salsa', 1, 1, '[{"nombre": "Verde"}, {"nombre": " Verde "}]', '{}') $$,
  '22023', 'Ya hay una opción que se llama «Verde» en este grupo',
  'Ni con dos opciones que se llaman igual'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Descuento', 0, 1, '[{"nombre": "Sin cebolla", "precio_extra": -5}]', '{}') $$,
  '22023', 'El precio extra no puede ser negativo: una opción solo suma',
  'Una opción nunca resta'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Extras', 0, 3, '[{"nombre": "Queso"}, {"nombre": "Aguacate"}]', '{}') $$,
  '22023', 'El grupo tiene 2 opciones; no se pueden elegir más de 2',
  'El máximo nunca pasa de sus opciones'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Extras', 2, 1, '[{"nombre": "Queso"}, {"nombre": "Aguacate"}]', '{}') $$,
  '22023', 'El máximo es por lo menos 1 y nunca menos que el mínimo',
  'Ni es menos que el mínimo'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Extras', 0, 0, '[{"nombre": "Queso"}]', '{}') $$,
  '22023', 'El máximo es por lo menos 1 y nunca menos que el mínimo',
  'Ni es 0'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 'Salsa', 1, 1, '[{"id": 9021, "nombre": "Queso"}]', '{}') $$,
  '23503', 'Una de esas opciones ya no está en este grupo',
  'Un grupo nuevo no se queda con las opciones de otro'
);

select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 902, 'Extras', 0, 1, '[{"id": 9021, "nombre": "Queso"}]', '{505}') $$,
  '23503', 'Uno de esos productos ya no está en tu menú',
  'Ni se pone en un producto archivado'
);

-- Un precio que no cabe en numeric(12,2) truena al insertar, cuando el grupo ya se renombró y
-- el aguacate ya se borró.
select throws_ok(
  $$ select public.guardar_grupo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 902, 'Extras nuevos', 0, 1,
       '[{"id": 9021, "nombre": "Queso"}, {"nombre": "Caro", "precio_extra": 99999999999}]', '{}') $$,
  '22003', null,
  'Si algo truena a medio guardar…'
);

select results_eq(
  $$ select g.nombre, (select count(*) from public.opciones where grupo_id = 902), (select count(*) from public.producto_grupos where grupo_id = 902)
     from public.grupos_opciones g where g.id = 902 $$,
  $$ values ('Extras'::text, 2::bigint, 1::bigint) $$,
  '… no se guarda nada a medias'
);


-- ─── mover_grupo y eliminar_grupo ─────────────────────────────────────────────

select lives_ok(
  $$ select public.mover_grupo(902, 'arriba') $$,
  'Gerente A sube un grupo'
);

select results_eq(
  $$ select array_agg(nombre order by orden) from public.grupos_opciones $$,
  $$ values (array['Extras', 'Salsas', 'Tamaño', 'Término']) $$,
  'Los demás se recorren: ese es el orden en que Pepe elige'
);

select lives_ok(
  $$ select public.mover_grupo(902, 'arriba') $$,
  'Subir el primero no hace nada'
);

select results_eq(
  $$ select array_agg(orden order by orden) from public.grupos_opciones $$,
  $$ values (array[1, 2, 3, 4]) $$,
  'Y quedan numerados 1, 2, 3, 4'
);

select throws_ok(
  $$ select public.mover_grupo(902, 'al centro') $$,
  '22023', 'El grupo solo se mueve arriba o abajo',
  'Un grupo solo se mueve arriba o abajo'
);

select lives_ok(
  'select public.eliminar_grupo(903)',
  'Gerente A elimina un grupo que lleva un producto'
);

select results_eq(
  $$ select (select count(*) from public.grupos_opciones where id = 903), (select count(*) from public.opciones where grupo_id = 903),
            (select count(*) from public.producto_grupos where grupo_id = 903) $$,
  $$ values (0::bigint, 0::bigint, 0::bigint) $$,
  'Se borra con sus opciones y se quita de sus productos'
);

select throws_ok(
  'select public.eliminar_grupo(903)',
  '42501', null,
  'Uno que ya no existe no se vuelve a eliminar'
);


-- ─── guardar_producto ─────────────────────────────────────────────────────────

select is(
  public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 601, '  Gringa  ', '  ', 70, null, '{901, 902}') > 0,
  true,
  'Gerente A agrega un producto con sus grupos'
);

select results_eq(
  $$ select p.nombre, p.descripcion, p.precio, p.visible, p.orden = (select max(orden) from public.productos where categoria_id = 601)
     from public.productos p where p.nombre = 'Gringa' $$,
  $$ values ('Gringa'::text, null::text, 70.00::numeric(12,2), true, true) $$,
  'Se guarda limpio, a la vista y al final de su categoría'
);

select set_eq(
  $$ select pg.grupo_id from public.producto_grupos pg join public.productos p on p.id = pg.producto_id where p.nombre = 'Gringa' $$,
  array[901, 902]::bigint[],
  'Con sus grupos'
);

select is(
  public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 602, 'Taco al pastor', 'Con piña', 24.5, null, '{902}'),
  501::bigint,
  'Gerente A cambia un producto y sus grupos'
);

select results_eq(
  $$ select categoria_id, descripcion, precio, imagen_ruta = 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('ab', 16) || '.webp'
     from public.productos where id = 501 $$,
  $$ values (602::bigint, 'Con piña'::text, 24.50::numeric(12,2), true) $$,
  'Sin foto nueva, la foto se queda como estaba'
);

select set_eq(
  'select grupo_id from public.producto_grupos where producto_id = 501',
  array[902]::bigint[],
  'Y sus grupos son los que llegaron'
);

select lives_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 602, 'Taco al pastor', null, 24.5,
       'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('cd', 16) || '.webp', '{}') $$,
  'Con foto nueva, la cambia'
);

select results_eq(
  $$ select imagen_ruta = 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('cd', 16) || '.webp',
            (select count(*) from public.producto_grupos where producto_id = 501)
     from public.productos where id = 501 $$,
  $$ values (true, 0::bigint) $$,
  'Y sin grupos, el producto queda sin opciones'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 505, 601, 'Taco viejo', null, 20, null, '{}') $$,
  '23503', 'Ese producto ya no está en tu menú',
  'Un producto archivado no se cambia'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 601, 'Taco', null, 20,
       'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/menu/' || repeat('ab', 16) || '.webp', '{}') $$,
  '23514', null,
  'La foto siempre va en la carpeta de su restaurante'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 601, 'Taco', null, -1, null, '{}') $$,
  '23514', null,
  'Ni el precio es negativo'
);

select throws_ok(
  $$ select public.guardar_producto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, 601, 'Taco', null, 20, null, '{901, 903}') $$,
  '23503', 'Uno de esos grupos ya no está en tu menú',
  'Ni lleva un grupo que ya no existe; y no se guarda nada'
);

select results_eq(
  $$ select count(*) from public.productos where nombre = 'Taco' $$,
  $$ values (0::bigint) $$,
  'El producto de esa vez no quedó guardado'
);

select results_eq(
  $$ select count(*) from public.producto_grupos where producto_id = 504 $$,
  $$ values (1::bigint) $$,
  'La Coca-Cola lleva el grupo Término'
);

select results_eq(
  'select resultado from public.eliminar_producto(504)',
  $$ values ('borrado'::text) $$,
  'Un producto que nunca se vendió se borra aunque lleve grupos'
);

select is_empty(
  'select grupo_id from public.producto_grupos where producto_id = 504',
  'Y sus ligas se van con él'
);


-- ─── La red de la base ────────────────────────────────────────────────────────
-- Lo que guardar_grupo revisa antes, la base también lo cuida.

reset role;

select throws_ok(
  $$ insert into public.opciones (restaurante_id, grupo_id, nombre, orden)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 902, 'queso', 9);
     set constraints public.opciones_nombre_unico immediate $$,
  '23P01', null,
  'Dos opciones de un grupo no se llaman igual, aunque cambien las mayúsculas'
);

select throws_ok(
  $$ insert into public.opciones (restaurante_id, grupo_id, nombre, precio_extra, orden)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 902, 'Tocino', -1, 9) $$,
  '23514', null,
  'Ninguna opción resta'
);

select throws_ok(
  $$ insert into public.grupos_opciones (restaurante_id, nombre, minimo, maximo)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Raro', 2, 1) $$,
  '23514', null,
  'Ningún grupo tiene un máximo menor que su mínimo'
);

select throws_ok(
  $$ insert into public.opciones (restaurante_id, grupo_id, nombre, orden)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 911, 'Ajena', 1) $$,
  '23503', null,
  '6 · Ni una opción de A cae en un grupo de B'
);


select * from finish();

rollback;
