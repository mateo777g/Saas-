-- Pruebas de la migración recetario (19 de noviembre de 2026; planes/trabajo/recetario/): quién lee y quién escribe el
-- recetario, los cuadros (todos para el gerente; para la cocina y la caja, solo los que tienen pasos), la página de un
-- platillo y de una preparación con lo que lleva de su receta, guardar el recetario entero y lo que no se guarda, las
-- fotos que dejan de usarse y van a la fila, el Worker que la vacía, puedo_borrar_foto con la carpeta recetario/, y el
-- recetario que se va con su platillo o su preparación (o se queda escondido si el platillo se archiva).
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
-- Se siembra como postgres, con ids fijos. A es La Fonda de Don Chuy: Pepe es mesero, Lupita la caja y Chente la
-- cocina, cada quien en su aparato. B es La Fonda · Norte, de otro gerente. El taco al pastor lleva pastor, tortillas,
-- salsa verde y salsa roja (dos preparaciones), y su grupo «Extras» trae Queso y Doble carne (con receta) y Sin cebolla
-- (sin ella).
-- La quesadilla no tiene receta; el refresco está agotado; la gringa está archivada; el envío es un costo.

create function tests.entrar(p_quien text)
returns void as $$
begin
  perform tests.authenticate_as(p_quien);
  if p_quien = 'pepe' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
  elsif p_quien = 'lupita' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
  elsif p_quien = 'chente' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
  end if;
end
$$ language plpgsql;

-- Una foto del recetario de A: 32 veces la misma letra.
create function tests.foto(p_letra text)
returns text
language sql
immutable
as $$
  select 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/recetario/' || repeat(p_letra, 32) || '.webp'
$$;

-- Una foto de Mi menú de A.
create function tests.menu(p_letra text)
returns text
language sql
immutable
as $$
  select 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat(p_letra, 32) || '.webp'
$$;

-- Las fotos que esperan en la fila, por ruta.
create function tests.fila()
returns text[]
language sql
security definer
set search_path = ''
as $$
  select coalesce(array_agg(ruta order by ruta), '{}') from public.fotos_por_borrar
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

set local time zone 'UTC';

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
begin
  perform tests.create_supabase_user('chuy', 'chuy@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('lupita', 'lupita@prueba.test');
  perform tests.create_supabase_user('chente', 'chente@prueba.test');
  perform tests.create_supabase_user('norte', 'norte@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30),
    (b, 'La Fonda · Norte', 'fonda-norte', true, hoy - 30, hoy + 30);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('chuy'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('pepe'), 'Pepe', '{mesero}', true),
    (103, a, tests.get_supabase_uid('lupita'), 'Lupita', '{caja}', true),
    (105, a, tests.get_supabase_uid('chente'), 'Chente', '{cocina}', true),
    (111, b, tests.get_supabase_uid('norte'), 'Gerente Norte', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, privado.huella_aparato(repeat('P', 43)), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta de Lupita', 103, privado.huella_aparato(repeat('L', 43)), '5e5e5e5e-0000-4000-8000-000000000002'),
    (a, 'Tableta de la cocina', 105, privado.huella_aparato(repeat('C', 43)), '5e5e5e5e-0000-4000-8000-000000000003');

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Tacos', 'taco', null), (602, a, 'Bebidas', 'refresco', null), (603, a, 'Postres', 'postre', null),
    (611, b, 'Tacos', 'taco', null);

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, imagen_ruta) overriding system value values
    (501, a, 601, 'Taco al pastor', 25, true, tests.menu('a')),
    (502, a, 602, 'Refresco', 28, false, null),
    (504, a, 601, 'Quesadilla', 40, true, null),
    (511, b, 611, 'Taco del Norte', 30, true, null);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, es_envio) overriding system value values
    (503, a, 601, 'Envío', 30, true, true);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, archivado_at) overriding system value values
    (505, a, 601, 'Gringa', 45, true, now()),
    (506, a, 603, 'Flan', 35, true, now());

  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Extras', 0, 2);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Queso', 10, true, 1),
    (9012, a, 901, 'Sin cebolla', 0, true, 2),
    (9013, a, 901, 'Doble carne', 15, true, 3);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values (a, 501, 901);

  insert into public.ingredientes (id, restaurante_id, nombre, unidad) overriding system value values
    (301, a, 'Pastor', 'kg'), (302, a, 'Tortilla', 'pieza'), (303, a, 'Queso', 'kg'), (304, a, 'Tomate verde', 'kg');
  insert into public.preparaciones (id, restaurante_id, nombre, rinde, unidad) overriding system value values
    (801, a, 'Salsa verde', 1, 'l'), (802, a, 'Salsa roja', 2, 'l');
  insert into public.recetas (restaurante_id, producto_id, opcion_id, preparacion_id, ingrediente_id, lleva_preparacion_id, cantidad, unidad) values
    (a, 501, null, null, 301, null, 100, 'g'),
    (a, 501, null, null, 302, null, 2, 'pieza'),
    (a, 501, null, null, null, 801, 30, 'ml'),
    (a, 501, null, null, null, 802, 15, 'ml'),
    (a, null, 9011, null, 303, null, 30, 'g'),
    (a, null, 9013, null, 301, null, 50, 'g'),
    (a, null, null, 801, 304, null, 500, 'g');
end;
$$;

select plan(100);


-- ─── Las tablas y quién las toca ──────────────────────────────────────────────

select has_table('public', 'recetarios', 'Hay tabla de recetarios');
select has_table('public', 'pasos_recetario', 'Hay tabla de pasos del recetario');
select has_table('public', 'fotos_por_borrar', 'Hay tabla de fotos por borrar');

select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('public.recetarios'::regclass, 'public.pasos_recetario'::regclass, 'public.fotos_por_borrar'::regclass)),
  'Las tres tablas llevan RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.recetarios', 'select')
  and not has_table_privilege('authenticated', 'public.recetarios', 'insert')
  and not has_table_privilege('authenticated', 'public.recetarios', 'update')
  and not has_table_privilege('authenticated', 'public.pasos_recetario', 'select')
  and not has_table_privilege('authenticated', 'public.pasos_recetario', 'delete')
  and not has_table_privilege('authenticated', 'public.fotos_por_borrar', 'select')
  and not has_table_privilege('anon', 'public.recetarios', 'select')
  and not has_table_privilege('anon', 'public.pasos_recetario', 'select'),
  'Ni el panel, ni el aparato, ni el menú en línea leen o escriben estas tablas directo'
);

select ok(
  not has_table_privilege('service_role', 'public.recetarios', 'select')
  and not has_table_privilege('service_role', 'public.pasos_recetario', 'select')
  and not has_table_privilege('service_role', 'public.fotos_por_borrar', 'select')
  and not has_table_privilege('service_role', 'public.fotos_por_borrar', 'delete'),
  'El Worker tampoco: solo por sus funciones'
);

select ok(
  has_function_privilege('authenticated', 'public.recetario(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.pagina_recetario(uuid, bigint, bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.guardar_recetario(uuid, text, jsonb, bigint, bigint)', 'execute')
  and not has_function_privilege('anon', 'public.recetario(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.pagina_recetario(uuid, bigint, bigint)', 'execute')
  and not has_function_privilege('service_role', 'public.guardar_recetario(uuid, text, jsonb, bigint, bigint)', 'execute'),
  'El recetario se lee y se escribe con la sesión; ni el menú en línea ni el Worker'
);

select ok(
  has_function_privilege('service_role', 'public.fotos_sueltas()', 'execute')
  and has_function_privilege('service_role', 'public.borrar_fotos_sueltas(bigint[])', 'execute')
  and not has_function_privilege('authenticated', 'public.fotos_sueltas()', 'execute')
  and not has_function_privilege('authenticated', 'public.borrar_fotos_sueltas(bigint[])', 'execute')
  and not has_function_privilege('anon', 'public.fotos_sueltas()', 'execute'),
  'Solo el Worker vacía la fila de fotos'
);

select ok(
  not has_function_privilege('authenticated', 'privado.foto_en_uso(text)', 'execute')
  and not has_function_privilege('authenticated', 'privado.lleva_del_recetario(uuid, bigint, bigint, bigint)', 'execute')
  and not has_function_privilege('service_role', 'privado.foto_en_uso(text)', 'execute'),
  'Las funciones privadas no se llaman de fuera'
);


-- ─── Recién nacido ────────────────────────────────────────────────────────────

select tests.entrar('chuy');
select is(
  public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object(
    'categorias', jsonb_build_array(
      jsonb_build_object('id', 601, 'nombre', 'Tacos', 'icono', 'taco', 'platillos', jsonb_build_array(
        jsonb_build_object('id', 501, 'nombre', 'Taco al pastor', 'foto', tests.menu('a'), 'pasos', 0),
        jsonb_build_object('id', 504, 'nombre', 'Quesadilla', 'foto', null, 'pasos', 0))),
      jsonb_build_object('id', 602, 'nombre', 'Bebidas', 'icono', 'refresco', 'platillos', jsonb_build_array(
        jsonb_build_object('id', 502, 'nombre', 'Refresco', 'foto', null, 'pasos', 0)))),
    'preparaciones', jsonb_build_array(
      jsonb_build_object('id', 802, 'nombre', 'Salsa roja', 'foto', null, 'pasos', 0),
      jsonb_build_object('id', 801, 'nombre', 'Salsa verde', 'foto', null, 'pasos', 0))
  ),
  'Recién nacido, Don Chuy ve todo «Sin escribir»: los platillos por categoría con la foto de Mi menú (el agotado también; sin envío ni archivados) y las preparaciones al final'
);
reset role;

select tests.entrar('chente');
select is(public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '{"categorias": [], "preparaciones": []}'::jsonb,
  'La cocina no ve los que no tienen pasos');
reset role;

select tests.entrar('lupita');
select is(public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '{"categorias": [], "preparaciones": []}'::jsonb,
  'La caja tampoco');
reset role;

select tests.entrar('pepe');
select throws_ok(
  $$ select public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario',
  'Un mesero no lee el recetario'
);
reset role;

select tests.authenticate_as('chente');
select throws_ok(
  $$ select public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario',
  'Fuera de su aparato, la cocina no lo lee'
);
reset role;

select tests.entrar('norte');
select throws_ok(
  $$ select public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario',
  'El gerente de otra sucursal no lo lee'
);
reset role;


-- ─── Don Chuy lo escribe ──────────────────────────────────────────────────────

select tests.entrar('chuy');
select is(
  public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.foto('1'), jsonb_build_array(
    jsonb_build_object('texto', '  Marina el pastor una noche con el adobo  '),
    jsonb_build_object('texto', 'Asa el pastor en el trompo', 'imagen_ruta', tests.foto('2')),
    jsonb_build_object('texto', 'Sirve con piña y cilantro', 'imagen_ruta', tests.foto('3'))),
    p_producto_id => 501),
  3,
  'Don Chuy guarda el recetario del taco: su foto y tres pasos'
);
select is(
  public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[{"texto": "Hierve el tomate con el chile"}]',
    p_preparacion_id => 801),
  1,
  'Y el de la salsa verde, sin foto'
);
reset role;

select results_eq(
  $$ select s.orden, s.texto, s.imagen_ruta
     from public.pasos_recetario s join public.recetarios r on r.id = s.recetario_id
     where r.producto_id = 501 order by s.orden $$,
  $$ values (1, 'Marina el pastor una noche con el adobo'::text, null::text),
            (2, 'Asa el pastor en el trompo', tests.foto('2')),
            (3, 'Sirve con piña y cilantro', tests.foto('3')) $$,
  'Los pasos quedan en orden, con su texto limpio y sus fotos'
);

select tests.entrar('chuy');
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) -> 'lleva',
  '[{"nombre": "Pastor", "cantidad": 100, "unidad": "g", "preparacion_id": null, "con_pasos": null},
    {"nombre": "Tortilla", "cantidad": 2, "unidad": "pieza", "preparacion_id": null, "con_pasos": null},
    {"nombre": "Salsa verde", "cantidad": 30, "unidad": "ml", "preparacion_id": 801, "con_pasos": true},
    {"nombre": "Salsa roja", "cantidad": 15, "unidad": "ml", "preparacion_id": 802, "con_pasos": false}]'::jsonb,
  'La página del taco: lo que lleva sale de su receta tal cual, y cada salsa dice si su recetario tiene pasos'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) -> 'opciones',
  '[{"grupo": "Extras", "nombre": "Queso",
     "lleva": [{"nombre": "Queso", "cantidad": 30, "unidad": "g", "preparacion_id": null, "con_pasos": null}]},
    {"grupo": "Extras", "nombre": "Doble carne",
     "lleva": [{"nombre": "Pastor", "cantidad": 50, "unidad": "g", "preparacion_id": null, "con_pasos": null}]}]'::jsonb,
  'Las opciones que suman algo, con lo que llevan; «Sin cebolla», sin receta, no sale'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501)
    - 'lleva' - 'opciones' - 'pasos',
  jsonb_build_object('tipo', 'platillo', 'id', 501, 'nombre', 'Taco al pastor', 'categoria', 'Tacos',
    'rinde', null, 'unidad', null, 'foto_de_mi_menu', tests.menu('a'), 'imagen_ruta', tests.foto('1'),
    'foto', tests.foto('1')),
  'Con su categoría y su foto de cómo se sirve, que gana a la de Mi menú'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) -> 'pasos',
  jsonb_build_array(
    jsonb_build_object('orden', 1, 'texto', 'Marina el pastor una noche con el adobo', 'imagen_ruta', null),
    jsonb_build_object('orden', 2, 'texto', 'Asa el pastor en el trompo', 'imagen_ruta', tests.foto('2')),
    jsonb_build_object('orden', 3, 'texto', 'Sirve con piña y cilantro', 'imagen_ruta', tests.foto('3'))),
  'Y sus pasos en orden'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_preparacion_id => 801),
  '{"tipo": "preparacion", "id": 801, "nombre": "Salsa verde", "categoria": null, "rinde": 1, "unidad": "l",
    "foto_de_mi_menu": null, "imagen_ruta": null, "foto": null, "opciones": [],
    "lleva": [{"nombre": "Tomate verde", "cantidad": 500, "unidad": "g", "preparacion_id": null, "con_pasos": null}],
    "pasos": [{"orden": 1, "texto": "Hierve el tomate con el chile", "imagen_ruta": null}]}'::jsonb,
  'La página de la salsa verde: lo que rinde, lo que lleva y su paso; sin foto, el cuadro negro'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 504) -> 'pasos',
  '[]'::jsonb,
  'Don Chuy abre también un platillo «Sin escribir»'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 504) ->> 'foto',
  null::text,
  'Sin foto de cómo se sirve ni de Mi menú, el cuadro negro'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 503),
  null::jsonb,
  'Un envío no tiene página'
);
select is(
  public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object(
    'categorias', jsonb_build_array(
      jsonb_build_object('id', 601, 'nombre', 'Tacos', 'icono', 'taco', 'platillos', jsonb_build_array(
        jsonb_build_object('id', 501, 'nombre', 'Taco al pastor', 'foto', tests.foto('1'), 'pasos', 3),
        jsonb_build_object('id', 504, 'nombre', 'Quesadilla', 'foto', null, 'pasos', 0))),
      jsonb_build_object('id', 602, 'nombre', 'Bebidas', 'icono', 'refresco', 'platillos', jsonb_build_array(
        jsonb_build_object('id', 502, 'nombre', 'Refresco', 'foto', null, 'pasos', 0)))),
    'preparaciones', jsonb_build_array(
      jsonb_build_object('id', 802, 'nombre', 'Salsa roja', 'foto', null, 'pasos', 0),
      jsonb_build_object('id', 801, 'nombre', 'Salsa verde', 'foto', null, 'pasos', 1))
  ),
  'Los cuadros dicen cuántos pasos lleva cada uno, con la foto de cómo se sirve'
);
reset role;


-- ─── La cocina y la caja lo leen ──────────────────────────────────────────────

select tests.entrar('chente');
select is(
  public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object(
    'categorias', jsonb_build_array(
      jsonb_build_object('id', 601, 'nombre', 'Tacos', 'icono', 'taco', 'platillos', jsonb_build_array(
        jsonb_build_object('id', 501, 'nombre', 'Taco al pastor', 'foto', tests.foto('1'), 'pasos', 3)))),
    'preparaciones', jsonb_build_array(
      jsonb_build_object('id', 801, 'nombre', 'Salsa verde', 'foto', null, 'pasos', 1))
  ),
  'La cocina ve solo los que tienen pasos'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) -> 'lleva' -> 2 ->> 'con_pasos',
  'true',
  'Y abre el taco: su salsa verde, con pasos, se puede abrir'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 504),
  null::jsonb,
  'Un platillo sin pasos no le sale'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_preparacion_id => 802),
  null::jsonb,
  'Ni una preparación sin pasos'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 504) $$,
  '42501', 'Solo el gerente de este restaurante escribe el recetario',
  'La cocina no lo cambia'
);
reset role;

select tests.entrar('lupita');
select is(
  jsonb_array_length(public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'categorias' -> 0 -> 'platillos')
    + jsonb_array_length(public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'preparaciones'),
  2,
  'La caja ve los mismos dos'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_preparacion_id => 801) ->> 'nombre',
  'Salsa verde',
  'Y los abre, aunque no lea el inventario'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 504) $$,
  '42501', 'Solo el gerente de este restaurante escribe el recetario',
  'La caja no lo cambia'
);
reset role;

select tests.entrar('pepe');
select throws_ok(
  $$ select public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario',
  'Un mesero no abre la página'
);
reset role;

select tests.entrar('norte');
select throws_ok(
  $$ select public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario',
  'El gerente de otra sucursal no abre la página'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 501) $$,
  '42501', 'Solo el gerente de este restaurante escribe el recetario',
  'Ni lo cambia'
);
reset role;


-- ─── Lo que no se guarda ──────────────────────────────────────────────────────

select tests.entrar('chuy');
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null,
       (select jsonb_agg(jsonb_build_object('texto', 'Paso ' || n)) from generate_series(1, 21) n), p_producto_id => 504) $$,
  '22023', 'Un recetario lleva hasta 20 pasos',
  'Hasta 20 pasos'
);
select is(
  public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null,
    (select jsonb_agg(jsonb_build_object('texto', repeat('x', 300))) from generate_series(1, 20) n), p_producto_id => 504),
  20,
  'Veinte pasos de 300 letras sí caben'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null,
       jsonb_build_array(jsonb_build_object('texto', repeat('x', 301))), p_producto_id => 504) $$,
  '22023', 'El paso 1 va de hasta 300 letras',
  'Un paso va de hasta 300 letras'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null,
       '[{"texto": "Calienta la tortilla"}, {"texto": "   "}]', p_producto_id => 504) $$,
  '22023', 'Escribe el paso 2',
  'Un paso sin texto no se guarda'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 504,
       p_preparacion_id => 801) $$,
  '22023', 'El recetario es de un platillo o de una preparación',
  'De un platillo o de una preparación, no de los dos'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]') $$,
  '22023', 'El recetario es de un platillo o de una preparación',
  'Ni de ninguno'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 503) $$,
  '22023', 'Un costo de envío no lleva recetario',
  'Un envío no lleva recetario'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 505) $$,
  '22023', 'Ese platillo ya no está',
  'Un platillo archivado no se escribe'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 511) $$,
  '22023', 'Ese platillo ya no está',
  'Ni uno de otra sucursal'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_preparacion_id => 999) $$,
  '22023', 'Esa preparación ya no está',
  'Ni una preparación que no está'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '{"texto": "Uno"}', p_producto_id => 504) $$,
  '22023', 'Los pasos llegan como una lista',
  'Los pasos llegan como una lista'
);
select throws_ok(
  format($$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, '[]', p_producto_id => 501) $$,
         tests.menu('a')),
  '23514', null,
  'La foto de cómo se sirve va en la carpeta recetario/, no en la del menú'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, jsonb_build_array(jsonb_build_object(
       'texto', 'Sirve',
       'imagen_ruta', 'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/recetario/' || repeat('9', 32) || '.webp')),
       p_producto_id => 501) $$,
  '23514', null,
  'La foto de un paso es de su mismo restaurante'
);
reset role;

select is(
  (select count(*) from public.pasos_recetario s join public.recetarios r on r.id = s.recetario_id where r.producto_id = 501)::int,
  3,
  'Lo que no se guardó no tocó el recetario del taco'
);
select is((select count(*) from public.recetarios)::int, 3, 'Hay tres recetarios: el taco, la quesadilla y la salsa verde');
select is(tests.fila(), '{}'::text[], 'Ninguna foto suelta todavía');


-- ─── Las fotos que se quitan van a la fila ────────────────────────────────────

select tests.entrar('chuy');
select is(
  public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.foto('4'), jsonb_build_array(
    jsonb_build_object('texto', 'Marina el pastor una noche con el adobo'),
    jsonb_build_object('texto', 'Sirve con piña y cilantro', 'imagen_ruta', tests.foto('3')),
    jsonb_build_object('texto', 'Asa el pastor en el trompo')),
    p_producto_id => 501),
  3,
  'Don Chuy cambia la foto del taco, mueve un paso y le quita la foto a otro'
);
reset role;

select is(tests.fila(), array[tests.foto('1'), tests.foto('2')],
  'A la fila van la foto que cambió y la que se quitó; la del paso que solo se movió, no');

select tests.entrar('chuy');
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, jsonb_build_array(
  jsonb_build_object('texto', 'Marina el pastor una noche con el adobo'),
  jsonb_build_object('texto', 'Sirve con piña y cilantro', 'imagen_ruta', tests.foto('3')),
  jsonb_build_object('texto', 'Asa el pastor en el trompo')),
  p_producto_id => 501);
select is(
  public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') #>> '{categorias,0,platillos,0,foto}',
  tests.menu('a'),
  'Sin su foto de cómo se sirve, el cuadro vuelve a la de Mi menú'
);
select is(
  public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501) - 'lleva' - 'opciones' - 'pasos',
  jsonb_build_object('tipo', 'platillo', 'id', 501, 'nombre', 'Taco al pastor', 'categoria', 'Tacos',
    'rinde', null, 'unidad', null, 'foto_de_mi_menu', tests.menu('a'), 'imagen_ruta', null, 'foto', tests.menu('a')),
  'Y la página también, sin foto propia'
);
reset role;
select is(tests.fila(), array[tests.foto('1'), tests.foto('2'), tests.foto('4')], 'Y la foto que se quitó va a la fila');

select tests.entrar('chuy');
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, jsonb_build_array(
  jsonb_build_object('texto', 'Marina el pastor una noche con el adobo'),
  jsonb_build_object('texto', 'Sirve con piña y cilantro', 'imagen_ruta', tests.foto('3')),
  jsonb_build_object('texto', 'Asa el pastor en el trompo', 'imagen_ruta', tests.foto('2'))),
  p_producto_id => 501);
reset role;
select is(tests.fila(), array[tests.foto('1'), tests.foto('4')], 'Una foto que se vuelve a usar sale de la fila');

select tests.entrar('chuy');
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, jsonb_build_array(
  jsonb_build_object('texto', 'Pica el tomate', 'imagen_ruta', tests.foto('5')),
  jsonb_build_object('texto', 'Muélelo con el chile', 'imagen_ruta', tests.foto('5'))),
  p_preparacion_id => 801);
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null,
  '[{"texto": "Pica el tomate"}, {"texto": "Muélelo con el chile"}]', p_preparacion_id => 801);
reset role;
select is(
  (select count(*) from public.fotos_por_borrar where ruta = tests.foto('5'))::int,
  1,
  'La misma foto en dos pasos va a la fila una sola vez'
);


-- ─── Lo que se borra se lleva su recetario ────────────────────────────────────

select tests.entrar('chuy');
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.foto('6'),
  jsonb_build_array(jsonb_build_object('texto', 'Pica el tomate', 'imagen_ruta', tests.foto('7'))), p_preparacion_id => 801);
select public.eliminar_preparacion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 801);
reset role;
select is(
  array[(select count(*) from public.recetarios where preparacion_id = 801), (select count(*) from public.pasos_recetario)]::int[],
  array[0, 23],
  'La salsa verde que se elimina se lleva su recetario y su paso (quedan los 3 del taco y los 20 de la quesadilla)'
);
select is(tests.fila(), array[tests.foto('1'), tests.foto('4'), tests.foto('5'), tests.foto('6'), tests.foto('7')],
  'Y sus fotos van a la fila');

select tests.entrar('chuy');
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null,
  jsonb_build_array(jsonb_build_object('texto', 'Calienta la tortilla', 'imagen_ruta', tests.foto('8'))), p_producto_id => 504);
select is((select resultado from public.eliminar_producto(504)), 'borrado', 'Don Chuy elimina la quesadilla, que nunca se vendió');
reset role;
select is((select count(*) from public.recetarios where producto_id = 504)::int, 0, 'Se lleva su recetario');
select is(tests.fila(), array[tests.foto('1'), tests.foto('4'), tests.foto('5'), tests.foto('6'), tests.foto('7'), tests.foto('8')],
  'Y su foto va a la fila');


-- ─── El Worker vacía la fila ──────────────────────────────────────────────────

-- Una foto en la fila que todavía se usa (la del paso 2 del taco): el Worker no la ve ni la saca.
insert into public.fotos_por_borrar (restaurante_id, ruta) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.foto('3'));

select tests.como_worker();
select is(jsonb_array_length(public.fotos_sueltas()), 6, 'El Worker recibe las seis fotos sueltas');
reset role;

select is(
  (select array_agg((e ->> 'id')::bigint order by n) from jsonb_array_elements(public.fotos_sueltas()) with ordinality t(e, n)),
  (select array_agg(id order by id) from public.fotos_por_borrar where ruta <> tests.foto('3')),
  'Las más viejas primero, sin la que todavía se usa'
);
select is(
  (select array_agg(e ->> 'ruta' order by e ->> 'ruta') from jsonb_array_elements(public.fotos_sueltas()) e),
  array[tests.foto('1'), tests.foto('4'), tests.foto('5'), tests.foto('6'), tests.foto('7'), tests.foto('8')],
  'Cada una con su ruta'
);

select tests.guardar('primera', (select min(id) from public.fotos_por_borrar));
select tests.guardar('ultima', (select max(id) from public.fotos_por_borrar));
select tests.como_worker();
select is(
  public.borrar_fotos_sueltas(array(select generate_series(tests.id('primera'), tests.id('ultima')))),
  6,
  'Ya borradas de R2, el Worker las saca de la fila'
);
reset role;
select is(tests.fila(), array[tests.foto('3')], 'La que todavía se usa se queda');


-- ─── puedo_borrar_foto acepta el recetario ────────────────────────────────────

select tests.entrar('chuy');
select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.foto('b'), '[]', p_preparacion_id => 802);
select is(public.puedo_borrar_foto(tests.foto('9')), true,
  'Una foto del recetario que se subió y no se guardó: Don Chuy la puede borrar');
select is(public.puedo_borrar_foto(tests.foto('3')), false, 'Una que usa un paso, no');
select is(public.puedo_borrar_foto(tests.foto('b')), false, 'Ni la de cómo se sirve de un recetario');
select is(public.puedo_borrar_foto(tests.menu('a')), false, 'El menú sigue igual: la foto de un platillo no se borra');
select is(public.puedo_borrar_foto(tests.menu('c')), true, 'Y una del menú que nadie usa, sí');
select is(
  public.puedo_borrar_foto('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/recetarios/' || repeat('9', 32) || '.webp'),
  false,
  'Solo esas carpetas'
);
select is(
  public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'preparaciones' -> 0,
  jsonb_build_object('id', 802, 'nombre', 'Salsa roja', 'foto', tests.foto('b'), 'pasos', 0),
  'Con foto y sin pasos sigue «Sin escribir»'
);
reset role;

select tests.entrar('chente');
select is(public.puedo_borrar_foto(tests.foto('9')), false, 'La cocina no borra fotos');
select is(jsonb_array_length(public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'preparaciones'), 0,
  'Y no ve la salsa roja, que tiene foto pero no pasos');
reset role;

select tests.entrar('norte');
select is(public.puedo_borrar_foto(tests.foto('9')), false, 'Ni el gerente de otra sucursal');
reset role;


-- ─── Lo que la tabla no deja ──────────────────────────────────────────────────

select throws_ok(
  $$ insert into public.pasos_recetario (restaurante_id, recetario_id, orden, texto)
     select restaurante_id, id, 21, 'Uno más' from public.recetarios where producto_id = 501 $$,
  '23514', null,
  'Ni escribiéndolo directo hay un paso 21'
);
select throws_ok(
  $$ insert into public.pasos_recetario (restaurante_id, recetario_id, orden, texto)
     select restaurante_id, id, 4, repeat('x', 301) from public.recetarios where producto_id = 501 $$,
  '23514', null,
  'Ni uno de 301 letras'
);
select throws_ok(
  $$ insert into public.pasos_recetario (restaurante_id, recetario_id, orden, texto)
     select restaurante_id, id, 1, 'Otra vez el uno' from public.recetarios where producto_id = 501 $$,
  '23505', null,
  'Ni dos pasos con el mismo número'
);
select throws_ok(
  $$ insert into public.recetarios (restaurante_id, producto_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501) $$,
  '23505', null,
  'Ni dos recetarios del mismo platillo'
);
select throws_ok(
  $$ insert into public.recetarios (restaurante_id, producto_id, preparacion_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 502, 802) $$,
  '23514', null,
  'Ni uno de un platillo y una preparación a la vez'
);
select throws_ok(
  format($$ insert into public.fotos_por_borrar (restaurante_id, ruta) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L) $$,
         tests.menu('a')),
  '23514', null,
  'A la fila solo van fotos del recetario'
);
select throws_ok(
  format($$ insert into public.fotos_por_borrar (restaurante_id, ruta) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', %L) $$,
         tests.foto('1')),
  '23514', null,
  'Y cada una a nombre de su restaurante'
);


-- ─── La licencia y el platillo archivado ──────────────────────────────────────

update public.restaurantes set licencia_activa = false where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.entrar('chuy');
select throws_ok(
  $$ select public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario',
  'Con la licencia pausada no se lee'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 501) $$,
  '42501', 'Solo el gerente de este restaurante escribe el recetario',
  'Ni se escribe'
);
reset role;
update public.restaurantes set licencia_activa = true where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

-- El taco se vendió y lo archivaron (eliminar_producto lo archiva cuando ya tiene ventas).
update public.productos set archivado_at = now() where id = 501;
select is((select count(*) from public.recetarios where producto_id = 501)::int, 1,
  'Un platillo archivado guarda su recetario escondido');

select tests.entrar('chuy');
select is(public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501), null::jsonb,
  'Su página ya no se abre');
select is(
  public.recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'categorias',
  jsonb_build_array(
    jsonb_build_object('id', 602, 'nombre', 'Bebidas', 'icono', 'refresco', 'platillos', jsonb_build_array(
      jsonb_build_object('id', 502, 'nombre', 'Refresco', 'foto', null, 'pasos', 0)))),
  'Ni sale en los cuadros, y su categoría sin platillos tampoco'
);
select throws_ok(
  $$ select public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, '[]', p_producto_id => 501) $$,
  '22023', 'Ese platillo ya no está',
  'Ni se escribe'
);
reset role;

select tests.entrar('chente');
select is(public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 501), null::jsonb,
  'La cocina tampoco lo abre');
reset role;



-- ─── Las rutas vacías son «sin foto» ──────────────────────────────────────────

select tests.entrar('chuy');
select is(
  public.guardar_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '  ', '[{"texto": "Sírvelo frío", "imagen_ruta": ""}]',
    p_producto_id => 502),
  1,
  'Una foto vacía se guarda como sin foto'
);
select is(
  array[public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 502) ->> 'imagen_ruta',
        public.pagina_recetario('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_producto_id => 502) #>> '{pasos,0,imagen_ruta}'],
  array[null, null]::text[],
  'Ni en el recetario ni en el paso queda una ruta vacía'
);
reset role;


-- ─── Un restaurante que se borra entero (solo a mano, como postgres) ──────────

select tests.entrar('norte');
select public.guardar_recetario('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/recetario/' || repeat('1', 32) || '.webp',
  '[{"texto": "Asa la carne"}]', p_producto_id => 511);
select public.guardar_recetario('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/recetario/' || repeat('2', 32) || '.webp',
  '[{"texto": "Asa la carne", "imagen_ruta": "restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/recetario/33333333333333333333333333333333.webp"}]',
  p_producto_id => 511);
reset role;
select is(
  (select count(*) from public.fotos_por_borrar where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')::int,
  1,
  'La Fonda · Norte cambió la foto de su taco: la vieja va a la fila, a su nombre'
);
select lives_ok(
  $$ delete from public.restaurantes where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  'Un restaurante con recetario se puede borrar entero'
);
select is(
  (select count(*) from public.fotos_por_borrar where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')::int,
  0,
  'Y se lleva su fila de fotos'
);


select * from finish();
rollback;
