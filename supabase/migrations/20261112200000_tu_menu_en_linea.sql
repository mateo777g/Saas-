-- Tu menú en línea y las formas del menú digital (decidido del 10 al 12 de noviembre de 2026; libreta 2,
-- Diccionario de datos, y la maqueta UDArhiEZceT7rmSKxqRA5r de la segunda cuenta, versión 59).
--
-- Cada menú elige cómo se ve: el color de su barra y de su fondo, y la forma de cada pieza (la barra de
-- arriba, el idioma y la moneda, la búsqueda, los carteles y su «i», las categorías, el orden de las tres
-- piezas de arriba, los títulos, los productos, lo de abajo y la vista del producto). Una columna por
-- cosa en restaurantes, cada una con su regla; los defaults son como nace hoy un menú, así que al subir
-- esta migración todos se ven como en la maqueta sin tocar nada.
--
-- Un cartel es una imagen subida o un producto de Mi menú con foto: el menú enseña su foto y, si así se
-- eligió, su nombre y su precio, que toma del producto mismo. Si el producto se borra, el cartel se va
-- con él; si pierde su foto o se archiva, se queda en «Tus carteles» y no sale en el menú.
--
-- El teléfono se pide también para llevar, para que la caja le pueda llamar al cliente si su mensaje no
-- llegó. Los pedidos para llevar de antes no lo tienen y se quedan así.
--
-- «Hago envíos» se guarda con Tu restaurante. estado_menu_en_linea, mover_cartel y quitar_cartel no
-- cambian (quitar un cartel de producto regresa vacío: no hay imagen que borrar).


-- ─── Las formas, en restaurantes ──────────────────────────────────────────────

alter table public.restaurantes
  add column menu_color_barra text
    constraint restaurantes_menu_color_barra_formato check (menu_color_barra ~ '^#[0-9A-F]{6}$'),
  add column menu_fondo text
    constraint restaurantes_menu_fondo_formato check (menu_fondo ~ '^#[0-9A-F]{6}$'),
  add column menu_barra text not null default 'izquierda'
    constraint restaurantes_menu_barra_lista check (menu_barra in ('izquierda', 'centro')),
  add column menu_con_nombre boolean not null default true,
  add column menu_idioma text not null default 'letras'
    constraint restaurantes_menu_idioma_lista check (menu_idioma in ('letras', 'planeta', 'cuadro')),
  add column menu_moneda text not null default 'letras'
    constraint restaurantes_menu_moneda_lista check (menu_moneda in ('letras', 'monedas', 'cuadro')),
  add column menu_busqueda text not null default 'gris'
    constraint restaurantes_menu_busqueda_lista check (menu_busqueda in ('gris', 'blanca', 'tarjeta')),
  add column menu_carteles text not null default 'esquinas'
    constraint restaurantes_menu_carteles_lista check (menu_carteles in ('esquinas', 'completo', 'bajito')),
  add column menu_info text not null default 'capsula'
    constraint restaurantes_menu_info_lista check (menu_info in ('capsula', 'icono')),
  add column menu_info_lugar text not null default 'arriba'
    constraint restaurantes_menu_info_lugar_lista check (menu_info_lugar in ('arriba', 'abajo')),
  add column menu_carteles_producto text not null default 'nombre'
    constraint restaurantes_menu_carteles_producto_lista check (menu_carteles_producto in ('nombre', 'foto')),
  add column menu_categorias text not null default 'pestanas'
    constraint restaurantes_menu_categorias_lista check (menu_categorias in (
      'pestanas', 'rectangulos', 'tarjeta', 'pildoras', 'circulos_icono', 'circulos_foto')),
  add column menu_orden text[] not null default array['carteles', 'busqueda', 'categorias']
    constraint restaurantes_menu_orden_lista
    check (cardinality(menu_orden) = 3 and menu_orden @> array['carteles', 'busqueda', 'categorias']),
  add column menu_titulos text not null default 'icono'
    constraint restaurantes_menu_titulos_lista check (menu_titulos in ('icono', 'nombre', 'raya')),
  add column menu_productos text not null default 'a_lo_largo'
    constraint restaurantes_menu_productos_lista
    check (menu_productos in ('a_lo_largo', 'intercalado', 'dos_en_dos', 'clasicas')),
  add column menu_abajo text not null default 'barra'
    constraint restaurantes_menu_abajo_lista check (menu_abajo in ('barra', 'pildora')),
  add column menu_abajo_con_nombres boolean not null default true,
  add column menu_producto_ventana text not null default 'completa'
    constraint restaurantes_menu_producto_ventana_lista check (menu_producto_ventana in ('completa', 'ventana')),
  add column menu_producto_titulo text not null default 'abajo'
    constraint restaurantes_menu_producto_titulo_lista check (menu_producto_titulo in ('abajo', 'arriba')),
  add column menu_producto_opciones text not null default 'juntas'
    constraint restaurantes_menu_producto_opciones_lista check (menu_producto_opciones in ('juntas', 'pasos'));

-- El panel las lee directo, como el tema y el color; se escriben con guardar_menu_en_linea.
grant select (
  menu_color_barra, menu_fondo, menu_barra, menu_con_nombre, menu_idioma, menu_moneda, menu_busqueda,
  menu_carteles, menu_info, menu_info_lugar, menu_carteles_producto, menu_categorias, menu_orden,
  menu_titulos, menu_productos, menu_abajo, menu_abajo_con_nombres, menu_producto_ventana,
  menu_producto_titulo, menu_producto_opciones
) on public.restaurantes to authenticated;


-- ─── Un cartel puede ser un producto ──────────────────────────────────────────
-- Una imagen subida o un producto, nunca los dos ni ninguno. Un producto no se repite en los carteles
-- de su restaurante. La regla de la carpeta de la imagen sigue valiendo cuando hay imagen.

alter table public.carteles
  alter column imagen_ruta drop not null,
  add column producto_id bigint,
  add constraint carteles_producto foreign key (restaurante_id, producto_id)
    references public.productos (restaurante_id, id) on delete cascade,
  add constraint carteles_imagen_o_producto check ((imagen_ruta is null) <> (producto_id is null)),
  add constraint carteles_producto_unico unique (restaurante_id, producto_id);

grant select (producto_id) on public.carteles to authenticated;


-- ─── El teléfono, también para llevar ─────────────────────────────────────────
-- A domicilio sigue pidiendo teléfono y dirección; para llevar, ahora el teléfono, sin dirección,
-- referencias ni «paga con». La regla del teléfono para llevar no revisa los pedidos de antes (not
-- valid): ya están atendidos y no vuelven a cambiar.

alter table public.pedidos_en_linea
  drop constraint pedidos_en_linea_domicilio,
  add constraint pedidos_en_linea_domicilio check (
    case when tipo = 'domicilio'
      then cliente_telefono is not null and cliente_direccion is not null
      else cliente_direccion is null and cliente_referencias is null and paga_con is null
    end
  ),
  add constraint pedidos_en_linea_telefono_para_llevar
    check (tipo <> 'para_llevar' or cliente_telefono is not null) not valid;

-- Uno para llevar «por confirmar» sin teléfono chocaría al confirmarlo o rechazarlo: si hay alguno,
-- esta migración se para sin cambiar nada (la tabla ya quedó bloqueada arriba hasta el final).
do $$
begin
  if exists (
    select 1 from public.pedidos_en_linea
    where tipo = 'para_llevar' and cliente_telefono is null and estado = 'por_confirmar'
  ) then
    raise exception 'Hay pedidos para llevar por confirmar sin teléfono: que se atiendan y vuelve a subir esta migración';
  end if;
end;
$$;

-- La cuenta: a domicilio, teléfono y dirección; para llevar, el teléfono si lo trae el pedido del menú
-- en línea (el «Para llevar» del punto de venta no lo pide), sin dirección; en mesa, ninguno.
alter table public.ventas
  drop constraint ventas_domicilio,
  add constraint ventas_domicilio check (
    case tipo
      when 'domicilio'
        then coalesce(btrim(cliente_telefono), '') <> '' and coalesce(btrim(cliente_direccion), '') <> ''
      when 'para_llevar' then cliente_direccion is null
      else cliente_telefono is null and cliente_direccion is null
    end
  );


-- ─── «Guardar» de Tu restaurante, con «Hago envíos» ───────────────────────────
-- Como en la 6a, y además «Hago envíos», que se fue de Tu menú en línea; vacío lo deja como estaba.

drop function public.guardar_restaurante(uuid, text, text, text, text, jsonb);

-- «Guardar» de Tu restaurante: los datos, el horario y «Hago envíos», juntos. p_logo_ruta es el logo
-- que debe quedar (el mismo, uno nuevo que ya subió el Worker, o vacío para quitarlo). p_horario trae
-- {dia, abre, cierra} por cada día que abre, con las horas como '9:00'; los días que no llegan quedan
-- cerrados. Regresa la ruta del logo anterior si cambió, para que la app le pida al Worker borrarla.
create function public.guardar_restaurante(
  p_restaurante_id uuid,
  p_nombre text,
  p_telefono text,
  p_direccion text,
  p_logo_ruta text,
  p_horario jsonb,
  p_hace_envios boolean default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text := btrim(coalesce(p_nombre, ''));
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


-- ─── «Guardar» de Tu menú en línea, con todas las formas ──────────────────────

drop function public.guardar_menu_en_linea(uuid, text, text, boolean);

-- «Guardar» de la barra de guardar: el tema, los tres colores y las 18 formas, todo junto. Un color
-- vacío es el de siempre (el neutro, el de menu_color en la barra, el blanco o el negro del tema en el
-- fondo). Cada forma la revisa su regla de la tabla: una que no existe se rechaza.
create function public.guardar_menu_en_linea(
  p_restaurante_id uuid,
  p_tema text,
  p_color text,
  p_color_barra text,
  p_fondo text,
  p_barra text,
  p_con_nombre boolean,
  p_idioma text,
  p_moneda text,
  p_busqueda text,
  p_carteles text,
  p_info text,
  p_info_lugar text,
  p_carteles_producto text,
  p_categorias text,
  p_orden text[],
  p_titulos text,
  p_productos text,
  p_abajo text,
  p_abajo_con_nombres boolean,
  p_producto_ventana text,
  p_producto_titulo text,
  p_producto_opciones text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_color text := upper(nullif(btrim(p_color), ''));
  v_color_barra text := upper(nullif(btrim(p_color_barra), ''));
  v_fondo text := upper(nullif(btrim(p_fondo), ''));
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
  if v_color_barra !~ '^#[0-9A-F]{6}$' then
    raise exception 'El color de la barra no se entiende; escríbelo como #B3261E' using errcode = '22023';
  end if;
  if v_fondo !~ '^#[0-9A-F]{6}$' then
    raise exception 'El color del fondo no se entiende; escríbelo como #F4F1EA' using errcode = '22023';
  end if;

  update public.restaurantes
  set menu_tema = p_tema,
      menu_color = v_color,
      menu_color_barra = v_color_barra,
      menu_fondo = v_fondo,
      menu_barra = p_barra,
      menu_con_nombre = p_con_nombre,
      menu_idioma = p_idioma,
      menu_moneda = p_moneda,
      menu_busqueda = p_busqueda,
      menu_carteles = p_carteles,
      menu_info = p_info,
      menu_info_lugar = p_info_lugar,
      menu_carteles_producto = p_carteles_producto,
      menu_categorias = p_categorias,
      menu_orden = p_orden,
      menu_titulos = p_titulos,
      menu_productos = p_productos,
      menu_abajo = p_abajo,
      menu_abajo_con_nombres = p_abajo_con_nombres,
      menu_producto_ventana = p_producto_ventana,
      menu_producto_titulo = p_producto_titulo,
      menu_producto_opciones = p_producto_opciones
  where id = p_restaurante_id;
end;
$$;


-- ─── «Tus carteles»: una imagen o un producto ─────────────────────────────────

-- ¿Puede este producto ser un cartel? Debe ser de ese restaurante, no archivado (ni un envío), con
-- foto y sin estar ya en otro de sus carteles (p_cartel_id es el que se cambia, que no cuenta). Si
-- no, un error en español para la ventana.
create function privado.revisar_producto_cartel(p_restaurante_id uuid, p_producto_id bigint, p_cartel_id bigint)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_foto text;
begin
  select p.imagen_ruta into v_foto
  from public.productos p
  where p.restaurante_id = p_restaurante_id
    and p.id = p_producto_id
    and p.archivado_at is null
    and not p.es_envio;
  if not found then
    raise exception 'Ese producto ya no está en tu menú.' using errcode = '22023';
  end if;
  if v_foto is null then
    raise exception 'Ese producto no tiene foto. Ponle una en Mi menú.' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.carteles c
    where c.restaurante_id = p_restaurante_id
      and c.producto_id = p_producto_id
      and c.id is distinct from p_cartel_id
  ) then
    raise exception 'Ese producto ya está en tus carteles.' using errcode = '23505';
  end if;
end;
$$;

revoke execute on function privado.revisar_producto_cartel(uuid, bigint, bigint)
from public, anon, authenticated, service_role;

drop function public.agregar_cartel(uuid, text);

-- «Subir imagen» o «Foto de un producto» de Tus carteles: la imagen ya la subió el Worker, o el
-- producto. Va al final; con 5 ya no cabe otro. Regresa el id del cartel.
create function public.agregar_cartel(
  p_restaurante_id uuid,
  p_imagen_ruta text default null,
  p_producto_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_imagen text := nullif(btrim(p_imagen_ruta), '');
  v_id bigint;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if (v_imagen is null) = (p_producto_id is null) then
    raise exception 'Un cartel lleva una imagen o un producto' using errcode = '22023';
  end if;

  -- Bloquea el restaurante: dos carteles a la vez no pasan juntos de 5 ni repiten un producto.
  perform 1 from public.restaurantes where id = p_restaurante_id for no key update;

  if (select count(*) from public.carteles where restaurante_id = p_restaurante_id) >= 5 then
    raise exception 'Ya tienes 5 carteles. Quita uno para agregar otro.' using errcode = '55000';
  end if;
  if p_producto_id is not null then
    perform privado.revisar_producto_cartel(p_restaurante_id, p_producto_id, null);
  end if;

  insert into public.carteles (restaurante_id, imagen_ruta, producto_id, orden)
  values (
    p_restaurante_id,
    v_imagen,
    p_producto_id,
    coalesce((select max(orden) from public.carteles where restaurante_id = p_restaurante_id), 0) + 1
  )
  returning id into v_id;
  return v_id;
end;
$$;

drop function public.cambiar_cartel(bigint, text);

-- «Cambiar» de un cartel: otra imagen u otro producto, en su mismo lugar. Regresa la ruta de la imagen
-- anterior si se fue (también si pasa de imagen a producto), para que la app le pida al Worker borrarla.
create function public.cambiar_cartel(
  p_cartel_id bigint,
  p_imagen_ruta text default null,
  p_producto_id bigint default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_imagen text := nullif(btrim(p_imagen_ruta), '');
  v_restaurante_id uuid;
  v_antes text;
begin
  select restaurante_id into v_restaurante_id
  from public.carteles
  where id = p_cartel_id
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if (v_imagen is null) = (p_producto_id is null) then
    raise exception 'Un cartel lleva una imagen o un producto' using errcode = '22023';
  end if;

  -- Como al agregar: primero el restaurante, luego el cartel.
  perform 1 from public.restaurantes where id = v_restaurante_id for no key update;
  select imagen_ruta into v_antes from public.carteles where id = p_cartel_id for update;
  if not found then
    raise exception 'Ese cartel ya no está' using errcode = '22023';
  end if;
  if p_producto_id is not null then
    perform privado.revisar_producto_cartel(v_restaurante_id, p_producto_id, p_cartel_id);
  end if;

  update public.carteles
  set imagen_ruta = v_imagen, producto_id = p_producto_id
  where id = p_cartel_id;
  return case when v_antes is distinct from v_imagen then v_antes end;
end;
$$;


-- ─── El menú que ve la clienta ────────────────────────────────────────────────
-- Como en mi_menu, y además el color de la barra, el fondo y las formas (en restaurante.formas, con
-- los nombres de sus columnas sin «menu_»), y cada cartel como {ruta, producto_id}: la ruta es la
-- imagen subida o la foto del producto. El nombre, el precio y el «Desde» de un cartel de producto los
-- toma el menú del producto mismo, que le llega en su categoría; por eso sale solo si ese producto sale
-- en el menú (a la vista y con foto).

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


-- ─── «Hacer pedido», con el teléfono también para llevar ──────────────────────
-- Como en la 6b, y el teléfono se pide igual para llevar y a domicilio. Lo demás de domicilio
-- (dirección, referencias y «paga con») sigue vacío para llevar.

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


-- ─── Permisos ─────────────────────────────────────────────────────────────────

revoke execute on function
  public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean),
  public.guardar_menu_en_linea(
    uuid, text, text, text, text, text, boolean, text, text, text, text, text, text, text, text, text[],
    text, text, text, boolean, text, text, text),
  public.agregar_cartel(uuid, text, bigint),
  public.cambiar_cartel(bigint, text, bigint)
from public, anon, service_role;

grant execute on function
  public.guardar_restaurante(uuid, text, text, text, text, jsonb, boolean),
  public.guardar_menu_en_linea(
    uuid, text, text, text, text, text, boolean, text, text, text, text, text, text, text, text, text[],
    text, text, text, boolean, text, text, text),
  public.agregar_cartel(uuid, text, bigint),
  public.cambiar_cartel(bigint, text, bigint)
to authenticated;
