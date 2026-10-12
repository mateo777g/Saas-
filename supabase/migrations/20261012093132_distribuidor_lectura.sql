-- Lectura del panel del distribuidor (libreta 8, «Qué se construye primero»; maqueta
-- aprobada el 12 de octubre de 2026). Juanito ve a sus clientes como la lista de Clientes
-- de Fragmentless, solo para leer: si funcionan y su fecha de fin, sin ventas ni
-- gerentes. La app no hace cuentas, así que Postgres le entrega todo ya contado, con
-- privado.vigencias, la misma regla del panel de Fragmentless.
--
-- Son 2 funciones y no cambian datos. Solo le responden a una cuenta ligada a un
-- distribuidor activo: si está de baja no le dan nada, ni llamándolas directo. Su nombre
-- y si está de baja la app los lee de su fila en distribuidores, que su RLS ya le deja
-- leer; la tabla restaurantes no la puede leer directo.


-- ─── El distribuidor de quien llama ───────────────────────────────────────────
-- El id del distribuidor activo ligado a la cuenta de la sesión; vacío si la cuenta no
-- es de un distribuidor o si está de baja. Solo la usan las funciones de abajo.

create function privado.mi_distribuidor()
returns bigint
language sql
stable
set search_path = ''
as $$
  select id
  from public.distribuidores
  where usuario_id = (select auth.uid())
    and activo;
$$;

revoke execute on function privado.mi_distribuidor() from public, anon, authenticated, service_role;


-- ─── Funciones del distribuidor ───────────────────────────────────────────────

-- Las 3 cifras de arriba de su Inicio, en una sola fila: las mismas de panel_resumen,
-- pero solo con sus clientes. Sin clientes, todo en 0.
create function public.distribuidor_resumen()
returns table (
  total integer,
  funcionan integer,
  vencen_pronto integer,
  vencen_hoy integer,
  sin_funcionar integer,
  vencidos integer,
  pausados integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_distribuidor bigint := privado.mi_distribuidor();
begin
  if v_distribuidor is null then
    raise exception 'Solo un distribuidor activo puede ver esto' using errcode = '42501';
  end if;

  return query
  select count(*)::integer,
         (count(*) filter (where v.estado in ('vigente', 'vence_pronto')))::integer,
         (count(*) filter (where v.estado = 'vence_pronto'))::integer,
         (count(*) filter (where v.estado = 'vence_pronto' and v.dias_restantes = 0))::integer,
         (count(*) filter (where v.estado in ('vencida', 'pausada')))::integer,
         (count(*) filter (where v.estado = 'vencida'))::integer,
         (count(*) filter (where v.estado = 'pausada'))::integer
  from public.restaurantes r
  join privado.vigencias() v on v.restaurante_id = r.id
  where r.distribuidor_id = v_distribuidor;
end;
$$;

-- Sus clientes: cada restaurante que Fragmentless le asignó, con su licencia y su
-- vigencia. De aquí salen Tus clientes, Vencen pronto (estado vencida o vence_pronto) y
-- su vista Clientes. Va ordenada por fecha de fin, como la de Fragmentless.
create function public.distribuidor_clientes()
returns table (
  id uuid,
  nombre text,
  slug text,
  licencia_activa boolean,
  licencia_inicio date,
  licencia_fin date,
  dias_restantes integer,
  estado text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_distribuidor bigint := privado.mi_distribuidor();
begin
  if v_distribuidor is null then
    raise exception 'Solo un distribuidor activo puede ver esto' using errcode = '42501';
  end if;

  return query
  select r.id, r.nombre, r.slug,
         r.licencia_activa, r.licencia_inicio, r.licencia_fin,
         v.dias_restantes, v.estado
  from public.restaurantes r
  join privado.vigencias() v on v.restaurante_id = r.id
  where r.distribuidor_id = v_distribuidor
  order by r.licencia_fin nulls last, r.nombre, r.id;
end;
$$;

revoke execute on function
  public.distribuidor_resumen(),
  public.distribuidor_clientes()
from public, anon, service_role;

grant execute on function
  public.distribuidor_resumen(),
  public.distribuidor_clientes()
to authenticated;
