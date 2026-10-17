-- Cuentas y comandas: la parte 4a del punto de venta (libreta 5; libreta 2, Diccionario de datos,
-- escrito el 17 de octubre de 2026; maqueta Mesero y cocina TYq97pKacRCYBqcvRp1bZ2).
--
-- El mesero anota en su celular y nada se guarda hasta «Mandar a cocina»: mandar_a_cocina abre
-- la cuenta si hace falta, guarda los renglones con los precios del menú y crea una comanda por
-- área. La cocina marca cada comanda «Lista» o la regresa (marcar_comanda). La cuenta se pide
-- (pedir_cuenta), se cambia de mesa (cambiar_mesa) o se junta con otra (juntar_mesas), y esas dos
-- quedan en la bitácora. Nadie escribe directo en ventas, venta_items, comandas ni bitacora: todos
-- los del restaurante las leen (la bitácora, solo el gerente) y solo las funciones las escriben.
-- El total lo recalcula un trigger; nadie lo escribe.
--
-- El cobro, el folio y el turno llegan con la parte 4b; las cancelaciones y los descuentos con
-- PIN, con la 4c. Por eso aquí no hay todavía folio, pagos ni renglones cancelados.


-- ─── productos: el IVA ────────────────────────────────────────────────────────
-- Cada producto nace con 16 % y cada renglón lo copia al mandarse. Sin pantalla ni permiso de
-- escritura: la pantalla llega con Facturación (decidido el 17 de octubre de 2026).

alter table public.productos
  add column tasa_iva numeric(4,2) not null default 16
    constraint productos_tasa_iva_valida check (tasa_iva >= 0 and tasa_iva < 100);


-- ─── ventas ───────────────────────────────────────────────────────────────────
-- Cada cuenta del punto de venta (y, con la pieza 6, cada pedido del menú en línea). Nace con el
-- primer «Mandar a cocina», nunca vacía. created_at es la apertura: la fecha de los reportes.

create table public.ventas (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  origen text not null default 'punto_de_venta'
    constraint ventas_origen_valido check (origen in ('punto_de_venta', 'menu_en_linea')),
  tipo text not null
    constraint ventas_tipo_valido check (tipo in ('mesa', 'para_llevar', 'domicilio')),
  mesa_id bigint,
  mesa_nombre text,
  cliente_nombre text,
  cliente_telefono text,
  cliente_direccion text,
  estado text not null default 'abierta'
    constraint ventas_estado_valido check (estado in ('abierta', 'cerrada', 'cancelada')),
  total numeric(12,2) not null default 0 constraint ventas_total_valido check (total >= 0),
  abierta_por bigint,
  cuenta_pedida_at timestamptz,
  cancelada_motivo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, mesa_id) references public.mesas (restaurante_id, id),
  foreign key (restaurante_id, abierta_por) references public.miembros (restaurante_id, id),
  constraint ventas_mesa_segun_tipo check ((tipo = 'mesa') = (mesa_id is not null)),
  constraint ventas_mesa_nombre check (tipo <> 'mesa' or coalesce(btrim(mesa_nombre), '') <> ''),
  constraint ventas_cliente_nombre check (tipo = 'mesa' or coalesce(btrim(cliente_nombre), '') <> ''),
  constraint ventas_domicilio check (
    case when tipo = 'domicilio'
      then coalesce(btrim(cliente_telefono), '') <> '' and coalesce(btrim(cliente_direccion), '') <> ''
      else cliente_telefono is null and cliente_direccion is null
    end
  ),
  constraint ventas_cancelada_motivo check (estado <> 'cancelada' or coalesce(btrim(cancelada_motivo), '') <> '')
);

-- Una sola cuenta abierta por mesa. Las de para llevar no tienen mesa y no chocan.
create unique index ventas_una_abierta_por_mesa
on public.ventas (restaurante_id, mesa_id)
where estado = 'abierta';

-- Los reportes suman las cerradas por fecha de apertura.
create index ventas_cerradas_por_fecha
on public.ventas (restaurante_id, created_at)
where estado = 'cerrada';

create index ventas_mesa_idx on public.ventas (restaurante_id, mesa_id);
create index ventas_abierta_por_idx on public.ventas (restaurante_id, abierta_por);

create trigger ventas_updated_at
before update on public.ventas
for each row execute function privado.set_updated_at();


-- ─── comandas ─────────────────────────────────────────────────────────────────
-- Cada envío a un área. No se borra nunca, solo cambia de estado: el tiempo real de Supabase no
-- revisa RLS en los borrados. created_at es la hora en que se envió.

create table public.comandas (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  venta_id bigint not null,
  area_preparacion_id bigint not null,
  estado text not null default 'pendiente'
    constraint comandas_estado_valido check (estado in ('pendiente', 'lista')),
  enviada_por bigint,
  lista_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, area_preparacion_id) references public.areas_preparacion (restaurante_id, id),
  foreign key (restaurante_id, enviada_por) references public.miembros (restaurante_id, id),
  constraint comandas_lista_at check ((estado = 'lista') = (lista_at is not null))
);

create index comandas_venta_idx on public.comandas (restaurante_id, venta_id);
create index comandas_area_idx on public.comandas (restaurante_id, area_preparacion_id);
create index comandas_enviada_por_idx on public.comandas (restaurante_id, enviada_por);

create trigger comandas_updated_at
before update on public.comandas
for each row execute function privado.set_updated_at();


-- ─── venta_items ──────────────────────────────────────────────────────────────
-- Cada renglón de una cuenta. Nace al mandarse a cocina, con su copia del nombre, del precio y
-- de las opciones de ese momento: cambiar el menú después no toca las ventas pasadas.

create table public.venta_items (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  venta_id bigint not null,
  producto_id bigint not null,
  nombre text not null check (btrim(nombre) <> ''),
  precio_unitario numeric(12,2) not null constraint venta_items_precio_valido check (precio_unitario >= 0),
  cantidad integer not null constraint venta_items_cantidad_valida check (cantidad > 0),
  importe numeric(12,2) generated always as (cantidad * precio_unitario) stored,
  opciones jsonb not null default '[]'
    constraint venta_items_opciones_lista check (jsonb_typeof(opciones) = 'array'),
  nota text,
  tasa_iva numeric(4,2) not null
    constraint venta_items_tasa_iva_valida check (tasa_iva >= 0 and tasa_iva < 100),
  comanda_id bigint,
  agregado_por bigint,
  clave_envio uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, producto_id) references public.productos (restaurante_id, id),
  foreign key (restaurante_id, comanda_id) references public.comandas (restaurante_id, id),
  foreign key (restaurante_id, agregado_por) references public.miembros (restaurante_id, id)
);

create index venta_items_venta_idx on public.venta_items (restaurante_id, venta_id);
create index venta_items_producto_idx on public.venta_items (restaurante_id, producto_id);
create index venta_items_comanda_idx on public.venta_items (restaurante_id, comanda_id);
create index venta_items_agregado_por_idx on public.venta_items (restaurante_id, agregado_por);
create index venta_items_clave_envio_idx on public.venta_items (restaurante_id, clave_envio);

create trigger venta_items_updated_at
before update on public.venta_items
for each row execute function privado.set_updated_at();

-- El total de la cuenta es la suma de sus renglones. Lo recalcula este trigger cada vez que un
-- renglón entra, cambia o pasa a otra cuenta (juntar mesas); nadie más lo escribe. No corre al
-- borrar: un renglón nunca se borra, y el borrado en cascada de un restaurante no lo necesita.
create function privado.recalcular_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ventas v
  set total = coalesce((
    select sum(i.importe) from public.venta_items i
    where i.restaurante_id = v.restaurante_id and i.venta_id = v.id
  ), 0)
  where v.restaurante_id = new.restaurante_id
    and (v.id = new.venta_id or (tg_op = 'UPDATE' and v.id = old.venta_id));
  return null;
end;
$$;

create trigger venta_items_recalcular_total
after insert or update of cantidad, precio_unitario, venta_id on public.venta_items
for each row execute function privado.recalcular_total();


-- ─── bitacora ─────────────────────────────────────────────────────────────────
-- Un registro que nadie edita ni borra. Lo escriben las funciones; solo el gerente lo lee. La
-- lista de acciones crece con cada parte: la 4b suma retiros e ingresos, y la 4c las
-- cancelaciones y los descuentos.

create table public.bitacora (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  miembro_id bigint,
  autorizado_por bigint,
  accion text not null
    constraint bitacora_accion_valida check (accion in ('cambiar_mesa', 'juntar_mesas')),
  tabla text not null check (btrim(tabla) <> ''),
  registro_id text not null check (btrim(registro_id) <> ''),
  detalle jsonb not null default '{}'
    constraint bitacora_detalle_objeto check (jsonb_typeof(detalle) = 'object'),
  created_at timestamptz not null default now(),
  foreign key (restaurante_id, miembro_id) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, autorizado_por) references public.miembros (restaurante_id, id)
);

create index bitacora_fecha_idx on public.bitacora (restaurante_id, created_at);
create index bitacora_miembro_idx on public.bitacora (restaurante_id, miembro_id);
create index bitacora_autorizado_por_idx on public.bitacora (restaurante_id, autorizado_por);


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. Todos los del restaurante leen cuentas, renglones y
-- comandas, también la cocina (así el tiempo real no necesita funciones aparte, y un precio no
-- es secreto para el taquero). La bitácora solo la lee el gerente. Nadie escribe directo.

alter table public.ventas enable row level security;
alter table public.comandas enable row level security;
alter table public.venta_items enable row level security;
alter table public.bitacora enable row level security;

revoke all on table public.ventas, public.comandas, public.venta_items, public.bitacora
from anon, authenticated;
revoke all on sequence public.ventas_id_seq, public.comandas_id_seq, public.venta_items_id_seq,
  public.bitacora_id_seq
from anon, authenticated;

grant select (
  id, restaurante_id, origen, tipo, mesa_id, mesa_nombre, cliente_nombre, cliente_telefono,
  cliente_direccion, estado, total, abierta_por, cuenta_pedida_at, cancelada_motivo, created_at,
  updated_at
) on public.ventas to authenticated;

grant select (
  id, restaurante_id, venta_id, area_preparacion_id, estado, enviada_por, lista_at, created_at,
  updated_at
) on public.comandas to authenticated;

grant select (
  id, restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, importe, opciones,
  nota, tasa_iva, comanda_id, agregado_por, clave_envio, created_at, updated_at
) on public.venta_items to authenticated;

grant select (
  id, restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle, created_at
) on public.bitacora to authenticated;

create policy "Los miembros leen las cuentas de sus restaurantes que funcionan"
on public.ventas for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen las comandas de sus restaurantes que funcionan"
on public.comandas for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "Los miembros leen los renglones de sus restaurantes que funcionan"
on public.venta_items for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

create policy "El gerente lee la bitácora de sus restaurantes que funcionan"
on public.bitacora for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()));

-- Las mesas y la cocina se actualizan con el tiempo real de Supabase, filtrado por restaurante.
-- Supabase revisa RLS en cada evento y para cada suscriptor. La publicación solo existe en
-- Supabase; en la base de pruebas no.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.ventas, public.venta_items, public.comandas;
  end if;
end;
$$;


-- ─── Quién es quien llama ─────────────────────────────────────────────────────
-- El id de miembro de quien llama en ese restaurante, si es activo, tiene alguno de esos roles,
-- el restaurante funciona hoy y (si no es gerente) entra desde su aparato. Si no, vacío.

create function privado.mi_miembro(p_restaurante_id uuid, p_roles text[])
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.miembros m
  where m.usuario_id = (select auth.uid())
    and m.restaurante_id = p_restaurante_id
    and m.activo
    and m.roles && p_roles
    and p_restaurante_id in (select privado.mis_restaurantes());
$$;

revoke execute on function
  privado.recalcular_total(),
  privado.mi_miembro(uuid, text[])
from public, anon, authenticated, service_role;


-- ─── Mandar a cocina ──────────────────────────────────────────────────────────
-- Guarda todo un envío junto. La cuenta es la que ya está abierta (p_venta_id), la de esa mesa
-- (p_mesa_id: la abierta, o una nueva si está libre) o un pedido nuevo para llevar o a domicilio
-- (p_tipo con el cliente). Cada renglón trae producto_id, cantidad, opciones (ids) y nota; el
-- precio lo pone esta función con el menú de este momento. Una comanda por área; lo que no va a
-- ningún área («Lo sirve el mesero») entra a la cuenta sin comanda. Con la misma clave no hace
-- nada dos veces: regresa la misma cuenta. Regresa el id de la cuenta.

create function public.mandar_a_cocina(
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
    on conflict (restaurante_id, mesa_id) where estado = 'abierta' do nothing
    returning id into v_venta_id;
    if v_venta_id is null then
      select id into v_venta_id
      from public.ventas
      where restaurante_id = p_restaurante_id and mesa_id = p_mesa_id and estado = 'abierta'
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


-- ─── Pedir la cuenta ──────────────────────────────────────────────────────────
-- La mesa sale como «Pidió la cuenta» para todos.

create function public.pedir_cuenta(p_venta_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select restaurante_id into v_restaurante_id
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  if privado.mi_miembro(v_restaurante_id, array['mesero', 'caja', 'gerente']) is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante piden la cuenta' using errcode = '42501';
  end if;

  update public.ventas set cuenta_pedida_at = now() where id = p_venta_id;
end;
$$;


-- ─── Marcar una comanda ───────────────────────────────────────────────────────
-- Un toque: «Lista». Si se equivocó, la regresa a pendiente. No se guarda quién la marcó.

create function public.marcar_comanda(p_comanda_id bigint, p_lista boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  select restaurante_id into v_restaurante_id
  from public.comandas
  where id = p_comanda_id and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa comanda ya no está' using errcode = '23503';
  end if;
  if privado.mi_miembro(v_restaurante_id, array['cocina', 'gerente']) is null then
    raise exception 'Solo la cocina y los gerentes de este restaurante marcan comandas' using errcode = '42501';
  end if;
  if p_lista is null then
    raise exception 'La comanda solo se marca lista o se regresa' using errcode = '22023';
  end if;

  update public.comandas
  set estado = case when p_lista then 'lista' else 'pendiente' end,
      lista_at = case when p_lista then coalesce(lista_at, now()) end
  where id = p_comanda_id;
end;
$$;


-- ─── Cambiar de mesa ──────────────────────────────────────────────────────────
-- Pasa la cuenta, con todo lo que lleva, a una mesa libre. No toca precios, así que no pide
-- PIN, pero queda en la bitácora.

create function public.cambiar_mesa(p_venta_id bigint, p_mesa_id bigint)
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
  select id, restaurante_id, tipo, mesa_id, mesa_nombre into v_venta
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


-- ─── Juntar mesas ─────────────────────────────────────────────────────────────
-- Pasa todo lo de una cuenta (renglones y comandas) a la de otra mesa. La primera queda vacía y
-- cancelada con su motivo, y su mesa libre. No toca precios ni pide PIN; queda en la bitácora.
-- Con la parte 4b se suma la regla de que una cuenta con pagos no se junta.

create function public.juntar_mesas(p_venta_id bigint, p_destino_id bigint)
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

  select id, restaurante_id, tipo, mesa_nombre into v_origen
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

  update public.venta_items set venta_id = p_destino_id
  where restaurante_id = v_origen.restaurante_id and venta_id = p_venta_id;
  update public.comandas set venta_id = p_destino_id
  where restaurante_id = v_origen.restaurante_id and venta_id = p_venta_id;
  update public.ventas
  set estado = 'cancelada', cancelada_motivo = 'Se juntó con «' || v_destino.mesa_nombre || '»'
  where id = p_venta_id;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_origen.restaurante_id, v_miembro, 'juntar_mesas', 'ventas', p_venta_id::text,
          jsonb_build_object('de', v_origen.mesa_nombre, 'a', v_destino.mesa_nombre, 'a_venta', p_destino_id));
end;
$$;


-- ─── Eliminar mesa, con la cuenta abierta ─────────────────────────────────────
-- Una mesa con la cuenta abierta no se elimina (decidido el 17 de octubre de 2026). Ya libre,
-- se borra si nunca tuvo ventas y se archiva si ya tuvo: la llave de ventas lo decide.

create or replace function public.eliminar_mesa(p_mesa_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_nombre text;
begin
  select restaurante_id, nombre into v_restaurante_id, v_nombre
  from public.mesas
  where id = p_mesa_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar sus mesas' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.ventas
    where restaurante_id = v_restaurante_id and mesa_id = p_mesa_id and estado = 'abierta'
  ) then
    raise exception '% tiene una cuenta abierta. Cóbrala o cámbiala de mesa antes de eliminarla.', v_nombre
      using errcode = '55000';
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
  public.mandar_a_cocina(uuid, uuid, jsonb, bigint, bigint, text, text, text, text),
  public.pedir_cuenta(bigint),
  public.marcar_comanda(bigint, boolean),
  public.cambiar_mesa(bigint, bigint),
  public.juntar_mesas(bigint, bigint)
from public, anon, service_role;

grant execute on function
  public.mandar_a_cocina(uuid, uuid, jsonb, bigint, bigint, text, text, text, text),
  public.pedir_cuenta(bigint),
  public.marcar_comanda(bigint, boolean),
  public.cambiar_mesa(bigint, bigint),
  public.juntar_mesas(bigint, bigint)
to authenticated;
