-- Parte 7b-3: el sobre de los anuncios (decidido el 4 de noviembre de 2026). No hay tablas nuevas:
-- cambia cómo se reparte el tope y lo que lo lee. Hasta hoy los anuncios gastaban de la parte del
-- agente; desde hoy cada uno de los tres gasta y se pausa por su lado.
--
-- Con el tope de 10 dólares: 2 para el asistente del menú, 4 para los anuncios y 4 para el agente,
-- y 40 anuncios al mes (un post y su historia ya son 2). Con un tope menor, en la misma proporción.


-- ─── El reparto ───────────────────────────────────────────────────────────────

-- La parte de cada sobre con el tope de hoy: una quinta parte para el menú, dos para los anuncios y
-- lo demás para el agente, así que las tres suman el tope exacto (con 10 dólares, 2, 4 y 4; con 7.77,
-- 1.55, 3.11 y 3.11). Lo que un sobre no gasta no pasa a otro ni al mes siguiente.
create or replace function privado.parte_del_tope(p_tope numeric, p_sobre text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select (case p_sobre
            when 'menu' then round(p_tope / 5, 2)
            when 'anuncios' then round(p_tope * 2 / 5, 2)
            when 'agente' then p_tope - round(p_tope / 5, 2) - round(p_tope * 2 / 5, 2)
          end)::numeric(10,2);
$$;

-- Cuántos anuncios caben al mes con un tope. Aquí viven los 0.10 dólares que se apartan por cada
-- uno (lo que se calcula para el más caro, un post con combo de 5) y el máximo de 40: si las pruebas
-- de los demás estilos dicen otra cosa, solo se cambia esta función.
create function privado.anuncios_que_caben(p_tope numeric)
returns integer
language sql
immutable
set search_path = ''
as $$
  select least(40, floor(privado.parte_del_tope(p_tope, 'anuncios') / 0.10))::integer;
$$;

revoke execute on function privado.anuncios_que_caben(numeric)
from public, anon, authenticated, service_role;

-- Si un sobre todavía puede gastar este mes, como en la 6c, ya con los tres por su lado. Un tope tan
-- chico que no cabe ni un anuncio deja a los anuncios «sin IA», y el menú y el agente usan lo suyo.
create or replace function privado.saldo_ia(p_restaurante_id uuid, p_sobre text)
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
    select case when p_sobre = 'anuncios' and privado.anuncios_que_caben(r.tope_ia_usd_mes) = 0 then 0
                else privado.parte_del_tope(r.tope_ia_usd_mes, p_sobre) end as parte,
           (case p_sobre when 'menu' then coalesce(u.costo_menu_usd, 0)
                         when 'anuncios' then coalesce(u.costo_anuncios_usd, 0)
                         else coalesce(u.costo_agente_usd, 0) end)::numeric(10,4) as gastado
  ) x
  where r.id = p_restaurante_id;
$$;

-- Los anuncios del mes: los que salieron (anuncios de uso_ia, que nunca resta) más el que se está
-- haciendo, contra los que caben con su tope. Si le bajan el tope a medio mes y ya hizo más, le
-- quedan 0 y no se borra nada.
create or replace function privado.anuncios_del_mes(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'de', privado.anuncios_que_caben(r.tope_ia_usd_mes),
    'quedan', greatest(privado.anuncios_que_caben(r.tope_ia_usd_mes) - coalesce(u.anuncios, 0)
                          - (exists (select 1 from public.anuncios a
                                     where a.restaurante_id = r.id and a.estado = 'haciendo'))::integer, 0),
    'vuelve', (privado.mes_ia(r.zona_horaria) + interval '1 month')::date
  )
  from public.restaurantes r
  left join public.uso_ia u on u.restaurante_id = r.id and u.mes = privado.mes_ia(r.zona_horaria)
  where r.id = p_restaurante_id;
$$;


-- ─── Lo que lo lee ────────────────────────────────────────────────────────────

-- Igual que en la 7b-1. Solo cambia el motivo cuando ya hizo los que le caben: «cupo», porque ya no
-- son siempre 20.
create or replace function public.apartar_anuncio(
  p_restaurante_id uuid,
  p_estilo_id bigint,
  p_formato text,
  p_productos bigint[],
  p_mensaje text,
  p_color text,
  p_con_color boolean,
  p_palabras jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mensaje text := nullif(btrim(p_mensaje), '');
  v_color text := upper(nullif(btrim(p_color), ''));
  v_palabras jsonb := nullif(p_palabras, '{}'::jsonb);
  v_revision jsonb;
  v_cuenta jsonb;
  v_id bigint;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede crear anuncios' using errcode = '42501';
  end if;

  if p_formato is null or p_formato not in ('post', 'historia', 'cartel') then
    raise exception 'El formato es post, historia o cartel' using errcode = '22023';
  end if;
  if char_length(v_mensaje) > 200 then
    raise exception 'El mensaje puede tener hasta 200 letras' using errcode = '22023';
  end if;
  if p_con_color is null then
    raise exception 'Falta decir si el estilo lleva color' using errcode = '22023';
  end if;
  if not p_con_color and v_color is not null then
    raise exception 'Este estilo no lleva color' using errcode = '22023';
  end if;
  if v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'El color va como #RRGGBB' using errcode = '22023';
  end if;
  if v_palabras is not null and jsonb_typeof(v_palabras) <> 'object' then
    raise exception 'Las palabras van en un objeto' using errcode = '22023';
  end if;

  -- Dos pestañas al mismo tiempo no apartan dos lugares.
  perform pg_advisory_xact_lock(hashtextextended('anuncios:' || p_restaurante_id::text, 0));

  v_revision := privado.revisar_anuncio(p_restaurante_id, p_estilo_id, p_productos);
  if not (v_revision ->> 'ok')::boolean then
    return v_revision;
  end if;

  perform privado.soltar_atorados(p_restaurante_id);
  if exists (select 1 from public.anuncios where restaurante_id = p_restaurante_id and estado = 'haciendo') then
    return jsonb_build_object('ok', false, 'motivo', 'haciendo');
  end if;
  v_cuenta := privado.anuncios_del_mes(p_restaurante_id);
  if (v_cuenta ->> 'quedan')::integer = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'cupo', 'vuelve', v_cuenta -> 'vuelve');
  end if;

  insert into public.anuncios (restaurante_id, estilo_id, formato, productos, mensaje, color, palabras, hecho_por)
  select p_restaurante_id, p_estilo_id, p_formato,
         (select jsonb_agg(jsonb_build_object('id', x -> 'id', 'nombre', x -> 'nombre') order by n)
          from jsonb_array_elements(v_revision -> 'productos') with ordinality as e (x, n)),
         v_mensaje,
         case when p_con_color then coalesce(v_color, r.menu_color) end,
         v_palabras,
         privado.mi_miembro(p_restaurante_id, array['gerente'])
  from public.restaurantes r
  where r.id = p_restaurante_id
  returning id into v_id;

  return jsonb_build_object('ok', true, 'anuncio_id', v_id);
end;
$$;

-- La ventana «Tope de IA»: cada sobre con su renglón. El del agente ya solo suma lo suyo, y el de los
-- anuncios dice cuántos caben con este tope.
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
