-- La tarjeta de lealtad (23 de noviembre de 2026; parte B de planes/trabajo/tarjeta-lealtad/): los sellos o los puntos que
-- juntan los clientes de cada sucursal para ganarse un premio. Lo decidido: las encuestas de encuestas.md, el Diccionario
-- de diccionario.md (libreta 2, revs 137 y 138) con el estilo y el color de diccionario-estilo-color.md (rev 139), y la
-- parte de la tarjeta en el aviso de aviso.md. Lo que decidió esta migración, en migracion.md.
--
-- Cinco tablas nuevas: lealtad (la regla de cada sucursal), tarjetas_lealtad, movimientos_lealtad, codigos_lealtad y
-- solicitudes_lealtad; y dos columnas: ventas.tarjeta_lealtad_id y pedidos_en_linea.premio_tarjeta_id. Nadie lee ni
-- escribe las tarjetas directo: el gerente, quien cobra y el Worker (para el menú) lo hacen por sus funciones.
--
-- La tarjeta suma sola con un disparador de ventas, como el inventario: al cerrarse pagada una cuenta que la lleva, y le
-- quita lo sumado si un pago cancelado la reabre. El premio entra a la cuenta con lo que ya tiene el punto de venta (el
-- descuento del renglón al 100 % o el descuento en pesos de la cuenta, con el motivo «Premio de la tarjeta»), y otro
-- disparador lo regresa a la tarjeta si sale de la cuenta. En un pedido del menú, el premio entra al confirmarse, con
-- un disparador de pedidos_en_linea. Se reescribe hacer_pedido, con el ok del developer (23 nov 2026): gana la llave de
-- la tarjeta, opcional. No se reescriben confirmar_pedido, cobrar ni mandar_a_cocina.


-- ─── lealtad ──────────────────────────────────────────────────────────────────
-- La regla de la tarjeta de cada sucursal y cómo se ve. Nace la primera vez que el gerente guarda algo en «Tarjeta de
-- lealtad»: en Metal, negra y apagada. Su regla tiene dos partes que se guardan juntas: los números (cuántos pide el
-- premio, y el mínimo con sellos o los pesos por punto con puntos) y el premio. Sin las dos no se prende.

create table public.lealtad (
  restaurante_id uuid primary key references public.restaurantes (id) on delete cascade,
  prendida boolean not null default false,
  forma text not null default 'sellos' constraint lealtad_forma_valida check (forma in ('sellos', 'puntos')),
  meta integer constraint lealtad_meta_valida check (meta > 0),
  minimo numeric(12,2) constraint lealtad_minimo_valido check (minimo >= 0),
  pesos_por_punto numeric(12,2) constraint lealtad_pesos_por_punto_valido check (pesos_por_punto > 0),
  premio_tipo text constraint lealtad_premio_tipo_valido check (premio_tipo in ('producto', 'pesos')),
  premio_producto_id bigint,
  premio_pesos numeric(12,2) constraint lealtad_premio_pesos_valido check (premio_pesos > 0),
  estilo text not null default 'metal'
    constraint lealtad_estilo_valido check (estilo in ('liquido', 'agua', 'metal', 'brillante', 'liso', 'olas')),
  color text default '#121212' constraint lealtad_color_formato check (color ~ '^#[0-9A-F]{6}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Sin borrado en cascada: como el premio lo apunta, «Eliminar producto» lo archiva en vez de borrarlo.
  foreign key (restaurante_id, premio_producto_id) references public.productos (restaurante_id, id),
  constraint lealtad_numeros check (
    case
      when meta is null then minimo is null and pesos_por_punto is null
      when forma = 'sellos' then meta between 2 and 20 and minimo is not null and pesos_por_punto is null
      else meta <= 10000 and pesos_por_punto is not null and minimo is null
    end
  ),
  constraint lealtad_premio check (
    case premio_tipo
      when 'producto' then premio_producto_id is not null and premio_pesos is null
      when 'pesos' then premio_pesos is not null and premio_producto_id is null
      else premio_producto_id is null and premio_pesos is null
    end
  ),
  constraint lealtad_prendida_con_regla check (not prendida or (meta is not null and premio_tipo is not null))
);

create index lealtad_premio_producto_idx on public.lealtad (restaurante_id, premio_producto_id);

create trigger lealtad_updated_at
before update on public.lealtad
for each row execute function privado.set_updated_at();


-- ─── tarjetas_lealtad ─────────────────────────────────────────────────────────
-- La tarjeta de cada cliente en una sucursal: una por teléfono. Solo las huellas de su llave y de su código corto.

create table public.tarjetas_lealtad (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null
    constraint tarjetas_lealtad_nombre_valido check (btrim(nombre) <> '' and char_length(nombre) <= 60),
  telefono text not null constraint tarjetas_lealtad_telefono_valido check (telefono ~ '^[0-9]{10}$'),
  llave_hash text not null constraint tarjetas_lealtad_llave_hash_valida check (llave_hash ~ '^[0-9a-f]{64}$'),
  codigo_hash text not null constraint tarjetas_lealtad_codigo_hash_valido check (codigo_hash ~ '^[0-9a-f]{64}$'),
  saldo integer not null default 0,
  aviso_aceptado_at timestamptz not null,
  ultima_compra_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  constraint tarjetas_lealtad_telefono_unico unique (restaurante_id, telefono),
  constraint tarjetas_lealtad_llave_unica unique (llave_hash),
  constraint tarjetas_lealtad_codigo_unico unique (restaurante_id, codigo_hash)
);

create trigger tarjetas_lealtad_updated_at
before update on public.tarjetas_lealtad
for each row execute function privado.set_updated_at();


-- ─── movimientos_lealtad ──────────────────────────────────────────────────────
-- Cada cosa que sube o baja una tarjeta; su saldo es la suma. No se editan, y solo se van con su tarjeta.

create table public.movimientos_lealtad (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  tarjeta_id bigint not null,
  tipo text not null
    constraint movimientos_lealtad_tipo_valido check (tipo in ('compra', 'regreso', 'canje', 'devolucion', 'reinicio')),
  cantidad integer not null,
  venta_id bigint,
  venta_item_id bigint,
  canje_id bigint constraint movimientos_lealtad_canje_unico unique,
  anotado_por bigint,
  clave uuid,
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, tarjeta_id) references public.tarjetas_lealtad (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, venta_id) references public.ventas (restaurante_id, id),
  foreign key (restaurante_id, venta_item_id) references public.venta_items (restaurante_id, id),
  foreign key (restaurante_id, canje_id) references public.movimientos_lealtad (restaurante_id, id) on delete cascade,
  foreign key (restaurante_id, anotado_por) references public.miembros (restaurante_id, id),
  constraint movimientos_lealtad_signo check (
    case tipo
      when 'compra' then cantidad > 0
      when 'devolucion' then cantidad > 0
      when 'regreso' then cantidad < 0
      when 'canje' then cantidad < 0
      else cantidad <> 0
    end
  ),
  constraint movimientos_lealtad_venta check ((tipo = 'reinicio') = (venta_id is null)),
  constraint movimientos_lealtad_renglon check (venta_item_id is null or tipo in ('canje', 'devolucion')),
  constraint movimientos_lealtad_canje check ((tipo = 'devolucion') = (canje_id is not null)),
  constraint movimientos_lealtad_anotado check ((tipo in ('canje', 'reinicio')) = (anotado_por is not null)),
  constraint movimientos_lealtad_clave check ((tipo = 'canje') = (clave is not null))
);

create index movimientos_lealtad_historial_idx on public.movimientos_lealtad (restaurante_id, tarjeta_id, created_at);
create index movimientos_lealtad_venta_idx on public.movimientos_lealtad (restaurante_id, venta_id);
create unique index movimientos_lealtad_clave_unica on public.movimientos_lealtad (restaurante_id, clave);
create index movimientos_lealtad_renglon_idx on public.movimientos_lealtad (restaurante_id, venta_item_id);
create index movimientos_lealtad_anotado_por_idx on public.movimientos_lealtad (restaurante_id, anotado_por);

-- El saldo es la suma de los movimientos: cada uno lo mueve al entrar.
create function privado.mover_saldo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.tarjetas_lealtad
  set saldo = saldo + new.cantidad
  where restaurante_id = new.restaurante_id and id = new.tarjeta_id;
  return null;
end;
$$;

create trigger movimientos_lealtad_saldo
after insert on public.movimientos_lealtad
for each row execute function privado.mover_saldo();


-- ─── codigos_lealtad ──────────────────────────────────────────────────────────
-- El código de 6 letras para pasar una tarjeta a otro celular, con la llave y el código corto que ya guarda el
-- celular nuevo. Dura 10 minutos, sirve una vez y hay uno por tarjeta. Sin I, L ni O, como el de vincular un aparato.

create table public.codigos_lealtad (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  tarjeta_id bigint not null constraint codigos_lealtad_tarjeta_unica unique,
  codigo text not null constraint codigos_lealtad_codigo_formato check (codigo ~ '^[A-HJKMNP-Z]{6}$'),
  llave_hash text not null constraint codigos_lealtad_llave_hash_valida check (llave_hash ~ '^[0-9a-f]{64}$'),
  codigo_hash text not null constraint codigos_lealtad_codigo_hash_valido check (codigo_hash ~ '^[0-9a-f]{64}$'),
  expira_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (restaurante_id, id),
  constraint codigos_lealtad_codigo_unico unique (restaurante_id, codigo),
  foreign key (restaurante_id, tarjeta_id) references public.tarjetas_lealtad (restaurante_id, id) on delete cascade,
  constraint codigos_lealtad_expira check (expira_at > created_at)
);

create index codigos_lealtad_expira_idx on public.codigos_lealtad (expira_at);


-- ─── solicitudes_lealtad ──────────────────────────────────────────────────────
-- Una fila por cada vez que el menú saca una tarjeta o pide un código, solo para contar los límites. Vive una hora.

create table public.solicitudes_lealtad (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  marca_celular text not null
    constraint solicitudes_lealtad_marca_celular check (marca_celular ~ '^[0-9a-f]{64}$'),
  marca_conexion text not null
    constraint solicitudes_lealtad_marca_conexion check (marca_conexion ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create index solicitudes_lealtad_celular_idx on public.solicitudes_lealtad (restaurante_id, marca_celular, created_at);
create index solicitudes_lealtad_conexion_idx on public.solicitudes_lealtad (restaurante_id, marca_conexion, created_at);
create index solicitudes_lealtad_fecha_idx on public.solicitudes_lealtad (created_at);


-- ─── ventas y pedidos_en_linea: la tarjeta ────────────────────────────────────
-- Las dos se vacían solas si la tarjeta se borra (solo esa columna: el restaurante se queda).

alter table public.ventas
  add column tarjeta_lealtad_id bigint,
  add foreign key (restaurante_id, tarjeta_lealtad_id)
    references public.tarjetas_lealtad (restaurante_id, id) on delete set null (tarjeta_lealtad_id);

create index ventas_tarjeta_lealtad_idx on public.ventas (restaurante_id, tarjeta_lealtad_id);

-- «Paga con» ya no se compara con el total en la tabla: con un premio en pesos se compara con el total menos el premio,
-- y eso lo revisa hacer_pedido (el premio puede cambiar o su tarjeta borrarse después).
alter table public.pedidos_en_linea
  add column premio_tarjeta_id bigint,
  add foreign key (restaurante_id, premio_tarjeta_id)
    references public.tarjetas_lealtad (restaurante_id, id) on delete set null (premio_tarjeta_id),
  drop constraint pedidos_en_linea_paga_con,
  add constraint pedidos_en_linea_paga_con check (paga_con > 0);

create index pedidos_en_linea_premio_tarjeta_idx on public.pedidos_en_linea (restaurante_id, premio_tarjeta_id);


-- ─── bitacora: el canje y el cambio de celular ────────────────────────────────

alter table public.bitacora drop constraint bitacora_accion_valida;
alter table public.bitacora add constraint bitacora_accion_valida
  check (accion in ('cambiar_mesa', 'juntar_mesas', 'retiro', 'ingreso', 'cancelar_renglon',
                    'cancelar_cuenta', 'cancelar_pago', 'descontar', 'quitar_descuento',
                    'cambiar_hora_corte', 'conectar_mercado_pago', 'desconectar_mercado_pago',
                    'confirmar_terminal', 'devuelto_mercado_pago', 'borrar_datos_cliente',
                    'canjear_premio', 'pasar_tarjeta'));


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto. Los miembros de la sucursal leen su regla (el cobro enseña la fila
-- «Tarjeta» solo con ella prendida); nadie la escribe directo. Las tarjetas, sus movimientos, los códigos y las
-- solicitudes no los lee ni los escribe nadie con sesión.

alter table public.lealtad enable row level security;
alter table public.tarjetas_lealtad enable row level security;
alter table public.movimientos_lealtad enable row level security;
alter table public.codigos_lealtad enable row level security;
alter table public.solicitudes_lealtad enable row level security;

revoke all on table public.lealtad, public.tarjetas_lealtad, public.movimientos_lealtad, public.codigos_lealtad,
  public.solicitudes_lealtad
from anon, authenticated;
revoke all on sequence public.tarjetas_lealtad_id_seq, public.movimientos_lealtad_id_seq, public.codigos_lealtad_id_seq,
  public.solicitudes_lealtad_id_seq
from anon, authenticated;

grant select (
  restaurante_id, prendida, forma, meta, minimo, pesos_por_punto, premio_tipo, premio_producto_id, premio_pesos,
  estilo, color, created_at, updated_at
) on public.lealtad to authenticated;

create policy "Los miembros leen la tarjeta de lealtad de sus restaurantes que funcionan"
on public.lealtad for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));

grant select (tarjeta_lealtad_id) on public.ventas to authenticated;
grant select (premio_tarjeta_id) on public.pedidos_en_linea to authenticated;


-- ─── Lo que se cuenta una sola vez ────────────────────────────────────────────

-- Letras y números al azar, sin sesgo: cada byte menor que el múltiplo más grande del alfabeto elige una.
create function privado.texto_al_azar(p_alfabeto text, p_largo integer)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_n integer := char_length(p_alfabeto);
  v_tope integer := 256 - (256 % char_length(p_alfabeto));
  v_texto text := '';
  v_azar bytea;
  v_byte integer;
begin
  while char_length(v_texto) < p_largo loop
    v_azar := extensions.gen_random_bytes(16);
    for i in 0..15 loop
      v_byte := get_byte(v_azar, i);
      if v_byte < v_tope and char_length(v_texto) < p_largo then
        v_texto := v_texto || substr(p_alfabeto, (v_byte % v_n) + 1, 1);
      end if;
    end loop;
  end loop;
  return v_texto;
end;
$$;

-- La llave de una tarjeta: 32 bytes al azar en base64url (43 letras), como el secreto de un aparato. Su huella es la de
-- privado.huella_aparato.
create function privado.llave_al_azar()
returns text
language sql
set search_path = ''
as $$
  select translate(rtrim(encode(extensions.gen_random_bytes(32), 'base64'), '='), '+/', '-_');
$$;

-- El código corto que sale debajo del QR: 8 letras y números, sin I, L, O, 0 ni 1 («K7MP2QXR»; el menú lo enseña
-- «K7MP 2QXR»). Su huella, con lo que escriba quien cobra: sin espacios ni guiones y en mayúsculas. Si no tiene esa
-- forma, ninguna.
create function privado.codigo_corto_al_azar()
returns text
language sql
set search_path = ''
as $$
  select privado.texto_al_azar('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 8);
$$;

create function privado.huella_codigo_corto(p_codigo text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when x ~ '^[A-HJKMNP-Z2-9]{8}$' then encode(sha256(convert_to(x, 'UTF8')), 'hex') end
  from (select upper(regexp_replace(coalesce(p_codigo, ''), '[\s-]', '', 'g')) as x) s;
$$;

-- Lo que no deja canjear el premio en producto, en palabras de la vista: archivado, un envío, con opciones que se
-- tienen que elegir o agotado. Vacío si se puede (o si el premio es en pesos o no hay premio).
create function privado.aviso_del_premio(p_restaurante_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_p record;
begin
  select p.nombre, p.visible, p.es_envio,
         p.archivado_at is not null or c.archivado_at is not null as archivado,
         exists (
           select 1
           from public.producto_grupos pg
           join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
           where pg.restaurante_id = p.restaurante_id and pg.producto_id = p.id and g.minimo > 0
         ) as pide_opciones
  into v_p
  from public.lealtad l
  join public.productos p on p.restaurante_id = l.restaurante_id and p.id = l.premio_producto_id
  join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
  where l.restaurante_id = p_restaurante_id and l.premio_tipo = 'producto';
  if not found then
    return null;
  end if;
  if v_p.archivado then
    return format('«%s» ya no está en tu menú: cambia el premio', v_p.nombre);
  end if;
  if v_p.es_envio then
    return format('«%s» es un costo de envío: cambia el premio', v_p.nombre);
  end if;
  if v_p.pide_opciones then
    return format('«%s» pide elegir opciones: cambia el premio por uno que no las pida', v_p.nombre);
  end if;
  if not v_p.visible then
    return format('«%s» está agotado: el premio se canjea cuando vuelva', v_p.nombre);
  end if;
  return null;
end;
$$;

-- ¿Se puede canjear el premio ahora? Prendida, con su regla, y su producto a la mano.
create function privado.premio_canjeable(p_restaurante_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((
    select l.prendida and l.meta is not null and l.premio_tipo is not null
           and privado.aviso_del_premio(l.restaurante_id) is null
    from public.lealtad l
    where l.restaurante_id = p_restaurante_id), false);
$$;

-- «Sellos» o «puntos», en singular si es uno.
create function privado.sellos_o_puntos(p_forma text, p_cantidad integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_cantidad || ' ' || case p_forma
    when 'sellos' then case when abs(p_cantidad) = 1 then 'sello' else 'sellos' end
    else case when abs(p_cantidad) = 1 then 'punto' else 'puntos' end
  end;
$$;

-- El premio de la regla, en palabras: «Gringa» o «$50.00».
create function privado.premio_escrito(p_restaurante_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select case l.premio_tipo when 'pesos' then privado.pesos(l.premio_pesos) else p.nombre end
  from public.lealtad l
  left join public.productos p on p.restaurante_id = l.restaurante_id and p.id = l.premio_producto_id
  where l.restaurante_id = p_restaurante_id;
$$;

-- El canje de una cuenta que sigue en ella: el movimiento de canje que no tiene devolución.
create function privado.canje_en_la_cuenta(p_restaurante_id uuid, p_venta_id bigint)
returns public.movimientos_lealtad
language sql
stable
set search_path = ''
as $$
  select m.*
  from public.movimientos_lealtad m
  where m.restaurante_id = p_restaurante_id and m.venta_id = p_venta_id and m.tipo = 'canje'
    and not exists (
      select 1 from public.movimientos_lealtad d
      where d.restaurante_id = m.restaurante_id and d.canje_id = m.id)
  order by m.id desc
  limit 1;
$$;

-- La tarjeta como la ve quien cobra: su nombre y lo juntado, nunca su teléfono.
create function privado.tarjeta_en_json(p_tarjeta_id bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id,
    'nombre', t.nombre,
    'saldo', t.saldo,
    'premio_listo', l.meta is not null and t.saldo >= l.meta)
  from public.tarjetas_lealtad t
  left join public.lealtad l on l.restaurante_id = t.restaurante_id
  where t.id = p_tarjeta_id;
$$;

-- La tarjeta con la llave de un celular o con el código corto, en una sucursal.
create function privado.tarjeta_por_llave(p_restaurante_id uuid, p_llave text, p_codigo text)
returns bigint
language sql
stable
set search_path = ''
as $$
  select t.id
  from public.tarjetas_lealtad t
  where t.restaurante_id = p_restaurante_id
    and (t.llave_hash = privado.huella_aparato(btrim(p_llave))
         or t.codigo_hash = privado.huella_codigo_corto(p_codigo));
$$;

-- La tarjeta como la ve su dueña en el menú: también su número (va atrás de la tarjeta) y su historial, los 50 más
-- recientes, con el día de la sucursal y si fue en el local o en un pedido del menú.
create function privado.tarjeta_del_celular(p_tarjeta_id bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'nombre', t.nombre,
    'telefono', t.telefono,
    'saldo', t.saldo,
    'premio_listo', l.meta is not null and t.saldo >= l.meta,
    'sacada', (t.created_at at time zone r.zona_horaria)::date,
    'ultima_compra', (t.ultima_compra_at at time zone r.zona_horaria)::date,
    'movimientos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'tipo', x.tipo, 'cantidad', x.cantidad, 'dia', x.dia, 'origen', x.origen)
               order by x.id desc), '[]')
      from (
        select m.id, m.tipo, m.cantidad, (m.created_at at time zone r.zona_horaria)::date as dia, v.origen
        from public.movimientos_lealtad m
        left join public.ventas v on v.restaurante_id = m.restaurante_id and v.id = m.venta_id
        where m.restaurante_id = t.restaurante_id and m.tarjeta_id = t.id
        order by m.id desc
        limit 50
      ) x))
  from public.tarjetas_lealtad t
  join public.restaurantes r on r.id = t.restaurante_id
  left join public.lealtad l on l.restaurante_id = t.restaurante_id
  where t.id = p_tarjeta_id;
$$;

revoke execute on function
  privado.mover_saldo(),
  privado.texto_al_azar(text, integer),
  privado.llave_al_azar(),
  privado.codigo_corto_al_azar(),
  privado.huella_codigo_corto(text),
  privado.aviso_del_premio(uuid),
  privado.premio_canjeable(uuid),
  privado.sellos_o_puntos(text, integer),
  privado.premio_escrito(uuid),
  privado.canje_en_la_cuenta(uuid, bigint),
  privado.tarjeta_en_json(bigint),
  privado.tarjeta_por_llave(uuid, text, text),
  privado.tarjeta_del_celular(bigint)
from public, anon, authenticated, service_role;


-- ─── El premio entra a la cuenta ──────────────────────────────────────────────
-- Lo comparten el canje en el cobro y el pedido del menú que se confirma. La cuenta ya viene bloqueada por quien
-- llama. Un premio por cuenta. El producto entra con su precio (sin opciones) y el descuento de su renglón al 100 %, y
-- va a cocina: en la comanda de su área que se mandó en esta misma operación (la del pedido que se confirma) o en una
-- nueva. El descuento en pesos reemplaza al de la cuenta. La cuenta queda con esa tarjeta. Regresa vacío si entró, o
-- por qué no.

create function privado.meter_premio(
  p_restaurante_id uuid,
  p_venta_id bigint,
  p_tarjeta_id bigint,
  p_miembro bigint,
  p_clave uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.lealtad;
  v_venta record;
  v_tarjeta public.tarjetas_lealtad;
  v_aviso text;
  v_p record;
  v_comanda_id bigint;
  v_item_id bigint;
begin
  select * into v_l from public.lealtad where restaurante_id = p_restaurante_id;
  if not found or not v_l.prendida or v_l.meta is null or v_l.premio_tipo is null then
    return 'La tarjeta de lealtad está apagada';
  end if;

  select id, estado, subtotal, pagado into v_venta
  from public.ventas
  where restaurante_id = p_restaurante_id and id = p_venta_id;
  if not found or v_venta.estado <> 'abierta' then
    return 'Esa cuenta ya no está abierta';
  end if;
  if (privado.canje_en_la_cuenta(p_restaurante_id, p_venta_id)).id is not null then
    return 'Esta cuenta ya tiene un premio de la tarjeta';
  end if;

  select * into v_tarjeta
  from public.tarjetas_lealtad
  where restaurante_id = p_restaurante_id and id = p_tarjeta_id
  for update;
  if not found then
    return 'Esa tarjeta ya no existe';
  end if;
  if v_tarjeta.saldo < v_l.meta then
    return format('A esta tarjeta le faltan %s para su premio',
                  privado.sellos_o_puntos(v_l.forma, v_l.meta - v_tarjeta.saldo));
  end if;

  if v_l.premio_tipo = 'producto' then
    v_aviso := privado.aviso_del_premio(p_restaurante_id);
    if v_aviso is not null then
      return v_aviso;
    end if;
    select p.id, p.nombre, p.precio, p.tasa_iva, c.area_preparacion_id into v_p
    from public.productos p
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where p.restaurante_id = p_restaurante_id and p.id = v_l.premio_producto_id;

    if v_p.area_preparacion_id is not null then
      select id into v_comanda_id
      from public.comandas
      where restaurante_id = p_restaurante_id and venta_id = p_venta_id
        and area_preparacion_id = v_p.area_preparacion_id and estado = 'pendiente' and created_at = now()
      order by id
      limit 1;
      if v_comanda_id is null then
        insert into public.comandas (restaurante_id, venta_id, area_preparacion_id, enviada_por)
        values (p_restaurante_id, p_venta_id, v_p.area_preparacion_id, p_miembro)
        returning id into v_comanda_id;
      end if;
    end if;

    insert into public.venta_items (
      restaurante_id, venta_id, producto_id, nombre, precio_unitario, cantidad, opciones, nota, tasa_iva,
      comanda_id, agregado_por, clave_envio, descuento_tipo, descuento_valor, descuento_motivo
    ) values (
      p_restaurante_id, p_venta_id, v_p.id, v_p.nombre, v_p.precio, 1, '[]', null, v_p.tasa_iva,
      v_comanda_id, p_miembro, p_clave, 'porcentaje', 100, 'Premio de la tarjeta'
    )
    returning id into v_item_id;
  else
    if v_venta.subtotal < v_l.premio_pesos then
      return format('El premio es de %s: esta cuenta todavía no llega a eso', privado.pesos(v_l.premio_pesos));
    end if;
    if v_venta.subtotal - v_l.premio_pesos < v_venta.pagado then
      return format('Ya se pagaron %s. Cancela antes un pago.', privado.pesos(v_venta.pagado));
    end if;
    -- Primero el descuento y luego el canje: así el disparador que regresa premios no confunde este cambio.
    update public.ventas
    set descuento_tipo = 'pesos', descuento_valor = v_l.premio_pesos, descuento_motivo = 'Premio de la tarjeta'
    where restaurante_id = p_restaurante_id and id = p_venta_id;
    perform privado.recalcular_venta(p_restaurante_id, p_venta_id);
  end if;

  insert into public.movimientos_lealtad (restaurante_id, tarjeta_id, tipo, cantidad, venta_id, venta_item_id,
                                          anotado_por, clave)
  values (p_restaurante_id, p_tarjeta_id, 'canje', -v_l.meta, p_venta_id, v_item_id, p_miembro, p_clave);

  update public.ventas
  set tarjeta_lealtad_id = p_tarjeta_id
  where restaurante_id = p_restaurante_id and id = p_venta_id and tarjeta_lealtad_id is distinct from p_tarjeta_id;

  -- Sin el nombre ni el teléfono de la tarjeta. Quien canjea lo autoriza con el QR, así que es él mismo.
  insert into public.bitacora (restaurante_id, miembro_id, autorizado_por, accion, tabla, registro_id, detalle)
  values (p_restaurante_id, p_miembro, p_miembro, 'canjear_premio', 'ventas', p_venta_id::text,
          jsonb_build_object('premio', privado.premio_escrito(p_restaurante_id), 'cantidad', v_l.meta,
                             'forma', v_l.forma));
  return null;
end;
$$;

revoke execute on function privado.meter_premio(uuid, bigint, bigint, bigint, uuid)
from public, anon, authenticated, service_role;


-- ─── La cuenta que se cierra suma; la que se reabre regresa ───────────────────
-- Al cerrarse pagada una cuenta con tarjeta y la tarjeta prendida: con sellos, uno si lo pagado (después de descuentos,
-- sin propina: su total) llega al mínimo; con puntos, un punto por cada tantos pesos, hacia abajo. Una cuenta de $0 no
-- suma. Su última compra se anota aunque no le alcance. Al reabrirse (un pago cancelado), cada tarjeta regresa lo que
-- esa cuenta le sumó desde su último reinicio, aunque esté apagada.

create function privado.lealtad_de_la_cuenta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.lealtad;
  v_cantidad integer;
begin
  if old.estado = 'cerrada' then
    insert into public.movimientos_lealtad (restaurante_id, tarjeta_id, tipo, cantidad, venta_id)
    select new.restaurante_id, m.tarjeta_id, 'regreso', -sum(m.cantidad), new.id
    from public.movimientos_lealtad m
    where m.restaurante_id = new.restaurante_id and m.venta_id = new.id and m.tipo in ('compra', 'regreso')
      and m.id > coalesce((
        select max(r.id) from public.movimientos_lealtad r
        where r.restaurante_id = m.restaurante_id and r.tarjeta_id = m.tarjeta_id and r.tipo = 'reinicio'), 0)
    group by m.tarjeta_id
    having sum(m.cantidad) > 0;
  end if;

  if new.estado = 'cerrada' and new.tarjeta_lealtad_id is not null and new.total > 0 then
    select * into v_l from public.lealtad where restaurante_id = new.restaurante_id;
    if found and v_l.prendida and v_l.meta is not null then
      v_cantidad := case v_l.forma
        when 'sellos' then case when new.total >= v_l.minimo then 1 else 0 end
        else floor(new.total / v_l.pesos_por_punto)::integer
      end;
      if v_cantidad > 0 then
        insert into public.movimientos_lealtad (restaurante_id, tarjeta_id, tipo, cantidad, venta_id)
        values (new.restaurante_id, new.tarjeta_lealtad_id, 'compra', v_cantidad, new.id);
      end if;
      update public.tarjetas_lealtad
      set ultima_compra_at = coalesce(new.cerrada_at, now())
      where restaurante_id = new.restaurante_id and id = new.tarjeta_lealtad_id;
    end if;
  end if;
  return null;
end;
$$;

create trigger ventas_lealtad
after update of estado on public.ventas
for each row
when (old.estado is distinct from new.estado and 'cerrada' in (old.estado, new.estado))
execute function privado.lealtad_de_la_cuenta();


-- ─── El premio que sale de la cuenta regresa a la tarjeta ─────────────────────
-- Una sola vez por canje, y no si la tarjeta se reinició después (pasó de sellos a puntos o al revés). El producto
-- sale si su renglón se cancela (también con la cuenta) o si su descuento cambia o se quita; el descuento en pesos, si
-- el de la cuenta cambia o se quita, o si la cuenta se cancela (también al juntarla con otra).

create function privado.regresar_premio(p_canje public.movimientos_lealtad, p_venta_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.movimientos_lealtad (restaurante_id, tarjeta_id, tipo, cantidad, venta_id, venta_item_id, canje_id)
  select p_canje.restaurante_id, p_canje.tarjeta_id, 'devolucion', -p_canje.cantidad, p_venta_id,
         p_canje.venta_item_id, p_canje.id
  where p_canje.id is not null
    and not exists (
      select 1 from public.movimientos_lealtad r
      where r.restaurante_id = p_canje.restaurante_id and r.tarjeta_id = p_canje.tarjeta_id
        and r.tipo = 'reinicio' and r.id > p_canje.id);
$$;

create function privado.premio_del_renglon()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_canje public.movimientos_lealtad;
begin
  select m.* into v_canje
  from public.movimientos_lealtad m
  where m.restaurante_id = new.restaurante_id and m.venta_item_id = new.id and m.tipo = 'canje'
    and not exists (
      select 1 from public.movimientos_lealtad d
      where d.restaurante_id = m.restaurante_id and d.canje_id = m.id);
  if found and (new.estado = 'cancelado'
                or (new.descuento_tipo, new.descuento_valor, new.descuento_motivo)
                   is distinct from (old.descuento_tipo, old.descuento_valor, old.descuento_motivo)) then
    perform privado.regresar_premio(v_canje, new.venta_id);
  end if;
  return null;
end;
$$;

create trigger venta_items_premio_lealtad
after update of estado, descuento_tipo, descuento_valor, descuento_motivo on public.venta_items
for each row execute function privado.premio_del_renglon();

create function privado.premio_de_la_cuenta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_canje public.movimientos_lealtad;
begin
  v_canje := privado.canje_en_la_cuenta(new.restaurante_id, new.id);
  if v_canje.id is not null and v_canje.venta_item_id is null
     and (new.estado = 'cancelada'
          or (new.descuento_tipo, new.descuento_valor, new.descuento_motivo)
             is distinct from (old.descuento_tipo, old.descuento_valor, old.descuento_motivo)) then
    perform privado.regresar_premio(v_canje, new.id);
  end if;
  return null;
end;
$$;

create trigger ventas_premio_lealtad
after update of estado, descuento_tipo, descuento_valor, descuento_motivo on public.ventas
for each row execute function privado.premio_de_la_cuenta();


-- ─── El pedido del menú que se confirma ───────────────────────────────────────
-- Su cuenta lleva la tarjeta cuyo premio usa o, si no usa premio, la del teléfono del pedido en esa sucursal; solo con
-- la tarjeta prendida. El premio entra si todavía alcanza, a nombre de quien confirmó y con la clave del pedido; si no,
-- la cuenta nace sin premio (Pedidos lo dice con premio.entro).

create function privado.lealtad_del_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tarjeta_id bigint;
begin
  if not exists (select 1 from public.lealtad l where l.restaurante_id = new.restaurante_id and l.prendida) then
    return null;
  end if;
  if new.premio_tarjeta_id is not null then
    v_tarjeta_id := new.premio_tarjeta_id;
    perform privado.meter_premio(new.restaurante_id, new.venta_id, new.premio_tarjeta_id, new.atendido_por, new.clave);
  else
    select t.id into v_tarjeta_id
    from public.tarjetas_lealtad t
    where t.restaurante_id = new.restaurante_id and t.telefono = new.cliente_telefono;
  end if;
  if v_tarjeta_id is not null then
    update public.ventas
    set tarjeta_lealtad_id = v_tarjeta_id
    where restaurante_id = new.restaurante_id and id = new.venta_id and tarjeta_lealtad_id is null;
  end if;
  return null;
end;
$$;

create trigger pedidos_en_linea_lealtad
after update of estado on public.pedidos_en_linea
for each row
when (old.estado = 'por_confirmar' and new.estado = 'confirmado')
execute function privado.lealtad_del_pedido();

revoke execute on function
  privado.lealtad_de_la_cuenta(),
  privado.regresar_premio(public.movimientos_lealtad, bigint),
  privado.premio_del_renglon(),
  privado.premio_de_la_cuenta(),
  privado.lealtad_del_pedido()
from public, anon, authenticated, service_role;


-- ─── Lo que hace el gerente, en «Tarjeta de lealtad» ──────────────────────────
-- Nace la fila con lo primero que guarde: en Metal, negra, con sellos y apagada.

-- «Tu regla y tu premio» (Tarjetas): los números según la forma de hoy y el premio, juntos. Cambiarlos respeta lo ya
-- juntado. El producto tiene que estar en Mi menú, no ser un envío y no pedir opciones; agotado sí se puede elegir.
create function public.guardar_regla_lealtad(
  p_restaurante_id uuid,
  p_meta integer,
  p_minimo numeric,
  p_pesos_por_punto numeric,
  p_premio_tipo text,
  p_premio_producto_id bigint,
  p_premio_pesos numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.lealtad;
  v_minimo numeric(12,2) := round(p_minimo, 2);
  v_pesos_por_punto numeric(12,2) := round(p_pesos_por_punto, 2);
  v_premio_pesos numeric(12,2) := round(p_premio_pesos, 2);
  v_p record;
begin
  if p_restaurante_id is null or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante cambia su tarjeta de lealtad' using errcode = '42501';
  end if;
  insert into public.lealtad (restaurante_id) values (p_restaurante_id) on conflict (restaurante_id) do nothing;
  select * into v_l from public.lealtad where restaurante_id = p_restaurante_id for update;

  if v_l.forma = 'sellos' then
    if p_meta is null or p_meta < 2 or p_meta > 20 then
      raise exception 'Con sellos, el premio pide de 2 a 20' using errcode = '22023';
    end if;
    if v_minimo is null or v_minimo < 0 then
      raise exception 'Escribe desde cuánto gana su sello una cuenta (0 es cualquiera)' using errcode = '22023';
    end if;
    v_pesos_por_punto := null;
  else
    if p_meta is null or p_meta < 1 or p_meta > 10000 then
      raise exception 'Con puntos, el premio pide de 1 a 10,000' using errcode = '22023';
    end if;
    if v_pesos_por_punto is null or v_pesos_por_punto <= 0 then
      raise exception 'Escribe cuántos pesos vale un punto' using errcode = '22023';
    end if;
    v_minimo := null;
  end if;

  if p_premio_tipo is null or p_premio_tipo not in ('producto', 'pesos') then
    raise exception 'Elige el premio: un producto gratis o un descuento' using errcode = '22023';
  end if;
  if p_premio_tipo = 'producto' then
    select p.nombre, p.es_envio, p.archivado_at is not null or c.archivado_at is not null as archivado,
           exists (
             select 1
             from public.producto_grupos pg
             join public.grupos_opciones g on g.restaurante_id = pg.restaurante_id and g.id = pg.grupo_id
             where pg.restaurante_id = p.restaurante_id and pg.producto_id = p.id and g.minimo > 0
           ) as pide_opciones
    into v_p
    from public.productos p
    join public.categorias c on c.restaurante_id = p.restaurante_id and c.id = p.categoria_id
    where p.restaurante_id = p_restaurante_id and p.id = p_premio_producto_id;
    if not found or v_p.archivado then
      raise exception 'Ese producto ya no está en tu menú' using errcode = '23503';
    end if;
    if v_p.es_envio then
      raise exception 'Un costo de envío no puede ser el premio' using errcode = '22023';
    end if;
    if v_p.pide_opciones then
      raise exception '«%» pide elegir opciones: elige un producto que no las pida', v_p.nombre using errcode = '22023';
    end if;
    v_premio_pesos := null;
  else
    if v_premio_pesos is null or v_premio_pesos <= 0 then
      raise exception 'Escribe de cuántos pesos es el descuento' using errcode = '22023';
    end if;
    p_premio_producto_id := null;
  end if;

  update public.lealtad
  set meta = p_meta, minimo = v_minimo, pesos_por_punto = v_pesos_por_punto, premio_tipo = p_premio_tipo,
      premio_producto_id = p_premio_producto_id, premio_pesos = v_premio_pesos
  where restaurante_id = p_restaurante_id;
end;
$$;

-- «Tu tarjeta»: cómo se junta, el estilo y el color (vacío = «Del color de tu menú»). Cambiar de sellos a puntos (o
-- al revés) pone todas las tarjetas en 0 y, si ya había regla, se lleva sus números: la tarjeta se apaga hasta que el
-- gerente ponga los nuevos (el premio se queda). Regresa cuántas tarjetas volvieron a 0. El estilo y el color no van a
-- la bitácora.
create function public.guardar_tu_tarjeta(p_restaurante_id uuid, p_forma text, p_estilo text, p_color text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.lealtad;
  v_miembro bigint;
  v_color text := upper(nullif(btrim(p_color), ''));
  v_reiniciadas integer := 0;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['gerente']);
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante cambia su tarjeta de lealtad' using errcode = '42501';
  end if;
  if p_forma is null or p_forma not in ('sellos', 'puntos') then
    raise exception 'Elige si se juntan sellos o puntos' using errcode = '22023';
  end if;
  if p_estilo is null or p_estilo not in ('liquido', 'agua', 'metal', 'brillante', 'liso', 'olas') then
    raise exception 'Elige el estilo de tu tarjeta' using errcode = '22023';
  end if;
  if v_color is not null and v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'El color va como #1A2B3C' using errcode = '22023';
  end if;

  insert into public.lealtad (restaurante_id) values (p_restaurante_id) on conflict (restaurante_id) do nothing;
  select * into v_l from public.lealtad where restaurante_id = p_restaurante_id for update;

  if p_forma <> v_l.forma then
    insert into public.movimientos_lealtad (restaurante_id, tarjeta_id, tipo, cantidad, anotado_por)
    select t.restaurante_id, t.id, 'reinicio', -t.saldo, v_miembro
    from public.tarjetas_lealtad t
    where t.restaurante_id = p_restaurante_id and t.saldo <> 0;
    get diagnostics v_reiniciadas = row_count;
  end if;

  update public.lealtad
  set forma = p_forma,
      estilo = p_estilo,
      color = v_color,
      meta = case when p_forma <> v_l.forma then null else meta end,
      minimo = case when p_forma <> v_l.forma then null else minimo end,
      pesos_por_punto = case when p_forma <> v_l.forma then null else pesos_por_punto end,
      prendida = case when p_forma <> v_l.forma then false else prendida end
  where restaurante_id = p_restaurante_id;
  return v_reiniciadas;
end;
$$;

-- El interruptor. Prenderla pide su regla y su premio. Apagarla guarda lo juntado.
create function public.prender_lealtad(p_restaurante_id uuid, p_prendida boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_l public.lealtad;
begin
  if p_restaurante_id is null or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante prende o apaga su tarjeta de lealtad' using errcode = '42501';
  end if;
  if p_prendida is null then
    raise exception 'Elige prenderla o apagarla' using errcode = '22023';
  end if;
  select * into v_l from public.lealtad where restaurante_id = p_restaurante_id for update;
  if p_prendida and (not found or v_l.meta is null or v_l.premio_tipo is null) then
    raise exception 'Pon tu regla y tu premio antes de prenderla' using errcode = '55000';
  end if;
  update public.lealtad set prendida = p_prendida where restaurante_id = p_restaurante_id;
end;
$$;

-- La tabla de tarjetas: con su teléfono (solo el gerente lo ve), lo juntado, si el premio está listo, cuándo la sacó,
-- su última compra (días de la sucursal) y si pidió pasarla a otro celular. Las más nuevas primero. aviso_premio dice
-- si el premio en producto no se puede canjear ahora.
create function public.tarjetas_de_lealtad(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r public.restaurantes;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante ve sus tarjetas de lealtad' using errcode = '42501';
  end if;
  select * into v_r from public.restaurantes where id = p_restaurante_id;
  return jsonb_build_object(
    'hoy', privado.dia_local(v_r.zona_horaria),
    'aviso_premio', privado.aviso_del_premio(p_restaurante_id),
    'tarjetas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', t.id,
               'nombre', t.nombre,
               'telefono', t.telefono,
               'saldo', t.saldo,
               'premio_listo', l.meta is not null and t.saldo >= l.meta,
               'sacada', (t.created_at at time zone v_r.zona_horaria)::date,
               'ultima_compra', (t.ultima_compra_at at time zone v_r.zona_horaria)::date,
               'pide_celular', exists (
                 select 1 from public.codigos_lealtad c
                 where c.restaurante_id = t.restaurante_id and c.tarjeta_id = t.id and c.expira_at > now()))
               order by t.id desc), '[]')
      from public.tarjetas_lealtad t
      left join public.lealtad l on l.restaurante_id = t.restaurante_id
      where t.restaurante_id = p_restaurante_id));
end;
$$;

-- Para «Borrar los datos de un cliente» de Ajustes: la tarjeta de ese teléfono, si tiene, y con cuánto («Rosa Ramírez,
-- 8 sellos»). Vacío si no tiene.
create function public.tarjeta_del_cliente(p_restaurante_id uuid, p_telefono text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_telefono text;
begin
  if privado.mi_miembro(p_restaurante_id, array['gerente']) is null then
    raise exception 'Solo el gerente de este restaurante ve los datos de sus clientes' using errcode = '42501';
  end if;
  v_telefono := privado.telefono_del_cliente(p_telefono);
  return (
    select jsonb_build_object('nombre', t.nombre, 'saldo', t.saldo, 'forma', l.forma)
    from public.tarjetas_lealtad t
    left join public.lealtad l on l.restaurante_id = t.restaurante_id
    where t.restaurante_id = p_restaurante_id and t.telefono = v_telefono);
end;
$$;


-- ─── Lo que hace quien cobra ──────────────────────────────────────────────────
-- Pepe, Lupita o Don Chuy, en una cuenta abierta de su sucursal, con la tarjeta prendida.

-- «Escanear» o «Escribir número»: la cuenta queda con esa tarjeta, para sumarle al cerrarse. Con el número suma pero no
-- canjea. Regresa su nombre y lo juntado, y si llegó con el QR o el código (entonces puede canjear).
create function public.ligar_tarjeta(
  p_venta_id bigint,
  p_telefono text default null,
  p_llave text default null,
  p_codigo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_miembro bigint;
  v_telefono text := nullif(btrim(p_telefono), '');
  v_llave text := nullif(btrim(p_llave), '');
  v_codigo text := nullif(btrim(p_codigo), '');
  v_tarjeta_id bigint;
  v_canje public.movimientos_lealtad;
begin
  select id, restaurante_id into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante ponen la tarjeta' using errcode = '42501';
  end if;
  if not exists (select 1 from public.lealtad l where l.restaurante_id = v_venta.restaurante_id and l.prendida) then
    raise exception 'La tarjeta de lealtad está apagada' using errcode = '55000';
  end if;
  if num_nonnulls(v_telefono, v_llave, v_codigo) <> 1 then
    raise exception 'Escanea su QR o escribe su número' using errcode = '22023';
  end if;

  if v_telefono is not null then
    v_telefono := privado.telefono_del_cliente(v_telefono);
    select t.id into v_tarjeta_id
    from public.tarjetas_lealtad t
    where t.restaurante_id = v_venta.restaurante_id and t.telefono = v_telefono;
    if not found then
      raise exception 'No hay una tarjeta con ese número' using errcode = 'P0002';
    end if;
  else
    v_tarjeta_id := privado.tarjeta_por_llave(v_venta.restaurante_id, v_llave, v_codigo);
    if v_tarjeta_id is null then
      raise exception 'Ese código no es de una tarjeta de aquí' using errcode = 'P0002';
    end if;
  end if;

  v_canje := privado.canje_en_la_cuenta(v_venta.restaurante_id, p_venta_id);
  if v_canje.id is not null and v_canje.tarjeta_id <> v_tarjeta_id then
    raise exception 'Esta cuenta ya tiene el premio de otra tarjeta' using errcode = '55000';
  end if;

  update public.ventas set tarjeta_lealtad_id = v_tarjeta_id where id = p_venta_id;
  return privado.tarjeta_en_json(v_tarjeta_id) || jsonb_build_object('con_qr', v_telefono is null);
end;
$$;

-- «Quitar»: la cuenta se queda sin tarjeta. Con su premio adentro, no: primero se quita el premio.
create function public.quitar_tarjeta(p_venta_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
begin
  select id, restaurante_id into v_venta
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  if privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']) is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante quitan la tarjeta' using errcode = '42501';
  end if;
  if (privado.canje_en_la_cuenta(v_venta.restaurante_id, p_venta_id)).id is not null then
    raise exception 'Esta cuenta tiene su premio: quítalo antes' using errcode = '55000';
  end if;
  update public.ventas set tarjeta_lealtad_id = null where id = p_venta_id and tarjeta_lealtad_id is not null;
end;
$$;

-- «Canjear premio»: siempre con el QR o el código corto, nunca con el número. La misma clave dos veces (doble toque,
-- sin conexión) canjea una vez. Regresa la tarjeta como quedó.
create function public.canjear_premio(
  p_venta_id bigint,
  p_clave uuid,
  p_llave text default null,
  p_codigo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venta record;
  v_miembro bigint;
  v_tarjeta_id bigint;
  v_error text;
begin
  if p_clave is null then
    raise exception 'Falta la clave del canje' using errcode = '22023';
  end if;
  select id, restaurante_id into v_venta
  from public.ventas
  where id = p_venta_id and restaurante_id in (select privado.mis_restaurantes())
  for update;
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante canjean premios' using errcode = '42501';
  end if;

  select m.tarjeta_id into v_tarjeta_id
  from public.movimientos_lealtad m
  where m.restaurante_id = v_venta.restaurante_id and m.clave = p_clave and m.venta_id = p_venta_id;
  if found then
    return privado.tarjeta_en_json(v_tarjeta_id);
  end if;

  if num_nonnulls(nullif(btrim(p_llave), ''), nullif(btrim(p_codigo), '')) = 0 then
    raise exception 'Para canjear el premio, escanea su QR o escribe su código' using errcode = '22023';
  end if;
  v_tarjeta_id := privado.tarjeta_por_llave(v_venta.restaurante_id, p_llave, p_codigo);
  if v_tarjeta_id is null then
    raise exception 'Ese código no es de una tarjeta de aquí' using errcode = 'P0002';
  end if;

  v_error := privado.meter_premio(v_venta.restaurante_id, p_venta_id, v_tarjeta_id, v_miembro, p_clave);
  if v_error is not null then
    raise exception '%', v_error using errcode = '55000';
  end if;
  return privado.tarjeta_en_json(v_tarjeta_id);
end;
$$;

-- La tarjeta que lleva una cuenta, para el cobro: su nombre, lo juntado y si su premio ya está en la cuenta. Vacío si
-- no lleva.
create function public.tarjeta_de_la_cuenta(p_venta_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_venta record;
begin
  select id, restaurante_id, tarjeta_lealtad_id into v_venta
  from public.ventas
  where id = p_venta_id and restaurante_id in (select privado.mis_restaurantes());
  if not found or privado.mi_miembro(v_venta.restaurante_id, array['mesero', 'caja', 'gerente']) is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante ven la tarjeta de una cuenta' using errcode = '42501';
  end if;
  if v_venta.tarjeta_lealtad_id is null then
    return null;
  end if;
  return privado.tarjeta_en_json(v_venta.tarjeta_lealtad_id)
    || jsonb_build_object('premio_en_cuenta', (privado.canje_en_la_cuenta(v_venta.restaurante_id, p_venta_id)).id is not null);
end;
$$;

-- «Pasar su tarjeta»: el código de 6 letras que le salió en el celular nuevo y el número de su tarjeta (si lo mandó por
-- WhatsApp, el número desde el que escribió). La llave y el código corto nuevos pasan a la tarjeta, el celular viejo
-- deja de verla y el código se borra. Si no cuadra, un solo mensaje, sin decir qué falló.
create function public.pasar_tarjeta(p_restaurante_id uuid, p_codigo text, p_telefono text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_codigo public.codigos_lealtad;
  v_telefono text := regexp_replace(coalesce(p_telefono, ''), '[\s().-]', '', 'g');
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante pasan tarjetas' using errcode = '42501';
  end if;

  select c.* into v_codigo
  from public.codigos_lealtad c
  join public.tarjetas_lealtad t on t.restaurante_id = c.restaurante_id and t.id = c.tarjeta_id
  where c.restaurante_id = p_restaurante_id
    and c.codigo = upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'))
    and c.expira_at > now()
    and t.telefono = v_telefono
  for update of c;
  if not found then
    raise exception 'Ese código no existe, ya venció o no es de ese número' using errcode = 'P0002';
  end if;

  update public.tarjetas_lealtad
  set llave_hash = v_codigo.llave_hash, codigo_hash = v_codigo.codigo_hash
  where restaurante_id = p_restaurante_id and id = v_codigo.tarjeta_id;
  delete from public.codigos_lealtad where id = v_codigo.id;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id)
  values (p_restaurante_id, v_miembro, 'pasar_tarjeta', 'tarjetas_lealtad', v_codigo.tarjeta_id::text);
  return privado.tarjeta_en_json(v_codigo.tarjeta_id);
end;
$$;

revoke execute on function
  public.guardar_regla_lealtad(uuid, integer, numeric, numeric, text, bigint, numeric),
  public.guardar_tu_tarjeta(uuid, text, text, text),
  public.prender_lealtad(uuid, boolean),
  public.tarjetas_de_lealtad(uuid),
  public.tarjeta_del_cliente(uuid, text),
  public.ligar_tarjeta(bigint, text, text, text),
  public.quitar_tarjeta(bigint),
  public.canjear_premio(bigint, uuid, text, text),
  public.tarjeta_de_la_cuenta(bigint),
  public.pasar_tarjeta(uuid, text, text)
from public, anon, service_role;

grant execute on function
  public.guardar_regla_lealtad(uuid, integer, numeric, numeric, text, bigint, numeric),
  public.guardar_tu_tarjeta(uuid, text, text, text),
  public.prender_lealtad(uuid, boolean),
  public.tarjetas_de_lealtad(uuid),
  public.tarjeta_del_cliente(uuid, text),
  public.ligar_tarjeta(bigint, text, text, text),
  public.quitar_tarjeta(bigint),
  public.canjear_premio(bigint, uuid, text, text),
  public.tarjeta_de_la_cuenta(bigint),
  public.pasar_tarjeta(uuid, text, text)
to authenticated;


-- ─── Lo que pide el menú, por el Worker ───────────────────────────────────────
-- Solo el Worker (service_role), después de Turnstile y con las dos marcas, como un pedido. Un menú que no existe, sin
-- licencia o sin la tarjeta prendida contesta «no_hay». Sacarla y pedir un código cuentan juntos: 3 por hora desde
-- cada celular y 10 desde cada conexión, en cada sucursal. Ver la tarjeta y borrarla piden su llave, que no se adivina,
-- y sirven aunque la tarjeta esté apagada.

-- La sucursal del menú, si funciona hoy.
create function privado.restaurante_del_menu(p_slug text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select r.id
  from public.restaurantes r
  where r.slug = lower(btrim(p_slug))
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
$$;

-- Cuenta una solicitud si cabe en los límites; si no, regresa cuál se pasó.
create function privado.solicitud_lealtad(p_restaurante_id uuid, p_marca_celular text, p_marca_conexion text)
returns text
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(p_marca_celular, '') !~ '^[0-9a-f]{64}$' or coalesce(p_marca_conexion, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'Faltan las marcas' using errcode = '22023';
  end if;
  if (select count(*) from public.solicitudes_lealtad
      where restaurante_id = p_restaurante_id and marca_celular = p_marca_celular
        and created_at > now() - interval '1 hour') >= 3 then
    return 'limite_celular';
  end if;
  if (select count(*) from public.solicitudes_lealtad
      where restaurante_id = p_restaurante_id and marca_conexion = p_marca_conexion
        and created_at > now() - interval '1 hour') >= 10 then
    return 'limite_conexion';
  end if;
  insert into public.solicitudes_lealtad (restaurante_id, marca_celular, marca_conexion)
  values (p_restaurante_id, p_marca_celular, p_marca_conexion);
  return null;
end;
$$;

revoke execute on function
  privado.restaurante_del_menu(text),
  privado.solicitud_lealtad(uuid, text, text)
from public, anon, authenticated, service_role;

-- «Sacar mi tarjeta»: nombre, teléfono y la casilla del aviso. Si ese número ya tiene tarjeta, motivo «ya_existe» (el
-- menú ofrece recuperarla). Regresa una sola vez la llave y el código corto, que guarda el celular.
create function public.sacar_tarjeta(
  p_slug text,
  p_nombre text,
  p_telefono text,
  p_acepta boolean,
  p_marca_celular text,
  p_marca_conexion text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid := privado.restaurante_del_menu(p_slug);
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_telefono text := regexp_replace(coalesce(p_telefono, ''), '[\s().-]', '', 'g');
  v_limite text;
  v_llave text;
  v_codigo text;
  v_tarjeta_id bigint;
begin
  if v_restaurante_id is null
     or not exists (select 1 from public.lealtad l where l.restaurante_id = v_restaurante_id and l.prendida) then
    return jsonb_build_object('ok', false, 'motivo', 'no_hay');
  end if;
  if v_nombre = '' then
    raise exception 'Escribe tu nombre' using errcode = '22023';
  end if;
  if char_length(v_nombre) > 60 then
    raise exception 'Tu nombre puede tener hasta 60 letras' using errcode = '22023';
  end if;
  if v_telefono !~ '^[0-9]{10}$' then
    raise exception 'Tu teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
  end if;
  if p_acepta is not true then
    raise exception 'Marca «Acepto el aviso de privacidad»' using errcode = '22023';
  end if;

  -- Una a la vez en cada sucursal: los límites y el teléfono no se pisan.
  perform pg_advisory_xact_lock(hashtextextended('lealtad:' || v_restaurante_id::text, 0));
  v_limite := privado.solicitud_lealtad(v_restaurante_id, p_marca_celular, p_marca_conexion);
  if v_limite is not null then
    return jsonb_build_object('ok', false, 'motivo', v_limite);
  end if;
  if exists (select 1 from public.tarjetas_lealtad t where t.restaurante_id = v_restaurante_id and t.telefono = v_telefono) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_existe');
  end if;

  loop
    v_llave := privado.llave_al_azar();
    v_codigo := privado.codigo_corto_al_azar();
    exit when not exists (
      select 1 from public.tarjetas_lealtad t
      where t.restaurante_id = v_restaurante_id and t.codigo_hash = privado.huella_codigo_corto(v_codigo));
  end loop;
  insert into public.tarjetas_lealtad (restaurante_id, nombre, telefono, llave_hash, codigo_hash, aviso_aceptado_at)
  values (v_restaurante_id, v_nombre, v_telefono, privado.huella_aparato(v_llave), privado.huella_codigo_corto(v_codigo),
          now())
  returning id into v_tarjeta_id;

  return jsonb_build_object('ok', true, 'llave', v_llave, 'codigo', v_codigo,
                            'tarjeta', privado.tarjeta_del_celular(v_tarjeta_id));
end;
$$;

-- «Recupera tu tarjeta»: con su número, el celular nuevo recibe ya su llave y su código corto nuevos, y el código de 6
-- letras que confirma quien cobra; dura 10 minutos. Pedir otro reemplaza al anterior. Sin tarjeta con ese número,
-- motivo «sin_tarjeta».
create function public.pedir_codigo_tarjeta(
  p_slug text,
  p_telefono text,
  p_marca_celular text,
  p_marca_conexion text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid := privado.restaurante_del_menu(p_slug);
  v_telefono text := regexp_replace(coalesce(p_telefono, ''), '[\s().-]', '', 'g');
  v_limite text;
  v_tarjeta_id bigint;
  v_llave text;
  v_codigo_corto text;
  v_codigo text;
  v_expira timestamptz;
begin
  if v_restaurante_id is null
     or not exists (select 1 from public.lealtad l where l.restaurante_id = v_restaurante_id and l.prendida) then
    return jsonb_build_object('ok', false, 'motivo', 'no_hay');
  end if;
  if v_telefono !~ '^[0-9]{10}$' then
    raise exception 'Tu teléfono lleva 10 dígitos, como 222 123 4567.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lealtad:' || v_restaurante_id::text, 0));
  v_limite := privado.solicitud_lealtad(v_restaurante_id, p_marca_celular, p_marca_conexion);
  if v_limite is not null then
    return jsonb_build_object('ok', false, 'motivo', v_limite);
  end if;
  select t.id into v_tarjeta_id
  from public.tarjetas_lealtad t
  where t.restaurante_id = v_restaurante_id and t.telefono = v_telefono;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sin_tarjeta');
  end if;

  -- Los vencidos ya no sirven: se limpian al pedir uno nuevo, como los de vincular un aparato.
  delete from public.codigos_lealtad
  where restaurante_id = v_restaurante_id and (tarjeta_id = v_tarjeta_id or expira_at <= now());
  loop
    v_llave := privado.llave_al_azar();
    v_codigo_corto := privado.codigo_corto_al_azar();
    v_codigo := privado.texto_al_azar('ABCDEFGHJKMNPQRSTUVWXYZ', 6);
    exit when not exists (
        select 1 from public.tarjetas_lealtad t
        where t.restaurante_id = v_restaurante_id and t.codigo_hash = privado.huella_codigo_corto(v_codigo_corto))
      and not exists (
        select 1 from public.codigos_lealtad c
        where c.restaurante_id = v_restaurante_id
          and (c.codigo = v_codigo or c.codigo_hash = privado.huella_codigo_corto(v_codigo_corto)));
  end loop;
  insert into public.codigos_lealtad (restaurante_id, tarjeta_id, codigo, llave_hash, codigo_hash, expira_at)
  values (v_restaurante_id, v_tarjeta_id, v_codigo, privado.huella_aparato(v_llave),
          privado.huella_codigo_corto(v_codigo_corto), now() + interval '10 minutes')
  returning expira_at into v_expira;

  return jsonb_build_object('ok', true, 'codigo', v_codigo, 'vence', v_expira, 'llave', v_llave,
                            'codigo_corto', v_codigo_corto);
end;
$$;

-- La tarjeta del celular, con su historial. Si ese celular pidió pasarla y todavía no lo confirman, motivo «esperando»
-- con su código; si la llave ya no es de ninguna tarjeta (se borró, se pasó a otro celular, o el código venció),
-- «no_existe».
create function public.mi_tarjeta(p_slug text, p_llave text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid := privado.restaurante_del_menu(p_slug);
  v_huella text := privado.huella_aparato(btrim(p_llave));
  v_tarjeta_id bigint;
  v_codigo record;
begin
  if v_restaurante_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'no_hay');
  end if;
  select t.id into v_tarjeta_id
  from public.tarjetas_lealtad t
  where t.restaurante_id = v_restaurante_id and t.llave_hash = v_huella;
  if found then
    return jsonb_build_object(
      'ok', true,
      'hoy', (select privado.dia_local(r.zona_horaria) from public.restaurantes r where r.id = v_restaurante_id),
      'tarjeta', privado.tarjeta_del_celular(v_tarjeta_id));
  end if;
  select c.codigo, c.expira_at into v_codigo
  from public.codigos_lealtad c
  where c.restaurante_id = v_restaurante_id and c.llave_hash = v_huella and c.expira_at > now();
  if found then
    return jsonb_build_object('ok', false, 'motivo', 'esperando', 'codigo', v_codigo.codigo, 'vence', v_codigo.expira_at);
  end if;
  return jsonb_build_object('ok', false, 'motivo', 'no_existe');
end;
$$;

-- «Borrar mi tarjeta»: se va para siempre, con sus movimientos y su código pendiente; las cuentas y los pedidos que la
-- llevaban se quedan sin ella. No se anota (nadie del equipo lo decidió).
create function public.borrar_mi_tarjeta(p_slug text, p_llave text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid := privado.restaurante_del_menu(p_slug);
begin
  if v_restaurante_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'no_hay');
  end if;
  delete from public.tarjetas_lealtad
  where restaurante_id = v_restaurante_id and llave_hash = privado.huella_aparato(btrim(p_llave));
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'no_existe');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function
  public.sacar_tarjeta(text, text, text, boolean, text, text),
  public.pedir_codigo_tarjeta(text, text, text, text),
  public.mi_tarjeta(text, text),
  public.borrar_mi_tarjeta(text, text)
from public, anon, authenticated;

grant execute on function
  public.sacar_tarjeta(text, text, text, boolean, text, text),
  public.pedir_codigo_tarjeta(text, text, text, text),
  public.mi_tarjeta(text, text),
  public.borrar_mi_tarjeta(text, text)
to service_role;


-- ─── El premio de un pedido ───────────────────────────────────────────────────
-- Para Pedidos y para el menú: qué premio usa, si todavía alcanza (mientras está por confirmar: la tarjeta prendida, su
-- premio a la mano, lo juntado y, en pesos, que el pedido lo valga) y si entró a la cuenta al confirmarse. Vacío si no
-- usa premio o su tarjeta se borró.

create function privado.premio_del_pedido(p_pedido_id bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'tipo', l.premio_tipo,
    'nombre', pr.nombre,
    'pesos', l.premio_pesos,
    'alcanza', p.estado = 'por_confirmar' and privado.premio_canjeable(p.restaurante_id) and t.saldo >= l.meta
               and (l.premio_tipo = 'producto' or p.total >= l.premio_pesos),
    'entro', exists (
      select 1 from public.movimientos_lealtad m
      where m.restaurante_id = p.restaurante_id and m.clave = p.clave and m.tipo = 'canje'))
  from public.pedidos_en_linea p
  join public.tarjetas_lealtad t on t.restaurante_id = p.restaurante_id and t.id = p.premio_tarjeta_id
  left join public.lealtad l on l.restaurante_id = p.restaurante_id
  left join public.productos pr on pr.restaurante_id = l.restaurante_id and pr.id = l.premio_producto_id
  where p.id = p_pedido_id;
$$;

revoke execute on function privado.premio_del_pedido(bigint) from public, anon, authenticated, service_role;

-- Como en la migración pedidos; con premio, también el premio (sin premio, igual que antes).
create or replace function privado.pedido_en_json(p_pedido_id bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'numero', p.numero,
    'tipo', p.tipo,
    'cliente_nombre', p.cliente_nombre,
    'cliente_telefono', p.cliente_telefono,
    'cliente_direccion', p.cliente_direccion,
    'cliente_referencias', p.cliente_referencias,
    'paga_con', p.paga_con,
    'total', p.total,
    'created_at', p.created_at,
    'renglones', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'nombre', i.nombre, 'cantidad', i.cantidad, 'precio_unitario', i.precio_unitario,
               'importe', i.importe, 'opciones', i.opciones, 'nota', i.nota)
               order by i.id), '[]')
      from public.pedido_items i
      where i.restaurante_id = p.restaurante_id and i.pedido_id = p.id))
    || case when p.premio_tarjeta_id is not null
         then jsonb_build_object('premio', privado.premio_del_pedido(p.id)) else '{}' end
  from public.pedidos_en_linea p
  where p.id = p_pedido_id;
$$;

-- Como en la migración pedidos; los atendidos con premio dicen también su premio.
create or replace function public.pedidos_del_dia(p_restaurante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r public.restaurantes;
  v_dia date;
  v_pausado boolean;
begin
  if privado.mi_miembro(p_restaurante_id, array['caja', 'gerente']) is null then
    raise exception 'Solo la caja y el gerente de este restaurante ven sus pedidos' using errcode = '42501';
  end if;
  select * into v_r from public.restaurantes where id = p_restaurante_id;
  v_dia := privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte);
  v_pausado := privado.pedidos_pausados(p_restaurante_id);

  return jsonb_build_object(
    'ahora', now(),
    'pausado', v_pausado,
    'pausado_at', case when v_pausado then v_r.pedidos_pausados_at end,
    'recibe', privado.recibe_pedidos(p_restaurante_id),
    'estado', privado.horario_ahora(p_restaurante_id),
    'por_confirmar', (
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id) || privado.pedido_en_json(p.id)
               order by p.created_at, p.id), '[]')
      from public.pedidos_en_linea p
      where p.restaurante_id = p_restaurante_id and p.estado = 'por_confirmar' and p.dia = v_dia),
    'atendidos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', p.id, 'numero', p.numero, 'tipo', p.tipo, 'cliente_nombre', p.cliente_nombre,
               'total', p.total, 'estado', p.estado, 'venta_id', p.venta_id,
               'atendido_por', m.nombre, 'atendido_at', p.atendido_at, 'rechazo_motivo', p.rechazo_motivo)
               || case when p.premio_tarjeta_id is not null
                    then jsonb_build_object('premio', privado.premio_del_pedido(p.id)) else '{}' end
               order by p.atendido_at desc, p.id desc), '[]')
      from public.pedidos_en_linea p
      left join public.miembros m on m.restaurante_id = p.restaurante_id and m.id = p.atendido_por
      where p.restaurante_id = p_restaurante_id and p.estado <> 'por_confirmar' and p.dia = v_dia)
  );
end;
$$;


-- ─── «Hacer pedido», con el premio ────────────────────────────────────────────
-- Como en la migración adaptabilidad, y además p_llave_tarjeta, opcional: sin ella, todo igual que antes. Con ella
-- («Usar mi premio»), el pedido guarda la tarjeta de esa llave si su premio alcanza (la tarjeta prendida, su premio a la
-- mano, lo juntado y, en pesos, que el pedido lo valga); si no, no guarda nada y contesta motivo «premio». Con premio en
-- pesos, «paga con» se compara con el total menos el premio. El premio entra a la cuenta al confirmarse.

drop function public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text);

create function public.hacer_pedido(
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
  p_marca_conexion text,
  p_llave_tarjeta text default null
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
  v_premio record;
  v_tarjeta_id bigint;
  v_menos numeric(12,2) := 0;
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

  -- «Usar mi premio»: la tarjeta de esa llave, si su premio alcanza.
  if nullif(btrim(p_llave_tarjeta), '') is not null then
    select t.id, t.saldo, l.meta, l.premio_tipo, l.premio_pesos into v_premio
    from public.tarjetas_lealtad t
    join public.lealtad l on l.restaurante_id = t.restaurante_id
    where t.restaurante_id = v_r.id and t.llave_hash = privado.huella_aparato(btrim(p_llave_tarjeta));
    if not found or not privado.premio_canjeable(v_r.id) or v_premio.saldo < v_premio.meta
       or (v_premio.premio_tipo = 'pesos' and v_total < v_premio.premio_pesos) then
      return jsonb_build_object('ok', false, 'motivo', 'premio');
    end if;
    v_tarjeta_id := v_premio.id;
    if v_premio.premio_tipo = 'pesos' then
      v_menos := v_premio.premio_pesos;
    end if;
  end if;

  if v_paga_con < v_total - v_menos then
    raise exception 'Con % no alcanza: tu pedido es de %', privado.pesos(v_paga_con), privado.pesos(v_total - v_menos)
      using errcode = '22023';
  end if;

  -- El número corto: el siguiente del día de negocio, del mismo contador que las cuentas sin mesa y sin
  -- nombre del punto de venta.
  v_dia := privado.dia_de_negocio(v_r.zona_horaria, v_r.hora_corte);
  v_numero := privado.numero_del_dia(v_r.id, v_dia);

  insert into public.pedidos_en_linea (
    restaurante_id, dia, numero, tipo, cliente_nombre, cliente_telefono, cliente_direccion,
    cliente_referencias, paga_con, total, clave, marca_celular, marca_conexion, premio_tarjeta_id
  ) values (
    v_r.id, v_dia, v_numero, p_tipo, v_nombre, v_telefono, v_direccion,
    v_referencias, v_paga_con, v_total, p_clave, p_marca_celular, p_marca_conexion, v_tarjeta_id
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

revoke execute on function
  public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text, text)
from public, anon, authenticated;

grant execute on function
  public.hacer_pedido(text, uuid, text, text, text, text, text, numeric, jsonb, text, text, text)
to service_role;


-- ─── El menú que ve la clienta ────────────────────────────────────────────────
-- Como en la migración datos_de_clientes, y además la tarjeta: prendida, con su regla, su premio (disponible = se
-- puede canjear ahora), su estilo y su color ya resuelto (el suyo, o el del menú, o el negro); apagada, solo que
-- existe si tiene regla o tarjetas, para que el aviso de privacidad siga hablando de ella; si no, vacío.

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
      'nombre_legal', v_r.nombre_legal,
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
    'tarjeta', (
      select case
        when l.prendida then jsonb_build_object(
          'prendida', true,
          'forma', l.forma,
          'meta', l.meta,
          'minimo', l.minimo,
          'pesos_por_punto', l.pesos_por_punto,
          'estilo', l.estilo,
          'color', coalesce(l.color, v_r.menu_color, '#121212'),
          'premio', jsonb_build_object(
            'tipo', l.premio_tipo,
            'producto_id', l.premio_producto_id,
            'nombre', p.nombre,
            'nombre_en', p.nombre_en,
            'pesos', l.premio_pesos,
            'pesos_usd', round(l.premio_pesos / v_dolar, 2),
            'disponible', privado.premio_canjeable(v_r.id)))
        when l.meta is not null or exists (select 1 from public.tarjetas_lealtad t where t.restaurante_id = v_r.id)
          then jsonb_build_object('prendida', false)
      end
      from public.lealtad l
      left join public.productos p on p.restaurante_id = l.restaurante_id and p.id = l.premio_producto_id
      where l.restaurante_id = v_r.id),
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


-- ─── «Borrar los datos de un cliente», también su tarjeta ─────────────────────
-- Como en la migración datos_de_clientes, y además borra la tarjeta de ese teléfono en la sucursal, con sus
-- movimientos; la bitácora dice tarjeta: true si borró una. Regresa los pedidos encontrados, como antes (la tarjeta la
-- dice tarjeta_del_cliente).

create or replace function public.borrar_datos_cliente(p_restaurante_id uuid, p_telefono text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_miembro bigint;
  v_telefono text;
  v_datos record;
  v_pedidos integer;
  v_cuentas integer;
  v_tarjetas integer;
begin
  v_miembro := privado.mi_miembro(p_restaurante_id, array['gerente']);
  if v_miembro is null then
    raise exception 'Solo el gerente de este restaurante borra los datos de sus clientes' using errcode = '42501';
  end if;
  v_telefono := privado.telefono_del_cliente(p_telefono);

  select * into v_datos from privado.datos_de_un_cliente(p_restaurante_id, v_telefono);
  delete from public.tarjetas_lealtad where restaurante_id = p_restaurante_id and telefono = v_telefono;
  get diagnostics v_tarjetas = row_count;
  if v_datos.encontrados = 0 and v_tarjetas = 0 then
    return 0;
  end if;

  update public.pedidos_en_linea
  set cliente_telefono = null, cliente_direccion = null, cliente_referencias = null, datos_borrados_at = now()
  where restaurante_id = p_restaurante_id and id = any (v_datos.pedidos) and estado <> 'por_confirmar';
  get diagnostics v_pedidos = row_count;

  update public.ventas
  set cliente_telefono = null, cliente_direccion = null, datos_borrados_at = now()
  where restaurante_id = p_restaurante_id and id = any (v_datos.cuentas) and estado <> 'abierta';
  get diagnostics v_cuentas = row_count;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (p_restaurante_id, v_miembro, 'borrar_datos_cliente', 'restaurantes', p_restaurante_id::text,
          jsonb_build_object('pedidos', v_pedidos, 'cuentas', v_cuentas)
          || case when v_tarjetas > 0 then jsonb_build_object('tarjeta', true) else '{}' end);

  return v_datos.encontrados;
end;
$$;


-- ─── En Cortes, el premio con quién lo canjeó ─────────────────────────────────
-- Como en la migración adaptabilidad; un descuento «Premio de la tarjeta» toma quién lo hizo del canje de su cuenta.

create or replace function privado.descuentos_del_rango(p_restaurante_id uuid, p_desde date, p_hasta date)
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
    select v.id as venta_id, v.folio, v.tipo, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero) as cuenta,
           i.id as renglon_id, i.producto_id, i.nombre, i.cantidad, i.descuento_tipo, i.descuento_valor, i.descuento,
           i.descuento_motivo, 'venta_items' as tabla, i.id::text as registro, v.created_at as abierta_at
    from dia v
    join public.venta_items i on i.restaurante_id = v.restaurante_id and i.venta_id = v.id
    where v.estado = 'cerrada' and i.estado = 'activo' and i.descuento > 0
    union all
    select v.id, v.folio, v.tipo, privado.nombre_de_cuenta(v.mesa_nombre, v.cliente_nombre, v.pedido_numero), null, null, null, null,
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
    where b.restaurante_id = p_restaurante_id
      and ((b.accion = 'descontar' and b.tabla = d.tabla and b.registro_id = d.registro)
           or (b.accion = 'canjear_premio' and d.descuento_motivo = 'Premio de la tarjeta'
               and b.tabla = 'ventas' and b.registro_id = d.venta_id::text))
    order by b.created_at desc, b.id desc
    limit 1
  ) b on true
  left join public.miembros q on q.restaurante_id = p_restaurante_id and q.id = b.miembro_id
  left join public.miembros au on au.restaurante_id = p_restaurante_id and au.id = b.autorizado_por;
$$;


-- ─── Lo que se borra solo ─────────────────────────────────────────────────────
-- Cada noche, con lo de los datos de los clientes: las tarjetas con 12 meses sin compras (o de sacarla, si nunca
-- compró), contados con el día de cada sucursal, se borran con sus movimientos; no se anota. Cada hora, con las
-- preguntas del menú: las solicitudes de más de una hora y los códigos vencidos.

create function privado.borrar_tarjetas_viejas()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_borradas integer;
begin
  delete from public.tarjetas_lealtad t
  using public.restaurantes r
  where r.id = t.restaurante_id
    and (coalesce(t.ultima_compra_at, t.created_at) at time zone r.zona_horaria)::date
        <= (privado.dia_local(r.zona_horaria) - interval '12 months')::date;
  get diagnostics v_borradas = row_count;
  return v_borradas;
end;
$$;

create function privado.borrar_solicitudes_viejas()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_solicitudes integer;
  v_codigos integer;
begin
  delete from public.solicitudes_lealtad where created_at <= now() - interval '1 hour';
  get diagnostics v_solicitudes = row_count;
  delete from public.codigos_lealtad where expira_at <= now();
  get diagnostics v_codigos = row_count;
  return v_solicitudes + v_codigos;
end;
$$;

revoke execute on function
  privado.borrar_tarjetas_viejas(),
  privado.borrar_solicitudes_viejas()
from public, anon, authenticated, service_role;

-- Las dos tareas de siempre llaman a las nuevas: sus órdenes del pg_cron no cambian, y lo que regresan tampoco.

create or replace function privado.vaciar_datos_viejos()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_pedidos integer;
  v_cuentas integer;
begin
  update public.pedidos_en_linea p
  set cliente_telefono = null, cliente_direccion = null, cliente_referencias = null, datos_borrados_at = now()
  from public.restaurantes r
  where r.id = p.restaurante_id
    and p.datos_borrados_at is null
    and num_nonnulls(p.cliente_telefono, p.cliente_direccion, p.cliente_referencias) > 0
    and p.estado <> 'por_confirmar'
    and not exists (
      select 1 from public.ventas v
      where v.restaurante_id = p.restaurante_id and v.id = p.venta_id and v.estado = 'abierta')
    and p.dia <= privado.dia_de_negocio(r.zona_horaria, r.hora_corte)
                 - privado.dias_que_se_guardan(p.estado = 'rechazado');
  get diagnostics v_pedidos = row_count;

  update public.ventas v
  set cliente_telefono = null, cliente_direccion = null, datos_borrados_at = now()
  from public.restaurantes r
  where r.id = v.restaurante_id
    and v.datos_borrados_at is null
    and num_nonnulls(v.cliente_telefono, v.cliente_direccion) > 0
    and v.estado <> 'abierta'
    and v.created_at < privado.inicio_de_dia(
          r.zona_horaria, r.hora_corte,
          privado.dia_de_negocio(r.zona_horaria, r.hora_corte) - privado.dias_que_se_guardan(false) + 1);
  get diagnostics v_cuentas = row_count;

  perform privado.borrar_tarjetas_viejas();
  return v_pedidos + v_cuentas;
end;
$$;

create or replace function privado.borrar_preguntas_viejas()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_borradas integer;
begin
  delete from public.preguntas_menu where created_at <= now() - interval '1 hour';
  get diagnostics v_borradas = row_count;
  perform privado.borrar_solicitudes_viejas();
  return v_borradas;
end;
$$;
