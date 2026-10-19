-- El agente IA (libreta 1, Herramientas del agente IA, rev 54; libreta 3, «El gasto de IA», rev 18;
-- libreta 2, Diccionario de datos, rev 91; maqueta Agente IA KznKZdgQbLTZGs1EwVMvga).
--
-- El modelo no recibe ventas: recibe 6 herramientas, y cada una es una función de Postgres que
-- regresa los números ya hechos, con el dinero ya escrito. Todas suman con una sola pieza,
-- privado.ventas_agrupadas, sobre privado.cuentas_del_dia: un día del agente es un día de Cortes y
-- reportes. La sexta herramienta usa las mismas partes que reporte_del_dia, que ahora las llama
-- con un solo día. Las cuatro cifras de Inicio (cifras_de_inicio) salen de las mismas piezas, y
-- contexto_agente arma lo que el Worker pone en el prompt.
--
-- El gasto: el Worker anota los tokens de cada pregunta y de cada saludo (anotar_uso_ia, solo con
-- la llave secreta), y Postgres saca su costo con precios_ia. El agente gasta el tope completo
-- mientras no existan los flyers ni el mini agente del menú (decidido el 19 de octubre de 2026).
-- Fragmentless pone el tope de cada restaurante (fijar_tope_ia), de 0 a 10 dólares.
--
-- Una sola forma de contar: solo las cuentas cerradas son venta, lo cancelado no suma, una
-- reabierta no cuenta hasta que se vuelve a cerrar, y cada cuenta es del día de negocio en que se
-- abrió. La IA nunca suma: todo número sale de aquí.


-- ─── restaurantes: el máximo de IA ────────────────────────────────────────────
-- El tope va de 0 a 10 dólares al mes, el máximo de Fragmentless (decidido el 19 de octubre de
-- 2026). Nace en 0: sin tope no hay IA.

alter table public.restaurantes
  add constraint restaurantes_tope_ia_maximo check (tope_ia_usd_mes <= 10);


-- ─── precios_ia ───────────────────────────────────────────────────────────────
-- Lo que cobra OpenAI por millón de tokens de cada modelo, en su modo normal y con llamadas de
-- hasta 272 mil tokens de entrada (consultado el 19 de octubre de 2026 en su página de precios).
-- Desde GPT-5.6 también cobra lo que guarda en caché, a 1.25 veces la entrada. Se cambia con una
-- migración cuando OpenAI cambie sus precios; nadie con sesión la lee ni la escribe.

create table public.precios_ia (
  modelo text primary key check (btrim(modelo) <> ''),
  entrada_usd_millon numeric(10,4) not null constraint precios_ia_entrada_valida check (entrada_usd_millon >= 0),
  entrada_cache_usd_millon numeric(10,4) not null
    constraint precios_ia_entrada_cache_valida check (entrada_cache_usd_millon >= 0),
  escritura_cache_usd_millon numeric(10,4) not null
    constraint precios_ia_escritura_cache_valida check (escritura_cache_usd_millon >= 0),
  salida_usd_millon numeric(10,4) not null constraint precios_ia_salida_valida check (salida_usd_millon >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger precios_ia_updated_at
before update on public.precios_ia
for each row execute function privado.set_updated_at();

insert into public.precios_ia (modelo, entrada_usd_millon, entrada_cache_usd_millon, escritura_cache_usd_millon, salida_usd_millon) values
  ('gpt-6.1-sol', 2.00, 0.10, 2.50, 10.00),
  ('gpt-5.6-luna', 0.20, 0.02, 0.25, 1.20);


-- ─── uso_ia ───────────────────────────────────────────────────────────────────
-- Cuánto gasta en IA cada restaurante por mes, por sobres. El mes es el del calendario en la zona
-- del restaurante: el aviso dice «Vuelve el 1 de noviembre». Solo la escribe anotar_uso_ia; nadie
-- con sesión la lee directo.

create table public.uso_ia (
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  mes date not null constraint uso_ia_mes_valido check (mes = date_trunc('month', mes)::date),
  consultas_agente integer not null default 0 constraint uso_ia_consultas_validas check (consultas_agente >= 0),
  saludos integer not null default 0 constraint uso_ia_saludos_validos check (saludos >= 0),
  costo_agente_usd numeric(10,4) not null default 0 constraint uso_ia_costo_agente_valido check (costo_agente_usd >= 0),
  anuncios integer not null default 0 constraint uso_ia_anuncios_validos check (anuncios >= 0),
  costo_anuncios_usd numeric(10,4) not null default 0
    constraint uso_ia_costo_anuncios_valido check (costo_anuncios_usd >= 0),
  costo_usd numeric(10,4) generated always as (costo_agente_usd + costo_anuncios_usd) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (restaurante_id, mes)
);

create trigger uso_ia_updated_at
before update on public.uso_ia
for each row execute function privado.set_updated_at();

alter table public.precios_ia enable row level security;
alter table public.uso_ia enable row level security;

revoke all on table public.precios_ia, public.uso_ia from anon, authenticated, service_role;


-- ─── El costo y el saldo ──────────────────────────────────────────────────────
-- El costo de una llamada con los tokens que reporta OpenAI. Los de entrada traen dentro los que
-- leyó de caché y los que guardó en caché; cada parte va a su precio. Se redondea a 4 decimales.

create function privado.costo_ia(
  p_modelo text,
  p_entrada bigint,
  p_entrada_cache bigint,
  p_escritura_cache bigint,
  p_salida bigint
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round((
      (p_entrada - p_entrada_cache - p_escritura_cache) * p.entrada_usd_millon
      + p_entrada_cache * p.entrada_cache_usd_millon
      + p_escritura_cache * p.escritura_cache_usd_millon
      + p_salida * p.salida_usd_millon
    ) / 1000000, 4)::numeric(10,4)
  from public.precios_ia p
  where p.modelo = p_modelo;
$$;

-- El mes de IA de un restaurante: el día 1 del mes de hoy, en su zona.
create function privado.mes_ia(p_zona text)
returns date
language sql
stable
set search_path = ''
as $$
  select date_trunc('month', privado.dia_local(p_zona))::date;
$$;

-- El sobre del agente: si todavía puede gastar este mes. El tope completo es suyo mientras no
-- existan los flyers ni el mini agente del menú. Con tope 0 no hay IA.
create function privado.saldo_agente(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'tope', r.tope_ia_usd_mes,
    'gastado', coalesce(u.costo_agente_usd, 0)::numeric(10,4),
    'puede', r.tope_ia_usd_mes > 0 and coalesce(u.costo_agente_usd, 0) < r.tope_ia_usd_mes,
    'motivo', case when r.tope_ia_usd_mes = 0 then 'sin_ia'
                   when coalesce(u.costo_agente_usd, 0) >= r.tope_ia_usd_mes then 'limite' end,
    'con_distribuidor', r.distribuidor_id is not null,
    'vuelve', (privado.mes_ia(r.zona_horaria) + interval '1 month')::date
  )
  from public.restaurantes r
  left join public.uso_ia u on u.restaurante_id = r.id and u.mes = privado.mes_ia(r.zona_horaria)
  where r.id = p_restaurante_id;
$$;

revoke execute on function
  privado.costo_ia(text, bigint, bigint, bigint, bigint),
  privado.mes_ia(text),
  privado.saldo_agente(uuid)
from public, anon, authenticated, service_role;


-- ─── estado_ia: si el gerente puede preguntar ─────────────────────────────────
-- Lo pide la app al abrir el agente, para mostrar el aviso en la caja, y el Worker antes de cada
-- pregunta y cada saludo, con la sesión del gerente. No dice cuánto se gastó: solo si puede, y si
-- no, por qué (sin_ia o limite), si el restaurante tiene distribuidor y cuándo vuelve.

create function public.estado_ia(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_saldo jsonb;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante le preguntan al agente' using errcode = '42501';
  end if;
  v_saldo := privado.saldo_agente(p_restaurante_id);
  if (v_saldo ->> 'puede')::boolean then
    return jsonb_build_object('puede', true);
  end if;
  return jsonb_build_object(
    'puede', false,
    'motivo', v_saldo -> 'motivo',
    'con_distribuidor', v_saldo -> 'con_distribuidor',
    'vuelve', v_saldo -> 'vuelve'
  );
end;
$$;


-- ─── anotar_uso_ia: el gasto, solo el Worker ──────────────────────────────────
-- Una pregunta (con los tokens de todas sus rondas) o un saludo. El Worker manda los tokens que
-- reportó OpenAI; Postgres saca el costo y lo suma al sobre del agente del mes. Regresa el costo
-- y si el agente todavía puede gastar.

create function public.anotar_uso_ia(
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
begin
  if p_uso is null or p_uso not in ('pregunta', 'saludo') then
    raise exception 'El uso de IA es pregunta o saludo' using errcode = '22023';
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

  insert into public.uso_ia as u (restaurante_id, mes, consultas_agente, saludos, costo_agente_usd)
  values (p_restaurante_id, privado.mes_ia(v_zona),
          case when p_uso = 'pregunta' then 1 else 0 end,
          case when p_uso = 'saludo' then 1 else 0 end,
          v_costo)
  on conflict (restaurante_id, mes) do update
  set consultas_agente = u.consultas_agente + excluded.consultas_agente,
      saludos = u.saludos + excluded.saludos,
      costo_agente_usd = u.costo_agente_usd + excluded.costo_agente_usd;

  return jsonb_build_object('costo', v_costo, 'puede', privado.saldo_agente(p_restaurante_id) -> 'puede');
end;
$$;


-- ─── El tope, desde el panel de Fragmentless ──────────────────────────────────
-- Mientras el panel del distribuidor no tenga los cobros, Fragmentless pone el tope de cada
-- cliente en la ventana «Tope de IA», con lo gastado este mes (decidido el 19 de octubre de 2026).

create function public.fijar_tope_ia(p_restaurante_id uuid, p_tope numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if p_tope is null or p_tope < 0 or p_tope > 10 then
    raise exception 'El tope de IA va de 0 a 10 dólares' using errcode = '22023';
  end if;
  if p_tope <> round(p_tope, 2) then
    raise exception 'El tope de IA lleva hasta centavos' using errcode = '22023';
  end if;

  update public.restaurantes set tope_ia_usd_mes = p_tope where id = p_restaurante_id;
  if not found then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;
end;
$$;

-- Lo de la ventana «Tope de IA»: el mes, lo gastado en cada sobre, el tope y quién paga.
create function public.uso_ia_cliente(p_restaurante_id uuid)
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
    'gastado_agente', coalesce(u.costo_agente_usd, 0)::numeric(10,4),
    'consultas_agente', coalesce(u.consultas_agente, 0),
    'saludos', coalesce(u.saludos, 0),
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


-- ─── El dinero y las fechas en palabras ───────────────────────────────────────
-- Las herramientas mandan el dinero ya escrito, como en la maqueta ($4,270; $22.50; −$60), para
-- que el modelo lo copie y nunca lo reescriba, y las fechas como las dice la gente.

create function privado.dinero(p_monto numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when round(p_monto, 2) < 0 then '−' else '' end || '$'
         || to_char(abs(round(p_monto, 2)),
                    case when abs(round(p_monto, 2)) = trunc(abs(round(p_monto, 2)))
                         then 'FM999,999,999,990' else 'FM999,999,999,990.00' end);
$$;

create function privado.nombre_dia(p_dia date)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'])
         [extract(isodow from p_dia)::integer];
$$;

create function privado.nombre_mes(p_dia date)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
                'septiembre', 'octubre', 'noviembre', 'diciembre'])[extract(month from p_dia)::integer];
$$;

-- «17 de octubre», con el año solo si no es el de hoy.
create function privado.dia_y_mes(p_dia date, p_hoy date)
returns text
language sql
immutable
set search_path = ''
as $$
  select extract(day from p_dia)::integer || ' de ' || privado.nombre_mes(p_dia)
         || case when extract(year from p_dia) <> extract(year from p_hoy)
                 then ' de ' || extract(year from p_dia)::integer else '' end;
$$;

-- «sábado 17 de octubre».
create function privado.fecha_en_palabras(p_dia date, p_hoy date)
returns text
language sql
immutable
set search_path = ''
as $$
  select privado.nombre_dia(p_dia) || ' ' || privado.dia_y_mes(p_dia, p_hoy);
$$;

-- Un rango de días de negocio como lo dice la gente: «hoy», «ayer», «esta semana», «la semana
-- pasada», «este mes», «septiembre», «este año», «el sábado 17 de octubre», «del 12 al 15 de
-- octubre». p_forma: 'solo'; 'de' («de hoy», «del sábado 17…», «de septiembre»); 'en' («en
-- septiembre», «hoy»). Lo usan los renglones de «Lo que leí para responder».
create function privado.periodo(p_desde date, p_hasta date, p_hoy date, p_forma text default 'solo')
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_lunes date := p_hoy - (extract(isodow from p_hoy)::integer - 1);
  v_mes date := date_trunc('month', p_hoy)::date;
  v_fin_mes date := (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date;
  v_texto text;
  v_tipo text := 'fijo';
begin
  if p_desde = p_hasta and p_desde = p_hoy then
    v_texto := 'hoy';
  elsif p_desde = p_hasta and p_desde = p_hoy - 1 then
    v_texto := 'ayer';
  elsif p_desde = p_hasta then
    v_texto := 'el ' || privado.fecha_en_palabras(p_desde, p_hoy);
    v_tipo := 'dia';
  elsif p_desde = v_lunes and p_hasta between p_hoy and v_lunes + 6 then
    v_texto := 'esta semana';
  elsif p_desde = v_lunes - 7 and p_hasta = v_lunes - 1 then
    v_texto := 'la semana pasada';
  elsif p_desde = v_mes and p_hasta between p_hoy and (v_mes + interval '1 month' - interval '1 day')::date then
    v_texto := 'este mes';
  elsif p_desde = date_trunc('month', p_desde)::date and p_hasta = v_fin_mes then
    v_texto := privado.nombre_mes(p_desde)
               || case when extract(year from p_desde) <> extract(year from p_hoy)
                       then ' de ' || extract(year from p_desde)::integer else '' end;
    v_tipo := 'mes';
  elsif p_desde = date_trunc('year', p_desde)::date
        and (p_hasta = (date_trunc('year', p_desde) + interval '1 year' - interval '1 day')::date
             or (extract(year from p_desde) = extract(year from p_hoy) and p_hasta >= p_hoy
                 and extract(year from p_hasta) = extract(year from p_hoy))) then
    if extract(year from p_desde) = extract(year from p_hoy) then
      v_texto := 'este año';
    else
      v_texto := extract(year from p_desde)::integer::text;
      v_tipo := 'año';
    end if;
  elsif date_trunc('month', p_desde) = date_trunc('month', p_hasta) then
    v_texto := 'del ' || extract(day from p_desde)::integer || ' al ' || privado.dia_y_mes(p_hasta, p_hoy);
    v_tipo := 'rango';
  elsif extract(year from p_desde) = extract(year from p_hasta) then
    v_texto := 'del ' || extract(day from p_desde)::integer || ' de ' || privado.nombre_mes(p_desde)
               || ' al ' || privado.dia_y_mes(p_hasta, p_hoy);
    v_tipo := 'rango';
  else
    v_texto := 'del ' || privado.dia_y_mes(p_desde, '0001-01-01') || ' al ' || privado.dia_y_mes(p_hasta, '0001-01-01');
    v_tipo := 'rango';
  end if;

  return case p_forma
    when 'de' then case v_tipo when 'dia' then 'del ' || substr(v_texto, 4)
                               when 'rango' then v_texto
                               else 'de ' || v_texto end
    when 'en' then case when v_tipo in ('mes', 'año') then 'en ' || v_texto else v_texto end
    else v_texto
  end;
end;
$$;

-- La primera letra en mayúscula, para «Ayer contra hoy».
create function privado.con_mayuscula(p_texto text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(left(p_texto, 1)) || substr(p_texto, 2);
$$;


-- ─── La pieza base: ventas_agrupadas ──────────────────────────────────────────
-- Todas las sumas del agente y de Inicio. Las cuentas cerradas que se abrieron del día de negocio
-- p_desde al p_hasta (privado.cuentas_del_dia), agrupadas por p_agrupar_por, un renglón por grupo:
--   por cuenta (total, dia, semana, mes, dia_semana, hora, mesa, mesero): el dinero es la suma de
--     ventas.total, que ya resta el descuento a toda la cuenta;
--   por renglón (producto, categoria, o cualquiera con filtro de producto o de categoría): la suma
--     de los renglones activos, que ya restan su descuento. Sin filtro, el descuento a toda la
--     cuenta va en su propio renglón, «Descuento a la cuenta», y con él el total cuadra.
-- El producto, la categoría, la mesa y el mesero salen con su nombre de hoy. La hora es la de
-- apertura, en la zona del restaurante. Un rango sin ventas regresa 0 renglones. Solo la llaman
-- las funciones del agente y de Inicio, que antes revisan quién pregunta.

create function privado.ventas_agrupadas(
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
               when 'mesa' then case f.tipo when 'mesa' then me.nombre when 'para_llevar' then 'Para llevar'
                                             else 'A domicilio' end
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

-- El primer día de negocio con una cuenta cerrada: antes no había ventas que contar.
create function privado.primer_dia_con_ventas(p_restaurante_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select privado.dia_de_negocio(r.zona_horaria, r.hora_corte, min(v.created_at))
  from public.restaurantes r
  join public.ventas v on v.restaurante_id = r.id and v.estado = 'cerrada'
  where r.id = p_restaurante_id
  group by r.zona_horaria, r.hora_corte;
$$;


-- ─── Los argumentos del modelo ────────────────────────────────────────────────
-- El modelo manda los argumentos de cada herramienta en JSON. Se revisan aquí, y si algo viene
-- mal, el error dice en palabras qué corregir: el Worker se lo regresa al modelo, que corrige.

create function privado.revisar_argumentos(p_herramienta text, p_args jsonb, p_lleva text[])
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_sobra text;
begin
  select k into v_sobra from jsonb_object_keys(p_args) as k where k <> all (p_lleva) order by k limit 1;
  if v_sobra is null then
    return;
  end if;
  if cardinality(p_lleva) = 0 then
    raise exception '% no lleva argumentos.', p_herramienta using errcode = '22023';
  end if;
  raise exception '% no lleva «%». Lleva: %.', p_herramienta, v_sobra, array_to_string(p_lleva, ', ')
    using errcode = '22023';
end;
$$;

create function privado.arg_fecha(p_args jsonb, p_nombre text, p_obligatoria boolean default true)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_texto text;
  v_fecha date;
begin
  if coalesce(p_args -> p_nombre, 'null') = 'null' then
    if p_obligatoria then
      raise exception 'Falta %: un día de negocio en AAAA-MM-DD.', p_nombre using errcode = '22023';
    end if;
    return null;
  end if;
  v_texto := p_args ->> p_nombre;
  if jsonb_typeof(p_args -> p_nombre) <> 'string' or v_texto !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'La fecha % no existe. Usa AAAA-MM-DD.', v_texto using errcode = '22023';
  end if;
  begin
    v_fecha := v_texto::date;
  exception when others then
    raise exception 'La fecha % no existe. Usa AAAA-MM-DD.', v_texto using errcode = '22023';
  end;
  if v_fecha < date '2000-01-01' or v_fecha > date '2100-12-31' then
    raise exception 'La fecha % está fuera de lo que se puede consultar (del año 2000 al 2100).', v_texto
      using errcode = '22023';
  end if;
  return v_fecha;
end;
$$;

-- Una de las opciones de la lista; sin valor, la de por defecto (y si no hay, falta).
create function privado.arg_opcion(p_args jsonb, p_nombre text, p_opciones text[], p_defecto text default null)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_texto text;
begin
  if coalesce(p_args -> p_nombre, 'null') = 'null' then
    if p_defecto is null then
      raise exception 'Falta %. Opciones: %.', p_nombre, array_to_string(p_opciones, ', ') using errcode = '22023';
    end if;
    return p_defecto;
  end if;
  v_texto := p_args ->> p_nombre;
  if jsonb_typeof(p_args -> p_nombre) <> 'string' or not (v_texto = any (p_opciones)) then
    raise exception '«%» no es una opción de %. Opciones: %.', v_texto, p_nombre, array_to_string(p_opciones, ', ')
      using errcode = '22023';
  end if;
  return v_texto;
end;
$$;

create function privado.arg_entero(p_args jsonb, p_nombre text, p_minimo integer, p_maximo integer,
                                   p_defecto integer default null, p_ayuda text default null)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_numero numeric;
begin
  if coalesce(p_args -> p_nombre, 'null') = 'null' then
    return p_defecto;
  end if;
  if jsonb_typeof(p_args -> p_nombre) <> 'number' then
    raise exception '% va con un número entero.', p_nombre using errcode = '22023';
  end if;
  v_numero := (p_args ->> p_nombre)::numeric;
  if v_numero <> trunc(v_numero) or v_numero < p_minimo or v_numero > p_maximo then
    raise exception '% va de % a %.%', p_nombre, p_minimo, p_maximo, coalesce(' ' || p_ayuda, '')
      using errcode = '22023';
  end if;
  return v_numero::integer;
end;
$$;

create function privado.arg_texto(p_args jsonb, p_nombre text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if coalesce(p_args -> p_nombre, 'null') = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_args -> p_nombre) <> 'string' then
    raise exception '% va en texto.', p_nombre using errcode = '22023';
  end if;
  return nullif(btrim(p_args ->> p_nombre), '');
end;
$$;

create function privado.revisar_rango(p_n1 text, p_desde date, p_n2 text, p_hasta date)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_desde > p_hasta then
    raise exception '% (%) va después de % (%).', p_n1, p_desde, p_n2, p_hasta using errcode = '22023';
  end if;
end;
$$;

-- Una mesa por su nombre, o «Para llevar» o «A domicilio». Si no está, el error trae las que hay.
create function privado.buscar_mesa(p_restaurante_id uuid, p_nombre text, out mesa_id bigint, out tipo text,
                                    out nombre text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
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
                'Para llevar', 'A domicilio')
      using errcode = '22023';
  end if;
  tipo := 'mesa';
end;
$$;

create function privado.buscar_categoria(p_restaurante_id uuid, p_nombre text, out categoria_id bigint,
                                         out nombre text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  select c.id, c.nombre into categoria_id, nombre
  from public.categorias c
  where c.restaurante_id = p_restaurante_id and lower(btrim(c.nombre)) = lower(p_nombre)
  order by c.archivado_at nulls first, c.id desc
  limit 1;
  if categoria_id is null then
    raise exception 'No hay una categoría «%». Las que hay: %.', p_nombre,
      coalesce((select string_agg(c.nombre, ', ' order by c.orden, c.id) from public.categorias c
                where c.restaurante_id = p_restaurante_id and c.archivado_at is null), 'ninguna')
      using errcode = '22023';
  end if;
end;
$$;

create function privado.buscar_persona(p_restaurante_id uuid, p_nombre text, out miembro_id bigint,
                                       out nombre text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  select m.id, m.nombre into miembro_id, nombre
  from public.miembros m
  where m.restaurante_id = p_restaurante_id and lower(btrim(m.nombre)) = lower(p_nombre)
  order by m.activo desc, m.id desc
  limit 1;
  if miembro_id is null then
    raise exception 'No hay nadie llamado «%» en el equipo. Están: %.', p_nombre,
      (select string_agg(m.nombre, ', ' order by m.nombre) from public.miembros m
       where m.restaurante_id = p_restaurante_id and m.activo)
      using errcode = '22023';
  end if;
end;
$$;

create function privado.buscar_producto(p_restaurante_id uuid, p_producto_id integer)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_nombre text;
begin
  select p.nombre into v_nombre from public.productos p
  where p.restaurante_id = p_restaurante_id and p.id = p_producto_id;
  if v_nombre is null then
    raise exception 'No hay producto #% en el menú.', p_producto_id using errcode = '22023';
  end if;
  return v_nombre;
end;
$$;

-- El día de negocio de hoy de un restaurante.
create function privado.hoy_de(p_restaurante_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select privado.dia_de_negocio(zona_horaria, hora_corte) from public.restaurantes where id = p_restaurante_id;
$$;

-- Un renglón de «Lo que leí para responder».
create function privado.leido(p_icono text, p_texto text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('icono', p_icono, 'texto', p_texto);
$$;

-- «los viernes», «los sábados».
create function privado.los_dias(p_dia_semana integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'los ' || (array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'])[p_dia_semana];
$$;

-- El dinero con su signo, para las diferencias: «+$500», «−$300», «$0».
create function privado.dinero_con_signo(p_monto numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when round(p_monto, 2) > 0 then '+' else '' end || privado.dinero(p_monto);
$$;


-- ─── Herramienta 1 · resumen(desde, hasta) ────────────────────────────────────
-- ¿Cuánto vendí? Una sola suma del rango. Los promedios se dividen entre las cuentas y entre los
-- días que abrió, y se redondean al centavo al final.

create function privado.herramienta_resumen(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_desde date;
  v_hasta date;
  v_hoy date := privado.hoy_de(p_restaurante_id);
  v record;
  v_base jsonb;
begin
  perform privado.revisar_argumentos('resumen', p_args, array['desde', 'hasta']);
  v_desde := privado.arg_fecha(p_args, 'desde');
  v_hasta := privado.arg_fecha(p_args, 'hasta');
  perform privado.revisar_rango('desde', v_desde, 'hasta', v_hasta);

  v_base := jsonb_build_object(
    'desde', v_desde, 'hasta', v_hasta,
    'incluye_hoy_parcial', v_hoy between v_desde and v_hasta,
    'leido', privado.leido('datos', 'Lo vendido ' || privado.periodo(v_desde, v_hasta, v_hoy, 'en')));

  select * into v from privado.ventas_agrupadas(p_restaurante_id, v_desde, v_hasta, 'total');
  if not found then
    return v_base || jsonb_build_object('sin_ventas', true);
  end if;

  return v_base || jsonb_build_object(
    'cuentas', v.cuentas,
    'unidades', v.unidades,
    'total', privado.dinero(v.importe),
    'ticket_promedio', privado.dinero(v.importe / v.cuentas),
    'dias_abiertos', v.dias,
    'promedio_por_dia_abierto', privado.dinero(v.importe / v.dias));
end;
$$;


-- ─── Herramienta 2 · ranking(...) ─────────────────────────────────────────────
-- Ordena productos, categorías, mesas, meseros, horas o fechas por importe, piezas o cuentas, con
-- su participación y con los grupos en 0 (ese es el «menos vendido» real). La hora y el día de la
-- semana van en promedio, dentro del rango efectivo: de max(desde, el primer día con ventas) a
-- min(hasta, hoy). El día de la semana se divide entre las veces que cayó en ese rango; la hora,
-- entre los días que abrió. Después del límite va el resto, y siempre el total del periodo. El
-- descuento a toda la cuenta va aparte, junto al total, sin entrar al orden ni al límite.

create function privado.herramienta_ranking(p_restaurante_id uuid, p_args jsonb)
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
    || coalesce(case v_tipo when 'mesa' then ', en ' || v_mesa_nombre when 'para_llevar' then ', para llevar'
                  when 'domicilio' then ', a domicilio' end, '')
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


-- ─── Herramienta 3 · comparar(...) ────────────────────────────────────────────
-- Dos periodos lado a lado, A (el de antes) y B (el de ahora), en total o por grupo, con el
-- promedio por día abierto de cada uno para que la comparación sea justa. Por grupo, lo que más
-- se movió primero, hasta 20, y el resto.

create function privado.cambio(p_a numeric, p_b numeric)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_a > 0 and p_b > 0 then to_jsonb(round((p_b - p_a) * 100 / p_a, 1))
              when p_a = 0 and p_b > 0 then to_jsonb('nuevo'::text)
              when p_a > 0 and p_b = 0 then to_jsonb('dejó de venderse (−100 %)'::text)
              else to_jsonb('sin ventas en ninguno'::text) end;
$$;

create function privado.herramienta_comparar(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_a_desde date;
  v_a_hasta date;
  v_b_desde date;
  v_b_hasta date;
  v_agrupar text;
  v_medir text;
  v_hoy date := privado.hoy_de(p_restaurante_id);
  v_ta record;
  v_tb record;
  v_a numeric;
  v_b numeric;
  v_pa numeric;
  v_pb numeric;
  v_grupos jsonb := '{}';
begin
  perform privado.revisar_argumentos('comparar', p_args,
    array['a_desde', 'a_hasta', 'b_desde', 'b_hasta', 'agrupar_por', 'medir_por']);
  v_a_desde := privado.arg_fecha(p_args, 'a_desde');
  v_a_hasta := privado.arg_fecha(p_args, 'a_hasta');
  v_b_desde := privado.arg_fecha(p_args, 'b_desde');
  v_b_hasta := privado.arg_fecha(p_args, 'b_hasta');
  perform privado.revisar_rango('a_desde', v_a_desde, 'a_hasta', v_a_hasta);
  perform privado.revisar_rango('b_desde', v_b_desde, 'b_hasta', v_b_hasta);
  v_agrupar := privado.arg_opcion(p_args, 'agrupar_por',
    array['total', 'producto', 'categoria', 'mesa', 'mesero', 'dia_semana', 'hora'], 'total');
  v_medir := privado.arg_opcion(p_args, 'medir_por', array['importe', 'unidades', 'cuentas'], 'importe');

  select coalesce(max(x.cuentas), 0) as cuentas, coalesce(max(x.unidades), 0) as unidades,
         coalesce(max(x.importe), 0) as importe, coalesce(max(x.dias), 0) as dias
  into v_ta from privado.ventas_agrupadas(p_restaurante_id, v_a_desde, v_a_hasta, 'total') x;
  select coalesce(max(x.cuentas), 0) as cuentas, coalesce(max(x.unidades), 0) as unidades,
         coalesce(max(x.importe), 0) as importe, coalesce(max(x.dias), 0) as dias
  into v_tb from privado.ventas_agrupadas(p_restaurante_id, v_b_desde, v_b_hasta, 'total') x;

  v_a := case v_medir when 'importe' then v_ta.importe when 'unidades' then v_ta.unidades else v_ta.cuentas end;
  v_b := case v_medir when 'importe' then v_tb.importe when 'unidades' then v_tb.unidades else v_tb.cuentas end;
  v_pa := case when v_ta.dias > 0 then round(v_ta.importe / v_ta.dias, 2) end;
  v_pb := case when v_tb.dias > 0 then round(v_tb.importe / v_tb.dias, 2) end;

  if v_agrupar <> 'total' then
    with a as (
      select * from privado.ventas_agrupadas(p_restaurante_id, v_a_desde, v_a_hasta, v_agrupar)
    ),
    b as (
      select * from privado.ventas_agrupadas(p_restaurante_id, v_b_desde, v_b_hasta, v_agrupar)
    ),
    j as (
      select coalesce(b.clave, a.clave) as clave, coalesce(b.etiqueta, a.etiqueta) as etiqueta,
             coalesce(case v_medir when 'importe' then a.importe when 'unidades' then a.unidades else a.cuentas end, 0)::numeric as va,
             coalesce(case v_medir when 'importe' then b.importe when 'unidades' then b.unidades else b.cuentas end, 0)::numeric as vb
      from a
      full join b on b.clave = a.clave
    ),
    o as (
      select j.*, row_number() over (order by abs(j.vb - j.va) desc, j.etiqueta, j.clave) as lugar,
             count(*) over () as grupos
      from j
      where j.clave <> 'descuento_cuenta' and (j.va <> 0 or j.vb <> 0)
    )
    select jsonb_build_object(
      'grupos', coalesce(jsonb_agg(jsonb_build_object(
                  'nombre', o.etiqueta,
                  'a', case when v_medir = 'importe' then to_jsonb(privado.dinero(o.va)) else to_jsonb(o.va) end,
                  'b', case when v_medir = 'importe' then to_jsonb(privado.dinero(o.vb)) else to_jsonb(o.vb) end,
                  'diferencia', case when v_medir = 'importe' then to_jsonb(privado.dinero_con_signo(o.vb - o.va))
                                     else to_jsonb(o.vb - o.va) end,
                  'cambio_pct', privado.cambio(o.va, o.vb))
                  order by o.lugar) filter (where o.lugar <= 20), '[]'),
      'resto', case when max(o.grupos) > 20 then jsonb_build_object(
                 'grupos', max(o.grupos) - 20,
                 'a', case when v_medir = 'importe' then to_jsonb(privado.dinero(coalesce(sum(o.va) filter (where o.lugar > 20), 0)))
                           else to_jsonb(coalesce(sum(o.va) filter (where o.lugar > 20), 0)) end,
                 'b', case when v_medir = 'importe' then to_jsonb(privado.dinero(coalesce(sum(o.vb) filter (where o.lugar > 20), 0)))
                           else to_jsonb(coalesce(sum(o.vb) filter (where o.lugar > 20), 0)) end) end)
    || coalesce((select case when v_medir = 'importe' then jsonb_build_object('descuento_a_la_cuenta', jsonb_build_object(
                   'a', privado.dinero(j2.va), 'b', privado.dinero(j2.vb),
                   'diferencia', privado.dinero_con_signo(j2.vb - j2.va))) end
                 from j j2 where j2.clave = 'descuento_cuenta'), '{}')
    into v_grupos
    from o;
  end if;

  return jsonb_build_object(
    'agrupar_por', v_agrupar, 'medir_por', v_medir,
    'a', jsonb_build_object('desde', v_a_desde, 'hasta', v_a_hasta, 'cuentas', v_ta.cuentas, 'unidades', v_ta.unidades,
                            'importe', privado.dinero(v_ta.importe), 'dias_abiertos', v_ta.dias,
                            'promedio_por_dia_abierto', case when v_pa is not null then privado.dinero(v_pa) end),
    'b', jsonb_build_object('desde', v_b_desde, 'hasta', v_b_hasta, 'cuentas', v_tb.cuentas, 'unidades', v_tb.unidades,
                            'importe', privado.dinero(v_tb.importe), 'dias_abiertos', v_tb.dias,
                            'promedio_por_dia_abierto', case when v_pb is not null then privado.dinero(v_pb) end),
    'diferencia', case when v_medir = 'importe' then to_jsonb(privado.dinero_con_signo(v_b - v_a)) else to_jsonb(v_b - v_a) end,
    'cambio_pct', privado.cambio(v_a, v_b),
    'cambio_promedio_diario_pct', case when v_pa is not null and v_pb is not null then privado.cambio(v_pa, v_pb) end,
    'periodo_b_incompleto', v_hoy between v_b_desde and v_b_hasta,
    'leido', privado.leido('datos',
      privado.con_mayuscula(privado.periodo(v_a_desde, v_a_hasta, v_hoy)) || ' contra '
      || regexp_replace(privado.periodo(v_b_desde, v_b_hasta, v_hoy), '^del ', 'lo del ')
      || case v_agrupar when 'total' then '' when 'producto' then ', por producto' when 'categoria' then ', por categoría'
           when 'mesa' then ', por mesa' when 'mesero' then ', por mesero' when 'hora' then ', por hora'
           else ', por día de la semana' end)
  ) || v_grupos;
end;
$$;


-- ─── Herramienta 4 · detalle(...) ─────────────────────────────────────────────
-- Lee cuentas una por una y no suma nada: «¿qué se pidió en el folio 37?», «las cuentas de la
-- Mesa 3 de ayer». Las más recientes primero. Nunca manda el teléfono ni la dirección de un pedido
-- a domicilio. Al final, cuántas encontró y cuántas más hay.

create function privado.herramienta_detalle(p_restaurante_id uuid, p_args jsonb)
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
    || coalesce(case v_tipo when 'mesa' then ', en ' || v_mesa_nombre when 'para_llevar' then ', para llevar'
                  when 'domicilio' then ', a domicilio' end, '')
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
       'cuenta', case when o.tipo = 'mesa' then coalesce(me.nombre, o.mesa_nombre) else o.cliente_nombre end,
       'tipo', case o.tipo when 'mesa' then 'mesa' when 'para_llevar' then 'para llevar' else 'a domicilio' end,
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


-- ─── Herramienta 5 · proyeccion_mes() ─────────────────────────────────────────
-- Cómo cierra el mes del día de negocio de hoy: cada día que falta vale el promedio de ese mismo
-- día de la semana en las últimas k semanas (k = las semanas completas de historia, hasta 4; un
-- día sin ventas cuenta 0). Hoy vale lo más alto entre lo ya vendido hoy y su promedio. Cada
-- promedio se redondea al centavo antes de sumar, para que el desglose cuadre con el total. Con
-- menos de una semana de historia no hay número. Regresa números: la herramienta y Inicio los
-- escriben a su modo. p_hoy existe para que las pruebas fijen el día.

create function privado.proyeccion_del_mes(p_restaurante_id uuid, p_hoy date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoy date := coalesce(p_hoy, privado.hoy_de(p_restaurante_id));
  v_d1 date := date_trunc('month', v_hoy)::date;
  v_fin date := (date_trunc('month', v_hoy) + interval '1 month' - interval '1 day')::date;
  v_primer date := privado.primer_dia_con_ventas(p_restaurante_id);
  v_k integer;
  v_ya numeric;
  v_hoy_vendido numeric;
  v_promedios numeric[];
  v_hoy_cuenta numeric;
  v_restante numeric;
begin
  v_ya := coalesce((select x.importe from privado.ventas_agrupadas(p_restaurante_id, v_d1, v_hoy, 'total') x), 0);
  v_hoy_vendido := coalesce((select x.importe from privado.ventas_agrupadas(p_restaurante_id, v_hoy, v_hoy, 'total') x), 0);
  v_k := least(4, coalesce((v_hoy - v_primer) / 7, 0));
  if v_k < 1 then
    return jsonb_build_object('mes', v_d1, 'hoy', v_hoy, 'ya_vendido', v_ya, 'sin_historia_suficiente', true);
  end if;

  -- El promedio de cada día de la semana (1 = lunes) en las k semanas antes de hoy.
  select array_agg(round(coalesce(s.importe, 0) / v_k, 2) order by w)
  into v_promedios
  from generate_series(1, 7) as w
  left join (
    select extract(isodow from x.clave::date)::integer as dia_semana, sum(x.importe) as importe
    from privado.ventas_agrupadas(p_restaurante_id, v_hoy - 7 * v_k, v_hoy - 1, 'dia') x
    group by 1
  ) s on s.dia_semana = w;

  v_hoy_cuenta := greatest(v_hoy_vendido, v_promedios[extract(isodow from v_hoy)::integer]);
  select coalesce(sum(v_promedios[extract(isodow from d)::integer]), 0) into v_restante
  from generate_series((v_hoy + 1)::timestamp, v_fin::timestamp, interval '1 day') as d;

  return jsonb_build_object(
    'mes', v_d1, 'hoy', v_hoy,
    'ya_vendido', v_ya,
    'hoy_vendido', v_hoy_vendido,
    'hoy_promedio', v_promedios[extract(isodow from v_hoy)::integer],
    'hoy_cuenta_como', v_hoy_cuenta,
    'proyeccion', v_ya - v_hoy_vendido + v_hoy_cuenta + v_restante,
    'estimado_restante', v_hoy_cuenta - v_hoy_vendido + v_restante,
    'dias_restantes', v_fin - v_hoy,
    'semanas', v_k,
    'base_desde', v_hoy - 7 * v_k,
    'base_hasta', v_hoy - 1,
    'desglose', (select coalesce(jsonb_agg(jsonb_build_object(
                   'fecha', d::date, 'estimado', v_promedios[extract(isodow from d)::integer]) order by d), '[]')
                 from generate_series((v_hoy + 1)::timestamp, v_fin::timestamp, interval '1 day') as d));
end;
$$;

create function privado.herramienta_proyeccion_mes(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
  v_hoy date;
  v_leido jsonb;
begin
  perform privado.revisar_argumentos('proyeccion_mes', p_args, array[]::text[]);
  v := privado.proyeccion_del_mes(p_restaurante_id);
  v_hoy := (v ->> 'hoy')::date;
  v_leido := privado.leido('mes', 'Cómo va a cerrar ' || privado.nombre_mes(v_hoy));
  if v ? 'sin_historia_suficiente' then
    return jsonb_build_object('mes', privado.nombre_mes(v_hoy) || ' ' || extract(year from v_hoy)::integer,
                              'sin_historia_suficiente', true,
                              'ya_vendido', privado.dinero((v ->> 'ya_vendido')::numeric),
                              'leido', v_leido);
  end if;
  return jsonb_build_object(
    'mes', privado.nombre_mes(v_hoy) || ' ' || extract(year from v_hoy)::integer,
    'es_estimado', true,
    'ya_vendido', privado.dinero((v ->> 'ya_vendido')::numeric),
    'hoy', jsonb_build_object('vendido', privado.dinero((v ->> 'hoy_vendido')::numeric),
                              'promedio_de_su_dia', privado.dinero((v ->> 'hoy_promedio')::numeric),
                              'cuenta_como', privado.dinero((v ->> 'hoy_cuenta_como')::numeric)),
    'estimado_restante', privado.dinero((v ->> 'estimado_restante')::numeric),
    'proyeccion', privado.dinero((v ->> 'proyeccion')::numeric),
    'dias_restantes', (v ->> 'dias_restantes')::integer,
    'base', 'Los mismos días de la semana de las últimas ' || (v ->> 'semanas')
            || case when (v ->> 'semanas') = '1' then ' semana, ' else ' semanas, ' end
            || privado.periodo((v ->> 'base_desde')::date, (v ->> 'base_hasta')::date, v_hoy),
    'desglose', (select coalesce(jsonb_agg(jsonb_build_object(
                   'fecha', e ->> 'fecha',
                   'dia', privado.fecha_en_palabras((e ->> 'fecha')::date, v_hoy),
                   'estimado', privado.dinero((e ->> 'estimado')::numeric)) order by e ->> 'fecha'), '[]')
                 from jsonb_array_elements(v -> 'desglose') as e),
    'leido', v_leido);
end;
$$;


-- ─── Lo que no es venta, por rango ────────────────────────────────────────────
-- Las partes de reporte_del_dia que cuentan descuentos, cancelaciones, pagos cancelados y
-- propinas, ahora para un rango de días de negocio. reporte_del_dia las llama con un solo día, y
-- la sexta herramienta con cualquier rango: un día del agente es un día de Cortes y reportes, y las
-- pruebas de Cortes las siguen cuidando. Cada renglón trae su día de negocio: el de su cuenta, o el
-- de su turno en los pagos y las propinas.

-- Los turnos que se abrieron del día p_desde al p_hasta.
create function privado.turnos_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
returns setof public.turnos
language sql
stable
security definer
set search_path = ''
as $$
  select t.*
  from public.restaurantes r
  join public.turnos t on t.restaurante_id = r.id
  where r.id = p_restaurante_id
    and t.created_at >= privado.inicio_de_dia(r.zona_horaria, r.hora_corte, p_desde)
    and t.created_at < privado.inicio_de_dia(r.zona_horaria, r.hora_corte, p_hasta + 1);
$$;

-- Los descuentos de las cuentas cerradas de esos días, con su monto final: por renglón (los
-- activos) y a toda la cuenta, con quién lo pidió y quién lo autorizó (lo último de la bitácora).
create function privado.descuentos_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
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
    select v.id as venta_id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre) as cuenta,
           i.id as renglon_id, i.producto_id, i.nombre, i.cantidad, i.descuento_tipo, i.descuento_valor, i.descuento,
           i.descuento_motivo, 'venta_items' as tabla, i.id::text as registro, v.created_at as abierta_at
    from dia v
    join public.venta_items i on i.restaurante_id = v.restaurante_id and i.venta_id = v.id
    where v.estado = 'cerrada' and i.estado = 'activo' and i.descuento > 0
    union all
    select v.id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre), null, null, null, null,
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

-- Las cancelaciones de las cuentas de esos días (en cualquier estado): los renglones cancelados y
-- las cuentas canceladas con motivo y PIN, por lo que valían al cancelarlas. Los renglones que se
-- cancelaron con su cuenta van dentro de ella, y una cuenta que se juntó con otra no es una
-- cancelación.
create function privado.cancelaciones_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
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
    select v.id as venta_id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre) as cuenta,
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
    select 'renglon', v.id, v.folio, v.tipo, coalesce(v.mesa_nombre, v.cliente_nombre), v.estado, i.id,
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

-- Los pagos cancelados de los turnos que se abrieron esos días: son dinero del cajón.
create function privado.pagos_cancelados_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
returns table (
  turno_id bigint, pago_id bigint, folio integer, cuenta text, metodo text, monto numeric, propina numeric,
  motivo text, pidio_id bigint, pidio text, autorizo_id bigint, autorizo text, cancelado_at timestamptz, dia date
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, p.id, v.folio, coalesce(v.mesa_nombre, v.cliente_nombre), p.metodo, p.monto, p.propina,
         p.cancelado_motivo, p.cancelado_por, q.nombre, p.autorizado_por, au.nombre, p.cancelado_at,
         privado.dia_de_negocio(r.zona_horaria, r.hora_corte, t.created_at)
  from privado.turnos_del_rango(p_restaurante_id, p_desde, p_hasta) t
  join public.restaurantes r on r.id = t.restaurante_id
  join public.pagos p on p.restaurante_id = t.restaurante_id and p.turno_id = t.id and p.cancelado_at is not null
  join public.ventas v on v.restaurante_id = p.restaurante_id and v.id = p.venta_id
  join public.miembros q on q.restaurante_id = p.restaurante_id and q.id = p.cancelado_por
  left join public.miembros au on au.restaurante_id = p.restaurante_id and au.id = p.autorizado_por;
$$;

-- Las propinas de los turnos que se abrieron esos días, como en el corte: de cada mesero, lo que
-- le tocó, lo que ya se le pagó de la caja y lo que falta (privado.propinas_del_turno).
create function privado.propinas_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
returns table (turno_id bigint, dia date, miembro_id bigint, nombre text, total numeric, pagado numeric, falta numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, privado.dia_de_negocio(r.zona_horaria, r.hora_corte, t.created_at),
         x.miembro_id, x.nombre, x.total, x.pagado, x.falta
  from privado.turnos_del_rango(p_restaurante_id, p_desde, p_hasta) t
  join public.restaurantes r on r.id = t.restaurante_id
  cross join lateral privado.propinas_del_turno(t.id) x;
$$;


-- ─── Cortes y reportes, sobre las funciones de rango ──────────────────────────
-- La misma salida de la migración otros_con_cuenta: ahora sus partes salen de las funciones de
-- rango, con un solo día. Reemplazarla conserva sus permisos.

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
           'accion', b.accion, 'detalle', b.detalle, 'cuenta', coalesce(v.mesa_nombre, v.cliente_nombre),
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


-- ─── Herramienta 6 · cancelaciones_descuentos_propinas(...) ───────────────────
-- Lo que Cortes y reportes muestra día por día, para cualquier rango y agrupado: quién canceló
-- más, cuánto se fue en descuentos, cuánta propina juntó cada mesero, los pagos cancelados. Por
-- grupo: cuántas veces, el importe y sus 3 motivos más recientes; agrupando por persona, también
-- quién autorizó y cuántas veces. Después del límite, el resto; siempre, el total.

create function privado.herramienta_cdp(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_desde date;
  v_hasta date;
  v_ver text;
  v_agrupar text;
  v_limite integer;
  v_hoy date := privado.hoy_de(p_restaurante_id);
  v_leido jsonb;
  v_resultado jsonb;
begin
  perform privado.revisar_argumentos('cancelaciones_descuentos_propinas', p_args,
    array['desde', 'hasta', 'ver', 'agrupar_por', 'limite']);
  v_desde := privado.arg_fecha(p_args, 'desde');
  v_hasta := privado.arg_fecha(p_args, 'hasta');
  perform privado.revisar_rango('desde', v_desde, 'hasta', v_hasta);
  v_ver := privado.arg_opcion(p_args, 'ver', array['cancelaciones', 'descuentos', 'propinas', 'pagos_cancelados']);
  v_agrupar := privado.arg_opcion(p_args, 'agrupar_por', array['persona', 'autorizo', 'dia', 'producto', 'total'], 'persona');
  if v_agrupar = 'producto' and v_ver not in ('cancelaciones', 'descuentos') then
    raise exception 'agrupar_por producto solo va con cancelaciones y descuentos. Con % las opciones son: %.', v_ver,
      case v_ver when 'propinas' then 'persona, dia, total' else 'persona, autorizo, dia, total' end
      using errcode = '22023';
  end if;
  if v_agrupar = 'autorizo' and v_ver = 'propinas' then
    raise exception 'Las propinas no se autorizan. Con propinas, agrupar_por puede ser: persona, dia, total.'
      using errcode = '22023';
  end if;
  v_limite := privado.arg_entero(p_args, 'limite', 1, 50, 10);

  v_leido := privado.leido(
    case v_ver when 'cancelaciones' then 'corte' when 'descuentos' then 'porcentaje' else 'billete' end,
    case v_ver when 'cancelaciones' then 'Las cancelaciones ' when 'descuentos' then 'Los descuentos '
               when 'propinas' then 'Las propinas ' else 'Los pagos cancelados ' end
    || privado.periodo(v_desde, v_hasta, v_hoy, 'de')
    || case v_agrupar
         when 'persona' then case v_ver when 'cancelaciones' then ', por quién las pidió'
                                        when 'descuentos' then ', por quién los hizo'
                                        when 'propinas' then ', por mesero'
                                        else ', por quién los pidió' end
         when 'autorizo' then case v_ver when 'cancelaciones' then ', por quién las autorizó'
                                         else ', por quién los autorizó' end
         when 'dia' then ', día por día'
         when 'producto' then ', por producto'
         else '' end);

  if v_ver = 'propinas' then
    with x as (
      select case v_agrupar when 'persona' then p.miembro_id::text when 'dia' then p.dia::text else 'total' end as clave,
             case v_agrupar when 'persona' then p.nombre when 'dia' then privado.fecha_en_palabras(p.dia, v_hoy)
                            else 'Total' end as nombre,
             p.total, p.pagado, p.falta
      from privado.propinas_del_rango(p_restaurante_id, v_desde, v_hasta) p
    ),
    g as (
      select x.clave, x.nombre, sum(x.total) as total, sum(x.pagado) as pagado, sum(x.falta) as falta
      from x group by x.clave, x.nombre
    ),
    o as (
      select g.*, row_number() over (order by
               case when v_agrupar = 'dia' then g.clave end, g.total desc, g.nombre, g.clave) as lugar,
             count(*) over () as grupos
      from g
    )
    select jsonb_build_object(
      'grupos', coalesce(jsonb_agg(jsonb_build_object(
                  'nombre', o.nombre, 'propinas', privado.dinero(o.total),
                  'pagado', privado.dinero(o.pagado), 'falta', privado.dinero(o.falta))
                  order by o.lugar) filter (where o.lugar <= v_limite), '[]'),
      'resto', case when max(o.grupos) > v_limite then jsonb_build_object(
                 'grupos', max(o.grupos) - v_limite,
                 'propinas', privado.dinero(coalesce(sum(o.total) filter (where o.lugar > v_limite), 0))) end,
      'total', jsonb_build_object('propinas', privado.dinero(coalesce(sum(o.total), 0)),
                                  'pagado', privado.dinero(coalesce(sum(o.pagado), 0)),
                                  'falta', privado.dinero(coalesce(sum(o.falta), 0))))
    into v_resultado
    from o;
  else
    with x as (
      select c.pidio_id as persona_id, c.pidio as persona, c.autorizo_id, c.autorizo, c.dia,
             case when c.que = 'cuenta' then null else c.producto_id end as producto_id, c.importe,
             0::numeric as propina, c.motivo, c.created_at
      from privado.cancelaciones_del_rango(p_restaurante_id, v_desde, v_hasta) c
      where v_ver = 'cancelaciones'
      union all
      select d.pidio_id, d.pidio, d.autorizo_id, d.autorizo, d.dia, d.producto_id, d.descuento, 0, d.motivo,
             d.created_at
      from privado.descuentos_del_rango(p_restaurante_id, v_desde, v_hasta) d
      where v_ver = 'descuentos'
      union all
      select p.pidio_id, p.pidio, p.autorizo_id, p.autorizo, p.dia, null, p.monto, p.propina, p.motivo, p.cancelado_at
      from privado.pagos_cancelados_del_rango(p_restaurante_id, v_desde, v_hasta) p
      where v_ver = 'pagos_cancelados'
    ),
    k as (
      select x.*,
             case v_agrupar
               when 'persona' then coalesce(x.persona_id::text, 'sin_dato')
               when 'autorizo' then coalesce(x.autorizo_id::text, 'sin_dato')
               when 'dia' then x.dia::text
               when 'producto' then coalesce(x.producto_id::text, 'cuenta')
               else 'total' end as clave,
             case v_agrupar
               when 'persona' then coalesce(x.persona, 'Sin dato')
               when 'autorizo' then coalesce(x.autorizo, 'Sin dato')
               when 'dia' then privado.fecha_en_palabras(x.dia, v_hoy)
               when 'producto' then coalesce(pr.nombre, 'A toda la cuenta')
               else 'Total' end as nombre
      from x
      left join public.productos pr on pr.restaurante_id = p_restaurante_id and pr.id = x.producto_id
    ),
    g as (
      select k.clave, k.nombre, count(*) as veces, sum(k.importe) as importe, sum(k.propina) as propina,
             (select coalesce(jsonb_agg(m.motivo order by m.ultimo desc), '[]')
              from (select k2.motivo, max(k2.created_at) as ultimo from k k2
                    where k2.clave = k.clave and k2.motivo is not null
                    group by k2.motivo order by max(k2.created_at) desc limit 3) m) as motivos,
             case when v_agrupar = 'persona' then
               (select coalesce(jsonb_agg(jsonb_build_object('nombre', a.autorizo, 'veces', a.veces)
                                          order by a.veces desc, a.autorizo), '[]')
                from (select coalesce(k3.autorizo, 'Sin dato') as autorizo, count(*) as veces from k k3
                      where k3.clave = k.clave group by 1) a) end as autorizo
      from k
      group by k.clave, k.nombre
    ),
    o as (
      select g.*, row_number() over (order by
               case when v_agrupar = 'dia' then g.clave end, g.importe desc, g.veces desc, g.nombre, g.clave) as lugar,
             count(*) over () as grupos
      from g
    )
    select jsonb_build_object(
      'grupos', coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                  'nombre', o.nombre, 'veces', o.veces, 'importe', privado.dinero(o.importe),
                  'propina', case when v_ver = 'pagos_cancelados' and o.propina > 0 then privado.dinero(o.propina) end,
                  'motivos', o.motivos, 'autorizo', o.autorizo))
                  order by o.lugar) filter (where o.lugar <= v_limite), '[]'),
      'resto', case when max(o.grupos) > v_limite then jsonb_build_object(
                 'grupos', max(o.grupos) - v_limite,
                 'veces', coalesce(sum(o.veces) filter (where o.lugar > v_limite), 0),
                 'importe', privado.dinero(coalesce(sum(o.importe) filter (where o.lugar > v_limite), 0))) end,
      'total', jsonb_build_object('veces', coalesce(sum(o.veces), 0),
                                  'importe', privado.dinero(coalesce(sum(o.importe), 0)))
               || case when v_ver = 'pagos_cancelados'
                       then jsonb_build_object('propina', privado.dinero(coalesce(sum(o.propina), 0))) else '{}' end)
    into v_resultado
    from o;
  end if;

  return v_resultado || jsonb_build_object(
    'ver', v_ver, 'agrupar_por', v_agrupar, 'desde', v_desde, 'hasta', v_hasta,
    'sin_datos', v_resultado -> 'grupos' = '[]'::jsonb,
    'leido', v_leido);
end;
$$;


-- ─── agente_herramienta: la puerta de las 6 herramientas ──────────────────────
-- El Worker llama aquí cada tool_call del modelo, con la sesión del gerente, el restaurante (el
-- modelo nunca lo elige), el nombre de la herramienta y sus argumentos tal como llegaron. Solo le
-- contesta a un gerente de ese restaurante con la licencia funcionando: a nadie más, ni con 0
-- renglones. Un argumento mal puesto es un error con su mensaje, para que el modelo corrija.

create function public.agente_herramienta(p_restaurante_id uuid, p_herramienta text, p_argumentos jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_args jsonb := coalesce(p_argumentos, '{}');
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante le preguntan al agente' using errcode = '42501';
  end if;
  if jsonb_typeof(v_args) <> 'object' then
    raise exception 'Los argumentos van en un objeto JSON.' using errcode = '22023';
  end if;

  if p_herramienta = 'resumen' then
    return privado.herramienta_resumen(p_restaurante_id, v_args);
  elsif p_herramienta = 'ranking' then
    return privado.herramienta_ranking(p_restaurante_id, v_args);
  elsif p_herramienta = 'comparar' then
    return privado.herramienta_comparar(p_restaurante_id, v_args);
  elsif p_herramienta = 'detalle' then
    return privado.herramienta_detalle(p_restaurante_id, v_args);
  elsif p_herramienta = 'proyeccion_mes' then
    return privado.herramienta_proyeccion_mes(p_restaurante_id, v_args);
  elsif p_herramienta = 'cancelaciones_descuentos_propinas' then
    return privado.herramienta_cdp(p_restaurante_id, v_args);
  end if;
  raise exception 'No hay una herramienta «%». Las que hay: resumen, ranking, comparar, detalle, proyeccion_mes, cancelaciones_descuentos_propinas.',
    p_herramienta using errcode = '22023';
end;
$$;


-- ─── contexto_agente: lo que siempre tiene a la mano ──────────────────────────
-- Lo que el Worker pone en el prompt: el restaurante, la fecha y la hora en su zona, el día de
-- negocio, cómo quiere el gerente que lo llamen, el menú (cada producto con su id, su categoría,
-- su precio y si está oculto), las mesas, el equipo y las cuentas abiertas ahora con lo que falta
-- por cobrar. Las cuentas abiertas van aquí porque son pocas y cambian minuto a minuto; nunca van
-- el teléfono ni la dirección de un pedido.

create function public.contexto_agente(p_restaurante_id uuid)
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
             || '["Para llevar", "A domicilio"]'::jsonb,
    'equipo', (select coalesce(jsonb_agg(jsonb_build_object('nombre', m.nombre, 'roles', to_jsonb(m.roles))
                                         order by m.nombre, m.id), '[]')
               from public.miembros m
               where m.restaurante_id = p_restaurante_id and m.activo),
    'cuentas_abiertas', (
      select jsonb_build_object(
        'cuentas', count(*),
        'por_cobrar', privado.dinero(coalesce(sum(v.total - v.pagado), 0)),
        'lista', coalesce(jsonb_agg(jsonb_build_object(
                   'cuenta', case when v.tipo = 'mesa' then coalesce(me.nombre, v.mesa_nombre) else v.cliente_nombre end,
                   'tipo', case v.tipo when 'mesa' then 'mesa' when 'para_llevar' then 'para llevar' else 'a domicilio' end,
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


-- ─── cifras_de_inicio: las cuatro cifras ──────────────────────────────────────
-- Inicio pide sus cuatro cifras en una sola llamada, con las mismas piezas que el agente, y la
-- app no suma nada:
--   vendido_hoy: lo de hoy y lo que ayer ya estaba cerrado a esta misma hora (las cuentas de ayer
--     cerradas hasta hoy menos un día, en la zona del restaurante), y el % redondeado a entero;
--     sin ventas ayer a esta hora no hay %.
--   semana: de lunes a hoy, un renglón por día; los que faltan, vacíos.
--   lo_mas_vendido: los 3 productos con más piezas de la semana; a igualdad, el de más dinero.
--   mes: lo vendido día por día con su acumulado, y para cuánto va (proyeccion_mes).
-- Los números van como números: la app los escribe.

create function public.cifras_de_inicio(p_restaurante_id uuid)
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
  v_lunes date;
  v_d1 date;
  v_vendido numeric;
  v_ayer numeric;
  v_proyeccion jsonb;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo los gerentes de este restaurante ven sus cifras' using errcode = '42501';
  end if;
  select zona_horaria, hora_corte into v_zona, v_corte from public.restaurantes where id = p_restaurante_id;
  v_hoy := privado.dia_de_negocio(v_zona, v_corte);
  v_lunes := v_hoy - (extract(isodow from v_hoy)::integer - 1);
  v_d1 := date_trunc('month', v_hoy)::date;

  v_vendido := coalesce((select x.importe from privado.ventas_agrupadas(p_restaurante_id, v_hoy, v_hoy, 'total') x), 0);
  v_ayer := coalesce((
    select sum(c.total)
    from privado.cuentas_del_dia(p_restaurante_id, v_hoy - 1, v_hoy - 1) c
    where c.estado = 'cerrada'
      and c.cerrada_at <= ((now() at time zone v_zona) - interval '1 day') at time zone v_zona), 0)::numeric(12,2);
  v_proyeccion := privado.proyeccion_del_mes(p_restaurante_id);

  return jsonb_build_object(
    'hoy', v_hoy,
    'hora', to_char(now() at time zone v_zona, 'HH24:MI'),
    'vendido_hoy', jsonb_build_object(
      'hoy', v_vendido,
      'ayer_a_esta_hora', v_ayer,
      'porcentaje', case when v_ayer > 0 then round((v_vendido - v_ayer) * 100 / v_ayer)::integer end),
    'semana', jsonb_build_object(
      'vendido', coalesce((select x.importe from privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'total') x), 0),
      'dias', (select jsonb_agg(jsonb_build_object(
                 'dia', d::date,
                 'importe', case when d::date <= v_hoy then coalesce(x.importe, 0) end)
                 order by d)
               from generate_series(v_lunes::timestamp, (v_lunes + 6)::timestamp, interval '1 day') as d
               left join privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'dia') x
                 on x.clave = to_char(d, 'YYYY-MM-DD'))),
    'lo_mas_vendido', (select coalesce(jsonb_agg(jsonb_build_object(
                         'nombre', t.etiqueta, 'unidades', t.unidades, 'importe', t.importe)
                         order by t.unidades desc, t.importe desc, t.etiqueta), '[]')
                       from (select x.etiqueta, x.unidades, x.importe
                             from privado.ventas_agrupadas(p_restaurante_id, v_lunes, v_hoy, 'producto') x
                             where x.clave <> 'descuento_cuenta' and x.unidades > 0
                             order by x.unidades desc, x.importe desc, x.etiqueta
                             limit 3) t),
    'mes', jsonb_build_object(
      'vendido', (v_proyeccion ->> 'ya_vendido')::numeric,
      'dias', (select jsonb_agg(jsonb_build_object('dia', m.dia, 'importe', m.importe, 'acumulado', m.acumulado)
                                order by m.dia)
               from (select d::date as dia, coalesce(x.importe, 0) as importe,
                            sum(coalesce(x.importe, 0)) over (order by d) as acumulado
                     from generate_series(v_d1::timestamp, v_hoy::timestamp, interval '1 day') as d
                     left join privado.ventas_agrupadas(p_restaurante_id, v_d1, v_hoy, 'dia') x
                       on x.clave = to_char(d, 'YYYY-MM-DD')) m),
      'va_para', (v_proyeccion ->> 'proyeccion')::numeric)
  );
end;
$$;


-- ─── Permisos ─────────────────────────────────────────────────────────────────
-- Las herramientas, el contexto, las cifras y el estado de la IA, para quien tiene sesión (cada
-- una revisa que sea gerente); el tope y lo gastado, para Fragmentless (cada una lo revisa); el
-- gasto, solo para el Worker con la llave secreta. Lo de privado no lo llama nadie desde afuera.

revoke execute on function
  privado.dinero(numeric),
  privado.nombre_dia(date),
  privado.nombre_mes(date),
  privado.dia_y_mes(date, date),
  privado.fecha_en_palabras(date, date),
  privado.periodo(date, date, date, text),
  privado.con_mayuscula(text),
  privado.ventas_agrupadas(uuid, date, date, text, bigint, text, bigint, bigint, integer),
  privado.primer_dia_con_ventas(uuid),
  privado.revisar_argumentos(text, jsonb, text[]),
  privado.arg_fecha(jsonb, text, boolean),
  privado.arg_opcion(jsonb, text, text[], text),
  privado.arg_entero(jsonb, text, integer, integer, integer, text),
  privado.arg_texto(jsonb, text),
  privado.revisar_rango(text, date, text, date),
  privado.buscar_mesa(uuid, text),
  privado.buscar_categoria(uuid, text),
  privado.buscar_persona(uuid, text),
  privado.buscar_producto(uuid, integer),
  privado.hoy_de(uuid),
  privado.leido(text, text),
  privado.los_dias(integer),
  privado.dinero_con_signo(numeric),
  privado.herramienta_resumen(uuid, jsonb),
  privado.herramienta_ranking(uuid, jsonb),
  privado.cambio(numeric, numeric),
  privado.herramienta_comparar(uuid, jsonb),
  privado.herramienta_detalle(uuid, jsonb),
  privado.proyeccion_del_mes(uuid, date),
  privado.herramienta_proyeccion_mes(uuid, jsonb),
  privado.turnos_del_rango(uuid, date, date),
  privado.descuentos_del_rango(uuid, date, date),
  privado.cancelaciones_del_rango(uuid, date, date),
  privado.pagos_cancelados_del_rango(uuid, date, date),
  privado.propinas_del_rango(uuid, date, date),
  privado.herramienta_cdp(uuid, jsonb)
from public, anon, authenticated, service_role;

revoke execute on function
  public.agente_herramienta(uuid, text, jsonb),
  public.contexto_agente(uuid),
  public.cifras_de_inicio(uuid),
  public.estado_ia(uuid),
  public.fijar_tope_ia(uuid, numeric),
  public.uso_ia_cliente(uuid),
  public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)
from public, anon, authenticated, service_role;

grant execute on function
  public.agente_herramienta(uuid, text, jsonb),
  public.contexto_agente(uuid),
  public.cifras_de_inicio(uuid),
  public.estado_ia(uuid),
  public.fijar_tope_ia(uuid, numeric),
  public.uso_ia_cliente(uuid)
to authenticated;

grant execute on function public.anotar_uso_ia(uuid, text, text, bigint, bigint, bigint, bigint)
to service_role;
