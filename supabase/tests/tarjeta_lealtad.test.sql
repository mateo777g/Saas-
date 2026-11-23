-- Pruebas de la migración tarjeta_lealtad (23 de noviembre de 2026; planes/trabajo/tarjeta-lealtad/): la regla de cada
-- sucursal y cómo se ve; sacar la tarjeta desde el menú (por el Worker), con sus límites; ponerla en una cuenta y sumar
-- al cerrarse pagada (sellos y puntos), regresar lo sumado si un pago cancelado la reabre; canjear el premio con el QR
-- o el código corto (un producto en $0 o un descuento en pesos) y regresarlo si sale de la cuenta; apagarla; pasar de
-- sellos a puntos; el premio en un pedido del menú; pasar la tarjeta a otro celular; la tabla del gerente; borrarla
-- (ella, el gerente y la tarea de cada noche) y lo que se borra cada hora.
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
-- Se siembra como postgres, con ids fijos. A es La Fonda de Don Chuy (México, corte a las 6, color #2B5BAA): recibe
-- pedidos ahora y hace envíos. Pepe es mesero, Lupita la caja y Chente la cocina, cada quien en su aparato. B es La
-- Fonda · Norte, de otro gerente. Los tacos y la Gringa van a la Cocina (área 751); el refresco y el flan los sirve el
-- mesero. La quesadilla pide elegir su salsa. Rosa saca su tarjeta con el 222 987 6543; Mario con el 555 123 4567.

-- Lo que contesta el Worker, guardado con nombre (la llave y el código corto solo salen una vez).
create table tests.respuestas (nombre text primary key, valor jsonb not null);
grant select on tests.respuestas to anon, authenticated, service_role;

create function tests.guardar_json(p_nombre text, p_valor jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  insert into tests.respuestas (nombre, valor) values (p_nombre, p_valor)
  on conflict (nombre) do update set valor = excluded.valor
  returning valor;
$$;

create function tests.json(p_nombre text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select valor from tests.respuestas where nombre = p_nombre;
$$;

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

-- Lo juntado de una tarjeta de A, por su teléfono.
create function tests.saldo(p_telefono text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select saldo from public.tarjetas_lealtad
  where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and telefono = p_telefono
$$;

-- La regla de A, como la guarda la tabla.
create function tests.regla()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('prendida', prendida, 'forma', forma, 'meta', meta, 'minimo', minimo,
                            'pesos_por_punto', pesos_por_punto, 'premio_tipo', premio_tipo,
                            'premio_producto_id', premio_producto_id, 'premio_pesos', premio_pesos,
                            'estilo', estilo, 'color', color)
  from public.lealtad where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
$$;

-- El último pago que sigue en pie de una cuenta.
create function tests.ultimo_pago(p_venta_id bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select max(id) from public.pagos where venta_id = p_venta_id and cancelado_at is null
$$;

-- El renglón activo de un producto en una cuenta.
create function tests.renglon(p_venta_id bigint, p_producto_id bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select max(id) from public.venta_items where venta_id = p_venta_id and producto_id = p_producto_id and estado = 'activo'
$$;

-- El día de negocio de A, hoy.
create function tests.hoy()
returns date
language sql
stable
as $$
  select privado.dia_de_negocio('America/Mexico_City', 6::smallint)
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Como en producción, la sesión corre en UTC.
set local time zone 'UTC';

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_local timestamp := now() at time zone 'America/Mexico_City';
begin
  perform tests.create_supabase_user('chuy', 'chuy@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('lupita', 'lupita@prueba.test');
  perform tests.create_supabase_user('chente', 'chente@prueba.test');
  perform tests.create_supabase_user('norte', 'norte@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, telefono,
                                   hace_envios, menu_color) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, '2221234567', true, '#2B5BAA'),
    (b, 'La Fonda · Norte', 'fonda-norte', true, hoy - 30, hoy + 30, '2227654321', false, null);

  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select a, d, date_trunc('minute', v_local - interval '3 hours')::time, date_trunc('minute', v_local + interval '3 hours')::time
  from generate_series(1, 7) as d;

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
    (701, a, 'Mesa 1', 1), (702, a, 'Mesa 2', 2), (703, a, 'Mesa 3', 3), (704, a, 'Mesa 4', 4),
    (705, a, 'Mesa 5', 5), (706, a, 'Mesa 6', 6), (707, a, 'Mesa 7', 7), (708, a, 'Mesa 8', 8);

  insert into public.areas_preparacion (id, restaurante_id, nombre) overriding system value values (751, a, 'Cocina');

  insert into public.categorias (id, restaurante_id, nombre, icono, area_preparacion_id) overriding system value values
    (601, a, 'Tacos', 'taco', 751), (602, a, 'Bebidas', 'refresco', null), (611, b, 'Tacos', 'taco', null);

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco al pastor', 25, true),
    (502, a, 601, 'Gringa', 85, true),
    (503, a, 602, 'Refresco', 28, true),
    (504, a, 601, 'Quesadilla', 40, true),
    (506, a, 602, 'Flan', 30, true),
    (511, b, 611, 'Taco del Norte', 30, true);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, es_envio) overriding system value values
    (505, a, 601, 'Envío', 30, true, true);

  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Salsa', 1, 1);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Verde', 0, true, 1);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values (a, 504, 901);
end;
$$;

select plan(142);


-- ─── Las tablas y quién las lee ───────────────────────────────────────────────

select has_table('public', 'lealtad', 'Hay tabla de la regla de la tarjeta de lealtad');
select has_table('public', 'tarjetas_lealtad', 'Hay tabla de tarjetas');
select has_table('public', 'movimientos_lealtad', 'Hay tabla de movimientos de las tarjetas');
select has_table('public', 'codigos_lealtad', 'Hay tabla de códigos para pasar una tarjeta');
select has_table('public', 'solicitudes_lealtad', 'Hay tabla de solicitudes del menú');

select ok(
  (select bool_and(not has_table_privilege(r, t, p))
   from unnest(array['anon', 'authenticated']) r,
        unnest(array['public.tarjetas_lealtad', 'public.movimientos_lealtad', 'public.codigos_lealtad',
                     'public.solicitudes_lealtad']) t,
        unnest(array['select', 'insert', 'update', 'delete']) p),
  'Las tarjetas, sus movimientos, los códigos y las solicitudes no los lee ni los escribe nadie con sesión'
);

select ok(
  has_column_privilege('authenticated', 'public.lealtad', 'prendida', 'SELECT')
  and not has_table_privilege('authenticated', 'public.lealtad', 'insert')
  and not has_table_privilege('authenticated', 'public.lealtad', 'update')
  and not has_table_privilege('authenticated', 'public.lealtad', 'delete')
  and not has_table_privilege('anon', 'public.lealtad', 'select'),
  'La regla la leen los miembros; nadie la escribe directo'
);

select ok(
  (select bool_and(has_function_privilege('service_role', f, 'EXECUTE')
                   and not has_function_privilege('anon', f, 'EXECUTE')
                   and not has_function_privilege('authenticated', f, 'EXECUTE'))
   from unnest(array['public.sacar_tarjeta(text, text, text, boolean, text, text)',
                     'public.pedir_codigo_tarjeta(text, text, text, text)',
                     'public.mi_tarjeta(text, text)', 'public.borrar_mi_tarjeta(text, text)']) f),
  'Lo del menú solo lo llama el Worker, con la llave secreta'
);

select ok(
  (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE')
                   and not has_function_privilege('anon', f, 'EXECUTE')
                   and not has_function_privilege('service_role', f, 'EXECUTE'))
   from unnest(array['public.guardar_regla_lealtad(uuid, integer, numeric, numeric, text, bigint, numeric)',
                     'public.guardar_tu_tarjeta(uuid, text, text, text)', 'public.prender_lealtad(uuid, boolean)',
                     'public.tarjetas_de_lealtad(uuid)', 'public.tarjeta_del_cliente(uuid, text)',
                     'public.ligar_tarjeta(bigint, text, text, text)', 'public.quitar_tarjeta(bigint)',
                     'public.canjear_premio(bigint, uuid, text, text)', 'public.tarjeta_de_la_cuenta(bigint)',
                     'public.pasar_tarjeta(uuid, text, text)']) f),
  'Lo del panel y del aparato pide sesión'
);

select ok(
  (select bool_and(not has_function_privilege(r, p.oid, 'EXECUTE'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
        unnest(array['anon', 'authenticated', 'service_role']) r
   where n.nspname = 'privado'
     and p.proname in ('mover_saldo', 'texto_al_azar', 'llave_al_azar', 'codigo_corto_al_azar', 'huella_codigo_corto',
                       'aviso_del_premio', 'premio_canjeable', 'sellos_o_puntos', 'premio_escrito', 'canje_en_la_cuenta',
                       'tarjeta_en_json', 'tarjeta_por_llave', 'tarjeta_del_celular', 'meter_premio',
                       'lealtad_de_la_cuenta', 'regresar_premio', 'premio_del_renglon', 'premio_de_la_cuenta',
                       'lealtad_del_pedido', 'restaurante_del_menu', 'solicitud_lealtad', 'premio_del_pedido',
                       'borrar_tarjetas_viejas', 'borrar_solicitudes_viejas')),
  'Las funciones de adentro no las llama nadie desde afuera, ni el Worker'
);

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'hacer_pedido')::int,
  1,
  'hacer_pedido es una sola, con la llave de la tarjeta al final'
);


-- ─── La regla, la tarjeta y el interruptor (el gerente) ──────────────────────

select tests.entrar('pepe');
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, null, 'producto', 502, null) $$,
  '42501', 'Solo el gerente de este restaurante cambia su tarjeta de lealtad',
  'Pepe no pone la regla'
);
reset role;

select tests.entrar('norte');
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, null, 'producto', 502, null) $$,
  '42501', 'Solo el gerente de este restaurante cambia su tarjeta de lealtad',
  'Ni el gerente de otro restaurante'
);
reset role;

select tests.entrar('chuy');
select throws_ok(
  $$ select public.prender_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  '55000', 'Pon tu regla y tu premio antes de prenderla',
  'Sin regla no se prende'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 21, 50, null, 'producto', 502, null) $$,
  '22023', 'Con sellos, el premio pide de 2 a 20',
  'Con sellos, de 2 a 20'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, null, null, 'producto', 502, null) $$,
  '22023', 'Escribe desde cuánto gana su sello una cuenta (0 es cualquiera)',
  'Con sellos, el mínimo es obligatorio'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, null, 'producto', 504, null) $$,
  '22023', '«Quesadilla» pide elegir opciones: elige un producto que no las pida',
  'El premio no puede pedir opciones'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, null, 'producto', 505, null) $$,
  '22023', 'Un costo de envío no puede ser el premio',
  'Ni ser un envío'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, null, 'producto', 511, null) $$,
  '23503', 'Ese producto ya no está en tu menú',
  'Ni ser de otro restaurante'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, null, null, null, null) $$,
  '22023', 'Elige el premio: un producto gratis o un descuento',
  'Sin premio no se guarda'
);
reset role;

select is((select count(*) from public.lealtad)::int, 0, 'Lo que no se guardó no dejó fila');

select tests.entrar('chuy');
select lives_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, 50, 7, 'producto', 502, 99) $$,
  'Don Chuy pone su regla: 10 sellos, un sello desde $50, una Gringa gratis'
);
reset role;

select is(
  tests.regla(),
  '{"prendida": false, "forma": "sellos", "meta": 10, "minimo": 50, "pesos_por_punto": null, "premio_tipo": "producto",
    "premio_producto_id": 502, "premio_pesos": null, "estilo": "metal", "color": "#121212"}'::jsonb,
  'Nace apagada, en Metal y negra; con sellos se ignoran los pesos por punto, y con producto los pesos del premio'
);

select tests.clear_authentication();
select is(
  public.menu_publico('fonda-don-chuy') -> 'tarjeta',
  '{"prendida": false}'::jsonb,
  'Apagada con su regla, el menú solo sabe que existe'
);
reset role;

select tests.entrar('chuy');
select lives_ok(
  $$ select public.prender_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  'Con su regla, la prende'
);
reset role;

select tests.clear_authentication();
select is(
  (public.menu_publico('fonda-don-chuy') -> 'tarjeta') - 'premio',
  '{"prendida": true, "forma": "sellos", "meta": 10, "minimo": 50, "pesos_por_punto": null, "estilo": "metal",
    "color": "#121212"}'::jsonb,
  'Prendida, el menú recibe su regla, su estilo y su color: negra aunque el menú sea azul'
);
select is(
  (public.menu_publico('fonda-don-chuy') -> 'tarjeta' -> 'premio') - 'pesos_usd' - 'nombre_en',
  '{"tipo": "producto", "producto_id": 502, "nombre": "Gringa", "pesos": null, "disponible": true}'::jsonb,
  'Y su premio, que se puede canjear'
);
reset role;

select tests.entrar('pepe');
select is(
  (select prendida from public.lealtad where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  true,
  'Pepe lee la regla de su sucursal, para la fila «Tarjeta» del cobro'
);
reset role;

select tests.entrar('norte');
select is((select count(*) from public.lealtad)::int, 0, 'El gerente de B no ve la de A');
reset role;

select tests.entrar('chuy');
select is(
  public.guardar_tu_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sellos', 'olas', ''),
  0,
  'Tu tarjeta en Olas y «Del color de tu menú»: sin cambiar la forma, nada vuelve a 0'
);
reset role;

select tests.clear_authentication();
select is(
  public.menu_publico('fonda-don-chuy') -> 'tarjeta' ->> 'color',
  '#2B5BAA',
  'Del color de tu menú: el menú recibe el color del restaurante, ya resuelto'
);
reset role;

select tests.entrar('chuy');
select throws_ok(
  $$ select public.guardar_tu_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sellos', 'oro', null) $$,
  '22023', 'Elige el estilo de tu tarjeta',
  'Solo los seis estilos'
);
select throws_ok(
  $$ select public.guardar_tu_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sellos', 'metal', '#abc') $$,
  '22023', 'El color va como #1A2B3C',
  'El color va con sus seis letras'
);
select public.guardar_tu_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sellos', 'metal', ' #1a2b3c ');
reset role;

select is(tests.regla() ->> 'color', '#1A2B3C', 'El color se guarda limpio y en mayúsculas');


-- ─── Sacar la tarjeta en el menú (el Worker) ──────────────────────────────────

select tests.entrar('chuy');
select throws_ok(
  $$ select public.sacar_tarjeta('fonda-don-chuy', 'Rosa', '2229876543', true, repeat('1', 64), repeat('c', 64)) $$,
  '42501', null,
  'Con sesión no se saca una tarjeta: solo por el Worker'
);
reset role;

select tests.como_worker();
select is(
  public.sacar_tarjeta('fonda-norte', 'Rosa', '2229876543', true, repeat('1', 64), repeat('c', 64)),
  '{"ok": false, "motivo": "no_hay"}'::jsonb,
  'En un menú sin tarjeta, no hay'
);
select throws_ok(
  $$ select public.sacar_tarjeta('fonda-don-chuy', 'Rosa', '2229876543', false, repeat('1', 64), repeat('c', 64)) $$,
  '22023', 'Marca «Acepto el aviso de privacidad»',
  'Sin la casilla del aviso no se saca'
);
select throws_ok(
  $$ select public.sacar_tarjeta('fonda-don-chuy', 'Rosa', '22298765', true, repeat('1', 64), repeat('c', 64)) $$,
  '22023', 'Tu teléfono lleva 10 dígitos, como 222 123 4567.',
  'El teléfono lleva 10 dígitos'
);
select tests.guardar_json('rosa',
  public.sacar_tarjeta('fonda-don-chuy', '  Rosa Ramírez ', '222 987 6543', true, repeat('1', 64), repeat('c', 64)));
select ok(
  (tests.json('rosa') ->> 'ok')::boolean
  and tests.json('rosa') ->> 'llave' ~ '^[A-Za-z0-9_-]{43}$'
  and tests.json('rosa') ->> 'codigo' ~ '^[A-HJKMNP-Z2-9]{8}$',
  'Rosa saca su tarjeta: le regresa una vez su llave (43 letras) y su código corto (8, sin I, L, O, 0 ni 1)'
);
select is(
  (tests.json('rosa') -> 'tarjeta') - 'sacada',
  '{"nombre": "Rosa Ramírez", "telefono": "2229876543", "saldo": 0, "premio_listo": false, "ultima_compra": null,
    "movimientos": []}'::jsonb,
  'Y su tarjeta, con su nombre limpio y su número'
);
reset role;

select ok(
  exists (
    select 1 from public.tarjetas_lealtad
    where telefono = '2229876543'
      and llave_hash = privado.huella_aparato(tests.json('rosa') ->> 'llave')
      and codigo_hash = privado.huella_codigo_corto(tests.json('rosa') ->> 'codigo')
      and aviso_aceptado_at is not null and saldo = 0),
  'La base guarda solo las huellas de su llave y de su código, y cuándo aceptó el aviso'
);
select tests.guardar('rosa', (select id from public.tarjetas_lealtad where telefono = '2229876543'));

select tests.como_worker();
select is(
  public.sacar_tarjeta('fonda-don-chuy', 'Rosa', '2229876543', true, repeat('1', 64), repeat('c', 64)),
  '{"ok": false, "motivo": "ya_existe"}'::jsonb,
  'Con un número que ya tiene tarjeta, el menú ofrece recuperarla'
);
select tests.guardar_json('mario',
  public.sacar_tarjeta('fonda-don-chuy', 'Mario', '555 123 4567', true, repeat('1', 64), repeat('c', 64)));
select is((tests.json('mario') ->> 'ok')::boolean, true, 'Mario la saca desde el mismo celular: la tercera de la hora');
select is(
  public.sacar_tarjeta('fonda-don-chuy', 'Luis', '5550001111', true, repeat('1', 64), repeat('c', 64)),
  '{"ok": false, "motivo": "limite_celular"}'::jsonb,
  'La cuarta de la hora desde ese celular, ya no'
);
reset role;

select tests.guardar('mario', (select id from public.tarjetas_lealtad where telefono = '5551234567'));

insert into public.solicitudes_lealtad (restaurante_id, marca_celular, marca_conexion)
select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', lpad(n::text, 64, '0'), repeat('d', 64) from generate_series(1, 10) n;

select tests.como_worker();
select is(
  public.sacar_tarjeta('fonda-don-chuy', 'Luis', '5550001111', true, repeat('2', 64), repeat('d', 64)),
  '{"ok": false, "motivo": "limite_conexion"}'::jsonb,
  'Y desde una conexión, 10 por hora'
);
reset role;

select is(
  (select count(*) from public.solicitudes_lealtad where marca_celular = repeat('1', 64))::int,
  3,
  'Cuentan las que pasaron (también la que ya existía); la que se pasó, no'
);


-- ─── Su tarjeta en el menú ────────────────────────────────────────────────────

select tests.como_worker();
select ok(
  (public.mi_tarjeta('fonda-don-chuy', tests.json('rosa') ->> 'llave') ->> 'ok')::boolean
  and public.mi_tarjeta('fonda-don-chuy', tests.json('rosa') ->> 'llave') -> 'tarjeta' ->> 'nombre' = 'Rosa Ramírez',
  'Con su llave, el menú enseña su tarjeta'
);
select is(
  public.mi_tarjeta('fonda-don-chuy', repeat('x', 43)),
  '{"ok": false, "motivo": "no_existe"}'::jsonb,
  'Con otra llave, nada'
);
select is(
  public.mi_tarjeta('fonda-norte', tests.json('rosa') ->> 'llave'),
  '{"ok": false, "motivo": "no_existe"}'::jsonb,
  'Su tarjeta no existe en otra sucursal'
);
reset role;


-- ─── Ponerla en una cuenta y sumar al cerrarse ────────────────────────────────

select tests.entrar('lupita');
select public.abrir_turno('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 500);
reset role;

select tests.entrar('pepe');
select tests.guardar('mesa1', tests.cuenta(701, '[{"producto_id": 501, "cantidad": 2}, {"producto_id": 503, "cantidad": 1}]'));
reset role;

select tests.entrar('chente');
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, '2229876543') $$, tests.id('mesa1')),
  '42501', 'Solo meseros, caja y gerentes de este restaurante ponen la tarjeta',
  'La cocina no pone tarjetas'
);
reset role;

select tests.entrar('norte');
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, '2229876543') $$, tests.id('mesa1')),
  '55000', 'Esa cuenta ya no está abierta',
  'Ni otro restaurante: para él la cuenta no existe'
);
reset role;

select tests.entrar('pepe');
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, '2229876543', 'abc') $$, tests.id('mesa1')),
  '22023', 'Escanea su QR o escribe su número',
  'Con su número o con su QR, no con los dos'
);
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, '2220000000') $$, tests.id('mesa1')),
  'P0002', 'No hay una tarjeta con ese número',
  'Un número sin tarjeta'
);
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, p_codigo => 'AAAA2222') $$, tests.id('mesa1')),
  'P0002', 'Ese código no es de una tarjeta de aquí',
  'Un código que no es de aquí'
);
select is(
  public.ligar_tarjeta(tests.id('mesa1'), '222-987-6543') - 'id',
  '{"nombre": "Rosa Ramírez", "saldo": 0, "premio_listo": false, "con_qr": false}'::jsonb,
  'Pepe escribe su número: ve su nombre y lo juntado, nunca su teléfono, y con el número no canjea'
);
select is(
  (select tarjeta_lealtad_id from public.ventas where id = tests.id('mesa1')),
  tests.id('rosa'),
  'La cuenta queda con su tarjeta, y Pepe lo lee'
);
reset role;

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa1'), gen_random_uuid(), 'efectivo', 78, p_recibido => 100);
reset role;

select is(tests.saldo('2229876543'), 1, 'Al cerrarse pagada, la Mesa 1 ($78, desde $50) le suma un sello');
select ok(
  (select ultima_compra_at is not null from public.tarjetas_lealtad where id = tests.id('rosa'))
  and exists (select 1 from public.movimientos_lealtad
              where venta_id = tests.id('mesa1') and tipo = 'compra' and cantidad = 1
                and anotado_por is null and clave is null),
  'Un movimiento de compra, sin quién (se cerró sola), y su última compra'
);

select tests.entrar('pepe');
select tests.guardar('mesa2', tests.cuenta(702, '[{"producto_id": 501, "cantidad": 1}]'));
select is(
  public.ligar_tarjeta(tests.id('mesa2'), p_llave => tests.json('rosa') ->> 'llave') ->> 'con_qr',
  'true',
  'Con su QR, la cuenta queda lista también para canjear'
);
reset role;

update public.tarjetas_lealtad set ultima_compra_at = now() - interval '30 days' where id = tests.id('rosa');

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa2'), gen_random_uuid(), 'efectivo', 25, p_recibido => 25);
reset role;

select ok(
  tests.saldo('2229876543') = 1
  and (select ultima_compra_at > now() - interval '1 minute' from public.tarjetas_lealtad where id = tests.id('rosa')),
  'La Mesa 2 ($25) no llega al mínimo: no suma, pero cuenta como su última compra'
);


-- ─── Un pago cancelado le quita lo que sumó, y nunca suma dos veces ───────────

select tests.entrar('lupita');
select public.cancelar_pago(tests.ultimo_pago(tests.id('mesa1')), 'Se cobró a la mesa equivocada');
reset role;

select ok(
  tests.saldo('2229876543') = 0
  and exists (select 1 from public.movimientos_lealtad
              where venta_id = tests.id('mesa1') and tipo = 'regreso' and cantidad = -1),
  'La cuenta reabierta le quita su sello'
);

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa1'), gen_random_uuid(), 'efectivo', 78, p_recibido => 100);
reset role;

select ok(
  tests.saldo('2229876543') = 1
  and (select sum(cantidad) from public.movimientos_lealtad where venta_id = tests.id('mesa1')) = 1,
  'Al cerrarse otra vez, suma una sola vez'
);


-- ─── Canjear el premio: un producto ───────────────────────────────────────────

select tests.entrar('chuy');
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 2, 50, null, 'producto', 502, null);
reset role;
select is(tests.saldo('2229876543'), 1, 'Bajar la meta a 2 sellos respeta lo juntado');

select tests.entrar('pepe');
select tests.guardar('mesa3', tests.cuenta(703, '[{"producto_id": 501, "cantidad": 3}]'));
select public.ligar_tarjeta(tests.id('mesa3'), '2229876543');
reset role;
select tests.entrar('lupita');
select public.cobrar(tests.id('mesa3'), gen_random_uuid(), 'efectivo', 75, p_recibido => 100);
reset role;

select tests.entrar('pepe');
select is(
  public.tarjeta_de_la_cuenta(tests.id('mesa3')) - 'id',
  '{"nombre": "Rosa Ramírez", "saldo": 2, "premio_listo": true, "premio_en_cuenta": false}'::jsonb,
  'Con la Mesa 3, Rosa junta sus 2 sellos: su premio está listo'
);
select tests.guardar('mesa4', tests.cuenta(704, '[{"producto_id": 503, "cantidad": 1}]'));
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid()) $$, tests.id('mesa4')),
  '22023', 'Para canjear el premio, escanea su QR o escribe su código',
  'Canjear pide su QR o su código: con su número no se canjea'
);
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid(), p_codigo => 'AAAA2222') $$, tests.id('mesa4')),
  'P0002', 'Ese código no es de una tarjeta de aquí',
  'Un código que no es de aquí no canjea'
);
select is(
  public.canjear_premio(tests.id('mesa4'), '11111111-0000-4000-8000-000000000001',
    p_codigo => lower(substr(tests.json('rosa') ->> 'codigo', 1, 4) || ' ' || substr(tests.json('rosa') ->> 'codigo', 5))) - 'id',
  '{"nombre": "Rosa Ramírez", "saldo": 0, "premio_listo": false}'::jsonb,
  'Pepe escribe su código corto (en minúsculas y con espacio): canjea, y la tarjeta vuelve a 0'
);
reset role;

select is(
  (select jsonb_build_object('precio', i.precio_unitario, 'descuento', i.descuento, 'importe', i.importe,
                             'motivo', i.descuento_motivo, 'agregado_por', i.agregado_por, 'area', c.area_preparacion_id)
   from public.venta_items i
   join public.comandas c on c.id = i.comanda_id
   where i.venta_id = tests.id('mesa4') and i.producto_id = 502),
  '{"precio": 85, "descuento": 85, "importe": 0, "motivo": "Premio de la tarjeta", "agregado_por": 102, "area": 751}'::jsonb,
  'La Gringa entra en $0, con «Premio de la tarjeta», y va a la cocina'
);
select is(
  (select jsonb_build_object('total', total, 'tarjeta', tarjeta_lealtad_id) from public.ventas where id = tests.id('mesa4')),
  jsonb_build_object('total', 28, 'tarjeta', tests.id('rosa')),
  'La cuenta sigue en $28 y queda con su tarjeta'
);
select is(
  (select jsonb_build_object('cantidad', cantidad, 'renglon', venta_item_id = tests.renglon(tests.id('mesa4'), 502),
                             'anotado_por', anotado_por, 'clave', clave)
   from public.movimientos_lealtad where venta_id = tests.id('mesa4') and tipo = 'canje'),
  '{"cantidad": -2, "renglon": true, "anotado_por": 102, "clave": "11111111-0000-4000-8000-000000000001"}'::jsonb,
  'El canje resta los 2 sellos, apunta al renglón y lleva quién canjeó y la clave'
);
select is(
  (select jsonb_build_object('miembro', miembro_id, 'autoriza', autorizado_por, 'tabla', tabla,
                             'registro', registro_id = tests.id('mesa4')::text, 'detalle', detalle)
   from public.bitacora where accion = 'canjear_premio'),
  '{"miembro": 102, "autoriza": 102, "tabla": "ventas", "registro": true,
    "detalle": {"premio": "Gringa", "cantidad": 2, "forma": "sellos"}}'::jsonb,
  'La bitácora dice qué premio fue y cuántos sellos restó, sin el nombre ni el teléfono'
);

select tests.entrar('pepe');
select public.canjear_premio(tests.id('mesa4'), '11111111-0000-4000-8000-000000000001',
                             p_llave => tests.json('rosa') ->> 'llave');
reset role;
select is(
  (select count(*) from public.movimientos_lealtad where venta_id = tests.id('mesa4') and tipo = 'canje')::int,
  1,
  'La misma clave dos veces (doble toque) canjea una sola vez'
);

select tests.entrar('pepe');
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid(), p_llave => %L) $$, tests.id('mesa4'),
         tests.json('rosa') ->> 'llave'),
  '55000', 'Esta cuenta ya tiene un premio de la tarjeta',
  'Un premio por cuenta'
);
select throws_ok(
  format($$ select public.quitar_tarjeta(%s) $$, tests.id('mesa4')),
  '55000', 'Esta cuenta tiene su premio: quítalo antes',
  'Con su premio adentro, la tarjeta no se quita'
);
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, '5551234567') $$, tests.id('mesa4')),
  '55000', 'Esta cuenta ya tiene el premio de otra tarjeta',
  'Ni se cambia por otra'
);
select is(
  public.tarjeta_de_la_cuenta(tests.id('mesa4')) ->> 'premio_en_cuenta',
  'true',
  'El cobro sabe que su premio ya está en la cuenta'
);
reset role;


-- ─── El premio que sale de la cuenta regresa a la tarjeta ─────────────────────

select tests.entrar('chuy');
select public.cancelar_renglon(tests.renglon(tests.id('mesa4'), 502), 1, 'No la quiso');
reset role;

select ok(
  tests.saldo('2229876543') = 2
  and exists (select 1 from public.movimientos_lealtad m
              join public.movimientos_lealtad c on c.id = m.canje_id
              where m.tipo = 'devolucion' and m.cantidad = 2 and c.clave = '11111111-0000-4000-8000-000000000001'),
  'Cancelar el renglón del premio regresa sus 2 sellos, una vez, apuntando a su canje'
);

select tests.entrar('pepe');
select public.canjear_premio(tests.id('mesa4'), '11111111-0000-4000-8000-000000000002',
                             p_llave => tests.json('rosa') ->> 'llave');
reset role;
select is(tests.saldo('2229876543'), 0, 'Ya puede canjear otra vez en la misma cuenta: el premio de antes ya salió');

select tests.entrar('pepe');
select public.quitar_descuento(tests.id('mesa4'), tests.renglon(tests.id('mesa4'), 502));
reset role;
select ok(
  tests.saldo('2229876543') = 2 and (select total from public.ventas where id = tests.id('mesa4')) = 113,
  'Quitarle el descuento al premio lo regresa a la tarjeta, y la Gringa ya se cobra ($28 + $85)'
);

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa4'), gen_random_uuid(), 'efectivo', 113, p_recibido => 120);
reset role;
select is(tests.saldo('2229876543'), 3, 'La Mesa 4, de $113, le suma su sello');


-- ─── Canjear el premio: un descuento en pesos ─────────────────────────────────

select tests.entrar('chuy');
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 2, 50, null, 'pesos', null, 50);
reset role;

select tests.entrar('pepe');
select tests.guardar('mesa5', tests.cuenta(705, '[{"producto_id": 503, "cantidad": 1}]'));
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid(), p_llave => %L) $$, tests.id('mesa5'),
         tests.json('rosa') ->> 'llave'),
  '55000', 'El premio es de $50.00: esta cuenta todavía no llega a eso',
  'El descuento solo se canjea si la cuenta vale al menos eso'
);
select public.mandar_a_cocina('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', gen_random_uuid(),
                              '[{"producto_id": 501, "cantidad": 2}]', p_venta_id => tests.id('mesa5'));
reset role;

select tests.entrar('chuy');
select public.descontar(tests.id('mesa5'), null, 'porcentaje', 10, 'Cliente frecuente');
reset role;

select tests.entrar('pepe');
select public.canjear_premio(tests.id('mesa5'), '11111111-0000-4000-8000-000000000003',
                             p_llave => tests.json('rosa') ->> 'llave');
reset role;
select is(
  (select jsonb_build_object('tipo', descuento_tipo, 'valor', descuento_valor, 'motivo', descuento_motivo,
                             'descuento', descuento, 'total', total, 'saldo', tests.saldo('2229876543'))
   from public.ventas where id = tests.id('mesa5')),
  '{"tipo": "pesos", "valor": 50, "motivo": "Premio de la tarjeta", "descuento": 50, "total": 28, "saldo": 1}'::jsonb,
  'El premio en pesos reemplaza el descuento de la cuenta: $78 − $50'
);

select tests.entrar('chuy');
select public.descontar(tests.id('mesa5'), null, 'porcentaje', 10, 'Cliente frecuente');
reset role;
select is(tests.saldo('2229876543'), 3, 'Un descuento nuevo reemplaza al premio y lo regresa a la tarjeta');

select tests.entrar('pepe');
select public.canjear_premio(tests.id('mesa5'), '11111111-0000-4000-8000-000000000004',
                             p_llave => tests.json('rosa') ->> 'llave');
reset role;
select tests.entrar('chuy');
select public.cancelar_cuenta(tests.id('mesa5'), 'Se fueron');
reset role;
select is(tests.saldo('2229876543'), 3, 'Cancelar la cuenta con su premio lo regresa');

select tests.entrar('pepe');
select tests.guardar('mesa6', tests.cuenta(706, '[{"producto_id": 501, "cantidad": 2}, {"producto_id": 503, "cantidad": 1}]'));
reset role;
select tests.entrar('lupita');
select public.cobrar(tests.id('mesa6'), gen_random_uuid(), 'efectivo', 50, p_recibido => 50);
reset role;
select tests.entrar('pepe');
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid(), p_llave => %L) $$, tests.id('mesa6'),
         tests.json('rosa') ->> 'llave'),
  '55000', 'Ya se pagaron $50.00. Cancela antes un pago.',
  'El premio no deja la cuenta abajo de lo pagado'
);

select tests.guardar('mesa7', tests.cuenta(707, '[{"producto_id": 501, "cantidad": 2}]'));
select public.canjear_premio(tests.id('mesa7'), '11111111-0000-4000-8000-000000000005',
                             p_llave => tests.json('rosa') ->> 'llave');
select public.juntar_mesas(tests.id('mesa7'), tests.id('mesa6'));
reset role;
select is(tests.saldo('2229876543'), 3, 'Juntar la cuenta con su premio en pesos lo regresa: ese descuento se pierde');


-- ─── Apagada ──────────────────────────────────────────────────────────────────

select tests.entrar('pepe');
select tests.guardar('mesa8', tests.cuenta(708, '[{"producto_id": 501, "cantidad": 3}]'));
select public.ligar_tarjeta(tests.id('mesa8'), '2229876543');
reset role;

select tests.entrar('chuy');
select public.prender_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false);
reset role;

select tests.entrar('pepe');
select throws_ok(
  format($$ select public.ligar_tarjeta(%s, '2229876543') $$, tests.id('mesa6')),
  '55000', 'La tarjeta de lealtad está apagada',
  'Apagada, no se pone en una cuenta'
);
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid(), p_llave => %L) $$, tests.id('mesa6'),
         tests.json('rosa') ->> 'llave'),
  '55000', 'La tarjeta de lealtad está apagada',
  'Ni se canjea'
);
reset role;

select tests.como_worker();
select is(
  public.sacar_tarjeta('fonda-don-chuy', 'Ana', '5552223333', true, repeat('3', 64), repeat('e', 64)),
  '{"ok": false, "motivo": "no_hay"}'::jsonb,
  'Ni se saca'
);
select is(
  (public.mi_tarjeta('fonda-don-chuy', tests.json('rosa') ->> 'llave') ->> 'ok')::boolean,
  true,
  'Pero Rosa sigue viendo su tarjeta'
);
reset role;

select tests.clear_authentication();
select is(public.menu_publico('fonda-don-chuy') -> 'tarjeta', '{"prendida": false}'::jsonb, 'El menú sabe que existe, apagada');
reset role;

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa8'), gen_random_uuid(), 'efectivo', 75, p_recibido => 100);
reset role;
select is(tests.saldo('2229876543'), 3, 'Apagada, la Mesa 8 se cierra con su tarjeta y no suma');


-- ─── De sellos a puntos ───────────────────────────────────────────────────────
-- Prendida otra vez, para ver que el cambio la apaga.

select tests.entrar('chuy');
select public.prender_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select is(
  public.guardar_tu_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'puntos', 'metal', '#1A2B3C'),
  1,
  'Pasar a puntos pone en 0 la tarjeta de Rosa (la de Mario ya estaba en 0)'
);
reset role;

select ok(
  tests.saldo('2229876543') = 0
  and tests.regla() @> '{"forma": "puntos", "meta": null, "minimo": null, "pesos_por_punto": null, "prendida": false,
                         "premio_tipo": "pesos", "premio_pesos": 50}'::jsonb
  and exists (select 1 from public.movimientos_lealtad
              where tarjeta_id = tests.id('rosa') and tipo = 'reinicio' and cantidad = -3 and anotado_por = 101),
  'Se lleva los números de la regla y la apaga; el premio se queda; el reinicio queda con quién'
);

select tests.entrar('chuy');
select throws_ok(
  $$ select public.prender_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true) $$,
  '55000', 'Pon tu regla y tu premio antes de prenderla',
  'Sin sus números, no se prende'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10001, null, 10, 'pesos', null, 50) $$,
  '22023', 'Con puntos, el premio pide de 1 a 10,000',
  'Con puntos, hasta 10,000'
);
select throws_ok(
  $$ select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 100, 50, null, 'pesos', null, 50) $$,
  '22023', 'Escribe cuántos pesos vale un punto',
  'Con puntos, los pesos por punto'
);
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 100, 50, 10, 'pesos', null, 50);
select public.prender_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
reset role;

select tests.entrar('lupita');
select public.cancelar_pago(tests.ultimo_pago(tests.id('mesa4')), 'Corrección');
reset role;
select is(tests.saldo('2229876543'), 0, 'Una cuenta de antes del cambio que se reabre no le quita nada: ya volvió a 0');

select tests.entrar('lupita');
select public.cobrar(tests.id('mesa4'), gen_random_uuid(), 'efectivo', 113, p_recibido => 120);
reset role;
select is(tests.saldo('2229876543'), 11, 'Con puntos, $113 a un punto por cada $10 son 11, hacia abajo');


-- ─── El premio en un pedido del menú ──────────────────────────────────────────

select tests.como_worker();
select is(
  public.hacer_pedido('fonda-don-chuy', '22222222-0000-4000-8000-000000000000', 'para_llevar', 'Rosa Ramírez',
    '2229876543', null, null, null, '[{"producto_id": 501, "cantidad": 2, "precio": 25}]', repeat('4', 64),
    repeat('f', 64), tests.json('rosa') ->> 'llave'),
  '{"ok": false, "motivo": "premio"}'::jsonb,
  'Con 11 de 100 puntos, «Usar mi premio» no alcanza: no se guarda nada'
);
reset role;
select is((select count(*) from public.pedidos_en_linea)::int, 0, 'Ni un pedido');

select tests.entrar('chuy');
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, null, 10, 'pesos', null, 50);
reset role;

select tests.como_worker();
select tests.guardar_json('p1',
  public.hacer_pedido('fonda-don-chuy', '22222222-0000-4000-8000-000000000001', 'para_llevar', 'Rosa Ramírez',
    '2229876543', null, null, null, '[{"producto_id": 501, "cantidad": 2, "precio": 25}]', repeat('4', 64),
    repeat('f', 64), tests.json('rosa') ->> 'llave'));
select is(
  tests.json('p1') -> 'premio',
  '{"tipo": "pesos", "nombre": null, "pesos": 50, "alcanza": true, "entro": false}'::jsonb,
  'Con 11 de 10 puntos, el pedido usa su premio ($50 de descuento), y el menú lo sabe'
);
reset role;
select tests.guardar('p1', (select id from public.pedidos_en_linea where clave = '22222222-0000-4000-8000-000000000001'));
select is(
  (select premio_tarjeta_id from public.pedidos_en_linea where id = tests.id('p1')),
  tests.id('rosa'),
  'El pedido guarda la tarjeta cuyo premio usa'
);

select tests.entrar('chuy');
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 20, null, 10, 'pesos', null, 50);
reset role;

select tests.entrar('lupita');
select is(
  public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'por_confirmar' -> 0 -> 'premio' ->> 'alcanza',
  'false',
  'Si la meta sube a 20 antes de confirmar, Pedidos avisa que su premio ya no alcanza'
);
select tests.guardar('v1', public.confirmar_pedido(tests.id('p1')));
reset role;

select ok(
  (select descuento = 0 and tarjeta_lealtad_id = tests.id('rosa') from public.ventas where id = tests.id('v1'))
  and tests.saldo('2229876543') = 11,
  'Su cuenta nace sin premio, pero con su tarjeta'
);
select tests.entrar('lupita');
select is(
  public.pedidos_del_dia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'atendidos' -> 0 -> 'premio' ->> 'entro',
  'false',
  'Y Pedidos dice que el premio no entró'
);
reset role;

select tests.entrar('chuy');
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, null, 10, 'pesos', null, 50);
reset role;

select tests.como_worker();
select throws_ok(
  $$ select public.hacer_pedido('fonda-don-chuy', '22222222-0000-4000-8000-000000000009', 'domicilio', 'Rosa Ramírez',
       '2229876543', 'Calle 1', null, 80, '[{"producto_id": 501, "cantidad": 2, "precio": 25},
       {"producto_id": 502, "cantidad": 1, "precio": 85}]', repeat('5', 64), repeat('f', 64), tests.json('rosa') ->> 'llave') $$,
  '22023', 'Con $80.00 no alcanza: tu pedido es de $85.00',
  'Con premio en pesos, «paga con» se compara con el total menos el premio'
);
select tests.guardar_json('p2',
  public.hacer_pedido('fonda-don-chuy', '22222222-0000-4000-8000-000000000002', 'domicilio', 'Rosa Ramírez',
    '2229876543', 'Calle 1', null, 100, '[{"producto_id": 501, "cantidad": 2, "precio": 25},
    {"producto_id": 502, "cantidad": 1, "precio": 85}]', repeat('5', 64), repeat('f', 64), tests.json('rosa') ->> 'llave'));
select is((tests.json('p2') ->> 'ok')::boolean, true, 'Un pedido de $135 que paga con $100 sí cabe: $135 − $50');
select tests.guardar_json('p3',
  public.hacer_pedido('fonda-don-chuy', '22222222-0000-4000-8000-000000000003', 'para_llevar', 'Mario',
    '5551234567', null, null, null, '[{"producto_id": 503, "cantidad": 1, "precio": 28}]', repeat('6', 64),
    repeat('f', 64)));
reset role;
select tests.guardar('p2', (select id from public.pedidos_en_linea where clave = '22222222-0000-4000-8000-000000000002'));
select tests.guardar('p3', (select id from public.pedidos_en_linea where clave = '22222222-0000-4000-8000-000000000003'));
select ok(not (tests.json('p3') ? 'premio'), 'Un pedido sin premio sale como antes, sin la llave «premio»');

select tests.entrar('lupita');
select tests.guardar('v2', public.confirmar_pedido(tests.id('p2')));
select tests.guardar('v3', public.confirmar_pedido(tests.id('p3')));
reset role;

select is(
  (select jsonb_build_object('tipo', descuento_tipo, 'valor', descuento_valor, 'motivo', descuento_motivo, 'total', total,
                             'tarjeta', tarjeta_lealtad_id = tests.id('rosa'))
   from public.ventas where id = tests.id('v2')),
  '{"tipo": "pesos", "valor": 50, "motivo": "Premio de la tarjeta", "total": 85, "tarjeta": true}'::jsonb,
  'Al confirmarse, el premio entra a la cuenta del pedido'
);
select ok(
  tests.saldo('2229876543') = 1
  and exists (select 1 from public.movimientos_lealtad
              where tipo = 'canje' and cantidad = -10 and venta_id = tests.id('v2') and anotado_por = 103
                and clave = '22222222-0000-4000-8000-000000000002'),
  'A nombre de quien confirmó y con la clave del pedido: le resta sus 10 puntos'
);
select is(
  (select tarjeta_lealtad_id from public.ventas where id = tests.id('v3')),
  tests.id('mario'),
  'Un pedido sin premio lleva la tarjeta de su teléfono'
);

select tests.entrar('lupita');
select public.cobrar(tests.id('v1'), gen_random_uuid(), 'efectivo', 50, p_recibido => 50);
reset role;
select is(tests.saldo('2229876543'), 6, 'El pedido para llevar de Rosa, al cobrarse ($50), le suma 5 puntos');

select tests.entrar('lupita');
select public.cobrar(tests.id('v2'), gen_random_uuid(), 'efectivo', 85, p_recibido => 100);
reset role;
select is(tests.saldo('2229876543'), 14, 'Y el de $85 con su premio, 8');

select is(
  (select jsonb_build_object('motivo', d.motivo, 'pidio', d.pidio, 'autorizo', d.autorizo)
   from privado.descuentos_del_rango('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.hoy(), tests.hoy()) d
   where d.venta_id = tests.id('v2')),
  '{"motivo": "Premio de la tarjeta", "pidio": "Lupita", "autorizo": "Lupita"}'::jsonb,
  'En Cortes el premio sale con los descuentos, con quién lo canjeó'
);


-- ─── Pasarla a otro celular ───────────────────────────────────────────────────

select tests.como_worker();
select is(
  public.pedir_codigo_tarjeta('fonda-don-chuy', '5550009999', repeat('7', 64), repeat('f', 64)),
  '{"ok": false, "motivo": "sin_tarjeta"}'::jsonb,
  'Un número sin tarjeta no pide código'
);
select tests.guardar_json('pasa',
  public.pedir_codigo_tarjeta('fonda-don-chuy', '222 987 6543', repeat('7', 64), repeat('f', 64)));
select ok(
  (tests.json('pasa') ->> 'ok')::boolean
  and tests.json('pasa') ->> 'codigo' ~ '^[A-HJKMNP-Z]{6}$'
  and tests.json('pasa') ->> 'llave' ~ '^[A-Za-z0-9_-]{43}$'
  and tests.json('pasa') ->> 'codigo_corto' ~ '^[A-HJKMNP-Z2-9]{8}$'
  and (tests.json('pasa') ->> 'vence')::timestamptz = now() + interval '10 minutes',
  'El celular nuevo pide su código: 6 letras que duran 10 minutos, y ya guarda su llave y su código corto nuevos'
);
select is(
  public.mi_tarjeta('fonda-don-chuy', tests.json('pasa') ->> 'llave') - 'vence',
  jsonb_build_object('ok', false, 'motivo', 'esperando', 'codigo', tests.json('pasa') ->> 'codigo'),
  'Con su llave nueva, el menú dice que espera que lo confirmen'
);
select is(
  (public.mi_tarjeta('fonda-don-chuy', tests.json('rosa') ->> 'llave') ->> 'ok')::boolean,
  true,
  'Mientras tanto, el celular viejo la sigue viendo'
);
reset role;

select tests.entrar('lupita');
select throws_ok(
  format($$ select public.pasar_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, '5551234567') $$,
         tests.json('pasa') ->> 'codigo'),
  'P0002', 'Ese código no existe, ya venció o no es de ese número',
  'El código tiene que ser del número que lo mandó'
);
reset role;

select tests.entrar('chente');
select throws_ok(
  format($$ select public.pasar_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, '2229876543') $$,
         tests.json('pasa') ->> 'codigo'),
  '42501', 'Solo meseros, caja y gerentes de este restaurante pasan tarjetas',
  'La cocina no pasa tarjetas'
);
reset role;

select tests.entrar('lupita');
select is(
  public.pasar_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', lower(tests.json('pasa') ->> 'codigo'), '222 987 6543') - 'id',
  '{"nombre": "Rosa Ramírez", "saldo": 14, "premio_listo": true}'::jsonb,
  'Lupita escribe el código y su número: la tarjeta pasa, con lo juntado'
);
reset role;

select is(
  (select jsonb_build_object('miembro', miembro_id, 'tabla', tabla, 'registro', registro_id = tests.id('rosa')::text,
                             'detalle', detalle)
   from public.bitacora where accion = 'pasar_tarjeta'),
  '{"miembro": 103, "tabla": "tarjetas_lealtad", "registro": true, "detalle": {}}'::jsonb,
  'La bitácora apunta quién lo confirmó, sin más'
);

select tests.como_worker();
select tests.guardar_json('vieja', public.mi_tarjeta('fonda-don-chuy', tests.json('rosa') ->> 'llave'));
select tests.guardar_json('nueva', public.mi_tarjeta('fonda-don-chuy', tests.json('pasa') ->> 'llave'));
reset role;
select ok(
  tests.json('vieja') = '{"ok": false, "motivo": "no_existe"}'::jsonb
  and (tests.json('nueva') ->> 'ok')::boolean
  and (select codigo_hash = privado.huella_codigo_corto(tests.json('pasa') ->> 'codigo_corto')
       from public.tarjetas_lealtad where id = tests.id('rosa'))
  and not exists (select 1 from public.codigos_lealtad where tarjeta_id = tests.id('rosa')),
  'El celular viejo ya no la ve, el nuevo sí, con su código corto nuevo, y el código se borró'
);
select is(
  (select jsonb_agg(m - 'dia') from jsonb_array_elements(tests.json('nueva') -> 'tarjeta' -> 'movimientos') with ordinality x(m, n)
   where n <= 4),
  '[{"tipo": "compra", "cantidad": 8, "origen": "menu_en_linea"}, {"tipo": "compra", "cantidad": 5, "origen": "menu_en_linea"},
    {"tipo": "canje", "cantidad": -10, "origen": "menu_en_linea"}, {"tipo": "compra", "cantidad": 11, "origen": "punto_de_venta"}]'::jsonb,
  'Su historial, lo más nuevo primero: lo que sumó y canjeó, en el local o en un pedido del menú'
);
select tests.como_worker();
select tests.guardar_json('pasa2',
  public.pedir_codigo_tarjeta('fonda-don-chuy', '2229876543', repeat('8', 64), repeat('f', 64)));
reset role;

update public.codigos_lealtad
set created_at = now() - interval '20 minutes', expira_at = now() - interval '10 minutes'
where tarjeta_id = tests.id('rosa');

select tests.entrar('lupita');
select throws_ok(
  format($$ select public.pasar_tarjeta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', %L, '2229876543') $$,
         tests.json('pasa2') ->> 'codigo'),
  'P0002', 'Ese código no existe, ya venció o no es de ese número',
  'A los 10 minutos ya no sirve'
);
reset role;

select tests.como_worker();
select public.pedir_codigo_tarjeta('fonda-don-chuy', '2229876543', repeat('9', 64), repeat('f', 64));
select public.pedir_codigo_tarjeta('fonda-don-chuy', '2229876543', repeat('b', 64), repeat('f', 64));
reset role;
select is(
  (select count(*) from public.codigos_lealtad where tarjeta_id = tests.id('rosa'))::int,
  1,
  'Pedir otro reemplaza al anterior: uno por tarjeta'
);


-- ─── Lo que ve Don Chuy ───────────────────────────────────────────────────────

select tests.entrar('chuy');
select is(
  (select t - 'id' - 'sacada' - 'ultima_compra'
   from jsonb_array_elements(public.tarjetas_de_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'tarjetas') t
   where t ->> 'nombre' = 'Rosa Ramírez'),
  '{"nombre": "Rosa Ramírez", "telefono": "2229876543", "saldo": 14, "premio_listo": true, "pide_celular": true}'::jsonb,
  'Su tabla: el teléfono (solo él lo ve), lo juntado, el premio listo y que pidió pasarla a otro celular'
);
reset role;

select tests.entrar('pepe');
select throws_ok(
  $$ select public.tarjetas_de_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante ve sus tarjetas de lealtad',
  'Pepe no ve la tabla'
);
reset role;

select tests.entrar('chuy');
select is(
  public.tarjeta_del_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '222 987 6543'),
  '{"nombre": "Rosa Ramírez", "saldo": 14, "forma": "puntos"}'::jsonb,
  '«Borrar los datos de un cliente» dice que también borra su tarjeta, y con cuánto'
);
select is(
  public.tarjeta_del_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '5550000000'),
  null,
  'Un número sin tarjeta, nada'
);
reset role;


-- ─── Cuando el premio no se puede canjear ─────────────────────────────────────

select tests.entrar('chuy');
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, null, 10, 'producto', 502, null);
select public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 502, true);
reset role;

select tests.clear_authentication();
select is(
  public.menu_publico('fonda-don-chuy') -> 'tarjeta' -> 'premio' ->> 'disponible',
  'false',
  'Con la Gringa agotada, el menú no ofrece «Usar mi premio»'
);
reset role;

select tests.entrar('pepe');
select tests.guardar('mesa9', tests.cuenta(701, '[{"producto_id": 503, "cantidad": 1}]'));
select throws_ok(
  format($$ select public.canjear_premio(%s, gen_random_uuid(), p_llave => %L) $$, tests.id('mesa9'),
         tests.json('pasa') ->> 'llave'),
  '55000', '«Gringa» está agotado: el premio se canjea cuando vuelva',
  'Ni se canjea'
);
reset role;

select tests.entrar('chuy');
select public.marcar_agotado('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 502, false);
select public.guardar_regla_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 10, null, 10, 'producto', 506, null);
select is(
  (select resultado from public.eliminar_producto(506)),
  'archivado',
  'Como el premio lo apunta, eliminar el flan lo archiva'
);
select is(
  public.tarjetas_de_lealtad('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'aviso_premio',
  '«Flan» ya no está en tu menú: cambia el premio',
  'Y la vista de Don Chuy lo avisa'
);
reset role;


-- ─── Borrarla ─────────────────────────────────────────────────────────────────

select tests.como_worker();
select is(
  public.borrar_mi_tarjeta('fonda-don-chuy', tests.json('mario') ->> 'llave'),
  '{"ok": true}'::jsonb,
  'Mario borra su tarjeta'
);
select is(
  public.borrar_mi_tarjeta('fonda-don-chuy', tests.json('mario') ->> 'llave'),
  '{"ok": false, "motivo": "no_existe"}'::jsonb,
  'Ya no existe'
);
reset role;

select ok(
  not exists (select 1 from public.tarjetas_lealtad where id = tests.id('mario'))
  and not exists (select 1 from public.movimientos_lealtad where tarjeta_id = tests.id('mario'))
  and (select tarjeta_lealtad_id is null from public.ventas where id = tests.id('v3'))
  and (select count(*) from public.bitacora where accion = 'borrar_datos_cliente') = 0,
  'Se fue para siempre: su cuenta se quedó sin ella y no se anotó'
);

select tests.entrar('chuy');
select is(
  public.borrar_datos_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '222 987 6543'),
  2,
  '«Borrar los datos de un cliente» con el número de Rosa: sus 2 pedidos'
);
reset role;

select ok(
  not exists (select 1 from public.tarjetas_lealtad where telefono = '2229876543')
  and (select detalle from public.bitacora where accion = 'borrar_datos_cliente')
      = '{"pedidos": 2, "cuentas": 2, "tarjeta": true}'::jsonb
  and (select bool_and(pedido.premio_tarjeta_id is null) from public.pedidos_en_linea pedido),
  'Y su tarjeta: la bitácora dice que borró una; los pedidos se quedan sin ella'
);


-- ─── Lo que se borra solo ─────────────────────────────────────────────────────

insert into public.tarjetas_lealtad (restaurante_id, nombre, telefono, llave_hash, codigo_hash, aviso_aceptado_at,
                                     ultima_compra_at, created_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Vieja', '5550000001', repeat('1', 64), repeat('1', 64),
   now() - interval '2 years', now() - interval '12 months' - interval '1 day', now() - interval '2 years'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Reciente', '5550000002', repeat('2', 64), repeat('2', 64),
   now() - interval '2 years', now() - interval '11 months', now() - interval '2 years'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Nunca', '5550000003', repeat('3', 64), repeat('3', 64),
   now() - interval '13 months', null, now() - interval '13 months');

select privado.vaciar_datos_viejos();

select is(
  (select array_agg(nombre order by nombre) from public.tarjetas_lealtad where nombre in ('Vieja', 'Reciente', 'Nunca')),
  array['Reciente'],
  'Cada noche se van las de 12 meses sin compras, y las que nunca compraron a los 12 de sacarlas'
);

insert into public.solicitudes_lealtad (restaurante_id, marca_celular, marca_conexion, created_at)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', repeat('a', 64), repeat('a', 64), now() - interval '2 hours');
insert into public.codigos_lealtad (restaurante_id, tarjeta_id, codigo, llave_hash, codigo_hash, expira_at, created_at)
select restaurante_id, id, 'ZZZZZZ', repeat('4', 64), repeat('4', 64), now() - interval '10 minutes', now() - interval '20 minutes'
from public.tarjetas_lealtad where nombre = 'Reciente';

select privado.borrar_preguntas_viejas();

select ok(
  not exists (select 1 from public.solicitudes_lealtad where created_at <= now() - interval '1 hour')
  and not exists (select 1 from public.codigos_lealtad where expira_at <= now())
  and exists (select 1 from public.solicitudes_lealtad),
  'Cada hora se van las solicitudes de más de una hora y los códigos vencidos'
);


select * from finish();

rollback;
