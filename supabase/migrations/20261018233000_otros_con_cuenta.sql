-- Otros cambios con su cuenta (pieza 5; maqueta Cortes y reportes 7J6LvYWiktRnGxNugbuaoe). La
-- bitácora de «quitar descuento» guarda el renglón pero no la cuenta, y Cortes y reportes dice
-- «Quitó el descuento de Mesa 1»: reporte_del_dia manda en cada otro cambio el nombre de su cuenta
-- (la mesa, o el cliente de un para llevar). Lo demás de la función queda igual que en la migración
-- reportes; reemplazarla conserva sus permisos.

create or replace function public.reporte_del_dia(p_restaurante_id uuid, p_dia date default null)
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
           'accion', b.accion, 'detalle', b.detalle, 'cuenta', coalesce(v.mesa_nombre, v.cliente_nombre),
           'quien', q.nombre, 'created_at', b.created_at)
           order by b.created_at, b.id), '[]')
  into v_otros
  from public.bitacora b
  cross join lateral (
    select coalesce((b.detalle ->> 'venta_id')::bigint,
                    case when b.tabla = 'ventas' then b.registro_id::bigint end) as venta_id
  ) x
  left join public.ventas v on v.restaurante_id = b.restaurante_id and v.id = x.venta_id
  left join public.miembros q on q.restaurante_id = b.restaurante_id and q.id = b.miembro_id
  where b.restaurante_id = p_restaurante_id
    and ((b.accion in ('cambiar_mesa', 'juntar_mesas', 'quitar_descuento')
          and x.venta_id in (select c.id from privado.cuentas_del_dia(p_restaurante_id, v_dia, v_dia) c))
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
