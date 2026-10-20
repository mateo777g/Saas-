-- Menú en línea, parte 6a: el menú por slug que se lee (libreta 6, lo decidido el 20 de octubre
-- de 2026; libreta 2, Diccionario de datos; con la maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn).
--
-- «Tu restaurante» (logo, nombre, teléfono, dirección y horario) y «Tu menú en línea» (tema,
-- color, tipo de cambio y carteles) los escribe el gerente con funciones; los miembros los leen.
-- Mi menú suma sus campos en inglés. menu_publico(slug) es lo único que ejecuta quien no tiene
-- sesión: entrega lo que está a la vista de un restaurante cuya licencia funciona, con los
-- precios en dólares ya calculados aquí.
--
-- Llegan con la 6b: la pausa de los pedidos, «Hago envíos» y la tabla del pedido.


-- ─── restaurantes ─────────────────────────────────────────────────────────────
-- La página web se va: el menú en línea no es la página del restaurante. Llegan el tema, el
-- color y el tipo de cambio, y los datos de «Tu restaurante» ganan sus reglas.

alter table public.restaurantes
  drop column pagina_web,
  add column menu_tema text not null default 'claro'
    constraint restaurantes_menu_tema_lista check (menu_tema in ('claro', 'oscuro')),
  add column menu_color text
    constraint restaurantes_menu_color_formato check (menu_color ~ '^#[0-9A-F]{6}$'),
  add column tipo_cambio_usd numeric(8,2)
    constraint restaurantes_tipo_cambio_positivo check (tipo_cambio_usd > 0),
  add constraint restaurantes_nombre_largo check (char_length(nombre) <= 60),
  add constraint restaurantes_telefono_formato check (telefono ~ '^[0-9]{10}$'),
  add constraint restaurantes_direccion_formato
    check (btrim(direccion) <> '' and char_length(direccion) <= 200),
  add constraint restaurantes_logo_ruta_formato
    check (logo_ruta ~ ('^restaurantes/' || id::text || '/logo/[0-9a-f]{32}\.webp$'));

grant select (menu_tema, menu_color, tipo_cambio_usd) on public.restaurantes to authenticated;


-- ─── horarios ─────────────────────────────────────────────────────────────────
-- Un renglón por cada día que abre; un día sin renglón está cerrado. Si cierra antes de la hora
-- en que abre, cierra al día siguiente, y esas horas cuentan como del día en que abrió. Se
-- reescribe completo cada vez que el gerente guarda «Tu restaurante».

create table public.horarios (
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  dia smallint not null check (dia between 1 and 7),
  abre time not null,
  cierra time not null,
  created_at timestamptz not null default now(),
  primary key (restaurante_id, dia),
  constraint horarios_abre_distinto_de_cierra check (abre <> cierra)
);


-- ─── carteles ─────────────────────────────────────────────────────────────────
-- Las imágenes de arriba del menú, como «2x1 los martes»: hasta 5 por restaurante, en su
-- carpeta de R2. Solo se escriben con funciones: agregar_cartel cuida el máximo.

create table public.carteles (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  imagen_ruta text not null
    constraint carteles_imagen_ruta_formato
    check (imagen_ruta ~ ('^restaurantes/' || restaurante_id::text || '/carteles/[0-9a-f]{32}\.webp$')),
  orden integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

create trigger carteles_updated_at
before update on public.carteles
for each row execute function privado.set_updated_at();


-- ─── El inglés de Mi menú ─────────────────────────────────────────────────────
-- Opcional en categorías, productos, grupos y opciones; vacío = sale el de español.

alter table public.categorias
  add column nombre_en text constraint categorias_nombre_en_no_vacio check (btrim(nombre_en) <> '');
alter table public.productos
  add column nombre_en text constraint productos_nombre_en_no_vacio check (btrim(nombre_en) <> ''),
  add column descripcion_en text constraint productos_descripcion_en_no_vacia check (btrim(descripcion_en) <> '');
alter table public.grupos_opciones
  add column nombre_en text constraint grupos_opciones_nombre_en_no_vacio check (btrim(nombre_en) <> '');
alter table public.opciones
  add column nombre_en text constraint opciones_nombre_en_no_vacio check (btrim(nombre_en) <> '');

-- Los nombres se guardan sin espacios sobrantes, y un texto en blanco queda vacío; también el
-- inglés.
create or replace function privado.limpiar_menu()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nombre := btrim(new.nombre);
  if tg_table_name = 'productos' then
    new.descripcion := nullif(btrim(new.descripcion), '');
    new.descripcion_en := nullif(btrim(new.descripcion_en), '');
  end if;
  if tg_table_name in ('categorias', 'productos', 'grupos_opciones', 'opciones') then
    new.nombre_en := nullif(btrim(new.nombre_en), '');
  end if;
  return new;
end;
$$;

drop trigger categorias_limpiar on public.categorias;
create trigger categorias_limpiar
before insert or update of nombre, nombre_en on public.categorias
for each row execute function privado.limpiar_menu();

drop trigger productos_limpiar on public.productos;
create trigger productos_limpiar
before insert or update of nombre, descripcion, nombre_en, descripcion_en on public.productos
for each row execute function privado.limpiar_menu();

drop trigger grupos_opciones_limpiar on public.grupos_opciones;
create trigger grupos_opciones_limpiar
before insert or update of nombre, nombre_en on public.grupos_opciones
for each row execute function privado.limpiar_menu();

drop trigger opciones_limpiar on public.opciones;
create trigger opciones_limpiar
before insert or update of nombre, nombre_en on public.opciones
for each row execute function privado.limpiar_menu();

-- El gerente escribe las categorías directo; lo demás, con guardar_producto y guardar_grupo.
grant select (nombre_en) on public.categorias to authenticated;
grant insert (nombre_en) on public.categorias to authenticated;
grant update (nombre_en) on public.categorias to authenticated;
grant select (nombre_en, descripcion_en) on public.productos to authenticated;
grant select (nombre_en) on public.grupos_opciones to authenticated;
grant select (nombre_en) on public.opciones to authenticated;


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. Los miembros leen el horario y los carteles de sus
-- restaurantes que funcionan; nadie los escribe directo.

alter table public.horarios enable row level security;
alter table public.carteles enable row level security;

revoke all on table public.horarios, public.carteles from anon, authenticated;
revoke all on sequence public.carteles_id_seq from anon, authenticated;

grant select (restaurante_id, dia, abre, cierra, created_at) on public.horarios to authenticated;
grant select (id, restaurante_id, imagen_ruta, orden, created_at, updated_at) on public.carteles to authenticated;

create policy "Los miembros leen el horario de sus restaurantes que funcionan"
on public.horarios for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen los carteles de sus restaurantes que funcionan"
on public.carteles for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));


-- ─── Lo que se cuenta una sola vez ────────────────────────────────────────────

-- ¿Está abierto ahora? Con la hora del restaurante, nunca con la del celular. Un rango que
-- cierra después de medianoche cuenta como del día en que abrió: el sábado a la 1:00 revisa
-- el viernes. Abierto: {abierto: true, cierra: '18:00'}. Cerrado: {abierto: false, abre: {dia,
-- hora, en_dias}}, donde en_dias 0 es hoy y 1 es mañana. Sin horario: null. p_momento existe
-- para que las pruebas fijen la hora.
create function privado.horario_ahora(p_restaurante_id uuid, p_momento timestamptz default now())
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_local timestamp;
  v_dia integer;
  v_hora time;
  v_abre time;
  v_cierra time;
  v_siguiente record;
begin
  select p_momento at time zone r.zona_horaria into v_local
  from public.restaurantes r
  where r.id = p_restaurante_id;
  if v_local is null
     or not exists (select 1 from public.horarios where restaurante_id = p_restaurante_id) then
    return null;
  end if;
  v_dia := extract(isodow from v_local)::integer;
  v_hora := v_local::time;

  -- Lo de ayer que pasa de medianoche.
  select abre, cierra into v_abre, v_cierra
  from public.horarios
  where restaurante_id = p_restaurante_id and dia = case when v_dia = 1 then 7 else v_dia - 1 end;
  if found and v_cierra < v_abre and v_hora < v_cierra then
    return jsonb_build_object('abierto', true, 'cierra', to_char(v_cierra, 'FMHH24:MI'));
  end if;

  -- Lo de hoy.
  select abre, cierra into v_abre, v_cierra
  from public.horarios
  where restaurante_id = p_restaurante_id and dia = v_dia;
  if found and v_hora >= v_abre and (v_cierra < v_abre or v_hora < v_cierra) then
    return jsonb_build_object('abierto', true, 'cierra', to_char(v_cierra, 'FMHH24:MI'));
  end if;

  -- Cerrado: la siguiente vez que abre, más tarde hoy o en los días que siguen.
  select h.dia, h.abre, x.k into v_siguiente
  from generate_series(0, 7) as x (k)
  join public.horarios h
    on h.restaurante_id = p_restaurante_id and h.dia = ((v_dia - 1 + x.k) % 7) + 1
  where x.k > 0 or h.abre > v_hora
  order by x.k
  limit 1;

  return jsonb_build_object('abierto', false, 'abre', jsonb_build_object(
    'dia', v_siguiente.dia, 'hora', to_char(v_siguiente.abre, 'FMHH24:MI'), 'en_dias', v_siguiente.k));
end;
$$;

-- Los productos que el menú en línea enseña: a la vista, no archivados, de una categoría que no
-- está archivada, y sin un grupo que se quede con menos opciones a la vista de las que pide su
-- mínimo (ese producto está agotado).
create function privado.productos_a_la_vista(p_restaurante_id uuid)
returns setof bigint
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.productos p
  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
  where p.restaurante_id = p_restaurante_id
    and p.visible
    and p.archivado_at is null
    and c.archivado_at is null
    and not exists (
      select 1
      from public.producto_grupos pg
      join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
      where pg.restaurante_id = p.restaurante_id
        and pg.producto_id = p.id
        and g.minimo > (select count(*) from public.opciones o
                        where o.restaurante_id = g.restaurante_id and o.grupo_id = g.id and o.visible)
    );
$$;

revoke execute on function
  privado.horario_ahora(uuid, timestamptz),
  privado.productos_a_la_vista(uuid)
from public, anon, authenticated, service_role;


-- ─── El menú que ve la clienta ────────────────────────────────────────────────

-- La página pide el menú por su slug. Un slug que no existe y una licencia pausada o vencida
-- dan lo mismo, null: nadie puede saber qué restaurantes son clientes. Solo sale lo que está a la
-- vista (productos, opciones y categorías con algo que enseñar), en el orden del panel. Los
-- precios en dólares los calcula Postgres, al centavo; sin tipo de cambio van vacíos.
create function public.menu_publico(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r public.restaurantes;
  v_local timestamp;
begin
  select * into v_r
  from public.restaurantes r
  where r.slug = lower(btrim(p_slug))
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
  if not found then
    return null;
  end if;
  v_local := now() at time zone v_r.zona_horaria;

  return jsonb_build_object(
    'restaurante', jsonb_build_object(
      'nombre', v_r.nombre,
      'telefono', v_r.telefono,
      'direccion', v_r.direccion,
      'logo_ruta', v_r.logo_ruta,
      'tema', v_r.menu_tema,
      'color', v_r.menu_color,
      'tipo_cambio_usd', v_r.tipo_cambio_usd),
    'ahora', jsonb_build_object(
      'fecha', to_char(v_local, 'YYYY-MM-DD'),
      'dia', extract(isodow from v_local)::integer,
      'hora', to_char(v_local, 'HH24:MI')),
    'horario', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'dia', h.dia, 'abre', to_char(h.abre, 'FMHH24:MI'), 'cierra', to_char(h.cierra, 'FMHH24:MI'))
               order by h.dia), '[]')
      from public.horarios h
      where h.restaurante_id = v_r.id),
    'estado', privado.horario_ahora(v_r.id),
    'carteles', (
      select coalesce(jsonb_agg(c.imagen_ruta order by c.orden, c.id), '[]')
      from public.carteles c
      where c.restaurante_id = v_r.id),
    'categorias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'nombre', c.nombre, 'nombre_en', c.nombre_en, 'icono', c.icono,
               'productos', x.productos)
               order by c.orden, c.id), '[]')
      from public.categorias c
      cross join lateral (
        select jsonb_agg(jsonb_build_object(
                 'id', p.id,
                 'nombre', p.nombre,
                 'nombre_en', p.nombre_en,
                 'descripcion', p.descripcion,
                 'descripcion_en', p.descripcion_en,
                 'precio', p.precio,
                 'precio_usd', round(p.precio / v_r.tipo_cambio_usd, 2),
                 'imagen_ruta', p.imagen_ruta,
                 'desde', g.desde,
                 'grupos', g.grupos)
                 order by p.orden, p.id) as productos
        from public.productos p
        cross join lateral (
          -- «Desde»: un grupo obligatorio tiene alguna opción que sube el precio.
          select coalesce(bool_or(gr.minimo >= 1 and op.sube), false) as desde,
                 coalesce(jsonb_agg(jsonb_build_object(
                   'nombre', gr.nombre, 'nombre_en', gr.nombre_en,
                   'minimo', gr.minimo, 'maximo', gr.maximo, 'opciones', op.opciones)
                   order by gr.orden, gr.id), '[]') as grupos
          from public.producto_grupos pg
          join public.grupos_opciones gr on gr.restaurante_id = pg.restaurante_id and gr.id = pg.grupo_id
          cross join lateral (
            select jsonb_agg(jsonb_build_object(
                     'nombre', o.nombre, 'nombre_en', o.nombre_en,
                     'precio_extra', o.precio_extra,
                     'precio_extra_usd', round(o.precio_extra / v_r.tipo_cambio_usd, 2))
                     order by o.orden, o.id) as opciones,
                   bool_or(o.precio_extra > 0) as sube
            from public.opciones o
            where o.restaurante_id = gr.restaurante_id and o.grupo_id = gr.id and o.visible
          ) op
          where pg.restaurante_id = p.restaurante_id
            and pg.producto_id = p.id
            and op.opciones is not null
        ) g
        where p.restaurante_id = c.restaurante_id
          and p.categoria_id = c.id
          and p.id in (select privado.productos_a_la_vista(v_r.id))
      ) x
      where c.restaurante_id = v_r.id
        and c.archivado_at is null
        and x.productos is not null)
  );
end;
$$;

revoke execute on function public.menu_publico(text) from public, authenticated, service_role;
grant execute on function public.menu_publico(text) to anon;


-- ─── Funciones del gerente: «Tu restaurante» ──────────────────────────────────

-- «Guardar» de Tu restaurante: los datos y el horario, juntos. p_logo_ruta es el logo que debe
-- quedar (el mismo, uno nuevo que ya subió el Worker, o vacío para quitarlo). p_horario trae
-- {dia, abre, cierra} por cada día que abre, con las horas como '9:00'; los días que no llegan
-- quedan cerrados. Regresa la ruta del logo anterior si cambió, para que la app le pida al
-- Worker borrarla.
create function public.guardar_restaurante(
  p_restaurante_id uuid,
  p_nombre text,
  p_telefono text,
  p_direccion text,
  p_logo_ruta text,
  p_horario jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_telefono text := nullif(regexp_replace(coalesce(p_telefono, ''), '[\s().-]', '', 'g'), '');
  v_direccion text := nullif(btrim(p_direccion), '');
  v_logo text := nullif(btrim(p_logo_ruta), '');
  v_logo_antes text;
  v_dias text[] := array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  v_mal record;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar sus datos' using errcode = '42501';
  end if;

  select logo_ruta into v_logo_antes
  from public.restaurantes
  where id = p_restaurante_id
  for no key update;

  -- Lo que pide la vista, revisado aquí también.
  if v_nombre = '' then
    raise exception 'El nombre de tu restaurante es obligatorio' using errcode = '22023';
  end if;
  if char_length(v_nombre) > 60 then
    raise exception 'El nombre puede tener hasta 60 letras' using errcode = '22023';
  end if;
  if v_telefono is not null and v_telefono !~ '^[0-9]{10}$' then
    raise exception 'El teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
  end if;
  if char_length(v_direccion) > 200 then
    raise exception 'La dirección puede tener hasta 200 letras' using errcode = '22023';
  end if;

  if p_horario is null or jsonb_typeof(p_horario) <> 'array' then
    raise exception 'Falta el horario' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_horario) h
    where jsonb_typeof(h -> 'dia') <> 'number' or (h ->> 'dia') !~ '^[1-7]$'
  ) then
    raise exception 'El horario va de lunes a domingo' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_horario) h group by h ->> 'dia' having count(*) > 1
  ) then
    raise exception 'Cada día va una sola vez en tu horario' using errcode = '22023';
  end if;
  select (h ->> 'dia')::integer as dia, h ->> 'abre' as abre, h ->> 'cierra' as cierra into v_mal
  from jsonb_array_elements(p_horario) h
  where coalesce(h ->> 'abre', '') !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
     or coalesce(h ->> 'cierra', '') !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
  order by 1
  limit 1;
  if found then
    raise exception 'Revisa las horas del %', v_dias[v_mal.dia] using errcode = '22023';
  end if;
  select (h ->> 'dia')::integer as dia into v_mal
  from jsonb_array_elements(p_horario) h
  where (h ->> 'abre')::time = (h ->> 'cierra')::time
  order by 1
  limit 1;
  if found then
    raise exception 'El % abre y cierra a la misma hora', v_dias[v_mal.dia] using errcode = '22023';
  end if;

  -- Las reglas de cada columna (la carpeta del logo, por ejemplo) son las de la tabla.
  update public.restaurantes
  set nombre = v_nombre, telefono = v_telefono, direccion = v_direccion, logo_ruta = v_logo
  where id = p_restaurante_id;

  delete from public.horarios where restaurante_id = p_restaurante_id;
  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select p_restaurante_id, (h ->> 'dia')::smallint, (h ->> 'abre')::time, (h ->> 'cierra')::time
  from jsonb_array_elements(p_horario) h;

  return case when v_logo_antes is distinct from v_logo then v_logo_antes end;
end;
$$;


-- ─── Funciones del gerente: «Tu menú en línea» ────────────────────────────────

-- «Guardar» de Cómo se ve: el tema, el color (vacío = el neutro) y a cuánto toma el dólar
-- (vacío = el menú solo enseña pesos).
create function public.guardar_menu_en_linea(
  p_restaurante_id uuid,
  p_tema text,
  p_color text,
  p_tipo_cambio_usd numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_color text := upper(nullif(btrim(p_color), ''));
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if p_tema is null or p_tema not in ('claro', 'oscuro') then
    raise exception 'El menú se ve claro u oscuro' using errcode = '22023';
  end if;
  if v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'Ese color no se entiende; escríbelo como #B3261E' using errcode = '22023';
  end if;
  if round(p_tipo_cambio_usd, 2) <= 0 or round(p_tipo_cambio_usd, 2) >= 1000000 then
    raise exception 'Escribe a cuánto tomas el dólar, como 18.50' using errcode = '22023';
  end if;

  update public.restaurantes
  set menu_tema = p_tema, menu_color = v_color, tipo_cambio_usd = round(p_tipo_cambio_usd, 2)
  where id = p_restaurante_id;
end;
$$;

-- El chip de arriba de Tu menú en línea: si está abierto y cuántos productos ven tus clientes,
-- contados igual que menu_publico.
create function public.estado_menu_en_linea(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante ve su menú en línea así' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'estado', privado.horario_ahora(p_restaurante_id),
    'a_la_vista', (select count(*) from privado.productos_a_la_vista(p_restaurante_id)),
    'productos', (select count(*)
                  from public.productos p
                  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
                  where p.restaurante_id = p_restaurante_id
                    and p.archivado_at is null
                    and c.archivado_at is null));
end;
$$;

-- «Agregar cartel»: la imagen ya la subió el Worker. Va al final; con 5 ya no cabe otro.
-- Regresa el id del cartel.
create function public.agregar_cartel(p_restaurante_id uuid, p_imagen_ruta text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  -- Bloquea el restaurante: dos carteles subidos a la vez no pasan juntos de 5.
  perform 1 from public.restaurantes where id = p_restaurante_id for no key update;

  if (select count(*) from public.carteles where restaurante_id = p_restaurante_id) >= 5 then
    raise exception 'Ya tienes 5 carteles. Quita uno para agregar otro.' using errcode = '55000';
  end if;

  insert into public.carteles (restaurante_id, imagen_ruta, orden)
  values (
    p_restaurante_id,
    p_imagen_ruta,
    coalesce((select max(orden) from public.carteles where restaurante_id = p_restaurante_id), 0) + 1
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- «Cambiar imagen» de un cartel: se queda en su lugar. Regresa la ruta de la imagen anterior,
-- para que la app le pida al Worker borrarla.
create function public.cambiar_cartel(p_cartel_id bigint, p_imagen_ruta text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes text;
begin
  select imagen_ruta into v_antes
  from public.carteles
  where id = p_cartel_id
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  update public.carteles set imagen_ruta = p_imagen_ruta where id = p_cartel_id;
  return case when v_antes is distinct from p_imagen_ruta then v_antes end;
end;
$$;

-- Las flechas de Carteles: sube o baja un cartel un lugar, como las categorías.
create function public.mover_cartel(p_cartel_id bigint, p_hacia text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_ids bigint[];
  v_aqui integer;
  v_alla integer;
begin
  select restaurante_id into v_restaurante_id
  from public.carteles
  where id = p_cartel_id
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if p_hacia is null or p_hacia not in ('arriba', 'abajo') then
    raise exception 'El cartel solo se mueve arriba o abajo' using errcode = '22023';
  end if;

  -- Bloquea los carteles del restaurante: dos clics seguidos no se pisan.
  perform 1 from public.carteles where restaurante_id = v_restaurante_id for update;

  select array_agg(id order by orden, id) into v_ids
  from public.carteles
  where restaurante_id = v_restaurante_id;

  v_aqui := array_position(v_ids, p_cartel_id);
  v_alla := case p_hacia when 'arriba' then v_aqui - 1 else v_aqui + 1 end;
  if v_alla < 1 or v_alla > cardinality(v_ids) then
    return;
  end if;

  v_ids[v_aqui] := v_ids[v_alla];
  v_ids[v_alla] := p_cartel_id;

  update public.carteles c
  set orden = x.lugar
  from unnest(v_ids) with ordinality as x (id, lugar)
  where c.id = x.id
    and c.orden is distinct from x.lugar;
end;
$$;

-- «Quitar cartel»: lo borra y regresa la ruta de su imagen, que nada más usa, para que la app
-- le pida al Worker borrarla.
create function public.quitar_cartel(p_cartel_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ruta text;
begin
  delete from public.carteles
  where id = p_cartel_id
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  returning imagen_ruta into v_ruta;
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  return v_ruta;
end;
$$;


-- ─── Las preguntas del Worker ─────────────────────────────────────────────────

-- ¿Puede quien llama borrar esta imagen? Solo si está en la carpeta del menú, del logo o de los
-- carteles de un restaurante donde es gerente, y nada la usa: ningún producto (ni los
-- archivados), ni el logo, ni un cartel.
create or replace function public.puedo_borrar_foto(p_ruta text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  if p_ruta is null or p_ruta !~ (
    '^restaurantes/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(menu|logo|carteles)/[0-9a-f]{32}\.webp$'
  ) then
    return false;
  end if;
  v_restaurante_id := split_part(p_ruta, '/', 2)::uuid;

  return v_restaurante_id in (select privado.mis_restaurantes_gerente())
    and not exists (
      select 1 from public.productos
      where restaurante_id = v_restaurante_id and imagen_ruta = p_ruta
    )
    and not exists (
      select 1 from public.restaurantes
      where id = v_restaurante_id and logo_ruta = p_ruta
    )
    and not exists (
      select 1 from public.carteles
      where restaurante_id = v_restaurante_id and imagen_ruta = p_ruta
    );
end;
$$;


-- ─── Mi menú en inglés ────────────────────────────────────────────────────────
-- guardar_producto y guardar_grupo suman su inglés al final, con default: una llamada sin él
-- deja el inglés vacío.

drop function public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[]);

-- «Agregar producto» y «Guardar cambios» de la ventana del producto: el producto y sus grupos,
-- juntos. p_producto_id vacío = producto nuevo, al final de su categoría. p_imagen_ruta vacía
-- al editar = la foto se queda como estaba (la foto nueva ya la subió el Worker). Las reglas
-- de cada columna son las de la tabla: el precio, la ruta de la foto y la categoría que no
-- esté archivada. Regresa el id del producto.
create function public.guardar_producto(
  p_restaurante_id uuid,
  p_producto_id bigint,
  p_categoria_id bigint,
  p_nombre text,
  p_descripcion text,
  p_precio numeric,
  p_imagen_ruta text,
  p_grupos bigint[],
  p_nombre_en text default null,
  p_descripcion_en text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_producto_id bigint := p_producto_id;
  v_grupos bigint[] := array(select distinct x from unnest(coalesce(p_grupos, '{}')) as x where x is not null);
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if (select count(*) from public.grupos_opciones
      where restaurante_id = p_restaurante_id and id = any (v_grupos)) <> cardinality(v_grupos) then
    raise exception 'Uno de esos grupos ya no está en tu menú' using errcode = '23503';
  end if;

  if v_producto_id is null then
    insert into public.productos (
      restaurante_id, categoria_id, nombre, descripcion, precio, imagen_ruta, nombre_en, descripcion_en
    )
    values (
      p_restaurante_id, p_categoria_id, p_nombre, p_descripcion, p_precio, p_imagen_ruta,
      p_nombre_en, p_descripcion_en
    )
    returning id into v_producto_id;
  else
    update public.productos
    set categoria_id = p_categoria_id,
        nombre = p_nombre,
        descripcion = p_descripcion,
        precio = p_precio,
        imagen_ruta = coalesce(p_imagen_ruta, imagen_ruta),
        nombre_en = p_nombre_en,
        descripcion_en = p_descripcion_en
    where id = v_producto_id
      and restaurante_id = p_restaurante_id
      and archivado_at is null;
    if not found then
      raise exception 'Ese producto ya no está en tu menú' using errcode = '23503';
    end if;
  end if;

  delete from public.producto_grupos
  where restaurante_id = p_restaurante_id
    and producto_id = v_producto_id
    and grupo_id <> all (v_grupos);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id)
  select p_restaurante_id, v_producto_id, x from unnest(v_grupos) as x
  on conflict do nothing;

  return v_producto_id;
end;
$$;

drop function public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[]);

-- «Agregar grupo» y «Guardar cambios» de la ventana del grupo, todo junto: el nombre, cuántas
-- se eligen, sus opciones en su orden y los productos que lo llevan. p_grupo_id vacío = grupo
-- nuevo, que va al final. Cada opción llega como {id, nombre, nombre_en, precio_extra, visible}:
-- con id se cambia, sin id es nueva, y las que no llegan se borran. Regresa el id del grupo.
create function public.guardar_grupo(
  p_restaurante_id uuid,
  p_grupo_id bigint,
  p_nombre text,
  p_minimo integer,
  p_maximo integer,
  p_opciones jsonb,
  p_productos bigint[],
  p_nombre_en text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grupo_id bigint := p_grupo_id;
  v_opciones integer;
  v_repetida text;
  v_productos bigint[] := array(select distinct x from unnest(coalesce(p_productos, '{}')) as x where x is not null);
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if v_grupo_id is not null then
    perform 1 from public.grupos_opciones
    where id = v_grupo_id and restaurante_id = p_restaurante_id
    for update;
    if not found then
      raise exception 'Ese grupo ya no está en tu menú' using errcode = '23503';
    end if;
  end if;

  -- Lo que pide la ventana, revisado aquí también.
  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El nombre del grupo es obligatorio' using errcode = '22023';
  end if;
  if p_opciones is null or jsonb_typeof(p_opciones) <> 'array' or jsonb_array_length(p_opciones) = 0 then
    raise exception 'Agrega al menos una opción' using errcode = '22023';
  end if;
  v_opciones := jsonb_array_length(p_opciones);
  if exists (
    select 1 from jsonb_array_elements(p_opciones) o
    where coalesce(btrim(o ->> 'nombre'), '') = ''
  ) then
    raise exception 'Cada opción necesita su nombre' using errcode = '22023';
  end if;
  select min(btrim(o ->> 'nombre')) into v_repetida
  from jsonb_array_elements(p_opciones) o
  group by lower(btrim(o ->> 'nombre'))
  having count(*) > 1
  limit 1;
  if v_repetida is not null then
    raise exception 'Ya hay una opción que se llama «%» en este grupo', v_repetida using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_opciones) o
    where coalesce((o ->> 'precio_extra')::numeric, 0) < 0
  ) then
    raise exception 'El precio extra no puede ser negativo: una opción solo suma' using errcode = '22023';
  end if;
  if p_minimo is null or p_maximo is null or p_minimo < 0 or p_maximo < 1 or p_maximo < p_minimo then
    raise exception 'El máximo es por lo menos 1 y nunca menos que el mínimo' using errcode = '22023';
  end if;
  if p_maximo > v_opciones then
    raise exception 'El grupo tiene % opciones; no se pueden elegir más de %', v_opciones, v_opciones
      using errcode = '22023';
  end if;
  -- Las opciones con id son de este grupo; un grupo nuevo no trae ninguna con id.
  if exists (
    select 1 from jsonb_array_elements(p_opciones) o
    where o ->> 'id' is not null
      and not exists (
        select 1 from public.opciones op
        where op.id = (o ->> 'id')::bigint
          and op.restaurante_id = p_restaurante_id
          and op.grupo_id is not distinct from v_grupo_id
      )
  ) then
    raise exception 'Una de esas opciones ya no está en este grupo' using errcode = '23503';
  end if;
  if (select count(*) from public.productos
      where restaurante_id = p_restaurante_id and id = any (v_productos) and archivado_at is null)
     <> cardinality(v_productos) then
    raise exception 'Uno de esos productos ya no está en tu menú' using errcode = '23503';
  end if;

  -- El grupo.
  if v_grupo_id is null then
    insert into public.grupos_opciones (restaurante_id, nombre, nombre_en, minimo, maximo)
    values (p_restaurante_id, p_nombre, p_nombre_en, p_minimo, p_maximo)
    returning id into v_grupo_id;
  else
    update public.grupos_opciones
    set nombre = p_nombre, nombre_en = p_nombre_en, minimo = p_minimo, maximo = p_maximo
    where id = v_grupo_id;
  end if;

  -- Sus opciones, en el orden en que llegaron.
  delete from public.opciones op
  where op.restaurante_id = p_restaurante_id
    and op.grupo_id = v_grupo_id
    and op.id not in (
      select (o ->> 'id')::bigint from jsonb_array_elements(p_opciones) o where o ->> 'id' is not null
    );

  update public.opciones op
  set nombre = o.valor ->> 'nombre',
      nombre_en = o.valor ->> 'nombre_en',
      precio_extra = coalesce((o.valor ->> 'precio_extra')::numeric, 0),
      visible = coalesce((o.valor ->> 'visible')::boolean, true),
      orden = o.lugar
  from jsonb_array_elements(p_opciones) with ordinality as o (valor, lugar)
  where o.valor ->> 'id' is not null
    and op.id = (o.valor ->> 'id')::bigint
    and op.restaurante_id = p_restaurante_id
    and op.grupo_id = v_grupo_id;

  insert into public.opciones (restaurante_id, grupo_id, nombre, nombre_en, precio_extra, visible, orden)
  select p_restaurante_id, v_grupo_id, o.valor ->> 'nombre', o.valor ->> 'nombre_en',
         coalesce((o.valor ->> 'precio_extra')::numeric, 0),
         coalesce((o.valor ->> 'visible')::boolean, true),
         o.lugar
  from jsonb_array_elements(p_opciones) with ordinality as o (valor, lugar)
  where o.valor ->> 'id' is null;

  -- Los productos que lo llevan.
  delete from public.producto_grupos
  where restaurante_id = p_restaurante_id
    and grupo_id = v_grupo_id
    and producto_id <> all (v_productos);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id)
  select p_restaurante_id, x, v_grupo_id from unnest(v_productos) as x
  on conflict do nothing;

  return v_grupo_id;
end;
$$;


revoke execute on function
  public.guardar_restaurante(uuid, text, text, text, text, jsonb),
  public.guardar_menu_en_linea(uuid, text, text, numeric),
  public.estado_menu_en_linea(uuid),
  public.agregar_cartel(uuid, text),
  public.cambiar_cartel(bigint, text),
  public.mover_cartel(bigint, text),
  public.quitar_cartel(bigint),
  public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[], text, text),
  public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[], text)
from public, anon, service_role;

grant execute on function
  public.guardar_restaurante(uuid, text, text, text, text, jsonb),
  public.guardar_menu_en_linea(uuid, text, text, numeric),
  public.estado_menu_en_linea(uuid),
  public.agregar_cartel(uuid, text),
  public.cambiar_cartel(bigint, text),
  public.mover_cartel(bigint, text),
  public.quitar_cartel(bigint),
  public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[], text, text),
  public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[], text)
to authenticated;
