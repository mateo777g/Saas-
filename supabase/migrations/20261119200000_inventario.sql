-- El inventario con sus recetas (19 de noviembre de 2026; planes/trabajo/inventario/): cuánto queda de cada
-- ingrediente y qué lleva cada platillo. Cuando una cuenta se cierra resta sola su receta; si un pago cancelado la
-- reabre, se la regresa, y al cerrarse otra vez resta de nuevo, nunca dos veces. Lo decidido: las encuestas de
-- planes/trabajo/inventario/encuestas.md y el Diccionario de la libreta 2 («Inventario», revs 124 a 133).
--
-- Cuatro tablas nuevas: ingredientes (lo leen el gerente y la cocina, en tiempo real), preparaciones, recetas y
-- movimientos_inventario (solo el gerente las lee). Nadie las escribe directo: lo hacen las funciones de aquí. El
-- gerente hace todo; la cocina anota lo que llegó y las mermas; la cocina y la caja marcan un platillo agotado
-- (productos.visible), y productos entra al tiempo real para que el punto de venta lo vea al momento.
--
-- No se reescriben mandar_a_cocina, confirmar_pedido, cobrar ni privado.anotar_pago: el descuento va en un disparador
-- aparte de ventas, y cada renglón vendido guarda el id de sus opciones con otro disparador de venta_items.


-- ─── Las unidades ─────────────────────────────────────────────────────────────
-- kg, g, l, ml y pieza. Kilos y gramos son de una familia, litros y mililitros de otra, y las piezas solas.

create function privado.familia_unidad(p_unidad text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_unidad
    when 'kg' then 'peso' when 'g' then 'peso'
    when 'l' then 'volumen' when 'ml' then 'volumen'
    when 'pieza' then 'pieza'
  end;
$$;

-- La cantidad en p_de pasada a p_a. Fuera de su familia, vacío.
create function privado.convertir_unidad(p_cantidad numeric, p_de text, p_a text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select p_cantidad * case
    when p_de = p_a then 1
    when (p_de, p_a) in (('kg', 'g'), ('l', 'ml')) then 1000
    when (p_de, p_a) in (('g', 'kg'), ('ml', 'l')) then 0.001
  end;
$$;


-- ─── ingredientes ─────────────────────────────────────────────────────────────
-- Lo que se gasta al vender, contado en una sola unidad que no cambia. Su existencia es la suma de sus movimientos:
-- la pone el disparador de movimientos_inventario. Nunca se borra: se archiva.

create table public.ingredientes (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null constraint ingredientes_nombre check (btrim(nombre) <> '' and char_length(nombre) <= 60),
  unidad text not null constraint ingredientes_unidad check (unidad in ('kg', 'g', 'l', 'ml', 'pieza')),
  por_caja numeric(12,3) constraint ingredientes_por_caja check (por_caja > 0),
  minimo numeric(12,3) constraint ingredientes_minimo check (minimo > 0),
  existencia numeric(12,3) not null default 0,
  archivado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

create unique index ingredientes_nombre_unico
  on public.ingredientes (restaurante_id, lower(nombre)) where archivado_at is null;

create trigger ingredientes_updated_at
before update on public.ingredientes
for each row execute function privado.set_updated_at();

-- Su unidad no cambia: su historial tiene que seguir diciendo lo mismo.
create function privado.unidad_fija()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.unidad is distinct from old.unidad then
    raise exception 'La unidad de un ingrediente no cambia: archívalo y crea otro' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger ingredientes_unidad_fija
before update of unidad on public.ingredientes
for each row execute function privado.unidad_fija();


-- ─── preparaciones ────────────────────────────────────────────────────────────
-- Lo que se hace antes y va en varios platillos (la salsa en olla): su receta, escrita para lo que rinde. No tiene
-- existencia ni historia: se elimina en vez de archivarse.

create table public.preparaciones (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null constraint preparaciones_nombre check (btrim(nombre) <> '' and char_length(nombre) <= 60),
  rinde numeric(12,3) not null constraint preparaciones_rinde check (rinde > 0),
  unidad text not null constraint preparaciones_unidad check (unidad in ('kg', 'g', 'l', 'ml', 'pieza')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id)
);

create unique index preparaciones_nombre_unico on public.preparaciones (restaurante_id, lower(nombre));

create trigger preparaciones_updated_at
before update on public.preparaciones
for each row execute function privado.set_updated_at();


-- ─── recetas ──────────────────────────────────────────────────────────────────
-- Qué lleva cada platillo, cada opción y cada preparación: un renglón por ingrediente o preparación, para uno.

create table public.recetas (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  producto_id bigint,
  opcion_id bigint,
  preparacion_id bigint,
  ingrediente_id bigint,
  lleva_preparacion_id bigint,
  cantidad numeric(12,3) not null constraint recetas_cantidad check (cantidad > 0),
  unidad text not null constraint recetas_unidad check (unidad in ('kg', 'g', 'l', 'ml', 'pieza')),
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, producto_id) references public.productos (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, opcion_id) references public.opciones (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, preparacion_id) references public.preparaciones (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, ingrediente_id) references public.ingredientes (restaurante_id, id),
  foreign key (restaurante_id, lleva_preparacion_id) references public.preparaciones (restaurante_id, id) on delete cascade,
  constraint recetas_un_dueno check (num_nonnulls(producto_id, opcion_id, preparacion_id) = 1),
  constraint recetas_una_cosa check (num_nonnulls(ingrediente_id, lleva_preparacion_id) = 1),
  constraint recetas_una_capa check (preparacion_id is null or lleva_preparacion_id is null)
);

-- Un ingrediente o una preparación va una sola vez en cada receta.
create unique index recetas_sin_repetir on public.recetas (
  restaurante_id, coalesce(producto_id, 0), coalesce(opcion_id, 0), coalesce(preparacion_id, 0),
  coalesce(ingrediente_id, 0), coalesce(lleva_preparacion_id, 0)
);
create index recetas_producto_idx on public.recetas (restaurante_id, producto_id);
create index recetas_opcion_idx on public.recetas (restaurante_id, opcion_id);
create index recetas_preparacion_idx on public.recetas (restaurante_id, preparacion_id);
create index recetas_ingrediente_idx on public.recetas (restaurante_id, ingrediente_id);
create index recetas_lleva_preparacion_idx on public.recetas (restaurante_id, lleva_preparacion_id);

-- Lo que la tabla no puede revisar sola: un envío no lleva receta, un ingrediente archivado no entra, y la cantidad va
-- en la familia de su ingrediente o de lo que rinde su preparación.
create function privado.revisar_receta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unidad text;
  v_nombre text;
begin
  if new.producto_id is not null
     and (select p.es_envio from public.productos p where p.restaurante_id = new.restaurante_id and p.id = new.producto_id) then
    raise exception 'Un costo de envío no lleva receta' using errcode = '22023';
  end if;
  if new.ingrediente_id is not null then
    select i.unidad, i.nombre into v_unidad, v_nombre
    from public.ingredientes i
    where i.restaurante_id = new.restaurante_id and i.id = new.ingrediente_id and i.archivado_at is null;
    if v_unidad is null then
      raise exception 'Ese ingrediente ya no está' using errcode = '22023';
    end if;
  else
    select p.unidad, p.nombre into v_unidad, v_nombre
    from public.preparaciones p
    where p.restaurante_id = new.restaurante_id and p.id = new.lleva_preparacion_id;
  end if;
  if privado.familia_unidad(new.unidad) <> privado.familia_unidad(v_unidad) then
    raise exception '«%» se mide en %: su cantidad va en esa misma familia', v_nombre,
      case privado.familia_unidad(v_unidad) when 'peso' then 'kilos o gramos' when 'volumen' then 'litros o mililitros'
        else 'piezas' end
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger recetas_revisar
before insert or update on public.recetas
for each row execute function privado.revisar_receta();


-- ─── movimientos_inventario ───────────────────────────────────────────────────
-- Cada cosa que sube o baja la existencia de un ingrediente, en su unidad. No se editan ni se borran.

create table public.movimientos_inventario (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  ingrediente_id bigint not null,
  tipo text not null
    constraint movimientos_inventario_tipo check (tipo in ('venta', 'regreso', 'llegada', 'merma', 'conteo', 'deshacer')),
  cantidad numeric(12,3) not null,
  contado numeric(12,3) constraint movimientos_inventario_contado_valido check (contado >= 0),
  cajas integer constraint movimientos_inventario_cajas_valido check (cajas > 0),
  motivo text constraint movimientos_inventario_motivo_valido
    check (motivo in ('se_echo_a_perder', 'se_cayo_o_quemo', 'caduco', 'otro')),
  nota text constraint movimientos_inventario_nota_valida check (btrim(nota) <> '' and char_length(nota) <= 200),
  venta_id bigint,
  producto_id bigint,
  platillos integer constraint movimientos_inventario_platillos_valido check (platillos > 0),
  deshace_id bigint constraint movimientos_inventario_deshace_unico unique,
  anotado_por bigint,
  clave uuid,
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, ingrediente_id) references public.ingredientes (restaurante_id, id),
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, producto_id) references public.productos (restaurante_id, id),
  foreign key (restaurante_id, deshace_id) references public.movimientos_inventario (restaurante_id, id),
  foreign key (restaurante_id, anotado_por) references public.miembros (restaurante_id, id),
  constraint movimientos_inventario_signo check (
    case tipo
      when 'venta' then cantidad < 0
      when 'merma' then cantidad < 0
      when 'llegada' then cantidad > 0
      when 'regreso' then cantidad > 0
      else true
    end
  ),
  constraint movimientos_inventario_contado check ((tipo = 'conteo') = (contado is not null)),
  constraint movimientos_inventario_cajas check (cajas is null or tipo = 'llegada'),
  constraint movimientos_inventario_motivo check ((tipo = 'merma') = (motivo is not null)),
  constraint movimientos_inventario_nota_otro check (motivo is distinct from 'otro' or nota is not null),
  constraint movimientos_inventario_venta check ((tipo in ('venta', 'regreso')) = (venta_id is not null)),
  constraint movimientos_inventario_producto check (producto_id is null or tipo = 'merma'),
  constraint movimientos_inventario_platillos check ((producto_id is null) = (platillos is null)),
  constraint movimientos_inventario_deshace check ((tipo = 'deshacer') = (deshace_id is not null)),
  constraint movimientos_inventario_anotado check ((tipo in ('venta', 'regreso')) = (anotado_por is null)),
  constraint movimientos_inventario_clave check ((tipo in ('venta', 'regreso')) = (clave is null))
);

create index movimientos_inventario_historial_idx on public.movimientos_inventario (restaurante_id, ingrediente_id, created_at);
create index movimientos_inventario_venta_idx on public.movimientos_inventario (restaurante_id, venta_id);
create unique index movimientos_inventario_clave_unica on public.movimientos_inventario (restaurante_id, clave, ingrediente_id);
create index movimientos_inventario_producto_idx on public.movimientos_inventario (restaurante_id, producto_id);
create index movimientos_inventario_anotado_por_idx on public.movimientos_inventario (restaurante_id, anotado_por);

-- La existencia es la suma de los movimientos: cada uno la mueve al entrar.
create function privado.mover_existencia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ingredientes
  set existencia = existencia + new.cantidad
  where restaurante_id = new.restaurante_id and id = new.ingrediente_id;
  return null;
end;
$$;

create trigger movimientos_inventario_existencia
after insert on public.movimientos_inventario
for each row execute function privado.mover_existencia();


-- ─── venta_items.opciones lleva el id de cada opción ──────────────────────────
-- Lo pone este disparador al guardarse el renglón, buscando lo elegido entre los grupos del platillo, sin reescribir
-- mandar_a_cocina ni confirmar_pedido. Así se resta la receta de la opción aunque después le cambien el nombre. Un
-- renglón partido por cancelar_renglon ya trae sus ids.

create function privado.ids_de_opciones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if jsonb_array_length(new.opciones) = 0 or not exists (
    select 1 from jsonb_array_elements(new.opciones) e(x) where not (e.x ? 'id')
  ) then
    return new;
  end if;
  select coalesce(jsonb_agg(
    case when e.x ? 'id' then e.x else e.x || coalesce((
      select jsonb_build_object('id', o.id)
      from public.producto_grupos pg
      join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
      join public.opciones o on o.restaurante_id = g.restaurante_id and o.grupo_id = g.id
      where pg.restaurante_id = new.restaurante_id and pg.producto_id = new.producto_id
        and g.nombre = e.x ->> 'grupo' and o.nombre = e.x ->> 'opcion'
      order by g.id, o.id
      limit 1
    ), '{}') end
    order by e.n
  ), '[]')
  into new.opciones
  from jsonb_array_elements(new.opciones) with ordinality as e(x, n);
  return new;
end;
$$;

create trigger venta_items_ids_de_opciones
before insert on public.venta_items
for each row execute function privado.ids_de_opciones();

-- Las cuentas que siguen abiertas también guardan sus ids, para restar sus opciones al cerrarse. Las que ya estaban
-- cerradas no restan nada.
update public.venta_items vi
set opciones = (
  select coalesce(jsonb_agg(
    case when e.x ? 'id' then e.x else e.x || coalesce((
      select jsonb_build_object('id', o.id)
      from public.producto_grupos pg
      join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
      join public.opciones o on o.restaurante_id = g.restaurante_id and o.grupo_id = g.id
      where pg.restaurante_id = vi.restaurante_id and pg.producto_id = vi.producto_id
        and g.nombre = e.x ->> 'grupo' and o.nombre = e.x ->> 'opcion'
      order by g.id, o.id
      limit 1
    ), '{}') end
    order by e.n
  ), '[]')
  from jsonb_array_elements(vi.opciones) with ordinality as e(x, n)
)
from public.ventas v
where v.restaurante_id = vi.restaurante_id and v.id = vi.venta_id and v.estado = 'abierta'
  and jsonb_array_length(vi.opciones) > 0;


-- ─── Lo que lleva cada cosa, en ingredientes ──────────────────────────────────
-- LA forma de contar qué resta un platillo o una opción: por cada uno, cuánto de cada ingrediente en la unidad del
-- ingrediente. Una preparación resta su parte de cada ingrediente (30 ml de una salsa que rinde 1 litro, el 3 %).

create function privado.receta_en_ingredientes(p_restaurante_id uuid)
returns table (producto_id bigint, opcion_id bigint, ingrediente_id bigint, cantidad numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select r.producto_id, r.opcion_id, r.ingrediente_id, privado.convertir_unidad(r.cantidad, r.unidad, i.unidad)
  from public.recetas r
  join public.ingredientes i on i.restaurante_id = r.restaurante_id and i.id = r.ingrediente_id
  where r.restaurante_id = p_restaurante_id and r.preparacion_id is null and r.ingrediente_id is not null
  union all
  select r.producto_id, r.opcion_id, pr.ingrediente_id,
         privado.convertir_unidad(pr.cantidad, pr.unidad, i.unidad)
           * privado.convertir_unidad(r.cantidad, r.unidad, p.unidad) / p.rinde
  from public.recetas r
  join public.preparaciones p on p.restaurante_id = r.restaurante_id and p.id = r.lleva_preparacion_id
  join public.recetas pr on pr.restaurante_id = p.restaurante_id and pr.preparacion_id = p.id
  join public.ingredientes i on i.restaurante_id = pr.restaurante_id and i.id = pr.ingrediente_id
  where r.restaurante_id = p_restaurante_id and r.lleva_preparacion_id is not null;
$$;


-- ─── La cuenta que se cierra resta; la que se reabre regresa ──────────────────
-- Al cerrarse resta la receta de ese momento: un movimiento por ingrediente y por cuenta. Lo cancelado no resta. Al
-- reabrirse (un pago cancelado) regresa justo lo que había restado, aunque la receta haya cambiado.

create function privado.inventario_de_la_cuenta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.estado = 'cerrada' then
    insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, venta_id)
    select new.restaurante_id, m.ingrediente_id, 'regreso', -sum(m.cantidad), new.id
    from public.movimientos_inventario m
    where m.restaurante_id = new.restaurante_id and m.venta_id = new.id
    group by m.ingrediente_id
    having sum(m.cantidad) < 0;
  end if;

  if new.estado = 'cerrada' then
    with receta as materialized (
      select * from privado.receta_en_ingredientes(new.restaurante_id)
    ),
    lleva as (
      select x.ingrediente_id, x.cantidad * vi.cantidad as cantidad
      from public.venta_items vi
      join receta x on x.producto_id = vi.producto_id
      where vi.restaurante_id = new.restaurante_id and vi.venta_id = new.id and vi.estado = 'activo'
      union all
      select x.ingrediente_id, x.cantidad * vi.cantidad
      from public.venta_items vi
      cross join lateral jsonb_array_elements(vi.opciones) o(e)
      join receta x on x.opcion_id = (o.e ->> 'id')::bigint
      where vi.restaurante_id = new.restaurante_id and vi.venta_id = new.id and vi.estado = 'activo'
    )
    insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, venta_id)
    select new.restaurante_id, l.ingrediente_id, 'venta', -round(sum(l.cantidad), 3), new.id
    from lleva l
    group by l.ingrediente_id
    having round(sum(l.cantidad), 3) > 0;
  end if;
  return null;
end;
$$;

create trigger ventas_inventario
after update of estado on public.ventas
for each row
when (old.estado is distinct from new.estado and 'cerrada' in (old.estado, new.estado))
execute function privado.inventario_de_la_cuenta();


-- ─── Quién llama ──────────────────────────────────────────────────────────────

-- Las sucursales donde quien llama es cocina o gerente (la cocina, desde su aparato), con su licencia funcionando.
create function privado.mis_restaurantes_cocina()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.restaurante_id
  from public.miembros m
  join public.restaurantes r on r.id = m.restaurante_id
  where m.usuario_id = (select auth.uid())
    and m.activo
    and m.roles && array['cocina', 'gerente']
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria)
    and ('gerente' = any (m.roles) or privado.desde_su_aparato(m.restaurante_id, m.id));
$$;

-- El motivo de una merma, revisado; la nota, limpia.
create function privado.revisar_merma(p_motivo text, p_nota text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
begin
  if p_motivo is null or p_motivo not in ('se_echo_a_perder', 'se_cayo_o_quemo', 'caduco', 'otro') then
    raise exception 'Elige por qué se tiró' using errcode = '22023';
  end if;
  if p_motivo = 'otro' and v_nota is null then
    raise exception 'Con «Otro», cuenta qué pasó en la nota' using errcode = '22023';
  end if;
  if char_length(v_nota) > 200 then
    raise exception 'La nota va de hasta 200 letras' using errcode = '22023';
  end if;
  return v_nota;
end;
$$;


-- ─── Los ingredientes (el gerente) ────────────────────────────────────────────

-- Uno nuevo (sin p_id) con cuánto hay hoy, que es su primer conteo; o los datos de uno que ya existe (su unidad no
-- cambia). Con la misma clave, uno nuevo no se crea dos veces. Regresa su id.
create function public.guardar_ingrediente(
  p_restaurante_id uuid,
  p_nombre text,
  p_unidad text,
  p_por_caja numeric,
  p_minimo numeric,
  p_id bigint default null,
  p_hay numeric default null,
  p_clave uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.mi_miembro(p_restaurante_id, array['gerente']);
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_id bigint;
begin
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante cambia los ingredientes' using errcode = '42501';
  end if;
  if v_nombre = '' then
    raise exception 'Escribe el nombre del ingrediente' using errcode = '22023';
  end if;
  if p_por_caja is not null and p_por_caja <= 0 then
    raise exception 'Una caja trae más de 0' using errcode = '22023';
  end if;
  if p_minimo is not null and p_minimo <= 0 then
    raise exception 'El mínimo es más de 0' using errcode = '22023';
  end if;

  if p_id is null then
    if p_clave is null then
      raise exception 'Falta la clave del ingrediente nuevo' using errcode = '22023';
    end if;
    select m.ingrediente_id into v_id
    from public.movimientos_inventario m
    where m.restaurante_id = p_restaurante_id and m.clave = p_clave and m.tipo = 'conteo';
    if v_id is not null then
      return v_id;
    end if;
    if p_unidad is null or p_unidad not in ('kg', 'g', 'l', 'ml', 'pieza') then
      raise exception 'Elige en qué se cuenta' using errcode = '22023';
    end if;
    if p_hay is null or p_hay < 0 then
      raise exception 'Escribe cuánto hay hoy' using errcode = '22023';
    end if;
    begin
      insert into public.ingredientes (restaurante_id, nombre, unidad, por_caja, minimo)
      values (p_restaurante_id, v_nombre, p_unidad, p_por_caja, p_minimo)
      returning id into v_id;
    exception when unique_violation then
      raise exception 'Ya tienes un ingrediente que se llama «%»', v_nombre using errcode = '22023';
    end;
    insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, contado, anotado_por, clave)
    values (p_restaurante_id, v_id, 'conteo', round(p_hay, 3), round(p_hay, 3), v_miembro, p_clave);
    return v_id;
  end if;

  begin
    update public.ingredientes
    set nombre = v_nombre, unidad = coalesce(p_unidad, unidad), por_caja = p_por_caja, minimo = p_minimo
    where restaurante_id = p_restaurante_id and id = p_id and archivado_at is null
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya tienes un ingrediente que se llama «%»', v_nombre using errcode = '22023';
  end;
  if v_id is null then
    raise exception 'Ese ingrediente ya no está' using errcode = '22023';
  end if;
  return v_id;
end;
$$;

-- Ya no se usa: sale de las recetas que lo llevan y de la vista. Su historial se queda. Regresa de cuántas recetas
-- salió.
create function public.archivar_ingrediente(p_restaurante_id uuid, p_id bigint)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.mi_miembro(p_restaurante_id, array['gerente']);
  v_n integer;
begin
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante cambia los ingredientes' using errcode = '42501';
  end if;
  perform 1 from public.ingredientes
  where restaurante_id = p_restaurante_id and id = p_id and archivado_at is null
  for update;
  if not found then
    raise exception 'Ese ingrediente ya no está' using errcode = '22023';
  end if;
  delete from public.recetas where restaurante_id = p_restaurante_id and ingrediente_id = p_id;
  get diagnostics v_n = row_count;
  update public.ingredientes set archivado_at = now() where restaurante_id = p_restaurante_id and id = p_id;
  return v_n;
end;
$$;


-- ─── Las recetas (el gerente) ─────────────────────────────────────────────────

-- Guarda los renglones de una receta, ya revisados, para su dueño (uno de los tres). Cada renglón trae
-- ingrediente_id o preparacion_id, cantidad y unidad. Reemplaza los que había.
create function privado.poner_receta(
  p_restaurante_id uuid,
  p_producto_id bigint,
  p_opcion_id bigint,
  p_preparacion_id bigint,
  p_renglones jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_renglon jsonb;
  v_n integer := 0;
begin
  if p_renglones is null or jsonb_typeof(p_renglones) <> 'array' then
    raise exception 'La receta llega como una lista' using errcode = '22023';
  end if;
  delete from public.recetas
  where restaurante_id = p_restaurante_id
    and producto_id is not distinct from p_producto_id
    and opcion_id is not distinct from p_opcion_id
    and preparacion_id is not distinct from p_preparacion_id;
  for v_renglon in select x from jsonb_array_elements(p_renglones) x loop
    if p_preparacion_id is not null and (v_renglon ->> 'preparacion_id') is not null then
      raise exception 'Una preparación lleva solo ingredientes' using errcode = '22023';
    end if;
    if (v_renglon ->> 'cantidad') is null or (v_renglon ->> 'cantidad')::numeric <= 0 then
      raise exception 'Cada renglón lleva una cantidad de más de 0' using errcode = '22023';
    end if;
    if (v_renglon ->> 'unidad') is null or (v_renglon ->> 'unidad') not in ('kg', 'g', 'l', 'ml', 'pieza') then
      raise exception 'Cada renglón lleva su unidad' using errcode = '22023';
    end if;
    if num_nonnulls(v_renglon ->> 'ingrediente_id', v_renglon ->> 'preparacion_id') <> 1 then
      raise exception 'Cada renglón lleva un ingrediente o una preparación' using errcode = '22023';
    end if;
    if (v_renglon ->> 'preparacion_id') is not null and not exists (
      select 1 from public.preparaciones
      where restaurante_id = p_restaurante_id and id = (v_renglon ->> 'preparacion_id')::bigint
    ) then
      raise exception 'Esa preparación ya no está' using errcode = '22023';
    end if;
    begin
      insert into public.recetas (restaurante_id, producto_id, opcion_id, preparacion_id, ingrediente_id,
                                  lleva_preparacion_id, cantidad, unidad)
      values (p_restaurante_id, p_producto_id, p_opcion_id, p_preparacion_id,
              (v_renglon ->> 'ingrediente_id')::bigint, (v_renglon ->> 'preparacion_id')::bigint,
              (v_renglon ->> 'cantidad')::numeric, v_renglon ->> 'unidad');
    exception when unique_violation then
      raise exception 'Un ingrediente o una preparación va una sola vez en la receta' using errcode = '22023';
    end;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Lo que lleva un platillo de Mi menú o una opción de un grupo, para uno. Sin renglones, se queda sin receta y no
-- resta nada. Regresa cuántos renglones quedaron.
create function public.guardar_receta(
  p_restaurante_id uuid,
  p_renglones jsonb,
  p_producto_id bigint default null,
  p_opcion_id bigint default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante cambia las recetas' using errcode = '42501';
  end if;
  if num_nonnulls(p_producto_id, p_opcion_id) <> 1 then
    raise exception 'La receta es de un platillo o de una opción' using errcode = '22023';
  end if;
  if p_producto_id is not null then
    perform 1 from public.productos
    where restaurante_id = p_restaurante_id and id = p_producto_id and archivado_at is null
    for update;
    if not found then
      raise exception 'Ese platillo ya no está' using errcode = '22023';
    end if;
  else
    perform 1 from public.opciones where restaurante_id = p_restaurante_id and id = p_opcion_id for update;
    if not found then
      raise exception 'Esa opción ya no está' using errcode = '22023';
    end if;
  end if;
  return privado.poner_receta(p_restaurante_id, p_producto_id, p_opcion_id, null, p_renglones);
end;
$$;

-- Una preparación nueva (sin p_id) o una que ya existe, con su receta para lo que rinde. Si ya la llevan platillos,
-- su unidad no cambia de familia. Regresa su id.
create function public.guardar_preparacion(
  p_restaurante_id uuid,
  p_nombre text,
  p_rinde numeric,
  p_unidad text,
  p_renglones jsonb,
  p_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_id bigint;
  v_antes text;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante cambia las preparaciones' using errcode = '42501';
  end if;
  if v_nombre = '' then
    raise exception 'Escribe el nombre de la preparación' using errcode = '22023';
  end if;
  if p_rinde is null or p_rinde <= 0 then
    raise exception 'Escribe cuánto rinde' using errcode = '22023';
  end if;
  if p_unidad is null or p_unidad not in ('kg', 'g', 'l', 'ml', 'pieza') then
    raise exception 'Elige en qué se mide lo que rinde' using errcode = '22023';
  end if;
  begin
    if p_id is null then
      insert into public.preparaciones (restaurante_id, nombre, rinde, unidad)
      values (p_restaurante_id, v_nombre, p_rinde, p_unidad)
      returning id into v_id;
    else
      select unidad into v_antes from public.preparaciones
      where restaurante_id = p_restaurante_id and id = p_id
      for update;
      if v_antes is null then
        raise exception 'Esa preparación ya no está' using errcode = '22023';
      end if;
      if privado.familia_unidad(v_antes) <> privado.familia_unidad(p_unidad) and exists (
        select 1 from public.recetas where restaurante_id = p_restaurante_id and lleva_preparacion_id = p_id
      ) then
        raise exception 'Ya la llevan platillos: lo que rinde sigue en la misma familia de unidades' using errcode = '22023';
      end if;
      update public.preparaciones
      set nombre = v_nombre, rinde = p_rinde, unidad = p_unidad
      where restaurante_id = p_restaurante_id and id = p_id
      returning id into v_id;
    end if;
  exception when unique_violation then
    raise exception 'Ya tienes una preparación que se llama «%»', v_nombre using errcode = '22023';
  end;
  perform privado.poner_receta(p_restaurante_id, null, null, v_id, p_renglones);
  return v_id;
end;
$$;

-- Se va con su receta y sale de los platillos y opciones que la llevaban. Regresa de cuántos salió.
create function public.eliminar_preparacion(p_restaurante_id uuid, p_id bigint)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante cambia las preparaciones' using errcode = '42501';
  end if;
  select count(*) into v_n from public.recetas where restaurante_id = p_restaurante_id and lleva_preparacion_id = p_id;
  delete from public.preparaciones where restaurante_id = p_restaurante_id and id = p_id;
  if not found then
    raise exception 'Esa preparación ya no está' using errcode = '22023';
  end if;
  return v_n;
end;
$$;


-- ─── Lo que llegó y las mermas (el gerente y la cocina) ───────────────────────

-- Lo que llegó, en renglones {ingrediente_id, cantidad} o {ingrediente_id, cajas}; las cajas, solo si el ingrediente
-- dice cuánto trae una. Con la misma clave no se anota dos veces. Regresa cuántos renglones.
create function public.anotar_llegada(p_restaurante_id uuid, p_clave uuid, p_renglones jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.mi_miembro(p_restaurante_id, array['gerente', 'cocina']);
  v_renglon jsonb;
  v_ing record;
  v_cajas integer;
  v_cantidad numeric;
  v_n integer := 0;
begin
  if v_miembro is null then
    raise exception 'Solo el gerente y la cocina de este restaurante anotan lo que llegó' using errcode = '42501';
  end if;
  if p_clave is null then
    raise exception 'Falta la clave de lo que llegó' using errcode = '22023';
  end if;
  select count(*) into v_n from public.movimientos_inventario where restaurante_id = p_restaurante_id and clave = p_clave;
  if v_n > 0 then
    return v_n;
  end if;
  if p_renglones is null or jsonb_typeof(p_renglones) <> 'array' or jsonb_array_length(p_renglones) = 0 then
    raise exception 'Anota al menos un ingrediente' using errcode = '22023';
  end if;
  for v_renglon in select x from jsonb_array_elements(p_renglones) x loop
    select id, nombre, por_caja into v_ing
    from public.ingredientes
    where restaurante_id = p_restaurante_id and id = (v_renglon ->> 'ingrediente_id')::bigint and archivado_at is null;
    if v_ing.id is null then
      raise exception 'Ese ingrediente ya no está' using errcode = '22023';
    end if;
    v_cajas := (v_renglon ->> 'cajas')::integer;
    v_cantidad := (v_renglon ->> 'cantidad')::numeric;
    if num_nonnulls(v_cajas, v_cantidad) <> 1 then
      raise exception 'De «%», anota cuánto o cuántas cajas', v_ing.nombre using errcode = '22023';
    end if;
    if v_cajas is not null then
      if v_ing.por_caja is null then
        raise exception '«%» no dice cuánto trae una caja: anótalo en su unidad', v_ing.nombre using errcode = '22023';
      end if;
      if v_cajas <= 0 then
        raise exception 'De «%», anota más de 0 cajas', v_ing.nombre using errcode = '22023';
      end if;
      v_cantidad := v_cajas * v_ing.por_caja;
    elsif round(v_cantidad, 3) <= 0 then
      raise exception 'De «%», anota más de 0', v_ing.nombre using errcode = '22023';
    end if;
    begin
      insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, cajas, anotado_por, clave)
      values (p_restaurante_id, v_ing.id, 'llegada', round(v_cantidad, 3), v_cajas, v_miembro, p_clave);
    exception when unique_violation then
      raise exception '«%» va una sola vez: suma lo que llegó en un renglón', v_ing.nombre using errcode = '22023';
    end;
  end loop;
  return jsonb_array_length(p_renglones);
end;
$$;

-- Lo que se tiró, con su motivo: un ingrediente (p_ingrediente_id y p_cantidad, en su unidad) o un platillo entero
-- (p_producto_id y p_platillos), que resta su receta sin opciones, un movimiento por ingrediente con la misma clave.
-- Con la misma clave no se anota dos veces. Regresa cuántos movimientos.
create function public.anotar_merma(
  p_restaurante_id uuid,
  p_clave uuid,
  p_motivo text,
  p_nota text default null,
  p_ingrediente_id bigint default null,
  p_cantidad numeric default null,
  p_producto_id bigint default null,
  p_platillos integer default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.mi_miembro(p_restaurante_id, array['gerente', 'cocina']);
  v_nota text;
  v_n integer;
begin
  if v_miembro is null then
    raise exception 'Solo el gerente y la cocina de este restaurante anotan mermas' using errcode = '42501';
  end if;
  if p_clave is null then
    raise exception 'Falta la clave de la merma' using errcode = '22023';
  end if;
  select count(*) into v_n from public.movimientos_inventario where restaurante_id = p_restaurante_id and clave = p_clave;
  if v_n > 0 then
    return v_n;
  end if;
  v_nota := privado.revisar_merma(p_motivo, p_nota);

  if p_producto_id is null then
    if p_ingrediente_id is null or p_platillos is not null then
      raise exception 'Elige qué se tiró' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.ingredientes
      where restaurante_id = p_restaurante_id and id = p_ingrediente_id and archivado_at is null
    ) then
      raise exception 'Ese ingrediente ya no está' using errcode = '22023';
    end if;
    if p_cantidad is null or round(p_cantidad, 3) <= 0 then
      raise exception 'Anota cuánto se tiró' using errcode = '22023';
    end if;
    insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, motivo, nota, anotado_por, clave)
    values (p_restaurante_id, p_ingrediente_id, 'merma', -round(p_cantidad, 3), p_motivo, v_nota, v_miembro, p_clave);
    return 1;
  end if;

  if p_ingrediente_id is not null or p_cantidad is not null then
    raise exception 'Elige un ingrediente o un platillo, no los dos' using errcode = '22023';
  end if;
  if p_platillos is null or p_platillos <= 0 then
    raise exception 'Anota cuántos se tiraron' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.productos
    where restaurante_id = p_restaurante_id and id = p_producto_id and archivado_at is null and not es_envio
  ) then
    raise exception 'Ese platillo ya no está' using errcode = '22023';
  end if;
  insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, motivo, nota, producto_id,
                                             platillos, anotado_por, clave)
  select p_restaurante_id, x.ingrediente_id, 'merma', -round(sum(x.cantidad) * p_platillos, 3), p_motivo, v_nota,
         p_producto_id, p_platillos, v_miembro, p_clave
  from privado.receta_en_ingredientes(p_restaurante_id) x
  where x.producto_id = p_producto_id
  group by x.ingrediente_id
  having round(sum(x.cantidad) * p_platillos, 3) > 0;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Ese platillo no tiene receta: anota sus ingredientes uno por uno' using errcode = '22023';
  end if;
  return v_n;
end;
$$;

-- Los platillos que se pueden anotar como merma entera: los de Mi menú con receta, en el orden del menú.
create function public.platillos_para_merma(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente', 'cocina']) is null then
    raise exception 'Solo el gerente y la cocina de este restaurante anotan mermas' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre) order by c.orden, c.id, p.orden, p.id)
    from public.productos p
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where p.restaurante_id = p_restaurante_id and p.archivado_at is null and not p.es_envio
      and exists (select 1 from public.recetas r where r.restaurante_id = p.restaurante_id and r.producto_id = p.id)
  ), '[]');
end;
$$;

-- Lo que resta la merma de p_platillos de un platillo, como está escrita su receta («300 g de Pastor · 90 ml de Salsa
-- verde»), para enseñarlo antes de anotarla.
create function public.lo_que_resta(p_restaurante_id uuid, p_producto_id bigint, p_platillos integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente', 'cocina']) is null then
    raise exception 'Solo el gerente y la cocina de este restaurante anotan mermas' using errcode = '42501';
  end if;
  if p_platillos is null or p_platillos <= 0 then
    raise exception 'Anota cuántos se tiraron' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'nombre', coalesce(i.nombre, pr.nombre),
      'cantidad', r.cantidad * p_platillos,
      'unidad', r.unidad,
      'preparacion', r.lleva_preparacion_id is not null
    ) order by r.id)
    from public.recetas r
    left join public.ingredientes i on i.restaurante_id = r.restaurante_id and i.id = r.ingrediente_id
    left join public.preparaciones pr on pr.restaurante_id = r.restaurante_id and pr.id = r.lleva_preparacion_id
    where r.restaurante_id = p_restaurante_id and r.producto_id = p_producto_id
  ), '[]');
end;
$$;


-- ─── Contar y «Deshacer» (el gerente) ─────────────────────────────────────────

-- Lo contado, en renglones {ingrediente_id, contado}: reemplaza lo que decía el sistema y la diferencia queda como
-- pérdida (o sobrante). Un conteo de todos comparte su clave. Con la misma clave no se anota dos veces.
create function public.anotar_conteo(p_restaurante_id uuid, p_clave uuid, p_conteos jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.mi_miembro(p_restaurante_id, array['gerente']);
  v_conteo jsonb;
  v_ing record;
  v_contado numeric;
  v_n integer;
begin
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante cuenta' using errcode = '42501';
  end if;
  if p_clave is null then
    raise exception 'Falta la clave del conteo' using errcode = '22023';
  end if;
  select count(*) into v_n from public.movimientos_inventario where restaurante_id = p_restaurante_id and clave = p_clave;
  if v_n > 0 then
    return v_n;
  end if;
  if p_conteos is null or jsonb_typeof(p_conteos) <> 'array' or jsonb_array_length(p_conteos) = 0 then
    raise exception 'Cuenta al menos un ingrediente' using errcode = '22023';
  end if;
  for v_conteo in select x from jsonb_array_elements(p_conteos) x loop
    select id, nombre, existencia into v_ing
    from public.ingredientes
    where restaurante_id = p_restaurante_id and id = (v_conteo ->> 'ingrediente_id')::bigint and archivado_at is null
    for update;
    if v_ing.id is null then
      raise exception 'Ese ingrediente ya no está' using errcode = '22023';
    end if;
    v_contado := round((v_conteo ->> 'contado')::numeric, 3);
    if v_contado is null or v_contado < 0 then
      raise exception 'De «%», escribe cuánto hay', v_ing.nombre using errcode = '22023';
    end if;
    begin
      insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, contado, anotado_por, clave)
      values (p_restaurante_id, v_ing.id, 'conteo', v_contado - v_ing.existencia, v_contado, v_miembro, p_clave);
    exception when unique_violation then
      raise exception '«%» va una sola vez en el conteo', v_ing.nombre using errcode = '22023';
    end;
  end loop;
  return jsonb_array_length(p_conteos);
end;
$$;

-- Anula una llegada, una merma o un conteo con un movimiento contrario; los dos se ven tachados. La merma de un
-- platillo se deshace entera. Una venta no: se regresa cancelando su pago. Regresa cuántos movimientos anuló.
create function public.deshacer_movimiento(p_restaurante_id uuid, p_movimiento_id bigint, p_clave uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint := privado.mi_miembro(p_restaurante_id, array['gerente']);
  v_mov record;
  v_n integer;
begin
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante deshace' using errcode = '42501';
  end if;
  if p_clave is null then
    raise exception 'Falta la clave de «Deshacer»' using errcode = '22023';
  end if;
  select count(*) into v_n from public.movimientos_inventario where restaurante_id = p_restaurante_id and clave = p_clave;
  if v_n > 0 then
    return v_n;
  end if;
  select id, tipo, clave, producto_id into v_mov
  from public.movimientos_inventario
  where restaurante_id = p_restaurante_id and id = p_movimiento_id
  for update;
  if v_mov.id is null then
    raise exception 'Ese movimiento no está' using errcode = '22023';
  end if;
  if v_mov.tipo in ('venta', 'regreso') then
    raise exception 'Una venta se regresa cancelando su pago' using errcode = '22023';
  end if;
  if v_mov.tipo = 'deshacer' then
    raise exception 'Eso ya es un «Deshacer»' using errcode = '22023';
  end if;
  if exists (select 1 from public.movimientos_inventario where restaurante_id = p_restaurante_id and deshace_id = v_mov.id) then
    raise exception 'Eso ya se deshizo' using errcode = '22023';
  end if;

  insert into public.movimientos_inventario (restaurante_id, ingrediente_id, tipo, cantidad, deshace_id, anotado_por, clave)
  select m.restaurante_id, m.ingrediente_id, 'deshacer', -m.cantidad, m.id, v_miembro, p_clave
  from public.movimientos_inventario m
  where m.restaurante_id = p_restaurante_id
    and (m.id = v_mov.id
         or (v_mov.producto_id is not null and m.tipo = 'merma' and m.clave = v_mov.clave
             and m.producto_id = v_mov.producto_id))
    and not exists (select 1 from public.movimientos_inventario d where d.restaurante_id = m.restaurante_id and d.deshace_id = m.id);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;


-- ─── Agotado (el gerente, la cocina y la caja) ────────────────────────────────
-- El ojito de la vista chiquita de Mi menú en el aparato: solo cambia visible. Regresa cómo quedó.
create function public.marcar_agotado(p_restaurante_id uuid, p_producto_id bigint, p_agotado boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visible boolean;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente', 'cocina', 'caja']) is null then
    raise exception 'Solo el gerente, la cocina y la caja de este restaurante marcan un platillo agotado' using errcode = '42501';
  end if;
  if p_agotado is null then
    raise exception 'Di si está agotado' using errcode = '22023';
  end if;
  update public.productos
  set visible = not p_agotado
  where restaurante_id = p_restaurante_id and id = p_producto_id and archivado_at is null and not es_envio
  returning visible into v_visible;
  if v_visible is null then
    raise exception 'Ese platillo ya no está' using errcode = '22023';
  end if;
  return v_visible;
end;
$$;


-- ─── Permisos, RLS y tiempo real ──────────────────────────────────────────────
-- Los ingredientes los leen el gerente y la cocina; las preparaciones, las recetas y los movimientos, solo el
-- gerente. Nadie escribe directo, ni el Worker.

alter table public.ingredientes enable row level security;
alter table public.preparaciones enable row level security;
alter table public.recetas enable row level security;
alter table public.movimientos_inventario enable row level security;

revoke all on table public.ingredientes, public.preparaciones, public.recetas, public.movimientos_inventario
  from anon, authenticated, service_role;
revoke all on sequence public.ingredientes_id_seq, public.preparaciones_id_seq, public.recetas_id_seq,
  public.movimientos_inventario_id_seq from anon, authenticated, service_role;

grant select (
  id, restaurante_id, nombre, unidad, por_caja, minimo, existencia, archivado_at, created_at, updated_at
) on public.ingredientes to authenticated;

grant select (
  id, restaurante_id, nombre, rinde, unidad, created_at, updated_at
) on public.preparaciones to authenticated;

grant select (
  id, restaurante_id, producto_id, opcion_id, preparacion_id, ingrediente_id, lleva_preparacion_id, cantidad, unidad,
  created_at
) on public.recetas to authenticated;

grant select (
  id, restaurante_id, ingrediente_id, tipo, cantidad, contado, cajas, motivo, nota, venta_id, producto_id, platillos,
  deshace_id, anotado_por, clave, created_at
) on public.movimientos_inventario to authenticated;

create policy "El gerente y la cocina leen los ingredientes de sus restaurantes que funcionan"
on public.ingredientes for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_cocina()));

create policy "El gerente lee las preparaciones de sus restaurantes que funcionan"
on public.preparaciones for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "El gerente lee las recetas de sus restaurantes que funcionan"
on public.recetas for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()));

create policy "El gerente lee los movimientos del inventario de sus restaurantes que funcionan"
on public.movimientos_inventario for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.ingredientes, public.productos;
  end if;
end;
$$;

revoke execute on function
  privado.familia_unidad(text),
  privado.convertir_unidad(numeric, text, text),
  privado.unidad_fija(),
  privado.revisar_receta(),
  privado.mover_existencia(),
  privado.ids_de_opciones(),
  privado.receta_en_ingredientes(uuid),
  privado.inventario_de_la_cuenta(),
  privado.mis_restaurantes_cocina(),
  privado.revisar_merma(text, text),
  privado.poner_receta(uuid, bigint, bigint, bigint, jsonb)
from public, anon, authenticated, service_role;

-- La política de ingredientes la usa con la sesión de quien lee.
grant execute on function privado.mis_restaurantes_cocina() to authenticated;

revoke execute on function
  public.guardar_ingrediente(uuid, text, text, numeric, numeric, bigint, numeric, uuid),
  public.archivar_ingrediente(uuid, bigint),
  public.guardar_receta(uuid, jsonb, bigint, bigint),
  public.guardar_preparacion(uuid, text, numeric, text, jsonb, bigint),
  public.eliminar_preparacion(uuid, bigint),
  public.anotar_llegada(uuid, uuid, jsonb),
  public.anotar_merma(uuid, uuid, text, text, bigint, numeric, bigint, integer),
  public.platillos_para_merma(uuid),
  public.lo_que_resta(uuid, bigint, integer),
  public.anotar_conteo(uuid, uuid, jsonb),
  public.deshacer_movimiento(uuid, bigint, uuid),
  public.marcar_agotado(uuid, bigint, boolean)
from public, anon, service_role;

grant execute on function
  public.guardar_ingrediente(uuid, text, text, numeric, numeric, bigint, numeric, uuid),
  public.archivar_ingrediente(uuid, bigint),
  public.guardar_receta(uuid, jsonb, bigint, bigint),
  public.guardar_preparacion(uuid, text, numeric, text, jsonb, bigint),
  public.eliminar_preparacion(uuid, bigint),
  public.anotar_llegada(uuid, uuid, jsonb),
  public.anotar_merma(uuid, uuid, text, text, bigint, numeric, bigint, integer),
  public.platillos_para_merma(uuid),
  public.lo_que_resta(uuid, bigint, integer),
  public.anotar_conteo(uuid, uuid, jsonb),
  public.deshacer_movimiento(uuid, bigint, uuid),
  public.marcar_agotado(uuid, bigint, boolean)
to authenticated;
