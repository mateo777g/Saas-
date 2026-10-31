-- Pruebas de la migración anuncios (parte 7b-1): la tabla de los anuncios, que nadie la escriba
-- directo y que el gerente la lea sin el costo, el modelo de imagen en precios_ia, el teléfono y el
-- horario de Cuadros como van en el anuncio, «Crear contenido», apartar el lugar (uno a la vez, los
-- 20 del mes), el trabajo en segundo plano que lo termina o lo falla, uno atorado a los 15 minutos,
-- el paso de texto en el sobre de los anuncios y, hasta la 7b-3, la parte del agente que paga los dos.
--
-- Escenario: Fragmentless, Juanito (distribuidor), La Fonda de Don Chuy con dos gerentes (Don Chuy y
-- Marcos) y Pepe de mesero, el Restaurante B con tope 0 y el C con la licencia vencida.
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

grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;

-- Los ayudantes de estas pruebas. Los estilos, los anuncios y uso_ia se leen como su dueño, porque
-- nadie con sesión los lee completos.

create function tests.e(p_clave text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.estilos where clave = p_clave;
$$;

create function tests.anuncio(p_id bigint)
returns public.anuncios
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.anuncios where id = p_id;
$$;

create function tests.uso(p_restaurante_id uuid)
returns public.uso_ia
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.uso_ia
  where restaurante_id = p_restaurante_id
    and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
$$;

create function tests.miembro(p_nombre text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.miembros where nombre = p_nombre;
$$;

-- El id de cada anuncio que apartan las pruebas, por su nombre.
create table tests.ids (nombre text primary key, id bigint not null);

create function tests.id(p_nombre text)
returns bigint
language sql
stable
as $$
  select id from tests.ids where nombre = p_nombre;
$$;

-- Aparta con la sesión de quien llama y guarda el id con su nombre.
create function tests.apartar(
  p_nombre text, p_restaurante uuid, p_estilo text, p_formato text, p_productos bigint[],
  p_mensaje text, p_color text, p_con_color boolean, p_palabras jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  v := public.apartar_anuncio(p_restaurante, tests.e(p_estilo), p_formato, p_productos, p_mensaje, p_color,
                              p_con_color, p_palabras);
  if p_nombre is not null and (v ->> 'ok')::boolean then
    insert into tests.ids values (p_nombre, (v ->> 'anuncio_id')::bigint);
  end if;
  return v;
end;
$$;

-- Hoy y el mes de IA en la hora de México, para todos los papeles.
create function tests.hoy()
returns date
language sql
stable
as $$
  select (now() at time zone 'America/Mexico_City')::date;
$$;

create function tests.vuelve()
returns date
language sql
stable
as $$
  select (date_trunc('month', tests.hoy()) + interval '1 month')::date;
$$;

-- La sesión del aparato ligado de Pepe, como en las pruebas de empleados.
create function tests.en_aparato(p_sesion uuid)
returns void as $$
begin
  perform set_config('request.jwt.claims',
    (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
      || jsonb_build_object('session_id', p_sesion))::text, true);
end
$$ language plpgsql;

-- El Worker con la llave secreta.
create function tests.como_worker()
returns void as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', null, true);
end
$$ language plpgsql;

grant select, insert on tests.ids to authenticated, service_role;
grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres. La Fonda de Don Chuy (hora de México, tope de 10 dólares, color de
-- marca #2B5BAA, abre de lunes a sábado) tiene dos gerentes, Don Chuy y Marcos, y a Pepe de mesero.
-- El Restaurante B (de Juanito) tiene tope 0 y nada en «Tu restaurante»; el C, la licencia vencida.
-- Banderitas, el Clásico y el fútbol salen hoy; Barda está prendido sin muestras y Cuadros tiene
-- sus muestras pero está apagado.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  c uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');
  perform tests.create_supabase_user('marcos', 'marcos@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('gerente_b', 'gerente.b@prueba.test');
  perform tests.create_supabase_user('gerente_c', 'gerente.c@prueba.test');

  insert into public.plataforma_admins (usuario_id) values (tests.get_supabase_uid('fragmentless'));
  insert into public.distribuidores (nombre, usuario_id) values ('Juanito', tests.get_supabase_uid('juanito'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, zona_horaria,
                                   telefono, direccion, menu_color, distribuidor_id, tope_ia_usd_mes) values
    (a, 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, 'America/Mexico_City',
     '5512345678', 'Av. Juárez 120, Centro', '#2B5BAA', null, 10),
    (b, 'Restaurante B', 'restaurante-b', true, hoy - 30, hoy + 30, 'America/Mexico_City',
     null, null, null, (select id from public.distribuidores where nombre = 'Juanito'), 0),
    (c, 'Restaurante C', 'restaurante-c', true, hoy - 60, hoy - 2, 'America/Mexico_City',
     '2221234567', null, null, null, 10);

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    (a, tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}'),
    (a, tests.get_supabase_uid('marcos'), 'Marcos', '{gerente}'),
    (a, tests.get_supabase_uid('pepe'), 'Pepe', '{mesero}'),
    (b, tests.get_supabase_uid('gerente_b'), 'Gerente B', '{gerente}'),
    (c, tests.get_supabase_uid('gerente_c'), 'Gerente C', '{gerente}');

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id)
  select restaurante_id, 'Celular de Pepe', id, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'
  from public.miembros where nombre = 'Pepe';

  insert into public.categorias (id, restaurante_id, nombre, icono, orden, archivado_at) overriding system value values
    (601, a, 'Tacos', 'taco', 1, null),
    (602, a, 'Bebidas', 'agua', 2, null),
    (603, a, 'De antes', 'comida', 3, null),
    (611, b, 'Tacos B', 'taco', 1, null),
    (621, c, 'Tacos C', 'taco', 1, null);

  insert into public.productos (id, restaurante_id, categoria_id, nombre, precio, descripcion, imagen_ruta, orden,
                                visible, es_envio, archivado_at) overriding system value values
    (501, a, 601, 'Taco al pastor', 25, 'Con piña y cilantro',
     'restaurantes/' || a || '/menu/' || repeat('1', 32) || '.webp', 1, true, false, null),
    (502, a, 601, 'Torta de pastor con queso', 85.50, null, null, 2, true, false, null),
    (503, a, 601, 'Gringa', 1250, 'De harina', null, 3, true, false, null),
    (504, a, 601, 'Tlayuda', 90, null, null, 4, true, false, now()),
    (505, a, 602, 'Horchata', 30, null, null, 1, false, false, null),
    (506, a, 602, 'Envío', 40, null, null, 2, true, true, null),
    (507, a, 603, 'Tlacoyo', 20, null, null, 1, true, false, null),
    (511, b, 611, 'Taco B', 25, null, null, 1, true, false, null),
    (521, c, 621, 'Taco C', 25, null, null, 1, true, false, null);

  update public.categorias set archivado_at = now() where id = 603;

  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select a, d, '09:00', '23:00' from generate_series(1, 6) d;

  update public.estilos
  set prendido = true,
      muestra_post_ruta = 'estilos/' || clave || '/' || repeat('a', 32) || '.webp',
      muestra_historia_ruta = 'estilos/' || clave || '/' || repeat('b', 32) || '.webp',
      muestra_cartel_ruta = 'estilos/' || clave || '/' || repeat('c', 32) || '.webp'
  where clave in ('banderitas', 'clasico', 'futbol');
  update public.estilos set prendido = true where clave = 'barda';
  update public.estilos
  set muestra_post_ruta = 'estilos/cuadros/' || repeat('a', 32) || '.webp',
      muestra_historia_ruta = 'estilos/cuadros/' || repeat('b', 32) || '.webp',
      muestra_cartel_ruta = 'estilos/cuadros/' || repeat('c', 32) || '.webp'
  where clave = 'cuadros';
end;
$$;

select plan(215);


-- ─── precios_ia: el modelo de imagen ──────────────────────────────────────────

select has_column('public', 'precios_ia', 'entrada_imagen_usd_millon', 'precios_ia lleva lo que cobra la imagen de entrada');

select results_eq(
  $$select entrada_usd_millon, entrada_cache_usd_millon, escritura_cache_usd_millon, salida_usd_millon,
           entrada_imagen_usd_millon
    from public.precios_ia where modelo = 'gpt-image-2.5-sunburst'$$,
  $$values (5.00::numeric(10,4), 1.25::numeric(10,4), 5.00::numeric(10,4), 30.00::numeric(10,4), 8.00::numeric(10,4))$$,
  'gpt-image-2.5-sunburst: texto 5, caché 1.25, escribir en caché como la entrada, salida 30 e imagen de entrada 8'
);

select is(
  (select count(*)::integer from public.precios_ia where entrada_imagen_usd_millon is not null),
  1,
  'Los modelos de texto no llevan precio de imagen'
);

select is(
  privado.costo_imagen('gpt-image-2.5-sunburst', 1000, 2000, 6000),
  0.2010::numeric,
  'Una imagen: 1,000 de texto a 5, 2,000 de imagen a 8 y 6,000 de salida a 30 por millón son $0.2010'
);

select is(
  privado.costo_imagen('gpt-image-2.5-sunburst', 1, 0, 1),
  0.0000::numeric,
  'Se redondea a 4 decimales, como costo_ia'
);

select is(
  privado.costo_imagen('gpt-5.6-luna', 1000, 0, 0),
  null,
  'Un modelo de texto no tiene costo de imagen'
);


-- ─── Nadie la escribe; el gerente lee todo menos el costo ─────────────────────

select ok(
  not (has_table_privilege('anon', 'public.anuncios', 'select, insert, update, delete')
       or has_any_column_privilege('anon', 'public.anuncios', 'select, insert, update')),
  'anon no lee ni escribe los anuncios'
);

select ok(
  not (has_table_privilege('service_role', 'public.anuncios', 'select, insert, update, delete')
       or has_any_column_privilege('service_role', 'public.anuncios', 'select, insert, update')),
  'El Worker no lee la tabla directo: solo con sus funciones'
);

select ok(
  not (has_table_privilege('authenticated', 'public.anuncios', 'select, insert, update, delete')
       or has_any_column_privilege('authenticated', 'public.anuncios', 'insert, update')),
  'Nadie con sesión la escribe directo'
);

select ok(
  (select bool_and(has_column_privilege('authenticated', 'public.anuncios', c, 'select'))
   from unnest(array['id', 'restaurante_id', 'estilo_id', 'formato', 'productos', 'mensaje', 'color', 'palabras',
                     'estado', 'motivo', 'ruta', 'hecho_por', 'terminado_at', 'vence', 'visto_at', 'created_at',
                     'updated_at']) c),
  'El gerente puede leer sus columnas, para realtime'
);

select ok(
  not has_column_privilege('authenticated', 'public.anuncios', 'costo_usd', 'select'),
  'El costo no lo lee nadie con sesión'
);

select ok(
  not (has_sequence_privilege('authenticated', 'public.anuncios_id_seq', 'usage, select, update')
       or has_sequence_privilege('service_role', 'public.anuncios_id_seq', 'usage, select, update')),
  'Nadie toca su secuencia'
);

select ok((select relrowsecurity from pg_class where oid = 'public.anuncios'::regclass), 'La tabla tiene RLS');

select is(
  array(
    select f from unnest(array[
      'privado.son_productos_de_anuncio(jsonb)', 'privado.costo_imagen(text,bigint,bigint,bigint)',
      'privado.anuncios_del_mes(uuid)', 'privado.soltar_atorados(uuid)',
      'privado.sumar_a_anuncios(uuid,integer,numeric)', 'privado.telefono_escrito(text)',
      'privado.dias_escritos(smallint[])', 'privado.horario_de_cuadros(uuid)',
      'privado.restaurante_del_anuncio(uuid)', 'privado.revisar_anuncio(uuid,bigint,bigint[])',
      'privado.saldo_ia(uuid,text)']) f
    where has_function_privilege('anon', f, 'execute')
       or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute')
  ),
  '{}'::text[],
  'Las piezas de privado no las llama nadie de fuera'
);

select is(
  array(
    select f from unnest(array[
      'public.crear_contenido(uuid)', 'public.anuncio_visto(bigint)',
      'public.datos_para_anuncio(uuid,bigint,bigint[])',
      'public.apartar_anuncio(uuid,bigint,text,bigint[],text,text,boolean,jsonb)']) f
    where not has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('service_role', f, 'execute')
  ),
  '{}'::text[],
  'Las de Don Chuy y las dos que el Worker pide con su sesión, solo con sesión'
);

select is(
  array(
    select f from unnest(array[
      'public.datos_del_anuncio(bigint)', 'public.terminar_anuncio(bigint,text,text,bigint,bigint,bigint)',
      'public.fallar_anuncio(bigint,text,text,bigint,bigint,bigint)']) f
    where not has_function_privilege('service_role', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('authenticated', f, 'execute')
  ),
  '{}'::text[],
  'Las del trabajo en segundo plano, solo con la llave secreta'
);

select ok(
  has_function_privilege('service_role', 'public.anotar_uso_ia(uuid,text,text,bigint,bigint,bigint,bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.anotar_uso_ia(uuid,text,text,bigint,bigint,bigint,bigint)', 'execute'),
  'anotar_uso_ia sigue siendo solo del Worker'
);


-- ─── El teléfono y el horario de Cuadros ──────────────────────────────────────

select is(privado.telefono_escrito('5512345678'), '551 234 5678', 'El teléfono como en el menú: 551 234 5678');
select is(privado.telefono_escrito(null), null, 'Sin teléfono, nada');

select is(privado.dias_escritos('{1,2,3,4,5,6}'), 'Lun a sáb', 'Tres o más seguidos, con «a»: Lun a sáb');
select is(privado.dias_escritos('{6,7}'), 'Sáb y dom', 'Dos seguidos, con «y»: Sáb y dom');
select is(privado.dias_escritos('{1,3,5}'), 'Lun, mié y vie', 'Sueltos con comas: Lun, mié y vie');
select is(privado.dias_escritos('{1,2,3,4,5,6,7}'), 'Todos los días', 'Los 7: Todos los días (encuesta 3)');
select is(privado.dias_escritos('{5,1,3,2}'), 'Lun a mié y vie', 'Un tramo y uno suelto: Lun a mié y vie');
select is(privado.dias_escritos('{1,2,4}'), 'Lun, mar y jue', 'Dos seguidos dentro de una lista van sueltos: Lun, mar y jue');
select is(privado.dias_escritos('{7}'), 'Dom', 'Un solo día: Dom');
select is(privado.dias_escritos('{2,3,4,5,6,7}'), 'Mar a dom', 'Los que cierran el lunes: Mar a dom');

select is(
  privado.horario_de_cuadros('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '["Lun a sáb 9:00 a 23:00"]'::jsonb,
  'La Fonda: Lun a sáb 9:00 a 23:00, como en la maqueta'
);
select is(privado.horario_de_cuadros('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), null, 'Sin horario, el recuadro no lo lleva');

insert into public.horarios (restaurante_id, dia, abre, cierra)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', d, case when d >= 6 then '08:00'::time else '10:00'::time end,
       case when d >= 6 then '14:00'::time else '20:00'::time end
from unnest(array[1, 3, 5, 6, 7]) d;
select is(
  privado.horario_de_cuadros('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  '["Lun, mié y vie 10:00 a 20:00", "Sáb y dom 8:00 a 14:00"]'::jsonb,
  'Dos horarios, dos renglones: primero el que empieza más cerca del lunes, aunque abra más tarde'
);

update public.horarios set abre = '12:00' where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and dia = 1;
select is(
  privado.horario_de_cuadros('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  null,
  'Con tres horarios distintos, no sale'
);

delete from public.horarios where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
insert into public.horarios (restaurante_id, dia, abre, cierra)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', d, '20:00', '02:00' from generate_series(1, 7) d;
select is(
  privado.horario_de_cuadros('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  '["Todos los días 20:00 a 2:00"]'::jsonb,
  'Pasada la medianoche, como en el menú: 20:00 a 2:00'
);
delete from public.horarios where restaurante_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';


-- ─── La forma de los productos ────────────────────────────────────────────────

select ok(privado.son_productos_de_anuncio('[{"id": 1, "nombre": "Taco"}, {"id": 2, "nombre": "Torta"}]'),
          'De 1 a 5 productos, cada uno con su id y su nombre');
select ok(not privado.son_productos_de_anuncio('[]'), 'Sin productos, no');
select ok(not privado.son_productos_de_anuncio(
            (select jsonb_agg(jsonb_build_object('id', g, 'nombre', 'P' || g)) from generate_series(1, 6) g)),
          'Seis productos, no');
select ok(not privado.son_productos_de_anuncio('[{"id": 1, "nombre": "Taco"}, {"id": 1, "nombre": "Otro"}]'),
          'El mismo producto dos veces, no');
select ok(not privado.son_productos_de_anuncio('[{"id": "1", "nombre": "Taco"}]'), 'El id va como número');
select ok(not privado.son_productos_de_anuncio('[{"id": 1.5, "nombre": "Taco"}]'), 'El id va entero');
select ok(not privado.son_productos_de_anuncio('[{"id": 1, "nombre": " "}]'), 'El nombre no va vacío');
select ok(not privado.son_productos_de_anuncio('{"id": 1, "nombre": "Taco"}'), 'Van en una lista');


-- ─── Crear contenido: lo que lee Don Chuy ─────────────────────────────────────

select tests.authenticate_as('don_chuy');

select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'productos' - 'restaurante',
  jsonb_build_object('de', 20, 'quedan', 20, 'vuelve', tests.vuelve(), 'ia', jsonb_build_object('puede', true),
                     'resultado', null),
  'Al entrar: Te quedan 20 de 20, vuelven el 1 del mes que viene, la IA puede y «Resultado» vacío'
);

select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'restaurante',
  '{"nombre": "La Fonda de Don Chuy", "telefono": "551 234 5678", "direccion": "Av. Juárez 120, Centro",
    "color": "#2B5BAA", "horario": ["Lun a sáb 9:00 a 23:00"]}'::jsonb,
  'Su restaurante como va en el anuncio: nombre, teléfono escrito, dirección, color de marca y horario de Cuadros'
);

select is(
  array(select (p ->> 'id')::integer
        from jsonb_array_elements(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'productos') p),
  array[501, 502, 503, 505],
  'Sus productos en el orden de Mi menú, con los ocultos; sin archivados, sin los de una categoría archivada ni los costos de envío'
);

select is(
  array(select p ->> 'precio_escrito'
        from jsonb_array_elements(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'productos') p),
  array['$25', '$85.50', '$1,250', '$30'],
  'El precio como va en el anuncio, con la regla de Flet: $25, $85.50, $1,250'
);

select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'productos' -> 0,
  jsonb_build_object('id', 501, 'nombre', 'Taco al pastor', 'descripcion', 'Con piña y cilantro',
                     'imagen_ruta', 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('1', 32) || '.webp',
                     'precio', 25.00, 'precio_escrito', '$25'),
  'Cada producto con su nombre, descripción, foto, precio y precio escrito'
);

select tests.authenticate_as('gerente_b');
select is(
  public.crear_contenido('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'ia',
  jsonb_build_object('puede', false, 'motivo', 'sin_ia', 'con_distribuidor', true, 'vuelve', tests.vuelve()),
  'Con tope 0, el aviso del agente: sin IA, con su distribuidor'
);
select is(
  public.crear_contenido('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'restaurante',
  '{"nombre": "Restaurante B", "telefono": null, "direccion": null, "color": null, "horario": null}'::jsonb,
  'Lo que falta en «Tu restaurante» va vacío'
);
select throws_ok(
  $$ select public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios',
  'El gerente de otro restaurante no entra al de Don Chuy'
);

select tests.authenticate_as('gerente_c');
select throws_ok(
  $$ select public.crear_contenido('cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios',
  'Con la licencia vencida no se crea'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios',
  'Pepe, el mesero, no crea anuncios ni desde su aparato'
);

select tests.clear_authentication();
select throws_ok(
  $$ select public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', null,
  'Sin sesión, nada'
);


-- ─── Antes del paso de texto: datos_para_anuncio ──────────────────────────────

select tests.authenticate_as('don_chuy');

select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[502, 501]::bigint[]) - 'productos',
  jsonb_build_object('ok', true, 'estilo', 'banderitas',
                     'restaurante', public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'restaurante'),
  'El Worker recibe la clave del estilo y el restaurante como va en el anuncio'
);

select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[502, 501]::bigint[]) -> 'productos',
  jsonb_build_array(
    jsonb_build_object('id', 502, 'nombre', 'Torta de pastor con queso', 'descripcion', null, 'imagen_ruta', null,
                       'precio', 85.50, 'precio_escrito', '$85.50'),
    public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'productos' -> 0),
  'Y los productos en el orden en que los picó: el 1 es el del titular'
);

select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), '{}'::bigint[]) $$,
  '22023', 'Un anuncio lleva de 1 a 5 productos', 'Sin productos, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[501, 502, 503, 505, 506, 507]::bigint[]) $$,
  '22023', 'Un anuncio lleva de 1 a 5 productos', 'Seis, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[501, null]::bigint[]) $$,
  '22023', 'Un anuncio lleva de 1 a 5 productos', 'Un producto vacío, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[501, 501]::bigint[]) $$,
  '22023', 'Cada producto va una sola vez en el anuncio', 'El mismo dos veces, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[501, 511]::bigint[]) $$,
  '22023', 'Uno de tus productos ya no está en tu menú.', 'Un producto de otro restaurante, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[504]::bigint[]) $$,
  '22023', 'Uno de tus productos ya no está en tu menú.', 'Uno archivado, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[507]::bigint[]) $$,
  '22023', 'Uno de tus productos ya no está en tu menú.', 'Uno de una categoría archivada, no'
);
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[506]::bigint[]) $$,
  '22023', 'Uno de tus productos ya no está en tu menú.', 'Un costo de envío, no'
);
select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[505]::bigint[]) ->> 'ok',
  'true',
  'Uno oculto en el menú, sí'
);

select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('barda'), array[501]::bigint[]),
  '{"ok": false, "motivo": "estilo"}'::jsonb,
  'Un estilo prendido sin sus 3 muestras no le sale: «Este estilo ya no está»'
);
select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('cuadros'), array[501]::bigint[]),
  '{"ok": false, "motivo": "estilo"}'::jsonb,
  'Uno apagado tampoco'
);
select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 999999, array[501]::bigint[]),
  '{"ok": false, "motivo": "estilo"}'::jsonb,
  'Ni uno que ya no existe'
);

select tests.authenticate_as('gerente_b');
select is(
  public.datos_para_anuncio('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.e('clasico'), array[511]::bigint[]),
  jsonb_build_object('ok', false, 'motivo', 'sin_ia', 'con_distribuidor', true, 'vuelve', tests.vuelve()),
  'Con tope 0 el paso de texto no se hace: gasta'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('banderitas'), array[501]::bigint[]) $$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Pepe no pide palabras'
);


-- ─── Apartar el lugar ─────────────────────────────────────────────────────────

select tests.authenticate_as('don_chuy');

select is(
  tests.apartar('primero', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'banderitas', 'post', array[502, 501, 503],
                '  HAY PARA TODOS  ', null, true, '{"banderitas": ["TORTA", "TACO", "GRINGA"]}') - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Generar anuncio: Don Chuy aparta su lugar'
);
select isnt(tests.id('primero'), null, 'Y el Worker recibe el id del anuncio');

select is((tests.anuncio(tests.id('primero'))).estado, 'haciendo', 'Nace «haciendo»');
select is(
  (tests.anuncio(tests.id('primero'))).productos,
  '[{"id": 502, "nombre": "Torta de pastor con queso"}, {"id": 501, "nombre": "Taco al pastor"}, {"id": 503, "nombre": "Gringa"}]'::jsonb,
  'Guarda los productos como iban, con su nombre, en el orden en que los picó'
);
select is((tests.anuncio(tests.id('primero'))).mensaje, 'HAY PARA TODOS', 'Su mensaje, sin los espacios de las orillas');
select is((tests.anuncio(tests.id('primero'))).color, '#2B5BAA', 'Sin color elegido, el de su marca');
select is(
  (tests.anuncio(tests.id('primero'))).palabras,
  '{"banderitas": ["TORTA", "TACO", "GRINGA"]}'::jsonb,
  'Las palabras del paso de texto, como fueron'
);
select is((tests.anuncio(tests.id('primero'))).hecho_por, tests.miembro('Don Chuy'), 'Lo hizo Don Chuy');
select ok(
  (tests.anuncio(tests.id('primero'))).costo_usd = 0
  and (tests.anuncio(tests.id('primero'))).terminado_at is null
  and (tests.anuncio(tests.id('primero'))).vence is null
  and (tests.anuncio(tests.id('primero'))).ruta is null,
  'Todavía sin costo, sin terminar, sin archivo y sin día de vencer'
);

select is(
  tests.apartar('repetido', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null),
  '{"ok": false, "motivo": "haciendo"}'::jsonb,
  'Uno a la vez: una segunda pestaña no aparta otro'
);

select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), array[501]::bigint[]) ->> 'ok',
  'true',
  'Mientras se hace, puede preparar el siguiente: el paso de texto no revisa si hay otro haciéndose'
);

select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan',
  '19',
  'El que se está haciendo ya cuenta: Te quedan 19 de 20'
);

select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado',
  jsonb_build_object('id', tests.id('primero'), 'estado', 'haciendo', 'motivo', null, 'estilo_id', tests.e('banderitas'),
                     'formato', 'post', 'productos', (tests.anuncio(tests.id('primero'))).productos,
                     'mensaje', 'HAY PARA TODOS', 'color', '#2B5BAA',
                     'palabras', '{"banderitas": ["TORTA", "TACO", "GRINGA"]}'::jsonb, 'ruta', null, 'segundos', 0),
  '«Resultado» lo enseña haciéndose, con lo que pide «Otra vez» y los segundos que lleva'
);

select throws_ok(
  format('select public.anuncio_visto(%s)', tests.id('primero')),
  '22023', 'Ese anuncio todavía se está haciendo',
  'Uno que se está haciendo no se marca visto'
);

-- Los datos mal armados, aunque haya uno haciéndose: se revisan antes.
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'reel', array[501], null, null, true, null) $$,
  '22023', 'El formato es post, historia o cartel', 'Tres formatos: post, historia y cartel'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], repeat('a', 201), null, true, null) $$,
  '22023', 'El mensaje puede tener hasta 200 letras', 'El mensaje, hasta 200'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, null, null) $$,
  '22023', 'Falta decir si el estilo lleva color', 'El Worker dice si el estilo lleva color'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'futbol', 'post', array[501], null, '#FF0000', false, null) $$,
  '22023', 'Este estilo no lleva color', 'Un festivo no lleva color'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, 'azul', true, null) $$,
  '22023', 'El color va como #RRGGBB', 'El color va como #RRGGBB'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, '["TACO"]') $$,
  '22023', 'Las palabras van en un objeto', 'Las palabras van en un objeto'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[504], null, null, true, null) $$,
  '22023', 'Uno de tus productos ya no está en tu menú.', 'Apartar revisa sus productos como el paso de texto'
);
select is(
  tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'barda', 'post', array[501], null, null, true, null),
  '{"ok": false, "motivo": "estilo"}'::jsonb,
  'Si le apagan el estilo con la ventana abierta: «Este estilo ya no está. Elige otro.»'
);

-- Don Chuy lee los renglones de su restaurante directo, solo para realtime, sin el costo.
select is(
  (select count(*)::integer from public.anuncios),
  1,
  'Don Chuy ve el renglón de su anuncio, para que realtime le avise'
);
select throws_ok(
  $$ select costo_usd from public.anuncios $$,
  '42501', null,
  'Pero no su costo'
);

select tests.authenticate_as('marcos');
select is(
  tests.apartar('de_marcos', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null),
  '{"ok": false, "motivo": "haciendo"}'::jsonb,
  'Uno a la vez por sucursal: Marcos tampoco aparta mientras se hace el de Don Chuy'
);
select is(
  (public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado' ->> 'id')::bigint,
  tests.id('primero'),
  'Mientras se hace, Marcos también lo ve en «Resultado» (encuesta 1)'
);

select tests.authenticate_as('gerente_b');
select is(
  public.crear_contenido('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') -> 'resultado',
  'null'::jsonb,
  'Otro restaurante no ve los anuncios de La Fonda'
);
select is((select count(*)::integer from public.anuncios), 0, 'Ni sus renglones');
select is(
  tests.apartar(null, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'clasico', 'post', array[511], null, null, true, null),
  jsonb_build_object('ok', false, 'motivo', 'sin_ia', 'con_distribuidor', true, 'vuelve', tests.vuelve()),
  'Con tope 0 no aparta'
);
select throws_ok(
  $$ select tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null) $$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios',
  'No aparta en el restaurante de otro'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.anuncios), 0, 'Pepe no ve los anuncios');


-- ─── El trabajo en segundo plano ──────────────────────────────────────────────

-- Mientras se hace, Don Chuy le cambia el nombre a un producto y borra otro de Mi menú.
reset role;
update public.productos set nombre = 'Taco al pastor grande', precio = 27 where id = 501;
delete from public.productos where id = 503;

select tests.como_worker();

select is(
  public.datos_del_anuncio(tests.id('primero')) - 'productos' - 'restaurante',
  jsonb_build_object('id', tests.id('primero'), 'restaurante_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                     'estado', 'haciendo', 'estilo', 'banderitas', 'formato', 'post', 'mensaje', 'HAY PARA TODOS',
                     'color', '#2B5BAA', 'palabras', '{"banderitas": ["TORTA", "TACO", "GRINGA"]}'::jsonb),
  'El trabajo lee lo apartado con la llave secreta'
);
select is(
  public.datos_del_anuncio(tests.id('primero')) -> 'productos',
  jsonb_build_array(
    jsonb_build_object('id', 502, 'nombre', 'Torta de pastor con queso', 'descripcion', null, 'imagen_ruta', null,
                       'precio', 85.50, 'precio_escrito', '$85.50'),
    jsonb_build_object('id', 501, 'nombre', 'Taco al pastor', 'descripcion', 'Con piña y cilantro',
                       'imagen_ruta', 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('1', 32) || '.webp',
                       'precio', 27.00, 'precio_escrito', '$27'),
    jsonb_build_object('id', 503, 'nombre', 'Gringa')),
  'Sus productos con el nombre guardado y la descripción, la foto y el precio de hoy; el que ya no existe, solo con su nombre'
);
select is(
  public.datos_del_anuncio(tests.id('primero')) -> 'restaurante' ->> 'telefono',
  '551 234 5678',
  'Y su restaurante como va en el anuncio'
);
select throws_ok(
  $$ select public.datos_del_anuncio(999999) $$,
  'P0002', 'No existe el anuncio 999999', 'Un anuncio que no existe'
);

select throws_ok(
  format($$ select public.terminar_anuncio(%s, 'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/biblioteca/%s.jpg',
                                            'gpt-image-2.5-sunburst', 1000, 2000, 6000) $$, tests.id('primero'), repeat('a', 32)),
  '22023', 'La ruta del anuncio va en la biblioteca de su restaurante',
  'El archivo va en la biblioteca de su restaurante'
);
select throws_ok(
  format($$ select public.terminar_anuncio(%s, 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/%s.webp',
                                            'gpt-image-2.5-sunburst', 1000, 2000, 6000) $$, tests.id('primero'), repeat('a', 32)),
  '22023', 'La ruta del anuncio va en la biblioteca de su restaurante',
  'Y es JPG, nunca WebP'
);
select throws_ok(
  format($$ select public.terminar_anuncio(%s, 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/%s.jpg',
                                            'gpt-image-2.5-sunburst', 1000, -1, 6000) $$, tests.id('primero'), repeat('a', 32)),
  '22023', 'Los tokens van completos y en 0 o más',
  'Los tokens van completos'
);
select throws_ok(
  format($$ select public.terminar_anuncio(%s, 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/%s.jpg',
                                            'gpt-5.6-luna', 1000, 2000, 6000) $$, tests.id('primero'), repeat('a', 32)),
  'P0002', 'No hay precio de imagen para el modelo gpt-5.6-luna',
  'Con un modelo sin precio de imagen no se termina'
);
select throws_ok(
  format($$ select public.fallar_anuncio(%s, 'cansado', 'gpt-image-2.5-sunburst', 0, 0, 0) $$, tests.id('primero')),
  '22023', 'El motivo es rechazado o no_salio',
  'Dos motivos: rechazado o no_salio'
);

select is(
  public.terminar_anuncio(tests.id('primero'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('a', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 1000, 2000, 6000),
  '{"ok": true, "costo": 0.2010}'::jsonb,
  'El JPG ya está en R2: queda listo y regresa lo que costó'
);
select is((tests.anuncio(tests.id('primero'))).estado, 'listo', 'Queda «listo»');
select is(
  (tests.anuncio(tests.id('primero'))).ruta,
  'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('a', 32) || '.jpg',
  'Con su archivo en la biblioteca'
);
select is((tests.anuncio(tests.id('primero'))).vence, tests.hoy() + 29, 'Se ve 30 días contando el primero: hoy más 29');
select is((tests.anuncio(tests.id('primero'))).terminado_at, now(), 'Con cuándo terminó');
select is((tests.anuncio(tests.id('primero'))).costo_usd, 0.2010::numeric(10,4), 'Y lo que costó su imagen');
select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_agente_usd],
  array[1, 0.2010, 0]::numeric[],
  'Cuenta uno en los 20 del mes y su costo va al sobre de los anuncios, no al del agente'
);

select is(
  public.terminar_anuncio(tests.id('primero'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('a', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 1000, 2000, 6000),
  '{"ok": true, "costo": 0.2010}'::jsonb,
  'Si el Worker repite el paso, sigue listo'
);
select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd],
  array[1, 0.2010]::numeric[],
  'Y no cuenta dos veces'
);
select is(
  public.terminar_anuncio(tests.id('primero'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('b', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 1000, 2000, 6000) ->> 'ok',
  'false',
  'Otro archivo para uno ya listo no entra: el Worker lo borra'
);
select is(
  (tests.anuncio(tests.id('primero'))).ruta,
  'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('a', 32) || '.jpg',
  'Y el anuncio se queda con el suyo'
);
select throws_ok(
  format($$ select public.fallar_anuncio(%s, 'no_salio', 'gpt-image-2.5-sunburst', 0, 0, 0) $$, tests.id('primero')),
  '55000', null,
  'Uno que ya salió no se falla'
);


-- ─── «Resultado» al volver y visto ────────────────────────────────────────────

select tests.authenticate_as('don_chuy');
select is(
  (public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado') - 'segundos',
  jsonb_build_object('id', tests.id('primero'), 'estado', 'listo', 'motivo', null, 'estilo_id', tests.e('banderitas'),
                     'formato', 'post', 'productos', (tests.anuncio(tests.id('primero'))).productos,
                     'mensaje', 'HAY PARA TODOS', 'color', '#2B5BAA',
                     'palabras', '{"banderitas": ["TORTA", "TACO", "GRINGA"]}'::jsonb,
                     'ruta', 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('a', 32) || '.jpg'),
  'Al volver, «Resultado» le enseña su anuncio listo mientras no lo vea'
);
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan',
  '19',
  'Ya salió: sigue contando uno, Te quedan 19'
);

select tests.authenticate_as('marcos');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado',
  'null'::jsonb,
  'Ya terminado, solo se le enseña a quien lo hizo (encuesta 1)'
);
select throws_ok(
  format('select public.anuncio_visto(%s)', tests.id('primero')),
  '42501', 'Solo quien hizo el anuncio lo marca visto',
  'Marcos no lo marca visto'
);

select tests.authenticate_as('gerente_b');
select throws_ok(
  format('select public.anuncio_visto(%s)', tests.id('primero')),
  'P0002', 'Ese anuncio ya no existe',
  'Otro restaurante, tampoco'
);
select throws_ok(
  $$ select public.anuncio_visto(999999) $$,
  'P0002', 'Ese anuncio ya no existe',
  'Uno que no existe'
);

select tests.authenticate_as('don_chuy');
select lives_ok(format('select public.anuncio_visto(%s)', tests.id('primero')), 'Don Chuy lo ve');
select is((tests.anuncio(tests.id('primero'))).visto_at, now(), 'Queda con cuándo lo vio');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado',
  'null'::jsonb,
  'Ya visto, «Resultado» queda vacío y el anuncio vive en Mi biblioteca'
);

reset role;
update public.anuncios set visto_at = now() - interval '1 hour' where id = (select id from tests.ids where nombre = 'primero');
select tests.authenticate_as('don_chuy');
select lives_ok(format('select public.anuncio_visto(%s)', tests.id('primero')), 'Marcarlo otra vez no falla');
select is((tests.anuncio(tests.id('primero'))).visto_at, now() - interval '1 hour', 'Y no cambia cuándo lo vio');


-- ─── Cuando no sale ───────────────────────────────────────────────────────────

select is(
  tests.apartar('segundo', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'historia', array[501], '   ', '#ffcc00',
                true, '{}') - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Otro anuncio, con un color elegido'
);
select is((tests.anuncio(tests.id('segundo'))).color, '#FFCC00', 'El color que eligió, como #RRGGBB');
select is((tests.anuncio(tests.id('segundo'))).mensaje, null, 'Un mensaje de puros espacios va vacío');
select is((tests.anuncio(tests.id('segundo'))).palabras, null, 'Sin palabras, vacío');

select tests.como_worker();
select is(
  public.fallar_anuncio(tests.id('segundo'), 'rechazado', 'gpt-image-2.5-sunburst', 0, 0, 0),
  '{"costo": 0.0000}'::jsonb,
  'OpenAI no lo aceptó'
);
select ok(
  (tests.anuncio(tests.id('segundo'))).estado = 'fallo'
  and (tests.anuncio(tests.id('segundo'))).motivo = 'rechazado'
  and (tests.anuncio(tests.id('segundo'))).terminado_at = now()
  and (tests.anuncio(tests.id('segundo'))).vence = tests.hoy() + 29
  and (tests.anuncio(tests.id('segundo'))).ruta is null,
  'Queda «fallo», rechazado, con cuándo terminó y su día de vencer, sin archivo'
);
select is(
  public.fallar_anuncio(tests.id('segundo'), 'rechazado', 'gpt-image-2.5-sunburst', 100, 0, 0),
  '{"costo": 0.0005}'::jsonb,
  'Si OpenAI sí lo cobró, lleva su costo'
);
select is(
  public.fallar_anuncio(tests.id('segundo'), 'no_salio', 'gpt-image-2.5-sunburst', 100, 0, 0),
  '{"costo": 0.0005}'::jsonb,
  'Repetido, no se cobra dos veces'
);
select is((tests.anuncio(tests.id('segundo'))).motivo, 'rechazado', 'Y se queda con su motivo');
select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd],
  array[1, 0.2015]::numeric[],
  'Uno que no salió no cuenta en los 20, pero lo que cobró OpenAI sí va al sobre'
);

select tests.authenticate_as('don_chuy');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan',
  '19',
  'No contó: Te quedan 19'
);
select is(
  (public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado') - 'segundos' - 'productos' - 'estilo_id',
  jsonb_build_object('id', tests.id('segundo'), 'estado', 'fallo', 'motivo', 'rechazado', 'formato', 'historia',
                     'mensaje', null, 'color', '#FFCC00', 'palabras', null, 'ruta', null),
  'Al volver, «Resultado» le dice una vez que no salió, con su motivo'
);
select lives_ok(format('select public.anuncio_visto(%s)', tests.id('segundo')), 'El aviso también se marca visto');
select is(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado', 'null'::jsonb, 'Y ya no sale');


-- ─── Uno atorado: 15 minutos ──────────────────────────────────────────────────

select is(
  tests.apartar('tercero', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'futbol', 'cartel', array[501, 502], 'GOL', null,
                false, '{"titular": ["TACOS"]}') - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Un festivo'
);
select is((tests.anuncio(tests.id('tercero'))).color, null, 'Un festivo no lleva color, ni el de su marca');

reset role;
update public.anuncios set created_at = now() - interval '90 seconds' where id = (select id from tests.ids where nombre = 'tercero');
select tests.authenticate_as('don_chuy');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado' -> 'segundos',
  '90'::jsonb,
  'El contador sale de Postgres: lleva 90 segundos'
);

reset role;
update public.anuncios set created_at = now() - interval '14 minutes 59 seconds' where id = (select id from tests.ids where nombre = 'tercero');
select tests.authenticate_as('don_chuy');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado' ->> 'estado',
  'haciendo',
  'A los 14:59 todavía se está haciendo'
);

reset role;
update public.anuncios set created_at = now() - interval '15 minutes' where id = (select id from tests.ids where nombre = 'tercero');
select tests.authenticate_as('don_chuy');
select is(
  (public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado') - 'segundos' - 'productos' - 'estilo_id'
    - 'mensaje' - 'color' - 'palabras' - 'formato',
  jsonb_build_object('id', tests.id('tercero'), 'estado', 'fallo', 'motivo', 'no_salio', 'ruta', null),
  'A los 15 minutos cuenta como que no salió: al volver a leer, «No se pudo hacer tu anuncio»'
);
select ok(
  (tests.anuncio(tests.id('tercero'))).terminado_at = now()
  and (tests.anuncio(tests.id('tercero'))).vence = tests.hoy() + 29,
  'Con cuándo se soltó y su día de vencer, como cualquier otro'
);
select is(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan', '19', 'Y suelta su lugar: Te quedan 19');

select tests.como_worker();
select is(
  public.datos_del_anuncio(tests.id('tercero')) ->> 'estado',
  'fallo',
  'Si el trabajo lo lee tarde, ve que ya no está haciéndose y no llama a OpenAI'
);
select is(
  public.terminar_anuncio(tests.id('tercero'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('c', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 1000, 2000, 6000),
  '{"ok": false, "costo": 0.2010}'::jsonb,
  'Si su imagen llega tarde, no se guarda: el Worker borra el archivo'
);
select ok(
  (tests.anuncio(tests.id('tercero'))).estado = 'fallo'
  and (tests.anuncio(tests.id('tercero'))).ruta is null
  and (tests.anuncio(tests.id('tercero'))).costo_usd = 0.2010,
  'Sigue sin salir, pero con lo que costó'
);
select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd],
  array[1, 0.4025]::numeric[],
  'No cuenta en los 20; su costo sí va al sobre'
);
select is(
  public.terminar_anuncio(tests.id('tercero'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('c', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 1000, 2000, 6000),
  '{"ok": false, "costo": 0.2010}'::jsonb,
  'Repetido, igual'
);
select is((tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd, 0.4025::numeric(10,4), 'Sin cobrar dos veces');

select tests.authenticate_as('don_chuy');
select lives_ok(format('select public.anuncio_visto(%s)', tests.id('tercero')), 'Don Chuy ve el aviso');

select is(
  tests.apartar('cuarto', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null) - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Otro más'
);
reset role;
update public.anuncios set created_at = now() - interval '20 minutes' where id = (select id from tests.ids where nombre = 'cuarto');
select tests.authenticate_as('don_chuy');
select is(
  tests.apartar('quinto', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[502], null, null, true, null) - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Uno atorado no le estorba: al apartar, se suelta y aparta el nuevo'
);
select ok(
  (tests.anuncio(tests.id('cuarto'))).estado = 'fallo' and (tests.anuncio(tests.id('cuarto'))).motivo = 'no_salio',
  'El atorado quedó como que no salió'
);

select tests.como_worker();
select is(
  public.fallar_anuncio(tests.id('cuarto'), 'rechazado', 'gpt-image-2.5-sunburst', 200, 0, 0),
  '{"costo": 0.0010}'::jsonb,
  'Si su trabajo falla tarde, solo suma lo que cobró OpenAI'
);
select is((tests.anuncio(tests.id('cuarto'))).motivo, 'no_salio', 'Y se queda con el motivo que ya tenía');
select is(
  public.terminar_anuncio(tests.id('quinto'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('d', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 1000, 2000, 6000) ->> 'ok',
  'true',
  'El nuevo sale bien'
);
select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd],
  array[2, 0.6045]::numeric[],
  'Van dos en los 20'
);
select tests.authenticate_as('don_chuy');
select is(
  (public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'resultado' ->> 'id')::bigint,
  tests.id('quinto'),
  'Con dos sin ver (el atorado y el nuevo), «Resultado» enseña el último'
);


-- Tres atorados que nadie miró antes de que llegara su trabajo: cada función del trabajo lo suelta.
select tests.authenticate_as('don_chuy');
select is(tests.apartar('atorado_1', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null) ->> 'ok',
          'true', 'Uno que se va a atorar');
reset role;
update public.anuncios set created_at = now() - interval '16 minutes' where id = (select id from tests.ids where nombre = 'atorado_1');
select tests.como_worker();
select is(public.datos_del_anuncio(tests.id('atorado_1')) ->> 'estado', 'fallo',
          'datos_del_anuncio lo suelta él mismo: el trabajo no llama a OpenAI');

select tests.authenticate_as('don_chuy');
select is(tests.apartar('atorado_2', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null) ->> 'ok',
          'true', 'Otro');
reset role;
update public.anuncios set created_at = now() - interval '16 minutes' where id = (select id from tests.ids where nombre = 'atorado_2');
select tests.como_worker();
select is(
  public.terminar_anuncio(tests.id('atorado_2'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('7', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 0, 0, 0) ->> 'ok',
  'false',
  'terminar_anuncio también lo suelta: llegó tarde y no se guarda'
);
select is((tests.anuncio(tests.id('atorado_2'))).motivo, 'no_salio', 'Cuenta como que no salió');

select tests.authenticate_as('don_chuy');
select is(tests.apartar('atorado_3', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null) ->> 'ok',
          'true', 'Y otro');
reset role;
update public.anuncios set created_at = now() - interval '16 minutes' where id = (select id from tests.ids where nombre = 'atorado_3');
select tests.como_worker();
select lives_ok(
  format($$ select public.fallar_anuncio(%s, 'rechazado', 'gpt-image-2.5-sunburst', 0, 0, 0) $$, tests.id('atorado_3')),
  'fallar_anuncio también'
);
select is((tests.anuncio(tests.id('atorado_3'))).motivo, 'no_salio',
          'Pasados los 15 minutos ya era «no salió», aunque OpenAI lo rechazara después');


-- ─── Los 20 del mes ───────────────────────────────────────────────────────────

reset role;
update public.uso_ia set anuncios = 19
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;

select tests.authenticate_as('don_chuy');
select is(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan', '1', 'Con 19 hechos, le queda 1');
select is(
  tests.apartar('sexto', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null) - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Hace el último'
);
select is(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan', '0', 'Mientras se hace, Te quedan 0');
select is(
  tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null),
  '{"ok": false, "motivo": "haciendo"}'::jsonb,
  'Mientras se hace, el que se está haciendo'
);

select tests.como_worker();
select is(
  public.terminar_anuncio(tests.id('sexto'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('e', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 0, 0, 0) ->> 'ok',
  'true',
  'Sale el vigésimo'
);

select tests.authenticate_as('don_chuy');
select is(
  tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null),
  jsonb_build_object('ok', false, 'motivo', 'veinte', 'vuelve', tests.vuelve()),
  'Con los 20 hechos: «Ya hiciste tus 20 anuncios de este mes. Vuelven el 1 de noviembre.»'
);
select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), array[501]::bigint[]) ->> 'ok',
  'true',
  'El paso de texto no revisa los 20, como en la maqueta'
);

reset role;
update public.uso_ia set anuncios = 25
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
select tests.authenticate_as('don_chuy');
select is(public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'quedan', '0', '«Te quedan» nunca baja de 0');

reset role;
insert into public.uso_ia (restaurante_id, mes, anuncios)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        (date_trunc('month', (now() at time zone 'America/Mexico_City')::date) - interval '1 month')::date, 20);
select tests.authenticate_as('gerente_b');
select is(
  public.crear_contenido('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') ->> 'quedan',
  '20',
  'Los del mes pasado no cuentan: el mes es el del calendario'
);


-- ─── El sobre: hasta la 7b-3, la parte del agente ─────────────────────────────

reset role;
update public.uso_ia set anuncios = 2, costo_agente_usd = 0, costo_anuncios_usd = 0
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;

select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'palabras', 'gpt-5.6-luna', 1000, 0, 0, 500),
  '{"costo": 0.0008, "puede": true}'::jsonb,
  'El paso de texto se anota como palabras: 1,000 de entrada a 0.20 y 500 de salida a 1.20 son $0.0008'
);
select is(
  array[(tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).anuncios::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_anuncios_usd,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).costo_agente_usd,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).consultas_agente::numeric,
        (tests.uso('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).saludos::numeric],
  array[2, 0.0008, 0, 0, 0]::numeric[],
  'Va al sobre de los anuncios y no cuenta en los 20 ni como pregunta'
);
select is(
  (public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'pregunta', 'gpt-5.6-luna', 0, 0, 0, 0) ->> 'puede'),
  'true',
  'Las preguntas del agente se siguen anotando igual'
);

reset role;
update public.uso_ia set costo_agente_usd = 4, costo_anuncios_usd = 3.99
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
select tests.authenticate_as('don_chuy');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'ia',
  '{"puede": true}'::jsonb,
  'Con 10 dólares, la parte del agente es 8: con 7.99 gastados entre el agente y los anuncios, todavía puede'
);

reset role;
update public.uso_ia set costo_anuncios_usd = 4
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
select tests.authenticate_as('don_chuy');
select is(
  public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') -> 'ia',
  jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', false, 'vuelve', tests.vuelve()),
  'Con 8 gastados entre los dos, «Crear contenido» dice que llegó al límite'
);
select is(
  public.estado_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  jsonb_build_object('puede', false, 'motivo', 'limite', 'con_distribuidor', false, 'vuelve', tests.vuelve()),
  'Y el agente también se pausa: los anuncios gastaron de su parte'
);
select is(
  tests.apartar(null, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'clasico', 'post', array[501], null, null, true, null),
  jsonb_build_object('ok', false, 'motivo', 'limite', 'con_distribuidor', false, 'vuelve', tests.vuelve()),
  'No aparta'
);
select is(
  public.datos_para_anuncio('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), array[501]::bigint[]) ->> 'motivo',
  'limite',
  'Ni hace el paso de texto'
);

select tests.como_worker();
select is(
  public.anotar_uso_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'palabras', 'gpt-5.6-luna', 0, 0, 0, 0) ->> 'puede',
  'false',
  'anotar_uso_ia dice que el sobre de los anuncios ya no puede'
);
reset role;
select is(
  privado.saldo_ia('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'menu') ->> 'puede',
  'true',
  'El sobre del menú sigue por su lado'
);

select tests.authenticate_as('fragmentless');
select is(
  public.uso_ia_cliente('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') - 'mes' - 'distribuidor_id' - 'distribuidor'
    - 'sobre_menu' - 'gastado_menu' - 'consultas_menu' - 'menu_en_limite',
  '{"tope": 10.00, "gastado": 8.0000, "sobre_agente": 8.00, "gastado_agente": 8.0000, "consultas_agente": 1,
    "saludos": 0, "agente_en_limite": true, "anuncios": 2, "gastado_anuncios": 4.0000}'::jsonb,
  '«Tope de IA»: el renglón del agente suma los dos, y ya trae cuántos anuncios salieron y cuánto costaron'
);


-- ─── Lo que se revisó al apartar no se vuelve a revisar ───────────────────────

reset role;
update public.uso_ia set costo_agente_usd = 0, costo_anuncios_usd = 0
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;
select tests.authenticate_as('don_chuy');
select is(
  tests.apartar('septimo', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'banderitas', 'post', array[501], null, null, true, null) - 'anuncio_id',
  '{"ok": true}'::jsonb,
  'Aparta uno más'
);

reset role;
update public.estilos set prendido = false where clave = 'banderitas';
update public.restaurantes set licencia_fin = privado.dia_local('America/Mexico_City') - 1
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
update public.uso_ia set costo_anuncios_usd = 8
where restaurante_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and mes = date_trunc('month', (now() at time zone 'America/Mexico_City')::date)::date;

select tests.como_worker();
select is(
  public.datos_del_anuncio(tests.id('septimo')) ->> 'estilo',
  'banderitas',
  'Si mientras se hace apagan su estilo, vence la licencia y se acaba el sobre, el trabajo sigue'
);
select is(
  public.terminar_anuncio(tests.id('septimo'),
                          'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('f', 32) || '.jpg',
                          'gpt-image-2.5-sunburst', 0, 0, 0) ->> 'ok',
  'true',
  'Y el anuncio se termina y cuenta'
);

select tests.authenticate_as('don_chuy');
select throws_ok(
  $$ select public.crear_contenido('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios',
  'Con la licencia vencida, Don Chuy ya no entra'
);
select is((select count(*)::integer from public.anuncios), 0, 'Ni lee sus renglones');

reset role;
update public.restaurantes set licencia_fin = privado.dia_local('America/Mexico_City') + 30
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';


-- ─── Un estilo que ya se usó no se borra ──────────────────────────────────────

select tests.authenticate_as('fragmentless');
select throws_ok(
  format('select public.eliminar_estilo(%s)', tests.e('banderitas')),
  '55000', 'Este estilo ya se usó: apágalo.',
  'Banderitas ya tiene anuncios: no se borra, se apaga'
);
select ok(tests.e('banderitas') is not null, 'Y sigue en la tabla');


-- ─── Las reglas de la tabla ───────────────────────────────────────────────────
-- Como su dueño, directo, para ver que la tabla misma las cuida.

reset role;

select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por)
     select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
            tests.miembro('Don Chuy')
     from generate_series(1, 2) $$,
  '23505', null,
  'Uno «haciendo» por restaurante, también en la tabla'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, terminado_at, vence)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), 'listo', now(), current_date) $$,
  '23514', null,
  'Uno listo lleva su archivo'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, terminado_at, vence)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), 'fallo', now(), current_date) $$,
  '23514', null,
  'Uno que falló lleva su motivo'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, motivo)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), 'rechazado') $$,
  '23514', null,
  'Uno haciéndose no tiene motivo'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, visto_at)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), now()) $$,
  '23514', null,
  'Ni se ve antes de terminar'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, motivo, ruta, terminado_at, vence)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), 'fallo', 'no_salio',
             'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('9', 32) || '.jpg', now(), current_date) $$,
  '23514', null,
  'Uno que no salió no tiene archivo'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, ruta, terminado_at, vence)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), 'listo',
             'restaurantes/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/biblioteca/' || repeat('9', 32) || '.jpg', now(), current_date) $$,
  '23514', null,
  'Su archivo va en la biblioteca de su restaurante'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, estado, ruta, terminado_at, vence)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), 'listo',
             'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/biblioteca/' || repeat('a', 32) || '.jpg', now(), current_date) $$,
  '23505', null,
  'Un archivo no es de dos anuncios'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post',
             (select jsonb_agg(jsonb_build_object('id', g, 'nombre', 'P' || g)) from generate_series(1, 6) g),
             tests.miembro('Don Chuy')) $$,
  '23514', null,
  'Hasta 5 productos, también en la tabla'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, mensaje)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), ' ') $$,
  '23514', null,
  'Un mensaje vacío va como null'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, color)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), '#2b5baa') $$,
  '23514', null,
  'El color, como menu_color: #RRGGBB en mayúsculas'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, palabras)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), '["TACO"]') $$,
  '23514', null,
  'Las palabras, un objeto'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Gerente B')) $$,
  '23503', null,
  'Lo hace un miembro de su restaurante'
);
select throws_ok(
  $$ insert into public.anuncios (restaurante_id, estilo_id, formato, productos, hecho_por, costo_usd)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.e('clasico'), 'post', '[{"id": 501, "nombre": "Taco"}]',
             tests.miembro('Don Chuy'), -0.01) $$,
  '23514', null,
  'El costo no es negativo'
);

select * from finish();
rollback;
