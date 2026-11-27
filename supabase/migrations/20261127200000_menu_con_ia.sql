-- El menú con IA (libreta 2, Diccionario de datos, la sección uso_ia; lo decidido en
-- planes/trabajo/menu-con-ia: encuestas.md y diccionario.md).
--
-- Don Chuy abre el Agente IA, elige «Armar mi menú con tu carta» y sube las fotos de su carta. El
-- Worker le pregunta aquí, con su sesión, si todavía puede leer otra este mes (puedo_leer_carta), y
-- solo entonces llama a gpt-6.1-sol. Lo que leyó vive en el navegador mientras Don Chuy lo revisa;
-- nada llega a la base hasta «Subir a mi menú», que lo sube todo de una vez (subir_a_mi_menu): solo
-- agrega, nunca borra ni cambia lo que ya tiene.
--
-- No hay tablas nuevas. Lo que cambia es el gasto: cada carta se anota en uso_ia por su lado, fuera
-- de los tres sobres, así que funciona aunque el tope del restaurante sea 0, como el día del alta.
-- Son 3 cartas al mes por restaurante (decidido el 27 de noviembre de 2026).


-- ─── uso_ia: las cartas ───────────────────────────────────────────────────────

alter table public.uso_ia
  add column cartas integer not null default 0
    constraint uso_ia_cartas_validas check (cartas >= 0),
  add column costo_cartas_usd numeric(10,4) not null default 0
    constraint uso_ia_costo_cartas_valido check (costo_cartas_usd >= 0);

-- Lo que gastó el restaurante en el mes, ahora con las cartas: así las de un cliente de distribuidor
-- salen de su parte, como toda la IA. Una columna generada no cambia de fórmula en todas las versiones
-- de Postgres: se quita y se vuelve a poner, como en la 6c.
alter table public.uso_ia drop column costo_usd;
alter table public.uso_ia
  add column costo_usd numeric(10,4)
    generated always as (costo_agente_usd + costo_anuncios_usd + costo_menu_usd + costo_cartas_usd) stored;


-- ─── Cuántas cartas al mes ────────────────────────────────────────────────────

-- Cuántas cartas puede leer cada restaurante al mes. Aquí vive el 3: si un día cambia, solo se cambia
-- esta función.
create function privado.cartas_al_mes()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 3;
$$;

-- Las cartas del mes: las que leyó (cartas de uso_ia; una que falló no cuenta) contra las que le
-- caben. Dos lecturas a la vez pueden pasarse de 3 por una: entonces le quedan 0, sin restar nada.
create function privado.cartas_del_mes(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'de', privado.cartas_al_mes(),
    'quedan', greatest(privado.cartas_al_mes() - coalesce(u.cartas, 0), 0),
    'vuelve', (privado.mes_ia(r.zona_horaria) + interval '1 month')::date
  )
  from public.restaurantes r
  left join public.uso_ia u on u.restaurante_id = r.id and u.mes = privado.mes_ia(r.zona_horaria)
  where r.id = p_restaurante_id;
$$;

revoke execute on function
  privado.cartas_al_mes(),
  privado.cartas_del_mes(uuid)
from public, anon, authenticated, service_role;

-- Si Don Chuy todavía puede leer otra carta este mes: {puede, quedan, de, vuelve}. La llaman el Worker
-- antes de llamar a OpenAI y la ventana «Tu carta» («Te quedan 2 de 3 este mes»; sin ninguna, «Vuelve
-- el 1 de diciembre.»), las dos con su sesión. Solo el gerente, con la licencia vigente, como todo Mi
-- menú. No mira el tope: las cartas no son un sobre.
create function public.puedo_leer_carta(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cartas jsonb;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;

  v_cartas := privado.cartas_del_mes(p_restaurante_id);
  return jsonb_build_object('puede', (v_cartas ->> 'quedan')::integer > 0) || v_cartas;
end;
$$;

revoke execute on function public.puedo_leer_carta(uuid) from public, anon, service_role;
grant execute on function public.puedo_leer_carta(uuid) to authenticated;


-- ─── El gasto de IA ───────────────────────────────────────────────────────────

-- Como en la 7b-1, y además las cartas: «carta» es una lectura que llegó (suma una a cartas y su
-- costo a costo_cartas_usd) y «carta_sin_lectura», una que falló a medias (solo el costo, si OpenAI
-- la cobró). Ninguna toca los sobres ni las consultas. Regresa el costo y si todavía puede: para una
-- carta, si le queda otra este mes; para lo demás, si su sobre todavía puede gastar.
create or replace function public.anotar_uso_ia(
  p_restaurante_id uuid,
  p_uso text,
  p_modelo text,
  p_entrada bigint,
  p_entrada_cache bigint,
  p_escritura_cache bigint,
  p_salida bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_zona text;
  v_costo numeric(10,4);
  v_menu boolean := p_uso in ('menu', 'menu_sin_respuesta');
  v_palabras boolean := p_uso = 'palabras';
  v_carta boolean := p_uso in ('carta', 'carta_sin_lectura');
begin
  if p_uso is null
     or p_uso not in ('pregunta', 'saludo', 'menu', 'menu_sin_respuesta', 'palabras', 'carta', 'carta_sin_lectura') then
    raise exception 'El uso de IA es pregunta, saludo, menu, menu_sin_respuesta, palabras, carta o carta_sin_lectura'
      using errcode = '22023';
  end if;
  if p_entrada is null or p_entrada_cache is null or p_escritura_cache is null or p_salida is null
     or p_entrada < 0 or p_entrada_cache < 0 or p_escritura_cache < 0 or p_salida < 0 then
    raise exception 'Los tokens van completos y en 0 o más' using errcode = '22023';
  end if;
  if p_entrada_cache + p_escritura_cache > p_entrada then
    raise exception 'Los tokens de caché van dentro de los de entrada' using errcode = '22023';
  end if;

  select zona_horaria into v_zona from public.restaurantes where id = p_restaurante_id;
  if not found then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;
  v_costo := privado.costo_ia(p_modelo, p_entrada, p_entrada_cache, p_escritura_cache, p_salida);
  if v_costo is null then
    raise exception 'No hay precio para el modelo %', p_modelo using errcode = 'P0002';
  end if;

  insert into public.uso_ia as u (
    restaurante_id, mes, consultas_agente, saludos, costo_agente_usd, consultas_menu, costo_menu_usd,
    costo_anuncios_usd, cartas, costo_cartas_usd
  ) values (
    p_restaurante_id, privado.mes_ia(v_zona),
    case when p_uso = 'pregunta' then 1 else 0 end,
    case when p_uso = 'saludo' then 1 else 0 end,
    case when v_menu or v_palabras or v_carta then 0 else v_costo end,
    case when p_uso = 'menu' then 1 else 0 end,
    case when v_menu then v_costo else 0 end,
    case when v_palabras then v_costo else 0 end,
    case when p_uso = 'carta' then 1 else 0 end,
    case when v_carta then v_costo else 0 end
  )
  on conflict (restaurante_id, mes) do update
  set consultas_agente = u.consultas_agente + excluded.consultas_agente,
      saludos = u.saludos + excluded.saludos,
      costo_agente_usd = u.costo_agente_usd + excluded.costo_agente_usd,
      consultas_menu = u.consultas_menu + excluded.consultas_menu,
      costo_menu_usd = u.costo_menu_usd + excluded.costo_menu_usd,
      costo_anuncios_usd = u.costo_anuncios_usd + excluded.costo_anuncios_usd,
      cartas = u.cartas + excluded.cartas,
      costo_cartas_usd = u.costo_cartas_usd + excluded.costo_cartas_usd;

  return jsonb_build_object(
    'costo', v_costo,
    'puede', case
               when v_carta then to_jsonb((privado.cartas_del_mes(p_restaurante_id) ->> 'quedan')::integer > 0)
               else privado.saldo_ia(p_restaurante_id,
                      case when v_menu then 'menu' when v_palabras then 'anuncios' else 'agente' end) -> 'puede'
             end);
end;
$$;

-- La ventana «Tope de IA», como en la 7b-3, y además las cartas del mes en su propio renglón: cuántas
-- leyó y cuánto costaron. No son un sobre, así que no traen parte ni límite; «gastado» ya las suma.
create or replace function public.uso_ia_cliente(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uso jsonb;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'mes', privado.mes_ia(r.zona_horaria),
    'tope', r.tope_ia_usd_mes,
    'gastado', coalesce(u.costo_usd, 0)::numeric(10,4),
    'sobre_agente', privado.parte_del_tope(r.tope_ia_usd_mes, 'agente'),
    'gastado_agente', coalesce(u.costo_agente_usd, 0)::numeric(10,4),
    'consultas_agente', coalesce(u.consultas_agente, 0),
    'saludos', coalesce(u.saludos, 0),
    'agente_en_limite', (privado.saldo_ia(r.id, 'agente') ->> 'motivo') is not distinct from 'limite',
    'sobre_anuncios', privado.parte_del_tope(r.tope_ia_usd_mes, 'anuncios'),
    'gastado_anuncios', coalesce(u.costo_anuncios_usd, 0)::numeric(10,4),
    'anuncios', coalesce(u.anuncios, 0),
    'anuncios_caben', privado.anuncios_que_caben(r.tope_ia_usd_mes),
    'anuncios_en_limite', (privado.saldo_ia(r.id, 'anuncios') ->> 'motivo') is not distinct from 'limite',
    'sobre_menu', privado.parte_del_tope(r.tope_ia_usd_mes, 'menu'),
    'gastado_menu', coalesce(u.costo_menu_usd, 0)::numeric(10,4),
    'consultas_menu', coalesce(u.consultas_menu, 0),
    'menu_en_limite', (privado.saldo_ia(r.id, 'menu') ->> 'motivo') is not distinct from 'limite',
    'cartas', coalesce(u.cartas, 0),
    'gastado_cartas', coalesce(u.costo_cartas_usd, 0)::numeric(10,4),
    'distribuidor_id', r.distribuidor_id,
    'distribuidor', d.nombre
  )
  into v_uso
  from public.restaurantes r
  left join public.uso_ia u on u.restaurante_id = r.id and u.mes = privado.mes_ia(r.zona_horaria)
  left join public.distribuidores d on d.id = r.distribuidor_id
  where r.id = p_restaurante_id;
  if v_uso is null then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;
  return v_uso;
end;
$$;


-- ─── «Subir a mi menú» ────────────────────────────────────────────────────────

-- Sube lo que Don Chuy revisó, todo o nada: [{nombre, icono, productos: [{nombre, descripcion,
-- precio}]}], en el orden de su carta. Una categoría que ya tiene (el mismo nombre sin contar
-- mayúsculas, entre las no archivadas) recibe sus productos y se queda como está; una nueva lleva su
-- ícono y va a la primera área de preparación, o a «Lo sirve el mesero» si no tiene áreas, igual que al
-- crear una a mano en Mi menú. Los productos entran visibles, sin foto, después de lo que ya hay y en el
-- orden en que llegan; sin descripción si viene vacía, y su inglés vacío para que la IA lo traduzca.
-- Ninguno sin precio. Regresa {categorias_nuevas, productos}: cuántas categorías nuevas y cuántos
-- productos subió.
create function public.subir_a_mi_menu(p_restaurante_id uuid, p_categorias jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_area_id bigint;
  v_categoria jsonb;
  v_categoria_id bigint;
  v_nombre text;
  v_icono text;
  v_producto jsonb;
  v_producto_nombre text;
  v_precio numeric;
  v_nuevas integer := 0;
  v_productos integer := 0;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su menú' using errcode = '42501';
  end if;
  if p_categorias is null or jsonb_typeof(p_categorias) <> 'array' or jsonb_array_length(p_categorias) = 0 then
    raise exception 'No hay nada que subir a tu menú' using errcode = '22023';
  end if;
  -- El tope de una vez: una carta de 6 hojas trae mucho menos.
  if jsonb_array_length(p_categorias) > 40 then
    raise exception 'Son muchas categorías de una vez: sube a lo mucho 40' using errcode = '22023';
  end if;
  if (select coalesce(sum(jsonb_array_length(c.value -> 'productos')), 0)
      from jsonb_array_elements(p_categorias) c
      where jsonb_typeof(c.value -> 'productos') = 'array') > 400 then
    raise exception 'Son muchos productos de una vez: sube a lo mucho 400' using errcode = '22023';
  end if;

  -- La primera área, como la elige la ventana de una categoría nueva en Mi menú (las enseña por id).
  select a.id into v_area_id
  from public.areas_preparacion a
  where a.restaurante_id = p_restaurante_id and a.archivado_at is null
  order by a.id
  limit 1;

  for v_categoria in select c.value from jsonb_array_elements(p_categorias) c loop
    if jsonb_typeof(v_categoria) <> 'object' then
      raise exception 'Cada categoría va con su nombre y sus productos' using errcode = '22023';
    end if;
    v_nombre := btrim(v_categoria ->> 'nombre');
    if v_nombre is null or v_nombre = '' then
      raise exception 'Una categoría no tiene nombre' using errcode = '22023';
    end if;
    if jsonb_typeof(v_categoria -> 'productos') is distinct from 'array'
       or jsonb_array_length(v_categoria -> 'productos') = 0 then
      raise exception '«%» no tiene productos', v_nombre using errcode = '22023';
    end if;

    -- Si ya la tiene (o ya llegó antes en esta misma carta), sus productos entran ahí.
    select c.id into v_categoria_id
    from public.categorias c
    where c.restaurante_id = p_restaurante_id
      and c.archivado_at is null
      and lower(c.nombre) = lower(v_nombre);
    if not found then
      v_icono := nullif(btrim(v_categoria ->> 'icono'), '');
      if v_icono is null then
        raise exception 'Falta el ícono de «%»', v_nombre using errcode = '22023';
      end if;
      insert into public.categorias (restaurante_id, nombre, icono, area_preparacion_id)
      values (p_restaurante_id, v_nombre, v_icono, v_area_id)
      returning id into v_categoria_id;
      v_nuevas := v_nuevas + 1;
    end if;

    for v_producto in select p.value from jsonb_array_elements(v_categoria -> 'productos') p loop
      if jsonb_typeof(v_producto) <> 'object' then
        raise exception 'Cada producto de «%» va con su nombre y su precio', v_nombre using errcode = '22023';
      end if;
      v_producto_nombre := btrim(v_producto ->> 'nombre');
      if v_producto_nombre is null or v_producto_nombre = '' then
        raise exception 'Un producto de «%» no tiene nombre', v_nombre using errcode = '22023';
      end if;
      if jsonb_typeof(v_producto -> 'precio') is distinct from 'number' then
        raise exception 'Falta el precio de «%»', v_producto_nombre using errcode = '22023';
      end if;
      v_precio := (v_producto ->> 'precio')::numeric;
      if v_precio < 0 or v_precio > 9999999999.99 then
        raise exception 'Revisa el precio de «%»', v_producto_nombre using errcode = '22023';
      end if;
      if jsonb_typeof(v_producto -> 'descripcion') not in ('string', 'null') then
        raise exception 'Revisa la descripción de «%»', v_producto_nombre using errcode = '22023';
      end if;

      insert into public.productos (restaurante_id, categoria_id, nombre, descripcion, precio)
      values (p_restaurante_id, v_categoria_id, v_producto_nombre, v_producto ->> 'descripcion', v_precio);
      v_productos := v_productos + 1;
    end loop;
  end loop;

  return jsonb_build_object('categorias_nuevas', v_nuevas, 'productos', v_productos);
end;
$$;

revoke execute on function public.subir_a_mi_menu(uuid, jsonb) from public, anon, service_role;
grant execute on function public.subir_a_mi_menu(uuid, jsonb) to authenticated;
