-- Cortes y reportes: la pieza 5 del punto de venta (libreta 5; libreta 4; decidido el 18 de octubre
-- de 2026; libreta 2, Diccionario de datos, rev 88; maqueta 7J6LvYWiktRnGxNugbuaoe).
--
-- No crea tablas: lee lo que dejaron las partes 4a, 4b y 4c. Para el panel del gerente trae:
-- mesas_ahora (cada mesa con su cuenta abierta y lo que falta por cobrar, para Mesas ahora en
-- Inicio y las columnas de Mesas), tus_meseros (lo que trae abierto cada quien y lo que vendió
-- hoy) y reporte_del_dia (Cortes y reportes: el corte de cada turno que se abrió ese día, y los
-- descuentos, las cancelaciones y los otros cambios de las cuentas de ese día). También deja
-- cambiar la hora de corte (fijar_hora_corte), que queda en la bitácora.
--
-- Una sola forma de contar: una cuenta es del día de negocio en que se abrió (created_at), con la
-- hora de corte que tenga el restaurante al leer; cambiarla reacomoda los días pasados. Solo las
-- cerradas son venta. Lo cancelado no suma. El dinero por renglón ya resta su descuento; el de
-- toda la cuenta solo cuenta por cuenta. Las propinas no son venta. Las sumas las hace Postgres.
-- Las cuatro cifras de Inicio llegan con el agente.


-- ─── bitacora: la hora de corte ───────────────────────────────────────────────

alter table public.bitacora drop constraint bitacora_accion_valida;
alter table public.bitacora add constraint bitacora_accion_valida
  check (accion in ('cambiar_mesa', 'juntar_mesas', 'retiro', 'ingreso', 'cancelar_renglon',
                    'cancelar_cuenta', 'cancelar_pago', 'descontar', 'quitar_descuento',
                    'cambiar_hora_corte'));


-- ─── El día de negocio ────────────────────────────────────────────────────────
-- El momento en que empieza el día de negocio p_dia: su hora de corte, en la zona del restaurante.
-- Es la misma cuenta que privado.dia_de_negocio al revés: una cuenta abierta en
-- [inicio_de_dia(d), inicio_de_dia(d + 1)) es del día d. Así los reportes usan el índice de fecha.

create function privado.inicio_de_dia(p_zona text, p_hora_corte smallint, p_dia date)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (p_dia + make_interval(hours => p_hora_corte)) at time zone p_zona;
$$;

-- Las cuentas de un restaurante que se abrieron del día p_desde al p_hasta, en cualquier estado.
-- Es la manera única de decir de qué día es una cuenta; la usan Tus meseros y los reportes, y la
-- usará el agente.

create function privado.cuentas_del_dia(p_restaurante_id uuid, p_desde date, p_hasta date)
returns setof public.ventas
language sql
stable
set search_path = ''
as $$
  select v.*
  from public.restaurantes r
  join public.ventas v on v.restaurante_id = r.id
  where r.id = p_restaurante_id
    and v.created_at >= privado.inicio_de_dia(r.zona_horaria, r.hora_corte, p_desde)
    and v.created_at < privado.inicio_de_dia(r.zona_horaria, r.hora_corte, p_hasta + 1);
$$;

-- Las cuentas de un día, en cualquier estado, para los reportes.
create index ventas_por_fecha on public.ventas (restaurante_id, created_at);

revoke execute on function
  privado.inicio_de_dia(text, smallint, date),
  privado.cuentas_del_dia(uuid, date, date)
from public, anon, authenticated, service_role;


-- ─── La hora de corte ─────────────────────────────────────────────────────────
-- El gerente la cambia en Ajustes. Queda en la bitácora con la de antes y la nueva, porque mueve
-- los días pasados. Si no cambia, no se anota nada.

create function public.fijar_hora_corte(p_restaurante_id uuid, p_hora integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_antes smallint;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['gerente']);
  if v_miembro is null then
    raise exception 'Solo los gerentes de este restaurante cambian la hora de corte' using errcode = '42501';
  end if;
  if p_hora is null or p_hora not between 0 and 23 then
    raise exception 'La hora de corte va de 0 a 23' using errcode = '22023';
  end if;

  select hora_corte into v_antes from public.restaurantes where id = p_restaurante_id for update;
  if v_antes = p_hora then
    return;
  end if;
  update public.restaurantes set hora_corte = p_hora where id = p_restaurante_id;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (p_restaurante_id, v_miembro, 'cambiar_hora_corte', 'restaurantes', p_restaurante_id::text,
          jsonb_build_object('de', v_antes, 'a', p_hora));
end;
$$;


-- ─── Mesas ahora ──────────────────────────────────────────────────────────────
-- Las mesas del restaurante en su orden, cada una con su cuenta abierta si la tiene (una reabierta
-- ya no ocupa su mesa), cuántas están ocupadas y lo que falta por cobrar en ellas: el total menos
-- lo pagado. Para Mesas ahora en Inicio y las columnas Estado, Abierta y Cuenta de Mesas.

create function public.mesas_ahora(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_zona text;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante ven sus mesas así' using errcode = '42501';
  end if;
  select zona_horaria into v_zona from public.restaurantes where id = p_restaurante_id;

  return (
    with m as (
      select me.id, me.nombre, me.orden, v.id as venta_id, v.total, v.pagado, v.created_at as abierta_at
      from public.mesas me
      left join public.ventas v
        on v.restaurante_id = me.restaurante_id and v.mesa_id = me.id
       and v.estado = 'abierta' and v.folio is null
      where me.restaurante_id = p_restaurante_id and me.archivado_at is null
    )
    select jsonb_build_object(
      'hora', to_char(now() at time zone v_zona, 'HH24:MI'),
      'mesas', coalesce(jsonb_agg(jsonb_build_object(
                 'id', m.id, 'nombre', m.nombre, 'venta_id', m.venta_id, 'total', m.total,
                 'abierta_at', m.abierta_at)
                 order by m.orden, m.id), '[]'),
      'ocupadas', count(m.venta_id),
      'por_cobrar', coalesce(sum(m.total - m.pagado), 0)::numeric(12,2)
    )
    from m
  );
end;
$$;


-- ─── Tus meseros ──────────────────────────────────────────────────────────────
-- Quien tiene el rol de mesero y sigue activo, aunque hoy vaya en $0, y cualquiera que hoy cerró
-- cuentas o trae una abierta (Lupita con un para llevar, el gerente desde Accesos). De cada quien:
-- las cuentas que trae abiertas ahora, las cerradas de hoy y lo vendido en ellas. Cada cuenta es de
-- quien la abrió. Arriba, cuántos activos hay en cada rol del equipo.

create function public.tus_meseros(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_zona text;
  v_corte smallint;
  v_hoy date;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante ven a su equipo así' using errcode = '42501';
  end if;
  select zona_horaria, hora_corte into v_zona, v_corte from public.restaurantes where id = p_restaurante_id;
  v_hoy := privado.dia_de_negocio(v_zona, v_corte);

  return (
    with cerradas as (
      select c.abierta_por, count(*) as ventas, sum(c.total) as vendido
      from privado.cuentas_del_dia(p_restaurante_id, v_hoy, v_hoy) c
      where c.estado = 'cerrada' and c.abierta_por is not null
      group by c.abierta_por
    ),
    abiertas as (
      select v.abierta_por, count(*) as abiertas
      from public.ventas v
      where v.restaurante_id = p_restaurante_id and v.estado = 'abierta' and v.abierta_por is not null
      group by v.abierta_por
    ),
    gente as (
      select m.id, m.nombre, m.roles, coalesce(a.abiertas, 0) as abiertas, coalesce(c.ventas, 0) as ventas,
             coalesce(c.vendido, 0)::numeric(12,2) as vendido
      from public.miembros m
      left join cerradas c on c.abierta_por = m.id
      left join abiertas a on a.abierta_por = m.id
      where m.restaurante_id = p_restaurante_id
        and ((m.activo and 'mesero' = any (m.roles)) or c.abierta_por is not null or a.abierta_por is not null)
    )
    select jsonb_build_object(
      'hoy', v_hoy,
      'hora', to_char(now() at time zone v_zona, 'HH24:MI'),
      'equipo', (select jsonb_build_object(
                   'meseros', count(*) filter (where 'mesero' = any (e.roles)),
                   'caja', count(*) filter (where 'caja' = any (e.roles)),
                   'cocina', count(*) filter (where 'cocina' = any (e.roles)))
                 from public.miembros e
                 where e.restaurante_id = p_restaurante_id and e.activo),
      'personas', coalesce((select jsonb_agg(jsonb_build_object(
                     'miembro_id', g.id, 'nombre', g.nombre, 'roles', to_jsonb(g.roles),
                     'abiertas', g.abiertas, 'ventas', g.ventas, 'vendido', g.vendido)
                     order by g.vendido desc, g.nombre, g.id)
                   from gente g), '[]')
    )
  );
end;
$$;


-- ─── Cortes y reportes ────────────────────────────────────────────────────────
-- Todo lo de un día de negocio (hoy si no se dice cuál), para el gerente:
--   turnos: cada turno que se abrió ese día, con su corte (resumen_turno: con la caja abierta no
--     trae lo esperado), sus entradas y salidas y sus pagos cancelados, que son dinero del cajón.
--   descuentos: los de las cuentas cerradas de ese día, con su monto final, por renglón (los
--     activos) y por cuenta, con quién lo pidió y quién lo autorizó (lo último de la bitácora).
--   cancelaciones: los renglones cancelados de las cuentas de ese día (en cualquier estado) y las
--     cuentas canceladas con motivo y PIN, por lo que valían al cancelarlas. Los renglones que se
--     cancelaron con su cuenta van dentro de ella, y una cuenta que se juntó con otra no es una
--     cancelación: sale en otros.
--   otros: los cambios de mesa, las juntas y los descuentos quitados de esas cuentas, y los cambios
--     de la hora de corte de ese día.

create function public.reporte_del_dia(p_restaurante_id uuid, p_dia date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_zona text;
  v_corte smallint;
  v_hoy date;
  v_dia date;
  v_desde timestamptz;
  v_hasta timestamptz;
  v_turnos jsonb;
  v_descuentos jsonb;
  v_cancelaciones jsonb;
  v_otros jsonb;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante ven los cortes y reportes' using errcode = '42501';
  end if;
  select zona_horaria, hora_corte into v_zona, v_corte from public.restaurantes where id = p_restaurante_id;
  v_hoy := privado.dia_de_negocio(v_zona, v_corte);
  v_dia := coalesce(p_dia, v_hoy);
  if v_dia > v_hoy then
    raise exception 'Ese día todavía no llega' using errcode = '22023';
  end if;
  v_desde := privado.inicio_de_dia(v_zona, v_corte, v_dia);
  v_hasta := privado.inicio_de_dia(v_zona, v_corte, v_dia + 1);

  select coalesce(jsonb_agg(public.resumen_turno(t.id) || jsonb_build_object(
           'movimientos', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'tipo', mc.tipo, 'monto', mc.monto, 'motivo', mc.motivo, 'registrado_por', q.nombre,
                      'created_at', mc.created_at)
                      order by mc.created_at, mc.id)
             from public.movimientos_caja mc
             join public.miembros q on q.restaurante_id = mc.restaurante_id and q.id = mc.registrado_por
             where mc.restaurante_id = t.restaurante_id and mc.turno_id = t.id), '[]'),
           'pagos_cancelados', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'pago_id', p.id, 'folio', v.folio, 'cuenta', coalesce(v.mesa_nombre, v.cliente_nombre),
                      'metodo', p.metodo, 'monto', p.monto, 'propina', p.propina, 'motivo', p.cancelado_motivo,
                      'pidio_id', p.cancelado_por, 'pidio', q.nombre, 'autorizo_id', p.autorizado_por,
                      'autorizo', au.nombre, 'cancelado_at', p.cancelado_at)
                      order by p.cancelado_at, p.id)
             from public.pagos p
             join public.ventas v on v.restaurante_id = p.restaurante_id and v.id = p.venta_id
             join public.miembros q on q.restaurante_id = p.restaurante_id and q.id = p.cancelado_por
             left join public.miembros au on au.restaurante_id = p.restaurante_id and au.id = p.autorizado_por
             where p.restaurante_id = t.restaurante_id and p.turno_id = t.id and p.cancelado_at is not null), '[]'))
           order by t.created_at, t.id), '[]')
  into v_turnos
  from public.turnos t
  where t.restaurante_id = p_restaurante_id and t.created_at >= v_desde and t.created_at < v_hasta;

  with dia as (
    select * from privado.cuentas_del_dia(p_restaurante_id, v_dia, v_dia)
  ),
  d as (
    select v.id as venta_id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre) as cuenta,
           i.id as renglon_id, i.nombre, i.cantidad, i.descuento_tipo, i.descuento_valor, i.descuento,
           i.descuento_motivo, 'venta_items' as tabla, i.id::text as registro
    from dia v
    join public.venta_items i on i.restaurante_id = v.restaurante_id and i.venta_id = v.id
    where v.estado = 'cerrada' and i.estado = 'activo' and i.descuento > 0
    union all
    select v.id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre), null, null, null,
           v.descuento_tipo, v.descuento_valor, v.descuento, v.descuento_motivo, 'ventas', v.id::text
    from dia v
    where v.estado = 'cerrada' and v.descuento > 0
  )
  select jsonb_build_object(
    'total', coalesce(sum(d.descuento), 0)::numeric(12,2),
    'cuentas', count(distinct d.venta_id),
    'lista', coalesce(jsonb_agg(jsonb_build_object(
               'venta_id', d.venta_id, 'folio', d.folio, 'tipo', d.tipo, 'cuenta', d.cuenta,
               'renglon_id', d.renglon_id, 'nombre', d.nombre, 'cantidad', d.cantidad,
               'descuento_tipo', d.descuento_tipo, 'descuento_valor', d.descuento_valor,
               'descuento', d.descuento, 'motivo', d.descuento_motivo,
               'pidio_id', b.miembro_id, 'pidio', q.nombre, 'autorizo_id', b.autorizado_por,
               'autorizo', au.nombre, 'created_at', b.created_at)
               order by b.created_at nulls last, d.venta_id, d.renglon_id nulls first), '[]')
  )
  into v_descuentos
  from d
  left join lateral (
    select b.miembro_id, b.autorizado_por, b.created_at
    from public.bitacora b
    where b.restaurante_id = p_restaurante_id and b.accion = 'descontar'
      and b.tabla = d.tabla and b.registro_id = d.registro
    order by b.created_at desc, b.id desc
    limit 1
  ) b on true
  left join public.miembros q on q.restaurante_id = p_restaurante_id and q.id = b.miembro_id
  left join public.miembros au on au.restaurante_id = p_restaurante_id and au.id = b.autorizado_por;

  with dia as (
    select * from privado.cuentas_del_dia(p_restaurante_id, v_dia, v_dia)
  ),
  cuentas as (
    select v.id as venta_id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre) as cuenta,
           (b.detalle ->> 'total')::numeric(12,2) as importe, b.detalle ->> 'motivo' as motivo,
           b.miembro_id, b.autorizado_por, b.created_at
    from dia v
    join public.bitacora b
      on b.restaurante_id = v.restaurante_id and b.accion = 'cancelar_cuenta'
     and b.tabla = 'ventas' and b.registro_id = v.id::text
    where v.estado = 'cancelada'
  ),
  c as (
    select 'cuenta' as que, x.venta_id, x.folio, x.tipo, x.cuenta, 'cancelada' as estado, null::bigint as renglon_id,
           null::text as nombre, null::integer as cantidad, x.importe, x.motivo, x.miembro_id,
           x.autorizado_por, x.created_at
    from cuentas x
    union all
    select 'renglon', v.id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre), v.estado, i.id,
           i.nombre, i.cantidad, i.importe, i.cancelado_motivo, i.cancelado_por, i.autorizado_por, i.cancelado_at
    from dia v
    join public.venta_items i on i.restaurante_id = v.restaurante_id and i.venta_id = v.id
    where i.estado = 'cancelado'
      and not exists (select 1 from cuentas x where x.venta_id = v.id and x.created_at = i.cancelado_at)
  )
  select jsonb_build_object(
    'total', coalesce(sum(c.importe), 0)::numeric(12,2),
    'renglones', count(*) filter (where c.que = 'renglon'),
    'cuentas', count(*) filter (where c.que = 'cuenta'),
    'lista', coalesce(jsonb_agg(jsonb_build_object(
               'que', c.que, 'venta_id', c.venta_id, 'folio', c.folio, 'tipo', c.tipo, 'cuenta', c.cuenta,
               'estado', c.estado, 'renglon_id', c.renglon_id, 'nombre', c.nombre, 'cantidad', c.cantidad,
               'importe', c.importe, 'motivo', c.motivo, 'pidio_id', c.miembro_id, 'pidio', q.nombre,
               'autorizo_id', c.autorizado_por, 'autorizo', au.nombre, 'created_at', c.created_at)
               order by c.created_at, c.venta_id, c.renglon_id nulls first), '[]')
  )
  into v_cancelaciones
  from c
  left join public.miembros q on q.restaurante_id = p_restaurante_id and q.id = c.miembro_id
  left join public.miembros au on au.restaurante_id = p_restaurante_id and au.id = c.autorizado_por;

  select coalesce(jsonb_agg(jsonb_build_object(
           'accion', b.accion, 'detalle', b.detalle, 'quien', q.nombre, 'created_at', b.created_at)
           order by b.created_at, b.id), '[]')
  into v_otros
  from public.bitacora b
  left join public.miembros q on q.restaurante_id = b.restaurante_id and q.id = b.miembro_id
  where b.restaurante_id = p_restaurante_id
    and ((b.accion in ('cambiar_mesa', 'juntar_mesas', 'quitar_descuento')
          and coalesce((b.detalle ->> 'venta_id')::bigint,
                       case when b.tabla = 'ventas' then b.registro_id::bigint end)
              in (select x.id from privado.cuentas_del_dia(p_restaurante_id, v_dia, v_dia) x))
      or (b.accion = 'cambiar_hora_corte' and b.created_at >= v_desde and b.created_at < v_hasta));

  return jsonb_build_object(
    'dia', v_dia,
    'hoy', v_hoy,
    'zona', v_zona,
    'hora_corte', v_corte,
    'turnos', v_turnos,
    'descuentos', v_descuentos,
    'cancelaciones', v_cancelaciones,
    'otros', v_otros
  );
end;
$$;


revoke execute on function
  public.fijar_hora_corte(uuid, integer),
  public.mesas_ahora(uuid),
  public.tus_meseros(uuid),
  public.reporte_del_dia(uuid, date)
from public, anon, service_role;

grant execute on function
  public.fijar_hora_corte(uuid, integer),
  public.mesas_ahora(uuid),
  public.tus_meseros(uuid),
  public.reporte_del_dia(uuid, date)
to authenticated;
