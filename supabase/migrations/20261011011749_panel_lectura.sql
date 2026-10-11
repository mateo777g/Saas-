-- Lectura del panel de Fragmentless: lo que su panel cuenta (maqueta aprobada el 10
-- de octubre de 2026). La app no hace cuentas ni puede llamar nada de privado, así
-- que Postgres le entrega los números ya contados.
--
-- Son 4 funciones, una por pedazo del panel. Las 4 empiezan revisando que quien llama
-- esté en plataforma_admins, y ninguna cambia datos.


-- ─── La vigencia de cada licencia ─────────────────────────────────────────────
-- La única forma de contarla en el panel: la lista de Clientes, las 3 cifras de Inicio
-- y Vencen pronto salen de aquí. Se cuenta en la zona de cada restaurante, con la
-- misma regla que privado.mis_restaurantes: vale hasta el final de su día de fin.
--
--   pausada       licencia apagada, aunque su fecha no haya pasado
--   vencida       prendida, con su fecha de fin ya pasada
--   vence_pronto  prendida, vence hoy o en los próximos 7 días
--   vigente       prendida, vence después
--
-- dias_restantes es su fecha de fin menos hoy: 0 vence hoy, -8 venció hace 8 días,
-- vacío si no tiene fecha de fin.

create function privado.vigencias()
returns table (restaurante_id uuid, dias_restantes integer, estado text)
language sql
stable
set search_path = ''
as $$
  select r.id,
         r.licencia_fin - h.hoy,
         case
           when not r.licencia_activa then 'pausada'
           when r.licencia_fin < h.hoy then 'vencida'
           when r.licencia_fin <= h.hoy + 7 then 'vence_pronto'
           else 'vigente'
         end
  from public.restaurantes r
  cross join lateral (select privado.dia_local(r.zona_horaria) as hoy) h;
$$;

revoke execute on function privado.vigencias() from public, anon, authenticated, service_role;


-- ─── Funciones del panel ──────────────────────────────────────────────────────

-- Las 3 cifras de arriba de Inicio, en una sola fila. Cuentan restaurantes: vencidos
-- son los de licencia vencida y pausados los de licencia pausada.
create function public.panel_resumen()
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
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  return query
  select count(*)::integer,
         (count(*) filter (where v.estado in ('vigente', 'vence_pronto')))::integer,
         (count(*) filter (where v.estado = 'vence_pronto'))::integer,
         (count(*) filter (where v.estado = 'vence_pronto' and v.dias_restantes = 0))::integer,
         (count(*) filter (where v.estado in ('vencida', 'pausada')))::integer,
         (count(*) filter (where v.estado = 'vencida'))::integer,
         (count(*) filter (where v.estado = 'pausada'))::integer
  from privado.vigencias() v;
end;
$$;

-- Altas por mes: cuántos restaurantes se dieron de alta en cada uno de los últimos 6
-- meses, el actual incluido y también los meses en 0. Cuenta por el día en que se
-- creó la fila (created_at), no por su licencia_inicio, y el mes se cuenta en la hora
-- de México, donde está Fragmentless. total_6_meses va repetido en cada fila para que
-- la app no sume.
create function public.panel_altas_por_mes()
returns table (mes date, altas integer, total_6_meses integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mes_actual date := date_trunc('month', privado.dia_local('America/Mexico_City')::timestamp)::date;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  return query
  select m.inicio,
         count(r.id)::integer,
         (sum(count(r.id)) over ())::integer
  from generate_series(5, 0, -1) as g(atras)
  cross join lateral (select (v_mes_actual - make_interval(months => g.atras))::date as inicio) m
  left join public.restaurantes r
    on date_trunc('month', r.created_at at time zone 'America/Mexico_City')::date = m.inicio
  group by m.inicio
  order by m.inicio;
end;
$$;

-- La lista de Clientes: cada restaurante con su licencia, su vigencia y su
-- distribuidor (vacío = cliente directo). De aquí salen también Vencen pronto
-- (estado vencida o vence_pronto) y los clientes de la ventana de cada distribuidor.
-- Va ordenada por fecha de fin: lo que vence primero, arriba.
create function public.panel_clientes()
returns table (
  id uuid,
  nombre text,
  slug text,
  licencia_activa boolean,
  licencia_inicio date,
  licencia_fin date,
  dias_restantes integer,
  estado text,
  distribuidor_id bigint,
  distribuidor_nombre text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  return query
  select r.id, r.nombre, r.slug,
         r.licencia_activa, r.licencia_inicio, r.licencia_fin,
         v.dias_restantes, v.estado,
         r.distribuidor_id, d.nombre
  from public.restaurantes r
  join privado.vigencias() v on v.restaurante_id = r.id
  left join public.distribuidores d on d.id = r.distribuidor_id
  order by r.licencia_fin nulls last, r.nombre, r.id;
end;
$$;

-- La lista de distribuidores, con cuántos clientes tiene asignados cada uno
-- (funcionen o no) y si su cuenta ya está ligada. Primero los activos, de más a menos
-- clientes; los de baja al final.
create function public.panel_distribuidores()
returns table (
  id bigint,
  nombre text,
  telefono text,
  correo text,
  activo boolean,
  cuenta_ligada boolean,
  clientes integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  return query
  select d.id, d.nombre, d.telefono, d.correo, d.activo,
         d.usuario_id is not null,
         count(r.id)::integer
  from public.distribuidores d
  left join public.restaurantes r on r.distribuidor_id = d.id
  group by d.id
  order by d.activo desc, count(r.id) desc, d.nombre, d.id;
end;
$$;

revoke execute on function
  public.panel_resumen(),
  public.panel_altas_por_mes(),
  public.panel_clientes(),
  public.panel_distribuidores()
from public, anon, service_role;

grant execute on function
  public.panel_resumen(),
  public.panel_altas_por_mes(),
  public.panel_clientes(),
  public.panel_distribuidores()
to authenticated;
