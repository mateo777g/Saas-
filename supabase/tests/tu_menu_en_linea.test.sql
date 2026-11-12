-- Pruebas de la migración tu_menu_en_linea (10 al 12 de noviembre de 2026): las formas del menú digital,
-- una columna por cosa en restaurantes con su regla, que nacen como la maqueta y se guardan todas juntas
-- con guardar_menu_en_linea; «Hago envíos» en Tu restaurante; los carteles que son un producto de Mi menú
-- (con foto, sin repetirse, que se van con su producto y solo salen si el producto sale en el menú), y el
-- teléfono que se pide también para llevar.
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
-- Se siembra como postgres, con ids fijos. A es la fonda de Don Chuy: recibe pedidos ahora (su horario
-- va de 3 horas antes a 3 horas después de este momento, todos los días), hace envíos y tiene un cartel
-- subido. En A: Don Chuy (gerente) y Pepe (mesero, en su celular). B es otro restaurante con su gerente.
-- El menú de A: Taco al pastor con foto, Gringa sin foto, Taco oculto con foto, Quesadilla con foto pero
-- agotada por su grupo, el envío, Taco viejo archivado con foto, Flan y Horchata con foto.

create function tests.ruta(p_restaurante_id uuid, p_carpeta text, p_n integer)
returns text
language sql
immutable
as $$
  select 'restaurantes/' || p_restaurante_id || '/' || p_carpeta || '/' || lpad(p_n::text, 32, '0') || '.webp'
$$;

-- Un pedido como lo manda el Worker, a nombre de Rosa Ramírez, cada vez desde un celular y una conexión
-- nuevos.
create function tests.pedir(
  p_tipo text,
  p_telefono text,
  p_direccion text default null,
  p_referencias text default null,
  p_paga_con numeric default null
)
returns jsonb
language sql
as $$
  select public.hacer_pedido('fonda-don-chuy', gen_random_uuid(), p_tipo, 'Rosa Ramírez', p_telefono, p_direccion,
                             p_referencias, p_paga_con, '[{"producto_id": 501, "cantidad": 1, "precio": 22}]',
                             encode(extensions.gen_random_bytes(32), 'hex'), encode(extensions.gen_random_bytes(32), 'hex'))
$$;

-- «Guardar» de Tu menú en línea con todas las formas en una lista, en el orden de la función.
create function tests.guardar_formas(p_restaurante_id uuid, f jsonb)
returns void
language sql
as $$
  select public.guardar_menu_en_linea(
    p_restaurante_id, f ->> 'tema', f ->> 'color', f ->> 'color_barra', f ->> 'fondo', f ->> 'barra',
    (f ->> 'con_nombre')::boolean, f ->> 'idioma', f ->> 'moneda', f ->> 'busqueda', f ->> 'carteles', f ->> 'info',
    f ->> 'info_lugar', f ->> 'carteles_producto', f ->> 'categorias',
    array(select jsonb_array_elements_text(f -> 'orden')), f ->> 'titulos', f ->> 'productos', f ->> 'abajo',
    (f ->> 'abajo_con_nombres')::boolean, f ->> 'producto_ventana', f ->> 'producto_titulo', f ->> 'producto_opciones')
$$;

-- Las formas de un restaurante, como las guarda la tabla.
create function tests.formas(p_restaurante_id uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'tema', menu_tema, 'color', menu_color, 'color_barra', menu_color_barra, 'fondo', menu_fondo,
    'barra', menu_barra, 'con_nombre', menu_con_nombre, 'idioma', menu_idioma, 'moneda', menu_moneda,
    'busqueda', menu_busqueda, 'carteles', menu_carteles, 'info', menu_info, 'info_lugar', menu_info_lugar,
    'carteles_producto', menu_carteles_producto, 'categorias', menu_categorias, 'orden', to_jsonb(menu_orden),
    'titulos', menu_titulos, 'productos', menu_productos, 'abajo', menu_abajo,
    'abajo_con_nombres', menu_abajo_con_nombres, 'producto_ventana', menu_producto_ventana,
    'producto_titulo', menu_producto_titulo, 'producto_opciones', menu_producto_opciones)
  from public.restaurantes
  where id = p_restaurante_id
$$;

-- Las formas con que nace un menú, y las de Don Chuy cuando cambia todas.
create function tests.de_nacimiento()
returns jsonb
language sql
immutable
as $$
  select '{"tema": "claro", "color": null, "color_barra": null, "fondo": null, "barra": "izquierda",
           "con_nombre": true, "idioma": "letras", "moneda": "letras", "busqueda": "gris", "carteles": "esquinas",
           "info": "capsula", "info_lugar": "arriba", "carteles_producto": "nombre", "categorias": "pestanas",
           "orden": ["carteles", "busqueda", "categorias"], "titulos": "icono", "productos": "a_lo_largo",
           "abajo": "barra", "abajo_con_nombres": true, "producto_ventana": "completa", "producto_titulo": "abajo",
           "producto_opciones": "juntas"}'::jsonb
$$;

create function tests.de_don_chuy()
returns jsonb
language sql
immutable
as $$
  select '{"tema": "oscuro", "color": "#B3261E", "color_barra": "#1F2A44", "fondo": "#F4F1EA", "barra": "centro",
           "con_nombre": false, "idioma": "cuadro", "moneda": "monedas", "busqueda": "tarjeta", "carteles": "bajito",
           "info": "icono", "info_lugar": "abajo", "carteles_producto": "foto", "categorias": "pildoras",
           "orden": ["categorias", "carteles", "busqueda"], "titulos": "raya", "productos": "clasicas",
           "abajo": "pildora", "abajo_con_nombres": false, "producto_ventana": "ventana", "producto_titulo": "arriba",
           "producto_opciones": "pasos"}'::jsonb
$$;

-- Los carteles de A, en su orden: la imagen o el producto de cada uno.
create function tests.carteles_a()
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(jsonb_build_object('imagen', c.imagen_ruta, 'producto', c.producto_id)
                            order by c.orden, c.id), '[]')
  from public.carteles c
  where c.restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
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
  v_local timestamp := now() at time zone 'America/Mexico_City';
begin
  perform tests.create_supabase_user('gerente_a', 'gerente.a@prueba.test');
  perform tests.create_supabase_user('mesero_a', 'mesero.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, telefono, hace_envios) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, '2221234567', true),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, '2227654321', false);

  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select a, x, date_trunc('minute', v_local - interval '3 hours')::time, date_trunc('minute', v_local + interval '3 hours')::time
  from generate_series(1, 7) as x;

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo, pin_hash) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true, null),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Pepe', '{mesero}', true, 'pin'),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true, null);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, privado.huella_aparato(repeat('P', 43)), '5e5e5e5e-0000-4000-8000-000000000001');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Tacos', 'taco'), (602, a, 'Envíos', 'especialidad'), (611, b, 'Tacos B', 'taco');

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, imagen_ruta, es_envio)
  overriding system value values
    (501, a, 601, 'Taco al pastor', 22, tests.ruta(a, 'menu', 1), false),
    (502, a, 601, 'Gringa', 75, null, false),
    (503, a, 601, 'Taco oculto', 22, tests.ruta(a, 'menu', 3), false),
    (504, a, 601, 'Quesadilla', 40, tests.ruta(a, 'menu', 4), false),
    (505, a, 602, 'Envío', 30, null, true),
    (506, a, 601, 'Taco viejo', 20, tests.ruta(a, 'menu', 6), false),
    (507, a, 601, 'Flan', 35, tests.ruta(a, 'menu', 7), false),
    (508, a, 601, 'Horchata', 30, tests.ruta(a, 'menu', 8), false),
    (511, b, 611, 'Taco B', 25, tests.ruta(b, 'menu', 1), false);
  update public.productos set visible = false where id = 503;
  update public.productos set archivado_at = now() where id = 506;

  -- La quesadilla está agotada por su grupo: su única tortilla está agotada.
  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (903, a, 'Tortilla', 1, 1);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9031, a, 903, 'Maíz', 0, false, 1);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values (a, 504, 903);

  insert into public.carteles (id, restaurante_id, imagen_ruta, orden) overriding system value values
    (701, a, tests.ruta(a, 'carteles', 1), 1);

  insert into public.mesas (id, restaurante_id, nombre) overriding system value values (801, a, 'Mesa 1');
end;
$$;

select plan(142);


-- ─── Las formas: columnas, permisos y reglas ──────────────────────────────────

select is(
  tests.formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  tests.de_nacimiento(),
  'Un menú nace con las formas de la maqueta: la barra como app, el logo a la izquierda, todo como hoy'
);

select ok(
  (select bool_and(has_column_privilege('authenticated', 'public.restaurantes', c, 'SELECT')
                   and not has_column_privilege('authenticated', 'public.restaurantes', c, 'UPDATE')
                   and not has_column_privilege('authenticated', 'public.restaurantes', c, 'INSERT')
                   and not has_column_privilege('anon', 'public.restaurantes', c, 'SELECT'))
   from unnest(array[
     'menu_color_barra', 'menu_fondo', 'menu_barra', 'menu_con_nombre', 'menu_idioma', 'menu_moneda',
     'menu_busqueda', 'menu_carteles', 'menu_info', 'menu_info_lugar', 'menu_carteles_producto',
     'menu_categorias', 'menu_orden', 'menu_titulos', 'menu_productos', 'menu_abajo', 'menu_abajo_con_nombres',
     'menu_producto_ventana', 'menu_producto_titulo', 'menu_producto_opciones']) as c),
  'Las 20 columnas nuevas las lee quien tiene sesión, como el tema y el color; nadie las escribe directo'
);

select ok(
  has_column_privilege('authenticated', 'public.carteles', 'producto_id', 'SELECT')
  and not has_column_privilege('authenticated', 'public.carteles', 'producto_id', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.carteles', 'producto_id', 'INSERT')
  and not has_column_privilege('anon', 'public.carteles', 'producto_id', 'SELECT'),
  'El producto de un cartel se lee con sesión y no se escribe directo'
);

select is_empty(
  $$ select f from unnest(array[
       'public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean)',
       'public.guardar_menu_en_linea(uuid, text, text, text, text, text, boolean, text, text, text, text, text, text, text, text, text[], text, text, text, boolean, text, text, text)',
       'public.agregar_cartel(uuid, text, bigint)',
       'public.cambiar_cartel(bigint, text, bigint)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE')
        or has_function_privilege('service_role', f, 'EXECUTE') $$,
  'Las 4 funciones que cambian las llama quien tiene sesión; sin sesión no, ni con la llave del Worker'
);

select ok(
  to_regprocedure('public.guardar_menu_en_linea(uuid, text, text, boolean)') is null
  and to_regprocedure('public.guardar_restaurante(uuid, text, text, text, text, jsonb)') is null
  and to_regprocedure('public.agregar_cartel(uuid, text)') is null
  and to_regprocedure('public.cambiar_cartel(bigint, text)') is null,
  'Las versiones de antes ya no existen («Hago envíos» ya no está en Tu menú en línea)'
);

select ok(
  not has_function_privilege('anon', 'privado.revisar_producto_cartel(uuid, bigint, bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'privado.revisar_producto_cartel(uuid, bigint, bigint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'privado.revisar_producto_cartel(uuid, bigint, bigint)', 'EXECUTE'),
  'La revisión del producto de un cartel no la llama nadie de fuera'
);

-- Cada valor de la lista entra, y uno que no está se rechaza con su regla.
select lives_ok(
  format($$ update public.restaurantes set %I = %L where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, x.columna, x.valor),
  format('%s acepta «%s»', x.columna, x.valor)
)
from (values
  ('menu_barra', 'izquierda'), ('menu_barra', 'centro'),
  ('menu_idioma', 'letras'), ('menu_idioma', 'planeta'), ('menu_idioma', 'cuadro'),
  ('menu_moneda', 'letras'), ('menu_moneda', 'monedas'), ('menu_moneda', 'cuadro'),
  ('menu_busqueda', 'gris'), ('menu_busqueda', 'blanca'), ('menu_busqueda', 'tarjeta'),
  ('menu_carteles', 'esquinas'), ('menu_carteles', 'completo'), ('menu_carteles', 'bajito'),
  ('menu_info', 'capsula'), ('menu_info', 'icono'),
  ('menu_info_lugar', 'arriba'), ('menu_info_lugar', 'abajo'),
  ('menu_carteles_producto', 'nombre'), ('menu_carteles_producto', 'foto'),
  ('menu_categorias', 'pestanas'), ('menu_categorias', 'rectangulos'), ('menu_categorias', 'tarjeta'),
  ('menu_categorias', 'pildoras'), ('menu_categorias', 'circulos_icono'), ('menu_categorias', 'circulos_foto'),
  ('menu_titulos', 'icono'), ('menu_titulos', 'nombre'), ('menu_titulos', 'raya'),
  ('menu_productos', 'a_lo_largo'), ('menu_productos', 'intercalado'), ('menu_productos', 'dos_en_dos'),
  ('menu_productos', 'clasicas'),
  ('menu_abajo', 'barra'), ('menu_abajo', 'pildora'),
  ('menu_producto_ventana', 'completa'), ('menu_producto_ventana', 'ventana'),
  ('menu_producto_titulo', 'abajo'), ('menu_producto_titulo', 'arriba'),
  ('menu_producto_opciones', 'juntas'), ('menu_producto_opciones', 'pasos'),
  ('menu_color_barra', '#1F2A44'), ('menu_fondo', '#F4F1EA')
) as x (columna, valor);

select throws_ok(
  format($$ update public.restaurantes set %I = %L where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, x.columna, x.valor),
  '23514',
  format('new row for relation "restaurantes" violates check constraint "restaurantes_%s_%s"', x.columna, x.regla),
  format('%s no acepta «%s»', x.columna, x.valor)
)
from (values
  ('menu_barra', 'derecha', 'lista'),
  ('menu_idioma', 'banderas', 'lista'),
  ('menu_moneda', 'planeta', 'lista'),
  ('menu_busqueda', 'lupa', 'lista'),
  ('menu_carteles', 'grande', 'lista'),
  ('menu_info', 'capsula_blanca', 'lista'),
  ('menu_info_lugar', 'en_medio', 'lista'),
  ('menu_carteles_producto', 'precio', 'lista'),
  ('menu_categorias', 'circulos', 'lista'),
  ('menu_titulos', 'grande', 'lista'),
  ('menu_productos', 'tres_en_tres', 'lista'),
  ('menu_abajo', 'flotante', 'lista'),
  ('menu_producto_ventana', 'hoja', 'lista'),
  ('menu_producto_titulo', 'en_medio', 'lista'),
  ('menu_producto_opciones', 'una_por_una', 'lista'),
  ('menu_color_barra', '#1f2a44', 'formato'),
  ('menu_fondo', 'blanco', 'formato'),
  ('menu_fondo', '#f4f1ea', 'formato')
) as x (columna, valor, regla);

select throws_ok(
  format($$ update public.restaurantes set menu_orden = %L where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$, x.orden),
  '23514',
  'new row for relation "restaurantes" violates check constraint "restaurantes_menu_orden_lista"',
  x.que
)
from (values
  ('{carteles,busqueda}', 'El orden lleva las tres piezas'),
  ('{carteles,busqueda,busqueda}', 'Cada pieza va una vez'),
  ('{carteles,busqueda,categorias,productos}', 'Solo esas tres'),
  ('{carteles,busqueda,banner}', 'Una pieza que no existe no entra')
) as x (orden, que);

select lives_ok(
  $$ update public.restaurantes set menu_orden = '{busqueda,categorias,carteles}' where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  'Las tres piezas en cualquier orden'
);

select throws_ok(
  $$ update public.restaurantes set menu_con_nombre = null where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  '23502', null,
  'Las formas nunca van vacías'
);


-- ─── «Guardar» de Tu menú en línea ────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       tests.de_don_chuy() || '{"color": " #b3261e ", "color_barra": "#1f2a44", "fondo": "#f4f1ea "}') $$,
  'Don Chuy cambia todas las formas y los tres colores de un solo «Guardar»'
);

select is(
  tests.formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  tests.de_don_chuy(),
  'Se guardan todas, con los colores sin espacios y en mayúsculas'
);

select lives_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       tests.de_don_chuy() || '{"color": "", "color_barra": " ", "fondo": null}') $$,
  'Y puede quitar los colores'
);

select is(
  tests.formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  tests.de_don_chuy() || '{"color": null, "color_barra": null, "fondo": null}',
  'Sin colores, los de siempre; las formas se quedan'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() || '{"color_barra": "azul"}') $$,
  '22023', 'El color de la barra no se entiende; escríbelo como #B3261E',
  'Un color de barra que no es #RRGGBB no se guarda'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() || '{"fondo": "#FFF"}') $$,
  '22023', 'El color del fondo no se entiende; escríbelo como #F4F1EA',
  'Un fondo que no es #RRGGBB tampoco'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() || '{"color": "rojo"}') $$,
  '22023', 'Ese color no se entiende; escríbelo como #B3261E',
  'Ni el color de siempre'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() || '{"tema": "sepia"}') $$,
  '22023', 'El menú se ve claro u oscuro',
  'El tema sigue siendo claro u oscuro'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() || '{"busqueda": "lupa"}') $$,
  '23514', null,
  'Una forma que ya no existe (la lupa sola) no se guarda'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() - 'producto_opciones') $$,
  '23502', null,
  'Ni una forma vacía'
);

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy() || '{"orden": ["carteles", "carteles", "busqueda"]}') $$,
  '23514', null,
  'Ni un orden con una pieza repetida'
);

select is(
  tests.formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  tests.de_don_chuy() || '{"color": null, "color_barra": null, "fondo": null}',
  'Lo rechazado no cambia nada'
);

select throws_ok(
  $$ select tests.guardar_formas('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.de_don_chuy()) $$,
  '42501', null,
  'Don Chuy no cambia el menú de B'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_nacimiento()) $$,
  '42501', null,
  'Ni Pepe, el mesero'
);

reset role;

select is(
  tests.formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  tests.de_don_chuy() || '{"color": null, "color_barra": null, "fondo": null}',
  'Lo de A sigue como lo dejó Don Chuy'
);

-- Para lo que sigue, A con sus colores otra vez.
select tests.authenticate_as('gerente_a');
select tests.guardar_formas('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.de_don_chuy());
reset role;


-- ─── «Hago envíos», en Tu restaurante ─────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select lives_ok(
  $$ select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', '2221234567',
       null, null, '[]', false) $$,
  'Don Chuy apaga «Hago envíos» desde Tu restaurante'
);

select is(
  (select hace_envios from public.restaurantes where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  false,
  '«Hago envíos» queda apagado'
);

-- Lo vuelve a prender, con su horario de siempre (guardar reescribe el horario).
select public.guardar_restaurante('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', '2221234567', null, null,
  (select jsonb_agg(jsonb_build_object('dia', x, 'abre', to_char(now() at time zone 'America/Mexico_City' - interval '3 hours', 'HH24:MI'),
                                       'cierra', to_char(now() at time zone 'America/Mexico_City' + interval '3 hours', 'HH24:MI')))
   from generate_series(1, 7) as x),
  true);

reset role;


-- ─── «Tus carteles»: una imagen o un producto ─────────────────────────────────

select tests.authenticate_as('gerente_a');

select tests.guardar('cartel_pastor', public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501));

select is(
  tests.carteles_a(),
  jsonb_build_array(
    jsonb_build_object('imagen', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 1), 'producto', null),
    jsonb_build_object('imagen', null, 'producto', 501)),
  'Don Chuy pone la foto del taco al pastor como cartel: va al final, sin imagen propia'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) $$,
  '23505', 'Ese producto ya está en tus carteles.',
  'Un producto no se repite en los carteles'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 502) $$,
  '22023', 'Ese producto no tiene foto. Ponle una en Mi menú.',
  'Un producto sin foto no es cartel'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 506) $$,
  '22023', 'Ese producto ya no está en tu menú.',
  'Ni uno archivado'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 505) $$,
  '22023', 'Ese producto ya no está en tu menú.',
  'Ni el envío'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 511) $$,
  '22023', 'Ese producto ya no está en tu menú.',
  'Ni un producto de B'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2), 507) $$,
  '22023', 'Un cartel lleva una imagen o un producto',
  'Un cartel no lleva imagen y producto a la vez'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  ') $$,
  '22023', 'Un cartel lleva una imagen o un producto',
  'Ni ninguno de los dos'
);

select lives_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2)) $$,
  'Subir una imagen sigue igual que antes'
);

select lives_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 503) $$,
  'Un producto oculto con foto sí se puede poner (sale en el menú cuando se vuelva a ver)'
);

select tests.guardar('cartel_quesadilla', public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 504));

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 507) $$,
  '55000', 'Ya tienes 5 carteles. Quita uno para agregar otro.',
  'Con 5 carteles ya no cabe otro, tampoco de producto'
);

select is(
  public.cambiar_cartel(701, p_producto_id => 507),
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 1),
  '«Cambiar» la primera imagen por el flan regresa la imagen de antes, para borrarla de R2'
);

select is(
  public.cambiar_cartel(tests.id('cartel_pastor'), tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 3)),
  null,
  '«Cambiar» el taco al pastor por una imagen no deja nada que borrar'
);

select is(
  public.cambiar_cartel(tests.id('cartel_pastor'), tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 3)),
  null,
  '«Cambiar» por la misma imagen tampoco'
);

select throws_ok(
  format($$ select public.cambiar_cartel(%s, p_producto_id => 507) $$, tests.id('cartel_quesadilla')),
  '23505', 'Ese producto ya está en tus carteles.',
  '«Cambiar» a un producto que ya está en otro cartel no se puede'
);

select is(
  public.cambiar_cartel(701, p_producto_id => 507),
  null,
  'Al mismo producto que ya tiene, sí (no cambia nada)'
);

select throws_ok(
  $$ select public.cambiar_cartel(701) $$,
  '22023', 'Un cartel lleva una imagen o un producto',
  '«Cambiar» sin imagen ni producto no se puede'
);

select is(
  tests.carteles_a(),
  jsonb_build_array(
    jsonb_build_object('imagen', null, 'producto', 507),
    jsonb_build_object('imagen', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 3), 'producto', null),
    jsonb_build_object('imagen', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2), 'producto', null),
    jsonb_build_object('imagen', null, 'producto', 503),
    jsonb_build_object('imagen', null, 'producto', 504)),
  'Cada cartel cambió en su mismo lugar'
);

select is(
  public.quitar_cartel(tests.id('cartel_quesadilla')),
  null,
  '«Quitar» un cartel de producto no deja imagen que borrar'
);

select tests.authenticate_as('gerente_b');

select throws_ok(
  $$ select public.cambiar_cartel(701, p_producto_id => 511) $$,
  '42501', null,
  'B no cambia un cartel de A'
);

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) $$,
  '42501', null,
  'Ni agrega uno'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.agregar_cartel('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) $$,
  '42501', null,
  'Ni Pepe'
);

reset role;

-- Las reglas de la tabla, escribiendo directo como postgres.
select throws_ok(
  $$ insert into public.carteles (restaurante_id, imagen_ruta, producto_id, orden)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 9), 508, 9) $$,
  '23514', 'new row for relation "carteles" violates check constraint "carteles_imagen_o_producto"',
  'La tabla no deja un cartel con imagen y producto'
);

select throws_ok(
  $$ insert into public.carteles (restaurante_id, orden) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 9) $$,
  '23514', 'new row for relation "carteles" violates check constraint "carteles_imagen_o_producto"',
  'Ni uno sin nada'
);

select throws_ok(
  $$ insert into public.carteles (restaurante_id, producto_id, orden) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 507, 9) $$,
  '23505', 'duplicate key value violates unique constraint "carteles_producto_unico"',
  'Ni un producto dos veces'
);

select throws_ok(
  $$ insert into public.carteles (restaurante_id, producto_id, orden) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 511, 9) $$,
  '23503', null,
  'Ni un producto de B en un cartel de A'
);

select throws_ok(
  $$ insert into public.carteles (restaurante_id, imagen_ruta, orden)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 9), 9) $$,
  '23514', 'new row for relation "carteles" violates check constraint "carteles_imagen_ruta_formato"',
  'Una imagen sigue yendo en su carpeta de carteles'
);


-- ─── Lo que ve la clienta ─────────────────────────────────────────────────────

set local role anon;

select is(
  public.menu_publico('fonda-don-chuy') -> 'restaurante' -> 'formas',
  tests.de_don_chuy() - array['tema', 'color', 'color_barra', 'fondo'],
  'El menú recibe las 18 formas de Don Chuy, con los nombres de sus columnas sin «menu_»'
);

select is(
  (public.menu_publico('fonda-don-chuy') -> 'restaurante') - 'formas' - 'nombre' - 'telefono' - 'direccion' - 'logo_ruta' - 'tipo_cambio_usd',
  '{"tema": "oscuro", "color": "#B3261E", "color_barra": "#1F2A44", "fondo": "#F4F1EA", "hace_envios": true}'::jsonb,
  'Y el color de la barra y el fondo junto al color'
);

select is(
  public.menu_publico('fonda-don-chuy') -> 'carteles',
  jsonb_build_array(
    jsonb_build_object('ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 7), 'producto_id', 507),
    jsonb_build_object('ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 3), 'producto_id', null),
    jsonb_build_object('ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2), 'producto_id', null)),
  'Cada cartel con su ruta (la foto del flan, de Mi menú) y su producto; el taco oculto no sale'
);

reset role;

-- El flan cambia de foto, y luego la pierde.
update public.productos set imagen_ruta = tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 17) where id = 507;
set local role anon;

select is(
  public.menu_publico('fonda-don-chuy') -> 'carteles' -> 0 ->> 'ruta',
  tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 17),
  'Si el flan cambia de foto en Mi menú, su cartel cambia solo'
);

reset role;
update public.productos set imagen_ruta = null where id = 507;
update public.productos set visible = true where id = 503;
set local role anon;

select is(
  public.menu_publico('fonda-don-chuy') -> 'carteles',
  jsonb_build_array(
    jsonb_build_object('ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 3), 'producto_id', null),
    jsonb_build_object('ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'carteles', 2), 'producto_id', null),
    jsonb_build_object('ruta', tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 3), 'producto_id', 503)),
  'Sin foto, el flan deja de salir; el taco que se volvió a ver, sí sale'
);

reset role;

select is(
  (select count(*)::integer from public.carteles where producto_id = 507),
  1,
  'El cartel del flan sin foto se queda en «Tus carteles»'
);

-- La quesadilla, agotada por su grupo, en un cartel: no sale.
insert into public.carteles (restaurante_id, producto_id, orden) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 504, 9);
set local role anon;

select ok(
  not (public.menu_publico('fonda-don-chuy') -> 'carteles') @> '[{"producto_id": 504}]',
  'Un producto agotado tampoco sale como cartel'
);

reset role;


-- ─── Si el producto se borra, su cartel se va con él ──────────────────────────

delete from public.carteles where producto_id = 504;
insert into public.carteles (restaurante_id, producto_id, orden) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 508, 9);

select tests.authenticate_as('gerente_a');

select results_eq(
  $$ select resultado, imagen_ruta from public.eliminar_producto(508) $$,
  $$ values ('borrado'::text, tests.ruta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu', 8)) $$,
  'La horchata nunca se vendió: «Eliminar» la borra, aunque sea un cartel'
);

reset role;

select is(
  (select count(*)::integer from public.carteles where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  4,
  'Y su cartel se fue con ella'
);


-- ─── El teléfono, también para llevar ─────────────────────────────────────────

select tests.como_worker();

select throws_ok(
  $$ select tests.pedir('para_llevar', null) $$,
  '22023', 'Tu teléfono lleva 10 dígitos, como 222 123 4567.',
  'Para llevar ya pide el teléfono'
);

select throws_ok(
  $$ select tests.pedir('para_llevar', '222 123 456') $$,
  '22023', 'Tu teléfono lleva 10 dígitos, como 222 123 4567.',
  'Con sus 10 dígitos'
);

select ok(
  (tests.pedir('para_llevar', '(222) 987-6543', 'No va', 'Tampoco', 500) ->> 'ok')::boolean,
  'Rosa pide para llevar con su teléfono'
);

reset role;

select is(
  (select jsonb_build_object('tipo', tipo, 'telefono', cliente_telefono, 'direccion', cliente_direccion,
                             'referencias', cliente_referencias, 'paga_con', paga_con)
   from public.pedidos_en_linea where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"tipo": "para_llevar", "telefono": "2229876543", "direccion": null, "referencias": null, "paga_con": null}'::jsonb,
  'Se guarda el teléfono limpio; la dirección, las referencias y «paga con» siguen siendo solo de domicilio'
);

select tests.authenticate_as('gerente_a');
select tests.guardar('venta_llevar', public.confirmar_pedido(
  (select id from public.pedidos_en_linea where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')));
reset role;

select is(
  (select jsonb_build_object('tipo', tipo, 'telefono', cliente_telefono, 'direccion', cliente_direccion)
   from public.ventas where id = tests.id('venta_llevar')),
  '{"tipo": "para_llevar", "telefono": "2229876543", "direccion": null}'::jsonb,
  'Al confirmarlo, la cuenta para llevar lleva su teléfono'
);

select throws_ok(
  $$ insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, total, clave, marca_celular, marca_conexion)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', current_date, 90, 'para_llevar', 'Sin teléfono', 25, gen_random_uuid(),
             repeat('e', 64), repeat('e', 64)) $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_telefono_para_llevar"',
  'La tabla tampoco deja un pedido para llevar nuevo sin teléfono'
);

select throws_ok(
  $$ insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, cliente_telefono, cliente_direccion,
                                          total, clave, marca_celular, marca_conexion)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', current_date, 91, 'para_llevar', 'Con dirección', '2225550000', 'Calle 5',
             25, gen_random_uuid(), repeat('e', 64), repeat('e', 64)) $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_domicilio"',
  'Ni uno para llevar con dirección'
);

select throws_ok(
  $$ insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, cliente_direccion,
                                          total, clave, marca_celular, marca_conexion)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', current_date, 92, 'domicilio', 'Sin teléfono', 'Calle 5',
             25, gen_random_uuid(), repeat('e', 64), repeat('e', 64)) $$,
  '23514', 'new row for relation "pedidos_en_linea" violates check constraint "pedidos_en_linea_domicilio"',
  'A domicilio sigue pidiendo teléfono'
);

select is(
  (select jsonb_object_agg(conname, convalidated) from pg_constraint
   where conrelid = 'public.pedidos_en_linea'::regclass
     and conname in ('pedidos_en_linea_domicilio', 'pedidos_en_linea_telefono_para_llevar')),
  '{"pedidos_en_linea_domicilio": true, "pedidos_en_linea_telefono_para_llevar": false}'::jsonb,
  'La regla del teléfono para llevar no revisa los pedidos de antes (que no lo tienen); la de domicilio sí'
);

select lives_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre, cliente_telefono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'para_llevar', 'Con teléfono', '2225550000') $$,
  'Una cuenta para llevar puede llevar teléfono'
);

select lives_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'para_llevar', 'Sin teléfono') $$,
  'O no (el «Para llevar» del punto de venta no lo pide)'
);

select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, mesa_id, mesa_nombre, cliente_telefono)
     select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'mesa', m.id, m.nombre, '2225550000'
     from public.mesas m where m.restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' limit 1 $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_domicilio"',
  'Una cuenta de mesa sigue sin teléfono'
);

select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre, cliente_telefono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'domicilio', 'Sin dirección', '2225550000') $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_domicilio"',
  'Y una a domicilio sigue pidiendo dirección'
);


-- ─── Si el producto ya se vendió, se archiva y su cartel se queda ─────────────

insert into public.carteles (restaurante_id, producto_id, orden) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 10);

select tests.authenticate_as('gerente_a');

select results_eq(
  $$ select resultado from public.eliminar_producto(501) $$,
  $$ values ('archivado'::text) $$,
  'El taco al pastor ya se pidió: «Eliminar» lo archiva, aunque sea un cartel'
);

reset role;

select is(
  (select count(*)::integer from public.carteles where producto_id = 501),
  1,
  'Su cartel se queda en «Tus carteles»'
);

set local role anon;

select ok(
  not (public.menu_publico('fonda-don-chuy') -> 'carteles') @> '[{"producto_id": 501}]',
  '… pero ya no sale en el menú'
);

reset role;

select * from finish();
rollback;
