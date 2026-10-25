-- Menú en línea, parte 6b: el pedido «Por confirmar» por WhatsApp hasta la caja (libreta 6, lo
-- decidido el 20 de octubre de 2026; libreta 5, «Los pedidos del menú en línea»; libreta 2,
-- Diccionario de datos; con la maqueta de la 6b G2nxGb3xBgiPEYrDb6CgcW).
--
-- La señora Ramírez arma su pedido en el menú y toca «Hacer pedido». Nadie del menú tiene sesión:
-- el Worker, después de la revisión invisible de Cloudflare, llama a hacer_pedido con la llave
-- secreta. Postgres revisa todo, pone los precios, el total y el número corto, y lo guarda «Por
-- confirmar». La caja o el gerente lo confirman (se vuelve una cuenta para llevar o a domicilio y
-- va a cocina) o lo rechazan, y pueden pausar los pedidos el resto del día de negocio. Lo que
-- nadie confirma lo rechaza pg_cron al cierre del día.
--
-- Llega con la 6c: el mini agente del menú.


-- ─── restaurantes, productos, folios y ventas ─────────────────────────────────

-- «Hago envíos» lo cambia el gerente en Tu menú en línea; la pausa, la caja o el gerente en
-- Pedidos. La pausa vale solo el día de negocio en que se puso.
alter table public.restaurantes
  add column hace_envios boolean not null default false,
  add column pedidos_pausados_at timestamptz;

grant select (hace_envios, pedidos_pausados_at) on public.restaurantes to authenticated;

-- «Es un costo de envío»: no sale en el menú en línea ni llega a la cocina, y sale como botón al
-- confirmar un pedido a domicilio. Sus clientes no lo ven, así que no lleva foto ni inglés; las
-- opciones las cuidan guardar_producto y guardar_grupo.
alter table public.productos
  add column es_envio boolean not null default false,
  add constraint productos_envio_sin_foto
    check (not es_envio or (imagen_ruta is null and nombre_en is null and descripcion_en is null));

grant select (es_envio) on public.productos to authenticated;

-- El número corto de los pedidos: vuelve a 1 cada día de negocio.
alter table public.folios
  add column pedidos_dia date,
  add column pedidos_ultimo integer not null default 0
    constraint folios_pedidos_ultimo_valido check (pedidos_ultimo >= 0);

-- La cuenta que abrió «Confirmar» copia el #27, para llamarse «#27 · Rosa Ramírez» donde no se
-- leen los pedidos (Por cobrar, las mesas y la cocina).
alter table public.ventas
  add column pedido_numero integer,
  add constraint ventas_pedido_numero
    check (pedido_numero is null or (origen = 'menu_en_linea' and pedido_numero > 0));

grant select (pedido_numero) on public.ventas to authenticated;


-- ─── pedidos_en_linea ─────────────────────────────────────────────────────────
-- Lo pedido nunca cambia: se confirma como llegó, y lo que cambie se cambia ya en la cuenta. Solo
-- lo leen la caja y el gerente, así que un pedido sin confirmar no cuenta en Mesas, Por cobrar,
-- Cortes, Tus meseros ni el agente. La clave y las marcas no las lee nadie con sesión.

create table public.pedidos_en_linea (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  dia date not null,
  numero integer not null constraint pedidos_en_linea_numero_valido check (numero > 0),
  tipo text not null
    constraint pedidos_en_linea_tipo_valido check (tipo in ('para_llevar', 'domicilio')),
  cliente_nombre text not null
    constraint pedidos_en_linea_cliente_nombre
    check (btrim(cliente_nombre) <> '' and char_length(cliente_nombre) <= 60),
  cliente_telefono text
    constraint pedidos_en_linea_cliente_telefono check (cliente_telefono ~ '^[0-9]{10}$'),
  cliente_direccion text
    constraint pedidos_en_linea_cliente_direccion
    check (btrim(cliente_direccion) <> '' and char_length(cliente_direccion) <= 200),
  cliente_referencias text
    constraint pedidos_en_linea_cliente_referencias
    check (btrim(cliente_referencias) <> '' and char_length(cliente_referencias) <= 120),
  paga_con numeric(12,2),
  total numeric(12,2) not null constraint pedidos_en_linea_total_valido check (total > 0),
  estado text not null default 'por_confirmar'
    constraint pedidos_en_linea_estado_valido check (estado in ('por_confirmar', 'confirmado', 'rechazado')),
  venta_id bigint constraint pedidos_en_linea_venta_unica unique,
  atendido_por bigint,
  atendido_at timestamptz,
  rechazo_motivo text
    constraint pedidos_en_linea_rechazo_motivo
    check (btrim(rechazo_motivo) <> '' and char_length(rechazo_motivo) <= 140),
  clave uuid not null,
  marca_celular text not null
    constraint pedidos_en_linea_marca_celular check (marca_celular ~ '^[0-9a-f]{64}$'),
  marca_conexion text not null
    constraint pedidos_en_linea_marca_conexion check (marca_conexion ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  constraint pedidos_en_linea_numero_unico unique (restaurante_id, dia, numero),
  constraint pedidos_en_linea_clave_unica unique (restaurante_id, clave),
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, atendido_por) references public.miembros (restaurante_id, id),
  -- Para llevar no pide teléfono ni dirección: llegan con el WhatsApp.
  constraint pedidos_en_linea_domicilio check (
    case when tipo = 'domicilio'
      then cliente_telefono is not null and cliente_direccion is not null
      else cliente_telefono is null and cliente_direccion is null
           and cliente_referencias is null and paga_con is null
    end
  ),
  constraint pedidos_en_linea_paga_con check (paga_con >= total),
  -- Confirmado lleva su cuenta y quién lo confirmó; rechazado, su motivo (el del cierre del día,
  -- sin quién).
  constraint pedidos_en_linea_atendido check (
    case estado
      when 'por_confirmar' then
        venta_id is null and atendido_por is null and atendido_at is null and rechazo_motivo is null
      when 'confirmado' then
        venta_id is not null and atendido_por is not null and atendido_at is not null and rechazo_motivo is null
      else
        venta_id is null and atendido_at is not null and rechazo_motivo is not null
    end
  )
);

-- La lista de Pedidos y el cierre del día buscan por estado y día; los límites, por marca.
create index pedidos_en_linea_estado_idx on public.pedidos_en_linea (restaurante_id, estado, dia);
create index pedidos_en_linea_celular_idx on public.pedidos_en_linea (restaurante_id, marca_celular, created_at);
create index pedidos_en_linea_conexion_idx on public.pedidos_en_linea (restaurante_id, marca_conexion, created_at);
create index pedidos_en_linea_atendido_por_idx on public.pedidos_en_linea (restaurante_id, atendido_por);

create trigger pedidos_en_linea_updated_at
before update on public.pedidos_en_linea
for each row execute function privado.set_updated_at();


-- ─── pedido_items ─────────────────────────────────────────────────────────────
-- Cada renglón de un pedido, hasta 30. No cambia nunca. Por su llave, un producto pedido ya no se
-- borra, solo se archiva, como uno vendido.

create table public.pedido_items (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  pedido_id bigint not null,
  producto_id bigint not null,
  nombre text not null check (btrim(nombre) <> ''),
  precio_unitario numeric(12,2) not null constraint pedido_items_precio_valido check (precio_unitario >= 0),
  cantidad integer not null constraint pedido_items_cantidad_valida check (cantidad between 1 and 99),
  importe numeric(12,2) generated always as (cantidad * precio_unitario) stored,
  opciones jsonb not null default '[]'
    constraint pedido_items_opciones_lista check (jsonb_typeof(opciones) = 'array'),
  nota text constraint pedido_items_nota check (btrim(nota) <> '' and char_length(nota) <= 140),
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, pedido_id) references public.pedidos_en_linea (restaurante_id, id),
  foreign key (restaurante_id, producto_id) references public.productos (restaurante_id, id)
);

create index pedido_items_pedido_idx on public.pedido_items (restaurante_id, pedido_id);
create index pedido_items_producto_idx on public.pedido_items (restaurante_id, producto_id);


-- ─── Permisos, RLS y tiempo real ──────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. La caja y el gerente leen los pedidos de sus
-- restaurantes que funcionan; nadie los escribe directo.

alter table public.pedidos_en_linea enable row level security;
alter table public.pedido_items enable row level security;

revoke all on table public.pedidos_en_linea, public.pedido_items from anon, authenticated;
revoke all on sequence public.pedidos_en_linea_id_seq, public.pedido_items_id_seq from anon, authenticated;

grant select (
  id, restaurante_id, dia, numero, tipo, cliente_nombre, cliente_telefono, cliente_direccion,
  cliente_referencias, paga_con, total, estado, venta_id, atendido_por, atendido_at, rechazo_motivo,
  created_at, updated_at
) on public.pedidos_en_linea to authenticated;

grant select (
  id, restaurante_id, pedido_id, producto_id, nombre, precio_unitario, cantidad, importe, opciones,
  nota, created_at
) on public.pedido_items to authenticated;

create policy "La caja y el gerente leen los pedidos de sus restaurantes que funcionan"
on public.pedidos_en_linea for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_caja()));

create policy "La caja y el gerente leen los renglones de los pedidos"
on public.pedido_items for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_caja()));

-- Pedidos se pone al día solo y suena al llegar uno. La publicación solo existe en Supabase.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.pedidos_en_linea;
  end if;
end;
$$;


-- ─── Lo que se cuenta una sola vez ────────────────────────────────────────────

-- ¿Están pausados los pedidos? Solo el día de negocio en que se pausaron: al empezar el
-- siguiente, la pausa se quita sola.
create function privado.pedidos_pausados(p_restaurante_id uuid, p_momento timestamptz default now())
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    privado.dia_de_negocio(r.zona_horaria, r.hora_corte, r.pedidos_pausados_at)
      = privado.dia_de_negocio(r.zona_horaria, r.hora_corte, p_momento),
    false)
  from public.restaurantes r
  where r.id = p_restaurante_id;
$$;

-- ¿Recibe pedidos ahora? Con su teléfono, que es su WhatsApp, dentro de su horario y sin pausa.
-- Sin horario no recibe.
create function privado.recibe_pedidos(p_restaurante_id uuid, p_momento timestamptz default now())
returns boolean
language sql
stable
set search_path = ''
as $$
  select r.telefono is not null
    and coalesce((privado.horario_ahora(r.id, p_momento) ->> 'abierto')::boolean, false)
    and not privado.pedidos_pausados(r.id, p_momento)
  from public.restaurantes r
  where r.id = p_restaurante_id;
$$;

-- Los productos que el menú en línea enseña: como en la 6a, y sin los envíos.
create or replace function privado.productos_a_la_vista(p_restaurante_id uuid)
returns setof bigint
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.productos p
  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
  where p.restaurante_id = p_restaurante_id
    and p.visible
    and not p.es_envio
    and p.archivado_at is null
    and c.archivado_at is null
    and not exists (
      select 1
      from public.producto_grupos pg
      join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
      where pg.restaurante_id = p.restaurante_id
        and pg.producto_id = p.id
        and g.minimo > (select count(*) from public.opciones o
                        where o.restaurante_id = g.restaurante_id and o.grupo_id = g.id and o.visible)
    );
$$;

-- Un pedido como lo enseñan el menú («Pedido #27 enviado» y el WhatsApp) y la lista de Pedidos.
create function privado.pedido_en_json(p_pedido_id bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'numero', p.numero,
    'tipo', p.tipo,
    'cliente_nombre', p.cliente_nombre,
    'cliente_telefono', p.cliente_telefono,
    'cliente_direccion', p.cliente_direccion,
    'cliente_referencias', p.cliente_referencias,
    'paga_con', p.paga_con,
    'total', p.total,
    'created_at', p.created_at,
    'renglones', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'nombre', i.nombre, 'cantidad', i.cantidad, 'precio_unitario', i.precio_unitario,
               'importe', i.importe, 'opciones', i.opciones, 'nota', i.nota)
               order by i.id), '[]')
      from public.pedido_items i
      where i.restaurante_id = p.restaurante_id and i.pedido_id = p.id))
  from public.pedidos_en_linea p
  where p.id = p_pedido_id;
$$;

-- El cierre del día: lo que sigue «Por confirmar» de un día de negocio que ya terminó queda
-- rechazado con «No se confirmó», sin quién. Lo corre pg_cron cada hora en punto (la hora de
-- corte es una hora en punto, de 0 a 23). Regresa cuántos rechazó.
create function privado.rechazar_sin_confirmar()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_rechazados integer;
begin
  update public.pedidos_en_linea p
  set estado = 'rechazado', rechazo_motivo = 'No se confirmó', atendido_at = now()
  from public.restaurantes r
  where r.id = p.restaurante_id
    and p.estado = 'por_confirmar'
    and p.dia < privado.dia_de_negocio(r.zona_horaria, r.hora_corte);
  get diagnostics v_rechazados = row_count;
  return v_rechazados;
end;
$$;

revoke execute on function
  privado.pedidos_pausados(uuid, timestamptz),
  privado.recibe_pedidos(uuid, timestamptz),
  privado.pedido_en_json(bigint),
  privado.rechazar_sin_confirmar()
from public, anon, authenticated, service_role;


-- ─── El menú que ve la clienta ────────────────────────────────────────────────
-- Como en la 6a, y además: si recibe pedidos ahora (y si es por la pausa), si hace envíos, y el
-- id de cada grupo y de cada opción, para pedir. Los envíos no salen.

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
      'telefono', v_r.telefono,
      'direccion', v_r.direccion,
      'logo_ruta', v_r.logo_ruta,
      'tema', v_r.menu_tema,
      'color', v_r.menu_color,
      'tipo_cambio_usd', v_r.tipo_cambio_usd,
      'hace_envios', v_r.hace_envios),
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
    'carteles', (
      select coalesce(jsonb_agg(c.imagen_ruta order by c.orden, c.id), '[]')
      from public.carteles c
      where c.restaurante_id = v_r.id),
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
                 'precio_usd', round(p.precio / v_r.tipo_cambio_usd, 2),
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
                     'precio_extra_usd', round(o.precio_extra / v_r.tipo_cambio_usd, 2))
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


-- ─── «Hacer pedido» (solo el Worker) ──────────────────────────────────────────

-- La señora Ramírez toca «Hacer pedido»: el Worker llama aquí con la llave secreta, después de la
-- revisión de Cloudflare, con las marcas del celular y de la conexión ya hechas (la conexión
-- nunca llega). Cada renglón es {producto_id, cantidad, opciones: [ids], nota, precio}, donde
-- precio es lo que ella vio de cada uno, solo para compararlo: el que se guarda lo pone Postgres.
--
-- Regresa {ok: true, numero, …el pedido} si lo guardó (la misma clave otra vez regresa el mismo
-- pedido sin guardar nada); {ok: false, motivo: 'no_recibe'} si ahora no recibe pedidos (un
-- slug que no existe o una licencia que no funciona dan lo mismo); o {ok: false, motivo:
-- 'cambios', cambios, total} si algo cambió desde que lo armó, sin guardar nada: cada cambio es
-- {renglon, cambio: 'agotado' (con la opción agotada, si fue eso), 'opciones' (ya no se puede
-- elegir así) o 'precio' (con el nuevo)}, y total es el de lo que sí se puede pedir. Lo demás que
-- no se puede (los límites, «Hago envíos» apagado, un dato mal escrito) es un error en español.
create function public.hacer_pedido(
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

  -- Quién lo pide. Para llevar solo pide el nombre: el teléfono llega con el WhatsApp.
  if v_nombre = '' then
    raise exception 'Escribe tu nombre y apellido' using errcode = '22023';
  end if;
  if char_length(v_nombre) > 60 then
    raise exception 'Tu nombre puede tener hasta 60 letras' using errcode = '22023';
  end if;
  if p_tipo = 'domicilio' then
    if v_telefono is null or v_telefono !~ '^[0-9]{10}$' then
      raise exception 'Tu teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
    end if;
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
    v_telefono := null;
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

  -- El número corto: el siguiente del día de negocio, o el 1 si es el primero de hoy.
  v_dia := privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte);
  insert into public.folios (restaurante_id, pedidos_dia, pedidos_ultimo)
  values (v_r.id, v_dia, 1)
  on conflict (restaurante_id) do update
  set pedidos_dia = excluded.pedidos_dia,
      pedidos_ultimo = case
        when public.folios.pedidos_dia = excluded.pedidos_dia then public.folios.pedidos_ultimo + 1
        -- Un día que vuelve (si cambió la hora de corte) sigue después de su último número.
        else coalesce((select max(p.numero) from public.pedidos_en_linea p
                       where p.restaurante_id = excluded.restaurante_id and p.dia = excluded.pedidos_dia), 0) + 1
      end
  returning pedidos_ultimo into v_numero;

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

revoke execute on function
  public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text)
from public, anon, authenticated;

grant execute on function
  public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text)
to service_role;


-- ─── Pedidos: la caja y el gerente ────────────────────────────────────────────

-- La lista de Pedidos, en la caja y en el panel: si está en pausa (y desde cuándo), si recibe
-- pedidos y hasta qué hora; arriba los «Por confirmar» del día de negocio, del más viejo al más
-- nuevo y completos, y abajo los «Atendidos hoy», del más reciente al más viejo, con quién y su
-- motivo. ahora es la hora de Postgres, para contar «hace 3 min» sin el reloj del aparato.
create function public.pedidos_del_dia(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r public.restaurantes;
  v_dia date;
  v_pausado boolean;
begin
  if privado.mi_miembro(p_restaurante_id, array['caja', 'gerente']) is null then
    raise exception 'Solo la caja y el gerente de este restaurante ven sus pedidos' using errcode = '42501';
  end if;
  select * into v_r from public.restaurantes where id = p_restaurante_id;
  v_dia := privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte);
  v_pausado := privado.pedidos_pausados(p_restaurante_id);

  return jsonb_build_object(
    'ahora', now(),
    'pausado', v_pausado,
    'pausado_at', case when v_pausado then v_r.pedidos_pausados_at end,
    'recibe', privado.recibe_pedidos(p_restaurante_id),
    'estado', privado.horario_ahora(p_restaurante_id),
    'por_confirmar', (
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id) || privado.pedido_en_json(p.id)
               order by p.created_at, p.id), '[]')
      from public.pedidos_en_linea p
      where p.restaurante_id = p_restaurante_id and p.estado = 'por_confirmar' and p.dia = v_dia),
    'atendidos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'numero', p.numero, 'tipo', p.tipo, 'cliente_nombre', p.cliente_nombre,
               'total', p.total, 'estado', p.estado, 'venta_id', p.venta_id,
               'atendido_por', m.nombre, 'atendido_at', p.atendido_at, 'rechazo_motivo', p.rechazo_motivo)
               order by p.atendido_at desc, p.id desc), '[]')
      from public.pedidos_en_linea p
      left join public.miembros m on m.restaurante_id = p.restaurante_id and m.id = p.atendido_por
      where p.restaurante_id = p_restaurante_id and p.estado <> 'por_confirmar' and p.dia = v_dia)
  );
end;
$$;

-- «Confirmar»: el pedido se vuelve una cuenta para llevar o a domicilio, a nombre de quien
-- confirma, y va a cocina, una comanda por área, como «Mandar a cocina». Lleva los precios con que
-- llegó, aunque el menú haya cambiado, y lo agotado no la frena: se cancela ya como cuenta. A
-- domicilio, p_envio_id es el producto de envío que se eligió («Envío $30»), sin comanda; vacío =
-- «Sin envío». La dirección de la cuenta lleva las referencias. Regresa la cuenta; confirmar otra
-- vez el mismo pedido (doble toque) regresa la misma. Un pedido de un día de negocio que ya
-- terminó no se confirma, aunque pg_cron todavía no haya pasado: se rechaza ahí mismo con «No se
-- confirmó» y regresa vacío.
create function public.confirmar_pedido(p_pedido_id bigint, p_envio_id bigint default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos_en_linea;
  v_miembro bigint;
  v_r public.restaurantes;
  v_envio record;
  v_venta_id bigint;
  v_item record;
  v_comandas jsonb := '{}';
  v_comanda_id bigint;
begin
  select * into v_pedido
  from public.pedidos_en_linea
  where id = p_pedido_id and restaurante_id in (select privado.mis_restaurantes_caja())
  for update;
  -- Sin el pedido, restaurante_id va vacío y tampoco hay miembro.
  v_miembro := privado.mi_miembro(v_pedido.restaurante_id, array['caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo la caja y el gerente de este restaurante confirman sus pedidos' using errcode = '42501';
  end if;

  if v_pedido.estado = 'confirmado' then
    return v_pedido.venta_id;
  end if;
  if v_pedido.estado = 'rechazado' then
    raise exception 'El #% ya se rechazó', v_pedido.numero using errcode = '55000';
  end if;

  select * into v_r from public.restaurantes where id = v_pedido.restaurante_id;
  if v_pedido.dia < privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte) then
    update public.pedidos_en_linea
    set estado = 'rechazado', rechazo_motivo = 'No se confirmó', atendido_at = now()
    where id = v_pedido.id;
    return null;
  end if;

  if p_envio_id is not null then
    if v_pedido.tipo <> 'domicilio' then
      raise exception 'Solo un pedido a domicilio lleva envío' using errcode = '22023';
    end if;
    select p.id, p.nombre, p.precio, p.tasa_iva into v_envio
    from public.productos p
    where p.restaurante_id = v_pedido.restaurante_id
      and p.id = p_envio_id
      and p.es_envio
      and p.archivado_at is null;
    if not found then
      raise exception 'Ese envío ya no está en tu menú' using errcode = '23503';
    end if;
  end if;

  insert into public.ventas (
    restaurante_id, origen, tipo, cliente_nombre, cliente_telefono, cliente_direccion,
    pedido_numero, abierta_por
  ) values (
    v_pedido.restaurante_id, 'menu_en_linea', v_pedido.tipo, v_pedido.cliente_nombre,
    v_pedido.cliente_telefono,
    case when v_pedido.tipo = 'domicilio'
      then concat_ws(' · ', v_pedido.cliente_direccion, v_pedido.cliente_referencias) end,
    v_pedido.numero, v_miembro
  )
  returning id into v_venta_id;

  -- Los renglones en su orden, con el área de cocina de hoy. Un producto que se volvió envío
  -- después de pedirse tampoco va a cocina.
  for v_item in
    select i.producto_id, i.nombre, i.precio_unitario, i.cantidad, i.opciones, i.nota, p.tasa_iva,
           case when p.es_envio then null else c.area_preparacion_id end as area_id
    from public.pedido_items i
    join public.productos p on p.restaurante_id = i.restaurante_id and p.id = i.producto_id
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where i.restaurante_id = v_pedido.restaurante_id and i.pedido_id = v_pedido.id
    order by i.id
  loop
    v_comanda_id := null;
    if v_item.area_id is not null then
      v_comanda_id := (v_comandas ->> v_item.area_id::text)::bigint;
      if v_comanda_id is null then
        insert into public.comandas (restaurante_id, venta_id, area_preparacion_id, enviada_por)
        values (v_pedido.restaurante_id, v_venta_id, v_item.area_id, v_miembro)
        returning id into v_comanda_id;
        v_comandas := v_comandas || jsonb_build_object(v_item.area_id::text, v_comanda_id);
      end if;
    end if;

    insert into public.venta_items (
      restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, opciones, nota,
      tasa_iva, comanda_id, agregado_por, clave_envio
    ) values (
      v_pedido.restaurante_id, v_venta_id, v_item.producto_id, v_item.nombre, v_item.precio_unitario,
      v_item.cantidad, v_item.opciones, v_item.nota, v_item.tasa_iva, v_comanda_id, v_miembro,
      v_pedido.clave
    );
  end loop;

  if p_envio_id is not null then
    insert into public.venta_items (
      restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, opciones, nota,
      tasa_iva, comanda_id, agregado_por, clave_envio
    ) values (
      v_pedido.restaurante_id, v_venta_id, v_envio.id, v_envio.nombre, v_envio.precio, 1, '[]', null,
      v_envio.tasa_iva, null, v_miembro, v_pedido.clave
    );
  end if;

  update public.pedidos_en_linea
  set estado = 'confirmado', venta_id = v_venta_id, atendido_por = v_miembro, atendido_at = now()
  where id = v_pedido.id;

  return v_venta_id;
end;
$$;

-- «Rechazar», con su motivo («Pedido falso», «Ya cerramos»…). No va a la bitácora: no toca
-- dinero. Rechazar otra vez uno ya rechazado no hace nada.
create function public.rechazar_pedido(p_pedido_id bigint, p_motivo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido public.pedidos_en_linea;
  v_miembro bigint;
  v_motivo text := btrim(coalesce(p_motivo, ''));
begin
  select * into v_pedido
  from public.pedidos_en_linea
  where id = p_pedido_id and restaurante_id in (select privado.mis_restaurantes_caja())
  for update;
  v_miembro := privado.mi_miembro(v_pedido.restaurante_id, array['caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo la caja y el gerente de este restaurante rechazan sus pedidos' using errcode = '42501';
  end if;
  if v_motivo = '' then
    raise exception 'Escribe el motivo del rechazo' using errcode = '22023';
  end if;
  if char_length(v_motivo) > 140 then
    raise exception 'El motivo puede tener hasta 140 letras' using errcode = '22023';
  end if;

  if v_pedido.estado = 'rechazado' then
    return;
  end if;
  if v_pedido.estado = 'confirmado' then
    raise exception 'El #% ya se confirmó: cancélalo ya como cuenta', v_pedido.numero using errcode = '55000';
  end if;

  update public.pedidos_en_linea
  set estado = 'rechazado', rechazo_motivo = v_motivo, atendido_por = v_miembro, atendido_at = now()
  where id = v_pedido.id;
end;
$$;

-- «Pausar pedidos» y «Reanudar». La pausa dura el día de negocio; pausar otra vez el mismo día
-- conserva desde cuándo.
create function public.pausar_pedidos(p_restaurante_id uuid, p_pausar boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if privado.mi_miembro(p_restaurante_id, array['caja', 'gerente']) is null then
    raise exception 'Solo la caja y el gerente de este restaurante pausan sus pedidos' using errcode = '42501';
  end if;
  if p_pausar is null then
    raise exception 'Elige pausar o reanudar' using errcode = '22023';
  end if;

  update public.restaurantes
  set pedidos_pausados_at = case
    when not p_pausar then null
    when privado.pedidos_pausados(id) then pedidos_pausados_at
    else now()
  end
  where id = p_restaurante_id;
end;
$$;

revoke execute on function
  public.pedidos_del_dia(uuid),
  public.confirmar_pedido(bigint, bigint),
  public.rechazar_pedido(bigint, text),
  public.pausar_pedidos(uuid, boolean)
from public, anon, service_role;

grant execute on function
  public.pedidos_del_dia(uuid),
  public.confirmar_pedido(bigint, bigint),
  public.rechazar_pedido(bigint, text),
  public.pausar_pedidos(uuid, boolean)
to authenticated;


-- ─── «¿Quién eres?» también suena ─────────────────────────────────────────────
-- Como en la migración empleados, y además cuántos pedidos esperan «Por confirmar» hoy, para que
-- la tableta de la caja suene aunque nadie haya entrado. Solo en un aparato donde entra alguien
-- de caja; en los demás, vacío.

create or replace function public.nombres_del_aparato(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_aparato public.dispositivos := privado.aparato_vigente(p_token);
begin
  return jsonb_build_object(
    'restaurante', (select r.nombre from public.restaurantes r where r.id = v_aparato.restaurante_id),
    'aparato', v_aparato.nombre,
    'compartido', v_aparato.miembro_id is null,
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'nombre', m.nombre,
        'roles', to_jsonb(m.roles),
        'bloqueado', coalesce(m.bloqueado_hasta > now(), false),
        'bloqueado_hasta', case when m.bloqueado_hasta > now() and m.bloqueado_hasta <> 'infinity'
                                then m.bloqueado_hasta end
      ) order by lower(m.nombre), m.id)
      from public.miembros m
      where m.restaurante_id = v_aparato.restaurante_id
        and m.activo
        and m.pin_hash is not null
        and not ('gerente' = any (m.roles))
        and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
    ), '[]'::jsonb),
    'pedidos_por_confirmar', case when exists (
        select 1 from public.miembros m
        where m.restaurante_id = v_aparato.restaurante_id
          and m.activo
          and m.pin_hash is not null
          and 'caja' = any (m.roles)
          and not ('gerente' = any (m.roles))
          and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
      ) then (
        select count(*)
        from public.pedidos_en_linea p
        join public.restaurantes r on r.id = p.restaurante_id
        where p.restaurante_id = v_aparato.restaurante_id
          and p.estado = 'por_confirmar'
          and p.dia = privado.dia_de_negocio(r.zona_horaria, r.hora_corte))
      end
  );
end;
$$;


-- ─── El envío en el punto de venta y en Mi menú ───────────────────────────────

-- «Mandar a cocina», como en la migración cancelaciones, y un envío no crea comanda aunque su
-- categoría tenga área. Reemplazarla conserva sus permisos.
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

-- El chip de arriba de Tu menú en línea, como en la 6a: «12 de 14 productos a la vista» no cuenta
-- los envíos en ninguno de los dos números.
create or replace function public.estado_menu_en_linea(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante ve su menú en línea así' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'estado', privado.horario_ahora(p_restaurante_id),
    'a_la_vista', (select count(*) from privado.productos_a_la_vista(p_restaurante_id)),
    'productos', (select count(*)
                  from public.productos p
                  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
                  where p.restaurante_id = p_restaurante_id
                    and not p.es_envio
                    and p.archivado_at is null
                    and c.archivado_at is null));
end;
$$;

-- «Guardar» de Cómo se ve, como en la 6a, y además «Hago envíos». p_hace_envios vacío lo deja
-- como estaba.
drop function public.guardar_menu_en_linea(uuid, text, text, numeric);

create function public.guardar_menu_en_linea(
  p_restaurante_id uuid,
  p_tema text,
  p_color text,
  p_tipo_cambio_usd numeric,
  p_hace_envios boolean default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_color text := upper(nullif(btrim(p_color), ''));
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if p_tema is null or p_tema not in ('claro', 'oscuro') then
    raise exception 'El menú se ve claro u oscuro' using errcode = '22023';
  end if;
  if v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'Ese color no se entiende; escríbelo como #B3261E' using errcode = '22023';
  end if;
  if round(p_tipo_cambio_usd, 2) <= 0 or round(p_tipo_cambio_usd, 2) >= 1000000 then
    raise exception 'Escribe a cuánto tomas el dólar, como 18.50' using errcode = '22023';
  end if;

  update public.restaurantes
  set menu_tema = p_tema,
      menu_color = v_color,
      tipo_cambio_usd = round(p_tipo_cambio_usd, 2),
      hace_envios = coalesce(p_hace_envios, hace_envios)
  where id = p_restaurante_id;
end;
$$;

-- La ventana del producto, como en la 6a, y además «Es un costo de envío». Un envío no lleva
-- opciones, ni foto, ni su parte en inglés: sus clientes no lo ven. Volver envío un producto con
-- foto se la quita; la app, que la conoce, le pide al Worker borrarla.
drop function public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[], text, text);

create function public.guardar_producto(
  p_restaurante_id uuid,
  p_producto_id bigint,
  p_categoria_id bigint,
  p_nombre text,
  p_descripcion text,
  p_precio numeric,
  p_imagen_ruta text,
  p_grupos bigint[],
  p_nombre_en text default null,
  p_descripcion_en text default null,
  p_es_envio boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_producto_id bigint := p_producto_id;
  v_grupos bigint[] := array(select distinct x from unnest(coalesce(p_grupos, '{}')) as x where x is not null);
  v_envio boolean := coalesce(p_es_envio, false);
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if v_envio and cardinality(v_grupos) > 0 then
    raise exception 'Un envío no lleva opciones' using errcode = '22023';
  end if;
  if v_envio and (p_imagen_ruta is not null or p_nombre_en is not null or p_descripcion_en is not null) then
    raise exception 'Un envío no lleva foto ni su parte en inglés' using errcode = '22023';
  end if;
  if (select count(*) from public.grupos_opciones
      where restaurante_id = p_restaurante_id and id = any (v_grupos)) <> cardinality(v_grupos) then
    raise exception 'Uno de esos grupos ya no está en tu menú' using errcode = '23503';
  end if;

  if v_producto_id is null then
    insert into public.productos (
      restaurante_id, categoria_id, nombre, descripcion, precio, imagen_ruta, nombre_en, descripcion_en,
      es_envio
    )
    values (
      p_restaurante_id, p_categoria_id, p_nombre, p_descripcion, p_precio, p_imagen_ruta,
      p_nombre_en, p_descripcion_en, v_envio
    )
    returning id into v_producto_id;
  else
    update public.productos
    set categoria_id = p_categoria_id,
        nombre = p_nombre,
        descripcion = p_descripcion,
        precio = p_precio,
        imagen_ruta = case when not v_envio then coalesce(p_imagen_ruta, imagen_ruta) end,
        nombre_en = p_nombre_en,
        descripcion_en = p_descripcion_en,
        es_envio = v_envio
    where id = v_producto_id
      and restaurante_id = p_restaurante_id
      and archivado_at is null;
    if not found then
      raise exception 'Ese producto ya no está en tu menú' using errcode = '23503';
    end if;
  end if;

  delete from public.producto_grupos
  where restaurante_id = p_restaurante_id
    and producto_id = v_producto_id
    and grupo_id <> all (v_grupos);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id)
  select p_restaurante_id, v_producto_id, x from unnest(v_grupos) as x
  on conflict do nothing;

  return v_producto_id;
end;
$$;

-- La ventana del grupo, como en la 6a, y además un envío no lleva opciones. Reemplazarla conserva
-- sus permisos.
create or replace function public.guardar_grupo(
  p_restaurante_id uuid,
  p_grupo_id bigint,
  p_nombre text,
  p_minimo integer,
  p_maximo integer,
  p_opciones jsonb,
  p_productos bigint[],
  p_nombre_en text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grupo_id bigint := p_grupo_id;
  v_opciones integer;
  v_repetida text;
  v_productos bigint[] := array(select distinct x from unnest(coalesce(p_productos, '{}')) as x where x is not null);
  v_envio text;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if v_grupo_id is not null then
    perform 1 from public.grupos_opciones
    where id = v_grupo_id and restaurante_id = p_restaurante_id
    for update;
    if not found then
      raise exception 'Ese grupo ya no está en tu menú' using errcode = '23503';
    end if;
  end if;

  -- Lo que pide la ventana, revisado aquí también.
  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El nombre del grupo es obligatorio' using errcode = '22023';
  end if;
  if p_opciones is null or jsonb_typeof(p_opciones) <> 'array' or jsonb_array_length(p_opciones) = 0 then
    raise exception 'Agrega al menos una opción' using errcode = '22023';
  end if;
  v_opciones := jsonb_array_length(p_opciones);
  if exists (
    select 1 from jsonb_array_elements(p_opciones) o
    where coalesce(btrim(o ->> 'nombre'), '') = ''
  ) then
    raise exception 'Cada opción necesita su nombre' using errcode = '22023';
  end if;
  select min(btrim(o ->> 'nombre')) into v_repetida
  from jsonb_array_elements(p_opciones) o
  group by lower(btrim(o ->> 'nombre'))
  having count(*) > 1
  limit 1;
  if v_repetida is not null then
    raise exception 'Ya hay una opción que se llama «%» en este grupo', v_repetida using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_opciones) o
    where coalesce((o ->> 'precio_extra')::numeric, 0) < 0
  ) then
    raise exception 'El precio extra no puede ser negativo: una opción solo suma' using errcode = '22023';
  end if;
  if p_minimo is null or p_maximo is null or p_minimo < 0 or p_maximo < 1 or p_maximo < p_minimo then
    raise exception 'El máximo es por lo menos 1 y nunca menos que el mínimo' using errcode = '22023';
  end if;
  if p_maximo > v_opciones then
    raise exception 'El grupo tiene % opciones; no se pueden elegir más de %', v_opciones, v_opciones
      using errcode = '22023';
  end if;
  -- Las opciones con id son de este grupo; un grupo nuevo no trae ninguna con id.
  if exists (
    select 1 from jsonb_array_elements(p_opciones) o
    where o ->> 'id' is not null
      and not exists (
        select 1 from public.opciones op
        where op.id = (o ->> 'id')::bigint
          and op.restaurante_id = p_restaurante_id
          and op.grupo_id is not distinct from v_grupo_id
      )
  ) then
    raise exception 'Una de esas opciones ya no está en este grupo' using errcode = '23503';
  end if;
  if (select count(*) from public.productos
      where restaurante_id = p_restaurante_id and id = any (v_productos) and archivado_at is null)
     <> cardinality(v_productos) then
    raise exception 'Uno de esos productos ya no está en tu menú' using errcode = '23503';
  end if;
  select nombre into v_envio
  from public.productos
  where restaurante_id = p_restaurante_id and id = any (v_productos) and es_envio
  order by nombre, id
  limit 1;
  if found then
    raise exception '«%» es un envío: un envío no lleva opciones', v_envio using errcode = '22023';
  end if;

  -- El grupo.
  if v_grupo_id is null then
    insert into public.grupos_opciones (restaurante_id, nombre, nombre_en, minimo, maximo)
    values (p_restaurante_id, p_nombre, p_nombre_en, p_minimo, p_maximo)
    returning id into v_grupo_id;
  else
    update public.grupos_opciones
    set nombre = p_nombre, nombre_en = p_nombre_en, minimo = p_minimo, maximo = p_maximo
    where id = v_grupo_id;
  end if;

  -- Sus opciones, en el orden en que llegaron.
  delete from public.opciones op
  where op.restaurante_id = p_restaurante_id
    and op.grupo_id = v_grupo_id
    and op.id not in (
      select (o ->> 'id')::bigint from jsonb_array_elements(p_opciones) o where o ->> 'id' is not null
    );

  update public.opciones op
  set nombre = o.valor ->> 'nombre',
      nombre_en = o.valor ->> 'nombre_en',
      precio_extra = coalesce((o.valor ->> 'precio_extra')::numeric, 0),
      visible = coalesce((o.valor ->> 'visible')::boolean, true),
      orden = o.lugar
  from jsonb_array_elements(p_opciones) with ordinality as o (valor, lugar)
  where o.valor ->> 'id' is not null
    and op.id = (o.valor ->> 'id')::bigint
    and op.restaurante_id = p_restaurante_id
    and op.grupo_id = v_grupo_id;

  insert into public.opciones (restaurante_id, grupo_id, nombre, nombre_en, precio_extra, visible, orden)
  select p_restaurante_id, v_grupo_id, o.valor ->> 'nombre', o.valor ->> 'nombre_en',
         coalesce((o.valor ->> 'precio_extra')::numeric, 0),
         coalesce((o.valor ->> 'visible')::boolean, true),
         o.lugar
  from jsonb_array_elements(p_opciones) with ordinality as o (valor, lugar)
  where o.valor ->> 'id' is null;

  -- Los productos que lo llevan.
  delete from public.producto_grupos
  where restaurante_id = p_restaurante_id
    and grupo_id = v_grupo_id
    and producto_id <> all (v_productos);

  insert into public.producto_grupos (restaurante_id, producto_id, grupo_id)
  select p_restaurante_id, x, v_grupo_id from unnest(v_productos) as x
  on conflict do nothing;

  return v_grupo_id;
end;
$$;

revoke execute on function
  public.guardar_menu_en_linea(uuid, text, text, numeric, boolean),
  public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[], text, text, boolean)
from public, anon, service_role;

grant execute on function
  public.guardar_menu_en_linea(uuid, text, text, numeric, boolean),
  public.guardar_producto(uuid, bigint, bigint, text, text, numeric, text, bigint[], text, text, boolean)
to authenticated;


-- ─── El cierre del día con pg_cron ────────────────────────────────────────────
-- Cada hora en punto, en la base de Supabase. Programarlo otra vez con el mismo nombre lo
-- reemplaza.

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule('rechazar-pedidos-sin-confirmar', '0 * * * *', 'select privado.rechazar_sin_confirmar()');
