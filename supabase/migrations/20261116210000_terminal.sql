-- La terminal conectada (16 de noviembre de 2026; planes/trabajo/terminal/): cada sucursal conecta su cuenta de
-- Mercado Pago y su Point Smart, el monto de la cuenta llega solo a la terminal y, cuando el cliente paga, la cuenta
-- se cierra sola. El dinero va directo a la cuenta del restaurante: Fragmentless nunca lo toca. Quien no conecte nada
-- sigue igual, tecleando el monto. Lo decidido: libretas de Punto de venta («La terminal conectada»), Seguridad
-- («Mercado Pago») y el Diccionario («La terminal Mercado Pago»).
--
-- Cuatro tablas nuevas: mercado_pago (la conexión de cada sucursal; los miembros la leen), llaves_mercado_pago (sus
-- llaves, cifradas por el Worker; sin permisos para nadie), pases_mercado_pago (el pase de un solo uso para conectar;
-- sin permisos) y cobros_terminal (la nota de cada cobro mandado a la Point; los miembros la leen, en tiempo real).
--
-- cobrar se parte: privado.anotar_pago anota el pago y cierra la cuenta, y lo usan cobrar y el cobro de la terminal,
-- que anota a nombre de quien lo mandó. Mientras un cobro espera, su cuenta no cambia por ningún lado (candados en
-- ventas, venta_items y pagos), la caja no se cierra y Mercado Pago no se desconecta. cancelar_pago no cancela un
-- pago de la terminal: ese se devuelve con Mercado Pago (revisar_devolucion y pago_devuelto, por el Worker).
-- reporte_del_dia suma «Devuelto desde Mercado Pago» a los otros cambios del día en que llegó el aviso.


-- ─── mercado_pago ─────────────────────────────────────────────────────────────
-- Una fila por sucursal que conectó su cuenta. Sin fila: «Sin conectar»; con desconectada_at: «Se desconectó».
-- Desconectar borra la fila y sus llaves. No guarda ninguna llave.

create table public.mercado_pago (
  restaurante_id uuid primary key references public.restaurantes (id) on delete cascade,
  cuenta_id text not null constraint mercado_pago_cuenta check (btrim(cuenta_id) <> ''),
  cuenta_nombre text not null constraint mercado_pago_cuenta_nombre check (btrim(cuenta_nombre) <> ''),
  conectada_at timestamptz not null default now(),
  desconectada_at timestamptz,
  terminal_id text
    constraint mercado_pago_terminal check (terminal_id is null or btrim(terminal_id) <> '')
    constraint mercado_pago_terminal_unica unique,
  imprimir_ticket boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index mercado_pago_cuenta_idx on public.mercado_pago (cuenta_id);

create trigger mercado_pago_updated_at
before update on public.mercado_pago
for each row execute function privado.set_updated_at();


-- ─── llaves_mercado_pago ──────────────────────────────────────────────────────
-- Las llaves de cada sucursal, cifradas por el Worker con AES-256-GCM (su número al azar adelante). Se van con la
-- fila de mercado_pago.

create table public.llaves_mercado_pago (
  restaurante_id uuid primary key references public.mercado_pago (restaurante_id) on delete cascade,
  acceso text not null constraint llaves_mercado_pago_acceso check (btrim(acceso) <> ''),
  renovar text not null constraint llaves_mercado_pago_renovar check (btrim(renovar) <> ''),
  version smallint not null constraint llaves_mercado_pago_version check (version > 0),
  vence_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index llaves_mercado_pago_vence_idx on public.llaves_mercado_pago (vence_at);

create trigger llaves_mercado_pago_updated_at
before update on public.llaves_mercado_pago
for each row execute function privado.set_updated_at();


-- ─── pases_mercado_pago ───────────────────────────────────────────────────────
-- Un pase por cada «Conectar Mercado Pago»: sirve una vez y dura 10 minutos. Se guarda su huella, no el pase.

create table public.pases_mercado_pago (
  huella text primary key constraint pases_mercado_pago_huella check (huella ~ '^[0-9a-f]{64}$'),
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  usuario_id uuid not null,
  verificador text not null constraint pases_mercado_pago_verificador check (verificador ~ '^[A-Za-z0-9._~-]{43,128}$'),
  origen text not null constraint pases_mercado_pago_origen check (origen ~ '^https?://[^/?#]+$'),
  vence_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index pases_mercado_pago_vence_idx on public.pases_mercado_pago (vence_at);


-- ─── cobros_terminal ──────────────────────────────────────────────────────────
-- La nota de cada cobro mandado a la Point, guardada antes de mandarlo. Nunca se borra. Uno activo (mandando,
-- esperando o revisar) por cuenta y uno por sucursal.

create table public.cobros_terminal (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  venta_id bigint not null,
  clave uuid not null,
  mandado_por bigint not null,
  turno_id bigint not null,
  monto numeric(12,2) not null constraint cobros_terminal_monto check (monto >= 5),
  propina numeric(12,2) not null default 0 constraint cobros_terminal_propina check (propina >= 0 and propina < monto),
  terminal_id text not null constraint cobros_terminal_terminal check (btrim(terminal_id) <> ''),
  orden_id text constraint cobros_terminal_orden_unica unique
    constraint cobros_terminal_orden check (orden_id is null or btrim(orden_id) <> ''),
  estado text not null default 'mandando'
    constraint cobros_terminal_estado check (estado in ('mandando', 'esperando', 'pagado', 'no_se_cobro', 'revisar')),
  motivo text,
  tomado_at timestamptz,
  vence_at timestamptz not null,
  terminado_at timestamptz,
  confirmado_por bigint,
  pago_id bigint constraint cobros_terminal_pago_unico unique,
  devuelto_at timestamptz,
  devuelto_desde text constraint cobros_terminal_devuelto_desde check (devuelto_desde in ('sistema', 'mercado_pago')),
  devuelto_monto numeric(12,2) constraint cobros_terminal_devuelto_monto check (devuelto_monto > 0 and devuelto_monto <= monto),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  unique (restaurante_id, clave),
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, mandado_por) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, turno_id) references public.turnos (restaurante_id, id),
  foreign key (restaurante_id, confirmado_por) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, pago_id) references public.pagos (restaurante_id, id),
  constraint cobros_terminal_motivo check (
    case when estado = 'no_se_cobro'
      then motivo in ('rechazada', 'vencida', 'cancelada', 'cancelada_terminal', 'ocupada', 'sin_conexion')
      else motivo is null
    end
  ),
  constraint cobros_terminal_terminado check ((terminado_at is null) = (estado in ('mandando', 'esperando', 'revisar'))),
  constraint cobros_terminal_esperando check (estado <> 'esperando' or orden_id is not null),
  constraint cobros_terminal_pago check (pago_id is null or estado = 'pagado'),
  -- La devolución del sistema se aparta (devuelto_desde 'sistema' sin fecha) mientras Mercado Pago contesta.
  constraint cobros_terminal_devuelto check (
    (devuelto_desde is null or estado = 'pagado')
    and (devuelto_at is null) = (devuelto_monto is null)
    and (devuelto_at is null or devuelto_desde is not null)
  )
);

create unique index cobros_terminal_uno_por_cuenta
  on public.cobros_terminal (venta_id) where estado in ('mandando', 'esperando', 'revisar');
create unique index cobros_terminal_uno_por_sucursal
  on public.cobros_terminal (restaurante_id) where estado in ('mandando', 'esperando', 'revisar');
create index cobros_terminal_venta_idx on public.cobros_terminal (restaurante_id, venta_id);
create index cobros_terminal_mandado_por_idx on public.cobros_terminal (restaurante_id, mandado_por);
create index cobros_terminal_turno_idx on public.cobros_terminal (restaurante_id, turno_id);
create index cobros_terminal_confirmado_por_idx on public.cobros_terminal (restaurante_id, confirmado_por);

create trigger cobros_terminal_updated_at
before update on public.cobros_terminal
for each row execute function privado.set_updated_at();


-- ─── La bitácora ──────────────────────────────────────────────────────────────
-- Conectar, desconectar, cada «Sí se pagó / No se pagó» y cada devolución desde Mercado Pago.

alter table public.bitacora drop constraint bitacora_accion_valida;
alter table public.bitacora add constraint bitacora_accion_valida
  check (accion in ('cambiar_mesa', 'juntar_mesas', 'retiro', 'ingreso', 'cancelar_renglon',
                    'cancelar_cuenta', 'cancelar_pago', 'descontar', 'quitar_descuento',
                    'cambiar_hora_corte', 'conectar_mercado_pago', 'desconectar_mercado_pago',
                    'confirmar_terminal', 'devuelto_mercado_pago'));


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Los miembros leen la conexión (sin cuenta_id) y los cobros de sus sucursales; nadie escribe directo. Las llaves y
-- los pases no tienen permisos para nadie: solo los tocan las funciones del Worker.

alter table public.mercado_pago enable row level security;
alter table public.llaves_mercado_pago enable row level security;
alter table public.pases_mercado_pago enable row level security;
alter table public.cobros_terminal enable row level security;

revoke all on table public.mercado_pago, public.llaves_mercado_pago, public.pases_mercado_pago,
  public.cobros_terminal from anon, authenticated, service_role;
revoke all on sequence public.cobros_terminal_id_seq from anon, authenticated, service_role;

grant select (
  restaurante_id, cuenta_nombre, conectada_at, desconectada_at, terminal_id, imprimir_ticket, created_at, updated_at
) on public.mercado_pago to authenticated;

grant select (
  id, restaurante_id, venta_id, clave, mandado_por, turno_id, monto, propina, terminal_id, orden_id, estado, motivo,
  tomado_at, vence_at, terminado_at, confirmado_por, pago_id, devuelto_at, devuelto_desde, devuelto_monto,
  created_at, updated_at
) on public.cobros_terminal to authenticated;

create policy "Los miembros leen la conexión de sus restaurantes que funcionan"
on public.mercado_pago for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen los cobros de la terminal de sus restaurantes que funcionan"
on public.cobros_terminal for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.cobros_terminal;
  end if;
end;
$$;


-- ─── Los ayudantes ────────────────────────────────────────────────────────────

-- ¿Puso su contraseña hace 5 minutos o menos? Lo dice el amr de la sesión: entrar con contraseña otra vez lo pone
-- al día, y renovar la sesión no.
create function privado.contrasena_reciente()
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from jsonb_array_elements(coalesce((select auth.jwt()) -> 'amr', '[]')) e
    where e ->> 'method' = 'password'
      and (e ->> 'timestamp') ~ '^[0-9]+$'
      and (e ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - 300
  );
$$;

-- ¿Esta cuenta tiene un cobro esperando en la terminal?
create function privado.cobro_esperando(p_venta_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.cobros_terminal
    where venta_id = p_venta_id and estado in ('mandando', 'esperando', 'revisar')
  );
$$;

-- ¿Esta sucursal tiene un cobro esperando en la terminal?
create function privado.sucursal_esperando(p_restaurante_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.cobros_terminal
    where restaurante_id = p_restaurante_id and estado in ('mandando', 'esperando', 'revisar')
  );
$$;

-- El gerente activo de esa sucursal, con su licencia funcionando, para lo que el Worker hace a su nombre.
create function privado.gerente_de(p_usuario_id uuid, p_restaurante_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.miembros m
  join public.restaurantes r on r.id = m.restaurante_id
  where m.usuario_id = p_usuario_id
    and m.restaurante_id = p_restaurante_id
    and m.activo
    and 'gerente' = any (m.roles)
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
$$;


-- ─── Los candados mientras un cobro espera ────────────────────────────────────
-- Con un cobro esperando, la cuenta no cambia por ningún lado: ni productos, ni cancelaciones, ni descuentos, ni
-- juntarla, ni otro pago o cancelar uno. Se puede cambiar de mesa y pedir la cuenta. La caja no se cierra y Mercado
-- Pago no se desconecta ni cambia de Point.

create function privado.candado_venta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.estado, new.subtotal, new.total, new.descuento_tipo, new.descuento_valor, new.descuento)
       is distinct from (old.estado, old.subtotal, old.total, old.descuento_tipo, old.descuento_valor, old.descuento)
     and privado.cobro_esperando(old.id) then
    raise exception 'Esta cuenta tiene un cobro esperando en la terminal' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger ventas_candado_terminal
before update on public.ventas
for each row execute function privado.candado_venta();

create function privado.candado_renglon()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and (new.venta_id, new.cantidad, new.precio_unitario, new.estado, new.descuento_tipo, new.descuento_valor)
         is not distinct from (old.venta_id, old.cantidad, old.precio_unitario, old.estado, old.descuento_tipo,
                               old.descuento_valor) then
    return new;
  end if;
  if (tg_op in ('UPDATE', 'DELETE') and privado.cobro_esperando(old.venta_id))
     or (tg_op in ('INSERT', 'UPDATE') and privado.cobro_esperando(new.venta_id)) then
    raise exception 'Esta cuenta tiene un cobro esperando en la terminal' using errcode = '55000';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger venta_items_candado_terminal
before insert or update or delete on public.venta_items
for each row execute function privado.candado_renglon();

create function privado.candado_pago()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if privado.cobro_esperando(new.venta_id) then
    raise exception 'Esta cuenta tiene un cobro esperando en la terminal' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger pagos_candado_terminal
before insert or update on public.pagos
for each row execute function privado.candado_pago();

create function privado.candado_turno()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.estado = 'abierto' and new.estado <> 'abierto' and privado.sucursal_esperando(old.restaurante_id) then
    raise exception 'Hay un cobro esperando en la terminal' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger turnos_candado_terminal
before update on public.turnos
for each row execute function privado.candado_turno();

create function privado.candado_conexion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (tg_op = 'DELETE' or (new.cuenta_id, new.terminal_id) is distinct from (old.cuenta_id, old.terminal_id))
     and privado.sucursal_esperando(old.restaurante_id) then
    raise exception 'No se puede desconectar mientras un cobro espera en la terminal' using errcode = '55000';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger mercado_pago_candado_terminal
before update or delete on public.mercado_pago
for each row execute function privado.candado_conexion();


-- ─── Anotar un pago ───────────────────────────────────────────────────────────
-- Lo que cobrar hacía después de revisar: anota el pago en el turno a nombre de p_miembro y, si cubre el total,
-- cierra la cuenta con el siguiente folio. Sin p_monto no anota pago (la cuenta de $0). Quien la llama ya revisó todo
-- y tiene la cuenta bloqueada.

create function privado.anotar_pago(
  p_venta_id bigint,
  p_miembro bigint,
  p_turno_id bigint,
  p_clave uuid,
  p_metodo text,
  p_monto numeric,
  p_propina numeric,
  p_recibido numeric,
  p_referencia text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_pago_id bigint;
  v_cambio numeric(12,2) := 0;
  v_folio integer;
begin
  select restaurante_id, folio, total, pagado into v_venta from public.ventas where id = p_venta_id;

  if p_monto is not null then
    insert into public.pagos (restaurante_id, venta_id, turno_id, metodo, monto, propina, recibido, referencia, cobrado_por, clave)
    values (v_venta.restaurante_id, p_venta_id, p_turno_id, p_metodo, p_monto, p_propina, p_recibido, p_referencia,
            p_miembro, p_clave)
    returning id, coalesce(cambio, 0) into v_pago_id, v_cambio;
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
    set estado = 'cerrada', folio = v_folio, cerrada_por = p_miembro, turno_id = p_turno_id, cerrada_at = now()
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


-- ─── Cobrar ───────────────────────────────────────────────────────────────────
-- Igual que en la migración caja; lo que anota ya lo hace privado.anotar_pago.

create or replace function public.cobrar(
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

    return privado.anotar_pago(p_venta_id, v_miembro, v_turno_id, p_clave, p_metodo, v_monto, v_propina, v_recibido,
                               v_referencia);
  elsif p_monto is not null then
    raise exception 'Esta cuenta ya no debe nada' using errcode = '22023';
  end if;

  return privado.anotar_pago(p_venta_id, v_miembro, v_turno_id, p_clave, null, null, null, null, null);
end;
$$;


-- ─── Cancelar un pago ─────────────────────────────────────────────────────────
-- privado.anular_pago es lo que cancelar_pago hacía después de revisar: cancela el pago, reabre la cuenta si estaba
-- cerrada y lo anota en la bitácora. cancelar_pago sigue igual, salvo que un pago de la terminal no se cancela aquí:
-- se devuelve con Mercado Pago (revisar_devolucion y pago_devuelto).

create function privado.anular_pago(
  p_pago_id bigint,
  p_miembro bigint,
  p_autoriza bigint,
  p_motivo text,
  p_terminal boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pago public.pagos;
  v_venta record;
begin
  select * into v_pago from public.pagos where id = p_pago_id;
  select id, restaurante_id, estado, folio into v_venta from public.ventas where id = v_pago.venta_id;

  update public.pagos
  set cancelado_at = now(), cancelado_por = p_miembro, autorizado_por = p_autoriza, cancelado_motivo = p_motivo
  where id = p_pago_id;
  if v_venta.estado = 'cerrada' then
    update public.ventas
    set estado = 'abierta', cerrada_por = null, turno_id = null, cerrada_at = null
    where id = v_venta.id;
  end if;

  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle)
  values (v_venta.restaurante_id, p_miembro, p_autoriza, 'cancelar_pago', 'pagos', p_pago_id::text,
          jsonb_build_object('venta_id', v_venta.id, 'folio', v_venta.folio, 'metodo', v_pago.metodo,
                             'monto', v_pago.monto, 'propina', v_pago.propina, 'motivo', p_motivo,
                             'reabierta', v_venta.estado = 'cerrada')
          || case when p_terminal then jsonb_build_object('terminal', true) else '{}'::jsonb end);
  return v_venta.estado = 'cerrada';
end;
$$;

-- Lo que se revisa antes de cancelar un pago o devolverlo: que exista, sea de un turno abierto y no esté cancelado.
-- Regresa el pago bloqueado, con su cuenta bloqueada antes.
create function privado.pago_para_cancelar(p_pago_id bigint)
returns public.pagos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pago public.pagos;
begin
  select * into v_pago
  from public.pagos
  where id = p_pago_id and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Ese pago ya no está' using errcode = '23503';
  end if;

  perform 1 from public.ventas where id = v_pago.venta_id and restaurante_id = v_pago.restaurante_id for update;
  select * into v_pago from public.pagos where id = p_pago_id for update;
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
  return v_pago;
end;
$$;

create or replace function public.cancelar_pago(
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
  v_miembro bigint;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_aut jsonb;
  v_autoriza bigint;
  v_reabierta boolean;
begin
  v_pago := privado.pago_para_cancelar(p_pago_id);
  v_miembro := privado.mi_miembro(v_pago.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cancelan' using errcode = '42501';
  end if;
  if exists (select 1 from public.cobros_terminal where pago_id = p_pago_id) then
    raise exception 'Ese pago se cobró en la terminal: se cancela devolviendo el dinero' using errcode = '55000';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;

  v_aut := privado.autoriza(v_pago.restaurante_id, v_miembro, p_autoriza_id, p_pin_mezclado);
  if not (v_aut ->> 'ok')::boolean then
    return v_aut;
  end if;
  v_autoriza := (v_aut ->> 'autoriza')::bigint;

  v_reabierta := privado.anular_pago(p_pago_id, v_miembro, v_autoriza, v_motivo);
  return jsonb_build_object('ok', true, 'autoriza', v_autoriza, 'reabierta', v_reabierta);
end;
$$;


-- ─── La conexión, desde el panel del gerente ──────────────────────────────────
-- Conectar, cambiar o desconectar la cuenta pide la contraseña otra vez (5 minutos). Elegir la Point o el ticket, no.

-- Antes de mandarlo a Mercado Pago: el Worker pregunta con la sesión del gerente y, si sí, le da su pase.
create function public.puedo_conectar_mercado_pago(p_restaurante_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_restaurante_id is null or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo los gerentes de esta sucursal conectan Mercado Pago' using errcode = '42501';
  end if;
  if not privado.contrasena_reciente() then
    raise exception 'Vuelve a escribir tu contraseña' using errcode = '42501';
  end if;
  if privado.sucursal_esperando(p_restaurante_id) then
    raise exception 'No se puede cambiar la cuenta mientras un cobro espera en la terminal' using errcode = '55000';
  end if;
  return (select auth.uid());
end;
$$;

create function public.desconectar_mercado_pago(p_restaurante_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conexion public.mercado_pago;
begin
  if p_restaurante_id is null or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo los gerentes de esta sucursal desconectan Mercado Pago' using errcode = '42501';
  end if;
  if not privado.contrasena_reciente() then
    raise exception 'Vuelve a escribir tu contraseña' using errcode = '42501';
  end if;

  delete from public.mercado_pago where restaurante_id = p_restaurante_id returning * into v_conexion;
  if found then
    insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
    values (p_restaurante_id, privado.mi_miembro(p_restaurante_id, array['gerente']), 'desconectar_mercado_pago',
            'mercado_pago', p_restaurante_id::text, jsonb_build_object('cuenta_nombre', v_conexion.cuenta_nombre));
  end if;
end;
$$;

create function public.fijar_imprimir_ticket(p_restaurante_id uuid, p_imprimir boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_restaurante_id is null or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo los gerentes de esta sucursal cambian el ticket' using errcode = '42501';
  end if;
  if p_imprimir is null then
    raise exception 'Elige si imprime o no' using errcode = '22023';
  end if;
  update public.mercado_pago set imprimir_ticket = p_imprimir where restaurante_id = p_restaurante_id;
  if not found then
    raise exception 'Mercado Pago no está conectado en esta sucursal' using errcode = '55000';
  end if;
end;
$$;

-- Ver las Point de la cuenta o ligar una: el Worker pregunta con la sesión del gerente.
create function public.puedo_ver_terminales(p_restaurante_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_restaurante_id is null or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo los gerentes de esta sucursal eligen su Point' using errcode = '42501';
  end if;
  if not exists (select 1 from public.mercado_pago where restaurante_id = p_restaurante_id and desconectada_at is null) then
    raise exception 'Mercado Pago no está conectado en esta sucursal' using errcode = '55000';
  end if;
  return true;
end;
$$;


-- ─── La conexión, para el Worker ──────────────────────────────────────────────

-- Guarda el pase que lleva a Mercado Pago y borra los vencidos.
create function public.guardar_pase_mercado_pago(
  p_huella text,
  p_usuario_id uuid,
  p_restaurante_id uuid,
  p_verificador text,
  p_origen text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.pases_mercado_pago where vence_at <= now();
  if privado.gerente_de(p_usuario_id, p_restaurante_id) is null then
    raise exception 'Solo los gerentes de esta sucursal conectan Mercado Pago' using errcode = '42501';
  end if;
  insert into public.pases_mercado_pago (huella, restaurante_id, usuario_id, verificador, origen, vence_at)
  values (p_huella, p_restaurante_id, p_usuario_id, p_verificador, p_origen, now() + interval '10 minutes');
end;
$$;

-- El pase de regreso: sirve una vez. Usado, vencido o inventado: null.
create function public.usar_pase_mercado_pago(p_huella text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pase public.pases_mercado_pago;
begin
  delete from public.pases_mercado_pago where huella = p_huella returning * into v_pase;
  if not found or v_pase.vence_at <= now() then
    return null;
  end if;
  return jsonb_build_object('restaurante_id', v_pase.restaurante_id, 'usuario_id', v_pase.usuario_id,
                            'verificador', v_pase.verificador, 'origen', v_pase.origen);
end;
$$;

-- Guarda la conexión y sus llaves. Si la cuenta tiene una sola Point libre, la liga sola y lo dice (ligada), para que
-- el Worker la ponga en modo de punto de venta. Si cambia de cuenta, la Point anterior se suelta.
create function public.conectar_mercado_pago(
  p_usuario_id uuid,
  p_restaurante_id uuid,
  p_cuenta_id text,
  p_cuenta_nombre text,
  p_acceso text,
  p_renovar text,
  p_version smallint,
  p_vence_at timestamptz,
  p_terminales text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.gerente_de(p_usuario_id, p_restaurante_id);
  v_antes public.mercado_pago;
  v_terminal text;
  v_libres text[];
  v_ligada boolean := false;
begin
  if v_miembro is null then
    raise exception 'Solo los gerentes de esta sucursal conectan Mercado Pago' using errcode = '42501';
  end if;

  select * into v_antes from public.mercado_pago where restaurante_id = p_restaurante_id for update;
  if found and v_antes.cuenta_id = p_cuenta_id and v_antes.terminal_id = any (coalesce(p_terminales, '{}')) then
    v_terminal := v_antes.terminal_id;
  else
    select coalesce(array_agg(t), '{}') into v_libres
    from unnest(coalesce(p_terminales, '{}')) t
    where not exists (select 1 from public.mercado_pago m where m.terminal_id = t and m.restaurante_id <> p_restaurante_id);
    if cardinality(v_libres) = 1 and cardinality(p_terminales) = 1 then
      v_terminal := v_libres[1];
      v_ligada := true;
    end if;
  end if;

  insert into public.mercado_pago (restaurante_id, cuenta_id, cuenta_nombre, terminal_id)
  values (p_restaurante_id, p_cuenta_id, p_cuenta_nombre, v_terminal)
  on conflict (restaurante_id) do update
  set cuenta_id = excluded.cuenta_id, cuenta_nombre = excluded.cuenta_nombre, terminal_id = excluded.terminal_id,
      conectada_at = now(), desconectada_at = null;

  insert into public.llaves_mercado_pago (restaurante_id, acceso, renovar, version, vence_at)
  values (p_restaurante_id, p_acceso, p_renovar, p_version, p_vence_at)
  on conflict (restaurante_id) do update
  set acceso = excluded.acceso, renovar = excluded.renovar, version = excluded.version, vence_at = excluded.vence_at;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (p_restaurante_id, v_miembro, 'conectar_mercado_pago', 'mercado_pago', p_restaurante_id::text,
          jsonb_build_object('cuenta_nombre', p_cuenta_nombre));

  return jsonb_build_object('terminal_id', v_terminal, 'ligada', v_ligada);
end;
$$;

-- Las llaves de una sucursal conectada, para el Worker (null si no está conectada).
create function public.llaves_de_mercado_pago(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('restaurante_id', m.restaurante_id, 'cuenta_id', m.cuenta_id, 'terminal_id', m.terminal_id,
                            'acceso', l.acceso, 'renovar', l.renovar, 'version', l.version, 'vence_at', l.vence_at)
  from public.mercado_pago m
  join public.llaves_mercado_pago l on l.restaurante_id = m.restaurante_id
  where m.restaurante_id = p_restaurante_id and m.desconectada_at is null;
$$;

-- Las llaves de una cuenta de Mercado Pago (cualquiera de sus sucursales conectadas), para revisar un aviso.
create function public.llaves_por_cuenta(p_cuenta_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.llaves_de_mercado_pago(m.restaurante_id)
  from public.mercado_pago m
  join public.llaves_mercado_pago l on l.restaurante_id = m.restaurante_id
  where m.cuenta_id = p_cuenta_id and m.desconectada_at is null
  order by l.vence_at desc
  limit 1;
$$;

-- De las Point de la cuenta, en qué otra sucursal está cada una (las que no están en otra no salen).
create function public.terminales_en_otra_sucursal(p_restaurante_id uuid, p_terminales text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m.terminal_id, r.nombre), '{}')
  from public.mercado_pago m
  join public.restaurantes r on r.id = m.restaurante_id
  where m.terminal_id = any (coalesce(p_terminales, '{}')) and m.restaurante_id <> p_restaurante_id;
$$;

-- Liga una Point (el Worker ya revisó que es de la cuenta). null la suelta: dejó de aparecer en la cuenta.
create function public.ligar_terminal(p_restaurante_id uuid, p_terminal_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_terminal_id is not null
     and exists (select 1 from public.mercado_pago where terminal_id = p_terminal_id and restaurante_id <> p_restaurante_id) then
    raise exception 'Esa Point ya está en otra sucursal' using errcode = '23505';
  end if;
  update public.mercado_pago set terminal_id = nullif(btrim(p_terminal_id), '')
  where restaurante_id = p_restaurante_id and desconectada_at is null;
  if not found then
    raise exception 'Mercado Pago no está conectado en esta sucursal' using errcode = '55000';
  end if;
end;
$$;

-- Mercado Pago ya no acepta las llaves (quitaron el permiso o vencieron): «Se desconectó». Las llaves se borran.
create function public.mercado_pago_se_desconecto(p_restaurante_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.mercado_pago set desconectada_at = now()
  where restaurante_id = p_restaurante_id and desconectada_at is null;
  delete from public.llaves_mercado_pago where restaurante_id = p_restaurante_id;
end;
$$;

-- Las conexiones a las que les faltan 30 días o menos, para el Cron diario.
create function public.llaves_por_renovar()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(public.llaves_de_mercado_pago(l.restaurante_id) order by l.vence_at), '[]')
  from public.llaves_mercado_pago l
  join public.mercado_pago m on m.restaurante_id = l.restaurante_id
  where m.desconectada_at is null and l.vence_at <= now() + interval '30 days';
$$;

-- Las llaves nuevas de una renovación (o con otra versión de la llave de cifrado).
create function public.guardar_llaves_mercado_pago(
  p_restaurante_id uuid,
  p_acceso text,
  p_renovar text,
  p_version smallint,
  p_vence_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.llaves_mercado_pago
  set acceso = p_acceso, renovar = p_renovar, version = p_version, vence_at = p_vence_at
  where restaurante_id = p_restaurante_id;
  return found;
end;
$$;


-- ─── Mandar un cobro a la terminal ────────────────────────────────────────────
-- Con la sesión de quien cobra (mesero, caja o gerente), como cobrar: aparta el cobro antes de mandarlo. p_monto es
-- la parte de la cuenta, sin la propina; a la terminal va con ella, y debe ser $5.00 o más. Con la misma clave
-- regresa el mismo cobro, para que el Worker lo vuelva a mandar si se perdió la respuesta. Si la sucursal ya tiene
-- un cobro esperando, no aparta nada: {ok:false, motivo:'ocupada'}.

create function public.apartar_cobro_terminal(
  p_venta_id bigint,
  p_clave uuid,
  p_monto numeric,
  p_propina_porcentaje integer default null,
  p_propina numeric default null
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
  v_terminal text;
  v_falta numeric(12,2);
  v_monto numeric(12,2) := round(p_monto, 2);
  v_propina numeric(12,2);
  v_cobro public.cobros_terminal;
begin
  if p_clave is null then
    raise exception 'Falta la clave del cobro' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_clave::text, 3));
  select * into v_cobro
  from public.cobros_terminal
  where clave = p_clave and restaurante_id in (select privado.mis_restaurantes());
  if found then
    return jsonb_build_object('ok', true, 'cobro_id', v_cobro.id, 'estado', v_cobro.estado, 'motivo', v_cobro.motivo,
                              'orden_id', v_cobro.orden_id, 'monto', v_cobro.monto, 'terminal_id', v_cobro.terminal_id);
  end if;

  select id, restaurante_id, total, pagado into v_venta
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

  select terminal_id into v_terminal
  from public.mercado_pago
  where restaurante_id = v_venta.restaurante_id and desconectada_at is null;
  if not found then
    raise exception 'Mercado Pago no está conectado en esta sucursal' using errcode = '55000';
  end if;
  if v_terminal is null then
    raise exception 'Esta sucursal todavía no tiene su Point' using errcode = '55000';
  end if;

  v_turno_id := privado.turno_abierto(v_venta.restaurante_id);
  if v_turno_id is null then
    raise exception 'La caja no está abierta' using errcode = '55000';
  end if;
  if privado.cobro_esperando(p_venta_id) then
    raise exception 'Esta cuenta tiene un cobro esperando en la terminal' using errcode = '55000';
  end if;

  v_falta := v_venta.total - v_venta.pagado;
  if v_monto is null or v_monto <= 0 then
    raise exception 'Escribe cuánto paga' using errcode = '22023';
  end if;
  if v_monto > v_falta then
    raise exception 'No puede pasar de lo que falta (%)', privado.pesos(v_falta) using errcode = '22023';
  end if;
  v_propina := privado.propina(v_monto, p_propina_porcentaje, p_propina);
  if v_monto + v_propina < 5 then
    raise exception 'Menos de $5.00 no se puede mandar a la terminal' using errcode = '22023';
  end if;

  if privado.sucursal_esperando(v_venta.restaurante_id) then
    return jsonb_build_object('ok', false, 'motivo', 'ocupada');
  end if;

  insert into public.cobros_terminal (restaurante_id, venta_id, clave, mandado_por, turno_id, monto, propina,
                                      terminal_id, vence_at)
  values (v_venta.restaurante_id, p_venta_id, p_clave, v_miembro, v_turno_id, v_monto + v_propina, v_propina,
          v_terminal, now() + interval '5 minutes')
  returning * into v_cobro;

  return jsonb_build_object('ok', true, 'cobro_id', v_cobro.id, 'estado', v_cobro.estado, 'motivo', null,
                            'orden_id', null, 'monto', v_cobro.monto, 'terminal_id', v_cobro.terminal_id);
end;
$$;

-- Antes de revisar o cancelar un cobro: revisar lo puede cualquiera que cobre en esa sucursal; cancelarlo, quien lo
-- mandó, la caja o el gerente. Regresa la sucursal.
create function public.puedo_tocar_cobro(p_cobro_id bigint, p_para text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cobro public.cobros_terminal;
  v_miembro bigint;
begin
  select * into v_cobro
  from public.cobros_terminal
  where id = p_cobro_id and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Ese cobro ya no está' using errcode = '23503';
  end if;
  v_miembro := privado.mi_miembro(v_cobro.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cobran' using errcode = '42501';
  end if;
  if p_para = 'cancelar' then
    if v_miembro <> v_cobro.mandado_por
       and privado.mi_miembro(v_cobro.restaurante_id, array['caja', 'gerente']) is null then
      raise exception 'Lo cancela quien lo mandó, la caja o el gerente' using errcode = '42501';
    end if;
  elsif p_para is distinct from 'revisar' then
    raise exception 'Solo se revisa o se cancela' using errcode = '22023';
  end if;
  return v_cobro.restaurante_id;
end;
$$;

-- Lo que el Worker necesita de un cobro para mandarlo, revisarlo o cancelarlo, con las llaves de su sucursal.
create function public.cobro_para_el_worker(p_cobro_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('cobro_id', c.id, 'restaurante_id', c.restaurante_id, 'estado', c.estado,
                            'motivo', c.motivo, 'orden_id', c.orden_id, 'monto', c.monto, 'terminal_id', c.terminal_id,
                            'tomado', c.tomado_at is not null, 'vence_at', c.vence_at)
         || coalesce(jsonb_build_object('llaves', public.llaves_de_mercado_pago(c.restaurante_id)), '{}')
  from public.cobros_terminal c
  where c.id = p_cobro_id;
$$;

-- Lo que el ticket de la Point dice de una cuenta cerrada: el restaurante, la cuenta, quién atendió, los productos,
-- el descuento, la propina, el total y el folio.
create function privado.ticket_de_venta(p_venta_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'restaurante', r.nombre,
    'cuenta', privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero),
    'atendio', a.nombre,
    'renglones', coalesce((
      select jsonb_agg(jsonb_build_object('cantidad', i.cantidad, 'nombre', i.nombre, 'importe', i.importe)
                       order by i.created_at, i.id)
      from public.venta_items i
      where i.venta_id = v.id and i.estado = 'activo'), '[]'),
    'descuento', (v.subtotal - v.total)::numeric(12,2),
    'propina', coalesce((
      select sum(p.propina) from public.pagos p where p.venta_id = v.id and p.cancelado_at is null), 0)::numeric(12,2),
    'total', v.total,
    'folio', v.folio,
    'cerrada_at', v.cerrada_at,
    'zona', r.zona_horaria
  )
  from public.ventas v
  join public.restaurantes r on r.id = v.restaurante_id
  left join public.miembros a on a.restaurante_id = v.restaurante_id and a.id = v.abierta_por
  where v.id = p_venta_id;
$$;

-- Lo que pasó con un cobro, según Mercado Pago (o el Worker). Es el único lugar que lo mueve, y cada cobro deja de
-- esperar una sola vez: un aviso repetido lo encuentra hecho y no cambia nada (cambio: false).
--   esperando: la orden existe (guarda su número) · tomado: la Point ya lo tomó · pagado: con su monto, que debe ser
--   el del cobro; anota el pago a nombre de quien lo mandó y, si la cuenta se cierra y el ticket está prendido,
--   regresa el ticket · no_se_cobro: con su motivo · revisar: Mercado Pago no sabe si se pagó.
-- La orden debe ser la del cobro y la cuenta de Mercado Pago, la de su sucursal.
create function public.resultado_cobro(
  p_cobro_id bigint,
  p_cuenta_id text,
  p_orden_id text,
  p_estado text,
  p_motivo text default null,
  p_monto numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cobro public.cobros_terminal;
  v_cuenta text;
  v_imprimir boolean;
  v_pago jsonb;
  v_ticket jsonb;
begin
  select * into v_cobro from public.cobros_terminal where id = p_cobro_id for update;
  if not found then
    raise exception 'Ese cobro no existe' using errcode = '23503';
  end if;
  select cuenta_id, imprimir_ticket into v_cuenta, v_imprimir
  from public.mercado_pago where restaurante_id = v_cobro.restaurante_id;
  if v_cuenta is distinct from p_cuenta_id then
    raise exception 'Ese cobro no es de esa cuenta de Mercado Pago' using errcode = '42501';
  end if;
  -- Sin orden solo se dice que no se cobró, y solo si Mercado Pago nunca la creó.
  if (p_orden_id is null and not (p_estado = 'no_se_cobro' and v_cobro.orden_id is null))
     or (v_cobro.orden_id is not null and v_cobro.orden_id <> p_orden_id) then
    raise exception 'Esa orden no es de ese cobro' using errcode = '22023';
  end if;
  if p_estado is null or p_estado not in ('esperando', 'tomado', 'pagado', 'no_se_cobro', 'revisar') then
    raise exception 'Ese estado no existe' using errcode = '22023';
  end if;

  if v_cobro.estado not in ('mandando', 'esperando', 'revisar') then
    return jsonb_build_object('cambio', false, 'estado', v_cobro.estado, 'motivo', v_cobro.motivo,
                              'venta_id', v_cobro.venta_id, 'restaurante_id', v_cobro.restaurante_id);
  end if;

  if p_estado in ('esperando', 'tomado') then
    if v_cobro.estado = 'revisar' then
      return jsonb_build_object('cambio', false, 'estado', v_cobro.estado, 'motivo', null,
                                'venta_id', v_cobro.venta_id, 'restaurante_id', v_cobro.restaurante_id);
    end if;
    update public.cobros_terminal
    set orden_id = p_orden_id, estado = 'esperando',
        tomado_at = case when p_estado = 'tomado' then coalesce(tomado_at, now()) else tomado_at end
    where id = p_cobro_id
    returning * into v_cobro;
    return jsonb_build_object('cambio', true, 'estado', v_cobro.estado, 'motivo', null, 'tomado', v_cobro.tomado_at is not null,
                              'venta_id', v_cobro.venta_id, 'restaurante_id', v_cobro.restaurante_id);
  end if;

  if p_estado = 'revisar' then
    update public.cobros_terminal set orden_id = p_orden_id, estado = 'revisar' where id = p_cobro_id;
    return jsonb_build_object('cambio', v_cobro.estado <> 'revisar', 'estado', 'revisar', 'motivo', null,
                              'venta_id', v_cobro.venta_id, 'restaurante_id', v_cobro.restaurante_id);
  end if;

  if p_estado = 'no_se_cobro' then
    if p_motivo is null or p_motivo not in ('rechazada', 'vencida', 'cancelada', 'cancelada_terminal', 'ocupada',
                                            'sin_conexion') then
      raise exception 'Ese motivo no existe' using errcode = '22023';
    end if;
    update public.cobros_terminal
    set orden_id = coalesce(p_orden_id, orden_id), estado = 'no_se_cobro', motivo = p_motivo, terminado_at = now()
    where id = p_cobro_id;
    return jsonb_build_object('cambio', true, 'estado', 'no_se_cobro', 'motivo', p_motivo,
                              'venta_id', v_cobro.venta_id, 'restaurante_id', v_cobro.restaurante_id);
  end if;

  -- pagado
  if p_monto is null or round(p_monto, 2) <> v_cobro.monto then
    raise exception 'El monto de la orden no es el del cobro' using errcode = '22023';
  end if;
  perform 1 from public.ventas where id = v_cobro.venta_id for update;
  update public.cobros_terminal
  set orden_id = p_orden_id, estado = 'pagado', tomado_at = coalesce(tomado_at, now()), terminado_at = now()
  where id = p_cobro_id;
  v_pago := privado.anotar_pago(v_cobro.venta_id, v_cobro.mandado_por, v_cobro.turno_id, gen_random_uuid(), 'tarjeta',
                                v_cobro.monto - v_cobro.propina, v_cobro.propina, null, p_orden_id);
  update public.cobros_terminal set pago_id = (v_pago ->> 'pago_id')::bigint where id = p_cobro_id;

  if (v_pago ->> 'cerrada')::boolean and v_imprimir then
    v_ticket := privado.ticket_de_venta(v_cobro.venta_id);
  end if;
  return jsonb_build_object('cambio', true, 'estado', 'pagado', 'motivo', null, 'venta_id', v_cobro.venta_id,
                            'restaurante_id', v_cobro.restaurante_id, 'cerrada', (v_pago ->> 'cerrada')::boolean,
                            'folio', v_pago -> 'folio', 'ticket', v_ticket);
end;
$$;

-- «Revisa la terminal»: lo resuelve quien lo mandó, sin PIN. Sí se pagó anota el pago; no se pagó lo termina sin
-- cobrar. Queda en la bitácora.
create function public.confirmar_cobro_terminal(p_cobro_id bigint, p_pagado boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cobro public.cobros_terminal;
  v_miembro bigint;
  v_pago jsonb;
begin
  select * into v_cobro
  from public.cobros_terminal
  where id = p_cobro_id and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Ese cobro ya no está' using errcode = '23503';
  end if;
  v_miembro := privado.mi_miembro(v_cobro.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null or v_miembro <> v_cobro.mandado_por then
    raise exception 'Lo resuelve quien lo mandó' using errcode = '42501';
  end if;
  if p_pagado is null then
    raise exception 'Elige si se pagó o no' using errcode = '22023';
  end if;

  perform 1 from public.ventas where id = v_cobro.venta_id for update;
  select * into v_cobro from public.cobros_terminal where id = p_cobro_id for update;
  if v_cobro.estado <> 'revisar' then
    raise exception 'Ese cobro ya no está por revisar' using errcode = '55000';
  end if;

  if p_pagado then
    update public.cobros_terminal
    set estado = 'pagado', tomado_at = coalesce(tomado_at, now()), terminado_at = now(), confirmado_por = v_miembro
    where id = p_cobro_id;
    v_pago := privado.anotar_pago(v_cobro.venta_id, v_cobro.mandado_por, v_cobro.turno_id, gen_random_uuid(),
                                  'tarjeta', v_cobro.monto - v_cobro.propina, v_cobro.propina, null, v_cobro.orden_id);
    update public.cobros_terminal set pago_id = (v_pago ->> 'pago_id')::bigint where id = p_cobro_id;
  else
    update public.cobros_terminal
    set estado = 'no_se_cobro', motivo = 'cancelada', terminado_at = now(), confirmado_por = v_miembro
    where id = p_cobro_id;
  end if;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_cobro.restaurante_id, v_miembro, 'confirmar_terminal', 'cobros_terminal', p_cobro_id::text,
          jsonb_build_object('venta_id', v_cobro.venta_id, 'pagado', p_pagado, 'monto', v_cobro.monto,
                             'orden_id', v_cobro.orden_id));

  return jsonb_build_object('estado', case when p_pagado then 'pagado' else 'no_se_cobro' end,
                            'cerrada', coalesce((v_pago ->> 'cerrada')::boolean, false), 'folio', v_pago -> 'folio');
end;
$$;


-- ─── Devolver un pago de la terminal ──────────────────────────────────────────
-- Como cancelar un pago, con el PIN de la caja o el gerente, y solo del turno abierto. Primero revisar_devolucion,
-- con la sesión de quien cancela (por el Worker, que mezcla el PIN): revisa todo y aparta la devolución. Luego el
-- Worker la pide a Mercado Pago, y solo si dice que sí, pago_devuelto cancela el pago. Si no salió,
-- devolucion_no_salio la suelta.

create function public.revisar_devolucion(
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
  v_cobro public.cobros_terminal;
  v_miembro bigint;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_aut jsonb;
begin
  v_pago := privado.pago_para_cancelar(p_pago_id);
  v_miembro := privado.mi_miembro(v_pago.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante cancelan' using errcode = '42501';
  end if;
  select * into v_cobro from public.cobros_terminal where pago_id = p_pago_id for update;
  if not found then
    raise exception 'Ese pago no se cobró en la terminal' using errcode = '55000';
  end if;
  if v_cobro.devuelto_at is not null then
    raise exception 'Ese pago ya se devolvió' using errcode = '55000';
  end if;
  if privado.cobro_esperando(v_pago.venta_id) then
    raise exception 'Esta cuenta tiene un cobro esperando en la terminal' using errcode = '55000';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo' using errcode = '22023';
  end if;

  v_aut := privado.autoriza(v_pago.restaurante_id, v_miembro, p_autoriza_id, p_pin_mezclado);
  if not (v_aut ->> 'ok')::boolean then
    return v_aut;
  end if;

  update public.cobros_terminal set devuelto_desde = 'sistema' where id = v_cobro.id;
  return jsonb_build_object('ok', true, 'autoriza', (v_aut ->> 'autoriza')::bigint, 'miembro', v_miembro,
                            'cobro_id', v_cobro.id, 'orden_id', v_cobro.orden_id, 'monto', v_cobro.monto,
                            'motivo', v_motivo);
end;
$$;

-- Mercado Pago ya devolvió el dinero: el pago se cancela (y la cuenta se reabre si estaba cerrada).
create function public.pago_devuelto(p_cobro_id bigint, p_miembro bigint, p_autoriza bigint, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cobro public.cobros_terminal;
  v_reabierta boolean;
begin
  select * into v_cobro from public.cobros_terminal where id = p_cobro_id;
  if not found or v_cobro.pago_id is null then
    raise exception 'Ese cobro no tiene pago' using errcode = '23503';
  end if;
  perform 1 from public.ventas where id = v_cobro.venta_id for update;
  select * into v_cobro from public.cobros_terminal where id = p_cobro_id for update;
  if v_cobro.devuelto_at is not null then
    return jsonb_build_object('ok', true, 'reabierta', false);
  end if;

  update public.cobros_terminal
  set devuelto_desde = 'sistema', devuelto_at = now(), devuelto_monto = monto
  where id = p_cobro_id;
  v_reabierta := privado.anular_pago(v_cobro.pago_id, p_miembro, p_autoriza, p_motivo, true);
  return jsonb_build_object('ok', true, 'reabierta', v_reabierta);
end;
$$;

create function public.devolucion_no_salio(p_cobro_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.cobros_terminal set devuelto_desde = null
  where id = p_cobro_id and devuelto_at is null and devuelto_desde = 'sistema';
$$;

-- El aviso de una devolución que Don Chuy hizo desde su app de Mercado Pago: queda en la bitácora y en Cortes y
-- reportes del día en que llegó. No cancela el pago ni reabre la cuenta. Una devolución del sistema (apartada o hecha)
-- no se cuenta otra vez.
create function public.devuelto_desde_mercado_pago(p_cobro_id bigint, p_cuenta_id text, p_orden_id text, p_monto numeric)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cobro public.cobros_terminal;
  v_venta record;
begin
  select * into v_cobro from public.cobros_terminal where id = p_cobro_id for update;
  if not found or v_cobro.orden_id is distinct from p_orden_id then
    raise exception 'Esa orden no es de ese cobro' using errcode = '22023';
  end if;
  if (select cuenta_id from public.mercado_pago where restaurante_id = v_cobro.restaurante_id) is distinct from p_cuenta_id then
    raise exception 'Ese cobro no es de esa cuenta de Mercado Pago' using errcode = '42501';
  end if;
  if v_cobro.estado <> 'pagado' or v_cobro.devuelto_desde is not null then
    return false;
  end if;
  if p_monto is null or p_monto <= 0 or round(p_monto, 2) > v_cobro.monto then
    raise exception 'Ese monto no se pudo devolver' using errcode = '22023';
  end if;

  update public.cobros_terminal
  set devuelto_desde = 'mercado_pago', devuelto_at = now(), devuelto_monto = round(p_monto, 2)
  where id = p_cobro_id;
  select folio into v_venta from public.ventas where id = v_cobro.venta_id;
  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_cobro.restaurante_id, null, 'devuelto_mercado_pago', 'cobros_terminal', p_cobro_id::text,
          jsonb_build_object('venta_id', v_cobro.venta_id, 'folio', v_venta.folio, 'monto', round(p_monto, 2),
                             'orden_id', p_orden_id));
  return true;
end;
$$;


-- ─── Cortes y reportes ────────────────────────────────────────────────────────
-- Igual que en la migración adaptabilidad, y entre los otros cambios del día, «Devuelto desde Mercado Pago» del día
-- en que llegó el aviso.

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
                      'pago_id', x.pago_id, 'folio', x.folio, 'cuenta', x.cuenta, 'metodo', x.metodo,
                      'monto', x.monto, 'propina', x.propina, 'motivo', x.motivo, 'pidio_id', x.pidio_id,
                      'pidio', x.pidio, 'autorizo_id', x.autorizo_id, 'autorizo', x.autorizo,
                      'cancelado_at', x.cancelado_at)
                      order by x.cancelado_at, x.pago_id)
             from privado.pagos_cancelados_del_rango(p_restaurante_id, v_dia, v_dia) x
             where x.turno_id = t.id), '[]'))
           order by t.created_at, t.id), '[]')
  into v_turnos
  from privado.turnos_del_rango(p_restaurante_id, v_dia, v_dia) t;

  select jsonb_build_object(
    'total', coalesce(sum(d.descuento), 0)::numeric(12,2),
    'cuentas', count(distinct d.venta_id),
    'lista', coalesce(jsonb_agg(jsonb_build_object(
               'venta_id', d.venta_id, 'folio', d.folio, 'tipo', d.tipo, 'cuenta', d.cuenta,
               'renglon_id', d.renglon_id, 'nombre', d.nombre, 'cantidad', d.cantidad,
               'descuento_tipo', d.descuento_tipo, 'descuento_valor', d.descuento_valor,
               'descuento', d.descuento, 'motivo', d.motivo,
               'pidio_id', d.pidio_id, 'pidio', d.pidio, 'autorizo_id', d.autorizo_id,
               'autorizo', d.autorizo, 'created_at', d.created_at)
               order by d.created_at nulls last, d.venta_id, d.renglon_id nulls first), '[]')
  )
  into v_descuentos
  from privado.descuentos_del_rango(p_restaurante_id, v_dia, v_dia) d;

  select jsonb_build_object(
    'total', coalesce(sum(c.importe), 0)::numeric(12,2),
    'renglones', count(*) filter (where c.que = 'renglon'),
    'cuentas', count(*) filter (where c.que = 'cuenta'),
    'lista', coalesce(jsonb_agg(jsonb_build_object(
               'que', c.que, 'venta_id', c.venta_id, 'folio', c.folio, 'tipo', c.tipo, 'cuenta', c.cuenta,
               'estado', c.estado, 'renglon_id', c.renglon_id, 'nombre', c.nombre, 'cantidad', c.cantidad,
               'importe', c.importe, 'motivo', c.motivo, 'pidio_id', c.pidio_id, 'pidio', c.pidio,
               'autorizo_id', c.autorizo_id, 'autorizo', c.autorizo, 'created_at', c.created_at)
               order by c.created_at, c.venta_id, c.renglon_id nulls first), '[]')
  )
  into v_cancelaciones
  from privado.cancelaciones_del_rango(p_restaurante_id, v_dia, v_dia) c;

  select coalesce(jsonb_agg(jsonb_build_object(
           'accion', b.accion, 'detalle', b.detalle, 'cuenta', privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero),
           'quien', q.nombre, 'created_at', b.created_at)
           order by b.created_at, b.id), '[]')
  into v_otros
  from public.bitacora b
  left join public.miembros q on q.restaurante_id = b.restaurante_id and q.id = b.miembro_id
  cross join lateral (
    select coalesce((b.detalle ->> 'venta_id')::bigint,
                    case when b.tabla = 'ventas' then b.registro_id::bigint end) as venta_id
  ) x
  left join public.ventas v on v.restaurante_id = b.restaurante_id and v.id = x.venta_id
  where b.restaurante_id = p_restaurante_id
    and ((b.accion in ('cambiar_mesa', 'juntar_mesas', 'quitar_descuento')
          and x.venta_id in (select c.id from privado.cuentas_del_dia(p_restaurante_id, v_dia, v_dia) c))
      or (b.accion in ('cambiar_hora_corte', 'devuelto_mercado_pago')
          and b.created_at >= v_desde and b.created_at < v_hasta));

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


-- ─── Quién ejecuta qué ────────────────────────────────────────────────────────

revoke execute on function
  privado.contrasena_reciente(),
  privado.cobro_esperando(bigint),
  privado.sucursal_esperando(uuid),
  privado.gerente_de(uuid, uuid),
  privado.candado_venta(),
  privado.candado_renglon(),
  privado.candado_pago(),
  privado.candado_turno(),
  privado.candado_conexion(),
  privado.anotar_pago(bigint, bigint, bigint, uuid, text, numeric, numeric, numeric, text),
  privado.anular_pago(bigint, bigint, bigint, text, boolean),
  privado.pago_para_cancelar(bigint),
  privado.ticket_de_venta(bigint)
from public, anon, authenticated, service_role;

revoke execute on function
  public.puedo_conectar_mercado_pago(uuid),
  public.desconectar_mercado_pago(uuid),
  public.fijar_imprimir_ticket(uuid, boolean),
  public.puedo_ver_terminales(uuid),
  public.apartar_cobro_terminal(bigint, uuid, numeric, integer, numeric),
  public.puedo_tocar_cobro(bigint, text),
  public.confirmar_cobro_terminal(bigint, boolean),
  public.revisar_devolucion(bigint, text, bigint, text)
from public, anon, service_role;

grant execute on function
  public.puedo_conectar_mercado_pago(uuid),
  public.desconectar_mercado_pago(uuid),
  public.fijar_imprimir_ticket(uuid, boolean),
  public.puedo_ver_terminales(uuid),
  public.apartar_cobro_terminal(bigint, uuid, numeric, integer, numeric),
  public.puedo_tocar_cobro(bigint, text),
  public.confirmar_cobro_terminal(bigint, boolean),
  public.revisar_devolucion(bigint, text, bigint, text)
to authenticated;

revoke execute on function
  public.guardar_pase_mercado_pago(text, uuid, uuid, text, text),
  public.usar_pase_mercado_pago(text),
  public.conectar_mercado_pago(uuid, uuid, text, text, text, text, smallint, timestamptz, text[]),
  public.llaves_de_mercado_pago(uuid),
  public.llaves_por_cuenta(text),
  public.terminales_en_otra_sucursal(uuid, text[]),
  public.ligar_terminal(uuid, text),
  public.mercado_pago_se_desconecto(uuid),
  public.llaves_por_renovar(),
  public.guardar_llaves_mercado_pago(uuid, text, text, smallint, timestamptz),
  public.cobro_para_el_worker(bigint),
  public.resultado_cobro(bigint, text, text, text, text, numeric),
  public.pago_devuelto(bigint, bigint, bigint, text),
  public.devolucion_no_salio(bigint),
  public.devuelto_desde_mercado_pago(bigint, text, text, numeric)
from public, anon, authenticated;

grant execute on function
  public.guardar_pase_mercado_pago(text, uuid, uuid, text, text),
  public.usar_pase_mercado_pago(text),
  public.conectar_mercado_pago(uuid, uuid, text, text, text, text, smallint, timestamptz, text[]),
  public.llaves_de_mercado_pago(uuid),
  public.llaves_por_cuenta(text),
  public.terminales_en_otra_sucursal(uuid, text[]),
  public.ligar_terminal(uuid, text),
  public.mercado_pago_se_desconecto(uuid),
  public.llaves_por_renovar(),
  public.guardar_llaves_mercado_pago(uuid, text, text, smallint, timestamptz),
  public.cobro_para_el_worker(bigint),
  public.resultado_cobro(bigint, text, text, text, text, numeric),
  public.pago_devuelto(bigint, bigint, bigint, text),
  public.devolucion_no_salio(bigint),
  public.devuelto_desde_mercado_pago(bigint, text, text, numeric)
to service_role;
