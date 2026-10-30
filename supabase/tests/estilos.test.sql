-- Pruebas de la migración estilos (parte 7a): la tabla de los estilos de los anuncios con los 24 de
-- la libreta 7, que nadie la lea ni la escriba directo, las funciones de «Estilos» del panel de
-- Fragmentless, las dos preguntas del Worker para las muestras y los estilos que el gerente puede
-- elegir hoy, contados con el día de su restaurante.
--
-- Escenario: Fragmentless, Juanito (distribuidor), Don Chuy (gerente de La Fonda, en la hora de
-- México) con Pepe (mesero), el gerente de una fonda en Kiritimati y el de una con la licencia
-- vencida.
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

-- Los ayudantes de estas pruebas. Leen la tabla como su dueño, porque nadie con sesión la lee
-- directo.

create function tests.estilo(p_clave text)
returns public.estilos
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.estilos where clave = p_clave;
$$;

create function tests.claves(p_grupo text)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_agg(clave order by orden, id) from public.estilos where grupo = p_grupo;
$$;

create function tests.ordenes(p_grupo text)
returns integer[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_agg(orden order by orden, id) from public.estilos where grupo = p_grupo;
$$;

-- Las fechas de un estilo que sale solo ese día: {mes, día, mes, día}. El 29 de febrero no sirve
-- en la tabla, así que ese día da del 28 de febrero al 1 de marzo.
create function tests.fechas(p_dia date)
returns smallint[]
language sql
immutable
as $$
  select case
    when extract(month from p_dia) = 2 and extract(day from p_dia) = 29 then array[2, 28, 3, 1]::smallint[]
    else array[extract(month from p_dia), extract(day from p_dia),
               extract(month from p_dia), extract(day from p_dia)]::smallint[]
  end;
$$;

-- La sesión del aparato ligado de Pepe, como en las pruebas de empleados: sin ella, alguien que
-- no es gerente no entra a nada.
create function tests.en_aparato(p_sesion uuid)
returns void as $$
begin
  perform set_config('request.jwt.claims',
    (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
      || jsonb_build_object('session_id', p_sesion))::text, true);
end
$$ language plpgsql;

-- Lo que cada gerente debe ver en estilos_de_hoy, calculado antes como postgres.
create table tests.listas (nombre text primary key, claves text[]);

grant select on tests.listas to authenticated;
grant execute on function tests.estilo(text), tests.claves(text), tests.ordenes(text), tests.fechas(date),
  tests.en_aparato(uuid)
to anon, authenticated;


-- ─── Escenario ────────────────────────────────────────────────────────────────
-- Se siembra como postgres, dueño de las tablas. La Fonda está en la hora de México y la de
-- Kiritimati va 20 horas adelante: casi siempre allá ya es mañana. La tercera tiene la licencia
-- vencida.

do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
begin
  perform tests.create_supabase_user('fragmentless', 'fragmentless@prueba.test');
  perform tests.create_supabase_user('juanito', 'juanito@prueba.test');
  perform tests.create_supabase_user('don_chuy', 'don.chuy@prueba.test');
  perform tests.create_supabase_user('pepe', 'pepe@prueba.test');
  perform tests.create_supabase_user('gerente_k', 'gerente.k@prueba.test');
  perform tests.create_supabase_user('gerente_v', 'gerente.v@prueba.test');

  insert into public.plataforma_admins (usuario_id)
  values (tests.get_supabase_uid('fragmentless'));

  insert into public.distribuidores (nombre, usuario_id)
  values ('Juanito', tests.get_supabase_uid('juanito'));

  insert into public.restaurantes (id, nombre, slug, licencia_activa, licencia_inicio, licencia_fin, zona_horaria) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'La Fonda de Don Chuy', 'fonda-don-chuy', true, hoy - 30, hoy + 30, 'America/Mexico_City'),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'La Fonda de Kiritimati', 'fonda-kiritimati', true, hoy - 30, hoy + 30, 'Pacific/Kiritimati'),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'La Fonda Vencida', 'fonda-vencida', true, hoy - 60, hoy - 2, 'America/Mexico_City');

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles) values
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('don_chuy'), 'Don Chuy', '{gerente}'),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', tests.get_supabase_uid('pepe'), 'Pepe', '{mesero}'),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', tests.get_supabase_uid('gerente_k'), 'Gerente K', '{gerente}'),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', tests.get_supabase_uid('gerente_v'), 'Gerente V', '{gerente}');

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, sesion_id)
  select restaurante_id, 'Celular de Pepe', id, repeat('1', 64), '5e5e5e5e-0000-4000-8000-000000000001'
  from public.miembros where nombre = 'Pepe';
end;
$$;

select plan(123);


-- ─── Los 24 de la libreta 7 ───────────────────────────────────────────────────

select is((select count(*)::integer from public.estilos), 24, 'La migración trae los 24 estilos de la libreta 7');

select is(
  (select count(*)::integer from public.estilos
   where prendido or muestra_post_ruta is not null or muestra_historia_ruta is not null or muestra_cartel_ruta is not null),
  0,
  'Los 24 nacen apagados y sin muestras'
);

select is(
  tests.claves('temporada'),
  array['futbol', 'navidad', 'dia-de-muertos', 'halloween'],
  'De temporada: Fútbol, Navidad, Día de Muertos y Halloween, en ese orden'
);

select is(
  tests.claves('para_todos'),
  array['clasico', 'letra-gigante', 'anatomia', 'explosion', 'promo', 'minimalista', 'estrella', 'mano',
        'estrellas', 'palabra-repetida', 'reflector', 'diagonal', 'combo-en-mano', 'banderitas', 'barda',
        'cuadros', 'desayunos', 'menu-de-cafe', 'palabra-vertical', 'ranura'],
  'Para todos: los 20 normales, con los de cafetería al final'
);

select is(
  array(select nombre from public.estilos order by case grupo when 'temporada' then 1 else 2 end, orden),
  array['Fútbol', 'Navidad', 'Día de Muertos', 'Halloween', 'Clásico', 'Letra gigante', 'Anatomía', 'Explosión',
        'Promo', 'Minimalista', 'Estrella', 'Mano', 'Estrellas', 'Palabra repetida', 'Reflector', 'Diagonal',
        'Combo en mano', 'Banderitas', 'Barda', 'Cuadros', 'Desayunos', 'Menú de café', 'Palabra vertical', 'Ranura'],
  'Los nombres de la tabla «Los estilos»'
);

select is(
  (select descripcion from public.estilos where clave = 'clasico'),
  'La mitad de arriba de tu color, la de abajo crema, con el precio en grande.',
  'Cada uno con lo que dice su cuadro'
);

select results_eq(
  $$select clave, desde_mes::integer, desde_dia::integer, hasta_mes::integer, hasta_dia::integer
    from public.estilos where grupo = 'temporada' order by orden$$,
  $$values ('futbol'::text, null::integer, null::integer, null::integer, null::integer),
           ('navidad', 12, 1, 12, 25), ('dia-de-muertos', 10, 15, 11, 2), ('halloween', 10, 10, 10, 31)$$,
  'El fútbol sale siempre; Navidad del 1 al 25 de diciembre, Día de Muertos del 15 de octubre al 2 de noviembre y Halloween del 10 al 31 de octubre'
);

select is(
  (select count(*)::integer from public.estilos where grupo = 'para_todos' and desde_mes is not null),
  0,
  'Los de Para todos no llevan fechas'
);


-- ─── Nadie lee la tabla directo ───────────────────────────────────────────────

select ok(
  not (has_table_privilege('anon', 'public.estilos', 'select, insert, update, delete')
       or has_table_privilege('authenticated', 'public.estilos', 'select, insert, update, delete')
       or has_table_privilege('service_role', 'public.estilos', 'select, insert, update, delete')
       or has_any_column_privilege('anon', 'public.estilos', 'select, insert, update')
       or has_any_column_privilege('authenticated', 'public.estilos', 'select, insert, update')
       or has_any_column_privilege('service_role', 'public.estilos', 'select, insert, update')),
  'Nadie lee ni escribe la tabla directo, tampoco el Worker con la llave secreta'
);

select ok((select relrowsecurity from pg_class where oid = 'public.estilos'::regclass), 'La tabla tiene RLS');

select is(
  array(
    select f from unnest(array[
      'public.estilos_de_hoy(uuid)', 'public.panel_estilos()',
      'public.guardar_estilo(bigint, text, text, text, text, smallint, smallint, smallint, smallint, text, text, text)',
      'public.prender_estilo(bigint, boolean)', 'public.mover_estilo(bigint, text)', 'public.eliminar_estilo(bigint)',
      'public.puedo_subir_muestra(text)', 'public.puedo_borrar_muestra(text)'
    ]) f
    where not has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('service_role', f, 'execute')
  ),
  '{}'::text[],
  'Las 8 funciones se llaman con sesión, nunca sin ella ni con la llave secreta'
);

select is(
  array(
    select f from unnest(array[
      'privado.clave_fija()', 'privado.en_sus_fechas(smallint, smallint, smallint, smallint, date)',
      'privado.estilos_a_la_vista(date)'
    ]) f
    where has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('anon', f, 'execute')
       or has_function_privilege('service_role', f, 'execute')
  ),
  '{}'::text[],
  'Las 3 de privado no se llaman desde fuera'
);


-- ─── Las reglas de la tabla ───────────────────────────────────────────────────
-- Directo como postgres, por si un día una fila llega sin pasar por las funciones.

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('dia_madres', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no lleva guion bajo'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('día-madres', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no lleva acentos'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('Madres', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no lleva mayúsculas'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('-madres', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no empieza con guion'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('madres-', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no termina con guion'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('dia--madres', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no lleva dos guiones seguidos'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('', 'Madres', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'La clave no va vacía'
);

select throws_ok(
  format($$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values (%L, 'Madres', 'Flores.', 'para_todos', 99)$$, repeat('a', 41)),
  '23514', null, 'La clave tiene hasta 40 letras'
);

select lives_ok(
  format($$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values (%L, 'Cuarenta', 'Flores.', 'para_todos', 99)$$, repeat('a', 40)),
  'Una clave de 40 letras sí cabe'
);

delete from public.estilos where clave = repeat('a', 40);

select throws_ok(
  $$update public.estilos set clave = 'futbol-2' where clave = 'futbol'$$,
  '22023', 'La clave de un estilo ya guardado no cambia', 'La clave guardada no cambia, ni directo en la tabla'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('barda-2', 'BARDA', 'Flores.', 'para_todos', 99)$$,
  '23505', null, '«Barda» y «BARDA» no conviven'
);

select throws_ok(
  format($$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('largo', %L, 'Flores.', 'para_todos', 99)$$, repeat('n', 31)),
  '23514', null, 'El nombre tiene hasta 30 letras'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('vacio', '   ', 'Flores.', 'para_todos', 99)$$,
  '23514', null, 'El nombre no va en blanco'
);

select throws_ok(
  format($$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('largo', 'Largo', %L, 'para_todos', 99)$$, repeat('d', 81)),
  '23514', null, 'Lo que dice su cuadro tiene hasta 80 letras'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden) values ('cafe', 'Café', 'Flores.', 'cafeteria', 99)$$,
  '23514', null, 'Solo hay dos grupos: ya no existe Cafetería'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes)
    values ('madres', 'Madres', 'Flores.', 'temporada', 99, 5, 1, 5)$$,
  '23514', null, 'Las fechas van las cuatro o ninguna'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia)
    values ('madres', 'Madres', 'Flores.', 'para_todos', 99, 5, 1, 5, 10)$$,
  '23514', null, 'Solo los de temporada llevan fechas'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia)
    values ('madres', 'Madres', 'Flores.', 'temporada', 99, 2, 20, 2, 29)$$,
  '23514', null, 'El 29 de febrero no sirve: no existe todos los años'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia)
    values ('madres', 'Madres', 'Flores.', 'temporada', 99, 4, 31, 5, 10)$$,
  '23514', null, 'El 31 de abril no existe'
);

select throws_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia)
    values ('madres', 'Madres', 'Flores.', 'temporada', 99, 13, 1, 5, 10)$$,
  '23514', null, 'No hay mes 13'
);

select lives_ok(
  $$insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia)
    values ('reyes', 'Reyes', 'Tu rosca.', 'temporada', 99, 12, 20, 1, 6)$$,
  'Un rango puede cruzar el año: del 20 de diciembre al 6 de enero'
);

delete from public.estilos where clave = 'reyes';

select throws_ok(
  format($$update public.estilos set muestra_post_ruta = %L where clave = 'barda'$$, 'estilos/navidad/' || repeat('a', 32) || '.webp'),
  '23514', null, 'La muestra va en la carpeta de su propia clave'
);

select throws_ok(
  format($$update public.estilos set muestra_historia_ruta = %L where clave = 'barda'$$, 'estilos/barda/' || repeat('a', 32) || '.png'),
  '23514', null, 'La muestra va en WebP'
);

select throws_ok(
  format($$update public.estilos set muestra_cartel_ruta = %L where clave = 'barda'$$, 'restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/carteles/' || repeat('a', 32) || '.webp'),
  '23514', null, 'Una muestra nunca vive en la carpeta de un restaurante'
);

select lives_ok(
  format($$update public.estilos set muestra_cartel_ruta = %L where clave = 'barda'$$, 'estilos/barda/' || repeat('a', 32) || '.webp'),
  'En estilos/barda/ sí cabe la muestra de Barda'
);

update public.estilos set muestra_cartel_ruta = null where clave = 'barda';


-- ─── Solo Fragmentless ────────────────────────────────────────────────────────

select tests.clear_authentication();

select throws_ok('select * from public.panel_estilos()', '42501', null, 'Sin sesión no se lee panel_estilos');

select throws_ok(
  $$select * from public.estilos_de_hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '42501', null, 'Sin sesión no se lee estilos_de_hoy'
);

select tests.authenticate_as('don_chuy');

select throws_ok('select * from public.panel_estilos()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un gerente no lee panel_estilos');

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '42501', 'Solo Fragmentless puede hacer esto', 'Un gerente no da de alta estilos'
);

select throws_ok(
  format('select public.prender_estilo(%s, true)', (tests.estilo('barda')).id),
  '42501', 'Solo Fragmentless puede hacer esto', 'Un gerente no prende estilos'
);

select throws_ok(
  format($$select public.mover_estilo(%s, 'arriba')$$, (tests.estilo('barda')).id),
  '42501', 'Solo Fragmentless puede hacer esto', 'Un gerente no mueve estilos'
);

select throws_ok(
  format('select public.eliminar_estilo(%s)', (tests.estilo('barda')).id),
  '42501', 'Solo Fragmentless puede hacer esto', 'Un gerente no elimina estilos'
);

select is(public.puedo_subir_muestra('barda'), false, 'Un gerente no sube muestras');

select is(public.puedo_borrar_muestra('estilos/barda/' || repeat('a', 32) || '.webp'), false, 'Un gerente no borra muestras');

select tests.authenticate_as('juanito');

select throws_ok('select * from public.panel_estilos()', '42501', 'Solo Fragmentless puede hacer esto',
  'Un distribuidor no ve «Estilos»');

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '42501', 'Solo Fragmentless puede hacer esto', 'Un distribuidor no da de alta estilos'
);

select is(public.puedo_subir_muestra('barda'), false, 'Un distribuidor no sube muestras');


-- ─── «Agregar estilo» ─────────────────────────────────────────────────────────

select tests.authenticate_as('fragmentless');

select is(
  public.guardar_estilo(null, 'dia-de-las-madres', '  Día de las Madres ', ' Tu producto entre flores, para festejar a mamá. ',
    'temporada', 5::smallint, 1::smallint, 5::smallint, 10::smallint,
    'estilos/dia-de-las-madres/' || repeat('1', 32) || '.webp', null, null) - 'id',
  '{"borrar": []}'::jsonb,
  'Un estilo nuevo se guarda y no tiene muestras viejas que borrar'
);

select results_eq(
  $$select nombre, descripcion, grupo, orden, prendido, desde_mes::integer, hasta_dia::integer, muestra_post_ruta, muestra_historia_ruta
    from tests.estilo('dia-de-las-madres')$$,
  format($$values ('Día de las Madres'::text, 'Tu producto entre flores, para festejar a mamá.'::text, 'temporada'::text, 5, false,
                   5, 10, %L::text, null::text)$$, 'estilos/dia-de-las-madres/' || repeat('1', 32) || '.webp'),
  'Nace apagado, al final de De temporada, con sus fechas, su muestra y sin espacios de sobra'
);

select lives_ok(
  $$select public.guardar_estilo(null, 'taquiza', 'Taquiza', 'Tus tacos en charola.', 'para_todos', null, null, null, null, null, null, null)$$,
  'Fragmentless da de alta un estilo de Para todos sin muestras'
);

select is((tests.estilo('taquiza')).orden, 21, 'Va al final de Para todos, después de Ranura');

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', '   ', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '22023', 'Escribe el nombre del estilo.', 'Sin nombre no se guarda'
);

select throws_ok(
  format($$select public.guardar_estilo(null, 'madres', %L, 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$, repeat('n', 31)),
  '22023', 'El nombre puede tener hasta 30 letras', 'El nombre tiene hasta 30 letras'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', '', 'para_todos', null, null, null, null, null, null, null)$$,
  '22023', 'Escribe lo que dice su cuadro.', 'Sin lo que dice su cuadro no se guarda'
);

select throws_ok(
  format($$select public.guardar_estilo(null, 'madres', 'Madres', %L, 'para_todos', null, null, null, null, null, null, null)$$, repeat('d', 81)),
  '22023', 'Lo que dice su cuadro puede tener hasta 80 letras', 'Lo que dice su cuadro tiene hasta 80 letras'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'Día-madres', 'Madres', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '22023', 'La clave lleva solo letras sin acento, números y guiones: dia-de-muertos.', 'Una clave con acento o mayúscula no se guarda'
);

select throws_ok(
  $$select public.guardar_estilo(null, null, 'Madres', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '22023', 'La clave lleva solo letras sin acento, números y guiones: dia-de-muertos.', 'Un estilo nuevo lleva su clave'
);

select throws_ok(
  format($$select public.guardar_estilo(null, %L, 'Madres', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$, repeat('a', 41)),
  '22023', 'La clave puede tener hasta 40 letras', 'La clave tiene hasta 40 letras'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'cafeteria', null, null, null, null, null, null, null)$$,
  '22023', 'El grupo es De temporada o Para todos', 'Solo hay dos grupos'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'temporada', 5::smallint, 1::smallint, 5::smallint, null, null, null, null)$$,
  '22023', 'Las fechas llevan desde y hasta, cada una con su día y su mes', 'Las fechas van completas'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'para_todos', 5::smallint, 1::smallint, 5::smallint, 10::smallint, null, null, null)$$,
  '22023', 'Solo los de temporada llevan fechas', 'Uno de Para todos no lleva fechas'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'temporada', 2::smallint, 20::smallint, 2::smallint, 29::smallint, null, null, null)$$,
  '22023', 'Esa fecha no existe todos los años', 'El 29 de febrero no sirve'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'barda', 'Otra barda', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '23505', 'Ya hay un estilo con la clave barda.', 'Dos estilos no comparten clave'
);

select throws_ok(
  $$select public.guardar_estilo(null, 'barda-2', 'BARDA', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  '23505', 'Ya hay un estilo que se llama Barda.', 'Dos estilos no se llaman igual, ni con otras mayúsculas'
);

select throws_ok(
  format($$select public.guardar_estilo(null, 'madres', 'Madres', 'Flores.', 'para_todos', null, null, null, null, %L, null, null)$$,
    'estilos/barda/' || repeat('1', 32) || '.webp'),
  '23514', null, 'Su muestra va en la carpeta de su clave'
);


-- ─── «Guardar cambios» ────────────────────────────────────────────────────────

select is(
  public.guardar_estilo((tests.estilo('barda')).id, null, 'Barda al sol', 'Tu producto en una barda al sol, con flechas que lo señalan.',
    'para_todos', null, null, null, null, null, null, null),
  jsonb_build_object('id', (tests.estilo('barda')).id, 'borrar', '[]'::jsonb),
  'Cambiarle el nombre regresa su id y nada que borrar'
);

select results_eq(
  $$select clave, nombre, orden from tests.estilo('barda')$$,
  $$values ('barda'::text, 'Barda al sol'::text, 15)$$,
  'Con otro nombre, su clave y su lugar se quedan'
);

select throws_ok(
  format($$select public.guardar_estilo(%s, 'barda-al-sol', 'Barda al sol', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
    (tests.estilo('barda')).id),
  '22023', 'La clave de un estilo ya guardado no cambia', 'Su clave no cambia, ni aunque cambie el nombre'
);

select lives_ok(
  format($$select public.guardar_estilo(%s, 'barda', 'BARDA AL SOL', 'Tu producto en una barda al sol, con flechas que lo señalan.', 'para_todos', null, null, null, null, null, null, null)$$,
    (tests.estilo('barda')).id),
  'Con su misma clave sí se guarda, y puede cambiar solo sus mayúsculas'
);

select throws_ok(
  $$select public.guardar_estilo(999999, null, 'Madres', 'Flores.', 'para_todos', null, null, null, null, null, null, null)$$,
  'P0002', 'Ese estilo ya no existe', 'Uno que ya no existe no se guarda'
);

select lives_ok(
  format($$select public.guardar_estilo(%s, null, 'Día de las Madres', 'Tu producto entre flores, para festejar a mamá.', 'para_todos',
           null, null, null, null, %L, null, null)$$,
    (tests.estilo('dia-de-las-madres')).id, 'estilos/dia-de-las-madres/' || repeat('1', 32) || '.webp'),
  'Fragmentless le cambia el grupo a un estilo'
);

select results_eq(
  $$select grupo, orden, desde_mes::integer from tests.estilo('dia-de-las-madres')$$,
  $$values ('para_todos'::text, 22, null::integer)$$,
  'Con otro grupo se va al final del nuevo, y sin fechas'
);

select is(
  public.guardar_estilo((tests.estilo('navidad')).id, null, 'Navidad', 'Tu producto en la mano de Santa.', 'temporada',
    12::smallint, 1::smallint, 12::smallint, 25::smallint,
    'estilos/navidad/' || repeat('a', 32) || '.webp', 'estilos/navidad/' || repeat('b', 32) || '.webp',
    'estilos/navidad/' || repeat('c', 32) || '.webp') -> 'borrar',
  '[]'::jsonb,
  'Agregarle sus 3 muestras no borra nada'
);

select is(
  public.guardar_estilo((tests.estilo('navidad')).id, null, 'Navidad', 'Tu producto en la mano de Santa.', 'temporada',
    12::smallint, 1::smallint, 12::smallint, 25::smallint,
    'estilos/navidad/' || repeat('a', 32) || '.webp', 'estilos/navidad/' || repeat('d', 32) || '.webp', null) -> 'borrar',
  jsonb_build_array('estilos/navidad/' || repeat('b', 32) || '.webp', 'estilos/navidad/' || repeat('c', 32) || '.webp'),
  'Cambiar la de historia y quitar la del cartel regresa las dos viejas para borrarlas'
);

select results_eq(
  $$select muestra_post_ruta, muestra_historia_ruta, muestra_cartel_ruta from tests.estilo('navidad')$$,
  format($$values (%L::text, %L::text, null::text)$$,
    'estilos/navidad/' || repeat('a', 32) || '.webp', 'estilos/navidad/' || repeat('d', 32) || '.webp'),
  'Queda con la de post de antes, la de historia nueva y sin la del cartel'
);

select is(
  public.guardar_estilo((tests.estilo('navidad')).id, 'navidad', 'Navidad', 'Tu producto en la mano de Santa.', 'temporada',
    12::smallint, 1::smallint, 12::smallint, 25::smallint,
    'estilos/navidad/' || repeat('a', 32) || '.webp', 'estilos/navidad/' || repeat('d', 32) || '.webp', null) -> 'borrar',
  '[]'::jsonb,
  'Guardar sin cambiar las muestras no borra nada'
);


-- ─── El interruptor ───────────────────────────────────────────────────────────

select lives_ok(format('select public.prender_estilo(%s, true)', (tests.estilo('navidad')).id),
  'Fragmentless prende un estilo aunque le falte la muestra del cartel');

select is((tests.estilo('navidad')).prendido, true, 'Queda prendido');

select lives_ok(format('select public.prender_estilo(%s, true)', (tests.estilo('navidad')).id),
  'Prender uno ya prendido no falla');

select lives_ok(format('select public.prender_estilo(%s, false)', (tests.estilo('navidad')).id),
  'Fragmentless lo apaga');

select is((tests.estilo('navidad')).prendido, false, 'Queda apagado');

select throws_ok(format('select public.prender_estilo(%s, null)', (tests.estilo('navidad')).id),
  '22023', 'El estilo va prendido o apagado', 'El interruptor no se queda a medias');

select throws_ok('select public.prender_estilo(999999, true)', 'P0002', 'Ese estilo ya no existe',
  'Uno que ya no existe no se prende');


-- ─── Las flechas ──────────────────────────────────────────────────────────────
-- De temporada queda con huecos (10, 20, 30, 40), como si se hubieran ido estilos.

reset role;
update public.estilos set orden = orden * 10 where grupo = 'temporada';
select tests.authenticate_as('fragmentless');

select lives_ok(format($$select public.mover_estilo(%s, 'arriba')$$, (tests.estilo('halloween')).id),
  'Fragmentless sube Halloween');

select is(tests.claves('temporada'), array['futbol', 'navidad', 'halloween', 'dia-de-muertos'],
  'Halloween queda antes de Día de Muertos');

select is(tests.ordenes('temporada'), array[1, 2, 3, 4], 'El grupo queda numerado 1, 2, 3, 4');

select lives_ok(format($$select public.mover_estilo(%s, 'arriba')$$, (tests.estilo('futbol')).id),
  'Subir al primero no falla');

select lives_ok(format($$select public.mover_estilo(%s, 'arriba')$$, (tests.estilo('clasico')).id),
  'Subir al primero de Para todos no falla');

select is(
  array[(tests.claves('temporada'))[1], (tests.claves('para_todos'))[1], (tests.estilo('clasico')).grupo],
  array['futbol', 'clasico', 'para_todos'],
  'En la orilla no pasa nada: Clásico no brinca a De temporada'
);

select lives_ok(format($$select public.mover_estilo(%s, 'abajo')$$, (tests.estilo('dia-de-las-madres')).id),
  'Bajar al último no falla');

select is((tests.claves('para_todos'))[22], 'dia-de-las-madres', 'El último se queda al final');

select throws_ok(format($$select public.mover_estilo(%s, 'izquierda')$$, (tests.estilo('barda')).id),
  '22023', 'El estilo solo se mueve arriba o abajo', 'Solo se mueve arriba o abajo');

select throws_ok($$select public.mover_estilo(999999, 'arriba')$$, 'P0002', 'Ese estilo ya no existe',
  'Uno que ya no existe no se mueve');


-- ─── «Eliminar estilo» ────────────────────────────────────────────────────────

select is(public.eliminar_estilo((tests.estilo('taquiza')).id), '{}'::text[],
  'Uno sin muestras se borra y no hay nada que borrar en R2');

select is(public.eliminar_estilo((tests.estilo('dia-de-las-madres')).id),
  array['estilos/dia-de-las-madres/' || repeat('1', 32) || '.webp'],
  'Uno con su muestra se borra y regresa su ruta para borrarla en R2');

select is(cardinality(tests.claves('para_todos')), 20, 'Para todos vuelve a tener 20');

select throws_ok('select public.eliminar_estilo(999999)', 'P0002', 'Ese estilo ya no existe',
  'Uno que ya no existe no se elimina');

-- La tabla de los anuncios llega con la 7b; aquí una de mentira que señala al Clásico.
reset role;
create table tests.anuncios (id bigint primary key, estilo_id bigint not null references public.estilos (id));
insert into tests.anuncios values (1, (select id from public.estilos where clave = 'clasico'));
select tests.authenticate_as('fragmentless');

select throws_ok(format('select public.eliminar_estilo(%s)', (tests.estilo('clasico')).id),
  '55000', 'Este estilo ya se usó: apágalo.', 'Uno que ya se usó no se borra');

select is((tests.estilo('clasico')).clave, 'clasico', 'El Clásico sigue ahí');


-- ─── Las preguntas del Worker ─────────────────────────────────────────────────

select is(public.puedo_subir_muestra('dia-del-nino'), true,
  'Fragmentless sube muestras de un estilo que todavía no se guarda');

select is(
  array[public.puedo_subir_muestra('Día'), public.puedo_subir_muestra('../restaurantes'), public.puedo_subir_muestra(null),
        public.puedo_subir_muestra(repeat('a', 41))],
  array[false, false, false, false],
  'Ni con una clave mal escrita, ni fuera de estilos/, ni sin clave'
);

select is(public.puedo_borrar_muestra('estilos/navidad/' || repeat('e', 32) || '.webp'), true,
  'Fragmentless borra una muestra que ningún estilo usa');

select is(
  array[public.puedo_borrar_muestra('estilos/navidad/' || repeat('a', 32) || '.webp'),
        public.puedo_borrar_muestra('estilos/navidad/' || repeat('d', 32) || '.webp')],
  array[false, false],
  'No borra la muestra de post ni la de historia que Navidad usa'
);

select is(
  array[public.puedo_borrar_muestra('restaurantes/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/menu/' || repeat('e', 32) || '.webp'),
        public.puedo_borrar_muestra('estilos/navidad/../' || repeat('e', 32) || '.webp'),
        public.puedo_borrar_muestra('estilos/navidad/' || repeat('e', 32) || '.png'),
        public.puedo_borrar_muestra(null)],
  array[false, false, false, false],
  'Nunca borra fuera de estilos/ ni algo que no sea una muestra'
);


-- ─── panel_estilos ────────────────────────────────────────────────────────────
-- Halloween sale hoy en México y Navidad dentro de 3 días.

reset role;
do $$
declare
  hoy date := privado.dia_local('America/Mexico_City');
  f smallint[] := tests.fechas(hoy);
  g smallint[] := tests.fechas(hoy + 3);
begin
  update public.estilos set desde_mes = f[1], desde_dia = f[2], hasta_mes = f[3], hasta_dia = f[4] where clave = 'halloween';
  update public.estilos set desde_mes = g[1], desde_dia = g[2], hasta_mes = g[3], hasta_dia = g[4] where clave = 'navidad';
end;
$$;
select tests.authenticate_as('fragmentless');

select is(
  array(select clave from public.panel_estilos()),
  tests.claves('temporada') || tests.claves('para_todos'),
  'Fragmentless ve los 24, primero De temporada y luego Para todos, cada grupo en su orden'
);

select results_eq(
  $$select clave, en_fechas from public.panel_estilos() where clave in ('futbol', 'halloween', 'navidad', 'barda') order by clave$$,
  $$values ('barda'::text, true), ('futbol', true), ('halloween', true), ('navidad', false)$$,
  'en_fechas: sin fechas siempre; Halloween sí, porque hoy cae en sus fechas en México; Navidad, todavía no'
);

select results_eq(
  $$select nombre, descripcion, grupo, orden, prendido, muestra_post_ruta, muestra_historia_ruta, muestra_cartel_ruta
    from public.panel_estilos() where clave = 'navidad'$$,
  format($$values ('Navidad'::text, 'Tu producto en la mano de Santa.'::text, 'temporada'::text, 2, false, %L::text, %L::text, null::text)$$,
    'estilos/navidad/' || repeat('a', 32) || '.webp', 'estilos/navidad/' || repeat('d', 32) || '.webp'),
  'Cada renglón trae lo que la ventana enseña'
);


-- ─── estilos_de_hoy ───────────────────────────────────────────────────────────
-- Fútbol, Anatomía y Explosión tienen todo; Halloween sale hoy en México y Día de Muertos hoy en
-- Kiritimati; Navidad sale en 3 días; al Clásico le falta su cartel y Letra gigante está apagado.

reset role;
do $$
declare
  hoy_mx date := privado.dia_local('America/Mexico_City');
  hoy_ki date := privado.dia_local('Pacific/Kiritimati');
  f smallint[] := tests.fechas(hoy_mx);
  k smallint[] := tests.fechas(hoy_ki);
  e text;
begin
  update public.estilos set desde_mes = k[1], desde_dia = k[2], hasta_mes = k[3], hasta_dia = k[4] where clave = 'dia-de-muertos';
  foreach e in array array['futbol', 'halloween', 'dia-de-muertos', 'navidad', 'anatomia', 'explosion', 'letra-gigante', 'clasico'] loop
    update public.estilos
    set prendido = e <> 'letra-gigante',
        muestra_post_ruta = 'estilos/' || e || '/' || repeat('1', 32) || '.webp',
        muestra_historia_ruta = 'estilos/' || e || '/' || repeat('2', 32) || '.webp',
        muestra_cartel_ruta = case when e <> 'clasico' then 'estilos/' || e || '/' || repeat('3', 32) || '.webp' end
    where clave = e;
  end loop;

  insert into tests.listas values
    ('fonda', array['futbol', 'halloween']
       || case when privado.en_sus_fechas(k[1], k[2], k[3], k[4], hoy_mx) then array['dia-de-muertos'] else '{}' end
       || array['anatomia', 'explosion']),
    ('kiritimati', array['futbol']
       || case when privado.en_sus_fechas(f[1], f[2], f[3], f[4], hoy_ki) then array['halloween'] else '{}' end
       || array['dia-de-muertos', 'anatomia', 'explosion']);
end;
$$;

select tests.authenticate_as('don_chuy');

select is(
  array(select clave from public.estilos_de_hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')),
  (select claves from tests.listas where nombre = 'fonda'),
  'Don Chuy ve los prendidos con sus 3 muestras y en sus fechas de hoy en México, primero los de temporada'
);

select results_eq(
  $$select id, clave, nombre, descripcion, grupo, muestra_post_ruta, muestra_historia_ruta, muestra_cartel_ruta
    from public.estilos_de_hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') where clave = 'futbol'$$,
  format($$values (%s::bigint, 'futbol'::text, 'Fútbol'::text, 'Tus productos sobre la cancha, vistos desde arriba.'::text,
                   'temporada'::text, %L::text, %L::text, %L::text)$$,
    (tests.estilo('futbol')).id, 'estilos/futbol/' || repeat('1', 32) || '.webp',
    'estilos/futbol/' || repeat('2', 32) || '.webp', 'estilos/futbol/' || repeat('3', 32) || '.webp'),
  'Cada estilo llega con su clave, su nombre, su cuadro, su grupo y sus 3 muestras'
);

select throws_ok(
  $$select * from public.estilos_de_hoy('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Don Chuy no lee los de otro restaurante'
);

select throws_ok(
  $$select * from public.estilos_de_hoy(null)$$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Sin restaurante no hay estilos'
);

select tests.authenticate_as('gerente_k');

select is(
  array(select clave from public.estilos_de_hoy('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')),
  (select claves from tests.listas where nombre = 'kiritimati'),
  'En Kiritimati cuentan las fechas con su propio día'
);

select tests.authenticate_as('pepe');
select tests.en_aparato('5e5e5e5e-0000-4000-8000-000000000001');

select throws_ok(
  $$select * from public.estilos_de_hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Pepe, el mesero, no crea anuncios ni desde su aparato'
);

select tests.authenticate_as('gerente_v');

select throws_ok(
  $$select * from public.estilos_de_hoy('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Con la licencia vencida no hay estilos'
);

select tests.authenticate_as('fragmentless');

select throws_ok(
  $$select * from public.estilos_de_hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Fragmentless no es gerente de La Fonda'
);

select tests.authenticate_as('juanito');

select throws_ok(
  $$select * from public.estilos_de_hoy('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '42501', 'Solo el gerente de este restaurante puede crear anuncios', 'Juanito no crea anuncios de sus clientes'
);


-- ─── Las fechas, con días fijos ───────────────────────────────────────────────

reset role;

select is(
  privado.en_sus_fechas(null, null, null, null, date '2026-06-15'),
  true,
  'Sin fechas, sale siempre'
);

select is(
  array[privado.en_sus_fechas(10::smallint, 10::smallint, 10::smallint, 31::smallint, date '2026-10-10'),
        privado.en_sus_fechas(10::smallint, 10::smallint, 10::smallint, 31::smallint, date '2026-10-31'),
        privado.en_sus_fechas(10::smallint, 10::smallint, 10::smallint, 31::smallint, date '2026-10-09'),
        privado.en_sus_fechas(10::smallint, 10::smallint, 10::smallint, 31::smallint, date '2026-11-01')],
  array[true, true, false, false],
  'Halloween sale del 10 al 31 de octubre, los dos días incluidos'
);

select is(
  array[privado.en_sus_fechas(10::smallint, 15::smallint, 11::smallint, 2::smallint, date '2026-10-31'),
        privado.en_sus_fechas(10::smallint, 15::smallint, 11::smallint, 2::smallint, date '2026-11-02'),
        privado.en_sus_fechas(10::smallint, 15::smallint, 11::smallint, 2::smallint, date '2026-11-03')],
  array[true, true, false],
  'Día de Muertos pasa de octubre a noviembre'
);

select is(
  array[privado.en_sus_fechas(12::smallint, 20::smallint, 1::smallint, 6::smallint, date '2026-12-31'),
        privado.en_sus_fechas(12::smallint, 20::smallint, 1::smallint, 6::smallint, date '2027-01-06'),
        privado.en_sus_fechas(12::smallint, 20::smallint, 1::smallint, 6::smallint, date '2027-01-07'),
        privado.en_sus_fechas(12::smallint, 20::smallint, 1::smallint, 6::smallint, date '2026-12-19'),
        privado.en_sus_fechas(12::smallint, 20::smallint, 1::smallint, 6::smallint, date '2026-07-01')],
  array[true, true, false, false, false],
  'Un rango que cruza el año vale del 20 de diciembre al 6 de enero'
);

select is(
  array[privado.en_sus_fechas(2::smallint, 20::smallint, 3::smallint, 5::smallint, date '2028-02-29'),
        privado.en_sus_fechas(3::smallint, 1::smallint, 3::smallint, 5::smallint, date '2028-02-29'),
        privado.en_sus_fechas(5::smallint, 1::smallint, 5::smallint, 1::smallint, date '2026-05-01'),
        privado.en_sus_fechas(5::smallint, 1::smallint, 5::smallint, 1::smallint, date '2026-05-02')],
  array[true, false, true, false],
  'El 29 de febrero cae entre el 28 y el 1 de marzo; un rango de un solo día vale ese día'
);


select * from finish();

rollback;
