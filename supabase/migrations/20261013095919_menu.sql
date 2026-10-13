-- Menú: categorías y productos (libreta 2, Diccionario de datos; libreta 4, lo decidido el
-- 12 y el 13 de octubre de 2026, con la maqueta del Menú CC2rrjbgxC2yykNa33a3sA).
--
-- El gerente escribe el catálogo directo en las tablas (libreta 2, Roles y permisos), solo
-- en los restaurantes donde es gerente activo y que funcionan hoy; mesero, caja y cocina lo
-- leen. Lo que nadie escribe directo: el orden (la base pone lo nuevo al final y
-- mover_categoria lo cambia), el archivado y el borrado (eliminar_producto y
-- eliminar_categoria deciden si borran o archivan).
--
-- Llegan después: las opciones (grupos_opciones, opciones y producto_grupos) con Punto de
-- venta, productos.imagen_recortada_ruta con Creación de contenido y menu_publico con el
-- menú en línea.


-- ─── ¿Dónde soy gerente? ──────────────────────────────────────────────────────
-- Restaurantes donde quien llama es gerente activo y la licencia vale hoy, como
-- mis_restaurantes pero solo con el rol de gerente. Toño, el mesero, no sale aquí.

create function privado.mis_restaurantes_gerente()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.restaurante_id
  from public.miembros m
  join public.restaurantes r on r.id = m.restaurante_id
  where m.usuario_id = (select auth.uid())
    and m.activo
    and 'gerente' = any (m.roles)
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
$$;


-- ─── categorias ───────────────────────────────────────────────────────────────
-- Las secciones del menú que crea cada restaurante (Tacos, Bebidas), cada una con uno
-- de los 28 íconos de la maqueta. Su orden es el del menú en línea, el del filtro y el
-- de la tabla del panel.

create table public.categorias (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  icono text not null
    constraint categorias_icono_lista check (icono in (
      'taco', 'hamburguesa', 'pizza', 'torta', 'alitas', 'carne', 'pescado',
      'mariscos', 'ensalada', 'sopa', 'desayuno', 'pan', 'botana', 'picante',
      'comida', 'especialidad', 'paquete', 'promocion', 'postre', 'helado', 'galleta',
      'cafe', 'refresco', 'agua', 'jugo', 'cerveza', 'vino', 'coctel'
    )),
  nombre text not null check (btrim(nombre) <> ''),
  orden integer not null,
  archivado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

-- «Tacos» y «tacos» no conviven; el nombre de una archivada se puede volver a usar.
create unique index categorias_nombre_unico
on public.categorias (restaurante_id, lower(nombre))
where archivado_at is null;

create trigger categorias_updated_at
before update on public.categorias
for each row execute function privado.set_updated_at();


-- ─── productos ────────────────────────────────────────────────────────────────
-- Lo que se vende (sustituye a platillos). Oculto (visible = false) es agotado: deja de
-- salir en el menú en línea. La foto se guarda como su ruta en R2, siempre dentro de la
-- carpeta del menú de su restaurante y con el nombre que le pone el Worker.

create table public.productos (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  categoria_id bigint not null,
  nombre text not null check (btrim(nombre) <> ''),
  descripcion text,
  precio numeric(12,2) not null check (precio >= 0),
  imagen_ruta text
    constraint productos_imagen_ruta_formato
    check (imagen_ruta ~ ('^restaurantes/' || restaurante_id::text || '/menu/[0-9a-f]{32}\.webp$')),
  visible boolean not null default true,
  orden integer not null,
  archivado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, categoria_id) references public.categorias (restaurante_id, id)
);

create index productos_categoria_idx on public.productos (restaurante_id, categoria_id);

create trigger productos_updated_at
before update on public.productos
for each row execute function privado.set_updated_at();


-- ─── Lo que la base pone sola ─────────────────────────────────────────────────

-- Los nombres se guardan sin espacios sobrantes, y una descripción en blanco queda vacía.
create function privado.limpiar_menu()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nombre := btrim(new.nombre);
  if tg_table_name = 'productos' then
    new.descripcion := nullif(btrim(new.descripcion), '');
  end if;
  return new;
end;
$$;

create trigger categorias_limpiar
before insert or update of nombre on public.categorias
for each row execute function privado.limpiar_menu();

create trigger productos_limpiar
before insert or update of nombre, descripcion on public.productos
for each row execute function privado.limpiar_menu();

-- Una categoría nueva va al final del menú.
create function privado.categoria_al_final()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.orden := coalesce(
    (select max(orden) from public.categorias where restaurante_id = new.restaurante_id), 0
  ) + 1;
  return new;
end;
$$;

create trigger categorias_al_final
before insert on public.categorias
for each row execute function privado.categoria_al_final();

-- Un producto nuevo va al final de su categoría, y uno que cambia de categoría, al final
-- de la nueva. Nunca entra en una categoría archivada.
create function privado.producto_al_final()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.categoria_id = old.categoria_id then
    return new;
  end if;

  if exists (
    select 1 from public.categorias
    where restaurante_id = new.restaurante_id
      and id = new.categoria_id
      and archivado_at is not null
  ) then
    raise exception 'Esa categoría ya no está en tu menú' using errcode = '23503';
  end if;

  new.orden := coalesce(
    (select max(orden) from public.productos
     where restaurante_id = new.restaurante_id and categoria_id = new.categoria_id), 0
  ) + 1;
  return new;
end;
$$;

create trigger productos_al_final
before insert or update of categoria_id on public.productos
for each row execute function privado.producto_al_final();

revoke execute on function
  privado.mis_restaurantes_gerente(),
  privado.limpiar_menu(),
  privado.categoria_al_final(),
  privado.producto_al_final()
from public, anon, authenticated, service_role;

grant execute on function privado.mis_restaurantes_gerente() to authenticated;


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. Todos los miembros leen; el gerente agrega y
-- cambia solo las columnas de abajo. Nadie borra directo, ni toca el orden ni el archivado.

alter table public.categorias enable row level security;
alter table public.productos enable row level security;

revoke all on table public.categorias, public.productos from anon, authenticated;
revoke all on sequence public.categorias_id_seq, public.productos_id_seq from anon, authenticated;

grant select (
  id, restaurante_id, icono, nombre, orden, archivado_at, created_at, updated_at
) on public.categorias to authenticated;
grant insert (restaurante_id, icono, nombre) on public.categorias to authenticated;
grant update (icono, nombre) on public.categorias to authenticated;

grant select (
  id, restaurante_id, categoria_id, nombre, descripcion, precio, imagen_ruta, visible, orden,
  archivado_at, created_at, updated_at
) on public.productos to authenticated;
grant insert (
  restaurante_id, categoria_id, nombre, descripcion, precio, imagen_ruta, visible
) on public.productos to authenticated;
grant update (
  categoria_id, nombre, descripcion, precio, imagen_ruta, visible
) on public.productos to authenticated;

create policy "Los miembros leen las categorías de sus restaurantes que funcionan"
on public.categorias for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "El gerente agrega categorías a sus restaurantes que funcionan"
on public.categorias for insert to authenticated
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "El gerente cambia las categorías de sus restaurantes que funcionan"
on public.categorias for update to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()) and archivado_at is null)
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "Los miembros leen los productos de sus restaurantes que funcionan"
on public.productos for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "El gerente agrega productos a sus restaurantes que funcionan"
on public.productos for insert to authenticated
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "El gerente cambia los productos de sus restaurantes que funcionan"
on public.productos for update to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()) and archivado_at is null)
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));


-- ─── Funciones del gerente ────────────────────────────────────────────────────

-- Las flechas de Categorías: sube o baja una categoría un lugar. Las demás se recorren y
-- quedan numeradas 1, 2, 3… en el orden en que se ven. En la orilla no pasa nada (la
-- flecha ya viene apagada).
create function public.mover_categoria(p_categoria_id bigint, p_hacia text)
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
  from public.categorias
  where id = p_categoria_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if p_hacia is null or p_hacia not in ('arriba', 'abajo') then
    raise exception 'La categoría solo se mueve arriba o abajo' using errcode = '22023';
  end if;

  -- Bloquea las categorías del restaurante: dos clics seguidos no se pisan.
  perform 1 from public.categorias where restaurante_id = v_restaurante_id for update;

  select array_agg(id order by orden, id) into v_ids
  from public.categorias
  where restaurante_id = v_restaurante_id and archivado_at is null;

  v_aqui := array_position(v_ids, p_categoria_id);
  v_alla := case p_hacia when 'arriba' then v_aqui - 1 else v_aqui + 1 end;
  if v_alla < 1 or v_alla > cardinality(v_ids) then
    return;
  end if;

  v_ids[v_aqui] := v_ids[v_alla];
  v_ids[v_alla] := p_categoria_id;

  update public.categorias c
  set orden = x.lugar
  from unnest(v_ids) with ordinality as x (id, lugar)
  where c.id = x.id
    and c.orden is distinct from x.lugar;
end;
$$;

-- «Eliminar producto»: si nunca se vendió, se borra y regresa la ruta de su foto para que
-- la app le pida al Worker borrarla; si ya se vendió (una venta lo señala), se archiva y su
-- foto se queda. Para Don Chuy se ve igual: deja de salir en su menú.
create function public.eliminar_producto(p_producto_id bigint)
returns table (resultado text, imagen_ruta text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ruta text;
begin
  select p.imagen_ruta into v_ruta
  from public.productos p
  where p.id = p_producto_id
    and p.archivado_at is null
    and p.restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  begin
    delete from public.productos where id = p_producto_id;
    return query select 'borrado'::text, v_ruta;
  exception
    when foreign_key_violation then
      update public.productos set archivado_at = now() where id = p_producto_id;
      return query select 'archivado'::text, null::text;
  end;
end;
$$;

-- Eliminar una categoría. Con productos no se puede: primero se mueven o se eliminan. Si
-- solo le quedan productos archivados (ya vendidos), se archiva en vez de borrarse.
create function public.eliminar_categoria(p_categoria_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_nombre text;
  v_productos integer;
begin
  select restaurante_id, nombre into v_restaurante_id, v_nombre
  from public.categorias
  where id = p_categoria_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  select count(*) into v_productos
  from public.productos
  where restaurante_id = v_restaurante_id
    and categoria_id = p_categoria_id
    and archivado_at is null;
  if v_productos = 1 then
    raise exception '% todavía tiene 1 producto; muévelo a otra categoría o elimínalo primero', v_nombre
      using errcode = '55000';
  elsif v_productos > 1 then
    raise exception '% todavía tiene % productos; muévelos a otra categoría o elimínalos primero',
      v_nombre, v_productos using errcode = '55000';
  end if;

  begin
    delete from public.categorias where id = p_categoria_id;
    return 'borrado';
  exception
    when foreign_key_violation then
      update public.categorias set archivado_at = now() where id = p_categoria_id;
      return 'archivado';
  end;
end;
$$;


-- ─── Las preguntas del Worker ─────────────────────────────────────────────────
-- El Worker nunca decide solo (libreta 3): antes de guardar o borrar una foto en R2 le
-- pregunta a Postgres, con la sesión de quien llama.

-- ¿Puede quien llama subir fotos al menú de este restaurante?
create function public.puedo_subir_foto(p_restaurante_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_restaurante_id in (select privado.mis_restaurantes_gerente()), false);
$$;

-- ¿Puede quien llama borrar esta foto? Solo si está en la carpeta del menú de un
-- restaurante donde es gerente y ningún producto la usa, ni los archivados.
create function public.puedo_borrar_foto(p_ruta text)
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
    '^restaurantes/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/menu/[0-9a-f]{32}\.webp$'
  ) then
    return false;
  end if;
  v_restaurante_id := split_part(p_ruta, '/', 2)::uuid;

  return v_restaurante_id in (select privado.mis_restaurantes_gerente())
    and not exists (
      select 1 from public.productos
      where restaurante_id = v_restaurante_id and imagen_ruta = p_ruta
    );
end;
$$;

revoke execute on function
  public.mover_categoria(bigint, text),
  public.eliminar_producto(bigint),
  public.eliminar_categoria(bigint),
  public.puedo_subir_foto(uuid),
  public.puedo_borrar_foto(text)
from public, anon, service_role;

grant execute on function
  public.mover_categoria(bigint, text),
  public.eliminar_producto(bigint),
  public.eliminar_categoria(bigint),
  public.puedo_subir_foto(uuid),
  public.puedo_borrar_foto(text)
to authenticated;
