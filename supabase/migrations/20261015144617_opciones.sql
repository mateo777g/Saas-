-- Opciones y áreas (libreta 2, Diccionario de datos; libreta 5, pieza 3; lo decidido el 15 de
-- octubre de 2026 con la maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi).
--
-- Las áreas de preparación (Cocina, Barra, Parrilla) y a cuál va cada categoría; los grupos de
-- opciones (Salsa, Tamaño, Extras), sus opciones y qué productos los llevan. Todos los miembros
-- los leen: el punto de venta y la cocina los necesitan.
--
-- El gerente crea y renombra sus áreas directo en la tabla, como las mesas; eliminar_area
-- decide si la borra o la archiva. Los grupos, sus opciones y sus ligas con los productos solo
-- se escriben con funciones (guardar_grupo, guardar_producto, mover_grupo, eliminar_grupo),
-- porque cada ventana guarda varias filas de una vez y nada debe quedar a medias.
--
-- Las comandas llegan con la pieza 4: su llave hacia areas_preparacion es la que hará que
-- eliminar_area archive en vez de borrar un área que ya recibió comandas.


-- ─── areas_preparacion ────────────────────────────────────────────────────────
-- Dónde se prepara lo que se manda a cocina. Cada restaurante nace con «Cocina», que se
-- renombra y se elimina como las demás, menos la última que queda.

create table public.areas_preparacion (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null check (btrim(nombre) <> ''),
  archivado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

-- «Barra» y «barra» no conviven; el nombre de una archivada se puede volver a usar.
create unique index areas_preparacion_nombre_unico
on public.areas_preparacion (restaurante_id, lower(nombre))
where archivado_at is null;

create trigger areas_preparacion_updated_at
before update on public.areas_preparacion
for each row execute function privado.set_updated_at();

create trigger areas_preparacion_limpiar
before insert or update of nombre on public.areas_preparacion
for each row execute function privado.limpiar_menu();

-- Cada restaurante nace con «Cocina».
create function privado.nace_con_cocina()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.areas_preparacion (restaurante_id, nombre) values (new.id, 'Cocina');
  return null;
end;
$$;

create trigger restaurantes_nace_con_cocina
after insert on public.restaurantes
for each row execute function privado.nace_con_cocina();

-- Los restaurantes que ya existen también la tienen.
insert into public.areas_preparacion (restaurante_id, nombre)
select id, 'Cocina' from public.restaurantes;


-- ─── categorias.area_preparacion_id ───────────────────────────────────────────
-- A qué área llegan sus productos al mandar a cocina. Vacía = «Lo sirve el mesero». Si su
-- área se borra, una categoría archivada se queda sin área; a una que no está archivada
-- eliminar_area no la deja llegar a eso.

alter table public.categorias
  add column area_preparacion_id bigint,
  add foreign key (restaurante_id, area_preparacion_id)
    references public.areas_preparacion (restaurante_id, id)
    on delete set null (area_preparacion_id);

create index categorias_area_idx on public.categorias (restaurante_id, area_preparacion_id);

-- Las categorías que ya existen van a la Cocina de su restaurante.
update public.categorias c
set area_preparacion_id = a.id
from public.areas_preparacion a
where a.restaurante_id = c.restaurante_id;

-- Una categoría nunca apunta a un área archivada.
create function privado.area_vigente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.area_preparacion_id is not null and exists (
    select 1 from public.areas_preparacion
    where restaurante_id = new.restaurante_id
      and id = new.area_preparacion_id
      and archivado_at is not null
  ) then
    raise exception 'Esa área ya no está en tu menú' using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger categorias_area_vigente
before insert or update of area_preparacion_id on public.categorias
for each row execute function privado.area_vigente();


-- ─── grupos_opciones ──────────────────────────────────────────────────────────
-- «Salsa: Verde, Roja, Sin salsa», armado una vez y puesto en varios productos. Su orden es
-- el orden en que Pepe elige, el mismo en todos los productos que lo llevan. Que el mínimo y
-- el máximo no pasen de sus opciones lo cuida guardar_grupo, la única que lo escribe.

create table public.grupos_opciones (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null check (btrim(nombre) <> ''),
  minimo smallint not null check (minimo >= 0),
  maximo smallint not null check (maximo >= 1 and maximo >= minimo),
  orden integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

create trigger grupos_opciones_updated_at
before update on public.grupos_opciones
for each row execute function privado.set_updated_at();

create trigger grupos_opciones_limpiar
before insert or update of nombre on public.grupos_opciones
for each row execute function privado.limpiar_menu();

-- Un grupo nuevo va al final.
create function privado.grupo_al_final()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.orden := coalesce(
    (select max(orden) from public.grupos_opciones where restaurante_id = new.restaurante_id), 0
  ) + 1;
  return new;
end;
$$;

create trigger grupos_opciones_al_final
before insert on public.grupos_opciones
for each row execute function privado.grupo_al_final();


-- ─── opciones ─────────────────────────────────────────────────────────────────
-- Cada opción de un grupo, con lo que suma al precio (nunca resta). Oculta = agotada.

create table public.opciones (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  grupo_id bigint not null,
  nombre text not null check (btrim(nombre) <> ''),
  precio_extra numeric(12,2) not null default 0 check (precio_extra >= 0),
  visible boolean not null default true,
  orden integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, grupo_id)
    references public.grupos_opciones (restaurante_id, id) on delete cascade
);

-- «Verde» y «verde» no conviven en un grupo. Se revisa al terminar la transacción, para que
-- guardar_grupo pueda intercambiar los nombres de dos opciones en una sola vez.
alter table public.opciones
  add constraint opciones_nombre_unico
  exclude using btree (restaurante_id with =, grupo_id with =, lower(nombre) with =)
  deferrable initially deferred;

create trigger opciones_updated_at
before update on public.opciones
for each row execute function privado.set_updated_at();

create trigger opciones_limpiar
before insert or update of nombre on public.opciones
for each row execute function privado.limpiar_menu();


-- ─── producto_grupos ──────────────────────────────────────────────────────────
-- Qué grupos lleva cada producto. Sin orden propio: se preguntan en el de grupos_opciones.

create table public.producto_grupos (
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  producto_id bigint not null,
  grupo_id bigint not null,
  created_at timestamptz not null default now(),
  primary key (restaurante_id, producto_id, grupo_id),
  foreign key (restaurante_id, producto_id)
    references public.productos (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, grupo_id)
    references public.grupos_opciones (restaurante_id, id) on delete cascade
);

create index producto_grupos_grupo_idx on public.producto_grupos (restaurante_id, grupo_id);

revoke execute on function
  privado.nace_con_cocina(),
  privado.area_vigente(),
  privado.grupo_al_final()
from public, anon, authenticated, service_role;


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. Todos los miembros leen. El gerente agrega y
-- renombra áreas, y elige el área de cada categoría; lo demás, solo con funciones.

alter table public.areas_preparacion enable row level security;
alter table public.grupos_opciones enable row level security;
alter table public.opciones enable row level security;
alter table public.producto_grupos enable row level security;

revoke all on table
  public.areas_preparacion, public.grupos_opciones, public.opciones, public.producto_grupos
from anon, authenticated;
revoke all on sequence
  public.areas_preparacion_id_seq, public.grupos_opciones_id_seq, public.opciones_id_seq
from anon, authenticated;

grant select (
  id, restaurante_id, nombre, archivado_at, created_at, updated_at
) on public.areas_preparacion to authenticated;
grant insert (restaurante_id, nombre) on public.areas_preparacion to authenticated;
grant update (nombre) on public.areas_preparacion to authenticated;

grant select (area_preparacion_id) on public.categorias to authenticated;
grant insert (area_preparacion_id) on public.categorias to authenticated;
grant update (area_preparacion_id) on public.categorias to authenticated;

grant select (
  id, restaurante_id, nombre, minimo, maximo, orden, created_at, updated_at
) on public.grupos_opciones to authenticated;

grant select (
  id, restaurante_id, grupo_id, nombre, precio_extra, visible, orden, created_at, updated_at
) on public.opciones to authenticated;

grant select (restaurante_id, producto_id, grupo_id, created_at) on public.producto_grupos to authenticated;

create policy "Los miembros leen las áreas de sus restaurantes que funcionan"
on public.areas_preparacion for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "El gerente agrega áreas a sus restaurantes que funcionan"
on public.areas_preparacion for insert to authenticated
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "El gerente renombra las áreas de sus restaurantes que funcionan"
on public.areas_preparacion for update to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()) and archivado_at is null)
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "Los miembros leen los grupos de opciones de sus restaurantes que funcionan"
on public.grupos_opciones for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen las opciones de sus restaurantes que funcionan"
on public.opciones for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen qué grupos lleva cada producto de sus restaurantes que funcionan"
on public.producto_grupos for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));


-- ─── Funciones del gerente: áreas ─────────────────────────────────────────────

-- «Eliminar área»: no deja mientras alguna categoría vaya a ella, ni si es la última que
-- queda. Si nunca recibió comandas se borra; si ya recibió (una comanda la señala), se archiva.
-- Para Don Chuy se ve igual: deja de salir.
create function public.eliminar_area(p_area_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_nombre text;
  v_categorias integer;
begin
  select restaurante_id, nombre into v_restaurante_id, v_nombre
  from public.areas_preparacion
  where id = p_area_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  -- Bloquea las áreas del restaurante: dos ventanas no eliminan a la vez las dos últimas.
  perform 1 from public.areas_preparacion where restaurante_id = v_restaurante_id for update;

  select count(*) into v_categorias
  from public.categorias
  where restaurante_id = v_restaurante_id
    and area_preparacion_id = p_area_id
    and archivado_at is null;
  if v_categorias = 1 then
    raise exception '% todavía tiene 1 categoría; cámbiala de área primero', v_nombre
      using errcode = '55000';
  elsif v_categorias > 1 then
    raise exception '% todavía tiene % categorías; cámbialas de área primero', v_nombre, v_categorias
      using errcode = '55000';
  end if;

  if (select count(*) from public.areas_preparacion
      where restaurante_id = v_restaurante_id and archivado_at is null) = 1 then
    raise exception 'Necesitas al menos un área. Crea otra antes de eliminar «%».', v_nombre
      using errcode = '55000';
  end if;

  begin
    delete from public.areas_preparacion where id = p_area_id;
    return 'borrado';
  exception
    when foreign_key_violation then
      update public.areas_preparacion set archivado_at = now() where id = p_area_id;
      return 'archivado';
  end;
end;
$$;


-- ─── Funciones del gerente: grupos de opciones ────────────────────────────────

-- «Agregar grupo» y «Guardar cambios» de la ventana del grupo, todo junto: el nombre, cuántas
-- se eligen, sus opciones en su orden y los productos que lo llevan. p_grupo_id vacío = grupo
-- nuevo, que va al final. Cada opción llega como {id, nombre, precio_extra, visible}: con id
-- se cambia, sin id es nueva, y las que no llegan se borran. Regresa el id del grupo.
create function public.guardar_grupo(
  p_restaurante_id uuid,
  p_grupo_id bigint,
  p_nombre text,
  p_minimo integer,
  p_maximo integer,
  p_opciones jsonb,
  p_productos bigint[]
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
    insert into public.grupos_opciones (restaurante_id, nombre, minimo, maximo)
    values (p_restaurante_id, p_nombre, p_minimo, p_maximo)
    returning id into v_grupo_id;
  else
    update public.grupos_opciones
    set nombre = p_nombre, minimo = p_minimo, maximo = p_maximo
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
      precio_extra = coalesce((o.valor ->> 'precio_extra')::numeric, 0),
      visible = coalesce((o.valor ->> 'visible')::boolean, true),
      orden = o.lugar
  from jsonb_array_elements(p_opciones) with ordinality as o (valor, lugar)
  where o.valor ->> 'id' is not null
    and op.id = (o.valor ->> 'id')::bigint
    and op.restaurante_id = p_restaurante_id
    and op.grupo_id = v_grupo_id;

  insert into public.opciones (restaurante_id, grupo_id, nombre, precio_extra, visible, orden)
  select p_restaurante_id, v_grupo_id, o.valor ->> 'nombre',
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

-- Las flechas de Opciones: sube o baja un grupo un lugar. Los demás se recorren y quedan
-- numerados 1, 2, 3… en el orden en que se ven. En la orilla no pasa nada (la flecha ya viene
-- apagada).
create function public.mover_grupo(p_grupo_id bigint, p_hacia text)
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
  from public.grupos_opciones
  where id = p_grupo_id
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if p_hacia is null or p_hacia not in ('arriba', 'abajo') then
    raise exception 'El grupo solo se mueve arriba o abajo' using errcode = '22023';
  end if;

  -- Bloquea los grupos del restaurante: dos clics seguidos no se pisan.
  perform 1 from public.grupos_opciones where restaurante_id = v_restaurante_id for update;

  select array_agg(id order by orden, id) into v_ids
  from public.grupos_opciones
  where restaurante_id = v_restaurante_id;

  v_aqui := array_position(v_ids, p_grupo_id);
  v_alla := case p_hacia when 'arriba' then v_aqui - 1 else v_aqui + 1 end;
  if v_alla < 1 or v_alla > cardinality(v_ids) then
    return;
  end if;

  v_ids[v_aqui] := v_ids[v_alla];
  v_ids[v_alla] := p_grupo_id;

  update public.grupos_opciones g
  set orden = x.lugar
  from unnest(v_ids) with ordinality as x (id, lugar)
  where g.id = x.id
    and g.orden is distinct from x.lugar;
end;
$$;

-- «Eliminar grupo»: lo borra con sus opciones y lo quita de sus productos. Las ventas pasadas
-- no cambian: cada renglón guarda su copia de lo que se eligió.
create function public.eliminar_grupo(p_grupo_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.grupos_opciones
  where id = p_grupo_id
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
end;
$$;


-- ─── Funciones del gerente: el producto con sus grupos ────────────────────────

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
  p_grupos bigint[]
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
    insert into public.productos (restaurante_id, categoria_id, nombre, descripcion, precio, imagen_ruta)
    values (p_restaurante_id, p_categoria_id, p_nombre, p_descripcion, p_precio, p_imagen_ruta)
    returning id into v_producto_id;
  else
    update public.productos
    set categoria_id = p_categoria_id,
        nombre = p_nombre,
        descripcion = p_descripcion,
        precio = p_precio,
        imagen_ruta = coalesce(p_imagen_ruta, imagen_ruta)
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

revoke execute on function
  public.eliminar_area(bigint),
  public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[]),
  public.mover_grupo(bigint, text),
  public.eliminar_grupo(bigint),
  public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[])
from public, anon, service_role;

grant execute on function
  public.eliminar_area(bigint),
  public.guardar_grupo(uuid, bigint, text, integer, integer, jsonb, bigint[]),
  public.mover_grupo(bigint, text),
  public.eliminar_grupo(bigint),
  public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[])
to authenticated;
