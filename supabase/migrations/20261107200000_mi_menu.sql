-- Mi menú (decidido el 6 y el 7 de noviembre de 2026): los dólares se ponen solos y el inglés lo
-- traduce la IA.
--
-- Los dólares: el tipo de cambio ya no lo escribe cada gerente. Hay uno solo para todos los
-- restaurantes (tipo_de_cambio, una fila), que el Cron diario del Worker pone con lo que contesta
-- Frankfurter; si no contesta, se queda el último. Esta migración pone el primero, así que siempre
-- hay dólares en el menú. En el panel ya no se ve nada del dólar.
--
-- El inglés: vacío quiere decir que falta traducirlo. Si cambia el español y el inglés no, el inglés
-- se vacía solo para volver a traducirlo; si cambian los dos, se queda lo que escribió el gerente. El
-- Worker pide lo que falta con la sesión del gerente (pendientes_de_traducir), lo traduce con
-- gpt-5.6-luna y lo escribe con su llave (guardar_traducciones), solo si el español sigue igual y el
-- inglés sigue vacío. Su gasto entra al sobre del asistente del menú (anotar_uso_ia con
-- 'menu_sin_respuesta', que suma sin contar una pregunta): siguen 4 agente, 4 anuncios y 2 asistente.


-- ─── El tipo de cambio ────────────────────────────────────────────────────────

-- Una sola fila: como moneda solo acepta 'USD', nunca hay otra. Nadie la lee ni la escribe directo:
-- menu_publico la usa para los precios en dólares y el Worker la escribe con fijar_tipo_de_cambio.
create table public.tipo_de_cambio (
  moneda text primary key
    constraint tipo_de_cambio_solo_usd check (moneda = 'USD'),
  pesos numeric(8,4) not null
    constraint tipo_de_cambio_positivo check (pesos > 0),
  updated_at timestamptz not null default now()
);

alter table public.tipo_de_cambio enable row level security;
revoke all on table public.tipo_de_cambio from public, anon, authenticated, service_role;

-- El dólar del 6 de noviembre de 2026, el último que dio Frankfurter al escribir esta migración.
insert into public.tipo_de_cambio (moneda, pesos) values ('USD', 18.7040);

-- El Cron diario del Worker, con la llave secreta: pone el dólar del día, redondeado a 4 decimales,
-- y regresa lo que quedó. Un número que no tiene sentido no se guarda y se queda el último.
create function public.fijar_tipo_de_cambio(p_pesos numeric)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pesos numeric := round(p_pesos, 4);
begin
  if v_pesos is null or v_pesos <= 0 or v_pesos >= 10000 then
    raise exception 'El tipo de cambio va en pesos por dólar, como 18.7040' using errcode = '22023';
  end if;

  insert into public.tipo_de_cambio (moneda, pesos, updated_at)
  values ('USD', v_pesos, now())
  on conflict (moneda) do update
  set pesos = excluded.pesos,
      updated_at = excluded.updated_at;

  return v_pesos::numeric(8,4);
end;
$$;

revoke execute on function public.fijar_tipo_de_cambio(numeric) from public, anon, authenticated;
grant execute on function public.fijar_tipo_de_cambio(numeric) to service_role;


-- ─── Se va el tipo de cambio de cada restaurante ──────────────────────────────

-- «Guardar» de Cómo se ve, como en la 6b, sin el dólar. p_hace_envios vacío lo deja como estaba.
drop function public.guardar_menu_en_linea(uuid, text, text, numeric, boolean);

alter table public.restaurantes drop column tipo_cambio_usd;

create function public.guardar_menu_en_linea(
  p_restaurante_id uuid,
  p_tema text,
  p_color text,
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

  update public.restaurantes
  set menu_tema = p_tema,
      menu_color = v_color,
      hace_envios = coalesce(p_hace_envios, hace_envios)
  where id = p_restaurante_id;
end;
$$;

revoke execute on function public.guardar_menu_en_linea(uuid, text, text, boolean) from public, anon, service_role;
grant execute on function public.guardar_menu_en_linea(uuid, text, text, boolean) to authenticated;


-- ─── El menú que ve la clienta ────────────────────────────────────────────────
-- Como en la 6c, con los dólares del tipo de cambio de todos: mismos nombres (tipo_cambio_usd,
-- precio_usd, precio_extra_usd), así el menú en línea no cambia.

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
      'tipo_cambio_usd', v_dolar,
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
    'asistente_contesta', (privado.saldo_ia(v_r.id, 'menu') ->> 'puede')::boolean,
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


-- ─── Vacío quiere decir que falta traducir ────────────────────────────────────

-- Como en la 6a (los nombres sin espacios sobrantes y un texto en blanco, vacío), y además, en las
-- cuatro tablas del menú: si al cambiar un renglón cambia el español y el inglés no, el inglés se
-- vacía para que la IA lo vuelva a traducir; si cambian los dos, se queda lo que escribió el gerente.
-- Sin descripción en español no hay descripción en inglés. Así cubre guardar_producto, guardar_grupo
-- y lo que la app escribe directo (las categorías). Mesas y áreas solo se limpian, como antes.
create or replace function privado.limpiar_menu()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nombre := btrim(new.nombre);
  if tg_table_name = 'productos' then
    new.descripcion := nullif(btrim(new.descripcion), '');
    new.descripcion_en := nullif(btrim(new.descripcion_en), '');
    if new.descripcion is null then
      new.descripcion_en := null;
    end if;
  end if;
  if tg_table_name in ('categorias', 'productos', 'grupos_opciones', 'opciones') then
    new.nombre_en := nullif(btrim(new.nombre_en), '');
    if tg_op = 'UPDATE' then
      if new.nombre is distinct from old.nombre and new.nombre_en is not distinct from old.nombre_en then
        new.nombre_en := null;
      end if;
      -- Anidado: PL/pgSQL revisa toda la condición, y las demás tablas no tienen descripción.
      if tg_table_name = 'productos' then
        if new.descripcion is distinct from old.descripcion
           and new.descripcion_en is not distinct from old.descripcion_en then
          new.descripcion_en := null;
        end if;
      end if;
    end if;
  end if;
  return new;
end;
$$;


-- ─── Lo que falta traducir (con la sesión del gerente) ────────────────────────

-- Al abrir Mi menú y después de cada «Guardar», la app le pide al Worker que traduzca; el Worker
-- llama aquí con la sesión de Don Chuy, así que Postgres decide si puede. Regresa {puede, motivo,
-- quedan, pendientes}: quedan son todos los que faltan y pendientes, los primeros 20 (categorías,
-- productos, grupos y opciones, en el orden de su menú), cada uno con su español: {tipo, id, nombre,
-- descripcion, grupo}. La descripción va solo si le falta su inglés; grupo es el nombre del grupo de
-- una opción, para que «Verde» en «Salsa» salga «Green». Sin archivados ni envíos. puede sale del
-- sobre del menú: con el tope en 0 o el sobre gastado, no se traduce y pendientes va vacío.
create function public.pendientes_de_traducir(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_saldo jsonb;
  v_quedan integer;
  v_pendientes jsonb;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante traduce su menú' using errcode = '42501';
  end if;
  v_saldo := privado.saldo_ia(p_restaurante_id, 'menu');

  with faltan as (
    select 1 as tipo_orden, 'categoria' as tipo, c.id, c.orden as orden_1, 0 as orden_2,
           c.nombre, null::text as descripcion, null::text as grupo
    from public.categorias c
    where c.restaurante_id = p_restaurante_id
      and c.archivado_at is null
      and c.nombre_en is null
    union all
    select 2, 'producto', p.id, c.orden, p.orden, p.nombre,
           case when p.descripcion_en is null then p.descripcion end, null
    from public.productos p
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where p.restaurante_id = p_restaurante_id
      and p.archivado_at is null
      and c.archivado_at is null
      and not p.es_envio
      and (p.nombre_en is null or (p.descripcion is not null and p.descripcion_en is null))
    union all
    select 3, 'grupo', g.id, g.orden, 0, g.nombre, null, null
    from public.grupos_opciones g
    where g.restaurante_id = p_restaurante_id
      and g.nombre_en is null
    union all
    select 4, 'opcion', o.id, g.orden, o.orden, o.nombre, null, g.nombre
    from public.opciones o
    join public.grupos_opciones g on g.restaurante_id = o.restaurante_id and g.id = o.grupo_id
    where o.restaurante_id = p_restaurante_id
      and o.nombre_en is null
  ),
  primeros as (
    select * from faltan
    order by tipo_orden, orden_1, orden_2, id
    limit 20
  )
  select (select count(*) from faltan)::integer,
         coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                     'tipo', f.tipo, 'id', f.id, 'nombre', f.nombre,
                     'descripcion', f.descripcion, 'grupo', f.grupo))
                     order by f.tipo_orden, f.orden_1, f.orden_2, f.id)
                   from primeros f), '[]'::jsonb)
  into v_quedan, v_pendientes;

  return jsonb_build_object(
    'puede', (v_saldo ->> 'puede')::boolean,
    'motivo', v_saldo -> 'motivo',
    'quedan', v_quedan,
    'pendientes', case when (v_saldo ->> 'puede')::boolean then v_pendientes else '[]'::jsonb end);
end;
$$;

revoke execute on function public.pendientes_de_traducir(uuid) from public, anon, service_role;
grant execute on function public.pendientes_de_traducir(uuid) to authenticated;


-- ─── Lo que tradujo la IA (solo el Worker) ────────────────────────────────────

-- La lista que manda el Worker, ya limpia: un id que no es número queda vacío, y un inglés en blanco o
-- demasiado largo (más de 200 letras el nombre, más de 1,000 la descripción) también, así no se escribe.
create function privado.traducciones_que_llegan(p_traducciones jsonb)
returns table (tipo text, id bigint, nombre text, descripcion text, nombre_en text, descripcion_en text)
language sql
immutable
set search_path = ''
as $$
  select t ->> 'tipo',
         case when (t ->> 'id') ~ '^[0-9]{1,18}$' then (t ->> 'id')::bigint end,
         btrim(t ->> 'nombre'),
         nullif(btrim(t ->> 'descripcion'), ''),
         case when char_length(btrim(t ->> 'nombre_en')) between 1 and 200 then btrim(t ->> 'nombre_en') end,
         case when char_length(btrim(t ->> 'descripcion_en')) between 1 and 1000 then btrim(t ->> 'descripcion_en') end
  from jsonb_array_elements(p_traducciones) as t
  where jsonb_typeof(t) = 'object';
$$;

revoke execute on function privado.traducciones_que_llegan(jsonb) from public, anon, authenticated, service_role;

-- El Worker, con la llave secreta, después de pendientes_de_traducir con la sesión del gerente y de
-- la llamada a OpenAI. p_traducciones es una lista de {tipo, id, nombre, descripcion, nombre_en,
-- descripcion_en}: nombre y descripcion son el español que se tradujo. Cada inglés se escribe solo
-- si su español sigue igual y su inglés sigue vacío, así nunca pisa lo que Don Chuy cambió o
-- escribió mientras. Lo que no viene bien (un tipo que no existe, un inglés vacío o demasiado largo,
-- algo de otro restaurante, un envío o un archivado) no se escribe y se queda pendiente. Regresa
-- cuántos renglones escribió.
create function public.guardar_traducciones(p_restaurante_id uuid, p_traducciones jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_escritas integer := 0;
  v_n integer;
begin
  if p_restaurante_id is null or p_traducciones is null or jsonb_typeof(p_traducciones) <> 'array' then
    raise exception 'Las traducciones van en una lista, con su restaurante' using errcode = '22023';
  end if;

  update public.categorias c
  set nombre_en = x.nombre_en
  from privado.traducciones_que_llegan(p_traducciones) x
  where x.tipo = 'categoria'
    and c.restaurante_id = p_restaurante_id
    and c.id = x.id
    and c.archivado_at is null
    and c.nombre = x.nombre
    and c.nombre_en is null
    and x.nombre_en is not null;
  get diagnostics v_n = row_count;
  v_escritas := v_escritas + v_n;

  update public.productos p
  set nombre_en = case when p.nombre_en is null and p.nombre = x.nombre then x.nombre_en
                       else p.nombre_en end,
      descripcion_en = case when p.descripcion_en is null and p.descripcion = x.descripcion
                            then x.descripcion_en else p.descripcion_en end
  from privado.traducciones_que_llegan(p_traducciones) x
  where x.tipo = 'producto'
    and p.restaurante_id = p_restaurante_id
    and p.id = x.id
    and p.archivado_at is null
    and not p.es_envio
    and ((p.nombre_en is null and p.nombre = x.nombre and x.nombre_en is not null)
         or (p.descripcion_en is null and p.descripcion = x.descripcion and x.descripcion_en is not null));
  get diagnostics v_n = row_count;
  v_escritas := v_escritas + v_n;

  update public.grupos_opciones g
  set nombre_en = x.nombre_en
  from privado.traducciones_que_llegan(p_traducciones) x
  where x.tipo = 'grupo'
    and g.restaurante_id = p_restaurante_id
    and g.id = x.id
    and g.nombre = x.nombre
    and g.nombre_en is null
    and x.nombre_en is not null;
  get diagnostics v_n = row_count;
  v_escritas := v_escritas + v_n;

  update public.opciones o
  set nombre_en = x.nombre_en
  from privado.traducciones_que_llegan(p_traducciones) x
  where x.tipo = 'opcion'
    and o.restaurante_id = p_restaurante_id
    and o.id = x.id
    and o.nombre = x.nombre
    and o.nombre_en is null
    and x.nombre_en is not null;
  get diagnostics v_n = row_count;
  v_escritas := v_escritas + v_n;

  return v_escritas;
end;
$$;

revoke execute on function public.guardar_traducciones(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.guardar_traducciones(uuid, jsonb) to service_role;
