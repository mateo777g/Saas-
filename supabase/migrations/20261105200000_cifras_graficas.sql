-- Las gráficas de las cuatro cifras de Inicio (rediseño del panel, 5 de noviembre de 2026; maqueta
-- V64Pv4gmANPRZuJW5hTe5D; libreta 4, «El rediseño del panel»). Sin tablas nuevas: cifras_de_inicio da lo
-- mismo que antes y dos cosas más, y la app solo las dibuja:
--   horas: lo vendido hasta cada hora en punto del día de negocio, de la hora de corte a la hora actual,
--     hoy y ayer (ayer, hasta esa misma hora de ayer). Es acumulado. Cuentan las cuentas cerradas del
--     día (privado.cuentas_del_dia) por la hora en que se cerraron, igual que ayer_a_esta_hora; el último
--     punto, «ahora», ya lo dan vendido_hoy.hoy y vendido_hoy.ayer_a_esta_hora.
--   lo_mas_vendido_dias: las piezas del primero de lo_mas_vendido cada día de la semana, de lunes a
--     domingo; los días que faltan, vacíos. Sin un más vendido, la lista va vacía.

create or replace function public.cifras_de_inicio(p_restaurante_id uuid)
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
  v_lunes date;
  v_d1 date;
  v_vendido numeric;
  v_ayer numeric;
  v_proyeccion jsonb;
  v_horas jsonb;
  v_primero bigint;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante ven sus cifras' using errcode = '42501';
  end if;
  select zona_horaria, hora_corte into v_zona, v_corte from public.restaurantes where id = p_restaurante_id;
  v_hoy := privado.dia_de_negocio(v_zona, v_corte);
  v_lunes := v_hoy - (extract(isodow from v_hoy)::integer - 1);
  v_d1 := date_trunc('month', v_hoy)::date;

  v_vendido := coalesce((select x.importe from privado.ventas_agrupadas(p_restaurante_id, v_hoy, v_hoy, 'total') x), 0);
  v_ayer := coalesce((
    select sum(c.total)
    from privado.cuentas_del_dia(p_restaurante_id, v_hoy - 1, v_hoy - 1) c
    where c.estado = 'cerrada'
      and c.cerrada_at <= ((now() at time zone v_zona) - interval '1 day') at time zone v_zona), 0)::numeric(12,2);
  v_proyeccion := privado.proyeccion_del_mes(p_restaurante_id);

  with de_hoy as (
    select c.total, c.cerrada_at
    from privado.cuentas_del_dia(p_restaurante_id, v_hoy, v_hoy) c
    where c.estado = 'cerrada'
  ), de_ayer as (
    select c.total, c.cerrada_at
    from privado.cuentas_del_dia(p_restaurante_id, v_hoy - 1, v_hoy - 1) c
    where c.estado = 'cerrada'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'hora', to_char(h, 'HH24:MI'),
           'hoy', (select coalesce(sum(x.total), 0)::numeric(12,2) from de_hoy x
                   where x.cerrada_at <= h at time zone v_zona),
           'ayer', (select coalesce(sum(x.total), 0)::numeric(12,2) from de_ayer x
                    where x.cerrada_at <= (h - interval '1 day') at time zone v_zona))
           order by h), '[]')
  into v_horas
  from generate_series(v_hoy::timestamp + make_interval(hours => v_corte::integer),
                       date_trunc('hour', now() at time zone v_zona),
                       interval '1 hour') as h;

  select x.clave::bigint into v_primero
  from privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'producto') x
  where x.clave <> 'descuento_cuenta' and x.unidades > 0
  order by x.unidades desc, x.importe desc, x.etiqueta
  limit 1;

  return jsonb_build_object(
    'hoy', v_hoy,
    'hora', to_char(now() at time zone v_zona, 'HH24:MI'),
    'vendido_hoy', jsonb_build_object(
      'hoy', v_vendido,
      'ayer_a_esta_hora', v_ayer,
      'porcentaje', case when v_ayer > 0 then round((v_vendido - v_ayer) * 100 / v_ayer)::integer end),
    'horas', v_horas,
    'semana', jsonb_build_object(
      'vendido', coalesce((select x.importe from privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'total') x), 0),
      'dias', (select jsonb_agg(jsonb_build_object(
                 'dia', d::date,
                 'importe', case when d::date <= v_hoy then coalesce(x.importe, 0) end)
                 order by d)
               from generate_series(v_lunes::timestamp, (v_lunes + 6)::timestamp, interval '1 day') as d
               left join privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'dia') x
                 on x.clave = to_char(d, 'YYYY-MM-DD'))),
    'lo_mas_vendido', (select coalesce(jsonb_agg(jsonb_build_object(
                         'nombre', t.etiqueta, 'unidades', t.unidades, 'importe', t.importe)
                         order by t.unidades desc, t.importe desc, t.etiqueta), '[]')
                       from (select x.etiqueta, x.unidades, x.importe
                             from privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'producto') x
                             where x.clave <> 'descuento_cuenta' and x.unidades > 0
                             order by x.unidades desc, x.importe desc, x.etiqueta
                             limit 3) t),
    'lo_mas_vendido_dias', case when v_primero is null then '[]'::jsonb else
                             (select jsonb_agg(jsonb_build_object(
                                'dia', d::date,
                                'unidades', case when d::date <= v_hoy then coalesce(x.unidades, 0) end)
                                order by d)
                              from generate_series(v_lunes::timestamp, (v_lunes + 6)::timestamp, interval '1 day') as d
                              left join privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'dia',
                                                                 p_producto_id => v_primero) x
                                on x.clave = to_char(d, 'YYYY-MM-DD'))
                           end,
    'mes', jsonb_build_object(
      'vendido', (v_proyeccion ->> 'ya_vendido')::numeric,
      'dias', (select jsonb_agg(jsonb_build_object('dia', m.dia, 'importe', m.importe, 'acumulado', m.acumulado)
                                order by m.dia)
               from (select d::date as dia, coalesce(x.importe, 0) as importe,
                            sum(coalesce(x.importe, 0)) over (order by d) as acumulado
                     from generate_series(v_d1::timestamp, v_hoy::timestamp, interval '1 day') as d
                     left join privado.ventas_agrupadas(p_restaurante_id, v_d1, v_hoy, 'dia') x
                       on x.clave = to_char(d, 'YYYY-MM-DD')) m),
      'va_para', (v_proyeccion ->> 'proyeccion')::numeric)
  );
end;
$$;
