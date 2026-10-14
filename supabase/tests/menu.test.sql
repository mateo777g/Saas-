-- Pruebas del menú (migración menu): categorías y productos. Trae las pruebas de
-- aislamiento de la libreta 2 que tocan el menú (2, 3, 4, 5, la parte de la 6 entre
-- productos y categorías, 8, 9, 16, 18 y 22; cada descripción empieza con su número) y lo
-- decidido con la maqueta del Menú: el orden, el borrar o archivar y lo que pregunta el
-- Worker antes de subir o borrar una foto.
--
-- Escenario: los restaurantes A y B vigentes, C pausado, D venció ayer y E vence hoy; en A
-- un gerente, un mesero y un mesero dado de baja; Fragmentless; y el cliente sin sesión. A
-- tiene Tacos, Bebidas y Postres; el taco de lengua ya se vendió.
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
-- que quien prueba no alcanza a leer. tests.renglones hace de venta: lo que señala ya se
-- vendió.

create table tests.renglones (
  restaurante_id uuid not null,
  producto_id bigint not null,
  foreign key (restaurante_id, producto_id) references public.productos (restaurante_id, id)
);

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
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
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, activo) values
    (a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true),
    (a, tests.get_supabase_uid('mesero_a'), 'Mesero A', '{mesero}', true),
    (a, tests.get_supabase_uid('mesero_baja_a'), 'Mesero A dado de baja', '{mesero}', false),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.get_supabase_uid('gerente_e'), 'Gerente E', '{gerente}', true);

  -- La tableta compartida de A, con la sesión del mesero: así entra el personal (migración empleados).
  insert into public.dispositivos (restaurante_id, nombre, token_hash, sesion_id)
  values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Tableta caja', repeat('a', 64), '5e5e5e5e-0000-4000-8000-00000000000a');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (901, a, 'Tacos', 'taco'),
    (902, a, 'Bebidas', 'refresco'),
    (903, a, 'Postres', 'postre'),
    (911, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Tortas', 'torta'),
    (921, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Pozoles', 'sopa'),
    (931, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Caldos', 'sopa'),
    (941, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Gorditas', 'comida');

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, imagen_ruta, visible) overriding system value values
    (801, a, 901, 'Taco al pastor', 22, null, true),
    (802, a, 901, 'Taco de lengua', 30, 'restaurantes/' || a || '/menu/' || repeat('b', 32) || '.webp', true),
    (803, a, 902, 'Horchata', 30, 'restaurantes/' || a || '/menu/' || repeat('a', 32) || '.webp', true),
    (804, a, 903, 'Flan', 40, 'restaurantes/' || a || '/menu/' || repeat('d', 32) || '.webp', false),
    (811, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 911, 'Torta cubana', 95, null, true),
    (821, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 921, 'Pozole rojo', 120, null, true),
    (831, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 931, 'Caldo de res', 110, null, true),
    (841, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 941, 'Gordita de chicharrón', 35, null, true);

  -- El taco de lengua ya se vendió.
  insert into tests.renglones (restaurante_id, producto_id) values (a, 802);
end;
$$;

select plan(75);


-- ─── 1 · Permisos ─────────────────────────────────────────────────────────────

select ok(
  not has_table_privilege('authenticated', 'public.categorias', 'DELETE')
  and not has_table_privilege('authenticated', 'public.productos', 'DELETE'),
  '1 · Nadie con sesión borra directo del menú: lo hacen las funciones'
);

select is_empty(
  $$ select t.tabla || '.' || c.columna || ' ' || p.permiso
     from unnest(array['public.categorias', 'public.productos']) as t(tabla),
          unnest(array['orden', 'archivado_at', 'restaurante_id', 'id', 'created_at', 'updated_at']) as c(columna),
          unnest(array['INSERT', 'UPDATE']) as p(permiso)
     where has_column_privilege('authenticated', t.tabla, c.columna, p.permiso)
       and not (c.columna = 'restaurante_id' and p.permiso = 'INSERT') $$,
  '1 · Nadie con sesión escribe el orden, el archivado, el restaurante ni las fechas de una fila del menú'
);

select ok(
  has_function_privilege('authenticated', 'public.mover_categoria(bigint, text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.eliminar_producto(bigint)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.eliminar_categoria(bigint)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.puedo_subir_foto(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.puedo_borrar_foto(text)', 'EXECUTE'),
  '1 · Las 5 funciones del menú las llama quien tiene sesión, y cada una revisa quién es'
);


-- ─── 2 · Quién lee el menú ────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select set_eq(
  'select nombre from public.categorias',
  array['Tacos', 'Bebidas', 'Postres'],
  '2 · Gerente A lee las 3 categorías de A y ninguna de otro restaurante'
);

select set_eq(
  'select nombre from public.productos',
  array['Taco al pastor', 'Taco de lengua', 'Horchata', 'Flan'],
  '2 · Gerente A lee los 4 productos de A, el oculto también'
);

select results_eq(
  'select nombre, orden from public.categorias order by orden',
  $$ values ('Tacos'::text, 1), ('Bebidas', 2), ('Postres', 3) $$,
  'Las categorías quedaron numeradas en el orden en que se crearon'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select set_eq(
  'select nombre from public.productos',
  array['Taco al pastor', 'Taco de lengua', 'Horchata', 'Flan'],
  '2 · El mesero de A también lee el menú de A'
);

select tests.authenticate_as('gerente_b');

select set_eq(
  'select nombre from public.categorias union all select nombre from public.productos',
  array['Tortas', 'Torta cubana'],
  '2 · Gerente B lee solo su menú'
);

select tests.authenticate_as('fragmentless');

select is_empty(
  'select id from public.categorias union all select id from public.productos',
  '18 · Fragmentless no lee el menú de ningún cliente'
);


-- ─── 3 · Escribir en un restaurante ajeno, o sin ser gerente ──────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Intrusa', 'taco') $$,
  '42501', null,
  '3 · Gerente A no crea categorías en B'
);

select throws_ok(
  $$ insert into public.productos (restaurante_id, categoria_id, nombre, precio)
     values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 911, 'Intruso', 10) $$,
  '42501', null,
  '3 · Gerente A no crea productos en B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Del mesero', 'taco') $$,
  '42501', null,
  '3 · El mesero de A no crea categorías en A'
);

select is(
  tests.filas($$ update public.productos set precio = 1 where id = 801 $$),
  0,
  '3 · El mesero de A no cambia precios'
);


-- ─── 4 · Cambiar o borrar lo de B ─────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select is(
  tests.filas($$ update public.productos set precio = 1 where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$),
  0,
  '4 · Gerente A no cambia ningún producto de B'
);

select is(
  tests.filas($$ update public.categorias set nombre = 'Hackeada' where id = 911 $$),
  0,
  '4 · Ni ninguna categoría de B'
);

select throws_ok(
  $$ delete from public.productos where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '42501', null,
  '4 · Ni borra productos de B'
);

select tests.authenticate_as('gerente_b');

select results_eq(
  'select c.nombre, p.nombre, p.precio from public.productos p join public.categorias c on c.id = p.categoria_id',
  $$ values ('Tortas'::text, 'Torta cubana'::text, 95.00::numeric) $$,
  '4 · Revisado como B, su menú sigue igual'
);


-- ─── 5 y 6 · Pasar filas a B ──────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ update public.productos set restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' where id = 801 $$,
  '42501', null,
  '5 · Gerente A no pasa un producto suyo a B'
);

select throws_ok(
  $$ insert into public.productos (restaurante_id, categoria_id, nombre, precio)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 911, 'Torta ajena', 10) $$,
  '23503', null,
  '6 · Un producto de A no entra en una categoría de B'
);

select throws_ok(
  $$ update public.productos set categoria_id = 911 where id = 801 $$,
  '23503', null,
  '6 · Ni se cambia a una categoría de B'
);


-- ─── 8, 9 y 22 · Licencia y bajas ─────────────────────────────────────────────

select tests.authenticate_as('gerente_c');

select is_empty(
  'select id from public.categorias union all select id from public.productos',
  '8 · Gerente C, con la licencia pausada, no ve su menú'
);

select throws_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Nueva', 'sopa') $$,
  '42501', null,
  '8 · Ni lo cambia'
);

select tests.authenticate_as('mesero_baja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select is_empty(
  'select id from public.categorias union all select id from public.productos',
  '9 · El mesero de A dado de baja no ve el menú'
);

select tests.authenticate_as('gerente_d');

select is_empty(
  'select id from public.categorias union all select id from public.productos',
  '22 · Gerente D, que venció ayer, no ve su menú'
);

select tests.authenticate_as('gerente_e');

select set_eq(
  'select nombre from public.productos',
  array['Gordita de chicharrón'],
  '22 · Gerente E, que vence hoy, todavía ve el suyo'
);


-- ─── 16 · Sin sesión ──────────────────────────────────────────────────────────

select tests.clear_authentication();

select throws_ok(
  'select id from public.productos',
  '42501', null,
  '16 · Sin sesión no se lee el menú directo'
);

select throws_ok(
  $$ select public.puedo_subir_foto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null,
  '16 · Ni se llama una función del menú'
);


-- ─── Lo que la base pone sola ─────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  Antojitos  ', 'comida') $$,
  'Gerente A crea una categoría'
);

select results_eq(
  $$ select nombre, orden from public.categorias where nombre = 'Antojitos' $$,
  $$ values ('Antojitos'::text, 4) $$,
  'Se guarda sin espacios sobrantes y al final del menú'
);

select throws_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'tacos', 'taco') $$,
  '23505', null,
  'No hay dos categorías con el mismo nombre, aunque cambien las mayúsculas'
);

select throws_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Donas', 'dona') $$,
  '23514', null,
  'Solo se acepta uno de los 28 íconos'
);

select throws_ok(
  $$ update public.categorias set nombre = '   ' where id = 901 $$,
  '23514', null,
  'Una categoría no se queda sin nombre'
);

select lives_ok(
  $$ insert into public.productos (restaurante_id, categoria_id, nombre, descripcion, precio)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Taco de suadero', '   ', 22.5) $$,
  'Gerente A agrega un producto a Tacos'
);

select results_eq(
  $$ select descripcion is null, orden, visible, precio from public.productos where nombre = 'Taco de suadero' $$,
  $$ values (true, 3, true, 22.50::numeric) $$,
  'Va al final de Tacos, visible, y la descripción en blanco queda vacía'
);

select throws_ok(
  'select public.eliminar_categoria(901)',
  '55000',
  'Tacos todavía tiene 3 productos; muévelos a otra categoría o elimínalos primero',
  'Tacos tiene productos: no se elimina'
);

select throws_ok(
  $$ update public.productos set precio = -1 where id = 801 $$,
  '23514', null,
  'El precio no puede ser negativo'
);

select lives_ok(
  $$ update public.productos set categoria_id = 902 where nombre = 'Taco de suadero' $$,
  'Gerente A pasa el taco de suadero a Bebidas'
);

select results_eq(
  $$ select orden from public.productos where nombre = 'Taco de suadero' $$,
  array[2],
  'Al cambiar de categoría se va al final de la nueva'
);

select throws_ok(
  format(
    'update public.productos set imagen_ruta = %L where id = 801',
    'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/menu/' || repeat('c', 32) || '.webp'
  ),
  '23514', null,
  'La foto tiene que estar en la carpeta del menú de su restaurante'
);

select throws_ok(
  $$ update public.productos set imagen_ruta = 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/foto.webp' where id = 801 $$,
  '23514', null,
  'Y con el nombre que le pone el Worker'
);

select is(
  tests.filas(format(
    'update public.productos set imagen_ruta = %L where id = 801',
    'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('c', 32) || '.webp'
  )),
  1,
  'Una foto en su carpeta y con el nombre del Worker se guarda'
);


-- ─── mover_categoria ──────────────────────────────────────────────────────────

select lives_ok(
  $$ select public.mover_categoria(902, 'arriba') $$,
  'Gerente A sube Bebidas'
);

select results_eq(
  'select nombre from public.categorias where archivado_at is null order by orden',
  array['Bebidas', 'Tacos', 'Postres', 'Antojitos'],
  'Bebidas sube un lugar y Tacos baja'
);

select lives_ok(
  $$ select public.mover_categoria(902, 'arriba') $$,
  'Subir la primera no da error'
);

select results_eq(
  'select nombre, orden from public.categorias where archivado_at is null order by orden',
  $$ values ('Bebidas'::text, 1), ('Tacos', 2), ('Postres', 3), ('Antojitos', 4) $$,
  'En la orilla no pasa nada'
);

select throws_ok(
  $$ select public.mover_categoria(902, 'izquierda') $$,
  '22023', null,
  'Una categoría solo se mueve arriba o abajo'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  $$ select public.mover_categoria(901, 'abajo') $$,
  '42501', null,
  'El mesero no reacomoda el menú'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.mover_categoria(901, 'abajo') $$,
  '42501', null,
  'Gerente B no reacomoda el menú de A'
);


-- ─── eliminar_producto ────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select results_eq(
  'select resultado, imagen_ruta from public.eliminar_producto(803)',
  format($$ values ('borrado'::text, %L::text) $$,
         'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('a', 32) || '.webp'),
  'La horchata nunca se vendió: se borra y regresa la ruta de su foto para el Worker'
);

select is_empty(
  'select id from public.productos where id = 803',
  'Y ya no está'
);

select results_eq(
  'select resultado, imagen_ruta from public.eliminar_producto(802)',
  $$ values ('archivado'::text, null::text) $$,
  'El taco de lengua ya se vendió: se archiva'
);

select results_eq(
  'select archivado_at is not null from public.productos where id = 802',
  array[true],
  'Y sigue en la tabla, para los reportes'
);

select is(
  tests.filas($$ update public.productos set precio = 1 where id = 802 $$),
  0,
  'Un producto archivado ya no se cambia'
);

select throws_ok(
  'select * from public.eliminar_producto(802)',
  '42501', null,
  'Ni se vuelve a eliminar'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  'select * from public.eliminar_producto(801)',
  '42501', null,
  'El mesero no elimina productos'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  'select * from public.eliminar_producto(801)',
  '42501', null,
  'Gerente B no elimina productos de A'
);


-- ─── eliminar_categoria ───────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  'select public.eliminar_categoria(903)',
  '55000',
  'Postres todavía tiene 1 producto; muévelo a otra categoría o elimínalo primero',
  'Postres tiene el flan, aunque esté oculto: no se elimina'
);

select results_eq(
  $$ select public.eliminar_categoria(id) from public.categorias where nombre = 'Antojitos' $$,
  array['borrado'],
  'Antojitos no tiene productos: se borra'
);

select results_eq(
  'select resultado from public.eliminar_producto(801)',
  array['borrado'],
  'Gerente A elimina el taco al pastor, que nunca se vendió'
);

select results_eq(
  'select public.eliminar_categoria(901)',
  array['archivado'],
  'A Tacos solo le queda el taco de lengua, archivado: Tacos se archiva'
);

select lives_ok(
  $$ insert into public.categorias (restaurante_id, nombre, icono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Tacos', 'taco') $$,
  'El nombre de una categoría archivada se puede volver a usar'
);

select throws_ok(
  $$ insert into public.productos (restaurante_id, categoria_id, nombre, precio)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 901, 'Taco de tripa', 28) $$,
  '23503',
  'Esa categoría ya no está en tu menú',
  'Nada entra en una categoría archivada'
);

select is(
  tests.filas($$ update public.categorias set nombre = 'Tacos viejos' where id = 901 $$),
  0,
  'Una categoría archivada ya no se cambia'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select throws_ok(
  'select public.eliminar_categoria(903)',
  '42501', null,
  'El mesero no elimina categorías'
);


-- ─── Fotos: lo que pregunta el Worker ─────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select ok(
  public.puedo_subir_foto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'Gerente A sube fotos al menú de A'
);

select ok(
  not public.puedo_subir_foto('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'Al de B no'
);

select ok(
  not public.puedo_subir_foto(null),
  'Sin restaurante tampoco'
);

select ok(
  not public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('d', 32) || '.webp'),
  'La foto del flan, que está en el menú, no se borra'
);

select ok(
  not public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('b', 32) || '.webp'),
  'La del taco de lengua, archivado, tampoco: se queda con él'
);

select ok(
  public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('a', 32) || '.webp'),
  'La de la horchata, ya eliminada, sí se borra'
);

select ok(
  not public.puedo_borrar_foto('restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/menu/' || repeat('e', 32) || '.webp'),
  'Una de la carpeta de B no'
);

select ok(
  not public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/../../bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/menu/x.webp'),
  'Ni una ruta inventada'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-00000000000a');

select ok(
  not public.puedo_subir_foto('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'El mesero no sube fotos'
);

select ok(
  not public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('a', 32) || '.webp'),
  'Ni las borra'
);

select tests.authenticate_as('gerente_c');

select ok(
  not public.puedo_subir_foto('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  'Con la licencia pausada no se suben fotos'
);


select * from finish();

rollback;
