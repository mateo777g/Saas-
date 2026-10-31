-- Creación de contenido, parte 7b-1: hacer el anuncio (libreta 7, lo decidido el 28 y el 29 de
-- octubre de 2026; libreta 3, «El gasto de IA»; libreta 2, Diccionario de datos; las respuestas de
-- la 7b en planes/trabajo/7b; maqueta JQBw2yGFSiky1x9twUyYbe).
--
-- Don Chuy pica sus productos, elige el estilo y el formato, y el Worker le hace su anuncio en
-- segundo plano. Primero aparta su lugar con la sesión de Don Chuy (apartar_anuncio): el renglón
-- nace «haciendo», uno a la vez por restaurante, y ya cuenta en sus 20 del mes. Luego el trabajo en
-- segundo plano lee lo apartado con la llave secreta (datos_del_anuncio), llama a OpenAI, guarda el
-- JPG en R2 y lo termina (terminar_anuncio) o lo falla (fallar_anuncio). Postgres saca el costo de
-- la imagen con precios_ia y lo suma al sobre de los anuncios; el paso de texto que escoge las
-- palabras se anota con anotar_uso_ia. Uno que pasa 15 minutos «haciendo» cuenta como que no salió.
--
-- Mientras no exista el sobre de los anuncios (parte 7b-3), los anuncios gastan de la parte del
-- agente: el agente y los anuncios se pausan juntos. Mi biblioteca (verla, borrar y el borrado de
-- los 30 días) llega con la parte 7b-2.


-- ─── precios_ia: el modelo de imagen ──────────────────────────────────────────
-- Lo que dice la página de precios de OpenAI el 30 de octubre de 2026 (modo normal, por millón de
-- tokens): texto de entrada 5.00, imagen de entrada 8.00 e imagen de salida 30.00. La página no le
-- pone precio a escribir en caché, así que se cobra como la entrada. Su caché solo vale en la API de
-- Responses y el Worker usa la de imágenes, que no la reporta: la de texto queda escrita porque la
-- columna es obligatoria.

alter table public.precios_ia
  add column entrada_imagen_usd_millon numeric(10,4)
    constraint precios_ia_entrada_imagen_valida check (entrada_imagen_usd_millon >= 0);

insert into public.precios_ia (
  modelo, entrada_usd_millon, entrada_cache_usd_millon, escritura_cache_usd_millon, salida_usd_millon,
  entrada_imagen_usd_millon
) values
  ('gpt-image-2.5-sunburst', 5.00, 1.25, 5.00, 30.00, 8.00);


-- ─── anuncios ─────────────────────────────────────────────────────────────────
-- Los productos van dentro del anuncio con su id y su nombre, sin llave foránea: borrar, archivar o
-- renombrar un producto en Mi menú no toca sus anuncios. Cada estado trae lo suyo y nada más.

-- La forma de los productos de un anuncio: de 1 a 5, cada uno con su id y su nombre, sin repetir.
create function privado.son_productos_de_anuncio(p_productos jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_productos) is distinct from 'array' then false
    when jsonb_array_length(p_productos) not between 1 and 5 then false
    else not exists (
           select 1
           from jsonb_array_elements(p_productos) e
           where jsonb_typeof(e) <> 'object'
              or jsonb_typeof(e -> 'id') is distinct from 'number'
              or (e ->> 'id') !~ '^[1-9][0-9]{0,17}$'
              or jsonb_typeof(e -> 'nombre') is distinct from 'string'
              or btrim(e ->> 'nombre') = ''
         )
         and (select count(distinct e -> 'id') from jsonb_array_elements(p_productos) e)
             = jsonb_array_length(p_productos)
  end;
$$;

create table public.anuncios (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  estilo_id bigint not null references public.estilos (id),
  formato text not null
    constraint anuncios_formato_lista check (formato in ('post', 'historia', 'cartel')),
  productos jsonb not null
    constraint anuncios_productos_forma check (privado.son_productos_de_anuncio(productos)),
  mensaje text
    constraint anuncios_mensaje_largo check (btrim(mensaje) <> '' and char_length(mensaje) <= 200),
  color text
    constraint anuncios_color_formato check (color ~ '^#[0-9A-F]{6}$'),
  palabras jsonb
    constraint anuncios_palabras_objeto check (jsonb_typeof(palabras) = 'object'),
  estado text not null default 'haciendo'
    constraint anuncios_estado_lista check (estado in ('haciendo', 'listo', 'fallo')),
  motivo text
    constraint anuncios_motivo_lista check (motivo in ('rechazado', 'no_salio')),
  ruta text unique
    constraint anuncios_ruta_formato
    check (ruta ~ ('^restaurantes/' || restaurante_id::text || '/biblioteca/[0-9a-f]{32}\.jpg$')),
  costo_usd numeric(10,4) not null default 0
    constraint anuncios_costo_valido check (costo_usd >= 0),
  hecho_por bigint not null,
  terminado_at timestamptz,
  vence date,
  visto_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, hecho_por) references public.miembros (restaurante_id, id),
  -- «haciendo» aparta su lugar y nada más; «listo» ya está en R2; «fallo» trae por qué no salió.
  -- Los dos terminados llevan cuándo y hasta qué día se ven.
  constraint anuncios_segun_estado check (
    case estado
      when 'haciendo' then
        motivo is null and ruta is null and terminado_at is null and vence is null and visto_at is null
      when 'listo' then
        motivo is null and ruta is not null and terminado_at is not null and vence is not null
      else
        motivo is not null and ruta is null and terminado_at is not null and vence is not null
    end
  )
);

-- Un anuncio a la vez por restaurante: su lugar se aparta con el renglón «haciendo».
create unique index anuncios_uno_haciendo on public.anuncios (restaurante_id) where estado = 'haciendo';
-- «Resultado» busca el último de cada restaurante; el borrado de la 7b-2, por día.
create index anuncios_restaurante_idx on public.anuncios (restaurante_id, created_at);
create index anuncios_vence_idx on public.anuncios (vence);
create index anuncios_estilo_idx on public.anuncios (estilo_id);
create index anuncios_hecho_por_idx on public.anuncios (restaurante_id, hecho_por);

create trigger anuncios_updated_at
before update on public.anuncios
for each row execute function privado.set_updated_at();


-- ─── Permisos, RLS y tiempo real ──────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto, también para el Worker. Nadie la escribe directo. El
-- gerente lee los renglones de sus restaurantes que funcionan, todo menos el costo, solo para que
-- realtime le avise cuando su anuncio termina; lo que enseña lo lee con crear_contenido.

alter table public.anuncios enable row level security;

revoke all on table public.anuncios from anon, authenticated, service_role;
revoke all on sequence public.anuncios_id_seq from anon, authenticated, service_role;

grant select (
  id, restaurante_id, estilo_id, formato, productos, mensaje, color, palabras, estado, motivo, ruta,
  hecho_por, terminado_at, vence, visto_at, created_at, updated_at
) on public.anuncios to authenticated;

create policy "El gerente lee los anuncios de sus restaurantes que funcionan"
on public.anuncios for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()));

-- La publicación solo existe en Supabase.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.anuncios;
  end if;
end;
$$;


-- ─── Lo que se cuenta una sola vez ────────────────────────────────────────────

-- El costo de una imagen con los tokens que reporta la API de imágenes: los de texto del prompt, los
-- de imagen que recibe (las fotos de referencia) y los que entrega (el anuncio). Sin caché, porque
-- esa API no la reporta. Se redondea a 4 decimales, como privado.costo_ia; un modelo sin precio de
-- imagen da null.
create function privado.costo_imagen(
  p_modelo text,
  p_entrada_texto bigint,
  p_entrada_imagen bigint,
  p_salida bigint
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round((
      p_entrada_texto * p.entrada_usd_millon
      + p_entrada_imagen * p.entrada_imagen_usd_millon
      + p_salida * p.salida_usd_millon
    ) / 1000000, 4)::numeric(10,4)
  from public.precios_ia p
  where p.modelo = p_modelo
    and p.entrada_imagen_usd_millon is not null;
$$;

-- Si un sobre todavía puede gastar este mes, como en la 6c. Hasta la 7b-3 los anuncios no tienen
-- sobre: gastan de la parte del agente, así que «agente» y «anuncios» son la misma cuenta (la parte
-- del agente contra lo que gastaron los dos) y se pausan juntos.
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
    select privado.parte_del_tope(r.tope_ia_usd_mes, case p_sobre when 'menu' then 'menu' else 'agente' end) as parte,
           (case p_sobre when 'menu' then coalesce(u.costo_menu_usd, 0)
                         else coalesce(u.costo_agente_usd, 0) + coalesce(u.costo_anuncios_usd, 0) end)::numeric(10,4) as gastado
  ) x
  where r.id = p_restaurante_id;
$$;

-- Los 20 del mes: los que salieron este mes (anuncios de uso_ia, que nunca resta) más el que se
-- está haciendo. Aquí vive el 20; la 7b-3 le suma lo que cabe en el sobre.
create function privado.anuncios_del_mes(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'de', 20,
    'quedan', greatest(20 - coalesce(u.anuncios, 0)
                          - (exists (select 1 from public.anuncios a
                                     where a.restaurante_id = r.id and a.estado = 'haciendo'))::integer, 0),
    'vuelve', (privado.mes_ia(r.zona_horaria) + interval '1 month')::date
  )
  from public.restaurantes r
  left join public.uso_ia u on u.restaurante_id = r.id and u.mes = privado.mes_ia(r.zona_horaria)
  where r.id = p_restaurante_id;
$$;

-- Suelta el lugar de uno atorado: el que lleva 15 minutos «haciendo» cuenta como que no salió, con
-- su día de vencer como cualquier otro. Se llama cada vez que alguien mira los anuncios de un
-- restaurante. Regresa cuántos soltó.
create function privado.soltar_atorados(p_restaurante_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_soltados integer;
begin
  update public.anuncios a
  set estado = 'fallo',
      motivo = 'no_salio',
      terminado_at = now(),
      vence = privado.dia_local(r.zona_horaria) + 29
  from public.restaurantes r
  where r.id = a.restaurante_id
    and a.restaurante_id = p_restaurante_id
    and a.estado = 'haciendo'
    and a.created_at <= now() - interval '15 minutes';
  get diagnostics v_soltados = row_count;
  return v_soltados;
end;
$$;

-- Suma al sobre de los anuncios del mes de hoy: los que salieron y lo que costaron.
create function privado.sumar_a_anuncios(p_restaurante_id uuid, p_anuncios integer, p_costo numeric)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.uso_ia as u (restaurante_id, mes, anuncios, costo_anuncios_usd)
  select r.id, privado.mes_ia(r.zona_horaria), p_anuncios, p_costo
  from public.restaurantes r
  where r.id = p_restaurante_id
  on conflict (restaurante_id, mes) do update
  set anuncios = u.anuncios + excluded.anuncios,
      costo_anuncios_usd = u.costo_anuncios_usd + excluded.costo_anuncios_usd;
$$;

-- El teléfono como en el menú en línea: «551 234 5678».
create function privado.telefono_escrito(p_telefono text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(p_telefono, '^([0-9]{3})([0-9]{3})([0-9]{4})$', '\1 \2 \3');
$$;

-- Los días de un horario: tres o más seguidos con «a» («Lun a sáb»), sueltos con comas y el último
-- con «y» («Lun, mié y vie», «Sáb y dom»), los 7 «Todos los días». La semana empieza el lunes.
create function privado.dias_escritos(p_dias smallint[])
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_nombres text[] := array['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  v_partes text[] := '{}';
  v_desde integer;
  v_hasta integer;
  v_dia integer;
  v_texto text;
begin
  if (select count(distinct d) from unnest(p_dias) d) = 7 then
    return 'Todos los días';
  end if;

  -- Cada tramo de días seguidos: de tres o más, «lun a mié»; de uno o dos, cada día suelto. El
  -- null del final cierra el último tramo.
  for v_dia in select x.d from (select distinct d from unnest(p_dias) d) x
               union all select null
               order by 1 nulls last loop
    if v_dia is not null and v_desde is null then
      v_desde := v_dia;
      v_hasta := v_dia;
    elsif v_dia is not null and v_dia = v_hasta + 1 then
      v_hasta := v_dia;
    else
      if v_hasta - v_desde >= 2 then
        v_partes := v_partes || (v_nombres[v_desde] || ' a ' || v_nombres[v_hasta]);
      else
        v_partes := v_partes || v_nombres[v_desde:v_hasta];
      end if;
      v_desde := v_dia;
      v_hasta := v_dia;
    end if;
  end loop;

  v_texto := case cardinality(v_partes)
               when 1 then v_partes[1]
               else array_to_string(v_partes[1:cardinality(v_partes) - 1], ', ') || ' y '
                    || v_partes[cardinality(v_partes)]
             end;
  return upper(left(v_texto, 1)) || substr(v_texto, 2);
end;
$$;

-- El horario del recuadro de Cuadros: junta los días con las mismas horas, en uno o dos renglones,
-- primero el que empieza más cerca del lunes, con las horas como en el menú («Lun a sáb 9:00 a
-- 23:00»). Sin horario, o con más de dos horarios distintos, null: el recuadro no lo lleva.
create function privado.horario_de_cuadros(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(*) between 1 and 2 then
           jsonb_agg(privado.dias_escritos(g.dias) || ' ' || to_char(g.abre, 'FMHH24:MI') || ' a '
                     || to_char(g.cierra, 'FMHH24:MI') order by g.primero)
         end
  from (
    select h.abre, h.cierra, array_agg(h.dia order by h.dia) as dias, min(h.dia) as primero
    from public.horarios h
    where h.restaurante_id = p_restaurante_id
    group by h.abre, h.cierra
  ) g;
$$;

-- El restaurante como va en el anuncio: su nombre, el teléfono escrito, su dirección, su color de
-- marca (el de «Tu menú en línea») y el horario de Cuadros. Un dato vacío va vacío.
create function privado.restaurante_del_anuncio(p_restaurante_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'nombre', r.nombre,
    'telefono', privado.telefono_escrito(r.telefono),
    'direccion', r.direccion,
    'color', r.menu_color,
    'horario', privado.horario_de_cuadros(r.id)
  )
  from public.restaurantes r
  where r.id = p_restaurante_id;
$$;

-- Lo que revisan el paso de texto y apartar_anuncio, con la sesión de Don Chuy: que sea gerente con
-- la licencia al día, que lleve de 1 a 5 productos que sigan en Mi menú, que el estilo le salga hoy
-- y que la IA pueda. Los datos mal armados son errores; lo que la app le explica a Don Chuy regresa
-- {ok: false, motivo}. Si todo está bien: la clave del estilo, los productos en el orden en que los
-- picó (con el precio como va en el anuncio) y el restaurante.
create function privado.revisar_anuncio(p_restaurante_id uuid, p_estilo_id bigint, p_productos bigint[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoy date;
  v_clave text;
  v_productos jsonb;
  v_saldo jsonb;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede crear anuncios' using errcode = '42501';
  end if;
  if p_productos is null or cardinality(p_productos) not between 1 and 5 or array_position(p_productos, null) is not null then
    raise exception 'Un anuncio lleva de 1 a 5 productos' using errcode = '22023';
  end if;
  if (select count(distinct x) from unnest(p_productos) x) <> cardinality(p_productos) then
    raise exception 'Cada producto va una sola vez en el anuncio' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'nombre', p.nombre,
           'descripcion', p.descripcion,
           'imagen_ruta', p.imagen_ruta,
           'precio', p.precio,
           'precio_escrito', privado.dinero(p.precio)
         ) order by x.lugar), '[]')
  into v_productos
  from unnest(p_productos) with ordinality as x (id, lugar)
  join public.productos p on p.restaurante_id = p_restaurante_id and p.id = x.id
  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
  where p.archivado_at is null
    and c.archivado_at is null
    and not p.es_envio;
  if jsonb_array_length(v_productos) <> cardinality(p_productos) then
    raise exception 'Uno de tus productos ya no está en tu menú.' using errcode = '22023';
  end if;

  select privado.dia_local(r.zona_horaria) into v_hoy from public.restaurantes r where r.id = p_restaurante_id;
  select e.clave into v_clave
  from public.estilos e
  where e.id = p_estilo_id
    and e.id in (select privado.estilos_a_la_vista(v_hoy));
  if v_clave is null then
    return jsonb_build_object('ok', false, 'motivo', 'estilo');
  end if;

  v_saldo := privado.saldo_ia(p_restaurante_id, 'anuncios');
  if not (v_saldo ->> 'puede')::boolean then
    return jsonb_build_object(
      'ok', false,
      'motivo', v_saldo -> 'motivo',
      'con_distribuidor', v_saldo -> 'con_distribuidor',
      'vuelve', v_saldo -> 'vuelve'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'estilo', v_clave,
    'productos', v_productos,
    'restaurante', privado.restaurante_del_anuncio(p_restaurante_id)
  );
end;
$$;

revoke execute on function
  privado.son_productos_de_anuncio(jsonb),
  privado.costo_imagen(text, bigint, bigint, bigint),
  privado.anuncios_del_mes(uuid),
  privado.soltar_atorados(uuid),
  privado.sumar_a_anuncios(uuid, integer, numeric),
  privado.telefono_escrito(text),
  privado.dias_escritos(smallint[]),
  privado.horario_de_cuadros(uuid),
  privado.restaurante_del_anuncio(uuid),
  privado.revisar_anuncio(uuid, bigint, bigint[])
from public, anon, authenticated, service_role;


-- ─── El gasto de IA ───────────────────────────────────────────────────────────

-- Como en la 6c, y además el paso de texto de los anuncios (palabras): suma su costo al sobre de
-- los anuncios y no cuenta en los 20. La imagen no pasa por aquí: su costo entra al terminar o al
-- fallar el anuncio. Regresa el costo y si ese sobre todavía puede gastar.
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
begin
  if p_uso is null or p_uso not in ('pregunta', 'saludo', 'menu', 'menu_sin_respuesta', 'palabras') then
    raise exception 'El uso de IA es pregunta, saludo, menu, menu_sin_respuesta o palabras' using errcode = '22023';
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
    costo_anuncios_usd
  ) values (
    p_restaurante_id, privado.mes_ia(v_zona),
    case when p_uso = 'pregunta' then 1 else 0 end,
    case when p_uso = 'saludo' then 1 else 0 end,
    case when v_menu or v_palabras then 0 else v_costo end,
    case when p_uso = 'menu' then 1 else 0 end,
    case when v_menu then v_costo else 0 end,
    case when v_palabras then v_costo else 0 end
  )
  on conflict (restaurante_id, mes) do update
  set consultas_agente = u.consultas_agente + excluded.consultas_agente,
      saludos = u.saludos + excluded.saludos,
      costo_agente_usd = u.costo_agente_usd + excluded.costo_agente_usd,
      consultas_menu = u.consultas_menu + excluded.consultas_menu,
      costo_menu_usd = u.costo_menu_usd + excluded.costo_menu_usd,
      costo_anuncios_usd = u.costo_anuncios_usd + excluded.costo_anuncios_usd;

  return jsonb_build_object(
    'costo', v_costo,
    'puede', privado.saldo_ia(p_restaurante_id,
               case when v_menu then 'menu' when v_palabras then 'anuncios' else 'agente' end) -> 'puede');
end;
$$;

-- La ventana «Tope de IA», como en la 6c. Hasta la 7b-3, el renglón del agente suma lo que gastaron
-- el agente y los anuncios (es su parte), y ya trae cuántos anuncios salieron y cuánto costaron,
-- para cuando los anuncios tengan su sobre.
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
    'gastado_agente', (coalesce(u.costo_agente_usd, 0) + coalesce(u.costo_anuncios_usd, 0))::numeric(10,4),
    'consultas_agente', coalesce(u.consultas_agente, 0),
    'saludos', coalesce(u.saludos, 0),
    'agente_en_limite', (privado.saldo_ia(r.id, 'agente') ->> 'motivo') is not distinct from 'limite',
    'anuncios', coalesce(u.anuncios, 0),
    'gastado_anuncios', coalesce(u.costo_anuncios_usd, 0)::numeric(10,4),
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


-- ─── Lo que lee Don Chuy ──────────────────────────────────────────────────────

-- «Crear contenido» en una sola lectura, al abrir y cada vez que avisa realtime: «Te quedan N de
-- 20» con el día en que vuelven, si la IA puede (como estado_ia, con la cuenta de los anuncios), su
-- restaurante como va en el anuncio, sus productos de Mi menú en su orden (sin archivados ni costos
-- de envío; los ocultos sí) y el resultado: el que se está haciendo en la sucursal, de quien sea,
-- o si no, el último que terminó hecho por él que todavía no ve. Antes suelta uno atorado.
create function public.crear_contenido(p_restaurante_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_saldo jsonb;
  v_resultado jsonb;
  v_productos jsonb;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede crear anuncios' using errcode = '42501';
  end if;
  v_miembro := privado.mi_miembro(p_restaurante_id, array['gerente']);
  perform privado.soltar_atorados(p_restaurante_id);

  v_saldo := privado.saldo_ia(p_restaurante_id, 'anuncios');

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'nombre', p.nombre,
           'descripcion', p.descripcion,
           'imagen_ruta', p.imagen_ruta,
           'precio', p.precio,
           'precio_escrito', privado.dinero(p.precio)
         ) order by c.orden, c.id, p.orden, p.id), '[]')
  into v_productos
  from public.productos p
  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
  where p.restaurante_id = p_restaurante_id
    and p.archivado_at is null
    and c.archivado_at is null
    and not p.es_envio;

  select jsonb_build_object(
           'id', a.id,
           'estado', a.estado,
           'motivo', a.motivo,
           'estilo_id', a.estilo_id,
           'formato', a.formato,
           'productos', a.productos,
           'mensaje', a.mensaje,
           'color', a.color,
           'palabras', a.palabras,
           'ruta', a.ruta,
           'segundos', floor(extract(epoch from now() - a.created_at))::integer
         )
  into v_resultado
  from public.anuncios a
  where a.restaurante_id = p_restaurante_id
    and (a.estado = 'haciendo'
         or (a.hecho_por = v_miembro and a.visto_at is null))
  order by a.estado = 'haciendo' desc, a.created_at desc, a.id desc
  limit 1;

  return privado.anuncios_del_mes(p_restaurante_id) || jsonb_build_object(
    'ia', case when (v_saldo ->> 'puede')::boolean then jsonb_build_object('puede', true)
               else jsonb_build_object('puede', false, 'motivo', v_saldo -> 'motivo',
                                       'con_distribuidor', v_saldo -> 'con_distribuidor',
                                       'vuelve', v_saldo -> 'vuelve') end,
    'restaurante', privado.restaurante_del_anuncio(p_restaurante_id),
    'productos', v_productos,
    'resultado', v_resultado
  );
end;
$$;

-- La app lo marca en cuanto lo enseña terminado: el anuncio, o el aviso de que no salió. Solo quien
-- lo hizo; uno que se está haciendo no se marca, y uno ya visto se queda como estaba.
create function public.anuncio_visto(p_anuncio_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anuncio public.anuncios%rowtype;
begin
  select * into v_anuncio from public.anuncios where id = p_anuncio_id for update;
  if not found or v_anuncio.restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Ese anuncio ya no existe' using errcode = 'P0002';
  end if;
  if v_anuncio.hecho_por is distinct from privado.mi_miembro(v_anuncio.restaurante_id, array['gerente']) then
    raise exception 'Solo quien hizo el anuncio lo marca visto' using errcode = '42501';
  end if;
  if v_anuncio.estado = 'haciendo' then
    raise exception 'Ese anuncio todavía se está haciendo' using errcode = '22023';
  end if;

  update public.anuncios set visto_at = now() where id = p_anuncio_id and visto_at is null;
end;
$$;


-- ─── Lo que pide el Worker con la sesión de Don Chuy ──────────────────────────

-- Antes del paso de texto («POST /anuncios/palabras»): lo mismo que revisa apartar_anuncio, sin
-- apartar nada. No revisa los 20 ni si hay otro haciéndose.
create function public.datos_para_anuncio(p_restaurante_id uuid, p_estilo_id bigint, p_productos bigint[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select privado.revisar_anuncio(p_restaurante_id, p_estilo_id, p_productos);
$$;

-- «Generar anuncio» y «Otra vez»: aparta el lugar. La app manda solo el color que eligió, y el
-- Worker dice si el estilo lleva color (con_color, de su código): sin color elegido va el de su
-- marca, y en un estilo sin color (los festivos), ninguno. El mensaje y las palabras ya vienen
-- revisados contra su estilo por el Worker; aquí, solo su forma. Regresa {ok: true, anuncio_id} o
-- {ok: false, motivo}: sin_ia o limite (con con_distribuidor y vuelve), veinte (con vuelve),
-- estilo o haciendo.
create function public.apartar_anuncio(
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
    return jsonb_build_object('ok', false, 'motivo', 'veinte', 'vuelve', v_cuenta -> 'vuelve');
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


-- ─── Lo que pide el trabajo en segundo plano (solo la llave secreta) ──────────

-- Lo apartado y lo que lleva: los productos con el nombre que se guardó y la descripción, la foto y
-- el precio de hoy (si alguno ya no existe, va solo su nombre) y el restaurante. Si ya no está
-- «haciendo» (pasaron los 15 minutos), el trabajo no llama a OpenAI.
create function public.datos_del_anuncio(p_anuncio_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante uuid;
  v_datos jsonb;
begin
  select restaurante_id into v_restaurante from public.anuncios where id = p_anuncio_id;
  if not found then
    raise exception 'No existe el anuncio %', p_anuncio_id using errcode = 'P0002';
  end if;
  perform privado.soltar_atorados(v_restaurante);

  select jsonb_build_object(
    'id', a.id,
    'restaurante_id', a.restaurante_id,
    'estado', a.estado,
    'estilo', e.clave,
    'formato', a.formato,
    'productos', (
      select jsonb_agg(
               jsonb_build_object('id', x -> 'id', 'nombre', x -> 'nombre')
               || case when p.id is null then '{}'::jsonb
                       else jsonb_build_object(
                              'descripcion', p.descripcion,
                              'imagen_ruta', p.imagen_ruta,
                              'precio', p.precio,
                              'precio_escrito', privado.dinero(p.precio)) end
               order by n)
      from jsonb_array_elements(a.productos) with ordinality as l (x, n)
      left join public.productos p on p.restaurante_id = a.restaurante_id and p.id = (x ->> 'id')::bigint
    ),
    'mensaje', a.mensaje,
    'color', a.color,
    'palabras', a.palabras,
    'restaurante', privado.restaurante_del_anuncio(a.restaurante_id)
  )
  into v_datos
  from public.anuncios a
  join public.estilos e on e.id = a.estilo_id
  where a.id = p_anuncio_id;
  return v_datos;
end;
$$;

-- El JPG ya está en R2: queda «listo», se ve hasta el día en que terminó más 29 (30 días contando
-- el primero), y suma 1 y su costo en el mes en que terminó. Cada anuncio lleva una sola imagen,
-- así que su costo se pone, no se suma: si el Worker repite este paso, no cuenta dos veces. Si ya
-- no estaba «haciendo» (pasaron los 15 minutos), solo suma su costo y regresa ok false: el Worker
-- borra el archivo. Regresa {ok, costo}.
create function public.terminar_anuncio(
  p_anuncio_id bigint,
  p_ruta text,
  p_modelo text,
  p_entrada_texto bigint,
  p_entrada_imagen bigint,
  p_salida bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anuncio public.anuncios%rowtype;
  v_zona text;
  v_costo numeric(10,4);
  v_mas numeric(10,4);
begin
  if p_entrada_texto is null or p_entrada_imagen is null or p_salida is null
     or p_entrada_texto < 0 or p_entrada_imagen < 0 or p_salida < 0 then
    raise exception 'Los tokens van completos y en 0 o más' using errcode = '22023';
  end if;
  v_costo := privado.costo_imagen(p_modelo, p_entrada_texto, p_entrada_imagen, p_salida);
  if v_costo is null then
    raise exception 'No hay precio de imagen para el modelo %', p_modelo using errcode = 'P0002';
  end if;

  select * into v_anuncio from public.anuncios where id = p_anuncio_id for update;
  if not found then
    raise exception 'No existe el anuncio %', p_anuncio_id using errcode = 'P0002';
  end if;
  if coalesce(p_ruta, '') !~ ('^restaurantes/' || v_anuncio.restaurante_id::text || '/biblioteca/[0-9a-f]{32}\.jpg$') then
    raise exception 'La ruta del anuncio va en la biblioteca de su restaurante' using errcode = '22023';
  end if;
  if v_anuncio.estado = 'listo' then
    return jsonb_build_object('ok', v_anuncio.ruta = p_ruta, 'costo', v_anuncio.costo_usd);
  end if;

  perform privado.soltar_atorados(v_anuncio.restaurante_id);
  select * into v_anuncio from public.anuncios where id = p_anuncio_id;
  select zona_horaria into v_zona from public.restaurantes where id = v_anuncio.restaurante_id;
  v_mas := greatest(v_costo - v_anuncio.costo_usd, 0);

  if v_anuncio.estado = 'haciendo' then
    update public.anuncios
    set estado = 'listo',
        ruta = p_ruta,
        terminado_at = now(),
        vence = privado.dia_local(v_zona) + 29,
        costo_usd = greatest(costo_usd, v_costo)
    where id = p_anuncio_id;
    perform privado.sumar_a_anuncios(v_anuncio.restaurante_id, 1, v_mas);
    return jsonb_build_object('ok', true, 'costo', greatest(v_anuncio.costo_usd, v_costo));
  end if;

  -- Llegó tarde: ya cuenta como que no salió.
  if v_mas > 0 then
    update public.anuncios set costo_usd = costo_usd + v_mas where id = p_anuncio_id;
    perform privado.sumar_a_anuncios(v_anuncio.restaurante_id, 0, v_mas);
  end if;
  return jsonb_build_object('ok', false, 'costo', greatest(v_anuncio.costo_usd, v_costo));
end;
$$;

-- No salió: «rechazado», OpenAI no lo aceptó (lo único que Don Chuy arregla, cambiando el mensaje);
-- «no_salio», OpenAI no contestó o R2 no lo guardó. Lleva lo que cobró OpenAI (0 si no contestó),
-- que va al sobre y no cuenta en los 20. Si ya había fallado (pasaron los 15 minutos), se queda
-- con su motivo y solo suma su costo; repetido, no cuenta dos veces. Regresa {costo}.
create function public.fallar_anuncio(
  p_anuncio_id bigint,
  p_motivo text,
  p_modelo text,
  p_entrada_texto bigint,
  p_entrada_imagen bigint,
  p_salida bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anuncio public.anuncios%rowtype;
  v_zona text;
  v_costo numeric(10,4);
  v_mas numeric(10,4);
begin
  if p_motivo is null or p_motivo not in ('rechazado', 'no_salio') then
    raise exception 'El motivo es rechazado o no_salio' using errcode = '22023';
  end if;
  if p_entrada_texto is null or p_entrada_imagen is null or p_salida is null
     or p_entrada_texto < 0 or p_entrada_imagen < 0 or p_salida < 0 then
    raise exception 'Los tokens van completos y en 0 o más' using errcode = '22023';
  end if;
  v_costo := privado.costo_imagen(p_modelo, p_entrada_texto, p_entrada_imagen, p_salida);
  if v_costo is null then
    raise exception 'No hay precio de imagen para el modelo %', p_modelo using errcode = 'P0002';
  end if;

  select * into v_anuncio from public.anuncios where id = p_anuncio_id for update;
  if not found then
    raise exception 'No existe el anuncio %', p_anuncio_id using errcode = 'P0002';
  end if;
  if v_anuncio.estado = 'listo' then
    raise exception 'El anuncio % ya salió', p_anuncio_id using errcode = '55000';
  end if;

  perform privado.soltar_atorados(v_anuncio.restaurante_id);
  select * into v_anuncio from public.anuncios where id = p_anuncio_id;
  select zona_horaria into v_zona from public.restaurantes where id = v_anuncio.restaurante_id;
  v_mas := greatest(v_costo - v_anuncio.costo_usd, 0);

  update public.anuncios
  set estado = 'fallo',
      motivo = coalesce(motivo, p_motivo),
      terminado_at = coalesce(terminado_at, now()),
      vence = coalesce(vence, privado.dia_local(v_zona) + 29),
      costo_usd = costo_usd + v_mas
  where id = p_anuncio_id;
  if v_mas > 0 then
    perform privado.sumar_a_anuncios(v_anuncio.restaurante_id, 0, v_mas);
  end if;
  return jsonb_build_object('costo', v_anuncio.costo_usd + v_mas);
end;
$$;


-- ─── Quién llama a qué ────────────────────────────────────────────────────────

revoke execute on function
  public.crear_contenido(uuid),
  public.anuncio_visto(bigint),
  public.datos_para_anuncio(uuid, bigint, bigint[]),
  public.apartar_anuncio(uuid, bigint, text, bigint[], text, text, boolean, jsonb)
from public, anon, service_role;

grant execute on function
  public.crear_contenido(uuid),
  public.anuncio_visto(bigint),
  public.datos_para_anuncio(uuid, bigint, bigint[]),
  public.apartar_anuncio(uuid, bigint, text, bigint[], text, text, boolean, jsonb)
to authenticated;

revoke execute on function
  public.datos_del_anuncio(bigint),
  public.terminar_anuncio(bigint, text, text, bigint, bigint, bigint),
  public.fallar_anuncio(bigint, text, text, bigint, bigint, bigint)
from public, anon, authenticated;

grant execute on function
  public.datos_del_anuncio(bigint),
  public.terminar_anuncio(bigint, text, text, bigint, bigint, bigint),
  public.fallar_anuncio(bigint, text, text, bigint, bigint, bigint)
to service_role;
