-- Pruebas de cuentas y comandas (migración cuentas, parte 4a del punto de venta). Trae las
-- pruebas de aislamiento de la libreta 2 que tocan cuentas, renglones y comandas (2, 3, 6, 7, 8,
-- 9, 12, 16, 18, la parte de RLS de la 19, 21 y 22; cada descripción empieza con su número) y lo
-- decidido el 13 y el 17 de octubre de 2026: mandar a cocina (la cuenta se abre con el primer
-- envío, los precios los pone Postgres, una comanda por área, la misma clave no guarda dos
-- veces), pedir la cuenta, marcar una comanda, cambiar y juntar mesas, y no eliminar una mesa con
-- la cuenta abierta.
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


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas, con ids fijos. A tiene gerente, mesero (con su
-- celular), caja y cocina (en tabletas compartidas), un mesero sin aparato y uno dado de baja;
-- su menú: Tacos a Cocina, Aguas a Barra, Refrescos a nadie, y una categoría archivada; los
-- grupos Salsa (Habanero agotada), Extras, Tamaño y Picante (sin opciones a la vista). B tiene
-- gerente, mesero y cocina, una mesa y una cuenta abierta con su comanda. C (pausado), D (venció
-- ayer) y E (vence hoy) tienen una cuenta para llevar cada uno.

grant execute on function tests.guardar(text, bigint), tests.id(text) to anon, authenticated;

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
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('cocina_a', 'cocina.a@prueba.test');
  perform tests.create_supabase_user('mesero_sin_aparato_a', 'mesero.sin.aparato.a@prueba.test');
  perform tests.create_supabase_user('mesero_baja_a', 'mesero.baja.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('cocina_b', 'cocina.b@prueba.test');
  perform tests.create_supabase_user('mesero_b', 'mesero.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');
  perform tests.create_supabase_user('gerente_d', 'gerente.d@prueba.test');
  perform tests.create_supabase_user('gerente_e', 'gerente.e@prueba.test');

  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'Restaurante A', 'restaurante-a', true, hoy - 30, hoy + 30),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30),
    (c, 'Restaurante C', 'restaurante-c', false, hoy - 30, hoy + 30),
    (d, 'Restaurante D', 'restaurante-d', true, hoy - 31, hoy - 1),
    (e, 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Gerente A', '{gerente}', true),
    (102, a, tests.get_supabase_uid('mesero_a'), 'Mesero A', '{mesero}', true),
    (103, a, tests.get_supabase_uid('caja_a'), 'Caja A', '{caja}', true),
    (104, a, tests.get_supabase_uid('cocina_a'), 'Cocina A', '{cocina}', true),
    (105, a, tests.get_supabase_uid('mesero_sin_aparato_a'), 'Mesero A sin aparato', '{mesero}', true),
    (106, a, tests.get_supabase_uid('mesero_baja_a'), 'Mesero A dado de baja', '{mesero}', false),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true),
    (112, b, tests.get_supabase_uid('cocina_b'), 'Cocina B', '{cocina}', true),
    (113, b, tests.get_supabase_uid('mesero_b'), 'Mesero B', '{mesero}', true),
    (121, c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}', true),
    (131, d, tests.get_supabase_uid('gerente_d'), 'Gerente D', '{gerente}', true),
    (141, e, tests.get_supabase_uid('gerente_e'), 'Gerente E', '{gerente}', true);

  -- Los aparatos: el celular del mesero de A, las tabletas de caja y cocina de A (compartidas),
  -- la tableta de cocina de B y uno ligado al mesero dado de baja (que ya no entra).
  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular del mesero', 102, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta caja', null, repeat('2', 64), '5e5e5e5e-0000-4000-8000-000000000002'),
    (a, 'Tableta cocina', null, repeat('3', 64), '5e5e5e5e-0000-4000-8000-000000000003'),
    (b, 'Tableta cocina B', null, repeat('4', 64), '5e5e5e5e-0000-4000-8000-000000000011');

  insert into tests.ids (nombre, id)
  select 'cocina_' || lower(right(r.nombre, 1)), ap.id
  from public.areas_preparacion ap join public.restaurantes r on r.id = ap.restaurante_id;

  insert into public.areas_preparacion (id, restaurante_id, nombre) overriding system value
  values (802, a, 'Barra');

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Tacos', 'taco', (select id from tests.ids where nombre = 'cocina_a')),
    (602, a, 'Aguas', 'agua', 802),
    (603, a, 'Refrescos', 'refresco', null),
    (604, a, 'Temporada', 'especialidad', (select id from tests.ids where nombre = 'cocina_a')),
    (611, b, 'Tacos B', 'taco', (select id from tests.ids where nombre = 'cocina_b')),
    (621, c, 'Tacos C', 'taco', (select id from tests.ids where nombre = 'cocina_c')),
    (631, d, 'Tacos D', 'taco', (select id from tests.ids where nombre = 'cocina_d'));

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco al pastor', 22, true),
    (502, a, 601, 'Taco de suadero', 24.50, true),
    (503, a, 602, 'Horchata', 30, true),
    (504, a, 603, 'Coca-Cola', 28, true),
    (505, a, 601, 'Taco viejo', 20, true),
    (506, a, 601, 'Torta cubana', 95, false),
    (507, a, 601, 'Taco picante', 30, true),
    (508, a, 604, 'Taco de temporada', 26, true),
    (511, b, 611, 'Taco B', 25, true),
    (521, c, 621, 'Taco C', 25, true),
    (531, d, 631, 'Taco D', 25, true);
  update public.productos set archivado_at = now() where id = 505;
  update public.categorias set archivado_at = now() where id = 604;
  -- La Coca-Cola lleva otra tasa, para ver que el renglón copia la del producto.
  update public.productos set tasa_iva = 8 where id = 504;

  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Salsa', 1, 1),
    (902, a, 'Extras', 0, 2),
    (903, a, 'Tamaño', 1, 1),
    (904, a, 'Picante', 1, 1),
    (911, b, 'Salsa B', 1, 1);

  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Verde', 0, true, 1),
    (9012, a, 901, 'Roja', 0, true, 2),
    (9013, a, 901, 'Habanero', 0, false, 3),
    (9021, a, 902, 'Queso', 15, true, 1),
    (9022, a, 902, 'Aguacate', 12.50, true, 2),
    (9023, a, 902, 'Piña', 5, true, 3),
    (9031, a, 903, 'Medio litro', 0, true, 1),
    (9032, a, 903, 'Litro', 15, true, 2),
    (9041, a, 904, 'Chiltepín', 0, false, 1),
    (9111, b, 911, 'Verde B', 0, true, 1);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values
    (a, 501, 901), (a, 501, 902), (a, 502, 901), (a, 503, 903), (a, 507, 904), (b, 511, 911);

  insert into public.mesas (id, restaurante_id, nombre) overriding system value values
    (701, a, 'Mesa 1'), (702, a, 'Mesa 2'), (703, a, 'Mesa 3'), (704, a, 'Mesa 4'), (705, a, 'Mesa vieja'),
    (711, b, 'Mesa B');
  update public.mesas set archivado_at = now() where id = 705;

  -- La cuenta abierta de B, con su comanda; y una para llevar en C, D y E.
  insert into public.ventas (id, restaurante_id, tipo, mesa_id, mesa_nombre, abierta_por) overriding system value
  values (8101, b, 'mesa', 711, 'Mesa B', 113);
  insert into public.comandas (id, restaurante_id, venta_id, area_preparacion_id, enviada_por) overriding system value
  values (8201, b, 8101, (select id from tests.ids where nombre = 'cocina_b'), 113);
  insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, comanda_id, agregado_por, clave_envio)
  values (b, 8101, 511, 'Taco B', 25, 2, 16, 8201, 113, 'b0b0b0b0-0000-4000-8000-000000000001');
  insert into public.ventas (id, restaurante_id, tipo, cliente_nombre) overriding system value values
    (8301, c, 'para_llevar', 'Cliente C'),
    (8401, d, 'para_llevar', 'Cliente D'),
    (8501, e, 'para_llevar', 'Cliente E');
  insert into public.comandas (id, restaurante_id, venta_id, area_preparacion_id) overriding system value values
    (8302, c, 8301, (select id from tests.ids where nombre = 'cocina_c')),
    (8402, d, 8401, (select id from tests.ids where nombre = 'cocina_d'));
  insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, comanda_id, clave_envio) values
    (c, 8301, 521, 'Taco C', 25, 1, 16, 8302, 'c0c0c0c0-0000-4000-8000-000000000001'),
    (d, 8401, 531, 'Taco D', 25, 1, 16, 8402, 'd0d0d0d0-0000-4000-8000-000000000001');
end;
$$;

select plan(114);


-- ─── 1 · Permisos ─────────────────────────────────────────────────────────────

select is_empty(
  $$ select t.tabla || ' ' || p.permiso
     from unnest(array['public.ventas', 'public.venta_items', 'public.comandas', 'public.bitacora']) as t(tabla),
          unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) as p(permiso)
     where has_table_privilege('authenticated', t.tabla, p.permiso)
        or (p.permiso in ('INSERT', 'UPDATE') and has_any_column_privilege('authenticated', t.tabla, p.permiso)) $$,
  '1 · Nadie con sesión escribe directo cuentas, renglones, comandas ni bitácora: lo hacen las funciones'
);

select is_empty(
  $$ select t from unnest(array['public.ventas', 'public.venta_items', 'public.comandas', 'public.bitacora']) as t
     where has_any_column_privilege('anon', t, 'SELECT') $$,
  '1 · Sin sesión no se lee ninguna de las cuatro tablas'
);

select is_empty(
  $$ select c.relname from pg_class c
     where c.oid in ('public.ventas'::regclass, 'public.venta_items'::regclass, 'public.comandas'::regclass, 'public.bitacora'::regclass)
       and not c.relrowsecurity $$,
  '1 · Las cuatro tablas tienen RLS'
);

select ok(
  not has_column_privilege('authenticated', 'public.productos', 'tasa_iva', 'SELECT')
  and not has_column_privilege('authenticated', 'public.productos', 'tasa_iva', 'INSERT')
  and not has_column_privilege('authenticated', 'public.productos', 'tasa_iva', 'UPDATE'),
  'El IVA de un producto no tiene pantalla: nadie con sesión lo lee ni lo escribe'
);

select is_empty(
  $$ select f from unnest(array[
       'public.mandar_a_cocina(uuid, uuid, jsonb, bigint, bigint, text, text, text, text)',
       'public.pedir_cuenta(bigint)',
       'public.marcar_comanda(bigint, boolean)',
       'public.cambiar_mesa(bigint, bigint)',
       'public.juntar_mesas(bigint, bigint)',
       'public.eliminar_mesa(bigint)'
     ]) as f
     where not has_function_privilege('authenticated', f, 'EXECUTE')
        or has_function_privilege('anon', f, 'EXECUTE') $$,
  '1 · Las funciones las llama quien tiene sesión, y cada una revisa quién es; sin sesión no'
);

select ok(
  not has_function_privilege('authenticated', 'privado.mi_miembro(uuid, text[])', 'EXECUTE')
  and not has_function_privilege('authenticated', 'privado.recalcular_total()', 'EXECUTE'),
  '1 · Los ayudantes de privado no se llaman desde la API'
);


-- ─── Mandar a cocina: la primera vez abre la cuenta ───────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select isnt(
  tests.guardar('v1', public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000001',
    '[{"producto_id": 501, "cantidad": 3, "opciones": [9021, 9011, 9011], "nota": "  sin cebolla "},
      {"producto_id": 503, "cantidad": 2, "opciones": [9032]},
      {"producto_id": 504, "cantidad": 2}]',
    p_mesa_id => 701)),
  null,
  'El mesero manda a una mesa libre y la cuenta se abre'
);

reset role;

select results_eq(
  $$ select tipo, origen, estado, mesa_id, mesa_nombre, abierta_por, cuenta_pedida_at is null, total
     from public.ventas where id = tests.id('v1') $$,
  $$ values ('mesa'::text, 'punto_de_venta'::text, 'abierta'::text, 701::bigint, 'Mesa 1'::text, 102::bigint, true, 257.00::numeric(12,2)) $$,
  'La cuenta nace abierta, en la Mesa 1, a nombre de quien mandó, con el total que calcula Postgres'
);

select results_eq(
  $$ select nombre, precio_unitario, cantidad, importe, tasa_iva, nota, agregado_por
     from public.venta_items where venta_id = tests.id('v1') order by id $$,
  $$ values
       ('Taco al pastor'::text, 37.00::numeric(12,2), 3, 111.00::numeric(12,2), 16.00::numeric(4,2), 'sin cebolla'::text, 102::bigint),
       ('Horchata', 45.00, 2, 90.00, 16.00, null, 102),
       ('Coca-Cola', 28.00, 2, 56.00, 8.00, null, 102) $$,
  'Cada renglón lleva el precio del menú más sus opciones, su nota limpia y el IVA de su producto'
);

select is(
  (select opciones from public.venta_items where venta_id = tests.id('v1') and producto_id = 501),
  '[{"grupo": "Salsa", "opcion": "Verde", "precio_extra": 0.00}, {"grupo": "Extras", "opcion": "Queso", "precio_extra": 15.00}]'::jsonb,
  'Cada renglón guarda su copia de lo elegido, en el orden de los grupos y sin repetir'
);

select results_eq(
  $$ select a.nombre, k.estado, k.enviada_por, k.lista_at is null,
            (select array_agg(i.nombre order by i.id) from public.venta_items i where i.comanda_id = k.id)
     from public.comandas k join public.areas_preparacion a on a.id = k.area_preparacion_id
     where k.venta_id = tests.id('v1') order by k.id $$,
  $$ values ('Cocina'::text, 'pendiente'::text, 102::bigint, true, array['Taco al pastor']),
            ('Barra', 'pendiente', 102, true, array['Horchata']) $$,
  'El envío se reparte en una comanda por área: los tacos a Cocina, la horchata a Barra'
);

select is(
  (select comanda_id from public.venta_items where venta_id = tests.id('v1') and producto_id = 504),
  null,
  'El refresco entra a la cuenta sin comanda: lo sirve el mesero'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000001',
    '[{"producto_id": 504, "cantidad": 9}]', p_mesa_id => 702),
  tests.id('v1'),
  'El mismo envío otra vez (sin conexión, doble toque) regresa la misma cuenta'
);

reset role;

select results_eq(
  $$ select (select count(*) from public.venta_items where venta_id = tests.id('v1')),
            (select count(*) from public.comandas where venta_id = tests.id('v1')),
            (select count(*) from public.ventas where mesa_id = 702) $$,
  $$ values (3::bigint, 2::bigint, 0::bigint) $$,
  '… y no guarda nada dos veces'
);


-- ─── Más envíos a la misma cuenta ─────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select lives_ok($$ select public.pedir_cuenta(tests.id('v1')) $$, 'El mesero pide la cuenta');
reset role;
select isnt((select cuenta_pedida_at from public.ventas where id = tests.id('v1')), null, '… y la mesa sale como «Pidió la cuenta»');

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is(
  public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000002',
    '[{"producto_id": 502, "cantidad": 1, "opciones": [9012]}, {"producto_id": 501, "cantidad": 1, "opciones": [9011]}]', p_mesa_id => 701),
  tests.id('v1'),
  'La caja manda a la misma mesa y todo cae en la misma cuenta'
);
reset role;

select results_eq(
  $$ select v.abierta_por, v.cuenta_pedida_at is null, v.total,
            (select agregado_por from public.venta_items where venta_id = v.id and producto_id = 502),
            (select count(*) from public.comandas where venta_id = v.id),
            (select count(*) from public.venta_items i where i.comanda_id = (select max(id) from public.comandas where venta_id = v.id))
     from public.ventas v where v.id = tests.id('v1') $$,
  $$ values (102::bigint, true, 303.50::numeric(12,2), 103::bigint, 3::bigint, 2::bigint) $$,
  'La cuenta sigue a nombre de quien la abrió; lo nuevo va a nombre de la caja, en una sola comanda para sus dos tacos; pedir algo quita «Pidió la cuenta»'
);

select tests.authenticate_as('gerente_a');
select is(
  public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000003',
    '[{"producto_id": 501, "cantidad": 1, "opciones": [9011, 9022, 9021]}]', p_venta_id => tests.id('v1')),
  tests.id('v1'),
  'El gerente, desde su panel y sin aparato, agrega a la cuenta abierta'
);
reset role;

select is(
  (select opciones from public.venta_items where venta_id = tests.id('v1') and agregado_por = 101),
  '[{"grupo": "Salsa", "opcion": "Verde", "precio_extra": 0.00}, {"grupo": "Extras", "opcion": "Queso", "precio_extra": 15.00}, {"grupo": "Extras", "opcion": "Aguacate", "precio_extra": 12.50}]'::jsonb,
  'Dentro de un grupo, las opciones quedan en su orden'
);

select is((select total from public.ventas where id = tests.id('v1')), 353.00::numeric(12,2), 'El total suma el renglón nuevo: 22 + 15 + 12.50');


-- ─── Para llevar y domicilio ──────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select isnt(
  tests.guardar('llevar', public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000004',
    '[{"producto_id": 502, "cantidad": 2, "opciones": [9011]}]',
    p_tipo => 'para_llevar', p_cliente_nombre => '  Sr. Ramírez ', p_cliente_telefono => '55 1111 2222')),
  null,
  'Un pedido para llevar se abre con el nombre del cliente'
);

select isnt(
  tests.guardar('domicilio', public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000005',
    '[{"producto_id": 504, "cantidad": 1}]',
    p_tipo => 'domicilio', p_cliente_nombre => 'Sra. Rocío', p_cliente_telefono => '55 1234 5678',
    p_cliente_direccion => 'Calle Robles 18')),
  null,
  'Un pedido a domicilio se abre con nombre, teléfono y dirección'
);

reset role;

select results_eq(
  $$ select tipo, mesa_id, cliente_nombre, cliente_telefono, cliente_direccion from public.ventas
     where id in (tests.id('llevar'), tests.id('domicilio')) order by id $$,
  $$ values ('para_llevar'::text, null::bigint, 'Sr. Ramírez'::text, null::text, null::text),
            ('domicilio', null, 'Sra. Rocío', '55 1234 5678', 'Calle Robles 18') $$,
  'El nombre se guarda limpio; para llevar no guarda teléfono ni dirección'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000006',
       '[{"producto_id": 504, "cantidad": 1}]', p_tipo => 'para_llevar', p_cliente_nombre => '   ') $$,
  '22023', 'Escribe el nombre del cliente',
  'Para llevar sin nombre no se abre'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000006',
       '[{"producto_id": 504, "cantidad": 1}]', p_tipo => 'domicilio', p_cliente_nombre => 'Sra. Rocío',
       p_cliente_telefono => '55 1234 5678') $$,
  '22023', 'Para domicilio escribe el teléfono y la dirección',
  'Domicilio sin dirección no se abre'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000006',
       '[{"producto_id": 504, "cantidad": 1}]') $$,
  '22023', 'Elige una mesa, para llevar o domicilio',
  'Sin mesa ni tipo no se abre nada'
);


-- ─── Lo que no se manda ───────────────────────────────────────────────────────

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[]', p_mesa_id => 702) $$,
  '22023', 'No hay nada que mandar',
  'Un envío vacío no se manda'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 504, "cantidad": 1}, {"producto_id": 506, "cantidad": 1}]', p_mesa_id => 702) $$,
  '55000', '«Torta cubana» está agotado. Quítalo y vuelve a mandar.',
  'Un producto agotado no se manda, y la caja de error dice cuál'
);

select is(
  (select count(*) from public.ventas where mesa_id = 702)::integer, 0,
  '… y del envío no queda nada: ni la cuenta ni el refresco que sí se podía'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 507, "cantidad": 1, "opciones": []}]', p_mesa_id => 702) $$,
  '55000', '«Taco picante» está agotado. Quítalo y vuelve a mandar.',
  'Un producto cuyo grupo obligatorio no tiene opciones a la vista está agotado'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 505, "cantidad": 1}]', p_mesa_id => 702) $$,
  '23503', 'Uno de esos productos ya no está en el menú. Quítalo y vuelve a mandar.',
  'Un producto archivado no se manda'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 508, "cantidad": 1}]', p_mesa_id => 702) $$,
  '23503', 'Uno de esos productos ya no está en el menú. Quítalo y vuelve a mandar.',
  'Un producto de una categoría archivada no se manda'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 511, "cantidad": 1, "opciones": [9111]}]', p_mesa_id => 702) $$,
  '23503', 'Uno de esos productos ya no está en el menú. Quítalo y vuelve a mandar.',
  '6 · Un producto de B no entra a una cuenta de A'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 501, "cantidad": 1, "opciones": [9021]}]', p_mesa_id => 702) $$,
  '22023', 'En «Taco al pastor» falta elegir Salsa',
  'Sin elegir lo obligatorio no se manda'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 501, "cantidad": 1, "opciones": [9011, 9021, 9022, 9023]}]', p_mesa_id => 702) $$,
  '22023', 'En «Taco al pastor» se eligen hasta 2 de Extras',
  'Más opciones que el máximo del grupo no se mandan'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 501, "cantidad": 1, "opciones": [9011, 9012]}]', p_mesa_id => 702) $$,
  '22023', 'En «Taco al pastor» se eligen hasta 1 de Salsa',
  'Dos salsas en un grupo de una no se mandan'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 501, "cantidad": 1, "opciones": [9013]}]', p_mesa_id => 702) $$,
  '55000', '«Habanero» está agotada. Vuelve a elegir en «Taco al pastor».',
  'Una opción agotada no se manda'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 501, "cantidad": 1, "opciones": [9011, 9031]}]', p_mesa_id => 702) $$,
  '23503', 'Una de esas opciones ya no es de «Taco al pastor». Vuelve a elegirlas.',
  'Una opción de un grupo que el producto no lleva no se manda'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 501, "cantidad": 1, "opciones": [9111]}]', p_mesa_id => 702) $$,
  '23503', 'Una de esas opciones ya no es de «Taco al pastor». Vuelve a elegirlas.',
  'Una opción de B no se manda en A'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 504, "cantidad": 0}]', p_mesa_id => 702) $$,
  '22023', 'La cantidad de «Coca-Cola» debe ser al menos 1',
  'Cero piezas no se mandan'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 504, "cantidad": 1}]', p_venta_id => 8101) $$,
  '55000', 'Esa cuenta ya no está abierta',
  '7 · Una cuenta de B no recibe renglones desde A'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 504, "cantidad": 1}]', p_mesa_id => 711) $$,
  '23503', 'Esa mesa ya no existe',
  '7 · Una mesa de B no abre cuenta en A'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 504, "cantidad": 1}]', p_mesa_id => 705) $$,
  '23503', 'Esa mesa ya no existe',
  'Una mesa archivada no abre cuenta'
);

select throws_ok(
  $$ select public.mandar_a_cocina('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'c1a1e000-0000-4000-8000-000000000007',
       '[{"producto_id": 511, "cantidad": 1, "opciones": [9111]}]', p_mesa_id => 711) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante toman pedidos',
  '7 · El mesero de A no manda a cocina en B'
);


-- ─── 7 · Quién manda a cocina ─────────────────────────────────────────────────

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000008',
       '[{"producto_id": 504, "cantidad": 1}]', p_mesa_id => 702) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante toman pedidos',
  '7 · La cocina no toma pedidos'
);

select tests.authenticate_as('mesero_sin_aparato_a');
select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000008',
       '[{"producto_id": 504, "cantidad": 1}]', p_mesa_id => 702) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante toman pedidos',
  'Un mesero fuera de un aparato ligado no manda a cocina'
);

select tests.authenticate_as('mesero_baja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000008',
       '[{"producto_id": 504, "cantidad": 1}]', p_mesa_id => 702) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante toman pedidos',
  '9 · Un mesero dado de baja no manda a cocina, ni desde la tableta compartida'
);

select tests.authenticate_as('gerente_c');
select throws_ok(
  $$ select public.mandar_a_cocina('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'c1a1e000-0000-4000-8000-000000000008',
       '[{"producto_id": 504, "cantidad": 1}]', p_tipo => 'para_llevar', p_cliente_nombre => 'X') $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante toman pedidos',
  '8 · Con la licencia pausada no se manda a cocina'
);

select tests.authenticate_as('gerente_d');
select throws_ok(
  $$ select public.mandar_a_cocina('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'c1a1e000-0000-4000-8000-000000000008',
       '[{"producto_id": 504, "cantidad": 1}]', p_tipo => 'para_llevar', p_cliente_nombre => 'X') $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante toman pedidos',
  '22 · Con la licencia vencida ayer no se manda a cocina'
);


-- ─── Pedir la cuenta ──────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_e');
select lives_ok($$ select public.pedir_cuenta(8501) $$, '22 · Con la licencia que vence hoy se sigue trabajando');

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.pedir_cuenta(tests.id('v1')) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante piden la cuenta',
  '7 · La cocina no pide la cuenta'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.pedir_cuenta(8101) $$,
  '55000', 'Esa cuenta ya no está abierta',
  '7 · El mesero de A no pide la cuenta de B'
);


-- ─── La cocina marca «Lista» ──────────────────────────────────────────────────

select tests.guardar('comanda_cocina', (
  select k.id from public.comandas k
  where k.venta_id = tests.id('v1') and k.area_preparacion_id = tests.id('cocina_a')
  order by k.id limit 1
));

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select lives_ok($$ select public.marcar_comanda(tests.id('comanda_cocina'), true) $$, 'La cocina marca una comanda «Lista»');
reset role;
select results_eq(
  $$ select estado, lista_at is not null from public.comandas where id = tests.id('comanda_cocina') $$,
  $$ values ('lista'::text, true) $$,
  '… y queda lista, con su hora'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select lives_ok($$ select public.marcar_comanda(tests.id('comanda_cocina'), false) $$, 'Si se equivocó, la regresa');
reset role;
select results_eq(
  $$ select estado, lista_at is null from public.comandas where id = tests.id('comanda_cocina') $$,
  $$ values ('pendiente'::text, true) $$,
  '… y vuelve a pendiente, sin hora'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.marcar_comanda(tests.id('comanda_cocina'), null) $$,
  '22023', 'La comanda solo se marca lista o se regresa',
  'Una comanda no se marca a medias'
);

select tests.authenticate_as('gerente_a');
select lives_ok($$ select public.marcar_comanda(tests.id('comanda_cocina'), true) $$, 'El gerente también marca desde su panel');

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.marcar_comanda(tests.id('comanda_cocina'), false) $$,
  '42501', 'Solo la cocina y los gerentes de este restaurante marcan comandas',
  '7 · El mesero no marca comandas'
);

select tests.authenticate_as('cocina_b');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000011');
select throws_ok(
  $$ select public.marcar_comanda(tests.id('comanda_cocina'), false) $$,
  '23503', 'Esa comanda ya no está',
  '7 · La cocina de B no marca comandas de A'
);


-- ─── Cambiar de mesa ──────────────────────────────────────────────────────────

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select lives_ok($$ select public.cambiar_mesa(tests.id('v1'), 703) $$, 'El mesero pasa la cuenta de la Mesa 1 a la Mesa 3');
reset role;

select results_eq(
  $$ select mesa_id, mesa_nombre, total from public.ventas where id = tests.id('v1') $$,
  $$ values (703::bigint, 'Mesa 3'::text, 353.00::numeric(12,2)) $$,
  '… con todo lo que lleva y sin tocar precios'
);

select results_eq(
  $$ select miembro_id, autorizado_por, accion, tabla, registro_id, detalle from public.bitacora order by id $$,
  $$ values (102::bigint, null::bigint, 'cambiar_mesa'::text, 'ventas'::text, tests.id('v1')::text, '{"de": "Mesa 1", "a": "Mesa 3"}'::jsonb) $$,
  '… y queda en la bitácora, sin PIN'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select isnt(
  tests.guardar('v2', public.mandar_a_cocina(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-000000000009',
    '[{"producto_id": 502, "cantidad": 2, "opciones": [9011]}, {"producto_id": 504, "cantidad": 1}]', p_mesa_id => 702)),
  null,
  'Se abre otra cuenta en la Mesa 2'
);

select throws_ok(
  $$ select public.cambiar_mesa(tests.id('v1'), 702) $$,
  '23505', 'Mesa 2 ya tiene una cuenta abierta',
  'Una cuenta no pasa a una mesa ocupada'
);

select throws_ok(
  $$ select public.cambiar_mesa(tests.id('v1'), 703) $$,
  '22023', 'La cuenta ya está en Mesa 3',
  'Ni a la mesa donde ya está'
);

select throws_ok(
  $$ select public.cambiar_mesa(tests.id('v1'), 705) $$,
  '23503', 'Esa mesa ya no existe',
  'Ni a una mesa archivada'
);

select throws_ok(
  $$ select public.cambiar_mesa(tests.id('v1'), 711) $$,
  '23503', 'Esa mesa ya no existe',
  '7 · Ni a una mesa de B'
);

select throws_ok(
  $$ select public.cambiar_mesa(tests.id('llevar'), 704) $$,
  '22023', 'Solo una cuenta de mesa se cambia de mesa',
  'Un pedido para llevar no se cambia de mesa'
);

select throws_ok(
  $$ select public.cambiar_mesa(8101, 704) $$,
  '55000', 'Esa cuenta ya no está abierta',
  '7 · El mesero de A no mueve una cuenta de B'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select throws_ok(
  $$ select public.cambiar_mesa(tests.id('v1'), 704) $$,
  '42501', 'Solo meseros, caja y gerentes de este restaurante cambian de mesa',
  '7 · La cocina no cambia de mesa'
);


-- ─── Juntar mesas ─────────────────────────────────────────────────────────────

reset role;
select tests.guardar('total_v1', (select total * 100 from public.ventas where id = tests.id('v1'))::bigint);
select tests.guardar('total_v2', (select total * 100 from public.ventas where id = tests.id('v2'))::bigint);
select tests.guardar('renglones_v2', (select count(*) from public.venta_items where venta_id = tests.id('v2')));
select tests.guardar('comanda_v2', (select id from public.comandas where venta_id = tests.id('v2')));

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');

select throws_ok(
  $$ select public.juntar_mesas(tests.id('v2'), tests.id('v2')) $$,
  '22023', 'Elige otra mesa para juntarla',
  'Una cuenta no se junta consigo misma'
);

select throws_ok(
  $$ select public.juntar_mesas(tests.id('v2'), tests.id('llevar')) $$,
  '22023', 'Solo se juntan cuentas de mesa',
  'Un pedido para llevar no se junta'
);

select throws_ok(
  $$ select public.juntar_mesas(tests.id('v2'), 8101) $$,
  '55000', 'La cuenta de esa mesa ya no está abierta',
  '7 · Una cuenta de A no se junta con una de B'
);

select lives_ok($$ select public.juntar_mesas(tests.id('v2'), tests.id('v1')) $$, 'La caja junta la Mesa 2 con la Mesa 3');
reset role;

select results_eq(
  $$ select estado, cancelada_motivo, total,
            (select count(*) from public.venta_items where venta_id = v.id),
            (select count(*) from public.comandas where venta_id = v.id)
     from public.ventas v where id = tests.id('v2') $$,
  $$ values ('cancelada'::text, 'Se juntó con «Mesa 3»'::text, 0.00::numeric(12,2), 0::bigint, 0::bigint) $$,
  'La cuenta de la Mesa 2 queda vacía, cancelada con su motivo'
);

select results_eq(
  $$ select total * 100, (select count(*) from public.venta_items where venta_id = v.id),
            (select venta_id from public.comandas where id = tests.id('comanda_v2'))
     from public.ventas v where id = tests.id('v1') $$,
  $$ select (tests.id('total_v1') + tests.id('total_v2'))::numeric, (6 + tests.id('renglones_v2'))::bigint, tests.id('v1') $$,
  'La cuenta de la Mesa 3 recibe sus renglones y su comanda, y su total los suma'
);

select is(
  (select count(*) from public.ventas where mesa_id = 702 and estado = 'abierta')::integer, 0,
  'La Mesa 2 queda libre'
);

select results_eq(
  $$ select miembro_id, accion, registro_id, detalle from public.bitacora where accion = 'juntar_mesas' $$,
  $$ values (103::bigint, 'juntar_mesas'::text, tests.id('v2')::text,
             jsonb_build_object('de', 'Mesa 2', 'a', 'Mesa 3', 'a_venta', tests.id('v1'))) $$,
  'Juntar queda en la bitácora'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.juntar_mesas(tests.id('v2'), tests.id('v1')) $$,
  '55000', 'Esa cuenta ya no está abierta',
  'Una cuenta ya juntada no se vuelve a juntar'
);

select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c1a1e000-0000-4000-8000-00000000000a',
       '[{"producto_id": 504, "cantidad": 1}]', p_venta_id => tests.id('v2')) $$,
  '55000', 'Esa cuenta ya no está abierta',
  'A una cuenta ya juntada no se le agrega nada'
);


-- ─── Eliminar mesa ────────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ select public.eliminar_mesa(703) $$,
  '55000', 'Mesa 3 tiene una cuenta abierta. Cóbrala o cámbiala de mesa antes de eliminarla.',
  'Una mesa con la cuenta abierta no se elimina'
);

select is(public.eliminar_mesa(702), 'archivado', 'La Mesa 2, ya libre y con cuentas, se archiva');
select is(public.eliminar_mesa(704), 'borrado', 'La Mesa 4, que nunca tuvo cuentas, se borra');


-- ─── Eliminar un área que ya recibió comandas ─────────────────────────────────

update public.categorias set area_preparacion_id = tests.id('cocina_a') where id = 602;
select is(public.eliminar_area(802), 'archivado', 'La Barra, sin categorías y con comandas, se archiva');


-- ─── 2 · Quién lee ────────────────────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select set_eq(
  'select id from public.ventas',
  $$ values (tests.id('v1')), (tests.id('v2')), (tests.id('llevar')), (tests.id('domicilio')) $$,
  '2 · Gerente A lee sus cuentas, también la juntada; ninguna de B, C, D ni E'
);

select is_empty(
  $$ select 1 from public.venta_items where restaurante_id <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     union all select 1 from public.comandas where restaurante_id <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '2 · Gerente A no lee renglones ni comandas de B'
);

select is(
  (select count(*) from public.bitacora)::integer, 2,
  'El gerente lee la bitácora de su restaurante'
);

select tests.authenticate_as('mesero_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select results_eq(
  $$ select (select count(*) from public.ventas), (select count(*) from public.venta_items),
            (select count(*) from public.comandas), (select count(*) from public.bitacora) $$,
  $$ values (4::bigint, 10::bigint, 6::bigint, 0::bigint) $$,
  'El mesero lee todas las cuentas, renglones y comandas de su restaurante, y nada de la bitácora'
);

select tests.authenticate_as('cocina_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
select isnt_empty('select 1 from public.venta_items', 'La cocina lee los renglones, con todo y precios');

select tests.authenticate_as('cocina_b');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000011');
select set_eq(
  'select id from public.comandas',
  array[8201]::bigint[],
  '19 · La cocina de B solo lee las comandas de B'
);

select tests.authenticate_as('mesero_sin_aparato_a');
select is_empty('select 1 from public.ventas', 'Un mesero fuera de un aparato ligado no lee cuentas');

select tests.authenticate_as('mesero_baja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000002');
select is_empty('select 1 from public.ventas union all select 1 from public.comandas', '9 · Un mesero dado de baja no lee nada');

select tests.authenticate_as('fragmentless');
select is_empty('select 1 from public.ventas union all select 1 from public.venta_items', '18 · Fragmentless no lee ventas');

select tests.authenticate_as('gerente_c');
select is_empty(
  'select 1 from public.ventas union all select 1 from public.comandas union all select 1 from public.venta_items',
  '8 · Con la licencia pausada no se leen cuentas, comandas ni renglones'
);

select tests.authenticate_as('gerente_d');
select is_empty(
  'select 1 from public.ventas union all select 1 from public.comandas union all select 1 from public.venta_items',
  '22 · Con la licencia vencida ayer no se leen cuentas, comandas ni renglones'
);

select tests.authenticate_as('gerente_e');
select set_eq('select id from public.ventas', array[8501]::bigint[], '22 · Con la licencia que vence hoy se leen');

select tests.clear_authentication();
select throws_ok('select 1 from public.ventas', '42501', null, '16 · Sin sesión no se leen cuentas');


-- ─── 12 · Nadie escribe directo ───────────────────────────────────────────────

select tests.authenticate_as('gerente_a');

select throws_ok(
  $$ update public.ventas set total = 1 $$,
  '42501', null, '12 · Ni el gerente escribe un total'
);
select throws_ok(
  $$ delete from public.venta_items $$,
  '42501', null, '12 · Ni el gerente borra renglones'
);
select throws_ok(
  $$ delete from public.ventas $$,
  '42501', null, '12 · Ni el gerente borra cuentas'
);
select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'para_llevar', 'X') $$,
  '42501', null, '3 · Nadie inserta una cuenta directo'
);
select throws_ok(
  $$ update public.comandas set estado = 'lista' $$,
  '42501', null, 'Nadie marca una comanda directo'
);
select throws_ok(
  $$ insert into public.bitacora (restaurante_id, accion, tabla, registro_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cambiar_mesa', 'ventas', '1') $$,
  '42501', null, 'Nadie escribe en la bitácora directo'
);
select throws_ok(
  $$ update public.productos set tasa_iva = 0 $$,
  '42501', null, 'Nadie cambia el IVA de un producto'
);


-- ─── Lo que la base no deja, aunque se escriba como dueño ─────────────────────

reset role;

select throws_ok(
  $$ insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva, clave_envio)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('v1'), 511, 'Taco B', 25, 1, 16, gen_random_uuid()) $$,
  '23503', null, '6 · Un producto de B no entra a una cuenta de A, ni escribiendo directo'
);
select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre, abierta_por)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'para_llevar', 'X', 113) $$,
  '23503', null, '21 · Un miembro de B no abre una cuenta de A'
);
select throws_ok(
  $$ insert into public.comandas (restaurante_id, venta_id, area_preparacion_id)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('v1'), tests.id('cocina_b')) $$,
  '23503', null, 'Una comanda de A no va a la cocina de B'
);
select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, mesa_nombre) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'mesa', 'Mesa 9') $$,
  '23514', null, 'Una cuenta de mesa lleva su mesa'
);
select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre, cliente_telefono)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'para_llevar', 'X', '55') $$,
  '23514', null, 'Un pedido para llevar no lleva teléfono'
);
select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, mesa_id, mesa_nombre) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'mesa', 703, 'Mesa 3') $$,
  '23505', null, 'Una mesa no tiene dos cuentas abiertas'
);
select throws_ok(
  $$ update public.ventas set estado = 'cancelada' where id = tests.id('llevar') $$,
  '23514', null, 'Una cuenta cancelada lleva su motivo'
);

update public.venta_items set cantidad = cantidad + 1
where id = (select min(id) from public.venta_items where venta_id = tests.id('v1') and producto_id = 504);
select is(
  (select total * 100 from public.ventas where id = tests.id('v1')),
  (tests.id('total_v1') + tests.id('total_v2') + 2800)::numeric,
  'El total se recalcula solo cuando cambia un renglón'
);


select * from finish();

rollback;
