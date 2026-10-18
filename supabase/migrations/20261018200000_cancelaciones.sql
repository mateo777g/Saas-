-- Lo que pide PIN: la parte 4c del punto de venta (libreta 5, «Propinas, descuentos y
-- cancelaciones», decidido el 13 y el 18 de octubre de 2026; libreta 2, Diccionario de datos,
-- escrito el 18 de octubre; maqueta Cancelaciones y descuentos R5psXDQp1ovBFxBvmWbq46).
--
-- Nada de dinero se borra. Lo mandado a cocina se cancela entero o una parte (cancelar_renglon),
-- una cuenta se cancela completa (cancelar_cuenta), un pago mal anotado se cancela (cancelar_pago,
-- que reabre la cuenta cerrada con el mismo folio) y los descuentos van en % o en pesos, a un
-- renglón o a toda la cuenta (descontar; quitar_descuento no pide PIN porque sube la cuenta).
-- Todo lleva motivo y queda en la bitácora. Si quien lo pide no es de la caja ni gerente, autoriza
-- otra persona con su PIN: el Worker lo mezcla con su llave y Postgres lo revisa aquí, y cada PIN
-- equivocado cuenta para el bloqueo de esa persona. Un PIN equivocado no es un error: la función
-- contesta cuántos intentos quedan, para que el intento quede contado.
--
-- Lo cancelado no suma. El total de una cuenta es la suma de sus renglones activos (ya con su
-- descuento) menos el descuento de la cuenta, y nunca queda abajo de lo pagado. Los pagos
-- cancelados no cuentan en lo pagado, ni en el corte, ni en las propinas, y solo se cancelan
-- mientras su turno sigue abierto. Una cuenta reabierta conserva su folio y ya no ocupa su mesa.


-- ─── El descuento ─────────────────────────────────────────────────────────────
-- La manera única de contar un descuento: en porcentaje, ese % de la base redondeado al centavo;
-- en pesos, el valor sin pasar de la base; sin descuento, 0. La usan los renglones (en su columna
-- generada) y las cuentas (en privado.recalcular_venta).

create function privado.descuento(p_base numeric, p_tipo text, p_valor numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select (case p_tipo
    when 'porcentaje' then round(p_base * p_valor / 100, 2)
    when 'pesos' then least(p_valor, p_base)
    else 0
  end)::numeric(12,2);
$$;


-- ─── venta_items: la cancelación y el descuento ───────────────────────────────
-- Un renglón cancelado no suma, y queda con quién lo pidió, quién dio su PIN, por qué y cuándo.
-- Cancelar 1 de 3 baja el renglón a 2 y crea otro con 1, ya cancelado. El importe resta el
-- descuento del renglón.

alter table public.venta_items
  add column descuento_tipo text
    constraint venta_items_descuento_tipo_valido check (descuento_tipo in ('porcentaje', 'pesos')),
  add column descuento_valor numeric(12,2),
  add column descuento_motivo text,
  add column estado text not null default 'activo'
    constraint venta_items_estado_valido check (estado in ('activo', 'cancelado')),
  add column cancelado_por bigint,
  add column autorizado_por bigint,
  add column cancelado_motivo text,
  add column cancelado_at timestamptz,
  add foreign key (restaurante_id, cancelado_por) references public.miembros (restaurante_id, id),
  add foreign key (restaurante_id, autorizado_por) references public.miembros (restaurante_id, id),
  add constraint venta_items_descuento check (
    case when descuento_tipo is null
      then descuento_valor is null and descuento_motivo is null
      else descuento_valor > 0 and (descuento_tipo = 'pesos' or descuento_valor <= 100)
           and coalesce(btrim(descuento_motivo), '') <> ''
    end
  ),
  add constraint venta_items_cancelado check (
    case when estado = 'cancelado'
      then cancelado_por is not null and autorizado_por is not null and cancelado_at is not null
           and coalesce(btrim(cancelado_motivo), '') <> ''
      else cancelado_por is null and autorizado_por is null and cancelado_at is null and cancelado_motivo is null
    end
  );

alter table public.venta_items
  add column descuento numeric(12,2)
    generated always as (privado.descuento(cantidad * precio_unitario, descuento_tipo, descuento_valor)) stored;

alter table public.venta_items
  alter column importe set expression as (
    cantidad * precio_unitario - privado.descuento(cantidad * precio_unitario, descuento_tipo, descuento_valor)
  );

create index venta_items_cancelado_por_idx on public.venta_items (restaurante_id, cancelado_por);
create index venta_items_autorizado_por_idx on public.venta_items (restaurante_id, autorizado_por);


-- ─── ventas: el subtotal, el descuento y la cuenta reabierta ──────────────────
-- subtotal es la suma de los renglones activos; total, el subtotal menos el descuento de la
-- cuenta. Los dos los escribe privado.recalcular_venta y nunca quedan abajo de lo pagado. Una
-- cuenta reabierta (abierta con folio) ya no ocupa su mesa: la familia nueva sigue ahí.

alter table public.ventas
  add column subtotal numeric(12,2) not null default 0 constraint ventas_subtotal_valido check (subtotal >= 0),
  add column descuento_tipo text
    constraint ventas_descuento_tipo_valido check (descuento_tipo in ('porcentaje', 'pesos')),
  add column descuento_valor numeric(12,2),
  add column descuento numeric(12,2) not null default 0,
  add column descuento_motivo text;

-- Hasta hoy ninguna cuenta tenía descuento: su subtotal es su total.
update public.ventas set subtotal = total where subtotal <> total;

alter table public.ventas
  add constraint ventas_descuento check (
    case when descuento_tipo is null
      then descuento_valor is null and descuento_motivo is null
      else descuento_valor > 0 and (descuento_tipo = 'pesos' or descuento_valor <= 100)
           and coalesce(btrim(descuento_motivo), '') <> ''
    end
  ),
  add constraint ventas_descuento_valido check (descuento >= 0 and descuento <= subtotal),
  add constraint ventas_total_cuadra check (total = subtotal - descuento),
  add constraint ventas_total_cubre_pagado check (total >= pagado);

drop index public.ventas_una_abierta_por_mesa;
create unique index ventas_una_abierta_por_mesa
on public.ventas (restaurante_id, mesa_id)
where estado = 'abierta' and folio is null;


-- ─── pagos: la cancelación ────────────────────────────────────────────────────

alter table public.pagos
  add column cancelado_at timestamptz,
  add column cancelado_por bigint,
  add column autorizado_por bigint,
  add column cancelado_motivo text,
  add column updated_at timestamptz not null default now(),
  add foreign key (restaurante_id, cancelado_por) references public.miembros (restaurante_id, id),
  add foreign key (restaurante_id, autorizado_por) references public.miembros (restaurante_id, id),
  add constraint pagos_cancelado check (
    case when cancelado_at is not null
      then cancelado_por is not null and autorizado_por is not null and coalesce(btrim(cancelado_motivo), '') <> ''
      else cancelado_por is null and autorizado_por is null and cancelado_motivo is null
    end
  );

create index pagos_cancelado_por_idx on public.pagos (restaurante_id, cancelado_por);
create index pagos_autorizado_por_idx on public.pagos (restaurante_id, autorizado_por);

create trigger pagos_updated_at
before update on public.pagos
for each row execute function privado.set_updated_at();


-- ─── bitacora: las acciones de la 4c ──────────────────────────────────────────

alter table public.bitacora drop constraint bitacora_accion_valida;
alter table public.bitacora add constraint bitacora_accion_valida
  check (accion in ('cambiar_mesa', 'juntar_mesas', 'retiro', 'ingreso', 'cancelar_renglon',
                    'cancelar_cuenta', 'cancelar_pago', 'descontar', 'quitar_descuento'));


-- ─── Lo que se lee ────────────────────────────────────────────────────────────
-- Todos los del restaurante ven lo cancelado y lo descontado, con su motivo: así lo ven el
-- mesero, la caja y la cocina. Nadie escribe directo.

grant select (subtotal, descuento_tipo, descuento_valor, descuento, descuento_motivo)
on public.ventas to authenticated;

grant select (
  descuento_tipo, descuento_valor, descuento, descuento_motivo, estado, cancelado_por,
  autorizado_por, cancelado_motivo, cancelado_at
) on public.venta_items to authenticated;

grant select (cancelado_at, cancelado_por, autorizado_por, cancelado_motivo, updated_at)
on public.pagos to authenticated;


-- ─── El total de la cuenta ────────────────────────────────────────────────────
-- Recalcula el subtotal, el descuento de la cuenta y el total. La llaman el trigger de los
-- renglones y las funciones que cambian el descuento de la cuenta.

create function privado.recalcular_venta(p_restaurante_id uuid, p_venta_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  with s as (
    select coalesce(sum(i.importe), 0)::numeric(12,2) as subtotal
    from public.venta_items i
    where i.restaurante_id = p_restaurante_id and i.venta_id = p_venta_id and i.estado = 'activo'
  )
  update public.ventas v
  set subtotal = s.subtotal,
      descuento = privado.descuento(s.subtotal, v.descuento_tipo, v.descuento_valor),
      total = s.subtotal - privado.descuento(s.subtotal, v.descuento_tipo, v.descuento_valor)
  from s
  where v.restaurante_id = p_restaurante_id and v.id = p_venta_id;
$$;

-- El trigger de siempre, ahora también cuando un renglón se cancela o cambia su descuento.
create or replace function privado.recalcular_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform privado.recalcular_venta(new.restaurante_id, new.venta_id);
  if tg_op = 'UPDATE' and old.venta_id <> new.venta_id then
    perform privado.recalcular_venta(old.restaurante_id, old.venta_id);
  end if;
  return null;
end;
$$;

create or replace trigger venta_items_recalcular_total
after insert or update of cantidad, precio_unitario, venta_id, estado, descuento_tipo, descuento_valor
on public.venta_items
for each row execute function privado.recalcular_total();

-- Lo pagado es la suma de los pagos que no se cancelaron.
create or replace function privado.recalcular_pagado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ventas v
  set pagado = coalesce((
    select sum(p.monto) from public.pagos p
    where p.restaurante_id = v.restaurante_id and p.venta_id = v.id and p.cancelado_at is null
  ), 0)
  where v.restaurante_id = new.restaurante_id
    and (v.id = new.venta_id or (tg_op = 'UPDATE' and v.id = old.venta_id));
  return null;
end;
$$;

create or replace trigger pagos_recalcular_pagado
after insert or update of monto, venta_id, cancelado_at on public.pagos
for each row execute function privado.recalcular_pagado();


-- ─── El corte sin los pagos cancelados ────────────────────────────────────────
-- Las mismas de la 4b; solo cambia que un pago cancelado no cuenta.

create or replace function privado.propinas_del_turno(p_turno_id bigint)
returns table (miembro_id bigint, nombre text, total numeric, pagado numeric, falta numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with t as (
    select restaurante_id from public.turnos where id = p_turno_id
  ), tocan as (
    select v.abierta_por as miembro_id, sum(p.propina) as total
    from public.pagos p
    join t on t.restaurante_id = p.restaurante_id
    join public.ventas v on v.restaurante_id = p.restaurante_id and v.id = p.venta_id
    where p.turno_id = p_turno_id and p.propina > 0 and p.cancelado_at is null and v.abierta_por is not null
    group by v.abierta_por
  ), pagadas as (
    select mc.mesero_id as miembro_id, sum(mc.monto) as pagado
    from public.movimientos_caja mc
    join t on t.restaurante_id = mc.restaurante_id
    where mc.turno_id = p_turno_id and mc.mesero_id is not null
    group by mc.mesero_id
  )
  select m.id, m.nombre,
         coalesce(tc.total, 0)::numeric(12,2),
         coalesce(pg.pagado, 0)::numeric(12,2),
         (coalesce(tc.total, 0) - coalesce(pg.pagado, 0))::numeric(12,2)
  from (select miembro_id from tocan union select miembro_id from pagadas) x
  left join tocan tc on tc.miembro_id = x.miembro_id
  left join pagadas pg on pg.miembro_id = x.miembro_id
  join t on true
  join public.miembros m on m.restaurante_id = t.restaurante_id and m.id = x.miembro_id
  order by m.nombre;
$$;

create or replace function privado.esperado(p_turno_id bigint, p_metodo text)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select (
    coalesce((select sum(p.monto + p.propina) from public.pagos p
              where p.restaurante_id = t.restaurante_id and p.turno_id = t.id and p.metodo = p_metodo
                and p.cancelado_at is null), 0)
    + case when p_metodo = 'efectivo' then
        t.fondo_inicial
        + coalesce((select sum(case when mc.tipo = 'ingreso' then mc.monto else -mc.monto end)
                    from public.movimientos_caja mc
                    where mc.restaurante_id = t.restaurante_id and mc.turno_id = t.id), 0)
      else 0 end
  )::numeric(12,2)
  from public.turnos t
  where t.id = p_turno_id;
$$;

create or replace function public.mi_efectivo(p_restaurante_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cobran' using errcode = '42501';
  end if;
  return coalesce((
    select sum(p.monto + p.propina)
    from public.pagos p
    join public.turnos t on t.restaurante_id = p.restaurante_id and t.id = p.turno_id
    where p.restaurante_id = p_restaurante_id and t.estado = 'abierto'
      and p.cobrado_por = v_miembro and p.metodo = 'efectivo' and p.cancelado_at is null
  ), 0)::numeric(12,2);
end;
$$;

create or replace function public.resumen_turno(p_turno_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_turno record;
  v_resumen jsonb;
begin
  select t.id, t.restaurante_id, t.estado, t.fondo_inicial, t.created_at, t.cerrado_at,
         a.nombre as abierto_por, c.nombre as cerrado_por
  into v_turno
  from public.turnos t
  join public.miembros a on a.restaurante_id = t.restaurante_id and a.id = t.abierto_por
  left join public.miembros c on c.restaurante_id = t.restaurante_id and c.id = t.cerrado_por
  where t.id = p_turno_id and t.restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Ese turno no está' using errcode = '23503';
  end if;
  if privado.mi_miembro(v_turno.restaurante_id, array['caja', 'gerente']) is null then
    raise exception 'Solo la caja y los gerentes de este restaurante ven el corte' using errcode = '42501';
  end if;

  v_resumen := jsonb_build_object(
    'id', v_turno.id,
    'estado', v_turno.estado,
    'fondo_inicial', v_turno.fondo_inicial,
    'abierto_por', v_turno.abierto_por,
    'abierto_at', v_turno.created_at,
    'cerrado_por', v_turno.cerrado_por,
    'cerrado_at', v_turno.cerrado_at,
    'cuentas_abiertas', (select count(*) from public.ventas
                         where restaurante_id = v_turno.restaurante_id and estado = 'abierta'),
    'propinas', coalesce((select jsonb_agg(jsonb_build_object(
                   'miembro_id', x.miembro_id, 'nombre', x.nombre, 'total', x.total, 'pagado', x.pagado, 'falta', x.falta)
                   order by x.nombre)
                 from privado.propinas_del_turno(v_turno.id) x), '[]')
  );
  if v_turno.estado = 'abierto' then
    return v_resumen;
  end if;

  return v_resumen || jsonb_build_object(
    'cortes', (select jsonb_agg(jsonb_build_object(
                 'metodo', k.metodo, 'esperado', k.esperado, 'contado', k.contado, 'diferencia', k.diferencia)
                 order by array_position(array['efectivo', 'tarjeta', 'transferencia'], k.metodo))
               from public.cortes_caja k
               where k.restaurante_id = v_turno.restaurante_id and k.turno_id = v_turno.id),
    'por_persona', coalesce((select jsonb_agg(jsonb_build_object(
                     'miembro_id', q.miembro_id, 'nombre', q.nombre, 'total', q.total,
                     'efectivo', q.efectivo, 'tarjeta', q.tarjeta, 'transferencia', q.transferencia)
                     order by q.total desc, q.nombre)
                   from (
                     select m.id as miembro_id, m.nombre,
                            sum(p.monto + p.propina)::numeric(12,2) as total,
                            coalesce(sum(p.monto + p.propina) filter (where p.metodo = 'efectivo'), 0)::numeric(12,2) as efectivo,
                            coalesce(sum(p.monto + p.propina) filter (where p.metodo = 'tarjeta'), 0)::numeric(12,2) as tarjeta,
                            coalesce(sum(p.monto + p.propina) filter (where p.metodo = 'transferencia'), 0)::numeric(12,2) as transferencia
                     from public.pagos p
                     join public.miembros m on m.restaurante_id = p.restaurante_id and m.id = p.cobrado_por
                     where p.restaurante_id = v_turno.restaurante_id and p.turno_id = v_turno.id
                       and p.cancelado_at is null
                     group by m.id, m.nombre
                   ) q), '[]'),
    'movimientos', coalesce((select jsonb_agg(jsonb_build_object(
                     'tipo', mc.tipo, 'monto', mc.monto, 'motivo', mc.motivo, 'registrado_por', m.nombre,
                     'created_at', mc.created_at)
                     order by mc.created_at, mc.id)
                   from public.movimientos_caja mc
                   join public.miembros m on m.restaurante_id = mc.restaurante_id and m.id = mc.registrado_por
                   where mc.restaurante_id = v_turno.restaurante_id and mc.turno_id = v_turno.id), '[]')
  );
end;
$$;


-- ─── El PIN ───────────────────────────────────────────────────────────────────
-- La manera única de revisar un PIN y contar los intentos (libreta 3): al quinto equivocado, 15
-- minutos de bloqueo; si vuelve a pasar el mismo día de negocio, hasta que el gerente desbloquee.
-- La usan entrar_con_pin y las autorizaciones. Regresa {ok}, {ok:false, motivo:'pin', quedan} o
-- {ok:false, motivo:'bloqueado', hasta}; nunca un error, para que el intento quede contado.

create function privado.revisar_pin(p_miembro_id bigint, p_pin_mezclado text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro public.miembros;
  v_zona text;
  v_corte smallint;
  v_hasta timestamptz;
begin
  select * into v_miembro from public.miembros where id = p_miembro_id for update;

  if v_miembro.bloqueado_hasta > now() then
    return jsonb_build_object('ok', false, 'motivo', 'bloqueado',
      'hasta', case when v_miembro.bloqueado_hasta <> 'infinity' then v_miembro.bloqueado_hasta end);
  end if;

  if p_pin_mezclado ~ '^[0-9a-f]{64}$' and v_miembro.pin_hash is not null
     and extensions.crypt(p_pin_mezclado, v_miembro.pin_hash) = v_miembro.pin_hash then
    update public.miembros set intentos_fallidos = 0 where id = v_miembro.id;
    return jsonb_build_object('ok', true);
  end if;

  if v_miembro.intentos_fallidos + 1 < 5 then
    update public.miembros set intentos_fallidos = intentos_fallidos + 1 where id = v_miembro.id;
    return jsonb_build_object('ok', false, 'motivo', 'pin', 'quedan', 4 - v_miembro.intentos_fallidos);
  end if;

  select zona_horaria, hora_corte into v_zona, v_corte
  from public.restaurantes where id = v_miembro.restaurante_id;

  -- bloqueado_hasta conserva el fin del bloqueo anterior: empezó 15 minutos antes.
  if v_miembro.bloqueado_hasta is not null
     and privado.dia_de_negocio(v_zona, v_corte, v_miembro.bloqueado_hasta - interval '15 minutes')
         = privado.dia_de_negocio(v_zona, v_corte) then
    v_hasta := 'infinity';
  else
    v_hasta := now() + interval '15 minutes';
  end if;

  update public.miembros
  set intentos_fallidos = 0, bloqueado_hasta = v_hasta
  where id = v_miembro.id;

  return jsonb_build_object('ok', false, 'motivo', 'bloqueado',
    'hasta', case when v_hasta <> 'infinity' then v_hasta end);
end;
$$;

-- Entrar en el aparato: lo mismo de la migración empleados, con el PIN revisado por
-- privado.revisar_pin. Reemplazarla conserva sus permisos.
create or replace function public.entrar_con_pin(p_token text, p_miembro_id bigint, p_pin_mezclado text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_aparato public.dispositivos := privado.aparato_vigente(p_token);
  v_miembro public.miembros;
  v_pin jsonb;
begin
  select * into v_miembro
  from public.miembros m
  where m.id = p_miembro_id
    and m.restaurante_id = v_aparato.restaurante_id
    and m.activo
    and m.pin_hash is not null
    and not ('gerente' = any (m.roles))
    and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
  for update;
  if not found then
    raise exception 'Esa persona no puede entrar en este aparato' using errcode = '42501';
  end if;

  v_pin := privado.revisar_pin(v_miembro.id, p_pin_mezclado);
  if not (v_pin ->> 'ok')::boolean then
    return v_pin;
  end if;

  update public.dispositivos set ultimo_uso_at = now() where id = v_aparato.id;
  return jsonb_build_object(
    'ok', true,
    'usuario_id', v_miembro.usuario_id,
    'correo', (select u.email from auth.users u where u.id = v_miembro.usuario_id)
  );
end;
$$;

-- Quién autoriza lo que pide p_miembro. Si es de la caja o gerente, él mismo. Si no, otra persona
-- de la caja o gerente con PIN, en el mismo restaurante, que pone su PIN en el aparato de quien
-- pide: el Worker lo mezcló con su llave. Regresa {ok, autoriza} o lo que contestó el PIN.
create function privado.autoriza(
  p_restaurante_id uuid,
  p_miembro bigint,
  p_autoriza_id bigint,
  p_pin_mezclado text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pin jsonb;
begin
  if exists (
    select 1 from public.miembros m
    where m.id = p_miembro and m.restaurante_id = p_restaurante_id and m.roles && array['caja', 'gerente']
  ) then
    return jsonb_build_object('ok', true, 'autoriza', p_miembro);
  end if;

  if p_autoriza_id is null or p_pin_mezclado is null then
    raise exception 'Falta quién autoriza con su PIN' using errcode = '22023';
  end if;
  perform 1 from public.miembros m
  where m.id = p_autoriza_id
    and m.restaurante_id = p_restaurante_id
    and m.id <> p_miembro
    and m.activo
    and m.roles && array['caja', 'gerente']
    and m.pin_hash is not null;
  if not found then
    raise exception 'Esa persona no puede autorizar: solo la caja o un gerente con PIN' using errcode = '42501';
  end if;

  v_pin := privado.revisar_pin(p_autoriza_id, p_pin_mezclado);
  if not (v_pin ->> 'ok')::boolean then
    return v_pin;
  end if;
  return jsonb_build_object('ok', true, 'autoriza', p_autoriza_id);
end;
$$;

revoke execute on function
  privado.descuento(numeric, text, numeric),
  privado.recalcular_venta(uuid, bigint),
  privado.revisar_pin(bigint, text),
  privado.autoriza(uuid, bigint, bigint, text)
from public, anon, authenticated, service_role;


-- ─── Una cuenta reabierta no ocupa su mesa ────────────────────────────────────
-- mandar_a_cocina abre o encuentra la cuenta de la mesa sin contar las reabiertas, y una cuenta
-- reabierta no cambia de mesa ni se junta. Lo demás queda igual; reemplazarlas conserva sus
-- permisos.

create or replace function public.mandar_a_cocina(
  p_restaurante_id uuid,
  p_clave uuid,
  p_renglones jsonb,
  p_venta_id bigint default null,
  p_mesa_id bigint default null,
  p_tipo text default null,
  p_cliente_nombre text default null,
  p_cliente_telefono text default null,
  p_cliente_direccion text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_venta_id bigint;
  v_mesa_nombre text;
  v_nombre text := nullif(btrim(p_cliente_nombre), '');
  v_telefono text := nullif(btrim(p_cliente_telefono), '');
  v_direccion text := nullif(btrim(p_cliente_direccion), '');
  v_renglon jsonb;
  v_producto record;
  v_grupo record;
  v_cantidad integer;
  v_opciones bigint[];
  v_agotada text;
  v_extra numeric(12,2);
  v_copia jsonb;
  v_comandas jsonb := '{}';
  v_comanda_id bigint;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante toman pedidos' using errcode = '42501';
  end if;
  if p_clave is null then
    raise exception 'Falta la clave del envío' using errcode = '22023';
  end if;

  -- El mismo envío dos veces (sin conexión, doble toque): el segundo espera al primero y
  -- regresa la misma cuenta sin guardar nada.
  perform pg_advisory_xact_lock(hashtextextended(p_clave::text, 0));
  select venta_id into v_venta_id
  from public.venta_items
  where restaurante_id = p_restaurante_id and clave_envio = p_clave
  limit 1;
  if found then
    return v_venta_id;
  end if;

  if p_renglones is null or jsonb_typeof(p_renglones) <> 'array' or jsonb_array_length(p_renglones) = 0 then
    raise exception 'No hay nada que mandar' using errcode = '22023';
  end if;

  -- La cuenta.
  if p_venta_id is not null then
    select id into v_venta_id
    from public.ventas
    where id = p_venta_id and restaurante_id = p_restaurante_id and estado = 'abierta'
    for update;
    if not found then
      raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
    end if;
  elsif p_mesa_id is not null then
    -- for key share: si el gerente está eliminando la mesa, espera a ver si sigue.
    select nombre into v_mesa_nombre
    from public.mesas
    where id = p_mesa_id and restaurante_id = p_restaurante_id and archivado_at is null
    for key share;
    if not found then
      raise exception 'Esa mesa ya no existe' using errcode = '23503';
    end if;
    -- Si otro mesero la abrió al mismo tiempo, todo cae en la misma cuenta.
    insert into public.ventas (restaurante_id, tipo, mesa_id, mesa_nombre, abierta_por)
    values (p_restaurante_id, 'mesa', p_mesa_id, v_mesa_nombre, v_miembro)
    on conflict (restaurante_id, mesa_id) where estado = 'abierta' and folio is null do nothing
    returning id into v_venta_id;
    if v_venta_id is null then
      select id into v_venta_id
      from public.ventas
      where restaurante_id = p_restaurante_id and mesa_id = p_mesa_id and estado = 'abierta' and folio is null
      for update;
      if not found then
        raise exception 'La mesa cambió mientras mandabas. Vuelve a intentarlo.' using errcode = '40001';
      end if;
    end if;
  else
    if p_tipo is null or p_tipo not in ('para_llevar', 'domicilio') then
      raise exception 'Elige una mesa, para llevar o domicilio' using errcode = '22023';
    end if;
    if v_nombre is null then
      raise exception 'Escribe el nombre del cliente' using errcode = '22023';
    end if;
    if p_tipo = 'domicilio' and (v_telefono is null or v_direccion is null) then
      raise exception 'Para domicilio escribe el teléfono y la dirección' using errcode = '22023';
    end if;
    insert into public.ventas (
      restaurante_id, tipo, cliente_nombre, cliente_telefono, cliente_direccion, abierta_por
    ) values (
      p_restaurante_id, p_tipo, v_nombre,
      case when p_tipo = 'domicilio' then v_telefono end,
      case when p_tipo = 'domicilio' then v_direccion end,
      v_miembro
    )
    returning id into v_venta_id;
  end if;

  -- Los renglones, en el orden en que llegan.
  for v_renglon in select value from jsonb_array_elements(p_renglones) loop
    if jsonb_typeof(v_renglon) <> 'object' then
      raise exception 'Cada renglón va con su producto y su cantidad' using errcode = '22023';
    end if;

    select p.id, p.nombre, p.precio, p.tasa_iva, p.visible, c.area_preparacion_id
    into v_producto
    from public.productos p
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where p.restaurante_id = p_restaurante_id
      and p.id = (v_renglon ->> 'producto_id')::bigint
      and p.archivado_at is null
      and c.archivado_at is null;
    if not found then
      raise exception 'Uno de esos productos ya no está en el menú. Quítalo y vuelve a mandar.' using errcode = '23503';
    end if;
    if not v_producto.visible then
      raise exception '«%» está agotado. Quítalo y vuelve a mandar.', v_producto.nombre using errcode = '55000';
    end if;

    v_cantidad := (v_renglon ->> 'cantidad')::integer;
    if v_cantidad is null or v_cantidad < 1 then
      raise exception 'La cantidad de «%» debe ser al menos 1', v_producto.nombre using errcode = '22023';
    end if;

    if jsonb_typeof(coalesce(v_renglon -> 'opciones', '[]')) <> 'array' then
      raise exception 'Las opciones de «%» van en una lista', v_producto.nombre using errcode = '22023';
    end if;
    -- Cada opción se elige una sola vez.
    v_opciones := array(
      select distinct x::bigint from jsonb_array_elements_text(coalesce(v_renglon -> 'opciones', '[]')) as x
    );

    -- Cada opción elegida es de un grupo que lleva este producto.
    if exists (
      select 1 from unnest(v_opciones) as e (id)
      where not exists (
        select 1
        from public.opciones o
        join public.producto_grupos pg on pg.restaurante_id = o.restaurante_id and pg.grupo_id = o.grupo_id
        where o.restaurante_id = p_restaurante_id and o.id = e.id and pg.producto_id = v_producto.id
      )
    ) then
      raise exception 'Una de esas opciones ya no es de «%». Vuelve a elegirlas.', v_producto.nombre using errcode = '23503';
    end if;

    select o.nombre into v_agotada
    from public.opciones o
    where o.restaurante_id = p_restaurante_id and o.id = any (v_opciones) and not o.visible
    order by o.orden, o.id
    limit 1;
    if found then
      raise exception '«%» está agotada. Vuelve a elegir en «%».', v_agotada, v_producto.nombre using errcode = '55000';
    end if;

    -- Cada grupo, en su orden: con menos opciones a la vista que su mínimo, el producto está
    -- agotado (decidido el 15 de octubre de 2026); y se eligen entre su mínimo y su máximo.
    for v_grupo in
      select g.nombre, g.minimo, g.maximo,
        (select count(*) from public.opciones o
         where o.restaurante_id = g.restaurante_id and o.grupo_id = g.id and o.visible) as a_la_vista,
        (select count(*) from public.opciones o
         where o.restaurante_id = g.restaurante_id and o.grupo_id = g.id and o.id = any (v_opciones)) as elegidas
      from public.producto_grupos pg
      join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
      where pg.restaurante_id = p_restaurante_id and pg.producto_id = v_producto.id
      order by g.orden, g.id
    loop
      if v_grupo.a_la_vista < v_grupo.minimo then
        raise exception '«%» está agotado. Quítalo y vuelve a mandar.', v_producto.nombre using errcode = '55000';
      end if;
      if v_grupo.elegidas < v_grupo.minimo then
        if v_grupo.minimo = 1 then
          raise exception 'En «%» falta elegir %', v_producto.nombre, v_grupo.nombre using errcode = '22023';
        end if;
        raise exception 'En «%» se eligen al menos % de %', v_producto.nombre, v_grupo.minimo, v_grupo.nombre using errcode = '22023';
      end if;
      if v_grupo.elegidas > v_grupo.maximo then
        raise exception 'En «%» se eligen hasta % de %', v_producto.nombre, v_grupo.maximo, v_grupo.nombre using errcode = '22023';
      end if;
    end loop;

    -- El precio del renglón y su copia de lo elegido, en el orden de los grupos.
    select
      coalesce(sum(o.precio_extra), 0),
      coalesce(jsonb_agg(
        jsonb_build_object('grupo', g.nombre, 'opcion', o.nombre, 'precio_extra', o.precio_extra)
        order by g.orden, g.id, o.orden, o.id
      ), '[]')
    into v_extra, v_copia
    from public.opciones o
    join public.grupos_opciones g on g.restaurante_id = o.restaurante_id and g.id = o.grupo_id
    where o.restaurante_id = p_restaurante_id and o.id = any (v_opciones);

    -- Una comanda por área en este envío.
    v_comanda_id := null;
    if v_producto.area_preparacion_id is not null then
      v_comanda_id := (v_comandas ->> v_producto.area_preparacion_id::text)::bigint;
      if v_comanda_id is null then
        insert into public.comandas (restaurante_id, venta_id, area_preparacion_id, enviada_por)
        values (p_restaurante_id, v_venta_id, v_producto.area_preparacion_id, v_miembro)
        returning id into v_comanda_id;
        v_comandas := v_comandas || jsonb_build_object(v_producto.area_preparacion_id::text, v_comanda_id);
      end if;
    end if;

    insert into public.venta_items (
      restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, opciones, nota,
      tasa_iva, comanda_id, agregado_por, clave_envio
    ) values (
      p_restaurante_id, v_venta_id, v_producto.id, v_producto.nombre, v_producto.precio + v_extra,
      v_cantidad, v_copia, nullif(btrim(v_renglon ->> 'nota'), ''), v_producto.tasa_iva,
      v_comanda_id, v_miembro, p_clave
    );
  end loop;

  -- Si piden algo después de «Pedir la cuenta», la mesa deja de decirlo.
  update public.ventas
  set cuenta_pedida_at = null
  where id = v_venta_id and cuenta_pedida_at is not null;

  return v_venta_id;
end;
$$;

create or replace function public.cambiar_mesa(p_venta_id bigint, p_mesa_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_miembro bigint;
  v_nombre text;
begin
  select id, restaurante_id, tipo, mesa_id, mesa_nombre, folio into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cambian de mesa' using errcode = '42501';
  end if;
  if v_venta.tipo <> 'mesa' then
    raise exception 'Solo una cuenta de mesa se cambia de mesa' using errcode = '22023';
  end if;
  if v_venta.folio is not null then
    raise exception 'Una cuenta reabierta ya no ocupa mesa: se cobra desde la caja' using errcode = '55000';
  end if;

  select nombre into v_nombre
  from public.mesas
  where id = p_mesa_id and restaurante_id = v_venta.restaurante_id and archivado_at is null
  for key share;
  if not found then
    raise exception 'Esa mesa ya no existe' using errcode = '23503';
  end if;
  if p_mesa_id = v_venta.mesa_id then
    raise exception 'La cuenta ya está en %', v_nombre using errcode = '22023';
  end if;

  begin
    update public.ventas set mesa_id = p_mesa_id, mesa_nombre = v_nombre where id = p_venta_id;
  exception
    when unique_violation then
      raise exception '% ya tiene una cuenta abierta', v_nombre using errcode = '23505';
  end;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, v_miembro, 'cambiar_mesa', 'ventas', p_venta_id::text,
          jsonb_build_object('de', v_venta.mesa_nombre, 'a', v_nombre));
end;
$$;

create or replace function public.juntar_mesas(p_venta_id bigint, p_destino_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origen record;
  v_destino record;
  v_miembro bigint;
begin
  if p_venta_id is null or p_destino_id is null or p_venta_id = p_destino_id then
    raise exception 'Elige otra mesa para juntarla' using errcode = '22023';
  end if;

  -- Las dos cuentas se bloquean siempre en el mismo orden: dos juntas cruzadas no se atoran.
  perform 1
  from public.ventas
  where id in (p_venta_id, p_destino_id) and restaurante_id in (select privado.mis_restaurantes())
  order by id
  for update;

  select id, restaurante_id, tipo, mesa_nombre, pagado, folio into v_origen
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_origen.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante juntan mesas' using errcode = '42501';
  end if;

  select id, tipo, mesa_nombre, folio into v_destino
  from public.ventas
  where id = p_destino_id and estado = 'abierta' and restaurante_id = v_origen.restaurante_id;
  if not found then
    raise exception 'La cuenta de esa mesa ya no está abierta' using errcode = '55000';
  end if;
  if v_origen.tipo <> 'mesa' or v_destino.tipo <> 'mesa' then
    raise exception 'Solo se juntan cuentas de mesa' using errcode = '22023';
  end if;
  if v_origen.folio is not null or v_destino.folio is not null then
    raise exception 'Una cuenta reabierta no se junta con otra' using errcode = '55000';
  end if;
  if v_origen.pagado > 0 then
    raise exception '% ya tiene pagos. Cóbrala antes de juntarla.', v_origen.mesa_nombre using errcode = '55000';
  end if;

  update public.venta_items set venta_id = p_destino_id
  where restaurante_id = v_origen.restaurante_id and venta_id = p_venta_id;
  update public.comandas set venta_id = p_destino_id
  where restaurante_id = v_origen.restaurante_id and venta_id = p_venta_id;
  update public.ventas
  set estado = 'cancelada', cancelada_motivo = 'Se juntó con «' || v_destino.mesa_nombre || '»'
  where id = p_venta_id;
  -- La cuenta que vio el cliente ya cambió: la que recibe deja de decir «Pidió la cuenta».
  update public.ventas set cuenta_pedida_at = null
  where id = p_destino_id and cuenta_pedida_at is not null;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_origen.restaurante_id, v_miembro, 'juntar_mesas', 'ventas', p_venta_id::text,
          jsonb_build_object('de', v_origen.mesa_nombre, 'a', v_destino.mesa_nombre, 'a_venta', p_destino_id));
end;
$$;


-- ─── Cancelar lo mandado ──────────────────────────────────────────────────────
-- Cancela p_cantidad de un renglón mandado, con motivo. Si es una parte, el renglón baja y nace
-- otro con lo cancelado, en la misma comanda y con el mismo precio, opciones y clave (un descuento
-- en % se copia; uno en pesos se queda en el que sigue activo). La cuenta no puede quedar abajo de
-- lo pagado. Regresa {ok, autoriza} o lo que contestó el PIN.

create function public.cancelar_renglon(
  p_renglon_id bigint,
  p_cantidad integer,
  p_motivo text,
  p_autoriza_id bigint default null,
  p_pin_mezclado text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_renglon public.venta_items;
  v_venta record;
  v_miembro bigint;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_resta integer;
  v_queda numeric(12,2);
  v_subtotal numeric(12,2);
  v_total numeric(12,2);
  v_aut jsonb;
  v_autoriza bigint;
  v_cancelado_id bigint;
begin
  select * into v_renglon
  from public.venta_items
  where id = p_renglon_id and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Ese producto ya no está en la cuenta' using errcode = '23503';
  end if;

  -- Primero la cuenta y luego el renglón, como las demás funciones del dinero.
  select id, restaurante_id, estado, subtotal, pagado, descuento_tipo, descuento_valor into v_venta
  from public.ventas
  where id = v_renglon.venta_id and restaurante_id = v_renglon.restaurante_id
  for update;
  select * into v_renglon from public.venta_items where id = p_renglon_id for update;
  if v_venta.estado <> 'abierta' or v_renglon.venta_id <> v_venta.id then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cancelan' using errcode = '42501';
  end if;
  if v_renglon.estado = 'cancelado' then
    raise exception '«%» ya está cancelado', v_renglon.nombre using errcode = '55000';
  end if;
  if p_cantidad is null or p_cantidad < 1 or p_cantidad > v_renglon.cantidad then
    raise exception 'De «%» se cancelan de 1 a %', v_renglon.nombre, v_renglon.cantidad using errcode = '22023';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;

  -- En cuánto quedaría la cuenta, antes de pedir el PIN.
  v_resta := v_renglon.cantidad - p_cantidad;
  v_queda := v_resta * v_renglon.precio_unitario
    - privado.descuento(v_resta * v_renglon.precio_unitario, v_renglon.descuento_tipo, v_renglon.descuento_valor);
  v_subtotal := v_venta.subtotal - v_renglon.importe + v_queda;
  v_total := v_subtotal - privado.descuento(v_subtotal, v_venta.descuento_tipo, v_venta.descuento_valor);
  if v_total < v_venta.pagado then
    raise exception 'Ya se pagaron %. Cancela antes un pago.', privado.pesos(v_venta.pagado) using errcode = '55000';
  end if;

  v_aut := privado.autoriza(v_venta.restaurante_id, v_miembro, p_autoriza_id, p_pin_mezclado);
  if not (v_aut ->> 'ok')::boolean then
    return v_aut;
  end if;
  v_autoriza := (v_aut ->> 'autoriza')::bigint;

  if v_resta = 0 then
    update public.venta_items
    set estado = 'cancelado', cancelado_por = v_miembro, autorizado_por = v_autoriza,
        cancelado_motivo = v_motivo, cancelado_at = now()
    where id = p_renglon_id;
    v_cancelado_id := p_renglon_id;
  else
    update public.venta_items set cantidad = v_resta where id = p_renglon_id;
    insert into public.venta_items (
      restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, opciones, nota,
      tasa_iva, comanda_id, agregado_por, clave_envio, created_at, descuento_tipo, descuento_valor,
      descuento_motivo, estado, cancelado_por, autorizado_por, cancelado_motivo, cancelado_at
    ) values (
      v_renglon.restaurante_id, v_renglon.venta_id, v_renglon.producto_id, v_renglon.nombre,
      v_renglon.precio_unitario, p_cantidad, v_renglon.opciones, v_renglon.nota, v_renglon.tasa_iva,
      v_renglon.comanda_id, v_renglon.agregado_por, v_renglon.clave_envio, v_renglon.created_at,
      case when v_renglon.descuento_tipo = 'porcentaje' then 'porcentaje' end,
      case when v_renglon.descuento_tipo = 'porcentaje' then v_renglon.descuento_valor end,
      case when v_renglon.descuento_tipo = 'porcentaje' then v_renglon.descuento_motivo end,
      'cancelado', v_miembro, v_autoriza, v_motivo, now()
    )
    returning id into v_cancelado_id;
  end if;

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, v_miembro, v_autoriza, 'cancelar_renglon', 'venta_items', v_cancelado_id::text,
          jsonb_build_object('venta_id', v_venta.id, 'nombre', v_renglon.nombre, 'cantidad', p_cantidad,
                             'de', v_renglon.cantidad, 'importe', v_renglon.importe - v_queda, 'motivo', v_motivo));
  return jsonb_build_object('ok', true, 'autoriza', v_autoriza);
end;
$$;


-- ─── Cancelar la cuenta ───────────────────────────────────────────────────────
-- Cancela todo lo de una cuenta abierta, con motivo, como la de una mesa que se fue sin pagar. Su
-- mesa queda libre y la cocina ve sus renglones tachados. Con pagos no se puede: antes se cancelan.

create function public.cancelar_cuenta(
  p_venta_id bigint,
  p_motivo text,
  p_autoriza_id bigint default null,
  p_pin_mezclado text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_miembro bigint;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_aut jsonb;
  v_autoriza bigint;
begin
  select id, restaurante_id, tipo, mesa_nombre, cliente_nombre, total, pagado into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cancelan' using errcode = '42501';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;
  if v_venta.pagado > 0 then
    raise exception 'Esta cuenta tiene pagos (%). Cancélalos antes.', privado.pesos(v_venta.pagado) using errcode = '55000';
  end if;

  v_aut := privado.autoriza(v_venta.restaurante_id, v_miembro, p_autoriza_id, p_pin_mezclado);
  if not (v_aut ->> 'ok')::boolean then
    return v_aut;
  end if;
  v_autoriza := (v_aut ->> 'autoriza')::bigint;

  update public.venta_items
  set estado = 'cancelado', cancelado_por = v_miembro, autorizado_por = v_autoriza,
      cancelado_motivo = v_motivo, cancelado_at = now()
  where restaurante_id = v_venta.restaurante_id and venta_id = p_venta_id and estado = 'activo';
  update public.ventas
  set estado = 'cancelada', cancelada_motivo = v_motivo, cuenta_pedida_at = null
  where id = p_venta_id;

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, v_miembro, v_autoriza, 'cancelar_cuenta', 'ventas', p_venta_id::text,
          jsonb_build_object('cuenta', coalesce(v_venta.mesa_nombre, v_venta.cliente_nombre),
                             'total', v_venta.total, 'motivo', v_motivo));
  return jsonb_build_object('ok', true, 'autoriza', v_autoriza);
end;
$$;


-- ─── Cancelar un pago ─────────────────────────────────────────────────────────
-- Un pago mal anotado se cancela con motivo, solo mientras su turno sigue abierto: un corte
-- cerrado no cambia. Si la cuenta estaba cerrada, se reabre con el mismo folio; ya no ocupa su
-- mesa, y en la caja sale como reabierta para anotar el pago correcto.

create function public.cancelar_pago(
  p_pago_id bigint,
  p_motivo text,
  p_autoriza_id bigint default null,
  p_pin_mezclado text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pago public.pagos;
  v_venta record;
  v_miembro bigint;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_aut jsonb;
  v_autoriza bigint;
begin
  select * into v_pago
  from public.pagos
  where id = p_pago_id and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Ese pago ya no está' using errcode = '23503';
  end if;

  select id, restaurante_id, estado, folio into v_venta
  from public.ventas
  where id = v_pago.venta_id and restaurante_id = v_pago.restaurante_id
  for update;
  select * into v_pago from public.pagos where id = p_pago_id for update;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cancelan' using errcode = '42501';
  end if;
  if v_pago.cancelado_at is not null then
    raise exception 'Ese pago ya está cancelado' using errcode = '55000';
  end if;
  if v_pago.metodo = 'en_linea' then
    raise exception 'Un pago en línea no se cancela desde la caja' using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.turnos t
    where t.restaurante_id = v_pago.restaurante_id and t.id = v_pago.turno_id and t.estado = 'abierto'
  ) then
    raise exception 'Ese pago es de un turno que ya se cortó' using errcode = '55000';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;

  v_aut := privado.autoriza(v_venta.restaurante_id, v_miembro, p_autoriza_id, p_pin_mezclado);
  if not (v_aut ->> 'ok')::boolean then
    return v_aut;
  end if;
  v_autoriza := (v_aut ->> 'autoriza')::bigint;

  update public.pagos
  set cancelado_at = now(), cancelado_por = v_miembro, autorizado_por = v_autoriza, cancelado_motivo = v_motivo
  where id = p_pago_id;
  if v_venta.estado = 'cerrada' then
    update public.ventas
    set estado = 'abierta', cerrada_por = null, turno_id = null, cerrada_at = null
    where id = v_venta.id;
  end if;

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, v_miembro, v_autoriza, 'cancelar_pago', 'pagos', p_pago_id::text,
          jsonb_build_object('venta_id', v_venta.id, 'folio', v_venta.folio, 'metodo', v_pago.metodo,
                             'monto', v_pago.monto, 'propina', v_pago.propina, 'motivo', v_motivo,
                             'reabierta', v_venta.estado = 'cerrada'));
  return jsonb_build_object('ok', true, 'autoriza', v_autoriza, 'reabierta', v_venta.estado = 'cerrada');
end;
$$;


-- ─── Descontar ────────────────────────────────────────────────────────────────
-- Un descuento en % o en pesos, con motivo, a un renglón (p_renglon_id) o a toda la cuenta. Hay
-- uno solo en cada lugar: el nuevo reemplaza al anterior. Regalar es 100 %. En pesos no pasa de lo
-- que cuesta, y la cuenta no puede quedar abajo de lo pagado.

create function public.descontar(
  p_venta_id bigint,
  p_renglon_id bigint,
  p_tipo text,
  p_valor numeric,
  p_motivo text,
  p_autoriza_id bigint default null,
  p_pin_mezclado text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_renglon public.venta_items;
  v_miembro bigint;
  v_valor numeric(12,2) := round(p_valor, 2);
  v_motivo text := nullif(btrim(p_motivo), '');
  v_base numeric(12,2);
  v_subtotal numeric(12,2);
  v_total numeric(12,2);
  v_aut jsonb;
  v_autoriza bigint;
begin
  select id, restaurante_id, subtotal, pagado, descuento_tipo, descuento_valor into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante hacen descuentos' using errcode = '42501';
  end if;
  if p_renglon_id is not null then
    select * into v_renglon
    from public.venta_items
    where id = p_renglon_id and restaurante_id = v_venta.restaurante_id and venta_id = p_venta_id
    for update;
    if not found then
      raise exception 'Ese producto ya no está en la cuenta' using errcode = '23503';
    end if;
    if v_renglon.estado = 'cancelado' then
      raise exception '«%» está cancelado: no se descuenta', v_renglon.nombre using errcode = '55000';
    end if;
  end if;
  if p_tipo is null or p_tipo not in ('porcentaje', 'pesos') then
    raise exception 'Elige si el descuento es en %% o en pesos' using errcode = '22023';
  end if;
  if v_valor is null or v_valor <= 0 or (p_tipo = 'porcentaje' and v_valor > 100) then
    raise exception '%', case when p_tipo = 'porcentaje' then 'El descuento va de 1 a 100 %' else 'Escribe cuántos pesos' end
      using errcode = '22023';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;

  -- En cuánto quedaría la cuenta, antes de pedir el PIN.
  if p_renglon_id is not null then
    v_base := v_renglon.cantidad * v_renglon.precio_unitario;
    v_subtotal := v_venta.subtotal - v_renglon.importe + v_base - privado.descuento(v_base, p_tipo, v_valor);
    v_total := v_subtotal - privado.descuento(v_subtotal, v_venta.descuento_tipo, v_venta.descuento_valor);
  else
    v_base := v_venta.subtotal;
    v_total := v_venta.subtotal - privado.descuento(v_venta.subtotal, p_tipo, v_valor);
  end if;
  if p_tipo = 'pesos' and v_valor > v_base then
    raise exception 'El descuento no puede pasar de %', privado.pesos(v_base) using errcode = '22023';
  end if;
  if v_total < v_venta.pagado then
    raise exception 'Ya se pagaron %. Cancela antes un pago.', privado.pesos(v_venta.pagado) using errcode = '55000';
  end if;

  v_aut := privado.autoriza(v_venta.restaurante_id, v_miembro, p_autoriza_id, p_pin_mezclado);
  if not (v_aut ->> 'ok')::boolean then
    return v_aut;
  end if;
  v_autoriza := (v_aut ->> 'autoriza')::bigint;

  if p_renglon_id is not null then
    update public.venta_items
    set descuento_tipo = p_tipo, descuento_valor = v_valor, descuento_motivo = v_motivo
    where id = p_renglon_id;
  else
    update public.ventas
    set descuento_tipo = p_tipo, descuento_valor = v_valor, descuento_motivo = v_motivo
    where id = p_venta_id;
    perform privado.recalcular_venta(v_venta.restaurante_id, p_venta_id);
  end if;

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, v_miembro, v_autoriza, 'descontar',
          case when p_renglon_id is null then 'ventas' else 'venta_items' end,
          coalesce(p_renglon_id, p_venta_id)::text,
          jsonb_build_object('venta_id', p_venta_id, 'nombre', v_renglon.nombre, 'tipo', p_tipo,
                             'valor', v_valor, 'descuento', privado.descuento(v_base, p_tipo, v_valor),
                             'motivo', v_motivo,
                             'antes', case when p_renglon_id is null then v_venta.descuento_tipo else v_renglon.descuento_tipo end));
  return jsonb_build_object('ok', true, 'autoriza', v_autoriza);
end;
$$;


-- ─── Quitar un descuento ──────────────────────────────────────────────────────
-- Sube la cuenta, así que no pide PIN; queda en la bitácora.

create function public.quitar_descuento(p_venta_id bigint, p_renglon_id bigint default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_renglon public.venta_items;
  v_miembro bigint;
  v_antes jsonb;
begin
  select id, restaurante_id, descuento_tipo, descuento_valor, descuento_motivo into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante quitan descuentos' using errcode = '42501';
  end if;

  if p_renglon_id is not null then
    select * into v_renglon
    from public.venta_items
    where id = p_renglon_id and restaurante_id = v_venta.restaurante_id and venta_id = p_venta_id
      and estado = 'activo'
    for update;
    if not found or v_renglon.descuento_tipo is null then
      raise exception 'Ese producto no tiene descuento' using errcode = '55000';
    end if;
    v_antes := jsonb_build_object('nombre', v_renglon.nombre, 'tipo', v_renglon.descuento_tipo,
                                  'valor', v_renglon.descuento_valor, 'motivo', v_renglon.descuento_motivo);
    update public.venta_items
    set descuento_tipo = null, descuento_valor = null, descuento_motivo = null
    where id = p_renglon_id;
  else
    if v_venta.descuento_tipo is null then
      raise exception 'Esta cuenta no tiene descuento' using errcode = '55000';
    end if;
    v_antes := jsonb_build_object('tipo', v_venta.descuento_tipo, 'valor', v_venta.descuento_valor,
                                  'motivo', v_venta.descuento_motivo);
    update public.ventas
    set descuento_tipo = null, descuento_valor = null, descuento_motivo = null
    where id = p_venta_id;
    perform privado.recalcular_venta(v_venta.restaurante_id, p_venta_id);
  end if;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, v_miembro, 'quitar_descuento',
          case when p_renglon_id is null then 'ventas' else 'venta_items' end,
          coalesce(p_renglon_id, p_venta_id)::text,
          v_antes || jsonb_build_object('venta_id', p_venta_id));
end;
$$;


revoke execute on function
  public.cancelar_renglon(bigint, integer, text, bigint, text),
  public.cancelar_cuenta(bigint, text, bigint, text),
  public.cancelar_pago(bigint, text, bigint, text),
  public.descontar(bigint, bigint, text, numeric, text, bigint, text),
  public.quitar_descuento(bigint, bigint)
from public, anon, service_role;

grant execute on function
  public.cancelar_renglon(bigint, integer, text, bigint, text),
  public.cancelar_cuenta(bigint, text, bigint, text),
  public.cancelar_pago(bigint, text, bigint, text),
  public.descontar(bigint, bigint, text, numeric, text, bigint, text),
  public.quitar_descuento(bigint, bigint)
to authenticated;
