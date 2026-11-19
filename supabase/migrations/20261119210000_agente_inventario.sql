-- El agente IA lee el inventario (19 de noviembre de 2026; planes/trabajo/agente-inventario/): la séptima herramienta,
-- inventario(ver, …), y los ingredientes en contexto_agente. Lo decidido: las 8 encuestas y los 14 «Lo que decidí yo»
-- de encuestas.md, y el texto de la libreta 1 («Herramienta 7 · inventario(...)», rev 7 de segundo uso) en libretas.md.
--
-- Solo lee: no hay tablas nuevas y no se reescribe nada del inventario. Cada `ver` es una función privada sobre
-- ingredientes, recetas, movimientos_inventario y privado.receta_en_ingredientes, y entra por agente_herramienta con
-- la sesión del gerente, solo de su sucursal. Postgres hace todas las cuentas y escribe cada cantidad con su unidad,
-- como la vista Inventario: la IA solo lee.


-- ─── Las palabras ─────────────────────────────────────────────────────────────

-- Una cantidad como la escribe la vista Inventario (lib/inventario.ts, cantidad): hasta tres decimales sin ceros de más,
-- comas en los miles y su unidad. «4.2 kg», «−0.4 kg», «1,200.5 g», «46 piezas», «1 pieza».
create function privado.cantidad_escrita(p_cantidad numeric, p_unidad text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when x.n < 0 then '−' else '' end
         || rtrim(rtrim(to_char(abs(x.n), 'FM999,999,999,990.000'), '0'), '.')
         || ' ' || case when p_unidad <> 'pieza' then p_unidad when abs(x.n) = 1 then 'pieza' else 'piezas' end
  from (select round(p_cantidad, 3) as n) x;
$$;

-- El motivo de una merma, como lo dice la ventana «Merma».
create function privado.motivo_escrito(p_motivo text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_motivo
    when 'se_echo_a_perder' then 'Se echó a perder'
    when 'se_cayo_o_quemo' then 'Se cayó o se quemó'
    when 'caduco' then 'Caducó'
    when 'otro' then 'Otro'
  end;
$$;

-- Cuándo se anotó algo, con su día de negocio: «hoy a las 14:05», «ayer a las 00:40», «el sábado 15 de noviembre a las
-- 09:10».
create function privado.cuando_se_anoto(p_momento timestamptz, p_zona text, p_corte smallint, p_hoy date)
returns text
language sql
stable
set search_path = ''
as $$
  select case x.dia when p_hoy then 'hoy' when p_hoy - 1 then 'ayer'
                    else 'el ' || privado.fecha_en_palabras(x.dia, p_hoy) end
         || ' a las ' || to_char(p_momento at time zone p_zona, 'HH24:MI')
  from (select privado.dia_de_negocio(p_zona, p_corte, p_momento) as dia) x;
$$;

-- Quién anotó algo, como el historial de un ingrediente: el gerente por su nombre, la cocina «Chente · cocina».
create function privado.quien_anoto(p_restaurante_id uuid, p_miembro_id bigint)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when 'gerente' = any (m.roles) then m.nombre
              when 'cocina' = any (m.roles) then m.nombre || ' · cocina'
              else m.nombre end
  from public.miembros m
  where m.restaurante_id = p_restaurante_id and m.id = p_miembro_id;
$$;


-- ─── Los argumentos ───────────────────────────────────────────────────────────

create function privado.arg_si_no(p_args jsonb, p_nombre text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
  if coalesce(p_args -> p_nombre, 'null') = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_args -> p_nombre) <> 'boolean' then
    raise exception '% va con true o false.', p_nombre using errcode = '22023';
  end if;
  return (p_args ->> p_nombre)::boolean;
end;
$$;

-- Un ingrediente por su nombre. Con p_con_archivados (lo de un periodo) también los archivados: primero el de hoy y
-- luego el último que se archivó. Si no está, el error trae los que hay.
create function privado.buscar_ingrediente(p_restaurante_id uuid, p_nombre text, p_con_archivados boolean,
                                           out ingrediente_id bigint, out nombre text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  select i.id, i.nombre into ingrediente_id, nombre
  from public.ingredientes i
  where i.restaurante_id = p_restaurante_id and lower(btrim(i.nombre)) = lower(btrim(p_nombre))
    and (p_con_archivados or i.archivado_at is null)
  order by i.archivado_at desc nulls first, i.id desc
  limit 1;
  if ingrediente_id is null then
    raise exception 'No hay un ingrediente «%». %', p_nombre,
      coalesce('Los que hay: ' || (select string_agg(i.nombre, ', ' order by i.nombre, i.id) from public.ingredientes i
                                   where i.restaurante_id = p_restaurante_id and i.archivado_at is null) || '.',
               'Todavía no hay ingredientes: se agregan en Inventario, en el panel.')
      using errcode = '22023';
  end if;
end;
$$;

-- Un platillo del menú por su nombre (sin archivados ni envíos). Si no está, el error trae los que hay.
create function privado.buscar_platillo(p_restaurante_id uuid, p_nombre text, out producto_id bigint, out nombre text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  select p.id, p.nombre into producto_id, nombre
  from public.productos p
  where p.restaurante_id = p_restaurante_id and p.archivado_at is null and not p.es_envio
    and lower(btrim(p.nombre)) = lower(btrim(p_nombre))
  order by p.id desc
  limit 1;
  if producto_id is null then
    raise exception 'No hay un platillo «%» en el menú. Los que hay: %.', p_nombre,
      coalesce((select string_agg(p.nombre, ', ' order by c.orden, c.id, p.orden, p.id)
                from public.productos p
                join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
                where p.restaurante_id = p_restaurante_id and p.archivado_at is null and not p.es_envio), 'ninguno')
      using errcode = '22023';
  end if;
end;
$$;


-- ─── ver = queda ──────────────────────────────────────────────────────────────
-- Por ingrediente (sin archivados): cuánto queda, su mínimo, cómo va (Bien · Se acaba · Se acabó, como la vista: se
-- acaba en su mínimo o menos, se acabó en 0 o menos), cuánto le falta para su mínimo y para cuántos días alcanza.
-- Los días son un estimado: lo que queda entre lo que restaron las ventas en promedio en los últimos 28 días de
-- negocio sin hoy, contando solo los días que se cerró alguna cuenta y desde el día en que se dio de alta el
-- ingrediente. Las mermas no cuentan. Sin gasto no hay días; con menos de 7 días de historia, con_pocos_dias. Con
-- p_solo_falta, solo lo que se acabó, lo que se acaba y lo que alcanza para menos de 2 días: «qué comprar». Primero los
-- que se acabaron, luego los que se acaban y luego los demás, cada grupo por nombre.

create function privado.inventario_queda(p_restaurante_id uuid, p_ingrediente_id bigint, p_solo_falta boolean,
                                         p_limite integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte, privado.dia_de_negocio(zona_horaria, hora_corte) as hoy
    from public.restaurantes
    where id = p_restaurante_id
  ),
  cuentas as (
    select v.id, v.estado, privado.dia_de_negocio(r.zona, r.corte, v.created_at) as dia
    from r
    cross join lateral privado.cuentas_del_dia(p_restaurante_id, r.hoy - 28, r.hoy - 1) v
  ),
  dias_con_ventas as (
    select distinct c.dia from cuentas c where c.estado = 'cerrada'
  ),
  -- Lo que restaron las ventas, por ingrediente y por el día de su cuenta: una cuenta reabierta regresó lo suyo.
  gasto as (
    select m.ingrediente_id, c.dia, -sum(m.cantidad) as cantidad
    from cuentas c
    join public.movimientos_inventario m on m.restaurante_id = p_restaurante_id and m.venta_id = c.id
    where m.tipo in ('venta', 'regreso')
    group by m.ingrediente_id, c.dia
  ),
  ing as (
    select i.id, i.nombre, i.unidad, i.minimo, i.existencia,
           privado.dia_de_negocio(r.zona, r.corte, i.created_at) as desde
    from public.ingredientes i
    cross join r
    where i.restaurante_id = p_restaurante_id and i.archivado_at is null
      and (p_ingrediente_id is null or i.id = p_ingrediente_id)
  ),
  calc as (
    select g.*, p.gastado, p.dias,
           case when g.existencia <= 0 then 'se_acabo'
                when g.minimo is not null and g.existencia <= g.minimo then 'se_acaba'
                else 'bien' end as va,
           case when p.gastado > 0 and p.dias > 0 then
             case when g.existencia <= 0 then 0::numeric else round(g.existencia * p.dias / p.gastado, 1) end
           end as alcanza
    from ing g
    cross join lateral (
      select (select coalesce(sum(x.cantidad), 0) from gasto x where x.ingrediente_id = g.id and x.dia >= g.desde)
               as gastado,
             (select count(*) from dias_con_ventas d where d.dia >= g.desde) as dias
    ) p
  ),
  lista as (
    select c.*,
           row_number() over (order by case c.va when 'se_acabo' then 0 when 'se_acaba' then 1 else 2 end, c.nombre, c.id)
             as lugar,
           count(*) over () as renglones
    from calc c
    where not p_solo_falta or c.va <> 'bien' or c.alcanza < 2
  )
  select jsonb_build_object(
    'ingredientes', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'ingrediente', l.nombre,
               'queda', privado.cantidad_escrita(l.existencia, l.unidad),
               'minimo', case when l.minimo is not null then privado.cantidad_escrita(l.minimo, l.unidad) end,
               'como_va', case l.va when 'se_acabo' then 'Se acabó' when 'se_acaba' then 'Se acaba' else 'Bien' end,
               'le_falta_para_su_minimo',
                 case when l.existencia < l.minimo then privado.cantidad_escrita(l.minimo - l.existencia, l.unidad) end,
               'alcanza_dias', l.alcanza,
               'es_estimado', case when l.alcanza is not null then true end,
               'con_pocos_dias', case when l.alcanza is not null and l.dias < 7 then true end,
               'sin_gasto', case when l.alcanza is null then true end))
             order by l.lugar)
      from lista l
      where l.lugar <= p_limite), '[]'),
    'resto', (select case when max(l.renglones) > p_limite
                          then jsonb_build_object('ingredientes', max(l.renglones) - p_limite) end
              from lista l),
    'en_inventario', (select count(*) from calc),
    'se_acabaron', (select count(*) from calc where va = 'se_acabo'),
    'se_acaban', (select count(*) from calc where va = 'se_acaba'));
$$;


-- ─── ver = perdido ────────────────────────────────────────────────────────────
-- Por ingrediente (o día por día de uno): las mermas, con su motivo, más lo que faltó al contar; lo que sobró al
-- contar va aparte y no se resta. Cuentan en el día de negocio en que se anotaron. Lo deshecho no sale, ni el primer
-- conteo de un ingrediente, que es cuánto había al darlo de alta. Trae las 3 mermas más recientes de cada renglón,
-- con quién las anotó y, si fue un platillo entero, cuál («3 × Taco al pastor»). Por nombre, o por día.

create function privado.inventario_perdido(p_restaurante_id uuid, p_desde date, p_hasta date, p_ingrediente_id bigint,
                                           p_agrupar text, p_limite integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte, privado.dia_de_negocio(zona_horaria, hora_corte) as hoy
    from public.restaurantes
    where id = p_restaurante_id
  ),
  movs as (
    select m.id, m.ingrediente_id, m.tipo, m.cantidad, m.motivo, m.nota, m.producto_id, m.platillos, m.anotado_por,
           m.clave, m.created_at, privado.dia_de_negocio(r.zona, r.corte, m.created_at) as dia
    from r
    join public.movimientos_inventario m on m.restaurante_id = p_restaurante_id
    where m.tipo in ('merma', 'conteo')
      and m.created_at >= privado.inicio_de_dia(r.zona, r.corte, p_desde)
      and m.created_at < privado.inicio_de_dia(r.zona, r.corte, p_hasta + 1)
      and (p_ingrediente_id is null or m.ingrediente_id = p_ingrediente_id)
      and not exists (select 1 from public.movimientos_inventario d
                      where d.restaurante_id = m.restaurante_id and d.deshace_id = m.id)
      and (m.tipo = 'merma' or exists (select 1 from public.movimientos_inventario a
                                        where a.restaurante_id = m.restaurante_id
                                          and a.ingrediente_id = m.ingrediente_id and a.id < m.id))
  ),
  k as (
    select x.*, i.unidad,
           case when p_agrupar = 'dia' then x.dia::text else x.ingrediente_id::text end as grupo,
           case when p_agrupar = 'dia' then privado.fecha_en_palabras(x.dia, r.hoy) else i.nombre end as etiqueta
    from movs x
    cross join r
    join public.ingredientes i on i.restaurante_id = p_restaurante_id and i.id = x.ingrediente_id
  ),
  g as (
    select k.grupo, k.etiqueta, min(k.unidad) as unidad, min(k.dia) as dia,
           coalesce(-sum(k.cantidad) filter (where k.tipo = 'merma'), 0) as mermas,
           count(*) filter (where k.tipo = 'merma') as veces,
           coalesce(-sum(k.cantidad) filter (where k.tipo = 'conteo' and k.cantidad < 0), 0) as falto,
           coalesce(sum(k.cantidad) filter (where k.tipo = 'conteo' and k.cantidad > 0), 0) as sobro
    from k
    group by k.grupo, k.etiqueta
  ),
  o as (
    select g.*,
           row_number() over (order by case when p_agrupar = 'dia' then g.grupo end, g.etiqueta, g.grupo) as lugar,
           count(*) over () as grupos
    from g
    where g.mermas > 0 or g.falto > 0 or g.sobro > 0
  )
  select jsonb_build_object(
    'renglones', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               case when p_agrupar = 'dia' then 'dia' else 'ingrediente' end, o.etiqueta,
               'fecha', case when p_agrupar = 'dia' then o.dia end,
               'mermas', privado.cantidad_escrita(o.mermas, o.unidad),
               'veces', o.veces,
               'por_motivo', (
                 select jsonb_agg(jsonb_build_object('motivo', privado.motivo_escrito(t.motivo),
                                                     'cantidad', privado.cantidad_escrita(t.cantidad, o.unidad))
                                  order by t.cantidad desc, t.motivo)
                 from (select k.motivo, -sum(k.cantidad) as cantidad from k
                       where k.grupo = o.grupo and k.tipo = 'merma'
                       group by k.motivo) t),
               'falto_al_contar', privado.cantidad_escrita(o.falto, o.unidad),
               'se_perdio', privado.cantidad_escrita(o.mermas + o.falto, o.unidad),
               'sobro_al_contar', case when o.sobro > 0 then privado.cantidad_escrita(o.sobro, o.unidad) end,
               'recientes', (
                 select jsonb_agg(jsonb_build_object(
                          'cuando', privado.cuando_se_anoto(t.created_at, r.zona, r.corte, r.hoy),
                          'cantidad', privado.cantidad_escrita(-t.cantidad, o.unidad),
                          'motivo', privado.motivo_escrito(t.motivo),
                          'nota', t.nota,
                          'platillo', case when t.producto_id is not null
                                           then t.platillos || ' × ' || coalesce(p.nombre, '—') end,
                          'anoto', privado.quien_anoto(p_restaurante_id, t.anotado_por))
                          order by t.created_at desc, t.id desc)
                 from (select k.* from k
                       where k.grupo = o.grupo and k.tipo = 'merma'
                       order by k.created_at desc, k.id desc
                       limit 3) t
                 left join public.productos p on p.restaurante_id = p_restaurante_id and p.id = t.producto_id)))
             order by o.lugar)
      from o
      where o.lugar <= p_limite), '[]'),
    'resto', (select case when max(o.grupos) > p_limite
                          then jsonb_build_object('renglones', max(o.grupos) - p_limite) end
              from o),
    'mermas_anotadas', (select count(distinct k.clave) from k where k.tipo = 'merma'))
  from r;
$$;


-- ─── ver = gastado ────────────────────────────────────────────────────────────
-- Por ingrediente (o día por día de uno): lo que restaron las ventas, en el día de negocio de su cuenta, como las
-- ventas (privado.cuentas_del_dia). Lo que regresó una cuenta reabierta se descuenta; una cuenta que no restó nada
-- (reabierta y sin volver a cerrar) no cuenta. Por nombre, o por día.

create function privado.inventario_gastado(p_restaurante_id uuid, p_desde date, p_hasta date, p_ingrediente_id bigint,
                                           p_agrupar text, p_limite integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte, privado.dia_de_negocio(zona_horaria, hora_corte) as hoy
    from public.restaurantes
    where id = p_restaurante_id
  ),
  cuentas as (
    select v.id, privado.dia_de_negocio(r.zona, r.corte, v.created_at) as dia
    from r
    cross join lateral privado.cuentas_del_dia(p_restaurante_id, p_desde, p_hasta) v
  ),
  por_cuenta as (
    select m.ingrediente_id, c.id as venta_id, c.dia, -sum(m.cantidad) as cantidad
    from cuentas c
    join public.movimientos_inventario m on m.restaurante_id = p_restaurante_id and m.venta_id = c.id
    where m.tipo in ('venta', 'regreso')
      and (p_ingrediente_id is null or m.ingrediente_id = p_ingrediente_id)
    group by m.ingrediente_id, c.id, c.dia
    having sum(m.cantidad) < 0
  ),
  g as (
    select case when p_agrupar = 'dia' then x.dia::text else x.ingrediente_id::text end as grupo,
           case when p_agrupar = 'dia' then privado.fecha_en_palabras(x.dia, r.hoy) else i.nombre end as etiqueta,
           min(i.unidad) as unidad, min(x.dia) as dia, sum(x.cantidad) as gastado, count(*) as cuentas
    from por_cuenta x
    cross join r
    join public.ingredientes i on i.restaurante_id = p_restaurante_id and i.id = x.ingrediente_id
    group by 1, 2
  ),
  o as (
    select g.*,
           row_number() over (order by case when p_agrupar = 'dia' then g.grupo end, g.etiqueta, g.grupo) as lugar,
           count(*) over () as grupos
    from g
  )
  select jsonb_build_object(
    'renglones', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               case when p_agrupar = 'dia' then 'dia' else 'ingrediente' end, o.etiqueta,
               'fecha', case when p_agrupar = 'dia' then o.dia end,
               'gastado', privado.cantidad_escrita(o.gastado, o.unidad),
               'cuentas', o.cuentas))
             order by o.lugar)
      from o
      where o.lugar <= p_limite), '[]'),
    'resto', (select case when max(o.grupos) > p_limite
                          then jsonb_build_object('renglones', max(o.grupos) - p_limite) end
              from o),
    'cuentas', (select count(distinct x.venta_id) from por_cuenta x));
$$;


-- ─── ver = llego ──────────────────────────────────────────────────────────────
-- Por ingrediente (o día por día de uno): lo anotado en Llegó, con las cajas, en el día de negocio en que se anotó, y
-- las 3 llegadas más recientes con cuándo y quién. Lo deshecho no sale. Por nombre, o por día.

create function privado.inventario_llego(p_restaurante_id uuid, p_desde date, p_hasta date, p_ingrediente_id bigint,
                                         p_agrupar text, p_limite integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select zona_horaria as zona, hora_corte as corte, privado.dia_de_negocio(zona_horaria, hora_corte) as hoy
    from public.restaurantes
    where id = p_restaurante_id
  ),
  k as (
    select m.id, m.ingrediente_id, m.cantidad, m.cajas, m.anotado_por, m.created_at, i.unidad, x.dia,
           case when p_agrupar = 'dia' then x.dia::text else m.ingrediente_id::text end as grupo,
           case when p_agrupar = 'dia' then privado.fecha_en_palabras(x.dia, r.hoy) else i.nombre end as etiqueta
    from r
    join public.movimientos_inventario m on m.restaurante_id = p_restaurante_id
    join public.ingredientes i on i.restaurante_id = p_restaurante_id and i.id = m.ingrediente_id
    cross join lateral (select privado.dia_de_negocio(r.zona, r.corte, m.created_at) as dia) x
    where m.tipo = 'llegada'
      and m.created_at >= privado.inicio_de_dia(r.zona, r.corte, p_desde)
      and m.created_at < privado.inicio_de_dia(r.zona, r.corte, p_hasta + 1)
      and (p_ingrediente_id is null or m.ingrediente_id = p_ingrediente_id)
      and not exists (select 1 from public.movimientos_inventario d
                      where d.restaurante_id = m.restaurante_id and d.deshace_id = m.id)
  ),
  g as (
    select k.grupo, k.etiqueta, min(k.unidad) as unidad, min(k.dia) as dia, sum(k.cantidad) as llego,
           sum(k.cajas) as cajas, count(*) as veces
    from k
    group by k.grupo, k.etiqueta
  ),
  o as (
    select g.*,
           row_number() over (order by case when p_agrupar = 'dia' then g.grupo end, g.etiqueta, g.grupo) as lugar,
           count(*) over () as grupos
    from g
  )
  select jsonb_build_object(
    'renglones', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               case when p_agrupar = 'dia' then 'dia' else 'ingrediente' end, o.etiqueta,
               'fecha', case when p_agrupar = 'dia' then o.dia end,
               'llego', privado.cantidad_escrita(o.llego, o.unidad),
               'cajas', case when o.cajas is not null then o.cajas || case when o.cajas = 1 then ' caja' else ' cajas' end end,
               'veces', o.veces,
               'recientes', (
                 select jsonb_agg(jsonb_build_object(
                          'cuando', privado.cuando_se_anoto(t.created_at, r.zona, r.corte, r.hoy),
                          'cantidad', privado.cantidad_escrita(t.cantidad, o.unidad),
                          'cajas', case when t.cajas is not null
                                        then t.cajas || case when t.cajas = 1 then ' caja' else ' cajas' end end,
                          'anoto', privado.quien_anoto(p_restaurante_id, t.anotado_por))
                          order by t.created_at desc, t.id desc)
                 from (select k.* from k
                       where k.grupo = o.grupo
                       order by k.created_at desc, k.id desc
                       limit 3) t)))
             order by o.lugar)
      from o
      where o.lugar <= p_limite), '[]'),
    'resto', (select case when max(o.grupos) > p_limite
                          then jsonb_build_object('renglones', max(o.grupos) - p_limite) end
              from o))
  from r;
$$;


-- ─── ver = alcanza ────────────────────────────────────────────────────────────
-- Por platillo (sin archivados ni envíos): cuántos alcanzan con lo que queda, por su receta con sus preparaciones
-- (privado.receta_en_ingredientes), y qué ingrediente se acaba primero. Sin las opciones: cada quien elige la suya.
-- Primero los que alcanzan para menos. Sin p_producto_id dice cuántos platillos no tienen receta; con uno sin receta,
-- lo dice en su renglón.

create function privado.inventario_alcanza(p_restaurante_id uuid, p_producto_id bigint, p_limite integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with platillos as (
    select p.id, p.nombre
    from public.productos p
    where p.restaurante_id = p_restaurante_id and p.archivado_at is null and not p.es_envio
      and (p_producto_id is null or p.id = p_producto_id)
  ),
  lleva as (
    select x.producto_id, x.ingrediente_id, sum(x.cantidad) as cantidad
    from privado.receta_en_ingredientes(p_restaurante_id) x
    where x.producto_id in (select pl.id from platillos pl)
    group by x.producto_id, x.ingrediente_id
  ),
  primero as (
    select distinct on (l.producto_id)
           l.producto_id, i.nombre, i.unidad, i.existencia, l.cantidad,
           floor(greatest(i.existencia, 0) / l.cantidad)::bigint as alcanzan
    from lleva l
    join public.ingredientes i on i.restaurante_id = p_restaurante_id and i.id = l.ingrediente_id
    order by l.producto_id, greatest(i.existencia, 0) / l.cantidad, i.nombre, i.id
  ),
  lista as (
    select pl.id, pl.nombre, f.alcanzan, f.nombre as ingrediente, f.unidad, f.existencia, f.cantidad,
           row_number() over (order by f.alcanzan nulls last, pl.nombre, pl.id) as lugar,
           count(*) over () as renglones
    from platillos pl
    left join primero f on f.producto_id = pl.id
    where f.producto_id is not null or p_producto_id is not null
  )
  select jsonb_build_object(
    'platillos', coalesce((
      select jsonb_agg(case when l.alcanzan is null
                            then jsonb_build_object('platillo', l.nombre, 'sin_receta', true)
                            else jsonb_build_object(
                                   'platillo', l.nombre,
                                   'alcanzan', l.alcanzan,
                                   'se_acaba_primero', l.ingrediente,
                                   'queda', privado.cantidad_escrita(l.existencia, l.unidad),
                                   'lleva_cada_uno', privado.cantidad_escrita(l.cantidad, l.unidad)) end
             order by l.lugar)
      from lista l
      where l.lugar <= p_limite), '[]'),
    'resto', (select case when max(l.renglones) > p_limite
                          then jsonb_build_object('platillos', max(l.renglones) - p_limite) end
              from lista l),
    'sin_receta', case when p_producto_id is null
                       then (select count(*) from platillos pl
                             where not exists (select 1 from lleva x where x.producto_id = pl.id)) end);
$$;


-- ─── Herramienta 7 · inventario(ver, …) ───────────────────────────────────────
-- Revisa los argumentos (cada uno va con los `ver` que dice la libreta 1) y llama a la función de su `ver`. Siempre
-- dice si la sucursal no tiene ingredientes, para que el modelo diga que se agregan en Inventario.

create function privado.herramienta_inventario(p_restaurante_id uuid, p_args jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoy date := privado.hoy_de(p_restaurante_id);
  v_ver text;
  v_periodo boolean;
  v_desde date;
  v_hasta date;
  v_ingrediente text;
  v_producto text;
  v_ing_id bigint;
  v_prod_id bigint;
  v_solo boolean;
  v_agrupar text;
  v_limite integer;
  v_lista text;
  v_texto text;
  v_resultado jsonb;
begin
  perform privado.revisar_argumentos('inventario', p_args,
    array['ver', 'desde', 'hasta', 'ingrediente', 'producto', 'solo_lo_que_falta', 'agrupar_por', 'limite']);
  v_ver := privado.arg_opcion(p_args, 'ver', array['queda', 'perdido', 'gastado', 'llego', 'alcanza']);
  v_periodo := v_ver in ('perdido', 'gastado', 'llego');

  if v_periodo then
    v_desde := privado.arg_fecha(p_args, 'desde');
    v_hasta := privado.arg_fecha(p_args, 'hasta');
    perform privado.revisar_rango('desde', v_desde, 'hasta', v_hasta);
  elsif coalesce(p_args -> 'desde', 'null') <> 'null' or coalesce(p_args -> 'hasta', 'null') <> 'null' then
    raise exception 'Con %, inventario no lleva desde ni hasta: es lo de ahora. Llevan fechas: perdido, gastado y llego.',
      v_ver using errcode = '22023';
  end if;

  v_ingrediente := privado.arg_texto(p_args, 'ingrediente');
  if v_ingrediente is not null and v_ver = 'alcanza' then
    raise exception 'alcanza va por platillo: usa producto en vez de ingrediente.' using errcode = '22023';
  end if;
  v_producto := privado.arg_texto(p_args, 'producto');
  if v_producto is not null and v_ver <> 'alcanza' then
    raise exception 'producto solo va con alcanza. Para un ingrediente, usa ingrediente.' using errcode = '22023';
  end if;
  v_solo := coalesce(privado.arg_si_no(p_args, 'solo_lo_que_falta'), false);
  if v_solo and v_ver <> 'queda' then
    raise exception 'solo_lo_que_falta solo va con queda.' using errcode = '22023';
  end if;
  if v_periodo then
    v_agrupar := privado.arg_opcion(p_args, 'agrupar_por', array['ingrediente', 'dia'], 'ingrediente');
    if v_agrupar = 'dia' and v_ingrediente is null then
      raise exception 'agrupar_por dia pide un ingrediente: día por día va de uno solo. Sin ingrediente, agrupar_por ingrediente.'
        using errcode = '22023';
    end if;
  elsif coalesce(p_args -> 'agrupar_por', 'null') <> 'null' then
    raise exception 'agrupar_por solo va con perdido, gastado y llego.' using errcode = '22023';
  end if;
  v_limite := privado.arg_entero(p_args, 'limite', 1, 50, 20);

  if v_ingrediente is not null then
    select b.ingrediente_id, b.nombre into v_ing_id, v_ingrediente
    from privado.buscar_ingrediente(p_restaurante_id, v_ingrediente, v_periodo) b;
  end if;
  if v_producto is not null then
    select b.producto_id, b.nombre into v_prod_id, v_producto
    from privado.buscar_platillo(p_restaurante_id, v_producto) b;
  end if;

  if v_ver = 'queda' then
    v_resultado := privado.inventario_queda(p_restaurante_id, v_ing_id, v_solo, v_limite);
    v_lista := 'ingredientes';
    v_texto := case when v_solo then 'Lo que falta comprar' else 'Lo que queda' end
               || case when v_ingrediente is not null then ' de ' || v_ingrediente
                       when not v_solo then ' hoy' else '' end;
  elsif v_ver = 'alcanza' then
    v_resultado := privado.inventario_alcanza(p_restaurante_id, v_prod_id, v_limite);
    v_lista := 'platillos';
    v_texto := coalesce('Lo que alcanza de ' || v_producto, 'Cuántos platillos alcanzan');
  else
    v_resultado := case v_ver
      when 'perdido' then privado.inventario_perdido(p_restaurante_id, v_desde, v_hasta, v_ing_id, v_agrupar, v_limite)
      when 'gastado' then privado.inventario_gastado(p_restaurante_id, v_desde, v_hasta, v_ing_id, v_agrupar, v_limite)
      else privado.inventario_llego(p_restaurante_id, v_desde, v_hasta, v_ing_id, v_agrupar, v_limite) end;
    v_lista := 'renglones';
    v_texto := case v_ver when 'perdido' then 'Lo que se perdió' when 'gastado' then 'Lo que se gastó' else 'Lo que llegó' end
               || coalesce(' de ' || v_ingrediente, '') || ' ' || privado.periodo(v_desde, v_hasta, v_hoy, 'en')
               || case when v_agrupar = 'dia' then ', día por día' else '' end;
  end if;

  return v_resultado || jsonb_strip_nulls(jsonb_build_object(
    'ver', v_ver, 'desde', v_desde, 'hasta', v_hasta, 'ingrediente', v_ingrediente, 'producto', v_producto,
    'agrupar_por', v_agrupar))
    || jsonb_build_object(
      'sin_datos', v_resultado -> v_lista = '[]'::jsonb,
      'sin_ingredientes', not exists (select 1 from public.ingredientes i
                                      where i.restaurante_id = p_restaurante_id and i.archivado_at is null),
      'leido', privado.leido('datos', v_texto));
end;
$$;


-- ─── agente_herramienta: ahora son 7 ──────────────────────────────────────────
-- La misma puerta (migración agente), con la séptima herramienta.

create or replace function public.agente_herramienta(p_restaurante_id uuid, p_herramienta text, p_argumentos jsonb default '{}')
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
  elsif p_herramienta = 'inventario' then
    return privado.herramienta_inventario(p_restaurante_id, v_args);
  end if;
  raise exception 'No hay una herramienta «%». Las que hay: resumen, ranking, comparar, detalle, proyeccion_mes, cancelaciones_descuentos_propinas, inventario.',
    p_herramienta using errcode = '22023';
end;
$$;


-- ─── contexto_agente: también los ingredientes ────────────────────────────────
-- La de la migración adaptabilidad, con los ingredientes de la sucursal (nombre y unidad, sin archivados), para que el
-- modelo use el nombre exacto; lo que queda de cada uno se pide a inventario.

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
    'ingredientes', (select coalesce(jsonb_agg(jsonb_build_object('nombre', i.nombre, 'unidad', i.unidad)
                                               order by i.nombre, i.id), '[]')
                     from public.ingredientes i
                     where i.restaurante_id = p_restaurante_id and i.archivado_at is null),
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


-- ─── Permisos ─────────────────────────────────────────────────────────────────
-- Lo nuevo es de privado: nadie lo llama desde afuera. agente_herramienta y contexto_agente guardan sus permisos.

revoke execute on function
  privado.cantidad_escrita(numeric, text),
  privado.motivo_escrito(text),
  privado.cuando_se_anoto(timestamptz, text, smallint, date),
  privado.quien_anoto(uuid, bigint),
  privado.arg_si_no(jsonb, text),
  privado.buscar_ingrediente(uuid, text, boolean),
  privado.buscar_platillo(uuid, text),
  privado.inventario_queda(uuid, bigint, boolean, integer),
  privado.inventario_perdido(uuid, date, date, bigint, text, integer),
  privado.inventario_gastado(uuid, date, date, bigint, text, integer),
  privado.inventario_llego(uuid, date, date, bigint, text, integer),
  privado.inventario_alcanza(uuid, bigint, integer),
  privado.herramienta_inventario(uuid, jsonb)
from public, anon, authenticated, service_role;
