-- Creación de contenido, parte 7a: los estilos de los anuncios (libreta 7, lo decidido el 28 y el
-- 29 de octubre de 2026; libreta 2, Diccionario de datos; con la maqueta de la 7a
-- H2yFVjosPvSV56DJD1Un71).
--
-- Los estilos son de Fragmentless y salen en el panel de todos los clientes: no llevan
-- restaurante_id. Solo Fragmentless los escribe, con las funciones de «Estilos» de su panel, y
-- nadie lee la tabla directo: Fragmentless la lee entera con panel_estilos y el gerente, con
-- estilos_de_hoy, solo los que le pueden salir hoy. El prompt de cada estilo vive en el código del
-- Worker y se une a su fila por la clave, que también es su carpeta en R2 (estilos/<clave>/).
--
-- La migración trae los 24 de la libreta 7, apagados y sin muestras. Llegan con la 7b: la tabla de
-- los anuncios (desde ella, un estilo que ya se usó no se borra) y el filtro del prompt en el Worker.


-- ─── estilos ──────────────────────────────────────────────────────────────────
-- Uno de temporada sin fechas sale siempre, como el fútbol. Las fechas son día y mes, sin año, y
-- el rango puede cruzar el año (del 20 de diciembre al 6 de enero); el 29 de febrero no sirve,
-- porque no existe todos los años.

create table public.estilos (
  id bigint generated always as identity primary key,
  clave text not null unique
    constraint estilos_clave_formato
    check (clave ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(clave) <= 40),
  nombre text not null
    constraint estilos_nombre_largo
    check (btrim(nombre) <> '' and char_length(nombre) <= 30),
  descripcion text not null
    constraint estilos_descripcion_largo
    check (btrim(descripcion) <> '' and char_length(descripcion) <= 80),
  grupo text not null
    constraint estilos_grupo_lista check (grupo in ('temporada', 'para_todos')),
  orden integer not null,
  desde_mes smallint,
  desde_dia smallint,
  hasta_mes smallint,
  hasta_dia smallint,
  prendido boolean not null default false,
  muestra_post_ruta text
    constraint estilos_muestra_post_formato
    check (muestra_post_ruta ~ ('^estilos/' || clave || '/[0-9a-f]{32}\.webp$')),
  muestra_historia_ruta text
    constraint estilos_muestra_historia_formato
    check (muestra_historia_ruta ~ ('^estilos/' || clave || '/[0-9a-f]{32}\.webp$')),
  muestra_cartel_ruta text
    constraint estilos_muestra_cartel_formato
    check (muestra_cartel_ruta ~ ('^estilos/' || clave || '/[0-9a-f]{32}\.webp$')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint estilos_fechas_completas
    check (num_nonnulls(desde_mes, desde_dia, hasta_mes, hasta_dia) in (0, 4)),
  constraint estilos_fechas_de_temporada
    check (desde_mes is null or grupo = 'temporada'),
  constraint estilos_desde_existe
    check (desde_mes is null or (desde_mes between 1 and 12
      and desde_dia between 1 and (array[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])[desde_mes])),
  constraint estilos_hasta_existe
    check (hasta_mes is null or (hasta_mes between 1 and 12
      and hasta_dia between 1 and (array[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])[hasta_mes]))
);

-- «Barda» y «barda» no conviven.
create unique index estilos_nombre_unico on public.estilos (lower(nombre));

create trigger estilos_updated_at
before update on public.estilos
for each row execute function privado.set_updated_at();

-- La clave no cambia, ni aunque cambie el nombre: de ella cuelgan su carpeta en R2 y su prompt.
create function privado.clave_fija()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.clave is distinct from old.clave then
    raise exception 'La clave de un estilo ya guardado no cambia' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger estilos_clave_fija
before update of clave on public.estilos
for each row execute function privado.clave_fija();


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto, también para el Worker: la tabla se lee y se escribe
-- solo con las funciones de abajo.

alter table public.estilos enable row level security;

revoke all on table public.estilos from anon, authenticated, service_role;
revoke all on sequence public.estilos_id_seq from anon, authenticated, service_role;


-- ─── Los 24 de la libreta 7 ───────────────────────────────────────────────────
-- En su grupo y su orden, apagados y sin muestras. Fragmentless sube sus muestras cuando salgan de
-- las pruebas del desarrollador y prende cada uno cuando lo revise.

insert into public.estilos (clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia)
values
  ('futbol', 'Fútbol', 'Tus productos sobre la cancha, vistos desde arriba.', 'temporada', 1, null, null, null, null),
  ('navidad', 'Navidad', 'Tu producto en la mano de Santa.', 'temporada', 2, 12, 1, 12, 25),
  ('dia-de-muertos', 'Día de Muertos', 'Tu producto en el altar, entre cempasúchil y velas.', 'temporada', 3, 10, 15, 11, 2),
  ('halloween', 'Halloween', 'Una sombra va por tu producto.', 'temporada', 4, 10, 10, 10, 31),
  ('clasico', 'Clásico', 'La mitad de arriba de tu color, la de abajo crema, con el precio en grande.', 'para_todos', 1, null, null, null, null),
  ('letra-gigante', 'Letra gigante', 'Una palabra enorme y tu producto abajo.', 'para_todos', 2, null, null, null, null),
  ('anatomia', 'Anatomía', 'Tu producto en capas, cada una con su nombre.', 'para_todos', 3, null, null, null, null),
  ('explosion', 'Explosión', 'Tu producto estallando con sus ingredientes.', 'para_todos', 4, null, null, null, null),
  ('promo', 'Promo', 'Tu producto flotando y tu promoción en un círculo.', 'para_todos', 5, null, null, null, null),
  ('minimalista', 'Minimalista', 'Tu producto chiquito, mucho espacio y dos renglones.', 'para_todos', 6, null, null, null, null),
  ('estrella', 'Estrella', 'Tu mensaje en una estrella y tus datos abajo.', 'para_todos', 7, null, null, null, null),
  ('mano', 'Mano', 'Una mano lo sostiene y su nombre se repite detrás.', 'para_todos', 8, null, null, null, null),
  ('estrellas', 'Estrellas', 'Una mano con el plato, entre estrellas y destellos.', 'para_todos', 9, null, null, null, null),
  ('palabra-repetida', 'Palabra repetida', 'Su nombre en filas de lado a lado y tu producto al centro.', 'para_todos', 10, null, null, null, null),
  ('reflector', 'Reflector', 'Tu producto en una mesa, bajo una luz.', 'para_todos', 11, null, null, null, null),
  ('diagonal', 'Diagonal', 'Dos tonos en diagonal, una palabra gigante y tu promoción.', 'para_todos', 12, null, null, null, null),
  ('combo-en-mano', 'Combo en mano', 'Tres manos con tu combo, cada producto con su nombre.', 'para_todos', 13, null, null, null, null),
  ('banderitas', 'Banderitas', 'Tus productos en fila sobre azulejo, cada uno con su banderita.', 'para_todos', 14, null, null, null, null),
  ('barda', 'Barda', 'Tu producto en una barda al sol, con flechas que lo señalan.', 'para_todos', 15, null, null, null, null),
  ('cuadros', 'Cuadros', 'Una palabra gigante, una franja de cuadros y tu horario.', 'para_todos', 16, null, null, null, null),
  ('desayunos', 'Desayunos', 'Letra de cafetería, la bebida y el pan en su plato.', 'para_todos', 17, null, null, null, null),
  ('menu-de-cafe', 'Menú de café', 'Hasta 3 productos, cada uno con su etiqueta y precio.', 'para_todos', 18, null, null, null, null),
  ('palabra-vertical', 'Palabra vertical', 'Su nombre de pie, gigante, y tu producto encima.', 'para_todos', 19, null, null, null, null),
  ('ranura', 'Ranura', 'Tu vaso en una ranura con luz.', 'para_todos', 20, null, null, null, null);


-- ─── Lo que se cuenta una sola vez ────────────────────────────────────────────

-- ¿Este día cae en las fechas de un estilo? Sin fechas, siempre. Un rango que cruza el año (del 20
-- de diciembre al 6 de enero) vale de su «desde» a fin de año y de enero a su «hasta». El 29 de
-- febrero de un año bisiesto cuenta como entre el 28 y el 1 de marzo.
create function privado.en_sus_fechas(
  p_desde_mes smallint,
  p_desde_dia smallint,
  p_hasta_mes smallint,
  p_hasta_dia smallint,
  p_dia date
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_desde_mes is null
    or case
         when p_desde_mes * 100 + p_desde_dia <= p_hasta_mes * 100 + p_hasta_dia
           then x.hoy between p_desde_mes * 100 + p_desde_dia and p_hasta_mes * 100 + p_hasta_dia
         else x.hoy >= p_desde_mes * 100 + p_desde_dia or x.hoy <= p_hasta_mes * 100 + p_hasta_dia
       end
  from (select extract(month from p_dia)::integer * 100 + extract(day from p_dia)::integer as hoy) x;
$$;

-- Los estilos que les pueden salir a los clientes en este día: prendidos, con sus 3 muestras y en
-- sus fechas. Si el Worker ya tiene su prompt lo revisa el Worker (llega con la 7b).
create function privado.estilos_a_la_vista(p_dia date)
returns setof bigint
language sql
stable
set search_path = ''
as $$
  select e.id
  from public.estilos e
  where e.prendido
    and e.muestra_post_ruta is not null
    and e.muestra_historia_ruta is not null
    and e.muestra_cartel_ruta is not null
    and privado.en_sus_fechas(e.desde_mes, e.desde_dia, e.hasta_mes, e.hasta_dia, p_dia);
$$;

revoke execute on function
  privado.clave_fija(),
  privado.en_sus_fechas(smallint, smallint, smallint, smallint, date),
  privado.estilos_a_la_vista(date)
from public, anon, authenticated, service_role;


-- ─── Lo que lee el gerente ────────────────────────────────────────────────────

-- Los estilos que Don Chuy puede elegir hoy, contado con el día de su restaurante: primero los de
-- temporada y luego los de «Para todos», cada grupo en su orden.
create function public.estilos_de_hoy(p_restaurante_id uuid)
returns table (
  id bigint,
  clave text,
  nombre text,
  descripcion text,
  grupo text,
  muestra_post_ruta text,
  muestra_historia_ruta text,
  muestra_cartel_ruta text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoy date;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede crear anuncios' using errcode = '42501';
  end if;
  select privado.dia_local(r.zona_horaria) into v_hoy
  from public.restaurantes r
  where r.id = p_restaurante_id;

  return query
  select e.id, e.clave, e.nombre, e.descripcion, e.grupo,
         e.muestra_post_ruta, e.muestra_historia_ruta, e.muestra_cartel_ruta
  from public.estilos e
  where e.id in (select privado.estilos_a_la_vista(v_hoy))
  order by case e.grupo when 'temporada' then 1 else 2 end, e.orden, e.id;
end;
$$;


-- ─── Lo que lee Fragmentless ──────────────────────────────────────────────────

-- La tabla de «Estilos», en el orden de la ventana de Don Chuy. en_fechas dice si hoy cae en sus
-- fechas, con el día de México, como panel_hoy (sin fechas, true). Lo que le falta a cada uno lo
-- junta el panel: si está apagado, qué muestra no tiene y si el Worker tiene su prompt.
create function public.panel_estilos()
returns table (
  id bigint,
  clave text,
  nombre text,
  descripcion text,
  grupo text,
  orden integer,
  desde_mes smallint,
  desde_dia smallint,
  hasta_mes smallint,
  hasta_dia smallint,
  prendido boolean,
  muestra_post_ruta text,
  muestra_historia_ruta text,
  muestra_cartel_ruta text,
  en_fechas boolean,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoy date := privado.dia_local('America/Mexico_City');
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  return query
  select e.id, e.clave, e.nombre, e.descripcion, e.grupo, e.orden,
         e.desde_mes, e.desde_dia, e.hasta_mes, e.hasta_dia, e.prendido,
         e.muestra_post_ruta, e.muestra_historia_ruta, e.muestra_cartel_ruta,
         privado.en_sus_fechas(e.desde_mes, e.desde_dia, e.hasta_mes, e.hasta_dia, v_hoy),
         e.updated_at
  from public.estilos e
  order by case e.grupo when 'temporada' then 1 else 2 end, e.orden, e.id;
end;
$$;


-- ─── Las funciones de Fragmentless ────────────────────────────────────────────
-- Lo único que cambia la tabla. Lo primero que hacen es revisar que quien llama esté en
-- plataforma_admins, y sus errores salen en español, tal cual en el panel.

-- «Agregar estilo» y «Guardar cambios» de la ventana. p_estilo_id vacío = estilo nuevo, apagado y al
-- final de su grupo; la clave solo se pone al nacer (en uno guardado, vacía o la misma). Las fechas
-- van las cuatro o ninguna, solo en «De temporada». Cada muestra es la que debe quedar: la misma,
-- una nueva que ya subió el Worker, o vacía. Si le cambias el grupo, se va al final del nuevo.
-- Regresa {id, borrar}: borrar son las muestras anteriores que cambiaron, para que la app le pida
-- al Worker borrarlas.
create function public.guardar_estilo(
  p_estilo_id bigint,
  p_clave text,
  p_nombre text,
  p_descripcion text,
  p_grupo text,
  p_desde_mes smallint,
  p_desde_dia smallint,
  p_hasta_mes smallint,
  p_hasta_dia smallint,
  p_muestra_post_ruta text,
  p_muestra_historia_ruta text,
  p_muestra_cartel_ruta text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clave text := btrim(coalesce(p_clave, ''));
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_descripcion text := btrim(coalesce(p_descripcion, ''));
  v_post text := nullif(btrim(p_muestra_post_ruta), '');
  v_historia text := nullif(btrim(p_muestra_historia_ruta), '');
  v_cartel text := nullif(btrim(p_muestra_cartel_ruta), '');
  v_antes public.estilos%rowtype;
  v_otro text;
  v_id bigint;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  if p_estilo_id is not null then
    select * into v_antes from public.estilos where id = p_estilo_id for update;
    if not found then
      raise exception 'Ese estilo ya no existe' using errcode = 'P0002';
    end if;
    if v_clave <> '' and v_clave <> v_antes.clave then
      raise exception 'La clave de un estilo ya guardado no cambia' using errcode = '22023';
    end if;
    v_clave := v_antes.clave;
  end if;

  -- Lo que pide la ventana, revisado aquí también.
  if v_nombre = '' then
    raise exception 'Escribe el nombre del estilo.' using errcode = '22023';
  end if;
  if char_length(v_nombre) > 30 then
    raise exception 'El nombre puede tener hasta 30 letras' using errcode = '22023';
  end if;
  if v_descripcion = '' then
    raise exception 'Escribe lo que dice su cuadro.' using errcode = '22023';
  end if;
  if char_length(v_descripcion) > 80 then
    raise exception 'Lo que dice su cuadro puede tener hasta 80 letras' using errcode = '22023';
  end if;
  if p_estilo_id is null and v_clave !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'La clave lleva solo letras sin acento, números y guiones: dia-de-muertos.' using errcode = '22023';
  end if;
  if char_length(v_clave) > 40 then
    raise exception 'La clave puede tener hasta 40 letras' using errcode = '22023';
  end if;
  if p_grupo is null or p_grupo not in ('temporada', 'para_todos') then
    raise exception 'El grupo es De temporada o Para todos' using errcode = '22023';
  end if;
  if num_nonnulls(p_desde_mes, p_desde_dia, p_hasta_mes, p_hasta_dia) not in (0, 4) then
    raise exception 'Las fechas llevan desde y hasta, cada una con su día y su mes' using errcode = '22023';
  end if;
  if p_desde_mes is not null and p_grupo <> 'temporada' then
    raise exception 'Solo los de temporada llevan fechas' using errcode = '22023';
  end if;
  if p_desde_mes is not null and not (
       p_desde_mes between 1 and 12
       and p_desde_dia between 1 and (array[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])[p_desde_mes]
       and p_hasta_mes between 1 and 12
       and p_hasta_dia between 1 and (array[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])[p_hasta_mes]) then
    raise exception 'Esa fecha no existe todos los años' using errcode = '22023';
  end if;

  if p_estilo_id is null then
    select clave into v_otro from public.estilos where clave = v_clave;
    if found then
      raise exception 'Ya hay un estilo con la clave %.', v_clave using errcode = '23505';
    end if;
  end if;
  select nombre into v_otro
  from public.estilos
  where lower(nombre) = lower(v_nombre) and id is distinct from p_estilo_id;
  if found then
    raise exception 'Ya hay un estilo que se llama %.', v_otro using errcode = '23505';
  end if;

  -- Las reglas de las muestras (la carpeta de su clave) son las de la tabla.
  if p_estilo_id is null then
    insert into public.estilos (
      clave, nombre, descripcion, grupo, orden, desde_mes, desde_dia, hasta_mes, hasta_dia,
      muestra_post_ruta, muestra_historia_ruta, muestra_cartel_ruta
    )
    values (
      v_clave, v_nombre, v_descripcion, p_grupo,
      coalesce((select max(orden) from public.estilos where grupo = p_grupo), 0) + 1,
      p_desde_mes, p_desde_dia, p_hasta_mes, p_hasta_dia, v_post, v_historia, v_cartel
    )
    returning id into v_id;
    return jsonb_build_object('id', v_id, 'borrar', '[]'::jsonb);
  end if;

  update public.estilos
  set nombre = v_nombre,
      descripcion = v_descripcion,
      grupo = p_grupo,
      orden = case when p_grupo = v_antes.grupo then v_antes.orden
                   else coalesce((select max(e.orden) from public.estilos e where e.grupo = p_grupo), 0) + 1 end,
      desde_mes = p_desde_mes,
      desde_dia = p_desde_dia,
      hasta_mes = p_hasta_mes,
      hasta_dia = p_hasta_dia,
      muestra_post_ruta = v_post,
      muestra_historia_ruta = v_historia,
      muestra_cartel_ruta = v_cartel
  where id = p_estilo_id;

  return jsonb_build_object('id', p_estilo_id, 'borrar', to_jsonb(array_remove(array[
    case when v_antes.muestra_post_ruta is distinct from v_post then v_antes.muestra_post_ruta end,
    case when v_antes.muestra_historia_ruta is distinct from v_historia then v_antes.muestra_historia_ruta end,
    case when v_antes.muestra_cartel_ruta is distinct from v_cartel then v_antes.muestra_cartel_ruta end
  ], null)));
end;
$$;

-- El interruptor del renglón: prende o apaga un estilo, aunque le falte algo (el panel dice qué).
create function public.prender_estilo(p_estilo_id bigint, p_prendido boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if p_prendido is null then
    raise exception 'El estilo va prendido o apagado' using errcode = '22023';
  end if;

  update public.estilos
  set prendido = p_prendido
  where id = p_estilo_id and prendido is distinct from p_prendido;
  if not found and not exists (select 1 from public.estilos where id = p_estilo_id) then
    raise exception 'Ese estilo ya no existe' using errcode = 'P0002';
  end if;
end;
$$;

-- Las flechas: sube o baja un estilo un lugar dentro de su grupo, como las categorías de Mi menú.
-- Los demás del grupo se recorren y quedan numerados 1, 2, 3…; en la orilla no pasa nada.
create function public.mover_estilo(p_estilo_id bigint, p_hacia text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grupo text;
  v_ids bigint[];
  v_aqui integer;
  v_alla integer;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  select grupo into v_grupo from public.estilos where id = p_estilo_id;
  if not found then
    raise exception 'Ese estilo ya no existe' using errcode = 'P0002';
  end if;
  if p_hacia is null or p_hacia not in ('arriba', 'abajo') then
    raise exception 'El estilo solo se mueve arriba o abajo' using errcode = '22023';
  end if;

  -- Bloquea los estilos del grupo: dos clics seguidos no se pisan.
  perform 1 from public.estilos where grupo = v_grupo for update;

  select array_agg(id order by orden, id) into v_ids
  from public.estilos
  where grupo = v_grupo;

  v_aqui := array_position(v_ids, p_estilo_id);
  v_alla := case p_hacia when 'arriba' then v_aqui - 1 else v_aqui + 1 end;
  if v_aqui is null or v_alla < 1 or v_alla > cardinality(v_ids) then
    return;
  end if;

  v_ids[v_aqui] := v_ids[v_alla];
  v_ids[v_alla] := p_estilo_id;

  update public.estilos e
  set orden = x.lugar
  from unnest(v_ids) with ordinality as x (id, lugar)
  where e.id = x.id
    and e.orden is distinct from x.lugar;
end;
$$;

-- «Eliminar estilo»: uno que nunca se usó se borra y regresa las rutas de sus muestras, para que la
-- app le pida al Worker borrarlas. Uno que ya se usó (un anuncio lo señala, desde la 7b) no se
-- borra: se apaga.
create function public.eliminar_estilo(p_estilo_id bigint)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rutas text[];
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  select array_remove(array[muestra_post_ruta, muestra_historia_ruta, muestra_cartel_ruta], null)
  into v_rutas
  from public.estilos
  where id = p_estilo_id
  for update;
  if not found then
    raise exception 'Ese estilo ya no existe' using errcode = 'P0002';
  end if;

  begin
    delete from public.estilos where id = p_estilo_id;
  exception
    when foreign_key_violation then
      raise exception 'Este estilo ya se usó: apágalo.' using errcode = '55000';
  end;
  return v_rutas;
end;
$$;


-- ─── Las preguntas del Worker ─────────────────────────────────────────────────
-- Antes de guardar o borrar una muestra en R2, el Worker le pregunta a Postgres con la sesión de
-- quien llama (libreta 3). La carpeta estilos/ solo la escribe Fragmentless.

-- ¿Puede quien llama subir una muestra a la carpeta de esta clave? Un estilo nuevo sube sus
-- muestras antes de guardarse, así que la clave todavía puede no estar en la tabla.
create function public.puedo_subir_muestra(p_clave text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select privado.soy_admin()
    and coalesce(p_clave ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(p_clave) <= 40, false);
$$;

-- ¿Puede quien llama borrar esta muestra? Solo Fragmentless, solo dentro de estilos/, y solo si
-- ningún estilo la usa en ninguno de sus tres formatos.
create function public.puedo_borrar_muestra(p_ruta text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select privado.soy_admin()
    and coalesce(p_ruta ~ '^estilos/[a-z0-9]+(-[a-z0-9]+)*/[0-9a-f]{32}\.webp$', false)
    and not exists (
      select 1 from public.estilos
      where p_ruta in (muestra_post_ruta, muestra_historia_ruta, muestra_cartel_ruta)
    );
$$;

revoke execute on function
  public.estilos_de_hoy(uuid),
  public.panel_estilos(),
  public.guardar_estilo(bigint, text, text, text, text, smallint, smallint, smallint, smallint, text, text, text),
  public.prender_estilo(bigint, boolean),
  public.mover_estilo(bigint, text),
  public.eliminar_estilo(bigint),
  public.puedo_subir_muestra(text),
  public.puedo_borrar_muestra(text)
from public, anon, service_role;

grant execute on function
  public.estilos_de_hoy(uuid),
  public.panel_estilos(),
  public.guardar_estilo(bigint, text, text, text, text, smallint, smallint, smallint, smallint, text, text, text),
  public.prender_estilo(bigint, boolean),
  public.mover_estilo(bigint, text),
  public.eliminar_estilo(bigint),
  public.puedo_subir_muestra(text),
  public.puedo_borrar_muestra(text)
to authenticated;
