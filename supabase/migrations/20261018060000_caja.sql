-- La caja: la parte 4b del punto de venta (libreta 5; libreta 2, Diccionario de datos, escrito el
-- 17 de octubre de 2026; maqueta La caja FKj5RPPYE1tz6dcaU6F4kX).
--
-- El punto de venta nunca cobra: solo anota cómo se pagó. Lupita o Don Chuy abren la caja con el
-- fondo (abrir_turno) y todo pago cae en ese turno: lo anota el mesero o la caja con cobrar, que
-- pone la propina y el cambio, y cierra la cuenta con su folio cuando los pagos cubren el total.
-- resumen_cuenta da los mismos números antes de anotar, para la hoja de cobro. El efectivo que
-- entra o sale sin ser venta, y las propinas que se pagan del cajón, van con movimiento_caja. Al
-- cerrar (cerrar_turno) se escribe lo contado a ciegas y Postgres calcula lo esperado de cada
-- método; resumen_turno enseña el corte. Nadie escribe directo en estas tablas.
--
-- También trae el inicio del día de negocio (inicio_del_dia), para que «Últimas listas» de la
-- cocina muestre solo las de hoy, y la regla de que una cuenta con pagos no se junta.
--
-- Cancelar un pago, cancelar una cuenta y los descuentos llegan con la parte 4c.


-- ─── El día de negocio ────────────────────────────────────────────────────────
-- El momento en que empezó el día de negocio que contiene p_momento: la hora de corte de ese día,
-- en la zona del restaurante. Va junto a privado.dia_de_negocio, la manera única de contar el día.

create function privado.inicio_dia_de_negocio(
  p_zona text,
  p_hora_corte smallint,
  p_momento timestamptz default now()
)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select (privado.dia_de_negocio(p_zona, p_hora_corte, p_momento) + make_interval(hours => p_hora_corte))
    at time zone p_zona;
$$;

-- Los pesos como los lee la gente, para los mensajes: «$1,240.00».
create function privado.pesos(p_monto numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select '$' || to_char(p_monto, 'FM999,999,999,990.00');
$$;


-- ─── turnos ───────────────────────────────────────────────────────────────────
-- Cada turno de caja. Uno abierto por restaurante. created_at es la apertura.

create table public.turnos (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  abierto_por bigint not null,
  fondo_inicial numeric(12,2) not null constraint turnos_fondo_valido check (fondo_inicial >= 0),
  estado text not null default 'abierto'
    constraint turnos_estado_valido check (estado in ('abierto', 'cerrado')),
  cerrado_por bigint,
  cerrado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, abierto_por) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, cerrado_por) references public.miembros (restaurante_id, id),
  constraint turnos_cierre check (
    case when estado = 'cerrado'
      then cerrado_por is not null and cerrado_at is not null
      else cerrado_por is null and cerrado_at is null
    end
  )
);

create unique index turnos_uno_abierto
on public.turnos (restaurante_id)
where estado = 'abierto';

create index turnos_fecha_idx on public.turnos (restaurante_id, created_at);
create index turnos_abierto_por_idx on public.turnos (restaurante_id, abierto_por);
create index turnos_cerrado_por_idx on public.turnos (restaurante_id, cerrado_por);

create trigger turnos_updated_at
before update on public.turnos
for each row execute function privado.set_updated_at();


-- ─── ventas: el cobro ─────────────────────────────────────────────────────────
-- La cuenta cerrada lleva su folio, quién la cerró, en qué turno y cuándo. pagado es la suma de
-- sus pagos y, como el total, la recalcula un trigger.

alter table public.ventas
  add column folio integer constraint ventas_folio_valido check (folio > 0),
  add column pagado numeric(12,2) not null default 0 constraint ventas_pagado_valido check (pagado >= 0),
  add column cerrada_por bigint,
  add column turno_id bigint,
  add column cerrada_at timestamptz,
  add constraint ventas_folio_unico unique (restaurante_id, folio),
  add foreign key (restaurante_id, cerrada_por) references public.miembros (restaurante_id, id),
  add foreign key (restaurante_id, turno_id) references public.turnos (restaurante_id, id),
  add constraint ventas_cierre check (
    estado <> 'cerrada'
    or (folio is not null and cerrada_at is not null
        and (origen <> 'punto_de_venta' or (cerrada_por is not null and turno_id is not null)))
  );

create index ventas_turno_idx on public.ventas (restaurante_id, turno_id);
create index ventas_cerrada_por_idx on public.ventas (restaurante_id, cerrada_por);


-- ─── pagos ────────────────────────────────────────────────────────────────────
-- Cada pago de una cuenta; una cuenta dividida son varios. clave es la que manda la app con
-- cada pago: el mismo pago dos veces (doble toque, sin conexión) se guarda una vez. Sin
-- updated_at: la 4c se lo suma junto con la cancelación.

create table public.pagos (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  venta_id bigint not null,
  turno_id bigint,
  metodo text not null
    constraint pagos_metodo_valido check (metodo in ('efectivo', 'tarjeta', 'transferencia', 'en_linea')),
  monto numeric(12,2) not null constraint pagos_monto_valido check (monto > 0),
  propina numeric(12,2) not null default 0 constraint pagos_propina_valida check (propina >= 0),
  recibido numeric(12,2),
  cambio numeric(12,2) generated always as (recibido - monto - propina) stored,
  referencia text,
  cobrado_por bigint,
  clave uuid not null,
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  unique (restaurante_id, clave),
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, turno_id) references public.turnos (restaurante_id, id),
  foreign key (restaurante_id, cobrado_por) references public.miembros (restaurante_id, id),
  constraint pagos_recibido check (
    case when metodo = 'efectivo'
      then recibido is not null and recibido >= monto + propina
      else recibido is null
    end
  ),
  constraint pagos_referencia check (
    referencia is null or (metodo in ('tarjeta', 'transferencia') and btrim(referencia) <> '')
  ),
  constraint pagos_en_linea check (
    case when metodo = 'en_linea'
      then turno_id is null and cobrado_por is null
      else turno_id is not null and cobrado_por is not null
    end
  )
);

create index pagos_venta_idx on public.pagos (restaurante_id, venta_id);
create index pagos_turno_idx on public.pagos (restaurante_id, turno_id);
create index pagos_cobrado_por_idx on public.pagos (restaurante_id, cobrado_por);

-- Lo pagado de la cuenta es la suma de sus pagos. Lo recalcula este trigger; nadie más lo
-- escribe. Un pago nunca se borra (la 4c lo cancela), así que no corre al borrar.
create function privado.recalcular_pagado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ventas v
  set pagado = coalesce((
    select sum(p.monto) from public.pagos p
    where p.restaurante_id = v.restaurante_id and p.venta_id = v.id
  ), 0)
  where v.restaurante_id = new.restaurante_id
    and (v.id = new.venta_id or (tg_op = 'UPDATE' and v.id = old.venta_id));
  return null;
end;
$$;

create trigger pagos_recalcular_pagado
after insert or update of monto, venta_id on public.pagos
for each row execute function privado.recalcular_pagado();


-- ─── folios ───────────────────────────────────────────────────────────────────
-- El último folio de cada restaurante. La fila la crea el primer cobro; cobrar la bloquea con
-- insert … on conflict do update, así dos cajas nunca sacan el mismo número. Nadie más la lee.

create table public.folios (
  restaurante_id uuid primary key references public.restaurantes (id) on delete cascade,
  ultimo integer not null default 0 constraint folios_ultimo_valido check (ultimo >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger folios_updated_at
before update on public.folios
for each row execute function privado.set_updated_at();


-- ─── movimientos_caja ─────────────────────────────────────────────────────────
-- El efectivo que entra o sale del cajón sin ser venta. Las propinas que se pagan del cajón son
-- un retiro con el mesero al que se le pagaron. No se editan. clave, como en pagos.

create table public.movimientos_caja (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  turno_id bigint not null,
  tipo text not null constraint movimientos_caja_tipo_valido check (tipo in ('retiro', 'ingreso')),
  monto numeric(12,2) not null constraint movimientos_caja_monto_valido check (monto > 0),
  motivo text not null check (btrim(motivo) <> ''),
  mesero_id bigint,
  registrado_por bigint not null,
  clave uuid not null,
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  unique (restaurante_id, clave),
  foreign key (restaurante_id, turno_id) references public.turnos (restaurante_id, id),
  foreign key (restaurante_id, mesero_id) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, registrado_por) references public.miembros (restaurante_id, id),
  constraint movimientos_caja_propinas_son_retiro check (mesero_id is null or tipo = 'retiro')
);

create index movimientos_caja_turno_idx on public.movimientos_caja (restaurante_id, turno_id);
create index movimientos_caja_mesero_idx on public.movimientos_caja (restaurante_id, mesero_id);
create index movimientos_caja_registrado_por_idx on public.movimientos_caja (restaurante_id, registrado_por);


-- ─── cortes_caja ──────────────────────────────────────────────────────────────
-- El corte al cerrar el turno: siempre una fila por cada uno de los tres métodos. No se corrige.
-- esperado no lleva tope en cero: una salida mal anotada lo puede dejar negativo, y aun así la
-- caja tiene que poder cerrar.

create table public.cortes_caja (
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  turno_id bigint not null,
  metodo text not null
    constraint cortes_caja_metodo_valido check (metodo in ('efectivo', 'tarjeta', 'transferencia')),
  esperado numeric(12,2) not null,
  contado numeric(12,2) not null constraint cortes_caja_contado_valido check (contado >= 0),
  diferencia numeric(12,2) generated always as (contado - esperado) stored,
  created_at timestamptz not null default now(),
  primary key (restaurante_id, turno_id, metodo),
  foreign key (restaurante_id, turno_id) references public.turnos (restaurante_id, id)
);


-- ─── bitacora: entradas y salidas ─────────────────────────────────────────────

alter table public.bitacora drop constraint bitacora_accion_valida;
alter table public.bitacora add constraint bitacora_accion_valida
  check (accion in ('cambiar_mesa', 'juntar_mesas', 'retiro', 'ingreso'));


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Todos los del restaurante leen los turnos (el mesero sabe si la caja está abierta) y los pagos
-- (la cuenta dice cuánto falta). Los movimientos y los cortes, solo la caja y el gerente. folios
-- no la lee nadie. Nadie escribe directo.

-- mis_restaurantes, pero solo donde quien llama es de la caja o gerente (y, si no es gerente,
-- entra desde su aparato). Para las reglas de RLS de movimientos y cortes.
create function privado.mis_restaurantes_caja()
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
    and m.roles && array['caja', 'gerente']
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria)
    and ('gerente' = any (m.roles) or privado.desde_su_aparato(m.restaurante_id, m.id));
$$;

revoke execute on function
  privado.inicio_dia_de_negocio(text, smallint, timestamptz),
  privado.pesos(numeric),
  privado.recalcular_pagado(),
  privado.mis_restaurantes_caja()
from public, anon, authenticated, service_role;

grant execute on function privado.mis_restaurantes_caja() to authenticated;

alter table public.turnos enable row level security;
alter table public.pagos enable row level security;
alter table public.folios enable row level security;
alter table public.movimientos_caja enable row level security;
alter table public.cortes_caja enable row level security;

revoke all on table public.turnos, public.pagos, public.folios, public.movimientos_caja, public.cortes_caja
from anon, authenticated;
revoke all on sequence public.turnos_id_seq, public.pagos_id_seq, public.movimientos_caja_id_seq
from anon, authenticated;

grant select (folio, pagado, cerrada_por, turno_id, cerrada_at) on public.ventas to authenticated;

grant select (
  id, restaurante_id, abierto_por, fondo_inicial, estado, cerrado_por, cerrado_at, created_at, updated_at
) on public.turnos to authenticated;

grant select (
  id, restaurante_id, venta_id, turno_id, metodo, monto, propina, recibido, cambio, referencia,
  cobrado_por, created_at
) on public.pagos to authenticated;

grant select (
  id, restaurante_id, turno_id, tipo, monto, motivo, mesero_id, registrado_por, created_at
) on public.movimientos_caja to authenticated;

grant select (
  restaurante_id, turno_id, metodo, esperado, contado, diferencia, created_at
) on public.cortes_caja to authenticated;

create policy "Los miembros leen los turnos de sus restaurantes que funcionan"
on public.turnos for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen los pagos de sus restaurantes que funcionan"
on public.pagos for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "La caja y el gerente leen los movimientos de sus restaurantes que funcionan"
on public.movimientos_caja for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_caja()));

create policy "La caja y el gerente leen los cortes de sus restaurantes que funcionan"
on public.cortes_caja for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_caja()));

-- La cuenta de Pepe y el aviso «La caja no está abierta» se actualizan solos.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.pagos, public.turnos;
  end if;
end;
$$;


-- ─── Cómo cuenta Postgres la propina y las partes ─────────────────────────────
-- La manera única de contarlas: las usan resumen_cuenta (antes de anotar) y cobrar.

-- La propina de un pago: el 10 % o el 15 % de su monto, u otra cantidad, o nada.
create function privado.propina(p_monto numeric, p_porcentaje integer, p_propina numeric)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_porcentaje is not null and p_propina is not null then
    raise exception 'La propina es un porcentaje u otra cantidad, no las dos' using errcode = '22023';
  end if;
  if p_porcentaje is not null then
    if p_porcentaje not in (10, 15) then
      raise exception 'La propina sugerida es de 10 %% o de 15 %%' using errcode = '22023';
    end if;
    return round(p_monto * p_porcentaje / 100, 2);
  end if;
  if p_propina is not null then
    if p_propina < 0 then
      raise exception 'La propina no puede ser negativa' using errcode = '22023';
    end if;
    return round(p_propina, 2);
  end if;
  return 0;
end;
$$;

-- Lo que falta, en partes iguales: los primeros se llevan el centavo que sobra. $445 entre 3 son
-- $148.34, $148.33 y $148.33.
create function privado.partes(p_monto numeric, p_partes integer)
returns numeric[]
language sql
immutable
set search_path = ''
as $$
  select array_agg(((c / p_partes) + case when i <= c % p_partes then 1 else 0 end) / 100.0 order by i)::numeric(12,2)[]
  from (select round(p_monto * 100)::bigint as c) t,
       generate_series(1, p_partes) as i;
$$;

-- El turno abierto del restaurante, bloqueado para que nadie lo cierre a la mitad de un cobro.
-- Si se cerró mientras tanto, ya no lo encuentra.
create function privado.turno_abierto(p_restaurante_id uuid)
returns bigint
language sql
volatile
security definer
set search_path = ''
as $$
  select id from public.turnos
  where restaurante_id = p_restaurante_id and estado = 'abierto'
  for share;
$$;

-- Las propinas de un turno por persona: lo que le tocó (las propinas de las cuentas que abrió),
-- lo que ya se le pagó del cajón y lo que le falta.
create function privado.propinas_del_turno(p_turno_id bigint)
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
    where p.turno_id = p_turno_id and p.propina > 0 and v.abierta_por is not null
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

-- Lo esperado de un método al cerrar: en efectivo, el fondo más lo cobrado con su propina y las
-- entradas, menos las salidas; en los demás, lo cobrado con su propina.
create function privado.esperado(p_turno_id bigint, p_metodo text)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select (
    coalesce((select sum(p.monto + p.propina) from public.pagos p
              where p.restaurante_id = t.restaurante_id and p.turno_id = t.id and p.metodo = p_metodo), 0)
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

revoke execute on function
  privado.propina(numeric, integer, numeric),
  privado.partes(numeric, integer),
  privado.turno_abierto(uuid),
  privado.propinas_del_turno(bigint),
  privado.esperado(bigint, text)
from public, anon, authenticated, service_role;


-- ─── Abrir la caja ────────────────────────────────────────────────────────────
-- Con el fondo. La app propone el del turno anterior; aquí solo se revisa que no sea negativo.

create function public.abrir_turno(p_restaurante_id uuid, p_fondo numeric)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_turno_id bigint;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo la caja y los gerentes de este restaurante abren la caja' using errcode = '42501';
  end if;
  if p_fondo is null or p_fondo < 0 then
    raise exception 'Escribe con cuánto efectivo arranca la caja' using errcode = '22023';
  end if;

  begin
    insert into public.turnos (restaurante_id, abierto_por, fondo_inicial)
    values (p_restaurante_id, v_miembro, round(p_fondo, 2))
    returning id into v_turno_id;
  exception
    when unique_violation then
      raise exception 'La caja ya está abierta' using errcode = '23505';
  end;
  return v_turno_id;
end;
$$;


-- ─── Lo que dice la hoja de cobro antes de anotar ─────────────────────────────
-- El total, lo pagado, lo que falta, las partes iguales de lo que falta, y para el monto de este
-- pago (o la primera parte): las propinas de 10 y 15 %, la elegida, lo que se cobra y el cambio.
-- No anota nada ni falla porque falte un dato: la hoja la llama mientras Pepe escribe.

create function public.resumen_cuenta(
  p_venta_id bigint,
  p_monto numeric default null,
  p_partes integer default 1,
  p_propina_porcentaje integer default null,
  p_propina numeric default null,
  p_recibido numeric default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_falta numeric(12,2);
  v_partes numeric[];
  v_monto numeric(12,2);
  v_propina numeric(12,2);
begin
  select id, restaurante_id, estado, total, pagado into v_venta
  from public.ventas
  where id = p_venta_id and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Esa cuenta ya no está' using errcode = '23503';
  end if;
  if privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']) is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cobran' using errcode = '42501';
  end if;
  if p_partes is null or p_partes < 1 or p_partes > 20 then
    raise exception 'La cuenta se divide entre 1 y 20' using errcode = '22023';
  end if;

  v_falta := greatest(v_venta.total - v_venta.pagado, 0);
  v_partes := privado.partes(v_falta, p_partes);
  v_monto := coalesce(round(p_monto, 2), v_partes[1]);
  v_propina := privado.propina(greatest(v_monto, 0), p_propina_porcentaje, p_propina);

  return jsonb_build_object(
    'estado', v_venta.estado,
    'total', v_venta.total,
    'pagado', v_venta.pagado,
    'falta', v_falta,
    'partes', to_jsonb(v_partes),
    'monto', v_monto,
    'cabe', v_monto > 0 and v_monto <= v_falta,
    'propina_10', privado.propina(greatest(v_monto, 0), 10, null),
    'propina_15', privado.propina(greatest(v_monto, 0), 15, null),
    'propina', v_propina,
    'cobrar', v_monto + v_propina,
    'cambio', case when p_recibido is not null then round(p_recibido, 2) - v_monto - v_propina end
  );
end;
$$;


-- ─── Cobrar ───────────────────────────────────────────────────────────────────
-- Anota un pago en el turno abierto. En efectivo pide con cuánto pagó el cliente y Postgres
-- calcula el cambio; con tarjeta o transferencia, la referencia es opcional. Cuando los pagos
-- cubren el total, la cuenta se cierra sola con el siguiente folio. Una cuenta de $0 se cierra
-- sin anotar pago (p_monto vacío). Con la misma clave no anota dos veces: regresa lo mismo.

create function public.cobrar(
  p_venta_id bigint,
  p_clave uuid,
  p_metodo text,
  p_monto numeric,
  p_propina_porcentaje integer default null,
  p_propina numeric default null,
  p_recibido numeric default null,
  p_referencia text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_miembro bigint;
  v_turno_id bigint;
  v_falta numeric(12,2);
  v_monto numeric(12,2);
  v_propina numeric(12,2);
  v_recibido numeric(12,2);
  v_referencia text := nullif(btrim(p_referencia), '');
  v_pago_id bigint;
  v_pago_venta bigint;
  v_cambio numeric(12,2) := 0;
  v_folio integer;
begin
  if p_clave is null then
    raise exception 'Falta la clave del pago' using errcode = '22023';
  end if;

  -- El mismo pago dos veces (sin conexión, doble toque): el segundo espera al primero y regresa
  -- lo que anotó aquel.
  perform pg_advisory_xact_lock(hashtextextended(p_clave::text, 1));
  select p.id, p.venta_id, coalesce(p.cambio, 0) into v_pago_id, v_pago_venta, v_cambio
  from public.pagos p
  where p.clave = p_clave and p.restaurante_id in (select privado.mis_restaurantes());
  if found then
    select estado, folio, total, pagado into v_venta from public.ventas where id = v_pago_venta;
    return jsonb_build_object('pago_id', v_pago_id, 'cerrada', v_venta.estado = 'cerrada', 'folio', v_venta.folio,
                              'cambio', v_cambio, 'falta', greatest(v_venta.total - v_venta.pagado, 0)::numeric(12,2));
  end if;

  select id, restaurante_id, total, pagado, folio into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cobran' using errcode = '42501';
  end if;

  v_turno_id := privado.turno_abierto(v_venta.restaurante_id);
  if v_turno_id is null then
    raise exception 'La caja no está abierta' using errcode = '55000';
  end if;

  v_falta := v_venta.total - v_venta.pagado;

  if v_falta > 0 then
    if p_metodo is null or p_metodo not in ('efectivo', 'tarjeta', 'transferencia') then
      raise exception 'Elige si pagó en efectivo, con tarjeta o por transferencia' using errcode = '22023';
    end if;
    v_monto := round(p_monto, 2);
    if v_monto is null or v_monto <= 0 then
      raise exception 'Escribe cuánto paga' using errcode = '22023';
    end if;
    if v_monto > v_falta then
      raise exception 'No puede pasar de lo que falta (%)', privado.pesos(v_falta) using errcode = '22023';
    end if;
    v_propina := privado.propina(v_monto, p_propina_porcentaje, p_propina);

    if p_metodo = 'efectivo' then
      v_recibido := round(p_recibido, 2);
      if v_recibido is null then
        raise exception 'Escribe con cuánto paga el cliente' using errcode = '22023';
      end if;
      if v_recibido < v_monto + v_propina then
        raise exception 'No alcanza: son % con la propina', privado.pesos(v_monto + v_propina) using errcode = '22023';
      end if;
      v_referencia := null;
    elsif p_recibido is not null then
      raise exception 'Con cuánto paga solo se anota en efectivo' using errcode = '22023';
    end if;

    insert into public.pagos (restaurante_id, venta_id, turno_id, metodo, monto, propina, recibido, referencia, cobrado_por, clave)
    values (v_venta.restaurante_id, p_venta_id, v_turno_id, p_metodo, v_monto, v_propina, v_recibido, v_referencia, v_miembro, p_clave)
    returning id, coalesce(cambio, 0) into v_pago_id, v_cambio;
  elsif p_monto is not null then
    raise exception 'Esta cuenta ya no debe nada' using errcode = '22023';
  end if;

  -- El trigger ya sumó el pago. Si cubre el total, la cuenta se cierra con su folio.
  select total, pagado into v_venta.total, v_venta.pagado from public.ventas where id = p_venta_id;
  if v_venta.pagado >= v_venta.total then
    v_folio := v_venta.folio;
    if v_folio is null then
      insert into public.folios (restaurante_id, ultimo) values (v_venta.restaurante_id, 1)
      on conflict (restaurante_id) do update set ultimo = public.folios.ultimo + 1
      returning ultimo into v_folio;
    end if;
    update public.ventas
    set estado = 'cerrada', folio = v_folio, cerrada_por = v_miembro, turno_id = v_turno_id, cerrada_at = now()
    where id = p_venta_id;
  end if;

  return jsonb_build_object(
    'pago_id', v_pago_id,
    'cerrada', v_folio is not null,
    'folio', v_folio,
    'cambio', v_cambio,
    'falta', greatest(v_venta.total - v_venta.pagado, 0)::numeric(12,2)
  );
end;
$$;


-- ─── Entrada o salida de efectivo ─────────────────────────────────────────────
-- Efectivo que entra o sale del cajón sin ser venta, siempre con motivo; queda en la bitácora.
-- Con p_mesero_id es el pago de sus propinas: un retiro que no pasa de lo que le falta en este
-- turno, y el motivo lo pone la función («Propinas de Pepe»).

create function public.movimiento_caja(
  p_restaurante_id uuid,
  p_clave uuid,
  p_tipo text,
  p_monto numeric,
  p_motivo text default null,
  p_mesero_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_turno_id bigint;
  v_monto numeric(12,2) := round(p_monto, 2);
  v_motivo text := nullif(btrim(p_motivo), '');
  v_mesero record;
  v_falta numeric(12,2);
  v_id bigint;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo la caja y los gerentes de este restaurante sacan o meten efectivo' using errcode = '42501';
  end if;
  if p_clave is null then
    raise exception 'Falta la clave del movimiento' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_clave::text, 2));
  select id into v_id from public.movimientos_caja where restaurante_id = p_restaurante_id and clave = p_clave;
  if found then
    return v_id;
  end if;

  v_turno_id := privado.turno_abierto(p_restaurante_id);
  if v_turno_id is null then
    raise exception 'La caja no está abierta' using errcode = '55000';
  end if;
  if p_tipo is null or p_tipo not in ('retiro', 'ingreso') then
    raise exception 'Elige si el efectivo entra o sale' using errcode = '22023';
  end if;
  if v_monto is null or v_monto <= 0 then
    raise exception 'Escribe cuánto' using errcode = '22023';
  end if;

  if p_mesero_id is not null then
    if p_tipo <> 'retiro' then
      raise exception 'Las propinas salen del cajón' using errcode = '22023';
    end if;
    select id, nombre into v_mesero
    from public.miembros
    where id = p_mesero_id and restaurante_id = p_restaurante_id;
    if not found then
      raise exception 'Esa persona no es de este restaurante' using errcode = '23503';
    end if;
    select coalesce(sum(falta), 0) into v_falta from privado.propinas_del_turno(v_turno_id) where miembro_id = p_mesero_id;
    if v_monto > v_falta then
      raise exception 'A % le faltan % de propinas en este turno', v_mesero.nombre, privado.pesos(v_falta)
        using errcode = '22023';
    end if;
    v_motivo := 'Propinas de ' || v_mesero.nombre;
  elsif v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;

  insert into public.movimientos_caja (restaurante_id, turno_id, tipo, monto, motivo, mesero_id, registrado_por, clave)
  values (p_restaurante_id, v_turno_id, p_tipo, v_monto, v_motivo, p_mesero_id, v_miembro, p_clave)
  returning id into v_id;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (p_restaurante_id, v_miembro, p_tipo, 'movimientos_caja', v_id::text,
          jsonb_build_object('monto', v_monto, 'motivo', v_motivo, 'turno_id', v_turno_id));
  return v_id;
end;
$$;


-- ─── Cerrar la caja ───────────────────────────────────────────────────────────
-- El corte a ciegas: la caja escribe lo que contó de cada método, y aquí se calcula lo esperado.
-- Se puede cerrar con cuentas abiertas: las cobra el siguiente turno. Regresa el turno cerrado.

create function public.cerrar_turno(
  p_restaurante_id uuid,
  p_efectivo numeric,
  p_tarjeta numeric,
  p_transferencia numeric
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_turno_id bigint;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo la caja y los gerentes de este restaurante cierran la caja' using errcode = '42501';
  end if;
  if p_efectivo is null or p_tarjeta is null or p_transferencia is null
     or p_efectivo < 0 or p_tarjeta < 0 or p_transferencia < 0 then
    raise exception 'Escribe lo que contaste de efectivo, tarjeta y transferencia, aunque sea $0' using errcode = '22023';
  end if;

  select id into v_turno_id
  from public.turnos
  where restaurante_id = p_restaurante_id and estado = 'abierto'
  for update;
  if not found then
    raise exception 'La caja no está abierta' using errcode = '55000';
  end if;

  insert into public.cortes_caja (restaurante_id, turno_id, metodo, esperado, contado)
  values
    (p_restaurante_id, v_turno_id, 'efectivo', privado.esperado(v_turno_id, 'efectivo'), round(p_efectivo, 2)),
    (p_restaurante_id, v_turno_id, 'tarjeta', privado.esperado(v_turno_id, 'tarjeta'), round(p_tarjeta, 2)),
    (p_restaurante_id, v_turno_id, 'transferencia', privado.esperado(v_turno_id, 'transferencia'), round(p_transferencia, 2));

  update public.turnos
  set estado = 'cerrado', cerrado_por = v_miembro, cerrado_at = now()
  where id = v_turno_id;
  return v_turno_id;
end;
$$;


-- ─── El resumen de un turno ───────────────────────────────────────────────────
-- Las propinas de cada quien y cuántas cuentas siguen abiertas. Ya cerrado, también el corte:
-- lo esperado contra lo contado, quién cobró qué y las entradas y salidas. Abierto no enseña lo
-- esperado: el corte es a ciegas.

create function public.resumen_turno(p_turno_id bigint)
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


-- ─── El efectivo que trae el mesero ───────────────────────────────────────────
-- Lo que quien llama cobró en efectivo en el turno abierto, con propinas: lo que le entrega a la
-- caja. Sin caja abierta, $0.

create function public.mi_efectivo(p_restaurante_id uuid)
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
      and p.cobrado_por = v_miembro and p.metodo = 'efectivo'
  ), 0)::numeric(12,2);
end;
$$;


-- ─── Desde cuándo es «hoy» ────────────────────────────────────────────────────
-- El inicio del día de negocio de hoy en el restaurante (la hora de corte). «Últimas listas» de
-- la cocina muestra solo las de hoy.

create function public.inicio_del_dia(p_restaurante_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select privado.inicio_dia_de_negocio(r.zona_horaria, r.hora_corte)
  from public.restaurantes r
  where r.id = p_restaurante_id and r.id in (select privado.mis_restaurantes());
$$;


-- ─── Juntar mesas: una cuenta con pagos no se junta ───────────────────────────
-- Decidido el 17 de octubre de 2026 (4b): sus pagos son de esa cuenta y no se mueven. Lo demás
-- queda igual que en la migración juntar_cuenta_pedida; reemplazarla conserva sus permisos.

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

  select id, restaurante_id, tipo, mesa_nombre, pagado into v_origen
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_origen.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante juntan mesas' using errcode = '42501';
  end if;

  select id, tipo, mesa_nombre into v_destino
  from public.ventas
  where id = p_destino_id and estado = 'abierta' and restaurante_id = v_origen.restaurante_id;
  if not found then
    raise exception 'La cuenta de esa mesa ya no está abierta' using errcode = '55000';
  end if;
  if v_origen.tipo <> 'mesa' or v_destino.tipo <> 'mesa' then
    raise exception 'Solo se juntan cuentas de mesa' using errcode = '22023';
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


revoke execute on function
  public.abrir_turno(uuid, numeric),
  public.resumen_cuenta(bigint, numeric, integer, integer, numeric, numeric),
  public.cobrar(bigint, uuid, text, numeric, integer, numeric, numeric, text),
  public.movimiento_caja(uuid, uuid, text, numeric, text, bigint),
  public.cerrar_turno(uuid, numeric, numeric, numeric),
  public.resumen_turno(bigint),
  public.mi_efectivo(uuid),
  public.inicio_del_dia(uuid)
from public, anon, service_role;

grant execute on function
  public.abrir_turno(uuid, numeric),
  public.resumen_cuenta(bigint, numeric, integer, integer, numeric, numeric),
  public.cobrar(bigint, uuid, text, numeric, integer, numeric, numeric, text),
  public.movimiento_caja(uuid, uuid, text, numeric, text, bigint),
  public.cerrar_turno(uuid, numeric, numeric, numeric),
  public.resumen_turno(bigint),
  public.mi_efectivo(uuid),
  public.inicio_del_dia(uuid)
to authenticated;
