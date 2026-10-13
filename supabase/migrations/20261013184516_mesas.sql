-- Mesas: el catálogo de mesas de cada restaurante (libreta 2, Diccionario de datos; libreta 5,
-- pieza 1; lo decidido el 13 de octubre de 2026 con la maqueta de Mesas 4TKmJzMwyWMCAVU2MwEDwc).
--
-- El gerente agrega y renombra directo en la tabla, solo en los restaurantes donde es gerente
-- activo y que funcionan hoy; mesero, caja y cocina las leen. Lo que nadie escribe directo: el
-- orden (la base pone la nueva al final y mover_mesa lo cambia), el archivado y el borrado
-- (eliminar_mesa decide si borra o archiva).
--
-- Las cuentas llegan con la pieza 4: la llave de ventas hacia mesas es la que hará que
-- eliminar_mesa archive en vez de borrar una mesa que ya tuvo cuentas.


-- ─── mesas ────────────────────────────────────────────────────────────────────
-- «Mesa 1», «Barra», «Terraza 2». Su orden es el de la tabla del panel y el de las tarjetas
-- en el punto de venta.

create table public.mesas (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null check (btrim(nombre) <> ''),
  orden integer not null,
  archivado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

-- «Mesa 1» y «mesa 1» no conviven; el nombre de una archivada se puede volver a usar.
create unique index mesas_nombre_unico
on public.mesas (restaurante_id, lower(nombre))
where archivado_at is null;

create trigger mesas_updated_at
before update on public.mesas
for each row execute function privado.set_updated_at();

-- El nombre se guarda sin espacios sobrantes, con la misma limpieza que el menú.
create trigger mesas_limpiar
before insert or update of nombre on public.mesas
for each row execute function privado.limpiar_menu();

-- Una mesa nueva va al final.
create function privado.mesa_al_final()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.orden := coalesce(
    (select max(orden) from public.mesas where restaurante_id = new.restaurante_id), 0
  ) + 1;
  return new;
end;
$$;

create trigger mesas_al_final
before insert on public.mesas
for each row execute function privado.mesa_al_final();

revoke execute on function privado.mesa_al_final()
from public, anon, authenticated, service_role;


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. Todos los miembros leen; el gerente agrega y
-- renombra. Nadie borra directo, ni toca el orden ni el archivado.

alter table public.mesas enable row level security;

revoke all on table public.mesas from anon, authenticated;
revoke all on sequence public.mesas_id_seq from anon, authenticated;

grant select (
  id, restaurante_id, nombre, orden, archivado_at, created_at, updated_at
) on public.mesas to authenticated;
grant insert (restaurante_id, nombre) on public.mesas to authenticated;
grant update (nombre) on public.mesas to authenticated;

create policy "Los miembros leen las mesas de sus restaurantes que funcionan"
on public.mesas for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "El gerente agrega mesas a sus restaurantes que funcionan"
on public.mesas for insert to authenticated
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "El gerente renombra las mesas de sus restaurantes que funcionan"
on public.mesas for update to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()) and archivado_at is null)
with check (restaurante_id in (select privado.mis_restaurantes_gerente()));


-- ─── Funciones del gerente ────────────────────────────────────────────────────

-- Las flechas: sube o baja una mesa un lugar. Las demás se recorren y quedan numeradas 1, 2,
-- 3… en el orden en que se ven. En la orilla no pasa nada (la flecha ya viene apagada).
create function public.mover_mesa(p_mesa_id bigint, p_hacia text)
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
  from public.mesas
  where id = p_mesa_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar sus mesas' using errcode = '42501';
  end if;
  if p_hacia is null or p_hacia not in ('arriba', 'abajo') then
    raise exception 'La mesa solo se mueve arriba o abajo' using errcode = '22023';
  end if;

  -- Bloquea las mesas del restaurante: dos clics seguidos no se pisan.
  perform 1 from public.mesas where restaurante_id = v_restaurante_id for update;

  select array_agg(id order by orden, id) into v_ids
  from public.mesas
  where restaurante_id = v_restaurante_id and archivado_at is null;

  v_aqui := array_position(v_ids, p_mesa_id);
  v_alla := case p_hacia when 'arriba' then v_aqui - 1 else v_aqui + 1 end;
  if v_alla < 1 or v_alla > cardinality(v_ids) then
    return;
  end if;

  v_ids[v_aqui] := v_ids[v_alla];
  v_ids[v_alla] := p_mesa_id;

  update public.mesas m
  set orden = x.lugar
  from unnest(v_ids) with ordinality as x (id, lugar)
  where m.id = x.id
    and m.orden is distinct from x.lugar;
end;
$$;

-- «Eliminar mesa»: si nunca tuvo cuentas, se borra; si ya tuvo (una cuenta la señala), se
-- archiva y sus cuentas siguen en los reportes. Para Don Chuy se ve igual: deja de salir.
create function public.eliminar_mesa(p_mesa_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.mesas
  where id = p_mesa_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar sus mesas' using errcode = '42501';
  end if;

  begin
    delete from public.mesas where id = p_mesa_id;
    return 'borrado';
  exception
    when foreign_key_violation then
      update public.mesas set archivado_at = now() where id = p_mesa_id;
      return 'archivado';
  end;
end;
$$;

revoke execute on function
  public.mover_mesa(bigint, text),
  public.eliminar_mesa(bigint)
from public, anon, service_role;

grant execute on function
  public.mover_mesa(bigint, text),
  public.eliminar_mesa(bigint)
to authenticated;
