-- Los datos de los clientes del menú (21 de noviembre de 2026; parte A de planes/trabajo/tarjeta-lealtad/, con lo de
-- planes/trabajo/datos-de-clientes/): el nombre legal del restaurante para el aviso de privacidad del menú, y la marca
-- de «datos borrados» en los pedidos y las cuentas. Lo decidido: las encuestas de datos-de-clientes/encuestas.md, el
-- aviso de aviso.md y el Diccionario de diccionario.md (libreta 2).
--
-- No hay tablas nuevas. El teléfono, la dirección y las referencias de quien pide se vacían solos cada noche (pg_cron) a
-- los 90 días del día del pedido o de la cuenta, y a los 7 si el pedido se rechazó; Don Chuy los vacía antes con
-- «Borrar los datos de un cliente» en Ajustes. El pedido y la venta nunca se borran: su número, su nombre, lo que se
-- pidió, «paga con» y el total se quedan. Ni lo uno ni lo otro toca un pedido por confirmar ni una cuenta abierta.
-- No se reescriben hacer_pedido, confirmar_pedido, cobrar ni mandar_a_cocina.


-- ─── restaurantes: el nombre legal ────────────────────────────────────────────
-- El del dueño o la razón social de su empresa («Jesús Pérez López»). El aviso de privacidad del menú lo nombra como
-- responsable, con su nombre comercial; sin él, va solo el nombre. Lo escribe el gerente en Tu restaurante.

alter table public.restaurantes
  add column nombre_legal text
    constraint restaurantes_nombre_legal_formato
    check (btrim(nombre_legal) <> '' and char_length(nombre_legal) <= 120);

grant select (nombre_legal) on public.restaurantes to authenticated;


-- ─── pedidos_en_linea: la marca de «datos borrados» ───────────────────────────
-- Con ella, el teléfono, la dirección y las referencias van vacíos, y las reglas que los piden no la revisan: a
-- domicilio pide teléfono y dirección, y para llevar el teléfono, solo mientras el pedido los tenga. La regla del
-- teléfono para llevar sigue sin revisar los pedidos de antes (not valid), como en tu_menu_en_linea. Un pedido por
-- confirmar nunca lleva la marca: todavía hacen falta para entregarlo, y de ahí ya no regresa.

alter table public.pedidos_en_linea
  add column datos_borrados_at timestamptz,
  drop constraint pedidos_en_linea_domicilio,
  add constraint pedidos_en_linea_domicilio check (
    case when tipo = 'domicilio'
      then datos_borrados_at is not null or (cliente_telefono is not null and cliente_direccion is not null)
      else cliente_direccion is null and cliente_referencias is null and paga_con is null
    end
  ),
  drop constraint pedidos_en_linea_telefono_para_llevar,
  add constraint pedidos_en_linea_telefono_para_llevar
    check (tipo <> 'para_llevar' or cliente_telefono is not null or datos_borrados_at is not null) not valid,
  add constraint pedidos_en_linea_datos_borrados check (
    datos_borrados_at is null
    or (cliente_telefono is null and cliente_direccion is null and cliente_referencias is null
        and estado <> 'por_confirmar')
  );

grant select (datos_borrados_at) on public.pedidos_en_linea to authenticated;


-- ─── ventas: la marca de «datos borrados» ─────────────────────────────────────
-- Igual: con ella, el teléfono y la dirección (que trae las referencias) van vacíos, venga la cuenta del menú o del
-- punto de venta, y a domicilio ya no los pide. Una cuenta cerrada que se reabre (cancelar un pago) conserva su marca.

alter table public.ventas
  add column datos_borrados_at timestamptz,
  drop constraint ventas_domicilio,
  add constraint ventas_domicilio check (
    case tipo
      when 'domicilio'
        then datos_borrados_at is not null
          or (coalesce(btrim(cliente_telefono), '') <> '' and coalesce(btrim(cliente_direccion), '') <> '')
      when 'para_llevar' then cliente_direccion is null
      else cliente_telefono is null and cliente_direccion is null
    end
  ),
  add constraint ventas_datos_borrados
    check (datos_borrados_at is null or (cliente_telefono is null and cliente_direccion is null));

grant select (datos_borrados_at) on public.ventas to authenticated;


-- ─── bitacora: «Borrar los datos de un cliente» ───────────────────────────────
-- Lo que vacía el pg_cron cada noche no se anota: es la regla de siempre, no una decisión de alguien.

alter table public.bitacora drop constraint bitacora_accion_valida;
alter table public.bitacora add constraint bitacora_accion_valida
  check (accion in ('cambiar_mesa', 'juntar_mesas', 'retiro', 'ingreso', 'cancelar_renglon',
                    'cancelar_cuenta', 'cancelar_pago', 'descontar', 'quitar_descuento',
                    'cambiar_hora_corte', 'conectar_mercado_pago', 'desconectar_mercado_pago',
                    'confirmar_terminal', 'devuelto_mercado_pago', 'borrar_datos_cliente'));


-- ─── Cuántos días se guardan ──────────────────────────────────────────────────
-- El único lugar de los 90 y los 7: los días que el teléfono y la dirección de un pedido o de una cuenta se guardan,
-- contados desde su día de negocio. 7 para un pedido rechazado (nunca fue venta); 90 para lo demás.

create function privado.dias_que_se_guardan(p_rechazado boolean)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when p_rechazado then 7 else 90 end;
$$;


-- ─── Lo que se vacía cada noche ───────────────────────────────────────────────
-- Un pedido se vacía cuando han pasado sus días desde su día (pedidos_en_linea.dia), si se confirmó y su cuenta ya no
-- está abierta, o si se rechazó; una cuenta, cuando han pasado 90 desde su día de negocio (el de su created_at, como lo
-- cuenta privado.cuentas_del_dia), si ya no está abierta. Con el día de hoy de cada restaurante. Solo los que todavía
-- tienen algo que vaciar. Regresa cuántos pedidos y cuentas vació.

create function privado.vaciar_datos_viejos()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_pedidos integer;
  v_cuentas integer;
begin
  update public.pedidos_en_linea p
  set cliente_telefono = null, cliente_direccion = null, cliente_referencias = null, datos_borrados_at = now()
  from public.restaurantes r
  where r.id = p.restaurante_id
    and p.datos_borrados_at is null
    and num_nonnulls(p.cliente_telefono, p.cliente_direccion, p.cliente_referencias) > 0
    and p.estado <> 'por_confirmar'
    and not exists (
      select 1 from public.ventas v
      where v.restaurante_id = p.restaurante_id and v.id = p.venta_id and v.estado = 'abierta')
    and p.dia <= privado.dia_de_negocio(r.zona_horaria, r.hora_corte)
                 - privado.dias_que_se_guardan(p.estado = 'rechazado');
  get diagnostics v_pedidos = row_count;

  update public.ventas v
  set cliente_telefono = null, cliente_direccion = null, datos_borrados_at = now()
  from public.restaurantes r
  where r.id = v.restaurante_id
    and v.datos_borrados_at is null
    and num_nonnulls(v.cliente_telefono, v.cliente_direccion) > 0
    and v.estado <> 'abierta'
    and v.created_at < privado.inicio_de_dia(
          r.zona_horaria, r.hora_corte,
          privado.dia_de_negocio(r.zona_horaria, r.hora_corte) - privado.dias_que_se_guardan(false) + 1);
  get diagnostics v_cuentas = row_count;

  return v_pedidos + v_cuentas;
end;
$$;


-- ─── Los datos de un cliente, por su teléfono ─────────────────────────────────
-- Lo que «Borrar los datos de un cliente» vaciaría ahora en una sucursal: los pedidos con ese teléfono que ya no están
-- por confirmar (ni su cuenta abierta) y las cuentas con ese teléfono que ya no están abiertas. El teléfono llega con
-- sus 10 dígitos; el de una cuenta del punto de venta lo escribió la caja a mano («222 987 6543», «+52 222…»), así que
-- se comparan sus últimos 10 dígitos. Los ya vaciados no tienen teléfono: no salen. encontrados cuenta pedidos para Don
-- Chuy: un pedido y la cuenta que salió de él son uno.

create function privado.datos_de_un_cliente(p_restaurante_id uuid, p_telefono text)
returns table (pedidos bigint[], cuentas bigint[], encontrados integer)
language sql
stable
set search_path = ''
as $$
  with p as (
    select p.id, p.venta_id
    from public.pedidos_en_linea p
    where p.restaurante_id = p_restaurante_id
      and p.cliente_telefono = p_telefono
      and p.estado <> 'por_confirmar'
      and not exists (
        select 1 from public.ventas v
        where v.restaurante_id = p.restaurante_id and v.id = p.venta_id and v.estado = 'abierta')
  ),
  c as (
    select v.id
    from public.ventas v
    where v.restaurante_id = p_restaurante_id
      and right(regexp_replace(v.cliente_telefono, '\D', '', 'g'), 10) = p_telefono
      and v.estado <> 'abierta'
  )
  select
    coalesce((select array_agg(p.id order by p.id) from p), '{}'),
    coalesce((select array_agg(c.id order by c.id) from c), '{}'),
    ((select count(*) from p)
     + (select count(*) from c where c.id not in (select p.venta_id from p where p.venta_id is not null)))::integer;
$$;

-- El teléfono que escribe Don Chuy, como lo limpia hacer_pedido: sin espacios, guiones, puntos ni paréntesis.
create function privado.telefono_del_cliente(p_telefono text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_telefono text := regexp_replace(coalesce(p_telefono, ''), '[\s().-]', '', 'g');
begin
  if v_telefono !~ '^[0-9]{10}$' then
    raise exception 'El teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
  end if;
  return v_telefono;
end;
$$;


-- ─── «Borrar los datos de un cliente», en Ajustes ─────────────────────────────
-- Solo el gerente, en la sucursal de la cajita. buscar_datos_cliente dice cuántos pedidos encontró («Encontramos 4
-- pedidos»); borrar_datos_cliente los vacía como los 90 días pero antes, y regresa cuántos vació. Queda en la bitácora
-- con cuántos pedidos y cuántas cuentas tocó, sin el teléfono: guardarlo sería guardar el dato que se borró. Sin nada
-- que vaciar no anota nada.

create function public.buscar_datos_cliente(p_restaurante_id uuid, p_telefono text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_telefono text;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante ve los datos de sus clientes' using errcode = '42501';
  end if;
  v_telefono := privado.telefono_del_cliente(p_telefono);
  return (select d.encontrados from privado.datos_de_un_cliente(p_restaurante_id, v_telefono) d);
end;
$$;

create function public.borrar_datos_cliente(p_restaurante_id uuid, p_telefono text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_telefono text;
  v_datos record;
  v_pedidos integer;
  v_cuentas integer;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['gerente']);
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante borra los datos de sus clientes' using errcode = '42501';
  end if;
  v_telefono := privado.telefono_del_cliente(p_telefono);

  select * into v_datos from privado.datos_de_un_cliente(p_restaurante_id, v_telefono);
  if v_datos.encontrados = 0 then
    return 0;
  end if;

  update public.pedidos_en_linea
  set cliente_telefono = null, cliente_direccion = null, cliente_referencias = null, datos_borrados_at = now()
  where restaurante_id = p_restaurante_id and id = any (v_datos.pedidos) and estado <> 'por_confirmar';
  get diagnostics v_pedidos = row_count;

  update public.ventas
  set cliente_telefono = null, cliente_direccion = null, datos_borrados_at = now()
  where restaurante_id = p_restaurante_id and id = any (v_datos.cuentas) and estado <> 'abierta';
  get diagnostics v_cuentas = row_count;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (p_restaurante_id, v_miembro, 'borrar_datos_cliente', 'restaurantes', p_restaurante_id::text,
          jsonb_build_object('pedidos', v_pedidos, 'cuentas', v_cuentas));

  return v_datos.encontrados;
end;
$$;


-- ─── «Guardar» de Tu restaurante, con el nombre legal ─────────────────────────
-- Como en tu_menu_en_linea, y además el nombre legal: en blanco lo quita; sin mandarlo (nulo) lo deja como estaba,
-- como «Hago envíos», así la app de antes sigue guardando mientras llega la nueva.

drop function public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean);

create function public.guardar_restaurante(
  p_restaurante_id uuid,
  p_nombre text,
  p_telefono text,
  p_direccion text,
  p_logo_ruta text,
  p_horario jsonb,
  p_hace_envios boolean default null,
  p_nombre_legal text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_nombre_legal text := nullif(btrim(p_nombre_legal), '');
  v_telefono text := nullif(regexp_replace(coalesce(p_telefono, ''), '[\s().-]', '', 'g'), '');
  v_direccion text := nullif(btrim(p_direccion), '');
  v_logo text := nullif(btrim(p_logo_ruta), '');
  v_logo_antes text;
  v_dias text[] := array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  v_mal record;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar sus datos' using errcode = '42501';
  end if;

  select logo_ruta into v_logo_antes
  from public.restaurantes
  where id = p_restaurante_id
  for no key update;

  -- Lo que pide la vista, revisado aquí también.
  if v_nombre = '' then
    raise exception 'El nombre de tu restaurante es obligatorio' using errcode = '22023';
  end if;
  if char_length(v_nombre) > 60 then
    raise exception 'El nombre puede tener hasta 60 letras' using errcode = '22023';
  end if;
  if char_length(v_nombre_legal) > 120 then
    raise exception 'El nombre legal puede tener hasta 120 letras' using errcode = '22023';
  end if;
  if v_telefono is not null and v_telefono !~ '^[0-9]{10}$' then
    raise exception 'El teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
  end if;
  if char_length(v_direccion) > 200 then
    raise exception 'La dirección puede tener hasta 200 letras' using errcode = '22023';
  end if;

  if p_horario is null or jsonb_typeof(p_horario) <> 'array' then
    raise exception 'Falta el horario' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_horario) h
    where jsonb_typeof(h -> 'dia') <> 'number' or (h ->> 'dia') !~ '^[1-7]$'
  ) then
    raise exception 'El horario va de lunes a domingo' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_horario) h group by h ->> 'dia' having count(*) > 1
  ) then
    raise exception 'Cada día va una sola vez en tu horario' using errcode = '22023';
  end if;
  select (h ->> 'dia')::integer as dia, h ->> 'abre' as abre, h ->> 'cierra' as cierra into v_mal
  from jsonb_array_elements(p_horario) h
  where coalesce(h ->> 'abre', '') !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
     or coalesce(h ->> 'cierra', '') !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
  order by 1
  limit 1;
  if found then
    raise exception 'Revisa las horas del %', v_dias[v_mal.dia] using errcode = '22023';
  end if;
  select (h ->> 'dia')::integer as dia into v_mal
  from jsonb_array_elements(p_horario) h
  where (h ->> 'abre')::time = (h ->> 'cierra')::time
  order by 1
  limit 1;
  if found then
    raise exception 'El % abre y cierra a la misma hora', v_dias[v_mal.dia] using errcode = '22023';
  end if;

  -- Las reglas de cada columna (la carpeta del logo, por ejemplo) son las de la tabla.
  update public.restaurantes
  set nombre = v_nombre,
      nombre_legal = case when p_nombre_legal is null then nombre_legal else v_nombre_legal end,
      telefono = v_telefono,
      direccion = v_direccion,
      logo_ruta = v_logo,
      hace_envios = coalesce(p_hace_envios, hace_envios)
  where id = p_restaurante_id;

  delete from public.horarios where restaurante_id = p_restaurante_id;
  insert into public.horarios (restaurante_id, dia, abre, cierra)
  select p_restaurante_id, (h ->> 'dia')::smallint, (h ->> 'abre')::time, (h ->> 'cierra')::time
  from jsonb_array_elements(p_horario) h;

  return case when v_logo_antes is distinct from v_logo then v_logo_antes end;
end;
$$;


-- ─── El menú que ve la clienta ────────────────────────────────────────────────
-- Como en tu_menu_en_linea, y además el nombre legal, para el aviso de privacidad (su texto vive en el menú; Postgres
-- manda solo los datos del restaurante: el nombre legal, el nombre, la dirección y el teléfono).

create or replace function public.menu_publico(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r public.restaurantes;
  v_local timestamp;
  v_dolar numeric(8,4) := (select t.pesos from public.tipo_de_cambio t where t.moneda = 'USD');
begin
  select * into v_r
  from public.restaurantes r
  where r.slug = lower(btrim(p_slug))
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
  if not found then
    return null;
  end if;
  v_local := now() at time zone v_r.zona_horaria;

  return jsonb_build_object(
    'restaurante', jsonb_build_object(
      'nombre', v_r.nombre,
      'nombre_legal', v_r.nombre_legal,
      'telefono', v_r.telefono,
      'direccion', v_r.direccion,
      'logo_ruta', v_r.logo_ruta,
      'tema', v_r.menu_tema,
      'color', v_r.menu_color,
      'color_barra', v_r.menu_color_barra,
      'fondo', v_r.menu_fondo,
      'tipo_cambio_usd', v_dolar,
      'hace_envios', v_r.hace_envios,
      'formas', jsonb_build_object(
        'barra', v_r.menu_barra,
        'con_nombre', v_r.menu_con_nombre,
        'idioma', v_r.menu_idioma,
        'moneda', v_r.menu_moneda,
        'busqueda', v_r.menu_busqueda,
        'carteles', v_r.menu_carteles,
        'info', v_r.menu_info,
        'info_lugar', v_r.menu_info_lugar,
        'carteles_producto', v_r.menu_carteles_producto,
        'categorias', v_r.menu_categorias,
        'orden', to_jsonb(v_r.menu_orden),
        'titulos', v_r.menu_titulos,
        'productos', v_r.menu_productos,
        'abajo', v_r.menu_abajo,
        'abajo_con_nombres', v_r.menu_abajo_con_nombres,
        'producto_ventana', v_r.menu_producto_ventana,
        'producto_titulo', v_r.menu_producto_titulo,
        'producto_opciones', v_r.menu_producto_opciones)),
    'ahora', jsonb_build_object(
      'fecha', to_char(v_local, 'YYYY-MM-DD'),
      'dia', extract(isodow from v_local)::integer,
      'hora', to_char(v_local, 'HH24:MI')),
    'horario', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'dia', h.dia, 'abre', to_char(h.abre, 'FMHH24:MI'), 'cierra', to_char(h.cierra, 'FMHH24:MI'))
               order by h.dia), '[]')
      from public.horarios h
      where h.restaurante_id = v_r.id),
    'estado', privado.horario_ahora(v_r.id),
    'recibe_pedidos', privado.recibe_pedidos(v_r.id),
    'pedidos_pausados', privado.pedidos_pausados(v_r.id),
    'asistente_contesta', (privado.saldo_ia(v_r.id, 'menu') ->> 'puede')::boolean,
    'carteles', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'ruta', coalesce(c.imagen_ruta, p.imagen_ruta), 'producto_id', c.producto_id)
               order by c.orden, c.id), '[]')
      from public.carteles c
      left join public.productos p on p.restaurante_id = c.restaurante_id and p.id = c.producto_id
      where c.restaurante_id = v_r.id
        and (c.producto_id is null
             or (p.imagen_ruta is not null and p.id in (select privado.productos_a_la_vista(v_r.id))))),
    'categorias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'nombre', c.nombre, 'nombre_en', c.nombre_en, 'icono', c.icono,
               'productos', x.productos)
               order by c.orden, c.id), '[]')
      from public.categorias c
      cross join lateral (
        select jsonb_agg(jsonb_build_object(
                 'id', p.id,
                 'nombre', p.nombre,
                 'nombre_en', p.nombre_en,
                 'descripcion', p.descripcion,
                 'descripcion_en', p.descripcion_en,
                 'precio', p.precio,
                 'precio_usd', round(p.precio / v_dolar, 2),
                 'imagen_ruta', p.imagen_ruta,
                 'desde', g.desde,
                 'grupos', g.grupos)
                 order by p.orden, p.id) as productos
        from public.productos p
        cross join lateral (
          -- «Desde»: un grupo obligatorio tiene alguna opción que sube el precio.
          select coalesce(bool_or(gr.minimo >= 1 and op.sube), false) as desde,
                 coalesce(jsonb_agg(jsonb_build_object(
                   'id', gr.id, 'nombre', gr.nombre, 'nombre_en', gr.nombre_en,
                   'minimo', gr.minimo, 'maximo', gr.maximo, 'opciones', op.opciones)
                   order by gr.orden, gr.id), '[]') as grupos
          from public.producto_grupos pg
          join public.grupos_opciones gr on gr.restaurante_id = pg.restaurante_id and gr.id = pg.grupo_id
          cross join lateral (
            select jsonb_agg(jsonb_build_object(
                     'id', o.id, 'nombre', o.nombre, 'nombre_en', o.nombre_en,
                     'precio_extra', o.precio_extra,
                     'precio_extra_usd', round(o.precio_extra / v_dolar, 2))
                     order by o.orden, o.id) as opciones,
                   bool_or(o.precio_extra > 0) as sube
            from public.opciones o
            where o.restaurante_id = gr.restaurante_id and o.grupo_id = gr.id and o.visible
          ) op
          where pg.restaurante_id = p.restaurante_id
            and pg.producto_id = p.id
            and op.opciones is not null
        ) g
        where p.restaurante_id = c.restaurante_id
          and p.categoria_id = c.id
          and p.id in (select privado.productos_a_la_vista(v_r.id))
      ) x
      where c.restaurante_id = v_r.id
        and c.archivado_at is null
        and x.productos is not null)
  );
end;
$$;


-- ─── Permisos ─────────────────────────────────────────────────────────────────

revoke execute on function
  privado.dias_que_se_guardan(boolean),
  privado.vaciar_datos_viejos(),
  privado.datos_de_un_cliente(uuid, text),
  privado.telefono_del_cliente(text)
from public, anon, authenticated, service_role;

revoke execute on function
  public.buscar_datos_cliente(uuid, text),
  public.borrar_datos_cliente(uuid, text),
  public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean, text)
from public, anon, service_role;

grant execute on function
  public.buscar_datos_cliente(uuid, text),
  public.borrar_datos_cliente(uuid, text),
  public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean, text)
to authenticated;


-- ─── Cada noche, con pg_cron ──────────────────────────────────────────────────
-- A las 9:00 UTC (las 3:00 en México), como el Cron del Worker. Programarlo otra vez con el mismo nombre lo reemplaza.

select cron.schedule('vaciar-datos-de-clientes', '0 9 * * *', 'select privado.vaciar_datos_viejos()');
