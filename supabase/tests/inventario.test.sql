-- Pruebas de la migración inventario (19 de noviembre de 2026; planes/trabajo/inventario/): los ingredientes con su
-- unidad que no cambia, las preparaciones y las recetas, la cuenta que se cierra resta su receta y la que se reabre la
-- regresa (nunca dos veces), lo que llegó y las mermas (también desde la cocina), contar y «Deshacer» (el gerente),
-- archivar y eliminar, y el platillo agotado que marcan la cocina y la caja.
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
-- cocina, cada quien en su aparato. B es La Fonda · Norte, de otro gerente. El taco al pastor cuesta $25 y su grupo
-- «Extras» trae Queso ($10) y Sin cebolla; el refresco $28; la quesadilla no tiene receta; el envío es un costo.

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

-- Una cuenta nueva de Pepe en una mesa, con sus renglones.
create function tests.cuenta(p_mesa bigint, p_renglones jsonb)
returns bigint
language sql
as $$
  select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), p_renglones,
                                p_mesa_id => p_mesa, p_tipo => 'mesa')
$$;

-- Cuánto queda de un ingrediente de A, por su nombre (también los archivados).
create function tests.queda(p_nombre text)
returns numeric
language sql
security definer
set search_path = ''
as $$
  select existencia from public.ingredientes
  where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and nombre = p_nombre
  order by archivado_at nulls first limit 1
$$;

-- La suma de los movimientos de un ingrediente: siempre igual a su existencia.
create function tests.suma(p_nombre text)
returns numeric
language sql
security definer
set search_path = ''
as $$
  select coalesce(sum(m.cantidad), 0)
  from public.movimientos_inventario m
  join public.ingredientes i on i.restaurante_id = m.restaurante_id and i.id = m.ingrediente_id
  where i.restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and i.nombre = p_nombre
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

  insert into public.mesas (id, restaurante_id, nombre, orden) overriding system value values
    (701, a, 'Mesa 1', 1), (702, a, 'Mesa 2', 2), (703, a, 'Mesa 3', 3), (704, a, 'Mesa 4', 4);

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Tacos', 'taco', null), (602, a, 'Bebidas', 'refresco', null), (611, b, 'Tacos', 'taco', null);

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco al pastor', 25, true),
    (502, a, 602, 'Refresco', 28, true),
    (504, a, 601, 'Quesadilla', 40, true),
    (511, b, 611, 'Taco del Norte', 30, true);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, es_envio) overriding system value values
    (503, a, 601, 'Envío', 30, true, true);

  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Extras', 0, 2);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Queso', 10, true, 1),
    (9012, a, 901, 'Sin cebolla', 0, true, 2);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values (a, 501, 901);
end;
$$;

select plan(106);


-- ─── Las tablas y quién las lee ───────────────────────────────────────────────

select has_table('public', 'ingredientes', 'Hay tabla de ingredientes');
select has_table('public', 'preparaciones', 'Hay tabla de preparaciones');
select has_table('public', 'recetas', 'Hay tabla de recetas');
select has_table('public', 'movimientos_inventario', 'Hay tabla de movimientos del inventario');

select ok(
  not has_table_privilege('authenticated', 'public.ingredientes', 'insert')
  and not has_table_privilege('authenticated', 'public.ingredientes', 'update')
  and not has_table_privilege('authenticated', 'public.recetas', 'insert')
  and not has_table_privilege('authenticated', 'public.recetas', 'delete')
  and not has_table_privilege('authenticated', 'public.preparaciones', 'update')
  and not has_table_privilege('authenticated', 'public.movimientos_inventario', 'insert')
  and not has_table_privilege('authenticated', 'public.movimientos_inventario', 'update')
  and not has_table_privilege('authenticated', 'public.movimientos_inventario', 'delete'),
  'Nadie escribe directo el inventario: solo sus funciones'
);

select ok(
  not has_table_privilege('service_role', 'public.ingredientes', 'select')
  and not has_table_privilege('service_role', 'public.movimientos_inventario', 'select')
  and not has_table_privilege('anon', 'public.ingredientes', 'select')
  and not has_table_privilege('anon', 'public.recetas', 'select'),
  'Ni el Worker ni el menú en línea leen el inventario'
);


-- ─── Los ingredientes ─────────────────────────────────────────────────────────

select tests.entrar('chuy');
select tests.guardar('pastor', public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', ' Pastor ', 'kg', 10, 10,
  p_hay => 5, p_clave => '11111111-0000-4000-8000-000000000001'));
select tests.guardar('tortilla', public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Tortilla', 'pieza', null, 200,
  p_hay => 300, p_clave => '11111111-0000-4000-8000-000000000002'));
select tests.guardar('coca', public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Coca-Cola', 'pieza', 24, 24,
  p_hay => 24, p_clave => '11111111-0000-4000-8000-000000000003'));
select tests.guardar('queso', public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Queso', 'kg', null, null,
  p_hay => 2, p_clave => '11111111-0000-4000-8000-000000000004'));
select tests.guardar('tomate', public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Tomate verde', 'kg', null, 4,
  p_hay => 6, p_clave => '11111111-0000-4000-8000-000000000005'));
select tests.guardar('chile', public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Chile serrano', 'kg', null, null,
  p_hay => 1, p_clave => '11111111-0000-4000-8000-000000000006'));

select is(
  public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Pastor', 'kg', 10, 10,
    p_hay => 5, p_clave => '11111111-0000-4000-8000-000000000001'),
  tests.id('pastor'),
  'La misma clave no crea el ingrediente dos veces (doble toque)'
);

select throws_ok(
  $$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pastor', 'kg', null, null,
       p_hay => 1, p_clave => gen_random_uuid()) $$,
  '22023', 'Ya tienes un ingrediente que se llama «pastor»',
  'Dos ingredientes no se llaman igual, sin importar mayúsculas'
);

select throws_ok(
  $$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cebolla', 'kg', null, null, p_clave => gen_random_uuid()) $$,
  '22023', 'Escribe cuánto hay hoy',
  'Uno nuevo dice cuánto hay hoy'
);

select throws_ok(
  $$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cebolla', 'taza', null, null,
       p_hay => 1, p_clave => gen_random_uuid()) $$,
  '22023', 'Elige en qué se cuenta',
  'Solo kilos, gramos, litros, mililitros o piezas'
);

select throws_ok(
  format($$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Pastor', 'g', 10, 10, p_id => %s) $$,
         tests.id('pastor')),
  '22023', 'La unidad de un ingrediente no cambia: archívalo y crea otro',
  'Su unidad no cambia después de crearlo'
);

select is(
  public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Pastor', 'kg', 10, 8, p_id => tests.id('pastor')),
  tests.id('pastor'),
  'Sus datos sí cambian: el mínimo de 10 a 8'
);
select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Pastor', 'kg', 10, 10, p_id => tests.id('pastor'));
reset role;

select results_eq(
  $$ select nombre, unidad, existencia, minimo, por_caja from public.ingredientes
     where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' order by id $$,
  $$ values ('Pastor'::text, 'kg'::text, 5::numeric, 10::numeric, 10::numeric),
            ('Tortilla', 'pieza', 300, 200, null), ('Coca-Cola', 'pieza', 24, 24, 24),
            ('Queso', 'kg', 2, null, null), ('Tomate verde', 'kg', 6, 4, null), ('Chile serrano', 'kg', 1, null, null) $$,
  'Al darlo de alta, cuánto hay es su existencia, y el nombre va limpio'
);

select results_eq(
  format($$ select tipo, cantidad, contado, anotado_por from public.movimientos_inventario where ingrediente_id = %s $$,
         tests.id('pastor')),
  $$ values ('conteo'::text, 5::numeric, 5::numeric, 101::bigint) $$,
  'Lo que había ese día es su primer conteo, a nombre de Don Chuy'
);

select throws_ok(
  format($$ update public.ingredientes set unidad = 'g' where id = %s $$, tests.id('pastor')),
  '22023', 'La unidad de un ingrediente no cambia: archívalo y crea otro',
  'Ni escribiéndola directo cambia su unidad'
);

select tests.entrar('pepe');
select throws_ok(
  $$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cebolla', 'kg', null, null,
       p_hay => 1, p_clave => gen_random_uuid()) $$,
  '42501', 'Solo el gerente de este restaurante cambia los ingredientes',
  'Un mesero no da de alta ingredientes'
);
select is((select count(*) from public.ingredientes)::int, 0, 'Pepe no ve el inventario');
reset role;

select tests.entrar('lupita');
select is((select count(*) from public.ingredientes)::int, 0, 'La caja no ve el inventario');
reset role;

select tests.entrar('chente');
select is((select count(*) from public.ingredientes)::int, 6, 'La cocina ve todos los ingredientes');
select is((select count(*) from public.movimientos_inventario)::int, 0, 'La cocina no ve el historial');
select throws_ok(
  $$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cebolla', 'kg', null, null,
       p_hay => 1, p_clave => gen_random_uuid()) $$,
  '42501', 'Solo el gerente de este restaurante cambia los ingredientes',
  'La cocina no da de alta ingredientes'
);
reset role;

select tests.authenticate_as('chente');
select is((select count(*) from public.ingredientes)::int, 0, 'Fuera de su aparato, la cocina no ve nada');
reset role;

select tests.entrar('norte');
select is((select count(*) from public.ingredientes)::int, 0, 'El gerente de otra sucursal no ve estos ingredientes');
select throws_ok(
  $$ select public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Cebolla', 'kg', null, null,
       p_hay => 1, p_clave => gen_random_uuid()) $$,
  '42501', 'Solo el gerente de este restaurante cambia los ingredientes',
  'Ni los cambia'
);
reset role;


-- ─── Las preparaciones y las recetas ──────────────────────────────────────────

select tests.entrar('chuy');
select tests.guardar('salsa', public.guardar_preparacion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Salsa verde', 1, 'l',
  format('[{"ingrediente_id": %s, "cantidad": 500, "unidad": "g"}, {"ingrediente_id": %s, "cantidad": 60, "unidad": "g"}]',
         tests.id('tomate'), tests.id('chile'))::jsonb));

select throws_ok(
  format($$ select public.guardar_preparacion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Salsa doble', 1, 'l',
              '[{"preparacion_id": %s, "cantidad": 1, "unidad": "l"}]') $$, tests.id('salsa')),
  '22023', 'Una preparación lleva solo ingredientes',
  'Una preparación no lleva otra preparación: una sola capa'
);

select throws_ok(
  $$ select public.guardar_preparacion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'salsa verde', 2, 'l', '[]') $$,
  '22023', 'Ya tienes una preparación que se llama «salsa verde»',
  'Dos preparaciones no se llaman igual'
);

select is(
  public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    format('[{"ingrediente_id": %s, "cantidad": 100, "unidad": "g"}, {"ingrediente_id": %s, "cantidad": 2, "unidad": "pieza"},
             {"preparacion_id": %s, "cantidad": 30, "unidad": "ml"}]',
           tests.id('pastor'), tests.id('tortilla'), tests.id('salsa'))::jsonb,
    p_producto_id => 501),
  3,
  'El taco al pastor lleva 100 g de pastor, 2 tortillas y 30 ml de salsa verde'
);

select is(
  public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    format('[{"ingrediente_id": %s, "cantidad": 30, "unidad": "g"}]', tests.id('queso'))::jsonb, p_opcion_id => 9011),
  1,
  'La opción «Queso» lleva 30 g de queso'
);

select is(
  public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    format('[{"ingrediente_id": %s, "cantidad": 1, "unidad": "pieza"}]', tests.id('coca'))::jsonb, p_producto_id => 502),
  1,
  'Lo que se vende tal cual lleva una receta de una línea: un refresco, una Coca-Cola'
);

select throws_ok(
  format($$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              '[{"ingrediente_id": %s, "cantidad": 1, "unidad": "pieza"}]', p_producto_id => 503) $$, tests.id('coca')),
  '22023', 'Un costo de envío no lleva receta',
  'Un envío no lleva receta'
);

select throws_ok(
  format($$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              '[{"ingrediente_id": %s, "cantidad": 2, "unidad": "kg"}]', p_producto_id => 504) $$, tests.id('tortilla')),
  '22023', '«Tortilla» se mide en piezas: su cantidad va en esa misma familia',
  'La cantidad va en la familia de su ingrediente: la tortilla, en piezas'
);

select throws_ok(
  format($$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              '[{"preparacion_id": %s, "cantidad": 30, "unidad": "g"}]', p_producto_id => 504) $$, tests.id('salsa')),
  '22023', '«Salsa verde» se mide en litros o mililitros: su cantidad va en esa misma familia',
  'Y la de una preparación, en la familia de lo que rinde'
);

select throws_ok(
  format($$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              '[{"ingrediente_id": %1$s, "cantidad": 1, "unidad": "kg"}, {"ingrediente_id": %1$s, "cantidad": 2, "unidad": "g"}]',
              p_producto_id => 504) $$, tests.id('queso')),
  '22023', 'Un ingrediente o una preparación va una sola vez en la receta',
  'Un ingrediente no se repite en una receta'
);

select is(
  (select count(*) from public.recetas where producto_id = 504)::int, 0,
  'Una receta que no se pudo guardar no deja nada a medias'
);

select throws_ok(
  format($$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              '[{"ingrediente_id": %s, "cantidad": 1, "unidad": "kg"}]', p_producto_id => 511) $$, tests.id('queso')),
  '22023', 'Ese platillo ya no está',
  'Un platillo de otra sucursal no lleva los ingredientes de esta'
);

select is((select count(*) from public.recetas)::int, 7, 'El gerente lee las recetas: 3 del taco, 1 de la opción, 1 del refresco y 2 de la salsa');
reset role;

select tests.entrar('chente');
select is((select count(*) from public.recetas)::int, 0, 'La cocina no lee las recetas directo');
select is((select count(*) from public.preparaciones)::int, 0, 'Ni las preparaciones');
select throws_ok(
  $$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[]', p_producto_id => 504) $$,
  '42501', 'Solo el gerente de este restaurante cambia las recetas',
  'Ni las cambia'
);
reset role;


-- ─── Una cuenta que se cierra resta su receta ─────────────────────────────────

select tests.entrar('lupita');
select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500);
reset role;

select tests.entrar('pepe');
select tests.guardar('mesa1', tests.cuenta(701, '[{"producto_id": 501, "cantidad": 3, "opciones": [9011]},
                                                 {"producto_id": 502, "cantidad": 2}]'));
reset role;

select is(
  (select opciones from public.venta_items where venta_id = tests.id('mesa1') and producto_id = 501),
  '[{"id": 9011, "grupo": "Extras", "opcion": "Queso", "precio_extra": 10.00}]'::jsonb,
  'Cada renglón vendido guarda también el id de la opción elegida'
);

select is(
  (select count(*) from public.movimientos_inventario where venta_id = tests.id('mesa1'))::int, 0,
  'Mandar a cocina no resta nada: resta al cerrarse la cuenta'
);

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa1'), gen_random_uuid(), 'efectivo', 161, p_recibido => 200);
reset role;

select results_eq(
  format($$ select i.nombre, m.cantidad from public.movimientos_inventario m
            join public.ingredientes i on i.id = m.ingrediente_id
            where m.venta_id = %s and m.tipo = 'venta' order by i.id $$, tests.id('mesa1')),
  $$ values ('Pastor'::text, -0.3::numeric), ('Tortilla', -6), ('Coca-Cola', -2), ('Queso', -0.09),
            ('Tomate verde', -0.045), ('Chile serrano', -0.005) $$,
  'Al cerrarse, la Mesa 1 resta 3 tacos con queso y 2 refrescos: uno por ingrediente, con la salsa en su parte de tomate y chile'
);

select ok(
  tests.queda('Pastor') = 4.7 and tests.queda('Tortilla') = 294 and tests.queda('Coca-Cola') = 22
  and tests.queda('Queso') = 1.91 and tests.queda('Tomate verde') = 5.955 and tests.queda('Chile serrano') = 0.995,
  'Y las existencias bajan'
);

select ok(
  (select bool_and(m.anotado_por is null and m.clave is null) from public.movimientos_inventario m
   where m.venta_id = tests.id('mesa1')),
  'Una venta no la anota nadie: se cerró sola'
);

-- Lo cancelado no resta.
select tests.entrar('pepe');
select tests.guardar('mesa2', tests.cuenta(702, '[{"producto_id": 501, "cantidad": 2}]'));
reset role;
select tests.entrar('chuy');
select public.cancelar_renglon((select id from public.venta_items where venta_id = tests.id('mesa2')), 1, 'Se equivocó');
reset role;
select tests.entrar('lupita');
select public.cobrar(tests.id('mesa2'), gen_random_uuid(), 'efectivo', 25, p_recibido => 25);
reset role;

select is(
  (select sum(m.cantidad) from public.movimientos_inventario m where m.venta_id = tests.id('mesa2')
     and m.ingrediente_id = tests.id('pastor')),
  -0.1::numeric,
  'De 2 tacos con uno cancelado, se resta uno'
);

-- Un platillo sin receta no resta, y una cuenta cancelada nunca restó.
select tests.entrar('pepe');
select tests.guardar('mesa3', tests.cuenta(703, '[{"producto_id": 504, "cantidad": 1}]'));
select tests.guardar('mesa4', tests.cuenta(704, '[{"producto_id": 501, "cantidad": 4}]'));
reset role;
select tests.entrar('lupita');
select public.cobrar(tests.id('mesa3'), gen_random_uuid(), 'efectivo', 40, p_recibido => 40);
reset role;
select tests.entrar('chuy');
select public.cancelar_cuenta(tests.id('mesa4'), 'Se fueron');
reset role;

select is(
  (select count(*) from public.movimientos_inventario where venta_id in (tests.id('mesa3'), tests.id('mesa4')))::int, 0,
  'La quesadilla, sin receta, no resta nada; la Mesa 4 cancelada, tampoco'
);


-- ─── Un pago cancelado regresa lo que restó, y nunca resta dos veces ──────────

select tests.entrar('lupita');
select public.cancelar_pago(
  (select max(id) from public.pagos where venta_id = tests.id('mesa1')), 'Se cobró a la mesa equivocada');
reset role;

select results_eq(
  format($$ select i.nombre, m.cantidad from public.movimientos_inventario m
            join public.ingredientes i on i.id = m.ingrediente_id
            where m.venta_id = %s and m.tipo = 'regreso' order by i.id $$, tests.id('mesa1')),
  $$ values ('Pastor'::text, 0.3::numeric), ('Tortilla', 6), ('Coca-Cola', 2), ('Queso', 0.09),
            ('Tomate verde', 0.045), ('Chile serrano', 0.005) $$,
  'La cuenta reabierta regresa justo lo que había restado'
);

select ok(tests.queda('Pastor') = 4.9 and tests.queda('Coca-Cola') = 24, 'Y las existencias suben');

-- Con la receta cambiada (ahora 120 g de pastor), al cerrarse otra vez resta la de ese momento, una sola vez.
select tests.entrar('chuy');
select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  format('[{"ingrediente_id": %s, "cantidad": 120, "unidad": "g"}, {"ingrediente_id": %s, "cantidad": 2, "unidad": "pieza"},
           {"preparacion_id": %s, "cantidad": 30, "unidad": "ml"}]',
         tests.id('pastor'), tests.id('tortilla'), tests.id('salsa'))::jsonb,
  p_producto_id => 501);
reset role;
select tests.entrar('lupita');
select public.cobrar(tests.id('mesa1'), gen_random_uuid(), 'efectivo', 161, p_recibido => 200);
reset role;

select is(
  (select sum(m.cantidad) from public.movimientos_inventario m
   where m.venta_id = tests.id('mesa1') and m.ingrediente_id = tests.id('pastor')),
  -0.36::numeric,
  'Al cerrarse otra vez resta una sola vez, con la receta de ese momento (3 × 120 g)'
);

select ok(tests.queda('Pastor') = 4.54 and tests.queda('Tortilla') = 292, 'Pastor: 4.9 − 0.36; tortilla: 298 − 6');

select ok(
  (select bool_and(tests.queda(nombre) = tests.suma(nombre)) from public.ingredientes),
  'Cada existencia es la suma de sus movimientos'
);


-- ─── Lo que llegó (el gerente y la cocina) ────────────────────────────────────

select tests.entrar('chente');
select is(
  public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-0000-4000-8000-000000000001',
    format('[{"ingrediente_id": %s, "cajas": 2}, {"ingrediente_id": %s, "cantidad": 10}]',
           tests.id('coca'), tests.id('pastor'))::jsonb),
  2,
  'Chente anota lo que llegó desde la cocina: 2 cajas de Coca-Cola y 10 kg de pastor'
);
select is(
  public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-0000-4000-8000-000000000001',
    format('[{"ingrediente_id": %s, "cajas": 2}, {"ingrediente_id": %s, "cantidad": 10}]',
           tests.id('coca'), tests.id('pastor'))::jsonb),
  2,
  'Con la misma clave no se anota dos veces'
);
select throws_ok(
  format($$ select public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %s, "cajas": 3}]') $$, tests.id('tortilla')),
  '22023', '«Tortilla» no dice cuánto trae una caja: anótalo en su unidad',
  'Sin «Una caja trae», no se anota en cajas'
);
select throws_ok(
  format($$ select public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %1$s, "cantidad": 3}, {"ingrediente_id": %1$s, "cantidad": 2}]') $$, tests.id('queso')),
  '22023', '«Queso» va una sola vez: suma lo que llegó en un renglón',
  'Un ingrediente va una sola vez en lo que llegó'
);
select throws_ok(
  format($$ select public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %s, "cantidad": 0}]') $$, tests.id('queso')),
  '22023', 'De «Queso», anota más de 0',
  'Lo que llegó es más de 0'
);
reset role;

select ok(tests.queda('Coca-Cola') = 70 and tests.queda('Pastor') = 14.54, 'Las cajas se vuelven piezas: 22 + 48 Cocas');
select results_eq(
  $$ select cajas, cantidad, anotado_por from public.movimientos_inventario
     where clave = '22222222-0000-4000-8000-000000000001' order by ingrediente_id $$,
  $$ values (null::integer, 10::numeric, 105::bigint), (2, 48, 105) $$,
  'Lo que llegó queda a nombre de Chente, con sus cajas'
);

select tests.entrar('pepe');
select throws_ok(
  format($$ select public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %s, "cantidad": 1}]') $$, tests.id('queso')),
  '42501', 'Solo el gerente y la cocina de este restaurante anotan lo que llegó',
  'Un mesero no anota lo que llegó'
);
reset role;
select tests.entrar('lupita');
select throws_ok(
  format($$ select public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %s, "cantidad": 1}]') $$, tests.id('queso')),
  '42501', 'Solo el gerente y la cocina de este restaurante anotan lo que llegó',
  'La caja tampoco'
);
reset role;


-- ─── Las mermas (el gerente y la cocina) ──────────────────────────────────────

select tests.entrar('chente');
select is(
  public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-0000-4000-8000-000000000001', 'se_cayo_o_quemo',
    p_ingrediente_id => tests.id('pastor'), p_cantidad => 0.5),
  1,
  'Chente anota medio kilo de pastor que se cayó'
);

select is(
  public.platillos_para_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '[{"id": 501, "nombre": "Taco al pastor"}, {"id": 502, "nombre": "Refresco"}]'::jsonb,
  'Como merma de un platillo entero se ofrecen solo los que tienen receta (ni la quesadilla ni el envío)'
);

select is(
  public.lo_que_resta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, 3),
  '[{"nombre": "Pastor", "unidad": "g", "cantidad": 360, "preparacion": false},
    {"nombre": "Tortilla", "unidad": "pieza", "cantidad": 6, "preparacion": false},
    {"nombre": "Salsa verde", "unidad": "ml", "cantidad": 90, "preparacion": true}]'::jsonb,
  'Antes de anotarla, la ventana dice qué resta, como está escrita la receta'
);

select is(
  public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-0000-4000-8000-000000000002', 'se_echo_a_perder',
    p_producto_id => 501, p_platillos => 3),
  4,
  'Se quemó una orden de 3 tacos: resta su receta, un movimiento por ingrediente'
);
reset role;

select results_eq(
  $$ select i.nombre, m.cantidad, m.producto_id, m.platillos, m.motivo from public.movimientos_inventario m
     join public.ingredientes i on i.id = m.ingrediente_id
     where m.clave = '33333333-0000-4000-8000-000000000002' order by i.id $$,
  $$ values ('Pastor'::text, -0.36::numeric, 501::bigint, 3, 'se_echo_a_perder'::text),
            ('Tortilla', -6, 501, 3, 'se_echo_a_perder'), ('Tomate verde', -0.045, 501, 3, 'se_echo_a_perder'),
            ('Chile serrano', -0.005, 501, 3, 'se_echo_a_perder') $$,
  'Con su platillo, cuántos y su motivo; sin opciones'
);

select tests.entrar('chente');

select throws_ok(
  format($$ select public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), 'otro',
              p_ingrediente_id => %s, p_cantidad => 1) $$, tests.id('queso')),
  '22023', 'Con «Otro», cuenta qué pasó en la nota',
  '«Otro» lleva su nota'
);
select is(
  public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), 'otro', ' Se fue la luz ',
    p_ingrediente_id => tests.id('queso'), p_cantidad => 0.2),
  1,
  'Con su nota, sí'
);
select throws_ok(
  $$ select public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), 'se_cayo_o_quemo',
       p_producto_id => 504, p_platillos => 1) $$,
  '22023', 'Ese platillo no tiene receta: anota sus ingredientes uno por uno',
  'Un platillo sin receta no se anota entero'
);
select throws_ok(
  $$ select public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), 'se_tiro',
       p_producto_id => 501, p_platillos => 1) $$,
  '22023', 'Elige por qué se tiró',
  'El motivo es uno de la lista'
);
reset role;

select ok(
  tests.queda('Pastor') = 13.68 and tests.queda('Queso') = 1.71 and tests.queda('Tortilla') = 286,
  'Pastor: 14.54 − 0.5 − 0.36; queso: 1.91 − 0.2; tortilla: 292 − 6'
);
select is(
  (select nota from public.movimientos_inventario where motivo = 'otro'), 'Se fue la luz',
  'La nota va limpia'
);

select tests.entrar('lupita');
select throws_ok(
  $$ select public.platillos_para_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente y la cocina de este restaurante anotan mermas',
  'La caja no anota mermas'
);
reset role;


-- ─── Contar (el gerente) ──────────────────────────────────────────────────────

select tests.entrar('chente');
select throws_ok(
  format($$ select public.anotar_conteo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %s, "contado": 13}]') $$, tests.id('pastor')),
  '42501', 'Solo el gerente de este restaurante cuenta',
  'La cocina no cuenta: lo contado reemplaza lo que dice el sistema'
);
reset role;

select tests.entrar('chuy');
select is(
  public.anotar_conteo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '44444444-0000-4000-8000-000000000001',
    format('[{"ingrediente_id": %s, "contado": 13.5}, {"ingrediente_id": %s, "contado": 290}]',
           tests.id('pastor'), tests.id('tortilla'))::jsonb),
  2,
  'Don Chuy cuenta el pastor y las tortillas'
);
reset role;

select results_eq(
  $$ select contado, cantidad from public.movimientos_inventario
     where clave = '44444444-0000-4000-8000-000000000001' order by ingrediente_id $$,
  $$ values (13.5::numeric, -0.18::numeric), (290, 4) $$,
  'La diferencia queda en el historial: faltaban 0.18 kg de pastor y sobraban 4 tortillas'
);
select ok(tests.queda('Pastor') = 13.5 and tests.queda('Tortilla') = 290, 'Lo contado reemplaza lo que decía el sistema');


-- ─── «Deshacer» (el gerente) ──────────────────────────────────────────────────

select tests.entrar('chente');
select throws_ok(
  $$ select public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       (select 1::bigint), gen_random_uuid()) $$,
  '42501', 'Solo el gerente de este restaurante deshace',
  'La cocina no deshace: le avisa al gerente'
);
reset role;

select tests.guardar('llego_coca', (select id from public.movimientos_inventario
  where clave = '22222222-0000-4000-8000-000000000001' and ingrediente_id = tests.id('coca')));
select tests.guardar('merma_taco', (select min(id) from public.movimientos_inventario
  where clave = '33333333-0000-4000-8000-000000000002'));
select tests.guardar('conteo_pastor', (select id from public.movimientos_inventario
  where clave = '44444444-0000-4000-8000-000000000001' and ingrediente_id = tests.id('pastor')));
select tests.guardar('venta_mesa1', (select min(id) from public.movimientos_inventario where venta_id = tests.id('mesa1')));

select tests.entrar('chuy');
select is(
  public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('llego_coca'), '55555555-0000-4000-8000-000000000001'),
  1,
  'Don Chuy deshace las 2 cajas de Coca-Cola'
);
select is(
  public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('llego_coca'), '55555555-0000-4000-8000-000000000001'),
  1,
  'Con la misma clave no se deshace dos veces'
);
select throws_ok(
  format($$ select public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %s, gen_random_uuid()) $$,
         tests.id('llego_coca')),
  '22023', 'Eso ya se deshizo',
  'Lo deshecho no se deshace otra vez'
);
select throws_ok(
  format($$ select public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %s, gen_random_uuid()) $$,
         tests.id('venta_mesa1')),
  '22023', 'Una venta se regresa cancelando su pago',
  'Una venta no se deshace'
);
select is(
  public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('merma_taco'), gen_random_uuid()),
  4,
  'La merma de un platillo se deshace entera'
);
select is(
  public.deshacer_movimiento('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('conteo_pastor'), gen_random_uuid()),
  1,
  'Un conteo también se deshace'
);
reset role;

select ok(
  tests.queda('Coca-Cola') = 22 and tests.queda('Tortilla') = 296 and tests.queda('Pastor') = 14.04,
  'Deshacer regresa lo que había puesto: Cocas 70 − 48; tortillas 290 + 6; pastor 13.5 + 0.36 + 0.18'
);
select is(
  (select count(*) from public.movimientos_inventario m
   where m.tipo = 'deshacer' and m.anotado_por = 101 and m.deshace_id is not null)::int, 6,
  'Cada «Deshacer» es un movimiento contrario a nombre de Don Chuy, que dice cuál anula'
);
select ok(
  (select bool_and(tests.queda(nombre) = tests.suma(nombre)) from public.ingredientes),
  'Y cada existencia sigue siendo la suma de sus movimientos'
);


-- ─── Archivar un ingrediente y eliminar una preparación ───────────────────────

select tests.entrar('chuy');
select is(
  public.archivar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('queso')), 1,
  'Archivar el queso lo saca de la receta que lo llevaba (la opción «Queso»)'
);
select is(
  (select count(*) from public.recetas where ingrediente_id = tests.id('queso'))::int, 0,
  'Ya no queda en ninguna receta'
);
select throws_ok(
  format($$ select public.guardar_receta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              '[{"ingrediente_id": %s, "cantidad": 1, "unidad": "kg"}]', p_producto_id => 504) $$, tests.id('queso')),
  '22023', 'Ese ingrediente ya no está',
  'Un ingrediente archivado no entra a ninguna receta'
);
select throws_ok(
  format($$ select public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
              '[{"ingrediente_id": %s, "cantidad": 1}]') $$, tests.id('queso')),
  '22023', 'Ese ingrediente ya no está',
  'Ni se anota lo que llegó'
);
select isnt(
  public.guardar_ingrediente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Queso', 'g', null, null,
    p_hay => 1500, p_clave => gen_random_uuid()),
  tests.id('queso'),
  'Su nombre queda libre: un queso nuevo, ahora en gramos'
);
select is(
  public.eliminar_preparacion('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.id('salsa')), 1,
  'Eliminar la salsa la saca del platillo que la llevaba'
);
reset role;

select is(
  (select count(*) from public.recetas where producto_id = 501 or preparacion_id = tests.id('salsa'))::int, 2,
  'El taco se queda con su pastor y sus tortillas; la receta de la salsa se fue con ella'
);
select ok(
  (select archivado_at is not null and existencia = 1.71 from public.ingredientes where id = tests.id('queso'))
  and exists (select 1 from public.movimientos_inventario where ingrediente_id = tests.id('queso')),
  'El queso archivado conserva su existencia y su historial'
);
select throws_ok(
  format($$ delete from public.movimientos_inventario where id = %s $$, tests.id('llego_coca')),
  '23503', null,
  'Un movimiento que otro anula no se puede borrar ni por debajo'
);


-- ─── Agotado (el gerente, la cocina y la caja) ────────────────────────────────

select tests.entrar('chente');
select is(public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, true), false,
  'Se acabó el pastor: Chente marca el taco agotado');
reset role;
select is((select visible from public.productos where id = 501), false, 'Ya no sale en el menú en línea ni se manda');

select tests.entrar('pepe');
select throws_ok(
  $$ select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
       '[{"producto_id": 501, "cantidad": 1}]', p_mesa_id => 704, p_tipo => 'mesa') $$,
  '55000', null,
  'Pepe ya no puede mandarlo'
);
select throws_ok(
  $$ select public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, false) $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante marcan un platillo agotado',
  'Los meseros no marcan agotados: avisan'
);
reset role;

select tests.entrar('lupita');
select is(public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, false), true,
  'Llegó más pastor: Lupita lo regresa desde la caja');
select throws_ok(
  $$ select public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 503, true) $$,
  '22023', 'Ese platillo ya no está',
  'Un envío no se marca agotado'
);
select throws_ok(
  $$ select public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 511, true) $$,
  '22023', 'Ese platillo ya no está',
  'Ni un platillo de otra sucursal'
);
reset role;

select tests.entrar('norte');
select throws_ok(
  $$ select public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 501, true) $$,
  '42501', 'Solo el gerente, la cocina y la caja de este restaurante marcan un platillo agotado',
  'El gerente de otra sucursal no los marca'
);
reset role;

select is(
  (select count(*) from public.productos where visible and restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')::int, 4,
  'Todo quedó a la vista'
);


-- ─── Una receta en otra unidad y una preparación que rinde 4 litros ──────────
-- En La Fonda · Norte (aparte, para no mover las cuentas de arriba): el queso se cuenta en gramos y la receta lo pide
-- en kilos; la salsa roja rinde 4 litros con 2 kg de jitomate, así que 200 ml llevan 0.1 kg.

select tests.entrar('norte');
select tests.guardar('queso_norte', public.guardar_ingrediente('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Queso Oaxaca', 'g',
  null, null, p_hay => 1000, p_clave => gen_random_uuid()));
select tests.guardar('jitomate_norte', public.guardar_ingrediente('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Jitomate', 'kg',
  null, null, p_hay => 10, p_clave => gen_random_uuid()));
select tests.guardar('salsa_roja', public.guardar_preparacion('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Salsa roja', 4, 'l',
  format('[{"ingrediente_id": %s, "cantidad": 2, "unidad": "kg"}]', tests.id('jitomate_norte'))::jsonb));
select public.guardar_receta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  format('[{"ingrediente_id": %s, "cantidad": 0.03, "unidad": "kg"}, {"preparacion_id": %s, "cantidad": 0.2, "unidad": "l"}]',
         tests.id('queso_norte'), tests.id('salsa_roja'))::jsonb,
  p_producto_id => 511);
select tests.guardar('merma_norte_clave', public.anotar_merma('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', gen_random_uuid(),
  'se_cayo_o_quemo', p_producto_id => 511, p_platillos => 2));

select is(
  (select m.cantidad from public.movimientos_inventario m
   where m.producto_id = 511 and m.ingrediente_id = tests.id('queso_norte')),
  -60::numeric,
  'Una receta en kilos de un ingrediente que se cuenta en gramos: 2 tacos × 0.03 kg restan 60 g'
);

select is(
  (select m.cantidad from public.movimientos_inventario m
   where m.producto_id = 511 and m.ingrediente_id = tests.id('jitomate_norte')),
  -0.2::numeric,
  'Una preparación resta su parte de lo que rinde: 2 × 200 ml de una salsa de 4 litros con 2 kg son 0.2 kg de jitomate'
);
reset role;

select * from finish();
rollback;
