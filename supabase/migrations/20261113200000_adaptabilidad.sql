-- Adaptabilidad (libreta 2, Diccionario rev 120; las encuestas 2, 3 y 6 del 12 de noviembre de 2026): el
-- sistema se acomoda solo a cualquier local, por lo que tiene, sin interruptores.
--
-- «Comer aquí»: una cuenta sin mesa que se come en el local, como en un mostrador; sale también donde hay
-- mesas. El nombre del cliente es opcional en toda cuenta sin mesa: sin nombre, la cuenta toma el número
-- corto del día («#23») del mismo contador de folios que los pedidos del menú en línea, así la cocina nunca
-- ve dos «#12» el mismo día. Con nombre no toma número, como hoy. Un restaurante nuevo nace sin áreas (todo
-- se entrega directo) y también se puede quedar sin ninguna; los de antes conservan las suyas.
--
-- No hay tablas ni columnas nuevas. cobrar y confirmar_pedido no cambian.


-- ─── ventas: «Comer aquí» y el nombre opcional ────────────────────────────────
-- Una cuenta sin mesa lleva nombre, número o los dos (los del menú en línea). El número va en toda cuenta
-- del menú en línea, nunca en una de mesa. Comer aquí no lleva teléfono ni dirección: ventas_domicilio ya
-- los deja vacíos fuera de domicilio y para llevar.

alter table public.ventas
  drop constraint ventas_tipo_valido,
  add constraint ventas_tipo_valido check (tipo in ('mesa', 'comer_aqui', 'para_llevar', 'domicilio')),
  drop constraint ventas_cliente_nombre,
  add constraint ventas_cliente_nombre
    check (tipo = 'mesa' or coalesce(btrim(cliente_nombre), '') <> '' or pedido_numero is not null),
  drop constraint ventas_pedido_numero,
  add constraint ventas_pedido_numero check (
    (pedido_numero is null and origen = 'punto_de_venta')
    or (pedido_numero is not null and pedido_numero > 0 and tipo <> 'mesa')
  );


-- ─── El número corto del día ──────────────────────────────────────────────────

-- El siguiente número corto del día de negocio p_dia, o el 1 si es el primero. Uno solo para los pedidos
-- del menú en línea y las cuentas sin mesa y sin nombre del punto de venta. El upsert bloquea la fila de
-- folios: dos cuentas nunca sacan el mismo.
create function privado.numero_del_dia(p_restaurante_id uuid, p_dia date)
returns integer
language sql
set search_path = ''
as $$
  insert into public.folios (restaurante_id, pedidos_dia, pedidos_ultimo)
  values (p_restaurante_id, p_dia, 1)
  on conflict (restaurante_id) do update
  set pedidos_dia = excluded.pedidos_dia,
      pedidos_ultimo = case
        when public.folios.pedidos_dia = excluded.pedidos_dia then public.folios.pedidos_ultimo + 1
        -- Un día que vuelve (si cambió la hora de corte) sigue después de su último número, de los pedidos
        -- y de las cuentas del punto de venta.
        else greatest(
          coalesce((select max(p.numero) from public.pedidos_en_linea p
                    where p.restaurante_id = excluded.restaurante_id and p.dia = excluded.pedidos_dia), 0),
          coalesce((select max(v.pedido_numero)
                    from privado.cuentas_del_dia(excluded.restaurante_id, excluded.pedidos_dia, excluded.pedidos_dia) v
                    where v.origen = 'punto_de_venta'), 0)
        ) + 1
      end
  returning pedidos_ultimo;
$$;

-- Cómo se llama una cuenta en los reportes, la bitácora y el agente: su mesa, el nombre del cliente o su
-- número del día. «Mesa 4», «Sr. Ramírez» o «#23».
create function privado.nombre_de_cuenta(p_mesa text, p_cliente text, p_numero integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_mesa, p_cliente, '#' || p_numero);
$$;

revoke execute on function
  privado.numero_del_dia(uuid, date),
  privado.nombre_de_cuenta(text, text, integer)
from public, anon, authenticated, service_role;


-- ─── «Mandar a cocina» ────────────────────────────────────────────────────────
-- Como en la migración pedidos, y además «Comer aquí» y el nombre opcional en toda cuenta sin mesa (también
-- a domicilio, que sigue pidiendo teléfono y dirección). Reemplazarla conserva sus permisos.
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
  v_numero integer;
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
    if p_tipo is null or p_tipo not in ('comer_aqui', 'para_llevar', 'domicilio') then
      raise exception 'Elige una mesa, comer aquí, para llevar o domicilio' using errcode = '22023';
    end if;
    if p_tipo = 'domicilio' and (v_telefono is null or v_direccion is null) then
      raise exception 'Para domicilio escribe el teléfono y la dirección' using errcode = '22023';
    end if;
    -- Sin nombre, la cuenta se llama con el número corto del día: «#23».
    if v_nombre is null then
      v_numero := privado.numero_del_dia(p_restaurante_id, (
        select privado.dia_de_negocio(r.zona_horaria, r.hora_corte)
        from public.restaurantes r
        where r.id = p_restaurante_id));
    end if;
    insert into public.ventas (
      restaurante_id, tipo, cliente_nombre, cliente_telefono, cliente_direccion, pedido_numero, abierta_por
    ) values (
      p_restaurante_id, p_tipo, v_nombre,
      case when p_tipo = 'domicilio' then v_telefono end,
      case when p_tipo = 'domicilio' then v_direccion end,
      v_numero, v_miembro
    )
    returning id into v_venta_id;
  end if;

  -- Los renglones, en el orden en que llegan.
  for v_renglon in select value from jsonb_array_elements(p_renglones) loop
    if jsonb_typeof(v_renglon) <> 'object' then
      raise exception 'Cada renglón va con su producto y su cantidad' using errcode = '22023';
    end if;

    select p.id, p.nombre, p.precio, p.tasa_iva, p.visible, p.es_envio, c.area_preparacion_id
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

    -- Una comanda por área en este envío. El costo de envío no llega a la cocina.
    v_comanda_id := null;
    if v_producto.area_preparacion_id is not null and not v_producto.es_envio then
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


-- ─── «Hacer pedido» ───────────────────────────────────────────────────────────
-- Como en la migración tu_menu_en_linea; su número corto sale de privado.numero_del_dia, el contador que
-- comparte con el punto de venta.
create or replace function public.hacer_pedido(
  p_slug text,
  p_clave uuid,
  p_tipo text,
  p_cliente_nombre text,
  p_cliente_telefono text,
  p_cliente_direccion text,
  p_cliente_referencias text,
  p_paga_con numeric,
  p_renglones jsonb,
  p_marca_celular text,
  p_marca_conexion text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r public.restaurantes;
  v_pedido_id bigint;
  v_dia date;
  v_numero integer;
  v_nombre text := btrim(coalesce(p_cliente_nombre, ''));
  v_telefono text := nullif(regexp_replace(coalesce(p_cliente_telefono, ''), '[\s().-]', '', 'g'), '');
  v_direccion text := nullif(btrim(p_cliente_direccion), '');
  v_referencias text := nullif(btrim(p_cliente_referencias), '');
  v_paga_con numeric(12,2) := round(p_paga_con, 2);
  v_renglon jsonb;
  v_i bigint;
  v_producto record;
  v_grupo record;
  v_cantidad integer;
  v_nota text;
  v_visto numeric;
  v_opciones bigint[];
  v_agotada text;
  v_valido boolean;
  v_extra numeric(12,2);
  v_copia jsonb;
  v_precio numeric(12,2);
  v_cambios jsonb := '[]';
  v_lineas jsonb := '[]';
  v_linea jsonb;
  v_total numeric(12,2) := 0;
begin
  select * into v_r
  from public.restaurantes r
  where r.slug = lower(btrim(p_slug))
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'no_recibe');
  end if;
  if p_clave is null then
    raise exception 'Falta la clave del pedido' using errcode = '22023';
  end if;

  -- Un pedido a la vez en cada restaurante: el número corto y los límites no se pisan, y el
  -- mismo «Hacer pedido» dos veces (doble toque, se cortó el internet) se guarda una vez.
  perform pg_advisory_xact_lock(hashtextextended('pedidos:' || v_r.id::text, 0));
  select id into v_pedido_id
  from public.pedidos_en_linea
  where restaurante_id = v_r.id and clave = p_clave;
  if found then
    return jsonb_build_object('ok', true) || privado.pedido_en_json(v_pedido_id);
  end if;

  if not privado.recibe_pedidos(v_r.id) then
    return jsonb_build_object('ok', false, 'motivo', 'no_recibe');
  end if;
  if p_tipo is null or p_tipo not in ('para_llevar', 'domicilio') then
    raise exception 'Elige para llevar o a domicilio' using errcode = '22023';
  end if;
  if p_tipo = 'domicilio' and not v_r.hace_envios then
    raise exception 'Por ahora no hacemos envíos. Puedes pedir para llevar.' using errcode = '22023';
  end if;

  -- Los límites, en cada restaurante: 3 por hora desde un celular y 10 desde una conexión.
  if coalesce(p_marca_celular, '') !~ '^[0-9a-f]{64}$' or coalesce(p_marca_conexion, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'Faltan las marcas del pedido' using errcode = '22023';
  end if;
  if (select count(*) from public.pedidos_en_linea
      where restaurante_id = v_r.id and marca_celular = p_marca_celular
        and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Ya mandaste 3 pedidos en la última hora. Si quieres algo más, escríbele al restaurante por WhatsApp.'
      using errcode = '22023';
  end if;
  if (select count(*) from public.pedidos_en_linea
      where restaurante_id = v_r.id and marca_conexion = p_marca_conexion
        and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Desde esta conexión ya se mandaron 10 pedidos en la última hora. Si quieres algo más, escríbele al restaurante por WhatsApp.'
      using errcode = '22023';
  end if;

  -- Quién lo pide: su nombre y su teléfono, también para llevar (así la caja le puede llamar si su
  -- mensaje no llegó); a domicilio, además, la dirección y con cuánto paga.
  if v_nombre = '' then
    raise exception 'Escribe tu nombre y apellido' using errcode = '22023';
  end if;
  if char_length(v_nombre) > 60 then
    raise exception 'Tu nombre puede tener hasta 60 letras' using errcode = '22023';
  end if;
  if v_telefono is null or v_telefono !~ '^[0-9]{10}$' then
    raise exception 'Tu teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
  end if;
  if p_tipo = 'domicilio' then
    if v_direccion is null then
      raise exception 'Escribe la dirección para el envío' using errcode = '22023';
    end if;
    if char_length(v_direccion) > 200 then
      raise exception 'La dirección puede tener hasta 200 letras' using errcode = '22023';
    end if;
    if char_length(v_referencias) > 120 then
      raise exception 'Las referencias pueden tener hasta 120 letras' using errcode = '22023';
    end if;
    if v_paga_con <= 0 then
      raise exception 'Escribe con cuánto pagas, como 500' using errcode = '22023';
    end if;
  else
    v_direccion := null;
    v_referencias := null;
    v_paga_con := null;
  end if;

  if p_renglones is null or jsonb_typeof(p_renglones) <> 'array' or jsonb_array_length(p_renglones) = 0 then
    raise exception 'Tu pedido está vacío' using errcode = '22023';
  end if;
  if jsonb_array_length(p_renglones) > 30 then
    raise exception 'Un pedido lleva hasta 30 renglones' using errcode = '22023';
  end if;

  -- Cada renglón, revisado con el menú de este momento: lo que ya no se puede pedir y lo que
  -- cambió de precio se juntan en cambios, y entonces no se guarda nada.
  for v_renglon, v_i in select value, ordinality from jsonb_array_elements(p_renglones) with ordinality loop
    if jsonb_typeof(v_renglon) <> 'object' then
      raise exception 'Cada renglón va con su producto y su cantidad' using errcode = '22023';
    end if;
    v_cantidad := (v_renglon ->> 'cantidad')::integer;
    if v_cantidad is null or v_cantidad < 1 or v_cantidad > 99 then
      raise exception 'Pide de 1 a 99 de cada producto' using errcode = '22023';
    end if;
    v_nota := nullif(btrim(v_renglon ->> 'nota'), '');
    if char_length(v_nota) > 140 then
      raise exception 'Cada nota puede tener hasta 140 letras' using errcode = '22023';
    end if;
    v_visto := (v_renglon ->> 'precio')::numeric;
    if v_visto is null then
      raise exception 'Falta el precio de un renglón' using errcode = '22023';
    end if;
    if jsonb_typeof(coalesce(v_renglon -> 'opciones', '[]')) <> 'array' then
      raise exception 'Las opciones de cada renglón van en una lista' using errcode = '22023';
    end if;
    v_opciones := array(
      select distinct x::bigint from jsonb_array_elements_text(coalesce(v_renglon -> 'opciones', '[]')) as x
    );

    -- Lo que el menú ya no enseña (oculto, archivado, agotado por un grupo, o un envío).
    select p.id, p.nombre, p.precio into v_producto
    from public.productos p
    where p.restaurante_id = v_r.id
      and p.id = (v_renglon ->> 'producto_id')::bigint
      and p.id in (select privado.productos_a_la_vista(v_r.id));
    if not found then
      v_cambios := v_cambios || jsonb_build_array(jsonb_build_object('renglon', v_i, 'cambio', 'agotado'));
      continue;
    end if;

    -- Cada opción elegida es de un grupo que lleva este producto.
    if exists (
      select 1 from unnest(v_opciones) as e (id)
      where not exists (
        select 1
        from public.opciones o
        join public.producto_grupos pg on pg.restaurante_id = o.restaurante_id and pg.grupo_id = o.grupo_id
        where o.restaurante_id = v_r.id and o.id = e.id and pg.producto_id = v_producto.id
      )
    ) then
      v_cambios := v_cambios || jsonb_build_array(jsonb_build_object('renglon', v_i, 'cambio', 'opciones'));
      continue;
    end if;

    select o.nombre into v_agotada
    from public.opciones o
    where o.restaurante_id = v_r.id and o.id = any (v_opciones) and not o.visible
    order by o.orden, o.id
    limit 1;
    if found then
      v_cambios := v_cambios || jsonb_build_array(
        jsonb_build_object('renglon', v_i, 'cambio', 'agotado', 'opcion', v_agotada));
      continue;
    end if;

    -- Cada grupo se elige entre su mínimo y su máximo.
    v_valido := true;
    for v_grupo in
      select g.minimo, g.maximo,
        (select count(*) from public.opciones o
         where o.restaurante_id = g.restaurante_id and o.grupo_id = g.id and o.id = any (v_opciones)) as elegidas
      from public.producto_grupos pg
      join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
      where pg.restaurante_id = v_r.id and pg.producto_id = v_producto.id
    loop
      if v_grupo.elegidas < v_grupo.minimo or v_grupo.elegidas > v_grupo.maximo then
        v_valido := false;
      end if;
    end loop;
    if not v_valido then
      v_cambios := v_cambios || jsonb_build_array(jsonb_build_object('renglon', v_i, 'cambio', 'opciones'));
      continue;
    end if;

    -- El precio del renglón y su copia de lo elegido, en el orden de los grupos, como en
    -- mandar_a_cocina.
    select
      coalesce(sum(o.precio_extra), 0),
      coalesce(jsonb_agg(
        jsonb_build_object('grupo', g.nombre, 'opcion', o.nombre, 'precio_extra', o.precio_extra)
        order by g.orden, g.id, o.orden, o.id
      ), '[]')
    into v_extra, v_copia
    from public.opciones o
    join public.grupos_opciones g on g.restaurante_id = o.restaurante_id and g.id = o.grupo_id
    where o.restaurante_id = v_r.id and o.id = any (v_opciones);

    v_precio := v_producto.precio + v_extra;
    if v_visto <> v_precio then
      v_cambios := v_cambios || jsonb_build_array(
        jsonb_build_object('renglon', v_i, 'cambio', 'precio', 'precio', v_precio));
    end if;
    v_total := v_total + v_precio * v_cantidad;
    v_lineas := v_lineas || jsonb_build_array(jsonb_build_object(
      'producto_id', v_producto.id, 'nombre', v_producto.nombre, 'precio_unitario', v_precio,
      'cantidad', v_cantidad, 'opciones', v_copia, 'nota', v_nota));
  end loop;

  if jsonb_array_length(v_cambios) > 0 then
    return jsonb_build_object('ok', false, 'motivo', 'cambios', 'cambios', v_cambios, 'total', v_total);
  end if;
  if v_total <= 0 then
    raise exception 'Tu pedido no tiene nada que cobrar' using errcode = '22023';
  end if;
  if v_paga_con < v_total then
    raise exception 'Con % no alcanza: tu pedido es de %', privado.pesos(v_paga_con), privado.pesos(v_total)
      using errcode = '22023';
  end if;

  -- El número corto: el siguiente del día de negocio, del mismo contador que las cuentas sin mesa y sin
  -- nombre del punto de venta.
  v_dia := privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte);
  v_numero := privado.numero_del_dia(v_r.id, v_dia);

  insert into public.pedidos_en_linea (
    restaurante_id, dia, numero, tipo, cliente_nombre, cliente_telefono, cliente_direccion,
    cliente_referencias, paga_con, total, clave, marca_celular, marca_conexion
  ) values (
    v_r.id, v_dia, v_numero, p_tipo, v_nombre, v_telefono, v_direccion,
    v_referencias, v_paga_con, v_total, p_clave, p_marca_celular, p_marca_conexion
  )
  returning id into v_pedido_id;

  for v_linea in select value from jsonb_array_elements(v_lineas) loop
    insert into public.pedido_items (
      restaurante_id, pedido_id, producto_id, nombre, precio_unitario, cantidad, opciones, nota
    ) values (
      v_r.id, v_pedido_id, (v_linea ->> 'producto_id')::bigint, v_linea ->> 'nombre',
      (v_linea ->> 'precio_unitario')::numeric, (v_linea ->> 'cantidad')::integer,
      v_linea -> 'opciones', v_linea ->> 'nota'
    );
  end loop;

  return jsonb_build_object('ok', true) || privado.pedido_en_json(v_pedido_id);
end;
$$;


-- ─── Nacer y quedarse sin áreas ───────────────────────────────────────────────
-- Un restaurante nuevo nace sin áreas: todo se entrega directo hasta que el gerente agrega la primera. Los de
-- antes conservan las suyas.

drop trigger restaurantes_nace_con_cocina on public.restaurantes;
drop function privado.nace_con_cocina();

-- «Eliminar área», como en la migración opciones, pero ya se puede eliminar la última: el restaurante se queda
-- sin áreas, como un mostrador sin cocina. Sigue sin dejar mientras alguna categoría vaya a ella.
create or replace function public.eliminar_area(p_area_id bigint)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_nombre text;
  v_categorias integer;
begin
  select restaurante_id, nombre into v_restaurante_id, v_nombre
  from public.areas_preparacion
  where id = p_area_id
    and archivado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  select count(*) into v_categorias
  from public.categorias
  where restaurante_id = v_restaurante_id
    and area_preparacion_id = p_area_id
    and archivado_at is null;
  if v_categorias = 1 then
    raise exception '% todavía tiene 1 categoría; cámbiala de área primero', v_nombre
      using errcode = '55000';
  elsif v_categorias > 1 then
    raise exception '% todavía tiene % categorías; cámbialas de área primero', v_nombre, v_categorias
      using errcode = '55000';
  end if;

  begin
    delete from public.areas_preparacion where id = p_area_id;
    return 'borrado';
  exception
    when foreign_key_violation then
      update public.areas_preparacion set archivado_at = now() where id = p_area_id;
      return 'archivado';
  end;
end;
$$;


-- ─── El nombre de la cuenta en la bitácora, los reportes y el agente ──────────
-- Donde se decía «coalesce(mesa, cliente)», ahora privado.nombre_de_cuenta: una cuenta sin nombre se llama
-- «#23». Y donde se decía el tipo en palabras, también «Comer aquí».

-- «Cancelar cuenta», como en la migración cancelaciones.
create or replace function public.cancelar_cuenta(
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
  select id, restaurante_id, tipo, mesa_nombre, cliente_nombre, pedido_numero, total, pagado into v_venta
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
          jsonb_build_object('cuenta', privado.nombre_de_cuenta(v_venta.mesa_nombre, v_venta.cliente_nombre,
                                                                v_venta.pedido_numero),
                             'total', v_venta.total, 'motivo', v_motivo));
  return jsonb_build_object('ok', true, 'autoriza', v_autoriza);
end;
$$;

-- Del agente (migración agente), todas como estaban salvo el nombre y el tipo.
create or replace function privado.ventas_agrupadas(
  p_restaurante_id uuid,
  p_desde date,
  p_hasta date,
  p_agrupar_por text,
  p_mesa_id bigint default null,
  p_tipo text default null,
  p_producto_id bigint default null,
  p_categoria_id bigint default null,
  p_dia_semana integer default null
)
returns table (clave text, etiqueta text, cuentas bigint, unidades bigint, importe numeric, dias bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte,
           privado.dia_de_negocio(zona_horaria, hora_corte) as hoy
    from public.restaurantes
    where id = p_restaurante_id
  ),
  cuentas as (
    select v.id, v.total, v.descuento, v.tipo, v.mesa_id, v.abierta_por, x.dia,
           extract(hour from v.created_at at time zone r.zona)::integer as hora
    from privado.cuentas_del_dia(p_restaurante_id, p_desde, p_hasta) v
    cross join r
    cross join lateral (select privado.dia_de_negocio(r.zona, r.corte, v.created_at) as dia) x
    where v.estado = 'cerrada'
      and (p_tipo is null or v.tipo = p_tipo)
      and (p_mesa_id is null or v.mesa_id = p_mesa_id)
      and (p_dia_semana is null or extract(isodow from x.dia) = p_dia_semana)
  ),
  modo as (
    select p_agrupar_por in ('producto', 'categoria') or p_producto_id is not null or p_categoria_id is not null
             as por_renglon
  ),
  filas as (
    -- Por cuenta: su total y sus piezas activas.
    select c.id as venta_id, c.dia, c.hora, c.tipo, c.mesa_id, c.abierta_por,
           null::bigint as producto_id, null::bigint as categoria_id,
           (select coalesce(sum(i.cantidad), 0) from public.venta_items i
            where i.restaurante_id = p_restaurante_id and i.venta_id = c.id and i.estado = 'activo') as unidades,
           c.total as importe, false as es_descuento
    from cuentas c
    where not (select por_renglon from modo)
    union all
    -- Por renglón: los activos, ya con su descuento.
    select c.id, c.dia, c.hora, c.tipo, c.mesa_id, c.abierta_por, i.producto_id, p.categoria_id,
           i.cantidad, i.importe, false
    from cuentas c
    join public.venta_items i on i.restaurante_id = p_restaurante_id and i.venta_id = c.id and i.estado = 'activo'
    join public.productos p on p.restaurante_id = p_restaurante_id and p.id = i.producto_id
    where (select por_renglon from modo)
      and (p_producto_id is null or i.producto_id = p_producto_id)
      and (p_categoria_id is null or p.categoria_id = p_categoria_id)
    union all
    -- El descuento a toda la cuenta, en su renglón, al agrupar por producto o categoría sin filtro.
    select c.id, c.dia, c.hora, c.tipo, c.mesa_id, c.abierta_por, null, null, 0, -c.descuento, true
    from cuentas c
    where p_agrupar_por in ('producto', 'categoria') and p_producto_id is null and p_categoria_id is null
      and c.descuento > 0
  ),
  etiquetadas as (
    select f.venta_id, f.dia, f.unidades, f.importe,
           case when f.es_descuento then 'descuento_cuenta' else
             case p_agrupar_por
               when 'total' then 'total'
               when 'dia' then to_char(f.dia, 'YYYY-MM-DD')
               when 'semana' then to_char((f.dia - (extract(isodow from f.dia)::integer - 1)), 'YYYY-MM-DD')
               when 'mes' then to_char(f.dia, 'YYYY-MM')
               when 'dia_semana' then extract(isodow from f.dia)::integer::text
               when 'hora' then f.hora::text
               when 'mesa' then case when f.tipo = 'mesa' then f.mesa_id::text else f.tipo end
               when 'mesero' then coalesce(f.abierta_por::text, 'en_linea')
               when 'producto' then f.producto_id::text
               when 'categoria' then f.categoria_id::text
             end
           end as clave,
           case when f.es_descuento then 'Descuento a la cuenta' else
             case p_agrupar_por
               when 'total' then 'Total'
               when 'dia' then privado.fecha_en_palabras(f.dia, r.hoy)
               when 'semana' then 'semana del ' || privado.dia_y_mes((f.dia - (extract(isodow from f.dia)::integer - 1)), r.hoy)
               when 'mes' then privado.nombre_mes(f.dia) || ' ' || extract(year from f.dia)::integer
               when 'dia_semana' then privado.nombre_dia(f.dia)
               when 'hora' then lpad(f.hora::text, 2, '0') || ':00'
               when 'mesa' then case f.tipo when 'mesa' then me.nombre when 'comer_aqui' then 'Comer aquí'
                                             when 'para_llevar' then 'Para llevar' else 'A domicilio' end
               when 'mesero' then coalesce(mi.nombre, 'En línea')
               when 'producto' then pr.nombre
               when 'categoria' then ca.nombre
             end
           end as etiqueta
    from filas f
    cross join r
    left join public.mesas me
      on p_agrupar_por = 'mesa' and me.restaurante_id = p_restaurante_id and me.id = f.mesa_id
    left join public.miembros mi
      on p_agrupar_por = 'mesero' and mi.restaurante_id = p_restaurante_id and mi.id = f.abierta_por
    left join public.productos pr
      on p_agrupar_por = 'producto' and pr.restaurante_id = p_restaurante_id and pr.id = f.producto_id
    left join public.categorias ca
      on p_agrupar_por = 'categoria' and ca.restaurante_id = p_restaurante_id and ca.id = f.categoria_id
  )
  select e.clave, e.etiqueta, count(distinct e.venta_id), sum(e.unidades)::bigint,
         sum(e.importe)::numeric(12,2), count(distinct e.dia)
  from etiquetadas e
  group by e.clave, e.etiqueta;
$$;

-- Una mesa por su nombre, o «Comer aquí», «Para llevar» o «A domicilio».
create or replace function privado.buscar_mesa(p_restaurante_id uuid, p_nombre text, out mesa_id bigint, out tipo text,
                                    out nombre text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if lower(p_nombre) in ('comer aquí', 'comer aqui') then
    tipo := 'comer_aqui';
    nombre := 'Comer aquí';
    return;
  end if;
  if lower(p_nombre) = 'para llevar' then
    tipo := 'para_llevar';
    nombre := 'Para llevar';
    return;
  end if;
  if lower(p_nombre) in ('a domicilio', 'domicilio') then
    tipo := 'domicilio';
    nombre := 'A domicilio';
    return;
  end if;
  select m.id, m.nombre into mesa_id, nombre
  from public.mesas m
  where m.restaurante_id = p_restaurante_id and lower(btrim(m.nombre)) = lower(p_nombre)
  order by m.archivado_at nulls first, m.id desc
  limit 1;
  if mesa_id is null then
    raise exception 'No hay una mesa «%». Las que hay: %.', p_nombre,
      concat_ws(', ', (select string_agg(m.nombre, ', ' order by m.orden, m.id) from public.mesas m
                       where m.restaurante_id = p_restaurante_id and m.archivado_at is null),
                'Comer aquí', 'Para llevar', 'A domicilio')
      using errcode = '22023';
  end if;
  tipo := 'mesa';
end;
$$;

create or replace function privado.herramienta_ranking(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agrupar text;
  v_medir text;
  v_desde date;
  v_hasta date;
  v_orden text;
  v_limite integer;
  v_texto text;
  v_mesa_id bigint;
  v_tipo text;
  v_mesa_nombre text;
  v_categoria_id bigint;
  v_categoria_nombre text;
  v_producto_id integer;
  v_producto text;
  v_dia_semana integer;
  v_corte smallint;
  v_hoy date := privado.hoy_de(p_restaurante_id);
  v_ef_desde date;
  v_ef_hasta date;
  v_total record;
  v_dias_abiertos bigint;
  v_promedio boolean;
  v_leido text;
  v_resultado jsonb;
begin
  perform privado.revisar_argumentos('ranking', p_args,
    array['agrupar_por', 'medir_por', 'desde', 'hasta', 'orden', 'limite', 'mesa', 'categoria', 'producto_id', 'dia_semana']);
  v_agrupar := privado.arg_opcion(p_args, 'agrupar_por',
    array['producto', 'categoria', 'mesa', 'mesero', 'hora', 'dia_semana', 'dia', 'semana', 'mes']);
  v_medir := privado.arg_opcion(p_args, 'medir_por', array['importe', 'unidades', 'cuentas'], 'importe');
  v_desde := privado.arg_fecha(p_args, 'desde');
  v_hasta := privado.arg_fecha(p_args, 'hasta');
  perform privado.revisar_rango('desde', v_desde, 'hasta', v_hasta);
  v_orden := privado.arg_opcion(p_args, 'orden', array['mayor', 'menor', 'cronologico'],
    case when v_agrupar in ('dia', 'semana', 'mes') then 'cronologico' else 'mayor' end);
  if v_orden = 'cronologico' and v_agrupar not in ('hora', 'dia_semana', 'dia', 'semana', 'mes') then
    raise exception 'El orden cronologico va con hora, dia_semana, dia, semana o mes. Con % usa mayor o menor.', v_agrupar
      using errcode = '22023';
  end if;
  v_limite := privado.arg_entero(p_args, 'limite', 1, 50, 10);

  v_texto := privado.arg_texto(p_args, 'mesa');
  if v_texto is not null then
    select x.mesa_id, x.tipo, x.nombre into v_mesa_id, v_tipo, v_mesa_nombre
    from privado.buscar_mesa(p_restaurante_id, v_texto) x;
  end if;
  v_texto := privado.arg_texto(p_args, 'categoria');
  if v_texto is not null then
    select x.categoria_id, x.nombre into v_categoria_id, v_categoria_nombre
    from privado.buscar_categoria(p_restaurante_id, v_texto) x;
  end if;
  v_producto_id := privado.arg_entero(p_args, 'producto_id', 1, 2147483647);
  if v_producto_id is not null then
    v_producto := privado.buscar_producto(p_restaurante_id, v_producto_id);
  end if;
  v_dia_semana := privado.arg_entero(p_args, 'dia_semana', 1, 7, null, '1 = lunes, 7 = domingo.');

  v_leido := 'Lo vendido ' || privado.periodo(v_desde, v_hasta, v_hoy, 'en') || ', '
    || case v_agrupar when 'producto' then 'por producto' when 'categoria' then 'por categoría'
         when 'mesa' then 'por mesa' when 'mesero' then 'por mesero' when 'hora' then 'por hora'
         when 'dia_semana' then 'por día de la semana' when 'dia' then 'día por día'
         when 'semana' then 'semana por semana' else 'mes por mes' end
    || case v_medir when 'unidades' then ', en piezas' when 'cuentas' then ', en cuentas' else '' end
    || coalesce(', solo ' || v_categoria_nombre, '')
    || coalesce(', solo ' || v_producto, '')
    || coalesce(case v_tipo when 'mesa' then ', en ' || v_mesa_nombre when 'comer_aqui' then ', para comer aquí'
                  when 'para_llevar' then ', para llevar' when 'domicilio' then ', a domicilio' end, '')
    || coalesce(', ' || privado.los_dias(v_dia_semana), '');

  select * into v_total
  from privado.ventas_agrupadas(p_restaurante_id, v_desde, v_hasta, 'total', v_mesa_id, v_tipo,
                                v_producto_id, v_categoria_id, v_dia_semana);
  if not found then
    return jsonb_build_object('agrupar_por', v_agrupar, 'medir_por', v_medir, 'desde', v_desde, 'hasta', v_hasta,
                              'sin_ventas', true, 'leido', privado.leido('datos', v_leido));
  end if;

  select hora_corte into v_corte from public.restaurantes where id = p_restaurante_id;
  v_ef_desde := greatest(v_desde, privado.primer_dia_con_ventas(p_restaurante_id));
  v_ef_hasta := least(v_hasta, v_hoy);
  v_promedio := v_agrupar in ('hora', 'dia_semana');
  if v_agrupar = 'hora' then
    select x.dias into v_dias_abiertos
    from privado.ventas_agrupadas(p_restaurante_id, v_ef_desde, v_ef_hasta, 'total', p_dia_semana => v_dia_semana) x;
  end if;

  with g as (
    select * from privado.ventas_agrupadas(p_restaurante_id, v_desde, v_hasta, v_agrupar, v_mesa_id, v_tipo,
                                           v_producto_id, v_categoria_id, v_dia_semana)
  ),
  relleno as (
    select p.id::text as clave, p.nombre as etiqueta, not p.visible as oculto
    from public.productos p
    where v_agrupar = 'producto' and p.restaurante_id = p_restaurante_id and p.archivado_at is null
      and (v_categoria_id is null or p.categoria_id = v_categoria_id)
      and (v_producto_id is null or p.id = v_producto_id)
    union all
    select c.id::text, c.nombre, false
    from public.categorias c
    where v_agrupar = 'categoria' and c.restaurante_id = p_restaurante_id and c.archivado_at is null
      and (v_categoria_id is null or c.id = v_categoria_id)
      and (v_producto_id is null
           or c.id = (select p.categoria_id from public.productos p
                      where p.restaurante_id = p_restaurante_id and p.id = v_producto_id))
    union all
    select m.id::text, m.nombre, false
    from public.mesas m
    where v_agrupar = 'mesa' and m.restaurante_id = p_restaurante_id and m.archivado_at is null
      and (v_tipo is null or (v_tipo = 'mesa' and m.id = v_mesa_id))
    union all
    select m.id::text, m.nombre, false
    from public.miembros m
    where v_agrupar = 'mesero' and m.restaurante_id = p_restaurante_id and m.activo and 'mesero' = any (m.roles)
    union all
    select d::text, privado.nombre_dia(date '2024-01-01' + d - 1), false
    from generate_series(1, 7) as d
    where v_agrupar = 'dia_semana' and (v_dia_semana is null or d = v_dia_semana)
    union all
    select to_char(d, 'YYYY-MM-DD'), privado.fecha_en_palabras(d::date, v_hoy), false
    from generate_series(v_ef_desde::timestamp, v_ef_hasta::timestamp, interval '1 day') as d
    where v_agrupar = 'dia' and (v_dia_semana is null or extract(isodow from d) = v_dia_semana)
    union all
    select to_char(d, 'YYYY-MM-DD'), 'semana del ' || privado.dia_y_mes(d::date, v_hoy), false
    from generate_series(date_trunc('week', v_ef_desde::timestamp), v_ef_hasta::timestamp, interval '1 week') as d
    where v_agrupar = 'semana'
    union all
    select to_char(d, 'YYYY-MM'), privado.nombre_mes(d::date) || ' ' || extract(year from d)::integer, false
    from generate_series(date_trunc('month', v_ef_desde::timestamp), v_ef_hasta::timestamp, interval '1 month') as d
    where v_agrupar = 'mes'
  ),
  todos as (
    select coalesce(g.clave, f.clave) as clave, coalesce(g.etiqueta, f.etiqueta) as etiqueta,
           coalesce(f.oculto, false) as oculto, coalesce(g.cuentas, 0) as cuentas,
           coalesce(g.unidades, 0) as unidades, coalesce(g.importe, 0) as importe
    from g
    full join relleno f on f.clave = g.clave
    where coalesce(g.clave, f.clave) <> 'descuento_cuenta'
  ),
  medidos as (
    select t.*,
           case v_medir when 'importe' then t.importe when 'unidades' then t.unidades else t.cuentas end::numeric as bruto,
           case v_agrupar
             when 'dia_semana' then (select count(*) from generate_series(v_ef_desde::timestamp, v_ef_hasta::timestamp, interval '1 day') as d
                                     where extract(isodow from d) = t.clave::integer)
             when 'hora' then v_dias_abiertos
           end as divisor
    from todos t
  ),
  valores as (
    select m.*,
           case when not v_promedio then m.bruto
                when m.divisor > 0 then m.bruto / m.divisor
                else 0 end as valor
    from medidos m
  ),
  ordenados as (
    select v.*,
           row_number() over (order by
             case when v_orden = 'mayor' then v.valor end desc,
             case when v_orden = 'mayor' then v.importe end desc,
             case when v_orden = 'menor' then v.valor end,
             case when v_orden = 'menor' then v.importe end,
             case when v_orden = 'cronologico' then
               case v_agrupar when 'hora' then lpad(((v.clave::integer - v_corte + 24) % 24)::text, 2, '0')
                              else v.clave end
             end,
             v.etiqueta, v.clave) as lugar,
           sum(v.valor) over () as suma,
           count(*) over () as grupos
    from valores v
  )
  select jsonb_build_object(
    'grupos', coalesce(jsonb_agg(
       jsonb_build_object(
         'lugar', o.lugar, 'clave', o.clave, 'nombre', o.etiqueta,
         'valor', case when v_medir = 'importe' then to_jsonb(privado.dinero(o.valor))
                       when v_promedio then to_jsonb(round(o.valor, 1))
                       else to_jsonb(o.valor) end,
         'importe', privado.dinero(o.importe), 'unidades', o.unidades, 'cuentas', o.cuentas,
         'participacion',
           case when v_medir = 'cuentas' and v_agrupar in ('producto', 'categoria')
                  then round(o.cuentas * 100.0 / nullif(v_total.cuentas, 0), 1)
                else round(o.valor * 100 / nullif(o.suma, 0), 1) end)
       || case when o.oculto then jsonb_build_object('oculto', true) else '{}' end
       || case when v_agrupar = 'dia_semana' then jsonb_build_object('veces', o.divisor) else '{}' end
       order by o.lugar) filter (where o.lugar <= v_limite), '[]'),
    'resto', case when max(o.grupos) > v_limite then jsonb_build_object(
               'grupos', max(o.grupos) - v_limite,
               'importe', privado.dinero(coalesce(sum(o.importe) filter (where o.lugar > v_limite), 0)),
               'unidades', coalesce(sum(o.unidades) filter (where o.lugar > v_limite), 0)) end
  )
  into v_resultado
  from ordenados o;

  return v_resultado || jsonb_build_object(
    'agrupar_por', v_agrupar, 'medir_por', v_medir, 'orden', v_orden, 'desde', v_desde, 'hasta', v_hasta,
    'promedio', v_promedio,
    'incluye_hoy_parcial', v_hoy between v_desde and v_hasta,
    'total', jsonb_build_object('cuentas', v_total.cuentas, 'unidades', v_total.unidades,
                                'importe', privado.dinero(v_total.importe), 'dias_abiertos', v_total.dias),
    'leido', privado.leido('datos', v_leido))
  || case when v_promedio or v_agrupar in ('dia', 'semana', 'mes')
          then jsonb_build_object('rango_efectivo', jsonb_build_object('desde', v_ef_desde, 'hasta', v_ef_hasta)) else '{}' end
  || case when v_agrupar = 'hora' then jsonb_build_object('dias_abiertos_en_el_rango', v_dias_abiertos) else '{}' end
  || coalesce((select jsonb_build_object('descuento_a_la_cuenta',
                 jsonb_build_object('importe', privado.dinero(x.importe), 'cuentas', x.cuentas))
               from privado.ventas_agrupadas(p_restaurante_id, v_desde, v_hasta, v_agrupar, v_mesa_id, v_tipo,
                                             v_producto_id, v_categoria_id, v_dia_semana) x
               where x.clave = 'descuento_cuenta'), '{}');
end;
$$;

create or replace function privado.herramienta_detalle(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_folio integer;
  v_desde date;
  v_hasta date;
  v_estado text;
  v_limite integer;
  v_texto text;
  v_mesa_id bigint;
  v_tipo text;
  v_mesa_nombre text;
  v_persona_id bigint;
  v_persona text;
  v_producto_id integer;
  v_producto text;
  v_zona text;
  v_corte smallint;
  v_hoy date := privado.hoy_de(p_restaurante_id);
  v_leido text;
  v_resultado jsonb;
begin
  perform privado.revisar_argumentos('detalle', p_args,
    array['desde', 'hasta', 'folio', 'mesa', 'mesero', 'producto_id', 'estado', 'limite']);
  v_folio := privado.arg_entero(p_args, 'folio', 1, 2147483647);
  -- Con folio las fechas sobran, pero si viene una, viene la otra.
  v_desde := privado.arg_fecha(p_args, 'desde', v_folio is null or coalesce(p_args -> 'hasta', 'null') <> 'null');
  v_hasta := privado.arg_fecha(p_args, 'hasta', v_folio is null or coalesce(p_args -> 'desde', 'null') <> 'null');
  perform privado.revisar_rango('desde', v_desde, 'hasta', v_hasta);
  v_estado := privado.arg_opcion(p_args, 'estado', array['cerradas', 'abiertas', 'canceladas', 'todas'],
                                 case when v_folio is null then 'cerradas' else 'todas' end);
  v_limite := privado.arg_entero(p_args, 'limite', 1, 50, 50);
  v_texto := privado.arg_texto(p_args, 'mesa');
  if v_texto is not null then
    select x.mesa_id, x.tipo, x.nombre into v_mesa_id, v_tipo, v_mesa_nombre
    from privado.buscar_mesa(p_restaurante_id, v_texto) x;
  end if;
  v_texto := privado.arg_texto(p_args, 'mesero');
  if v_texto is not null then
    select x.miembro_id, x.nombre into v_persona_id, v_persona
    from privado.buscar_persona(p_restaurante_id, v_texto) x;
  end if;
  v_producto_id := privado.arg_entero(p_args, 'producto_id', 1, 2147483647);
  if v_producto_id is not null then
    v_producto := privado.buscar_producto(p_restaurante_id, v_producto_id);
  end if;
  select zona_horaria, hora_corte into v_zona, v_corte from public.restaurantes where id = p_restaurante_id;

  v_leido := case when v_folio is not null then 'La cuenta con folio ' || v_folio
                  else 'Las cuentas ' || case v_estado when 'todas' then '' else v_estado || ' ' end
                       || privado.periodo(v_desde, v_hasta, v_hoy, 'de') end
    || coalesce(case v_tipo when 'mesa' then ', en ' || v_mesa_nombre when 'comer_aqui' then ', para comer aquí'
                  when 'para_llevar' then ', para llevar' when 'domicilio' then ', a domicilio' end, '')
    || coalesce(', de ' || v_persona, '')
    || coalesce(', con ' || v_producto, '');

  with c as (
    select v.*,
           exists (select 1 from public.bitacora b
                   where b.restaurante_id = v.restaurante_id and b.accion = 'juntar_mesas'
                     and b.tabla = 'ventas' and b.registro_id = v.id::text) as juntada
    from public.ventas v
    where v.restaurante_id = p_restaurante_id
      and (v_folio is null or v.folio = v_folio)
      and (v_desde is null or v.id in (select x.id from privado.cuentas_del_dia(p_restaurante_id, v_desde, v_hasta) x))
      and (v_estado = 'todas' or v.estado = case v_estado when 'cerradas' then 'cerrada' when 'abiertas' then 'abierta'
                                                          else 'cancelada' end)
      and (v_tipo is null or v.tipo = v_tipo)
      and (v_mesa_id is null or v.mesa_id = v_mesa_id)
      and (v_persona_id is null or v.abierta_por = v_persona_id)
      and (v_producto_id is null or exists (select 1 from public.venta_items i
                                            where i.restaurante_id = v.restaurante_id and i.venta_id = v.id
                                              and i.producto_id = v_producto_id))
  ),
  o as (
    select c.*, row_number() over (order by c.created_at desc, c.id desc) as lugar, count(*) over () as encontradas
    from c
  )
  select jsonb_build_object(
    'cuentas', coalesce(jsonb_agg(jsonb_build_object(
       'folio', o.folio,
       'cuenta', case when o.tipo = 'mesa' then coalesce(me.nombre, o.mesa_nombre)
                      else privado.nombre_de_cuenta(null, o.cliente_nombre, o.pedido_numero) end,
       'tipo', case o.tipo when 'mesa' then 'mesa' when 'comer_aqui' then 'comer aquí' when 'para_llevar' then 'para llevar'
                           else 'a domicilio' end,
       'abrio', coalesce(q.nombre, 'En línea'),
       'estado', case when o.estado = 'abierta' and o.folio is not null then 'reabierta'
                      when o.estado = 'cancelada' and o.juntada then 'juntada'
                      else o.estado end,
       'motivo', o.cancelada_motivo,
       'dia', privado.fecha_en_palabras(privado.dia_de_negocio(v_zona, v_corte, o.created_at), v_hoy),
       'abierta', to_char(o.created_at at time zone v_zona, 'HH24:MI'),
       'cerrada', to_char(o.cerrada_at at time zone v_zona, 'HH24:MI'),
       'renglones', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                       'texto', i.cantidad || ' × ' || i.nombre || ', ' || privado.dinero(i.precio_unitario) || ' c/u',
                       'opciones', (select string_agg(x ->> 'opcion', ', ') from jsonb_array_elements(i.opciones) as x),
                       'nota', i.nota,
                       'descuento', case when i.descuento > 0
                                         then privado.dinero(-i.descuento) || ' (' || i.descuento_motivo || ')' end,
                       'importe', privado.dinero(i.importe),
                       'cancelado', case when i.estado = 'cancelado' then i.cancelado_motivo end))
                       order by i.created_at, i.id), '[]')
                     from public.venta_items i
                     where i.restaurante_id = o.restaurante_id and i.venta_id = o.id),
       'descuento_a_la_cuenta', case when o.descuento > 0 then jsonb_build_object(
                                  'importe', privado.dinero(-o.descuento), 'motivo', o.descuento_motivo) end,
       'total', privado.dinero(o.total),
       'pagos', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                   'metodo', p.metodo, 'monto', privado.dinero(p.monto),
                   'propina', case when p.propina > 0 then privado.dinero(p.propina) end,
                   'cancelado', p.cancelado_motivo))
                   order by p.created_at, p.id), '[]')
                 from public.pagos p
                 where p.restaurante_id = o.restaurante_id and p.venta_id = o.id))
       order by o.lugar) filter (where o.lugar <= v_limite), '[]'),
    'encontradas', coalesce(max(o.encontradas), 0),
    'hay_mas', greatest(coalesce(max(o.encontradas), 0) - v_limite, 0))
  into v_resultado
  from o
  left join public.mesas me on me.restaurante_id = o.restaurante_id and me.id = o.mesa_id
  left join public.miembros q on q.restaurante_id = o.restaurante_id and q.id = o.abierta_por;

  return v_resultado || jsonb_build_object('leido', privado.leido('historial', v_leido));
end;
$$;

create or replace function privado.descuentos_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
returns table (
  venta_id bigint, folio integer, tipo text, cuenta text, renglon_id bigint, producto_id bigint, nombre text,
  cantidad integer, descuento_tipo text, descuento_valor numeric, descuento numeric, motivo text,
  pidio_id bigint, pidio text, autorizo_id bigint, autorizo text, created_at timestamptz, dia date
)
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte from public.restaurantes where id = p_restaurante_id
  ),
  dia as (
    select * from privado.cuentas_del_dia(p_restaurante_id, p_desde, p_hasta)
  ),
  d as (
    select v.id as venta_id, v.folio, v.tipo, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero) as cuenta,
           i.id as renglon_id, i.producto_id, i.nombre, i.cantidad, i.descuento_tipo, i.descuento_valor, i.descuento,
           i.descuento_motivo, 'venta_items' as tabla, i.id::text as registro, v.created_at as abierta_at
    from dia v
    join public.venta_items i on i.restaurante_id = v.restaurante_id and i.venta_id = v.id
    where v.estado = 'cerrada' and i.estado = 'activo' and i.descuento > 0
    union all
    select v.id, v.folio, v.tipo, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero), null, null, null, null,
           v.descuento_tipo, v.descuento_valor, v.descuento, v.descuento_motivo, 'ventas', v.id::text, v.created_at
    from dia v
    where v.estado = 'cerrada' and v.descuento > 0
  )
  select d.venta_id, d.folio, d.tipo, d.cuenta, d.renglon_id, d.producto_id, d.nombre, d.cantidad,
         d.descuento_tipo, d.descuento_valor, d.descuento, d.descuento_motivo,
         b.miembro_id, q.nombre, b.autorizado_por, au.nombre, b.created_at,
         privado.dia_de_negocio(r.zona, r.corte, d.abierta_at)
  from d
  cross join r
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
$$;

create or replace function privado.cancelaciones_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
returns table (
  que text, venta_id bigint, folio integer, tipo text, cuenta text, estado text, renglon_id bigint,
  producto_id bigint, nombre text, cantidad integer, importe numeric, motivo text, pidio_id bigint, pidio text,
  autorizo_id bigint, autorizo text, created_at timestamptz, dia date
)
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte from public.restaurantes where id = p_restaurante_id
  ),
  dia as (
    select * from privado.cuentas_del_dia(p_restaurante_id, p_desde, p_hasta)
  ),
  cuentas as (
    select v.id as venta_id, v.folio, v.tipo, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero) as cuenta,
           (b.detalle ->> 'total')::numeric(12,2) as importe, b.detalle ->> 'motivo' as motivo,
           b.miembro_id, b.autorizado_por, b.created_at, v.created_at as abierta_at
    from dia v
    join public.bitacora b
      on b.restaurante_id = v.restaurante_id and b.accion = 'cancelar_cuenta'
     and b.tabla = 'ventas' and b.registro_id = v.id::text
    where v.estado = 'cancelada'
  ),
  c as (
    select 'cuenta' as que, x.venta_id, x.folio, x.tipo, x.cuenta, 'cancelada' as estado, null::bigint as renglon_id,
           null::bigint as producto_id, null::text as nombre, null::integer as cantidad, x.importe, x.motivo,
           x.miembro_id, x.autorizado_por, x.created_at, x.abierta_at
    from cuentas x
    union all
    select 'renglon', v.id, v.folio, v.tipo, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero), v.estado, i.id,
           i.producto_id, i.nombre, i.cantidad, i.importe, i.cancelado_motivo, i.cancelado_por, i.autorizado_por,
           i.cancelado_at, v.created_at
    from dia v
    join public.venta_items i on i.restaurante_id = v.restaurante_id and i.venta_id = v.id
    where i.estado = 'cancelado'
      and not exists (select 1 from cuentas x where x.venta_id = v.id and x.created_at = i.cancelado_at)
  )
  select c.que, c.venta_id, c.folio, c.tipo, c.cuenta, c.estado, c.renglon_id, c.producto_id, c.nombre, c.cantidad,
         c.importe, c.motivo, c.miembro_id, q.nombre, c.autorizado_por, au.nombre, c.created_at,
         privado.dia_de_negocio(r.zona, r.corte, c.abierta_at)
  from c
  cross join r
  left join public.miembros q on q.restaurante_id = p_restaurante_id and q.id = c.miembro_id
  left join public.miembros au on au.restaurante_id = p_restaurante_id and au.id = c.autorizado_por;
$$;

create or replace function privado.pagos_cancelados_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
returns table (
  turno_id bigint, pago_id bigint, folio integer, cuenta text, metodo text, monto numeric, propina numeric,
  motivo text, pidio_id bigint, pidio text, autorizo_id bigint, autorizo text, cancelado_at timestamptz, dia date
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, p.id, v.folio, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero), p.metodo, p.monto, p.propina,
         p.cancelado_motivo, p.cancelado_por, q.nombre, p.autorizado_por, au.nombre, p.cancelado_at,
         privado.dia_de_negocio(r.zona_horaria, r.hora_corte, t.created_at)
  from privado.turnos_del_rango(p_restaurante_id, p_desde, p_hasta) t
  join public.restaurantes r on r.id = t.restaurante_id
  join public.pagos p on p.restaurante_id = t.restaurante_id and p.turno_id = t.id and p.cancelado_at is not null
  join public.ventas v on v.restaurante_id = p.restaurante_id and v.id = p.venta_id
  join public.miembros q on q.restaurante_id = p.restaurante_id and q.id = p.cancelado_por
  left join public.miembros au on au.restaurante_id = p.restaurante_id and au.id = p.autorizado_por;
$$;

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

create or replace function public.contexto_agente(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_r public.restaurantes;
  v_hoy date;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['gerente']);
  if v_miembro is null then
    raise exception 'Solo los gerentes de este restaurante le preguntan al agente' using errcode = '42501';
  end if;
  select * into v_r from public.restaurantes where id = p_restaurante_id;
  v_hoy := privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte);

  return jsonb_build_object(
    'restaurante', v_r.nombre,
    'ahora', jsonb_build_object(
      'fecha', to_char(now() at time zone v_r.zona_horaria, 'YYYY-MM-DD'),
      'hora', to_char(now() at time zone v_r.zona_horaria, 'HH24:MI'),
      'zona', v_r.zona_horaria,
      'hora_corte', v_r.hora_corte,
      'dia_de_negocio', v_hoy,
      'dia_de_negocio_en_palabras', privado.fecha_en_palabras(v_hoy, v_hoy),
      'lunes_de_esta_semana', v_hoy - (extract(isodow from v_hoy)::integer - 1),
      'primer_dia_del_mes', date_trunc('month', v_hoy)::date),
    'como_llamarlo', (select coalesce(pf.apodo, m.nombre)
                      from public.miembros m
                      left join public.perfiles pf on pf.usuario_id = m.usuario_id
                      where m.restaurante_id = p_restaurante_id and m.id = v_miembro),
    'primer_dia_con_ventas', privado.primer_dia_con_ventas(p_restaurante_id),
    'menu', (select coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'nombre', p.nombre, 'categoria', c.nombre, 'precio', privado.dinero(p.precio))
               || case when not p.visible then jsonb_build_object('oculto', true) else '{}' end
               order by c.orden, c.id, p.orden, p.id), '[]')
             from public.productos p
             join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
             where p.restaurante_id = p_restaurante_id and p.archivado_at is null),
    'categorias', (select coalesce(jsonb_agg(c.nombre order by c.orden, c.id), '[]')
                   from public.categorias c
                   where c.restaurante_id = p_restaurante_id and c.archivado_at is null),
    'mesas', (select coalesce(jsonb_agg(m.nombre order by m.orden, m.id), '[]')
              from public.mesas m
              where m.restaurante_id = p_restaurante_id and m.archivado_at is null)
             || '["Comer aquí", "Para llevar", "A domicilio"]'::jsonb,
    'equipo', (select coalesce(jsonb_agg(jsonb_build_object('nombre', m.nombre, 'roles', to_jsonb(m.roles))
                                         order by m.nombre, m.id), '[]')
               from public.miembros m
               where m.restaurante_id = p_restaurante_id and m.activo),
    'cuentas_abiertas', (
      select jsonb_build_object(
        'cuentas', count(*),
        'por_cobrar', privado.dinero(coalesce(sum(v.total - v.pagado), 0)),
        'lista', coalesce(jsonb_agg(jsonb_build_object(
                   'cuenta', case when v.tipo = 'mesa' then coalesce(me.nombre, v.mesa_nombre)
                                  else privado.nombre_de_cuenta(null, v.cliente_nombre, v.pedido_numero) end,
                   'tipo', case v.tipo when 'mesa' then 'mesa' when 'comer_aqui' then 'comer aquí'
                                       when 'para_llevar' then 'para llevar' else 'a domicilio' end,
                   'abrio', coalesce(q.nombre, 'En línea'),
                   'abierta', to_char(v.created_at at time zone v_r.zona_horaria, 'HH24:MI'),
                   'total', privado.dinero(v.total),
                   'falta', privado.dinero(v.total - v.pagado))
                   || case when v.folio is not null then jsonb_build_object('reabierta', true) else '{}' end
                   order by v.created_at, v.id), '[]'))
      from public.ventas v
      left join public.mesas me on me.restaurante_id = v.restaurante_id and me.id = v.mesa_id
      left join public.miembros q on q.restaurante_id = v.restaurante_id and q.id = v.abierta_por
      where v.restaurante_id = p_restaurante_id and v.estado = 'abierta')
  );
end;
$$;
