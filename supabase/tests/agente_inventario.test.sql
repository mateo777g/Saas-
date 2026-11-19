-- Pruebas de la migración agente_inventario (19 de noviembre de 2026; planes/trabajo/agente-inventario/): la séptima
-- herramienta del agente, inventario(ver, …), que lee lo que queda (con qué comprar y los días que alcanza), lo que se
-- perdió, lo que se gastó, lo que llegó y cuántos platillos alcanzan, con los números de la vista Inventario; y los
-- ingredientes en contexto_agente. Solo el gerente pregunta, y cada sucursal lee su propio inventario.
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
-- Se siembra como postgres, con ids fijos. El día de negocio de hoy es d0 (corte a las 6, en la zona de México); las
-- cuentas viejas se abren a mediodía de su día y se cierran ahora, así sus movimientos llevan la hora de hoy pero su
-- cuenta es de su día.
--   A, La Fonda de Don Chuy: Don Chuy (gerente), Pepe (mesero) y Chente (cocina), cada quien en su aparato. El Taco
--     al pastor lleva 100 g de Pastor, 2 Tortillas y 30 ml de Salsa verde (rinde 1 l con 0.5 kg de Tomate y 50 g de
--     Chile); la opción Queso, 30 g de Queso; la Quesadilla, una Tortilla y 50 g de Queso; el Agua de limon, 0.1 kg de
--     Limon (0.06 kg de Queso en la Quesadilla). El Refresco no tiene receta (solo su opción Con limon, 10 g de Limon),
--     el Envío es un costo y la Gringa está archivada (con receta).
--     Ventas: hace 30 días 20 tacos (fuera de las 4 semanas); de hace 7 días a ayer, 10 tacos cada día (la de ayer se
--     abrió a las 5:30 de hoy, que todavía es ayer, y lleva 4 quesadillas; la de hace 2 días se reabrió y se volvió a
--     cerrar; la de hace 5 días trae 3 tacos cancelados); hace 4 días otra cuenta de 2 tacos se cerró y se reabrió, y
--     sigue abierta, y hace 8 días una se canceló. Hoy, 5 tacos con Queso. La Cebolla se dio de alta hace 3 días y gastó 0.1 kg en cada cuenta desde
--     entonces. Se tiraron 1.5 kg de Limon (había 1) hace 3 días (a las 5:00 del día siguiente, que todavía es ese
--     día), y 0.2 kg de Pastor hace 7 días. El Carbon
--     se tiró hace 2 días y se archivó ayer. Llegaron 10 kg de Pastor hace 6 días; 100 Tortillas que llegaron hace 5
--     días se deshicieron, y también 1 kg de Pastor que se tiró ayer. Hoy Chente anota mermas y 2 cajas de Queso, y Don
--     Chuy cuenta el Pastor (faltan 0.3 kg) y las Tortillas (sobran 10).
--   B, La Fonda · Norte: otro gerente, con su propio Pastor (99 kg, justo en su mínimo) y Sal en 0.
--   C, La Fonda · Sur: sin ingredientes, con un platillo.

create table tests.anclas (nombre text primary key, dia date);
grant select on tests.anclas to anon, authenticated, service_role;

-- El día de negocio de hoy de A.
create function tests.d0()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select dia from tests.anclas where nombre = 'd0'
$$;

-- Un día en palabras, como lo escribe el agente («sábado 15 de noviembre»).
create function tests.palabras(p_dia date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select privado.fecha_en_palabras(p_dia, tests.d0())
$$;

-- Un periodo en palabras, como en «Lo que leí».
create function tests.periodo(p_desde date, p_hasta date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select privado.periodo(p_desde, p_hasta, tests.d0(), 'en')
$$;

-- La hora de ahora en la zona de A, como la dicen las mermas y llegadas de hoy.
create function tests.hora()
returns text
language sql
stable
as $$
  select to_char(now() at time zone 'America/Mexico_City', 'HH24:MI')
$$;

create function tests.entrar(p_quien text)
returns void as $$
begin
  perform tests.authenticate_as(p_quien);
  if p_quien = 'pepe' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
  elsif p_quien = 'chente' then perform tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000003');
  end if;
end
$$ language plpgsql;

-- La herramienta de A, como la llama el Worker con la sesión de quien entró.
create function tests.inv(p_args jsonb)
returns jsonb
language sql
as $$
  select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'inventario', p_args)
$$;

-- Una cuenta para llevar de A abierta en p_momento, con sus renglones [{producto, cantidad, opciones?, cancelado?}].
create function tests.cuenta(p_id bigint, p_momento timestamptz, p_renglones jsonb)
returns void
language plpgsql
as $$
declare
  v_r jsonb;
begin
  insert into public.ventas (id, restaurante_id, tipo, cliente_nombre, abierta_por, created_at, estado)
  overriding system value
  values (p_id, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'para_llevar', 'Cliente', 102, p_momento, 'abierta');
  for v_r in select x from jsonb_array_elements(p_renglones) x loop
    if coalesce((v_r ->> 'cancelado')::boolean, false) then
      insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva,
                                      agregado_por, clave_envio, opciones, estado, cancelado_por, autorizado_por,
                                      cancelado_motivo, cancelado_at)
      values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_id, (v_r ->> 'producto')::bigint, 'Platillo', 25,
              (v_r ->> 'cantidad')::integer, 16, 102, extensions.uuid_generate_v4(), coalesce(v_r -> 'opciones', '[]'),
              'cancelado', 102, 101, 'Se equivoco', p_momento + interval '5 minutes');
    else
      insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva,
                                      agregado_por, clave_envio, opciones)
      values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_id, (v_r ->> 'producto')::bigint, 'Platillo', 25,
              (v_r ->> 'cantidad')::integer, 16, 102, extensions.uuid_generate_v4(), coalesce(v_r -> 'opciones', '[]'));
    end if;
  end loop;
end;
$$;

-- Cierra una cuenta de A con su folio: el disparador del inventario resta su receta.
create function tests.cerrar(p_id bigint)
returns void
language sql
as $$
  update public.ventas
  set estado = 'cerrada', folio = coalesce(folio, p_id::integer - 7900), cerrada_por = 101, turno_id = 9101,
      cerrada_at = now()
  where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and id = p_id
$$;

-- Reabre una cuenta cerrada de A (un pago cancelado): regresa lo que restó.
create function tests.reabrir(p_id bigint)
returns void
language sql
as $$
  update public.ventas set estado = 'abierta'
  where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and id = p_id
$$;

-- Un movimiento a mano, como postgres, en un momento del pasado.
create function tests.mov(p_ingrediente bigint, p_tipo text, p_cantidad numeric, p_momento timestamptz,
                          p_anoto bigint default null, p_motivo text default null, p_nota text default null,
                          p_venta bigint default null, p_deshace bigint default null, p_restaurante uuid default null)
returns bigint
language sql
as $$
  insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, contado, motivo, nota,
                                             venta_id, deshace_id, anotado_por, clave, created_at)
  values (coalesce(p_restaurante, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), p_ingrediente, p_tipo, p_cantidad,
          case when p_tipo = 'conteo' then p_cantidad end, p_motivo, p_nota, p_venta, p_deshace, p_anoto,
          case when p_tipo not in ('venta', 'regreso') then extensions.uuid_generate_v4() end, p_momento)
  returning id
$$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;

set local time zone 'UTC';

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  hoy date := privado.dia_local('America/Mexico_City');
  d0 date := privado.dia_de_negocio('America/Mexico_City', 6::smallint);
  i0 timestamptz := privado.inicio_de_dia('America/Mexico_City', 6::smallint, d0);
  alta timestamptz := i0 - interval '40 days' + interval '1 hour';
  n integer;
  v_merma bigint;
  v_llego bigint;
begin
  insert into tests.anclas values ('d0', d0);

  perform tests.create_supabase_user('chuy', 'chuy@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('chente', 'chente@prueba.test');
  perform tests.create_supabase_user('norte', 'norte@prueba.test');
  perform tests.create_supabase_user('sur', 'sur@prueba.test');

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 60, hoy + 30),
    (b, 'La Fonda · Norte', 'fonda-norte', true, hoy - 60, hoy + 30),
    (c, 'La Fonda · Sur', 'fonda-sur', true, hoy - 60, hoy + 30);

  insert into public.miembros (id, restaurante_id, usuario_id, nombre, roles, activo) overriding system value values
    (101, a, tests.get_supabase_uid('chuy'), 'Don Chuy', '{gerente}', true),
    (102, a, tests.get_supabase_uid('pepe'), 'Pepe', '{mesero}', true),
    (105, a, tests.get_supabase_uid('chente'), 'Chente', '{cocina}', true),
    (111, b, tests.get_supabase_uid('norte'), 'Gerente Norte', '{gerente}', true),
    (121, c, tests.get_supabase_uid('sur'), 'Gerente Sur', '{gerente}', true);

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id) values
    (a, 'Celular de Pepe', 102, privado.huella_aparato(repeat('P', 43)), '5e5e5e5e-0000-4000-8000-000000000001'),
    (a, 'Tableta de la cocina', 105, privado.huella_aparato(repeat('C', 43)), '5e5e5e5e-0000-4000-8000-000000000003');

  insert into public.categorias (id, restaurante_id, nombre, icono) overriding system value values
    (601, a, 'Tacos', 'taco'), (602, a, 'Bebidas', 'refresco'), (621, c, 'Tacos', 'taco');
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible) overriding system value values
    (501, a, 601, 'Taco al pastor', 25, true),
    (504, a, 601, 'Quesadilla', 40, true),
    (502, a, 602, 'Refresco', 28, true),
    (505, a, 602, 'Agua de limon', 20, true),
    (521, c, 621, 'Taco del Sur', 30, true);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, es_envio) overriding system value values
    (503, a, 601, 'Envío', 30, true, true);
  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, visible, archivado_at) overriding system value values
    (506, a, 601, 'Gringa', 55, true, now());

  insert into public.grupos_opciones (id, restaurante_id, nombre, minimo, maximo) overriding system value values
    (901, a, 'Extras', 0, 2), (902, a, 'Con que', 0, 1);
  insert into public.opciones (id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden) overriding system value values
    (9011, a, 901, 'Queso', 10, true, 1),
    (9021, a, 902, 'Con limon', 0, true, 1);
  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id) values (a, 501, 901), (a, 502, 902);

  insert into public.turnos (id, restaurante_id, abierto_por, fondo_inicial, estado, created_at) overriding system value values
    (9101, a, 101, 500, 'abierto', alta);

  -- Los ingredientes, cada uno con su primer conteo (cuánto había al darlo de alta).
  insert into public.ingredientes (id, restaurante_id, nombre, unidad, por_caja, minimo, created_at) overriding system value values
    (801, a, 'Pastor', 'kg', null, 10, alta),
    (802, a, 'Tortilla', 'pieza', null, 20, alta),
    (803, a, 'Tomate', 'kg', null, null, alta),
    (804, a, 'Chile', 'g', null, 100, alta),
    (805, a, 'Queso', 'kg', 2, 1, alta),
    (806, a, 'Cebolla', 'kg', null, null, i0 - interval '3 days' + interval '1 hour'),
    (807, a, 'Limon', 'kg', null, 2, alta),
    (808, a, 'Carbon', 'kg', null, null, alta),
    (811, b, 'Pastor', 'kg', null, 99, alta),
    (812, b, 'Sal', 'kg', null, null, alta);
  perform tests.mov(801, 'conteo', 9.2, alta, 101);
  perform tests.mov(802, 'conteo', 220, alta, 101);
  perform tests.mov(803, 'conteo', 5.15, alta, 101);
  perform tests.mov(804, 'conteo', 315, alta, 101);
  perform tests.mov(805, 'conteo', 1, alta, 101);
  perform tests.mov(806, 'conteo', 2, i0 - interval '3 days' + interval '1 hour', 101);
  perform tests.mov(807, 'conteo', 1, alta, 101);
  perform tests.mov(808, 'conteo', 5, alta, 101);
  perform tests.mov(811, 'conteo', 99, alta, 111, p_restaurante => b);
  perform tests.mov(812, 'conteo', 0, alta, 111, p_restaurante => b);

  insert into public.preparaciones (id, restaurante_id, nombre, rinde, unidad) overriding system value values
    (851, a, 'Salsa verde', 1, 'l');
  insert into public.recetas (restaurante_id, producto_id, opcion_id, preparacion_id, ingrediente_id, lleva_preparacion_id, cantidad, unidad) values
    (a, null, null, 851, 803, null, 0.5, 'kg'),
    (a, null, null, 851, 804, null, 50, 'g'),
    (a, 501, null, null, 801, null, 100, 'g'),
    (a, 501, null, null, 802, null, 2, 'pieza'),
    (a, 501, null, null, null, 851, 30, 'ml'),
    (a, null, 9011, null, 805, null, 30, 'g'),
    (a, 504, null, null, 802, null, 1, 'pieza'),
    (a, 504, null, null, 805, null, 60, 'g'),
    (a, 505, null, null, 807, null, 0.1, 'kg'),
    (a, null, 9021, null, 807, null, 10, 'g'),
    (a, 506, null, null, 801, null, 0.1, 'kg');

  -- Las ventas.
  perform tests.cuenta(8030, i0 - interval '30 days' + interval '6 hours', '[{"producto": 501, "cantidad": 20}]');
  perform tests.cerrar(8030);
  for n in 2..7 loop
    perform tests.cuenta(8000 + n, i0 - make_interval(days => n) + interval '6 hours', '[{"producto": 501, "cantidad": 10}]');
  end loop;
  perform tests.cuenta(8001, i0 - interval '30 minutes', '[{"producto": 501, "cantidad": 10}, {"producto": 504, "cantidad": 4}]');
  insert into public.venta_items (restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, tasa_iva,
                                  agregado_por, clave_envio, estado, cancelado_por, autorizado_por, cancelado_motivo, cancelado_at)
  values (a, 8005, 501, 'Taco al pastor', 25, 3, 16, 102, extensions.uuid_generate_v4(), 'cancelado', 102, 101,
          'Se equivoco', i0 - interval '5 days' + interval '7 hours');
  for n in 1..7 loop
    perform tests.cerrar(8000 + n);
  end loop;
  perform tests.reabrir(8002);
  perform tests.cerrar(8002);
  perform tests.cuenta(8040, i0 - interval '4 days' + interval '8 hours', '[{"producto": 501, "cantidad": 2}]');
  perform tests.cuenta(8008, i0 - interval '8 days' + interval '6 hours', '[{"producto": 501, "cantidad": 4}]');
  update public.ventas set estado = 'cancelada', cancelada_motivo = 'Se fue sin pagar' where id = 8008;
  perform tests.cerrar(8040);
  perform tests.reabrir(8040);
  perform tests.cuenta(8000, i0 + (now() - i0) / 2,
    '[{"producto": 501, "cantidad": 5, "opciones": [{"grupo": "Extras", "opcion": "Queso", "precio_extra": 10}]}]');
  perform tests.cerrar(8000);

  -- La Cebolla, desde que se dio de alta.
  perform tests.mov(806, 'venta', -0.1, now(), p_venta => 8003);
  perform tests.mov(806, 'venta', -0.1, now(), p_venta => 8002);
  perform tests.mov(806, 'venta', -0.1, now(), p_venta => 8001);

  -- Lo que llegó, las mermas y lo deshecho de los días pasados.
  perform tests.mov(801, 'llegada', 10, i0 - interval '6 days' + interval '4 hours', 101);
  v_llego := tests.mov(802, 'llegada', 100, i0 - interval '5 days' + interval '4 hours', 101);
  perform tests.mov(802, 'deshacer', -100, i0 - interval '5 days' + interval '5 hours', 101, p_deshace => v_llego);
  perform tests.mov(801, 'merma', -0.2, i0 - interval '7 days' + interval '2 hours', 105, 'se_echo_a_perder');
  perform tests.mov(807, 'merma', -1.5, i0 - interval '2 days' - interval '1 hour', 101, 'caduco');
  perform tests.mov(801, 'merma', -0.5, i0 - interval '2 days' + interval '2 hours', 105, 'se_echo_a_perder');
  perform tests.mov(808, 'merma', -2, i0 - interval '2 days' + interval '3 hours', 105, 'otro', 'Se mojó');
  v_merma := tests.mov(801, 'merma', -1, i0 - interval '1 day' + interval '2 hours', 105, 'caduco');
  perform tests.mov(801, 'deshacer', 1, i0 - interval '1 day' + interval '3 hours', 101, p_deshace => v_merma);
  update public.ingredientes set archivado_at = i0 - interval '1 day' + interval '1 hour' where id = 808;
end;
$$;

select plan(87);


-- ─── Permisos y las palabras ──────────────────────────────────────────────────

select ok(
  not has_function_privilege('authenticated', 'privado.herramienta_inventario(uuid, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'privado.inventario_queda(uuid, bigint, boolean, integer)', 'execute')
  and not has_function_privilege('service_role', 'privado.inventario_perdido(uuid, date, date, bigint, text, integer)', 'execute')
  and not has_function_privilege('anon', 'privado.inventario_alcanza(uuid, bigint, integer)', 'execute')
  and not has_function_privilege('authenticated', 'privado.buscar_ingrediente(uuid, text, boolean)', 'execute'),
  'Las piezas de la séptima herramienta son privadas'
);

select ok(
  has_function_privilege('authenticated', 'public.agente_herramienta(uuid, text, jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.contexto_agente(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.agente_herramienta(uuid, text, jsonb)', 'execute')
  and not has_function_privilege('service_role', 'public.contexto_agente(uuid)', 'execute'),
  'agente_herramienta y contexto_agente guardan sus permisos'
);

select is(
  array[privado.cantidad_escrita(4.2, 'kg'), privado.cantidad_escrita(-0.4, 'kg'), privado.cantidad_escrita(1200.5, 'g'),
        privado.cantidad_escrita(1, 'pieza'), privado.cantidad_escrita(46, 'pieza'), privado.cantidad_escrita(0, 'kg'),
        privado.cantidad_escrita(10, 'l'), privado.cantidad_escrita(0.0004, 'kg'), privado.cantidad_escrita(2.0005, 'ml')],
  array['4.2 kg', '−0.4 kg', '1,200.5 g', '1 pieza', '46 piezas', '0 kg', '10 l', '0 kg', '2.001 ml'],
  'Las cantidades se escriben como en la vista Inventario'
);


-- ─── Lo de hoy: Chente y Don Chuy anotan ──────────────────────────────────────

select tests.entrar('chente');

select is(
  public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f0f0f0f0-0000-4000-8000-000000000001', 'se_cayo_o_quemo',
                      p_ingrediente_id => 801, p_cantidad => 0.3),
  1, 'Chente anota 0.3 kg de Pastor que se cayó'
);
select is(
  public.anotar_merma('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f0f0f0f0-0000-4000-8000-000000000002', 'se_cayo_o_quemo',
                      p_producto_id => 501, p_platillos => 3),
  4, 'Chente anota 3 tacos al pastor que se quemaron: 4 ingredientes'
);
select is(
  public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f0f0f0f0-0000-4000-8000-000000000003',
                        '[{"ingrediente_id": 805, "cajas": 2}]'),
  1, 'Chente anota 2 cajas de Queso'
);

select tests.entrar('chuy');

select is(
  public.anotar_conteo('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f0f0f0f0-0000-4000-8000-000000000004',
                       '[{"ingrediente_id": 801, "contado": 8.1}, {"ingrediente_id": 802, "contado": 30}]'),
  2, 'Don Chuy cuenta el Pastor y las Tortillas'
);

select is(
  (select jsonb_object_agg(nombre, existencia) from public.ingredientes
   where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '{"Pastor": 8.1, "Tortilla": 30, "Tomate": 3.68, "Chile": 168, "Queso": 4.61, "Cebolla": 1.7, "Limon": -0.5, "Carbon": 3}'::jsonb,
  'El escenario deja lo que dice la vista Inventario'
);


-- ─── Quién pregunta ───────────────────────────────────────────────────────────

select tests.entrar('pepe');
select throws_ok(
  $$ select tests.inv('{"ver": "queda"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Pepe (mesero) no le pregunta al inventario'
);

select tests.entrar('chente');
select throws_ok(
  $$ select tests.inv('{"ver": "queda"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Chente (cocina) tampoco: solo el gerente pregunta'
);

select tests.entrar('norte');
select throws_ok(
  $$ select tests.inv('{"ver": "queda"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'El gerente de otra sucursal no lee el inventario de A'
);

select is(
  public.agente_herramienta('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'inventario', '{"ver": "queda"}') -> 'ingredientes',
  '[{"ingrediente": "Sal", "queda": "0 kg", "como_va": "Se acabó", "sin_gasto": true},
    {"ingrediente": "Pastor", "queda": "99 kg", "minimo": "99 kg", "como_va": "Se acaba", "sin_gasto": true}]'::jsonb,
  'Cada sucursal lee su propio inventario; en 0 se acabó, y justo en su mínimo ya se acaba sin que le falte nada'
);

select tests.entrar('sur');
select is(
  public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'inventario', '{"ver": "queda"}')
    - 'leido',
  '{"ingredientes": [], "resto": null, "en_inventario": 0, "se_acabaron": 0, "se_acaban": 0, "ver": "queda",
    "sin_datos": true, "sin_ingredientes": true}'::jsonb,
  'Sin ingredientes, queda lo dice'
);
select is(
  public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'inventario', '{"ver": "alcanza"}')
    - 'leido',
  '{"platillos": [], "resto": null, "sin_receta": 1, "ver": "alcanza", "sin_datos": true, "sin_ingredientes": true}'::jsonb,
  'Sin ingredientes, alcanza lo dice y cuenta los platillos sin receta'
);
select throws_ok(
  $$ select public.agente_herramienta('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'inventario',
                                      '{"ver": "queda", "ingrediente": "Pastor"}') $$,
  '22023', 'No hay un ingrediente «Pastor». Todavía no hay ingredientes: se agregan en Inventario, en el panel.',
  'Sin ingredientes, buscar uno dice dónde se agregan'
);


-- ─── contexto_agente ──────────────────────────────────────────────────────────

select tests.entrar('chuy');

select is(
  public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'ingredientes',
  '[{"nombre": "Cebolla", "unidad": "kg"}, {"nombre": "Chile", "unidad": "g"}, {"nombre": "Limon", "unidad": "kg"},
    {"nombre": "Pastor", "unidad": "kg"}, {"nombre": "Queso", "unidad": "kg"}, {"nombre": "Tomate", "unidad": "kg"},
    {"nombre": "Tortilla", "unidad": "pieza"}]'::jsonb,
  'El contexto trae los ingredientes con su unidad, por nombre y sin los archivados'
);

select ok(
  (select array_agg(k order by k) from jsonb_object_keys(public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')) k)
    = array['ahora', 'categorias', 'como_llamarlo', 'cuentas_abiertas', 'equipo', 'ingredientes', 'menu', 'mesas',
            'primer_dia_con_ventas', 'restaurante'],
  'El contexto sigue con todo lo de antes'
);

select is(
  public.contexto_agente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'mesas',
  '["Comer aquí", "Para llevar", "A domicilio"]'::jsonb,
  'Las mesas del contexto siguen como en adaptabilidad'
);


-- ─── La puerta y los argumentos ───────────────────────────────────────────────

select throws_ok(
  $$ select public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'inventarios', '{}') $$,
  '22023',
  'No hay una herramienta «inventarios». Las que hay: resumen, ranking, comparar, detalle, proyeccion_mes, cancelaciones_descuentos_propinas, inventario.',
  'Una herramienta que no existe dice que ya son 7'
);

select ok(
  public.agente_herramienta('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'resumen',
    jsonb_build_object('desde', tests.d0() - 7, 'hasta', tests.d0())) ? 'leido',
  'Las otras herramientas siguen contestando'
);

select throws_ok($$ select tests.inv('{}') $$, '22023',
  'Falta ver. Opciones: queda, perdido, gastado, llego, alcanza.', 'ver es obligatorio');
select throws_ok($$ select tests.inv('{"ver": "todo"}') $$, '22023',
  '«todo» no es una opción de ver. Opciones: queda, perdido, gastado, llego, alcanza.', 'ver va de cinco');
select throws_ok($$ select tests.inv('{"ver": "queda", "color": "rojo"}') $$, '22023',
  'inventario no lleva «color». Lleva: ver, desde, hasta, ingrediente, producto, solo_lo_que_falta, agrupar_por, limite.',
  'Un argumento que no va dice los que sí');
select throws_ok($$ select tests.inv('{"ver": "queda", "desde": "2026-11-01"}') $$, '22023',
  'Con queda, inventario no lleva desde ni hasta: es lo de ahora. Llevan fechas: perdido, gastado y llego.',
  'queda no lleva fechas');
select throws_ok($$ select tests.inv('{"ver": "alcanza", "hasta": "2026-11-01"}') $$, '22023',
  'Con alcanza, inventario no lleva desde ni hasta: es lo de ahora. Llevan fechas: perdido, gastado y llego.',
  'alcanza tampoco');
select throws_ok($$ select tests.inv('{"ver": "perdido", "hasta": "2026-11-01"}') $$, '22023',
  'Falta desde: un día de negocio en AAAA-MM-DD.', 'perdido pide sus fechas');
select throws_ok($$ select tests.inv('{"ver": "gastado", "desde": "2026-11-05", "hasta": "2026-11-01"}') $$, '22023',
  'desde (2026-11-05) va después de hasta (2026-11-01).', 'Un rango al revés');
select throws_ok($$ select tests.inv('{"ver": "queda", "producto": "Taco al pastor"}') $$, '22023',
  'producto solo va con alcanza. Para un ingrediente, usa ingrediente.', 'producto solo con alcanza');
select throws_ok($$ select tests.inv('{"ver": "alcanza", "ingrediente": "Pastor"}') $$, '22023',
  'alcanza va por platillo: usa producto en vez de ingrediente.', 'alcanza no va por ingrediente');
select throws_ok($$ select tests.inv('{"ver": "llego", "desde": "2026-11-01", "hasta": "2026-11-02", "solo_lo_que_falta": true}') $$,
  '22023', 'solo_lo_que_falta solo va con queda.', 'solo_lo_que_falta solo con queda');
select throws_ok($$ select tests.inv('{"ver": "queda", "solo_lo_que_falta": "si"}') $$, '22023',
  'solo_lo_que_falta va con true o false.', 'solo_lo_que_falta es true o false');
select throws_ok($$ select tests.inv('{"ver": "perdido", "desde": "2026-11-01", "hasta": "2026-11-02", "agrupar_por": "dia"}') $$,
  '22023', 'agrupar_por dia pide un ingrediente: día por día va de uno solo. Sin ingrediente, agrupar_por ingrediente.',
  'Día por día pide un ingrediente');
select throws_ok($$ select tests.inv('{"ver": "queda", "agrupar_por": "ingrediente"}') $$, '22023',
  'agrupar_por solo va con perdido, gastado y llego.', 'agrupar_por no va con queda');
select throws_ok($$ select tests.inv('{"ver": "gastado", "desde": "2026-11-01", "hasta": "2026-11-02", "agrupar_por": "mesa"}') $$,
  '22023', '«mesa» no es una opción de agrupar_por. Opciones: ingrediente, dia.', 'agrupar_por va por ingrediente o día');
select throws_ok($$ select tests.inv('{"ver": "queda", "limite": 51}') $$, '22023',
  'limite va de 1 a 50.', 'El límite va de 1 a 50');
select throws_ok($$ select tests.inv('{"ver": "queda", "ingrediente": "Carbon"}') $$, '22023',
  'No hay un ingrediente «Carbon». Los que hay: Cebolla, Chile, Limon, Pastor, Queso, Tomate, Tortilla.',
  'queda no busca archivados, y el error trae los que hay');
select throws_ok($$ select tests.inv('{"ver": "alcanza", "producto": "Pozole"}') $$, '22023',
  'No hay un platillo «Pozole» en el menú. Los que hay: Taco al pastor, Quesadilla, Refresco, Agua de limon.',
  'Un platillo que no existe trae los del menú, sin envíos ni archivados');
select throws_ok($$ select tests.inv('{"ver": "alcanza", "producto": "Envío"}') $$, '22023',
  'No hay un platillo «Envío» en el menú. Los que hay: Taco al pastor, Quesadilla, Refresco, Agua de limon.',
  'Un envío no es platillo');


-- ─── ver = queda ──────────────────────────────────────────────────────────────

select is(
  tests.inv('{"ver": "queda"}') -> 'ingredientes',
  '[{"ingrediente": "Limon", "queda": "−0.5 kg", "minimo": "2 kg", "como_va": "Se acabó", "le_falta_para_su_minimo": "2.5 kg",
     "sin_gasto": true},
    {"ingrediente": "Pastor", "queda": "8.1 kg", "minimo": "10 kg", "como_va": "Se acaba",
     "le_falta_para_su_minimo": "1.9 kg", "alcanza_dias": 8.1, "es_estimado": true},
    {"ingrediente": "Cebolla", "queda": "1.7 kg", "como_va": "Bien", "alcanza_dias": 17.0, "es_estimado": true,
     "con_pocos_dias": true},
    {"ingrediente": "Chile", "queda": "168 g", "minimo": "100 g", "como_va": "Bien", "alcanza_dias": 11.2,
     "es_estimado": true},
    {"ingrediente": "Queso", "queda": "4.61 kg", "minimo": "1 kg", "como_va": "Bien", "alcanza_dias": 134.5,
     "es_estimado": true},
    {"ingrediente": "Tomate", "queda": "3.68 kg", "como_va": "Bien", "alcanza_dias": 24.5, "es_estimado": true},
    {"ingrediente": "Tortilla", "queda": "30 piezas", "minimo": "20 piezas", "como_va": "Bien", "alcanza_dias": 1.5,
     "es_estimado": true}]'::jsonb,
  'queda: lo que se acabó, lo que se acaba y lo demás, con su mínimo y los días que alcanza'
);

select is(
  tests.inv('{"ver": "queda"}') - 'ingredientes',
  jsonb_build_object('resto', null, 'en_inventario', 7, 'se_acabaron', 1, 'se_acaban', 1, 'ver', 'queda',
                     'sin_datos', false, 'sin_ingredientes', false,
                     'leido', jsonb_build_object('icono', 'datos', 'texto', 'Lo que queda hoy')),
  'queda cuenta cuántos hay, cuántos se acabaron y cuántos se acaban, y su renglón de «Lo que leí»'
);

select is(
  (select jsonb_agg(x ->> 'ingrediente') from jsonb_array_elements(
     tests.inv('{"ver": "queda", "solo_lo_que_falta": true}') -> 'ingredientes') x),
  '["Limon", "Pastor", "Tortilla"]'::jsonb,
  'Qué comprar: lo que se acabó, lo que se acaba y lo que no llega a 2 días'
);

select is(
  tests.inv('{"ver": "queda", "solo_lo_que_falta": true}') -> 'leido' ->> 'texto',
  'Lo que falta comprar',
  'Qué comprar en «Lo que leí»'
);

select is(
  tests.inv('{"ver": "queda", "solo_lo_que_falta": false}') -> 'en_inventario',
  '7'::jsonb,
  'solo_lo_que_falta en false es como no ponerlo'
);

select is(
  tests.inv('{"ver": "queda", "limite": 2}') -> 'resto',
  '{"ingredientes": 5}'::jsonb,
  'Con un límite, lo demás va en resto'
);

select is(
  tests.inv('{"ver": "queda", "limite": 2}') -> 'ingredientes' -> 1 ->> 'ingrediente',
  'Pastor',
  'El límite corta en el orden de la vista'
);

select is(
  tests.inv('{"ver": "queda", "ingrediente": " pastor "}') -> 'ingredientes',
  '[{"ingrediente": "Pastor", "queda": "8.1 kg", "minimo": "10 kg", "como_va": "Se acaba",
     "le_falta_para_su_minimo": "1.9 kg", "alcanza_dias": 8.1, "es_estimado": true}]'::jsonb,
  'queda de un ingrediente, por su nombre sin importar mayúsculas'
);

select is(
  tests.inv('{"ver": "queda", "ingrediente": "Pastor"}') -> 'leido' ->> 'texto',
  'Lo que queda de Pastor',
  'Lo que queda de un ingrediente en «Lo que leí»'
);

select is(
  tests.inv('{"ver": "queda", "ingrediente": "Tortilla", "solo_lo_que_falta": true}') -> 'leido' ->> 'texto',
  'Lo que falta comprar de Tortilla',
  'Qué comprar de un ingrediente en «Lo que leí»'
);

select is(
  tests.inv('{"ver": "queda", "ingrediente": "Cebolla", "solo_lo_que_falta": true}') -> 'sin_datos',
  'true'::jsonb,
  'Lo que alcanza para más de 2 días no está en qué comprar'
);


-- ─── ver = perdido ────────────────────────────────────────────────────────────

select is(
  (select jsonb_agg(x ->> 'ingrediente') from jsonb_array_elements(
     tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones') x),
  '["Carbon", "Chile", "Limon", "Pastor", "Tomate", "Tortilla"]'::jsonb,
  'perdido: por nombre, con el archivado que se tiró, sin lo deshecho ni el alta de la Cebolla'
);

select is(
  (tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones' -> 3)
    - 'recientes',
  '{"ingrediente": "Pastor", "mermas": "1.3 kg", "veces": 4,
    "por_motivo": [{"motivo": "Se echó a perder", "cantidad": "0.7 kg"}, {"motivo": "Se cayó o se quemó", "cantidad": "0.6 kg"}],
    "falto_al_contar": "0.3 kg", "se_perdio": "1.6 kg"}'::jsonb,
  'Lo perdido del Pastor: sus mermas por motivo y lo que faltó al contar'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones' -> 3
    -> 'recientes',
  jsonb_build_array(
    jsonb_build_object('cuando', 'hoy a las ' || tests.hora(), 'cantidad', '0.3 kg', 'motivo', 'Se cayó o se quemó',
                       'platillo', '3 × Taco al pastor', 'anoto', 'Chente · cocina'),
    jsonb_build_object('cuando', 'hoy a las ' || tests.hora(), 'cantidad', '0.3 kg', 'motivo', 'Se cayó o se quemó',
                       'anoto', 'Chente · cocina'),
    jsonb_build_object('cuando', 'el ' || tests.palabras(tests.d0() - 2) || ' a las 08:00', 'cantidad', '0.5 kg',
                       'motivo', 'Se echó a perder', 'anoto', 'Chente · cocina')),
  'Las 3 mermas más recientes del Pastor, con el platillo entero y quién las anotó'
);

select is(
  (tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones' -> 5)
    #- '{recientes,0,cuando}',
  '{"ingrediente": "Tortilla", "mermas": "6 piezas", "veces": 1,
    "por_motivo": [{"motivo": "Se cayó o se quemó", "cantidad": "6 piezas"}], "falto_al_contar": "0 piezas",
    "se_perdio": "6 piezas", "sobro_al_contar": "10 piezas",
    "recientes": [{"cuando": "hoy a las HH", "cantidad": "6 piezas", "motivo": "Se cayó o se quemó",
                   "platillo": "3 × Taco al pastor", "anoto": "Chente · cocina"}]}'::jsonb
    #- '{recientes,0,cuando}',
  'Lo que sobró al contar las Tortillas va aparte y no se resta de lo perdido'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones' -> 0
    -> 'recientes',
  jsonb_build_array(jsonb_build_object('cuando', 'el ' || tests.palabras(tests.d0() - 2) || ' a las 09:00',
                                       'cantidad', '2 kg', 'motivo', 'Otro', 'nota', 'Se mojó', 'anoto', 'Chente · cocina')),
  'Una merma con «Otro» trae su nota'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones' -> 1
    ->> 'mermas',
  '4.5 g',
  'La merma de un platillo entero sale en sus ingredientes, también los de su preparación'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'mermas_anotadas',
  '6'::jsonb,
  'Seis mermas anotadas: la de un platillo entero cuenta una'
);

select is(
  (select jsonb_agg(x ->> 'ingrediente') from jsonb_array_elements(
     tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 2, 'hasta', tests.d0())) -> 'renglones') x),
  '["Carbon", "Chile", "Pastor", "Tomate", "Tortilla"]'::jsonb,
  'El Limon se tiró a las 5:00, todavía del día de negocio anterior'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 3, 'hasta', tests.d0() - 3)) -> 'renglones',
  jsonb_build_array(jsonb_build_object(
    'ingrediente', 'Limon', 'mermas', '1.5 kg', 'veces', 1,
    'por_motivo', jsonb_build_array(jsonb_build_object('motivo', 'Caducó', 'cantidad', '1.5 kg')),
    'falto_al_contar', '0 kg', 'se_perdio', '1.5 kg',
    'recientes', jsonb_build_array(jsonb_build_object(
      'cuando', 'el ' || tests.palabras(tests.d0() - 3) || ' a las 05:00', 'cantidad', '1.5 kg', 'motivo', 'Caducó',
      'anoto', 'Don Chuy')))),
  'Hace 3 días: el Limon (con quién lo anotó, el gerente por su nombre) y no el alta de la Cebolla'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 1, 'hasta', tests.d0() - 1)),
  jsonb_build_object('renglones', '[]'::jsonb, 'resto', null, 'mermas_anotadas', 0, 'ver', 'perdido',
                     'desde', tests.d0() - 1, 'hasta', tests.d0() - 1, 'agrupar_por', 'ingrediente',
                     'sin_datos', true, 'sin_ingredientes', false,
                     'leido', jsonb_build_object('icono', 'datos', 'texto', 'Lo que se perdió ayer')),
  'Ayer no se perdió nada: la merma que se deshizo no cuenta'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0(),
                               'ingrediente', 'Pastor', 'agrupar_por', 'dia')) -> 'renglones',
  jsonb_build_array(
    jsonb_build_object('dia', tests.palabras(tests.d0() - 7), 'fecha', tests.d0() - 7, 'mermas', '0.2 kg', 'veces', 1,
      'por_motivo', jsonb_build_array(jsonb_build_object('motivo', 'Se echó a perder', 'cantidad', '0.2 kg')),
      'falto_al_contar', '0 kg', 'se_perdio', '0.2 kg',
      'recientes', jsonb_build_array(jsonb_build_object(
        'cuando', 'el ' || tests.palabras(tests.d0() - 7) || ' a las 08:00', 'cantidad', '0.2 kg',
        'motivo', 'Se echó a perder', 'anoto', 'Chente · cocina'))),
    jsonb_build_object('dia', tests.palabras(tests.d0() - 2), 'fecha', tests.d0() - 2, 'mermas', '0.5 kg', 'veces', 1,
      'por_motivo', jsonb_build_array(jsonb_build_object('motivo', 'Se echó a perder', 'cantidad', '0.5 kg')),
      'falto_al_contar', '0 kg', 'se_perdio', '0.5 kg',
      'recientes', jsonb_build_array(jsonb_build_object(
        'cuando', 'el ' || tests.palabras(tests.d0() - 2) || ' a las 08:00', 'cantidad', '0.5 kg',
        'motivo', 'Se echó a perder', 'anoto', 'Chente · cocina'))),
    jsonb_build_object('dia', tests.palabras(tests.d0()), 'fecha', tests.d0(), 'mermas', '0.6 kg', 'veces', 2,
      'por_motivo', jsonb_build_array(jsonb_build_object('motivo', 'Se cayó o se quemó', 'cantidad', '0.6 kg')),
      'falto_al_contar', '0.3 kg', 'se_perdio', '0.9 kg',
      'recientes', jsonb_build_array(
        jsonb_build_object('cuando', 'hoy a las ' || tests.hora(), 'cantidad', '0.3 kg', 'motivo', 'Se cayó o se quemó',
                           'platillo', '3 × Taco al pastor', 'anoto', 'Chente · cocina'),
        jsonb_build_object('cuando', 'hoy a las ' || tests.hora(), 'cantidad', '0.3 kg', 'motivo', 'Se cayó o se quemó',
                           'anoto', 'Chente · cocina')))),
  'Lo perdido del Pastor día por día'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0(),
                               'ingrediente', 'pastor', 'agrupar_por', 'dia')) -> 'leido' ->> 'texto',
  'Lo que se perdió de Pastor ' || tests.periodo(tests.d0() - 7, tests.d0()) || ', día por día',
  'Lo perdido de un ingrediente día por día en «Lo que leí»'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0(), 'ingrediente', 'carbon'))
    -> 'renglones' -> 0 ->> 'ingrediente',
  'Carbon',
  'Un periodo sí busca los ingredientes archivados'
);

select is(
  tests.inv(jsonb_build_object('ver', 'perdido', 'desde', tests.d0() - 7, 'hasta', tests.d0(), 'limite', 2))
    -> 'resto',
  '{"renglones": 4}'::jsonb,
  'Lo perdido también lleva su límite'
);


-- ─── ver = gastado ────────────────────────────────────────────────────────────

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0() - 7, 'hasta', tests.d0() - 1)) -> 'renglones',
  '[{"ingrediente": "Cebolla", "gastado": "0.3 kg", "cuentas": 3},
    {"ingrediente": "Chile", "gastado": "105 g", "cuentas": 7},
    {"ingrediente": "Pastor", "gastado": "7 kg", "cuentas": 7},
    {"ingrediente": "Queso", "gastado": "0.24 kg", "cuentas": 1},
    {"ingrediente": "Tomate", "gastado": "1.05 kg", "cuentas": 7},
    {"ingrediente": "Tortilla", "gastado": "144 piezas", "cuentas": 7}]'::jsonb,
  'gastado: lo que restaron las ventas, con la reabierta una vez, sin la que sigue abierta ni lo cancelado'
);

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0() - 7, 'hasta', tests.d0() - 1)) -> 'cuentas',
  '7'::jsonb,
  'Siete cuentas restaron algo'
);

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0(), 'hasta', tests.d0())) -> 'renglones',
  '[{"ingrediente": "Chile", "gastado": "7.5 g", "cuentas": 1},
    {"ingrediente": "Pastor", "gastado": "0.5 kg", "cuentas": 1},
    {"ingrediente": "Queso", "gastado": "0.15 kg", "cuentas": 1},
    {"ingrediente": "Tomate", "gastado": "0.075 kg", "cuentas": 1},
    {"ingrediente": "Tortilla", "gastado": "10 piezas", "cuentas": 1}]'::jsonb,
  'Lo gastado hoy: la opción Queso cuenta; la cuenta de ayer que se cerró hoy no'
);

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0() - 1, 'hasta', tests.d0() - 1, 'ingrediente', 'Queso'))
    -> 'renglones',
  '[{"ingrediente": "Queso", "gastado": "0.24 kg", "cuentas": 1}]'::jsonb,
  'Lo gastado cuenta en el día de su cuenta: la de ayer abierta a las 5:30'
);

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0() - 7, 'hasta', tests.d0(),
                               'ingrediente', 'Pastor', 'agrupar_por', 'dia', 'limite', 3)),
  jsonb_build_object(
    'renglones', jsonb_build_array(
      jsonb_build_object('dia', tests.palabras(tests.d0() - 7), 'fecha', tests.d0() - 7, 'gastado', '1 kg', 'cuentas', 1),
      jsonb_build_object('dia', tests.palabras(tests.d0() - 6), 'fecha', tests.d0() - 6, 'gastado', '1 kg', 'cuentas', 1),
      jsonb_build_object('dia', tests.palabras(tests.d0() - 5), 'fecha', tests.d0() - 5, 'gastado', '1 kg', 'cuentas', 1)),
    'resto', jsonb_build_object('renglones', 5), 'cuentas', 8, 'ver', 'gastado',
    'desde', tests.d0() - 7, 'hasta', tests.d0(), 'ingrediente', 'Pastor', 'agrupar_por', 'dia',
    'sin_datos', false, 'sin_ingredientes', false,
    'leido', jsonb_build_object('icono', 'datos',
      'texto', 'Lo que se gastó de Pastor ' || tests.periodo(tests.d0() - 7, tests.d0()) || ', día por día')),
  'Lo gastado del Pastor día por día, con su límite'
);

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0() - 1, 'hasta', tests.d0() - 1)) -> 'leido' ->> 'texto',
  'Lo que se gastó ayer',
  'Lo gastado ayer en «Lo que leí»'
);

select is(
  tests.inv(jsonb_build_object('ver', 'gastado', 'desde', tests.d0() - 29, 'hasta', tests.d0() - 29)) -> 'sin_datos',
  'true'::jsonb,
  'Un día sin ventas no gastó nada'
);


-- ─── ver = llego ──────────────────────────────────────────────────────────────

select is(
  tests.inv(jsonb_build_object('ver', 'llego', 'desde', tests.d0() - 7, 'hasta', tests.d0())) -> 'renglones',
  jsonb_build_array(
    jsonb_build_object('ingrediente', 'Pastor', 'llego', '10 kg', 'veces', 1,
      'recientes', jsonb_build_array(jsonb_build_object(
        'cuando', 'el ' || tests.palabras(tests.d0() - 6) || ' a las 10:00', 'cantidad', '10 kg', 'anoto', 'Don Chuy'))),
    jsonb_build_object('ingrediente', 'Queso', 'llego', '4 kg', 'cajas', '2 cajas', 'veces', 1,
      'recientes', jsonb_build_array(jsonb_build_object(
        'cuando', 'hoy a las ' || tests.hora(), 'cantidad', '4 kg', 'cajas', '2 cajas', 'anoto', 'Chente · cocina')))),
  'llego: lo anotado en Llegó con sus cajas y quién; lo deshecho no sale'
);

select is(
  tests.inv(jsonb_build_object('ver', 'llego', 'desde', tests.d0(), 'hasta', tests.d0())) -> 'leido' ->> 'texto',
  'Lo que llegó hoy',
  'Lo que llegó hoy en «Lo que leí»'
);

select is(
  tests.inv(jsonb_build_object('ver', 'llego', 'desde', tests.d0(), 'hasta', tests.d0(), 'ingrediente', 'Pastor'))
    -> 'sin_datos',
  'true'::jsonb,
  'Hoy no llegó Pastor'
);

select is(
  tests.inv(jsonb_build_object('ver', 'llego', 'desde', tests.d0() - 7, 'hasta', tests.d0(),
                               'ingrediente', 'Queso', 'agrupar_por', 'dia')) -> 'renglones' -> 0 ->> 'dia',
  tests.palabras(tests.d0()),
  'Lo que llegó de un ingrediente, día por día'
);


-- ─── ver = alcanza ────────────────────────────────────────────────────────────

select is(
  tests.inv('{"ver": "alcanza"}') - 'leido',
  '{"platillos": [
      {"platillo": "Agua de limon", "alcanzan": 0, "se_acaba_primero": "Limon", "queda": "−0.5 kg", "lleva_cada_uno": "0.1 kg"},
      {"platillo": "Taco al pastor", "alcanzan": 15, "se_acaba_primero": "Tortilla", "queda": "30 piezas",
       "lleva_cada_uno": "2 piezas"},
      {"platillo": "Quesadilla", "alcanzan": 30, "se_acaba_primero": "Tortilla", "queda": "30 piezas",
       "lleva_cada_uno": "1 pieza"}],
    "resto": null, "sin_receta": 1, "ver": "alcanza", "sin_datos": false, "sin_ingredientes": false}'::jsonb,
  'alcanza: cuántos de cada platillo con lo que queda, el que menos primero, sin opciones (el Refresco sigue sin receta), envíos ni archivados'
);

select is(
  tests.inv('{"ver": "alcanza"}') -> 'leido' ->> 'texto',
  'Cuántos platillos alcanzan',
  'Todos los platillos en «Lo que leí»'
);

select is(
  tests.inv('{"ver": "alcanza", "producto": "taco al pastor"}') -> 'platillos',
  '[{"platillo": "Taco al pastor", "alcanzan": 15, "se_acaba_primero": "Tortilla", "queda": "30 piezas",
     "lleva_cada_uno": "2 piezas"}]'::jsonb,
  'Lo que alcanza de un platillo, por su nombre'
);

select is(
  tests.inv('{"ver": "alcanza", "producto": "Taco al pastor"}') -> 'leido' ->> 'texto',
  'Lo que alcanza de Taco al pastor',
  'Un platillo en «Lo que leí»'
);

select is(
  tests.inv('{"ver": "alcanza", "producto": "Refresco"}') -> 'platillos',
  '[{"platillo": "Refresco", "sin_receta": true}]'::jsonb,
  'Un platillo sin receta lo dice'
);

select is(
  tests.inv('{"ver": "alcanza", "limite": 1}') -> 'resto',
  '{"platillos": 2}'::jsonb,
  'alcanza también lleva su límite'
);


-- ─── Lo que alcanza cambia con lo que queda ───────────────────────────────────
-- Llegan 500 Tortillas: el taco ya no se acaba por la Tortilla sino por el Pastor (81), la Quesadilla por el Queso
-- (76.8, o sea 76), y la Tortilla deja de estar en qué comprar.

select is(
  public.anotar_llegada('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f0f0f0f0-0000-4000-8000-000000000005',
                        '[{"ingrediente_id": 802, "cantidad": 500}]'),
  1, 'Llegan 500 Tortillas'
);

select is(
  tests.inv('{"ver": "alcanza", "producto": "Taco al pastor"}') -> 'platillos' -> 0,
  '{"platillo": "Taco al pastor", "alcanzan": 81, "se_acaba_primero": "Pastor", "queda": "8.1 kg",
    "lleva_cada_uno": "0.1 kg"}'::jsonb,
  'Ahora el taco se acaba por el Pastor'
);

select is(
  tests.inv('{"ver": "alcanza", "producto": "Quesadilla"}') -> 'platillos' -> 0,
  '{"platillo": "Quesadilla", "alcanzan": 76, "se_acaba_primero": "Queso", "queda": "4.61 kg",
    "lleva_cada_uno": "0.06 kg"}'::jsonb,
  'Y la Quesadilla se acaba por el Queso: 76 enteras, no 77'
);

select is(
  (select jsonb_agg(x ->> 'ingrediente') from jsonb_array_elements(
     tests.inv('{"ver": "queda", "solo_lo_que_falta": true}') -> 'ingredientes') x),
  '["Limon", "Pastor"]'::jsonb,
  'Con 530 Tortillas ya no hay que comprar Tortillas'
);

select is(
  tests.inv('{"ver": "queda", "ingrediente": "Tortilla"}') -> 'ingredientes' -> 0 -> 'alcanza_dias',
  '25.8'::jsonb,
  'Y alcanzan para 25.8 días'
);

select is(
  (tests.inv(jsonb_build_object('ver', 'llego', 'desde', tests.d0(), 'hasta', tests.d0())) -> 'renglones' -> 1)
    - 'recientes',
  '{"ingrediente": "Tortilla", "llego": "500 piezas", "veces": 1}'::jsonb,
  'Lo que llegó sin cajas no dice cajas'
);


-- ─── Sin licencia ─────────────────────────────────────────────────────────────

select tests.clear_authentication();
reset role;
update public.restaurantes set licencia_activa = false where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select tests.entrar('chuy');
select throws_ok(
  $$ select tests.inv('{"ver": "queda"}') $$,
  '42501', 'Solo los gerentes de este restaurante le preguntan al agente',
  'Con la licencia pausada, el agente no lee el inventario'
);

select * from finish();
rollback;
