-- Pruebas de la migración adaptabilidad (13 de noviembre de 2026): «Comer aquí», el nombre opcional en toda
-- cuenta sin mesa con el número corto del día que comparten el punto de venta y el menú en línea, nacer y
-- quedarse sin áreas, y el nombre de una cuenta («#23») en la bitácora, los reportes y el agente.
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
-- Se siembra como postgres, con ids fijos. A es Café Luna, un mostrador de Don Chuy: sin mesas, nace sin
-- áreas y recibe pedidos del menú en línea ahora (su horario va de 3 horas antes a 3 horas después de este
-- momento, todos los días). Lupita es su caja, en su tableta. B es La Fonda, con su mesa y su «Cocina» de
-- antes, y su gerente. C, D y E no tienen a nadie: C y E para el número del día, D para las reglas de ventas.

-- Un envío de Lupita en Café Luna, sin mesa, con su clave nueva.
create function tests.vender(
  p_tipo text,
  p_renglones jsonb,
  p_nombre text default null,
  p_telefono text default null,
  p_direccion text default null
)
returns bigint
language sql
as $$
  select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(), p_renglones,
                                p_tipo => p_tipo, p_cliente_nombre => p_nombre, p_cliente_telefono => p_telefono,
                                p_cliente_direccion => p_direccion)
$$;

-- Un pedido del menú en línea de Café Luna, como lo manda el Worker, cada vez desde un celular y una
-- conexión nuevos.
create function tests.pedir()
returns jsonb
language sql
as $$
  select public.hacer_pedido('cafe-luna', gen_random_uuid(), 'para_llevar', 'Rosa Ramírez', '2221234567', null,
                             null, null, '[{"producto_id": 501, "cantidad": 1, "precio": 22}]',
                             encode(extensions.gen_random_bytes(32), 'hex'), encode(extensions.gen_random_bytes(32), 'hex'))
$$;

-- El día de negocio de hoy de un restaurante.
create function tests.hoy(p_restaurante_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select privado.dia_de_negocio(zona_horaria, hora_corte) from public.restaurantes where id = p_restaurante_id
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
  perform tests.create_supabase_user('caja_a', 'caja.a@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, telefono) values
    (a, 'Café Luna', 'cafe-luna', true, hoy - 30, hoy + 30, '2221234567'),
    (b, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, null),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Restaurante C', 'restaurante-c', true, hoy - 30, hoy + 30, null),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Restaurante D', 'restaurante-d', true, hoy - 30, hoy + 30, null),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Restaurante E', 'restaurante-e', true, hoy - 30, hoy + 30, null);

  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select a, x, date_trunc('minute', v_local - interval '3 hours')::time, date_trunc('minute', v_local + interval '3 hours')::time
  from generate_series(1, 7) as x;

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('gerente_a'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('caja_a'), 'Lupita', '{caja}', true),
    (111, b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Tableta de Lupita', 102, privado.huella_aparato(repeat('L', 43)), '5e5e5e5e-0000-4000-8000-000000000001');

  -- La Fonda es de antes: tiene su «Cocina» (811), y su mesa.
  insert into public.areas_preparacion (id, restaurante_id, nombre) overriding system value values (811, b, 'Cocina');
  insert into public.mesas (id, restaurante_id, nombre, orden) overriding system value values (701, b, 'Mesa 1', 1);

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Pan', 'pan', null), (602, a, 'Café', 'cafe', null), (611, b, 'Tacos', 'taco', 811);

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Concha', 22, true),
    (502, a, 602, 'Café americano', 35, true),
    (503, a, 601, 'Pan de muerto', 40, false),
    (511, b, 611, 'Taco al pastor', 25, true);
end;
$$;

select plan(53);


-- ─── Nacer sin áreas ──────────────────────────────────────────────────────────

select hasnt_trigger('public', 'restaurantes', 'restaurantes_nace_con_cocina',
  'Ya no hay disparador que le ponga «Cocina» a un restaurante nuevo');

select hasnt_function('privado', 'nace_con_cocina', 'Y su función se fue');

select is_empty(
  $$ select id from public.areas_preparacion where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'Café Luna nace sin áreas: todo se entrega directo'
);


-- ─── Comer aquí y el número del día ───────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select tests.guardar('v1', public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'c0c0c0c0-0000-4000-8000-000000000001', '[{"producto_id": 501, "cantidad": 2}]', p_tipo => 'comer_aqui'));

select results_eq(
  format('select tipo, origen, mesa_id, cliente_nombre, pedido_numero, abierta_por from public.ventas where id = %s',
         tests.id('v1')),
  $$ values ('comer_aqui'::text, 'punto_de_venta'::text, null::bigint, null::text, 1, 102::bigint) $$,
  'Lupita abre «Comer aquí» sin nombre: la cuenta se llama #1'
);

select results_eq(
  format($$ select (select count(*) from public.comandas where venta_id = %1$s),
                   (select count(*) from public.venta_items where venta_id = %1$s and comanda_id is null) $$,
         tests.id('v1')),
  $$ values (0::bigint, 1::bigint) $$,
  'Sin áreas no hay comanda: las conchas se entregan directo y sí entran a la cuenta'
);

select is(
  public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'c0c0c0c0-0000-4000-8000-000000000001',
    '[{"producto_id": 501, "cantidad": 2}]', p_tipo => 'comer_aqui'),
  tests.id('v1'),
  'El mismo envío dos veces regresa la misma cuenta…'
);

select is(
  (select count(*) from public.ventas where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  1::bigint,
  '… sin abrir otra ni gastar otro número'
);

select tests.guardar('v2', tests.vender('comer_aqui', '[{"producto_id": 502, "cantidad": 1}]', p_nombre => '  Sr. Ramírez '));

select results_eq(
  format('select tipo, cliente_nombre, pedido_numero from public.ventas where id = %s', tests.id('v2')),
  $$ values ('comer_aqui'::text, 'Sr. Ramírez'::text, null::integer) $$,
  'Con nombre no toma número, como hoy, y el nombre se guarda limpio'
);

select tests.guardar('v3', tests.vender('para_llevar', '[{"producto_id": 502, "cantidad": 1}]'));

select results_eq(
  format('select tipo, cliente_nombre, pedido_numero from public.ventas where id = %s', tests.id('v3')),
  $$ values ('para_llevar'::text, null::text, 2) $$,
  'Para llevar sin nombre toma el siguiente: #2'
);

reset role;
select tests.como_worker();

select tests.guardar('p3', (tests.pedir() ->> 'numero')::bigint);

reset role;

select is(
  tests.id('p3'),
  3::bigint,
  'Un pedido del menú en línea sigue en el mismo contador: #3'
);

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select tests.guardar('v4', tests.vender('domicilio', '[{"producto_id": 501, "cantidad": 1}]',
  p_telefono => '2229876543', p_direccion => 'Reforma 10'));

select results_eq(
  format('select tipo, cliente_nombre, pedido_numero, cliente_telefono, cliente_direccion from public.ventas where id = %s',
         tests.id('v4')),
  $$ values ('domicilio'::text, null::text, 4, '2229876543'::text, 'Reforma 10'::text) $$,
  'A domicilio el nombre también es opcional: #4, con su teléfono y su dirección'
);

select tests.guardar('v5', tests.vender('comer_aqui', '[{"producto_id": 501, "cantidad": 1}]',
  p_telefono => '2229876543', p_direccion => 'Reforma 10'));

select results_eq(
  format('select pedido_numero, cliente_telefono, cliente_direccion from public.ventas where id = %s', tests.id('v5')),
  $$ values (5, null::text, null::text) $$,
  'Comer aquí es el #5 y no guarda teléfono ni dirección'
);

select throws_ok(
  $$ select tests.vender('comer_aqui', '[{"producto_id": 501, "cantidad": 1}, {"producto_id": 503, "cantidad": 1}]') $$,
  '55000', '«Pan de muerto» está agotado. Quítalo y vuelve a mandar.',
  'Un envío que no pasa (el pan de muerto está agotado) no abre cuenta…'
);

select tests.guardar('v6', tests.vender('comer_aqui', '[{"producto_id": 501, "cantidad": 1}]'));

select is(
  (select pedido_numero from public.ventas where id = tests.id('v6')),
  6,
  '… ni gasta número: la siguiente es la #6'
);

select throws_ok(
  $$ select tests.vender('domicilio', '[{"producto_id": 501, "cantidad": 1}]', p_telefono => '2229876543') $$,
  '22023', 'Para domicilio escribe el teléfono y la dirección',
  'A domicilio sigue pidiendo teléfono y dirección'
);

select throws_ok(
  $$ select tests.vender('mesa', '[{"producto_id": 501, "cantidad": 1}]') $$,
  '22023', 'Elige una mesa, comer aquí, para llevar o domicilio',
  'Una cuenta de mesa sin mesa no se abre'
);

reset role;

select is(
  (select pedidos_ultimo from public.folios where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  6,
  'Los envíos que no se abrieron no gastaron número: el último sigue siendo el #6'
);

-- La Fonda, con su mesa.
select tests.authenticate_as('gerente_b');

select tests.guardar('b1', public.mandar_a_cocina('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', gen_random_uuid(),
  '[{"producto_id": 511, "cantidad": 2}]', p_tipo => 'comer_aqui'));

select is(
  (select pedido_numero from public.ventas where id = tests.id('b1')),
  1,
  'Cada restaurante lleva su número: en La Fonda es la #1'
);

select tests.guardar('mesa_b', public.mandar_a_cocina('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', gen_random_uuid(),
  '[{"producto_id": 511, "cantidad": 3}]', p_mesa_id => 701));

select results_eq(
  format('select tipo, mesa_nombre, pedido_numero from public.ventas where id = %s', tests.id('mesa_b')),
  $$ values ('mesa'::text, 'Mesa 1'::text, null::integer) $$,
  'Una cuenta de mesa no toma número'
);

select results_eq(
  $$ select k.area_preparacion_id, count(*) from public.comandas k
     where k.restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' group by 1 $$,
  $$ values (811::bigint, 2::bigint) $$,
  'En La Fonda, que tiene su «Cocina» de antes, los tacos llegan a su pantalla'
);


-- ─── Quedarse sin áreas ───────────────────────────────────────────────────────

select throws_ok(
  'select public.eliminar_area(811)',
  '55000', 'Cocina todavía tiene 1 categoría; cámbiala de área primero',
  'Un área con categorías sigue sin eliminarse'
);

select is(
  tests.filas($$ update public.categorias set area_preparacion_id = null where id = 611 $$),
  1,
  'Don Chuy pasa los tacos a «Se entrega directo»…'
);

select is(
  public.eliminar_area(811),
  'archivado',
  '… y elimina su última área (ya recibió comandas, así que se archiva)'
);

select is_empty(
  $$ select id from public.areas_preparacion
     where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and archivado_at is null $$,
  'La Fonda se queda sin áreas'
);

select is(
  public.mandar_a_cocina('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', gen_random_uuid(),
    '[{"producto_id": 511, "cantidad": 1}]', p_venta_id => tests.id('mesa_b')),
  tests.id('mesa_b'),
  'Y le sigue mandando a la mesa…'
);

select is(
  (select count(*) from public.comandas where venta_id = tests.id('mesa_b')),
  1::bigint,
  '… sin comandas nuevas: todo se entrega directo'
);

reset role;


-- ─── Las reglas de ventas ─────────────────────────────────────────────────────
-- Directo en la tabla, como postgres, en D.

select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo) values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comer_aqui') $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_cliente_nombre"',
  'Una cuenta sin mesa lleva nombre o número'
);

select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre) values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'mostrador', 'Ana') $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_tipo_valido"',
  'El tipo es mesa, comer aquí, para llevar o domicilio'
);

select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre, pedido_numero)
     values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comer_aqui', 'Ana', 0) $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_pedido_numero"',
  'El número va del 1 en adelante'
);

select throws_ok(
  $$ insert into public.ventas (restaurante_id, origen, tipo, cliente_nombre)
     values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'menu_en_linea', 'para_llevar', 'Rosa') $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_pedido_numero"',
  'Una cuenta del menú en línea siempre lleva su número'
);

select throws_ok(
  $$ update public.ventas set pedido_numero = 9 where id = $$ || tests.id('mesa_b'),
  '23514', 'new row for relation "ventas" violates check constraint "ventas_pedido_numero"',
  'Una cuenta de mesa nunca lleva número'
);

select throws_ok(
  $$ insert into public.ventas (restaurante_id, tipo, pedido_numero, cliente_telefono)
     values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comer_aqui', 3, '2229876543') $$,
  '23514', 'new row for relation "ventas" violates check constraint "ventas_domicilio"',
  'Comer aquí no lleva teléfono'
);

select lives_ok(
  $$ insert into public.ventas (restaurante_id, tipo, cliente_nombre, pedido_numero) values
       ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comer_aqui', null, 1),
       ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'comer_aqui', 'Ana', null),
       ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'para_llevar', null, 2) $$,
  'Comer aquí o para llevar, con solo el número o con solo el nombre'
);


-- ─── El número cuando vuelve un día ───────────────────────────────────────────
-- Si cambió la hora de corte, el día de folios ya no es hoy aunque hoy ya haya números: sigue después del
-- último, de las cuentas del punto de venta y de los pedidos.

update public.folios set pedidos_dia = tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 1, pedidos_ultimo = 99
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select tests.guardar('v7', tests.vender('comer_aqui', '[{"producto_id": 501, "cantidad": 1}]'));
reset role;

select is(
  (select pedido_numero from public.ventas where id = tests.id('v7')),
  7,
  'Sigue después de la última cuenta del punto de venta de hoy: #7 (y no el 100 de otro día)'
);

update public.folios set pedidos_dia = tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 1
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.como_worker();
select tests.guardar('p8', (tests.pedir() ->> 'numero')::bigint);
reset role;

select is(
  tests.id('p8'),
  8::bigint,
  'Un pedido del menú en línea también sigue después de las cuentas del punto de venta: #8'
);

update public.pedidos_en_linea set numero = 20
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and numero = 3;
update public.folios set pedidos_dia = tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 1
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.como_worker();
select tests.guardar('p21', (tests.pedir() ->> 'numero')::bigint);
reset role;

select is(
  tests.id('p21'),
  21::bigint,
  'Y después del último pedido del menú en línea, si es mayor: #21'
);

-- C: ayer llegó al #50 en el punto de venta y al #60 en el menú en línea; hoy no ha vendido nada.
insert into public.folios (restaurante_id, pedidos_dia, pedidos_ultimo)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.hoy('cccccccc-cccc-4ccc-8ccc-cccccccccccc') - 1, 60);
insert into public.pedidos_en_linea (restaurante_id, dia, numero, tipo, cliente_nombre, cliente_telefono, total, clave,
                                     marca_celular, marca_conexion)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.hoy('cccccccc-cccc-4ccc-8ccc-cccccccccccc') - 1, 60, 'para_llevar',
        'Rosa Ramírez', '2221234567', 22, gen_random_uuid(), repeat('a', 64), repeat('b', 64));
insert into public.ventas (restaurante_id, tipo, pedido_numero, created_at)
select r.id, 'comer_aqui', 50,
       privado.inicio_de_dia(r.zona_horaria, r.hora_corte, tests.hoy(r.id) - 1) + interval '1 hour'
from public.restaurantes r
where r.id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select is(
  privado.numero_del_dia('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.hoy('cccccccc-cccc-4ccc-8ccc-cccccccccccc')),
  1,
  'Un día nuevo empieza en el #1, aunque ayer llegara al #50 en el punto de venta y al #60 en el menú'
);

select is(
  privado.numero_del_dia('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', tests.hoy('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')),
  1,
  'El primer número de un restaurante es el #1'
);


-- ─── El nombre de una cuenta ──────────────────────────────────────────────────

select results_eq(
  $$ select privado.nombre_de_cuenta('Mesa 4', 'Sr. Ramírez', null), privado.nombre_de_cuenta(null, 'Sr. Ramírez', null),
            privado.nombre_de_cuenta(null, null, 23), privado.nombre_de_cuenta(null, 'Rosa Ramírez', 27) $$,
  $$ values ('Mesa 4'::text, 'Sr. Ramírez'::text, '#23'::text, 'Rosa Ramírez'::text) $$,
  'Una cuenta se llama por su mesa, el nombre del cliente o su número'
);

select results_eq(
  $$ select x.rol, has_function_privilege(x.rol, 'privado.numero_del_dia(uuid, date)', 'execute'),
            has_function_privilege(x.rol, 'privado.nombre_de_cuenta(text, text, integer)', 'execute')
     from (values ('anon'::text), ('authenticated'), ('service_role')) as x (rol) order by 1 $$,
  $$ values ('anon'::text, false, false), ('authenticated', false, false), ('service_role', false, false) $$,
  'Nadie con sesión, ni el Worker, llama directo a las dos funciones nuevas'
);


-- ─── Cancelar, cobrar y los reportes ──────────────────────────────────────────

select tests.authenticate_as('caja_a');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select is(
  public.cancelar_cuenta(tests.id('v6'), 'Se fue sin pedir') ->> 'ok',
  'true',
  'Lupita cancela la #6'
);

select tests.guardar('turno', public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500));
-- La #1 se cobra con 4 pesos de descuento en sus conchas; la #2 con 5 pesos de descuento a toda la cuenta; a
-- la #4 se le cancela un pago mal anotado; a la #5 se le pone y se le quita un descuento; de la #7 se cancela su
-- concha.
select public.descontar(tests.id('v1'), (select id from public.venta_items where venta_id = tests.id('v1')),
                        'pesos', 4, 'Pan de ayer');
select public.cobrar(tests.id('v1'), gen_random_uuid(), 'tarjeta', 40);
select public.descontar(tests.id('v3'), null, 'pesos', 5, 'Cliente frecuente');
select public.cobrar(tests.id('v3'), gen_random_uuid(), 'tarjeta', 30);
select public.cobrar(tests.id('v4'), gen_random_uuid(), 'tarjeta', 10);
select public.cancelar_pago((select id from public.pagos where venta_id = tests.id('v4')), 'Mal anotado');
select public.descontar(tests.id('v5'), null, 'pesos', 2, 'Cliente frecuente');
select public.quitar_descuento(tests.id('v5'));
select public.cancelar_renglon((select id from public.venta_items where venta_id = tests.id('v7')), 1, 'Se quemó');

select tests.authenticate_as('gerente_a');

select is(
  (select detalle ->> 'cuenta' from public.bitacora where accion = 'cancelar_cuenta' and registro_id = tests.id('v6')::text),
  '#6',
  'La bitácora la llama «#6»'
);

select is(
  (select jsonb_agg(jsonb_build_object('que', x ->> 'que', 'cuenta', x ->> 'cuenta', 'tipo', x ->> 'tipo'))
   from jsonb_array_elements(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') #> '{cancelaciones,lista}') x),
  '[{"que": "cuenta", "cuenta": "#6", "tipo": "comer_aqui"}, {"que": "renglon", "cuenta": "#7", "tipo": "comer_aqui"}]'::jsonb,
  'En Cortes, la cuenta cancelada es «#6» y la concha cancelada es de la «#7», las dos para comer aquí'
);

select is(
  (select jsonb_agg(x ->> 'cuenta')
   from jsonb_array_elements(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') #> '{descuentos,lista}') x),
  '["#1", "#2"]'::jsonb,
  'Los descuentos son de la «#1» (en sus conchas) y de la «#2» (a toda la cuenta)'
);

select is(
  public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') #>> '{turnos,0,pagos_cancelados,0,cuenta}',
  '#4',
  'El pago cancelado es de la «#4»'
);

select is(
  (select jsonb_agg(x ->> 'cuenta')
   from jsonb_array_elements(public.reporte_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'otros') x
   where x ->> 'accion' = 'quitar_descuento'),
  '["#5"]'::jsonb,
  'El descuento quitado es de la «#5»'
);


-- ─── El agente ────────────────────────────────────────────────────────────────

select is(
  (public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle',
     jsonb_build_object('folio', (select folio from public.ventas where id = tests.id('v1')))) -> 'cuentas' -> 0)
    - 'dia' - 'abierta' - 'cerrada' - 'renglones' - 'pagos',
  jsonb_build_object('folio', (select folio from public.ventas where id = tests.id('v1')), 'cuenta', '#1',
                     'tipo', 'comer aquí', 'abrio', 'Lupita', 'estado', 'cerrada', 'motivo', null,
                     'descuento_a_la_cuenta', null, 'total', '$40'),
  'El detalle de una cuenta sin nombre: «#1», para comer aquí'
);

select is(
  (select jsonb_build_object('cuentas', jsonb_array_length(r -> 'cuentas'), 'leido', r -> 'leido' ->> 'texto')
   from (select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'detalle',
           jsonb_build_object('mesa', 'comer aqui', 'desde', tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
                              'hasta', tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'))) as r) x),
  '{"cuentas": 1, "leido": "Las cuentas cerradas de hoy, para comer aquí"}'::jsonb,
  'El agente entiende «comer aqui», también sin acento'
);

select is(
  (select jsonb_agg(g ->> 'nombre')
   from jsonb_array_elements(public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
          jsonb_build_object('agrupar_por', 'mesa', 'desde', tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
                             'hasta', tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'))) -> 'grupos') g),
  '["Comer aquí", "Para llevar"]'::jsonb,
  'Por mesa, lo de comer aquí sale como «Comer aquí»'
);

select is(
  (select jsonb_build_object('total', r -> 'total' ->> 'importe', 'leido', r -> 'leido' ->> 'texto')
   from (select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
           jsonb_build_object('agrupar_por', 'producto', 'mesa', 'Comer aquí',
                              'desde', tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
                              'hasta', tests.hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'))) as r) x),
  '{"total": "$40", "leido": "Lo vendido hoy, por producto, para comer aquí"}'::jsonb,
  'Con el filtro «Comer aquí» solo cuenta lo de comer aquí'
);

select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ranking',
       '{"agrupar_por": "producto", "desde": "2026-10-01", "hasta": "2026-10-01", "mesa": "Terraza"}') $$,
  '22023', 'No hay una mesa «Terraza». Las que hay: Comer aquí, Para llevar, A domicilio.',
  'Sin mesas, el error dice que hay comer aquí, para llevar y a domicilio'
);

select is(
  public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'mesas',
  '["Comer aquí", "Para llevar", "A domicilio"]'::jsonb,
  'Al agente le llegan comer aquí, para llevar y a domicilio'
);

select is(
  (select jsonb_agg(jsonb_build_object('cuenta', x ->> 'cuenta', 'tipo', x ->> 'tipo'))
   from jsonb_array_elements(public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') #> '{cuentas_abiertas,lista}') x),
  '[{"cuenta": "Sr. Ramírez", "tipo": "comer aquí"}, {"cuenta": "#4", "tipo": "a domicilio"},
    {"cuenta": "#5", "tipo": "comer aquí"}, {"cuenta": "#7", "tipo": "comer aquí"}]'::jsonb,
  'Y sus cuentas abiertas, con su nombre o su número y su tipo'
);

reset role;


select * from finish();
rollback;
