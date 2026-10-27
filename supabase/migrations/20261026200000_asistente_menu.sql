-- Menú en línea, parte 6c: el asistente del menú (libreta 6; libreta 3, «El gasto de IA»; libreta
-- 2, Diccionario de datos, rev 104; las respuestas de la 6c en planes/trabajo/6c; maqueta
-- 2UPwZw31WrcYRZkH8jaT1Y).
--
-- La señora Ramírez le pregunta al asistente del menú. Nadie del menú tiene sesión: el Worker,
-- después de la revisión invisible de Cloudflare, llama a preguntar_al_asistente con la llave
-- secreta y las marcas del celular y de la conexión. Postgres revisa que el asistente tenga con
-- qué contestar y los límites (20 preguntas por hora desde cada celular y 60 desde cada conexión,
-- a cada restaurante), cuenta la pregunta y le da al Worker el menú que ve ella. El Worker llama a
-- OpenAI una vez y anota los tokens con anotar_uso_ia; Postgres saca el costo y lo suma al sobre
-- del menú. Nunca se guarda el texto de una pregunta ni de su respuesta.
--
-- Los sobres: el del menú es la quinta parte del tope, y el agente del panel tiene lo demás (con
-- 10 dólares, 2 y 8). Hasta hoy el agente gastaba el tope completo. Cada sobre se pausa solo,
-- hasta el día 1, al gastar lo suyo.


-- ─── uso_ia: el sobre del menú ────────────────────────────────────────────────

alter table public.uso_ia
  add column consultas_menu integer not null default 0
    constraint uso_ia_consultas_menu_validas check (consultas_menu >= 0),
  add column costo_menu_usd numeric(10,4) not null default 0
    constraint uso_ia_costo_menu_valido check (costo_menu_usd >= 0);

-- La suma de los tres sobres. Una columna generada no cambia de fórmula en todas las versiones de
-- Postgres: se quita y se vuelve a poner.
alter table public.uso_ia drop column costo_usd;
alter table public.uso_ia
  add column costo_usd numeric(10,4) generated always as (costo_agente_usd + costo_anuncios_usd + costo_menu_usd) stored;


-- ─── preguntas_menu ───────────────────────────────────────────────────────────
-- Una fila por pregunta, solo para contar el límite. No guarda la pregunta, ni la respuesta, ni la
-- conexión (solo su marca). Las filas viven una hora: pg_cron borra las viejas. Nadie con sesión
-- la lee ni la escribe; solo preguntar_al_asistente.

create table public.preguntas_menu (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  marca_celular text not null
    constraint preguntas_menu_marca_celular check (marca_celular ~ '^[0-9a-f]{64}$'),
  marca_conexion text not null
    constraint preguntas_menu_marca_conexion check (marca_conexion ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

-- Los límites buscan por marca; la limpieza, por hora.
create index preguntas_menu_celular_idx on public.preguntas_menu (restaurante_id, marca_celular, created_at);
create index preguntas_menu_conexion_idx on public.preguntas_menu (restaurante_id, marca_conexion, created_at);
create index preguntas_menu_created_at_idx on public.preguntas_menu (created_at);

alter table public.preguntas_menu enable row level security;

revoke all on table public.preguntas_menu from anon, authenticated, service_role;
revoke all on sequence public.preguntas_menu_id_seq from anon, authenticated, service_role;


-- ─── Lo que se cuenta una sola vez ────────────────────────────────────────────

-- La parte de cada sobre con el tope de hoy: la del menú es la quinta parte, redondeada a
-- centavos, y el agente del panel tiene lo demás, así que las dos suman el tope exacto (con 10
-- dólares, 2 y 8; con 7.77, 1.55 y 6.22). Los flyers todavía no tienen la suya.
create function privado.parte_del_tope(p_tope numeric, p_sobre text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select (case p_sobre
            when 'menu' then round(p_tope / 5, 2)
            when 'agente' then p_tope - round(p_tope / 5, 2)
          end)::numeric(10,2);
$$;

-- Si un sobre todavía puede gastar este mes: su parte, lo gastado, y si no puede, por qué. Un
-- sobre que vale 0 es «sin IA» (con tope 0, los dos); al gastar su parte llega a su «limite» hasta
-- el día 1. Reemplaza a privado.saldo_agente.
create function privado.saldo_ia(p_restaurante_id uuid, p_sobre text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'tope', x.parte,
    'gastado', x.gastado,
    'puede', x.parte > 0 and x.gastado < x.parte,
    'motivo', case when x.parte = 0 then 'sin_ia'
                   when x.gastado >= x.parte then 'limite' end,
    'con_distribuidor', r.distribuidor_id is not null,
    'vuelve', (privado.mes_ia(r.zona_horaria) + interval '1 month')::date
  )
  from public.restaurantes r
  left join public.uso_ia u on u.restaurante_id = r.id and u.mes = privado.mes_ia(r.zona_horaria)
  cross join lateral (
    select privado.parte_del_tope(r.tope_ia_usd_mes, p_sobre) as parte,
           (case p_sobre when 'menu' then coalesce(u.costo_menu_usd, 0)
                         else coalesce(u.costo_agente_usd, 0) end)::numeric(10,4) as gastado
  ) x
  where r.id = p_restaurante_id;
$$;

-- La limpieza de cada hora: el límite solo mira la última hora. Regresa cuántas borró.
create function privado.borrar_preguntas_viejas()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_borradas integer;
begin
  delete from public.preguntas_menu where created_at <= now() - interval '1 hour';
  get diagnostics v_borradas = row_count;
  return v_borradas;
end;
$$;

revoke execute on function
  privado.parte_del_tope(numeric, text),
  privado.saldo_ia(uuid, text),
  privado.borrar_preguntas_viejas()
from public, anon, authenticated, service_role;


-- ─── El agente del panel, con su parte ────────────────────────────────────────

-- Como en la migración del agente, ahora con su parte del tope.
create or replace function public.estado_ia(p_restaurante_id uuid)
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
  v_saldo := privado.saldo_ia(p_restaurante_id, 'agente');
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

-- Una pregunta del agente (con los tokens de todas sus rondas), un saludo, o una pregunta del
-- menú. Si OpenAI cobró una pregunta del menú pero no mandó nada que enseñar, el Worker la anota
-- como menu_sin_respuesta: suma su costo y no cuenta en consultas_menu, que solo lleva las que
-- contestó. Regresa el costo y si ese sobre todavía puede gastar.
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
begin
  if p_uso is null or p_uso not in ('pregunta', 'saludo', 'menu', 'menu_sin_respuesta') then
    raise exception 'El uso de IA es pregunta, saludo, menu o menu_sin_respuesta' using errcode = '22023';
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
    restaurante_id, mes, consultas_agente, saludos, costo_agente_usd, consultas_menu, costo_menu_usd
  ) values (
    p_restaurante_id, privado.mes_ia(v_zona),
    case when p_uso = 'pregunta' then 1 else 0 end,
    case when p_uso = 'saludo' then 1 else 0 end,
    case when v_menu then 0 else v_costo end,
    case when p_uso = 'menu' then 1 else 0 end,
    case when v_menu then v_costo else 0 end
  )
  on conflict (restaurante_id, mes) do update
  set consultas_agente = u.consultas_agente + excluded.consultas_agente,
      saludos = u.saludos + excluded.saludos,
      costo_agente_usd = u.costo_agente_usd + excluded.costo_agente_usd,
      consultas_menu = u.consultas_menu + excluded.consultas_menu,
      costo_menu_usd = u.costo_menu_usd + excluded.costo_menu_usd;

  return jsonb_build_object(
    'costo', v_costo,
    'puede', privado.saldo_ia(p_restaurante_id, case when v_menu then 'menu' else 'agente' end) -> 'puede');
end;
$$;

drop function privado.saldo_agente(uuid);

-- La ventana «Tope de IA»: el mes, el tope y lo gastado en total, y cada sobre en su renglón, con
-- su parte, lo gastado, cuántas preguntas y si llegó a lo suyo; y quién paga.
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
    'sobre_menu', privado.parte_del_tope(r.tope_ia_usd_mes, 'menu'),
    'gastado_menu', coalesce(u.costo_menu_usd, 0)::numeric(10,4),
    'consultas_menu', coalesce(u.consultas_menu, 0),
    'menu_en_limite', (privado.saldo_ia(r.id, 'menu') ->> 'motivo') is not distinct from 'limite',
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


-- ─── El menú que ve la clienta ────────────────────────────────────────────────
-- Como en la 6b, y además si el asistente contesta ahora, sin números: sin IA, la burbuja se
-- queda y al abrirla dice que por ahora no puede.

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


-- ─── La pregunta (solo el Worker) ─────────────────────────────────────────────

-- La señora Ramírez toca la flecha de enviar: el Worker llama aquí con la llave secreta, después
-- de la revisión de Cloudflare, con las marcas del celular y de la conexión ya hechas (las mismas
-- de los pedidos). La pregunta nunca llega: Postgres solo decide si se puede.
--
-- Regresa {ok: true, restaurante_id, menu} si se puede, y ya la contó para el límite (si OpenAI
-- falla, igual contó); menu es lo mismo que ve ella (menu_publico), para el prompt. Si no, {ok:
-- false, motivo}: 'sin_ia' (el sobre del menú está en 0 o ya se gastó; un slug que no existe o
-- una licencia que no funciona dan lo mismo), 'limite_celular' o 'limite_conexion'. Los avisos
-- los escribe el menú, en español o en inglés; sin IA o en el límite, la pregunta no cuenta.
create function public.preguntar_al_asistente(
  p_slug text,
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
begin
  select * into v_r
  from public.restaurantes r
  where r.slug = lower(btrim(p_slug))
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sin_ia');
  end if;
  if coalesce(p_marca_celular, '') !~ '^[0-9a-f]{64}$' or coalesce(p_marca_conexion, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'Faltan las marcas de la pregunta' using errcode = '22023';
  end if;
  if not (privado.saldo_ia(v_r.id, 'menu') ->> 'puede')::boolean then
    return jsonb_build_object('ok', false, 'motivo', 'sin_ia');
  end if;

  -- Una pregunta a la vez en cada restaurante: dos al mismo tiempo no pasan juntas el límite.
  perform pg_advisory_xact_lock(hashtextextended('preguntas:' || v_r.id::text, 0));
  if (select count(*) from public.preguntas_menu
      where restaurante_id = v_r.id and marca_celular = p_marca_celular
        and created_at > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('ok', false, 'motivo', 'limite_celular');
  end if;
  if (select count(*) from public.preguntas_menu
      where restaurante_id = v_r.id and marca_conexion = p_marca_conexion
        and created_at > now() - interval '1 hour') >= 60 then
    return jsonb_build_object('ok', false, 'motivo', 'limite_conexion');
  end if;

  insert into public.preguntas_menu (restaurante_id, marca_celular, marca_conexion)
  values (v_r.id, p_marca_celular, p_marca_conexion);

  return jsonb_build_object('ok', true, 'restaurante_id', v_r.id, 'menu', public.menu_publico(v_r.slug));
end;
$$;

revoke execute on function public.preguntar_al_asistente(text, text, text) from public, anon, authenticated;
grant execute on function public.preguntar_al_asistente(text, text, text) to service_role;


-- ─── Tu menú en línea: los avisos de Don Chuy ─────────────────────────────────
-- Como en la 6b, y además lo del asistente, sin números: si contesta y, si no, por qué (sin_ia o
-- limite), si el restaurante tiene distribuidor y cuándo vuelve.

create or replace function public.estado_menu_en_linea(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_saldo jsonb;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante ve su menú en línea así' using errcode = '42501';
  end if;
  v_saldo := privado.saldo_ia(p_restaurante_id, 'menu');

  return jsonb_build_object(
    'estado', privado.horario_ahora(p_restaurante_id),
    'a_la_vista', (select count(*) from privado.productos_a_la_vista(p_restaurante_id)),
    'productos', (select count(*)
                  from public.productos p
                  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
                  where p.restaurante_id = p_restaurante_id
                    and not p.es_envio
                    and p.archivado_at is null
                    and c.archivado_at is null),
    'asistente', case when (v_saldo ->> 'puede')::boolean then jsonb_build_object('puede', true)
                      else jsonb_build_object(
                        'puede', false,
                        'motivo', v_saldo -> 'motivo',
                        'con_distribuidor', v_saldo -> 'con_distribuidor',
                        'vuelve', v_saldo -> 'vuelve') end);
end;
$$;


-- ─── La limpieza con pg_cron ──────────────────────────────────────────────────
-- Cada hora en punto, aparte del cierre de los pedidos. Programarlo otra vez con el mismo nombre
-- lo reemplaza.

select cron.schedule('borrar-preguntas-del-menu', '0 * * * *', 'select privado.borrar_preguntas_viejas()');
