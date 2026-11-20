-- El recetario (19 de noviembre de 2026; planes/trabajo/recetario/): cómo se hace cada platillo y cada preparación, con
-- pasos y fotos, para el cocinero nuevo. Lo que lleva no se escribe otra vez: sale de recetas, con sus mismas
-- cantidades, y el recetario no resta nada del inventario. Lo decidido: las encuestas de
-- planes/trabajo/recetario/encuestas.md y el Diccionario de la libreta 2 («El recetario», rev 134).
--
-- Tres tablas nuevas: recetarios, pasos_recetario y fotos_por_borrar. Nadie las lee ni las escribe directo: el gerente
-- escribe con guardar_recetario; el gerente, la cocina y la caja leen con recetario y pagina_recetario (la caja no lee
-- ingredientes ni recetas), y el Worker vacía fotos_por_borrar una vez al día con fotos_sueltas y borrar_fotos_sueltas.
-- puedo_borrar_foto (del menú) acepta ahora la carpeta recetario/. No se reescribe ninguna función del inventario.


-- ─── recetarios ───────────────────────────────────────────────────────────────
-- El de un platillo o el de una preparación, con su foto de cómo se sirve. Nace la primera vez que el gerente guarda
-- algo en él y se va con su platillo o su preparación. Un platillo archivado lo guarda escondido.

create table public.recetarios (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  producto_id bigint,
  preparacion_id bigint,
  imagen_ruta text
    constraint recetarios_imagen_ruta_formato
    check (imagen_ruta ~ ('^restaurantes/' || restaurante_id::text || '/recetario/[0-9a-f]{32}\.webp$')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, producto_id) references public.productos (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, preparacion_id) references public.preparaciones (restaurante_id, id) on delete cascade,
  constraint recetarios_un_dueno check (num_nonnulls(producto_id, preparacion_id) = 1)
);

create unique index recetarios_producto_unico on public.recetarios (restaurante_id, producto_id);
create unique index recetarios_preparacion_unico on public.recetarios (restaurante_id, preparacion_id);

create trigger recetarios_updated_at
before update on public.recetarios
for each row execute function privado.set_updated_at();


-- ─── pasos_recetario ──────────────────────────────────────────────────────────
-- Cada paso, en orden: hasta 20, de hasta 300 letras, con su foto opcional. Se reemplazan juntos al guardar.

create table public.pasos_recetario (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  recetario_id bigint not null,
  orden integer not null constraint pasos_recetario_orden check (orden between 1 and 20),
  texto text not null constraint pasos_recetario_texto check (btrim(texto) <> '' and char_length(texto) <= 300),
  imagen_ruta text
    constraint pasos_recetario_imagen_ruta_formato
    check (imagen_ruta ~ ('^restaurantes/' || restaurante_id::text || '/recetario/[0-9a-f]{32}\.webp$')),
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, recetario_id) references public.recetarios (restaurante_id, id) on delete cascade
);

-- Uno por recetario y orden; empieza por el restaurante para buscar sus fotos sin recorrer los de todos.
create unique index pasos_recetario_orden_unico on public.pasos_recetario (restaurante_id, recetario_id, orden);


-- ─── fotos_por_borrar ─────────────────────────────────────────────────────────
-- Las fotos de R2 que dejaron de usarse. Las anota un disparador; el Worker las borra una vez al día.

create table public.fotos_por_borrar (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  ruta text not null
    constraint fotos_por_borrar_ruta
    check (ruta ~ ('^restaurantes/' || restaurante_id::text || '/recetario/[0-9a-f]{32}\.webp$')),
  created_at timestamptz not null default now()
);

-- LA forma de decir si una foto de R2 todavía se usa: un platillo de Mi menú (también los archivados), el logo, un
-- cartel, un recetario o un paso.
create function privado.foto_en_uso(p_ruta text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with r as (
    select (regexp_match(p_ruta, '^restaurantes/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/'))[1]::uuid as id
  )
  select exists (select 1 from r join public.productos p on p.restaurante_id = r.id where p.imagen_ruta = p_ruta)
      or exists (select 1 from r join public.restaurantes x on x.id = r.id where x.logo_ruta = p_ruta)
      or exists (select 1 from r join public.carteles c on c.restaurante_id = r.id where c.imagen_ruta = p_ruta)
      or exists (select 1 from r join public.recetarios rc on rc.restaurante_id = r.id where rc.imagen_ruta = p_ruta)
      or exists (select 1 from r join public.pasos_recetario s on s.restaurante_id = r.id where s.imagen_ruta = p_ruta);
$$;

-- La foto que se quitó, se cambió o se fue con su renglón, a la fila (una sola vez). Si se fue con su restaurante
-- entero (solo a mano, como postgres), no: la fila ya no tendría de quién ser.
create function privado.anotar_foto_por_borrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ruta text;
begin
  if tg_op = 'DELETE' then
    v_ruta := old.imagen_ruta;
  elsif new.imagen_ruta is distinct from old.imagen_ruta then
    v_ruta := old.imagen_ruta;
  end if;
  if v_ruta is not null then
    insert into public.fotos_por_borrar (restaurante_id, ruta)
    select old.restaurante_id, v_ruta
    where not exists (select 1 from public.fotos_por_borrar f where f.ruta = v_ruta)
      and exists (select 1 from public.restaurantes r where r.id = old.restaurante_id);
  end if;
  return null;
end;
$$;

create trigger recetarios_fotos_por_borrar
after update of imagen_ruta or delete on public.recetarios
for each row execute function privado.anotar_foto_por_borrar();

create trigger pasos_recetario_fotos_por_borrar
after update of imagen_ruta or delete on public.pasos_recetario
for each row execute function privado.anotar_foto_por_borrar();


-- ─── Lo que lleva, como está escrito ──────────────────────────────────────────
-- Los renglones de la receta de un platillo, una opción o una preparación, sin abrir las preparaciones («30 ml de
-- Salsa verde»). Una preparación dice si su recetario tiene pasos: en la cocina solo esa se abre.

create function privado.lleva_del_recetario(
  p_restaurante_id uuid,
  p_producto_id bigint,
  p_opcion_id bigint,
  p_preparacion_id bigint
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'nombre', coalesce(i.nombre, pr.nombre),
    'cantidad', r.cantidad,
    'unidad', r.unidad,
    'preparacion_id', r.lleva_preparacion_id,
    'con_pasos', case when r.lleva_preparacion_id is not null then exists (
      select 1
      from public.recetarios rc
      join public.pasos_recetario s on s.restaurante_id = rc.restaurante_id and s.recetario_id = rc.id
      where rc.restaurante_id = r.restaurante_id and rc.preparacion_id = r.lleva_preparacion_id
    ) end
  ) order by r.id), '[]')
  from public.recetas r
  left join public.ingredientes i on i.restaurante_id = r.restaurante_id and i.id = r.ingrediente_id
  left join public.preparaciones pr on pr.restaurante_id = r.restaurante_id and pr.id = r.lleva_preparacion_id
  where r.restaurante_id = p_restaurante_id
    and r.producto_id is not distinct from p_producto_id
    and r.opcion_id is not distinct from p_opcion_id
    and r.preparacion_id is not distinct from p_preparacion_id;
$$;


-- ─── Leer el recetario (el gerente, la cocina y la caja) ──────────────────────

-- Los cuadros: los platillos de Mi menú por categoría, en el orden del menú (sin envíos ni archivados; los agotados
-- sí), y las preparaciones al final, por nombre. Cada uno con su foto (la de cómo se sirve o, en un platillo, la de
-- Mi menú) y cuántos pasos tiene. La cocina y la caja ven solo los que tienen pasos; el gerente, todos.
create function public.recetario(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gerente boolean := privado.mi_miembro(p_restaurante_id, array['gerente']) is not null;
begin
  if not v_gerente and privado.mi_miembro(p_restaurante_id, array['cocina', 'caja']) is null then
    raise exception 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre, 'icono', c.icono, 'platillos', x.platillos)
                       order by c.orden, c.id)
      from public.categorias c
      cross join lateral (
        select jsonb_agg(jsonb_build_object(
          'id', p.id,
          'nombre', p.nombre,
          'foto', coalesce(rc.imagen_ruta, p.imagen_ruta),
          'pasos', n.pasos
        ) order by p.orden, p.id) as platillos
        from public.productos p
        left join public.recetarios rc on rc.restaurante_id = p.restaurante_id and rc.producto_id = p.id
        cross join lateral (
          select count(*)::integer as pasos
          from public.pasos_recetario s
          where s.restaurante_id = p.restaurante_id and s.recetario_id = rc.id
        ) n
        where p.restaurante_id = c.restaurante_id and p.categoria_id = c.id
          and p.archivado_at is null and not p.es_envio
          and (v_gerente or n.pasos > 0)
      ) x
      where c.restaurante_id = p_restaurante_id and c.archivado_at is null and x.platillos is not null
    ), '[]'),
    'preparaciones', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id,
        'nombre', pr.nombre,
        'foto', rc.imagen_ruta,
        'pasos', n.pasos
      ) order by lower(pr.nombre), pr.id)
      from public.preparaciones pr
      left join public.recetarios rc on rc.restaurante_id = pr.restaurante_id and rc.preparacion_id = pr.id
      cross join lateral (
        select count(*)::integer as pasos
        from public.pasos_recetario s
        where s.restaurante_id = pr.restaurante_id and s.recetario_id = rc.id
      ) n
      where pr.restaurante_id = p_restaurante_id
        and (v_gerente or n.pasos > 0)
    ), '[]')
  );
end;
$$;

-- La página de un platillo (p_producto_id) o de una preparación (p_preparacion_id): su foto, lo que lleva, las
-- opciones que suman algo (en un platillo) y sus pasos. Vacío si ya no está, o si la cocina o la caja la piden sin
-- pasos.
create function public.pagina_recetario(
  p_restaurante_id uuid,
  p_producto_id bigint default null,
  p_preparacion_id bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gerente boolean := privado.mi_miembro(p_restaurante_id, array['gerente']) is not null;
  v_pagina jsonb;
  v_recetario public.recetarios;
  v_pasos jsonb;
begin
  if not v_gerente and privado.mi_miembro(p_restaurante_id, array['cocina', 'caja']) is null then
    raise exception 'Solo el gerente, la cocina y la caja de este restaurante leen el recetario' using errcode = '42501';
  end if;
  if num_nonnulls(p_producto_id, p_preparacion_id) <> 1 then
    raise exception 'El recetario es de un platillo o de una preparación' using errcode = '22023';
  end if;

  if p_producto_id is not null then
    select jsonb_build_object(
      'tipo', 'platillo',
      'id', p.id,
      'nombre', p.nombre,
      'categoria', c.nombre,
      'rinde', null,
      'unidad', null,
      'foto_de_mi_menu', p.imagen_ruta,
      'lleva', privado.lleva_del_recetario(p_restaurante_id, p.id, null, null),
      'opciones', coalesce((
        select jsonb_agg(jsonb_build_object(
          'grupo', g.nombre,
          'nombre', o.nombre,
          'lleva', privado.lleva_del_recetario(p_restaurante_id, null, o.id, null)
        ) order by g.orden, g.id, o.orden, o.id)
        from public.producto_grupos pg
        join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
        join public.opciones o on o.restaurante_id = g.restaurante_id and o.grupo_id = g.id
        where pg.restaurante_id = p.restaurante_id and pg.producto_id = p.id
          and exists (select 1 from public.recetas r where r.restaurante_id = o.restaurante_id and r.opcion_id = o.id)
      ), '[]')
    )
    into v_pagina
    from public.productos p
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where p.restaurante_id = p_restaurante_id and p.id = p_producto_id and p.archivado_at is null and not p.es_envio;

    select * into v_recetario
    from public.recetarios where restaurante_id = p_restaurante_id and producto_id = p_producto_id;
  else
    select jsonb_build_object(
      'tipo', 'preparacion',
      'id', pr.id,
      'nombre', pr.nombre,
      'categoria', null,
      'rinde', pr.rinde,
      'unidad', pr.unidad,
      'foto_de_mi_menu', null,
      'lleva', privado.lleva_del_recetario(p_restaurante_id, null, null, pr.id),
      'opciones', '[]'::jsonb
    )
    into v_pagina
    from public.preparaciones pr
    where pr.restaurante_id = p_restaurante_id and pr.id = p_preparacion_id;

    select * into v_recetario
    from public.recetarios where restaurante_id = p_restaurante_id and preparacion_id = p_preparacion_id;
  end if;

  if v_pagina is null then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('orden', s.orden, 'texto', s.texto, 'imagen_ruta', s.imagen_ruta)
                            order by s.orden), '[]')
  into v_pasos
  from public.pasos_recetario s
  where s.restaurante_id = p_restaurante_id and s.recetario_id = v_recetario.id;

  if not v_gerente and jsonb_array_length(v_pasos) = 0 then
    return null;
  end if;

  return v_pagina || jsonb_build_object(
    'imagen_ruta', v_recetario.imagen_ruta,
    'foto', coalesce(v_recetario.imagen_ruta, v_pagina ->> 'foto_de_mi_menu'),
    'pasos', v_pasos
  );
end;
$$;


-- ─── Escribir el recetario (el gerente) ───────────────────────────────────────

-- El recetario entero de un platillo o de una preparación: la foto de cómo se sirve (vacía = sin foto propia) y los
-- pasos, en renglones {texto, imagen_ruta}, que reemplazan a los que había. Las fotos ya las subió el Worker. Regresa
-- cuántos pasos quedaron.
create function public.guardar_recetario(
  p_restaurante_id uuid,
  p_imagen_ruta text,
  p_pasos jsonb,
  p_producto_id bigint default null,
  p_preparacion_id bigint default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_imagen text := nullif(btrim(coalesce(p_imagen_ruta, '')), '');
  v_paso jsonb;
  v_texto text;
  v_orden integer := 0;
  v_envio boolean;
  v_id bigint;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante escribe el recetario' using errcode = '42501';
  end if;
  if num_nonnulls(p_producto_id, p_preparacion_id) <> 1 then
    raise exception 'El recetario es de un platillo o de una preparación' using errcode = '22023';
  end if;
  if p_pasos is null or jsonb_typeof(p_pasos) <> 'array' then
    raise exception 'Los pasos llegan como una lista' using errcode = '22023';
  end if;
  if jsonb_array_length(p_pasos) > 20 then
    raise exception 'Un recetario lleva hasta 20 pasos' using errcode = '22023';
  end if;

  if p_producto_id is not null then
    select es_envio into v_envio
    from public.productos
    where restaurante_id = p_restaurante_id and id = p_producto_id and archivado_at is null
    for update;
    if v_envio is null then
      raise exception 'Ese platillo ya no está' using errcode = '22023';
    end if;
    if v_envio then
      raise exception 'Un costo de envío no lleva recetario' using errcode = '22023';
    end if;
    insert into public.recetarios (restaurante_id, producto_id, imagen_ruta)
    values (p_restaurante_id, p_producto_id, v_imagen)
    on conflict (restaurante_id, producto_id) do update set imagen_ruta = excluded.imagen_ruta
    returning id into v_id;
  else
    perform 1 from public.preparaciones where restaurante_id = p_restaurante_id and id = p_preparacion_id for update;
    if not found then
      raise exception 'Esa preparación ya no está' using errcode = '22023';
    end if;
    insert into public.recetarios (restaurante_id, preparacion_id, imagen_ruta)
    values (p_restaurante_id, p_preparacion_id, v_imagen)
    on conflict (restaurante_id, preparacion_id) do update set imagen_ruta = excluded.imagen_ruta
    returning id into v_id;
  end if;

  delete from public.pasos_recetario where restaurante_id = p_restaurante_id and recetario_id = v_id;
  for v_paso in select x from jsonb_array_elements(p_pasos) x loop
    v_orden := v_orden + 1;
    v_texto := btrim(coalesce(v_paso ->> 'texto', ''));
    if v_texto = '' then
      raise exception 'Escribe el paso %', v_orden using errcode = '22023';
    end if;
    if char_length(v_texto) > 300 then
      raise exception 'El paso % va de hasta 300 letras', v_orden using errcode = '22023';
    end if;
    insert into public.pasos_recetario (restaurante_id, recetario_id, orden, texto, imagen_ruta)
    values (p_restaurante_id, v_id, v_orden, v_texto, nullif(btrim(coalesce(v_paso ->> 'imagen_ruta', '')), ''));
  end loop;

  -- Una foto que se quedó (un paso que solo se movió) vuelve a usarse: sale de la fila.
  delete from public.fotos_por_borrar f
  where f.ruta = v_imagen
     or f.ruta in (select s.imagen_ruta from public.pasos_recetario s
                   where s.restaurante_id = p_restaurante_id and s.recetario_id = v_id and s.imagen_ruta is not null);
  return v_orden;
end;
$$;


-- ─── Las fotos sueltas (el trabajo diario del Worker, solo la llave secreta) ──

-- Hasta 1,000 fotos de la fila que ya nadie usa, las más viejas primero; el resto se va al otro día.
create function public.fotos_sueltas()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'ruta', f.ruta) order by f.id), '[]')
  from (
    select f.id, f.ruta
    from public.fotos_por_borrar f
    where not privado.foto_en_uso(f.ruta)
    order by f.id
    limit 1000
  ) f;
$$;

-- Después de que R2 borró sus archivos: saca de la fila las que de verdad siguen sueltas (una que se volvió a usar, se
-- queda). Regresa cuántas sacó.
create function public.borrar_fotos_sueltas(p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_borradas integer;
begin
  delete from public.fotos_por_borrar f
  where f.id = any (p_ids) and not privado.foto_en_uso(f.ruta);
  get diagnostics v_borradas = row_count;
  return v_borradas;
end;
$$;


-- ─── puedo_borrar_foto acepta el recetario ────────────────────────────────────
-- ¿Puede quien llama borrar esta imagen? Solo si está en la carpeta del menú, del logo, de los carteles o del
-- recetario de un restaurante donde es gerente, y nada la usa (privado.foto_en_uso). Así la app borra al momento una
-- foto del recetario que se subió y no se guardó, como en Mi menú.
create or replace function public.puedo_borrar_foto(p_ruta text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
begin
  if p_ruta is null or p_ruta !~ (
    '^restaurantes/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(menu|logo|carteles|recetario)/[0-9a-f]{32}\.webp$'
  ) then
    return false;
  end if;
  v_restaurante_id := split_part(p_ruta, '/', 2)::uuid;

  return v_restaurante_id in (select privado.mis_restaurantes_gerente())
    and not privado.foto_en_uso(p_ruta);
end;
$$;


-- ─── Permisos ─────────────────────────────────────────────────────────────────
-- Nadie lee ni escribe estas tablas directo, ni el Worker: todo va por sus funciones.

alter table public.recetarios enable row level security;
alter table public.pasos_recetario enable row level security;
alter table public.fotos_por_borrar enable row level security;

revoke all on table public.recetarios, public.pasos_recetario, public.fotos_por_borrar
  from public, anon, authenticated, service_role;
revoke all on sequence public.recetarios_id_seq, public.pasos_recetario_id_seq, public.fotos_por_borrar_id_seq
  from public, anon, authenticated, service_role;

revoke execute on function
  privado.foto_en_uso(text),
  privado.anotar_foto_por_borrar(),
  privado.lleva_del_recetario(uuid, bigint, bigint, bigint)
from public, anon, authenticated, service_role;

revoke execute on function
  public.recetario(uuid),
  public.pagina_recetario(uuid, bigint, bigint),
  public.guardar_recetario(uuid, text, jsonb, bigint, bigint)
from public, anon, service_role;

grant execute on function
  public.recetario(uuid),
  public.pagina_recetario(uuid, bigint, bigint),
  public.guardar_recetario(uuid, text, jsonb, bigint, bigint)
to authenticated;

revoke execute on function
  public.fotos_sueltas(),
  public.borrar_fotos_sueltas(bigint[])
from public, anon, authenticated;

grant execute on function
  public.fotos_sueltas(),
  public.borrar_fotos_sueltas(bigint[])
to service_role;
