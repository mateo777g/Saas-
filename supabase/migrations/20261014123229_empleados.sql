-- Empleados y aparatos con PIN (libreta 5, pieza 2; libreta 3, «El personal: aparato y PIN»;
-- libreta 2, Diccionario de datos: miembros, dispositivos y codigos_vinculo; lo decidido el 14 de
-- octubre de 2026 con la maqueta de Empleados 36iXMMqXCfVv4NuVR7vNSc).
--
-- Pepe no tiene correo ni contraseña: entra con su nombre y su PIN, y solo desde un aparato
-- ligado al restaurante. El Worker hace lo que ningún usuario puede: crea su cuenta, mezcla
-- cada PIN con su llave (la pimienta) antes de que llegue aquí y, con la llave secreta, llama a
-- las cuatro funciones del aparato, que no tiene sesión. Postgres guarda solo huellas.
--
-- El gerente da de alta (por el Worker), corrige nombre y roles y da de baja a su equipo
-- (mesero, caja y cocina; nunca da el rol de gerente), pone PINs, desbloquea, liga aparatos con
-- un código de 6 letras y los desliga. Quien no es gerente solo funciona desde la sesión
-- registrada en un aparato ligado: si entra otra persona en ese aparato, o se desliga, la sesión
-- anterior deja de funcionar al instante.


-- ─── El día de negocio ────────────────────────────────────────────────────────
-- El día empieza a la hora de corte (libreta 5): a las 00:40 del sábado todavía es viernes si el
-- corte es a las 6. La única forma de contarlo, sobre dia_local. Hoy lo usa el bloqueo del PIN
-- («si le vuelve a pasar el mismo día»); después, las ventas.

create function privado.dia_de_negocio(
  p_zona text,
  p_hora_corte smallint,
  p_momento timestamptz default now()
)
returns date
language sql
stable
set search_path = ''
as $$
  select privado.dia_local(p_zona, p_momento - make_interval(hours => p_hora_corte));
$$;


-- ─── miembros: el PIN ─────────────────────────────────────────────────────────

alter table public.miembros
  add column pin_hash text,
  add column tiene_pin boolean generated always as (pin_hash is not null) stored,
  add column intentos_fallidos smallint not null default 0
    constraint miembros_intentos_validos check (intentos_fallidos between 0 and 5),
  add column bloqueado_hasta timestamptz;

-- «Pepe» y «pepe» no conviven entre los activos: la lista de nombres del aparato no confunde.
create unique index miembros_nombre_unico
on public.miembros (restaurante_id, lower(nombre))
where activo;

-- El nombre se guarda sin espacios sobrantes, como el del menú y el de las mesas.
create function privado.limpiar_nombre()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nombre := btrim(new.nombre);
  return new;
end;
$$;

create trigger miembros_limpiar
before insert or update of nombre on public.miembros
for each row execute function privado.limpiar_nombre();


-- ─── dispositivos ─────────────────────────────────────────────────────────────
-- La tableta de la caja (compartida: sale todo el equipo) o el celular de Pepe (de una persona:
-- solo entra él). El aparato guarda un secreto largo y al azar; aquí solo vive su huella.

create table public.dispositivos (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  nombre text not null check (btrim(nombre) <> ''),
  miembro_id bigint,
  token_hash text not null unique
    constraint dispositivos_token_hash_formato check (token_hash ~ '^[0-9a-f]{64}$'),
  sesion_id uuid unique,
  vinculado_por bigint,
  ultimo_uso_at timestamptz,
  revocado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  foreign key (restaurante_id, miembro_id) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, vinculado_por) references public.miembros (restaurante_id, id)
);

create unique index dispositivos_nombre_unico
on public.dispositivos (restaurante_id, lower(nombre))
where revocado_at is null;

create index dispositivos_miembro_idx on public.dispositivos (restaurante_id, miembro_id);
create index dispositivos_vinculado_por_idx on public.dispositivos (restaurante_id, vinculado_por);

create trigger dispositivos_updated_at
before update on public.dispositivos
for each row execute function privado.set_updated_at();

create trigger dispositivos_limpiar
before insert or update of nombre on public.dispositivos
for each row execute function privado.limpiar_nombre();


-- ─── codigos_vinculo ──────────────────────────────────────────────────────────
-- El código de 6 letras de «Vincular aparato». Dura 10 minutos y sirve una sola vez: al usarse
-- se borra y nace su fila en dispositivos. Sin I, L ni O, para no confundirlas con 1 y 0.

create table public.codigos_vinculo (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  codigo text not null unique
    constraint codigos_vinculo_formato check (codigo ~ '^[A-HJKMNP-Z]{6}$'),
  nombre text not null check (btrim(nombre) <> ''),
  miembro_id bigint,
  creado_por bigint,
  expira_at timestamptz not null,
  created_at timestamptz not null default now(),
  foreign key (restaurante_id, miembro_id) references public.miembros (restaurante_id, id),
  foreign key (restaurante_id, creado_por) references public.miembros (restaurante_id, id)
);

create index codigos_vinculo_miembro_idx on public.codigos_vinculo (restaurante_id, miembro_id);
create index codigos_vinculo_creado_por_idx on public.codigos_vinculo (restaurante_id, creado_por);


-- ─── Dar de baja desliga su aparato ───────────────────────────────────────────
-- Si Don Chuy da de baja a Pepe, el celular de Pepe queda desligado: nadie más podría entrar ahí.

create function privado.desligar_aparatos_de_baja()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.activo and not new.activo then
    update public.dispositivos
    set revocado_at = now(), sesion_id = null
    where restaurante_id = new.restaurante_id
      and miembro_id = new.id
      and revocado_at is null;
  end if;
  return null;
end;
$$;

create trigger miembros_desligar_al_dar_de_baja
after update of activo on public.miembros
for each row execute function privado.desligar_aparatos_de_baja();


-- ─── Quien no es gerente, solo desde su aparato ───────────────────────────────
-- La sesión de Supabase trae su session_id. Una persona que no es gerente solo funciona si esa
-- sesión es la registrada en un aparato ligado de su restaurante (y, si el aparato es de una
-- persona, si es suyo). Las funciones auxiliares de RLS lo revisan en cada consulta.

create function privado.sesion_actual()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
$$;

create function privado.desde_su_aparato(p_restaurante_id uuid, p_miembro_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.dispositivos d
    where d.sesion_id = privado.sesion_actual()
      and d.restaurante_id = p_restaurante_id
      and d.revocado_at is null
      and (d.miembro_id is null or d.miembro_id = p_miembro_id)
  );
$$;

create or replace function privado.mis_membresias()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.restaurante_id
  from public.miembros m
  where m.usuario_id = (select auth.uid())
    and m.activo
    and ('gerente' = any (m.roles) or privado.desde_su_aparato(m.restaurante_id, m.id));
$$;

create or replace function privado.mis_restaurantes()
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
    and r.licencia_activa
    and r.licencia_fin >= privado.dia_local(r.zona_horaria)
    and ('gerente' = any (m.roles) or privado.desde_su_aparato(m.restaurante_id, m.id));
$$;

revoke execute on function
  privado.dia_de_negocio(text, smallint, timestamptz),
  privado.limpiar_nombre(),
  privado.desligar_aparatos_de_baja(),
  privado.sesion_actual(),
  privado.desde_su_aparato(uuid, bigint)
from public, anon, authenticated, service_role;


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────

-- miembros: todos leen si alguien ya tiene PIN y si está bloqueado, nunca la huella. El gerente
-- corrige nombre y roles y da de baja a su equipo activo; nunca a un gerente ni para hacerlo
-- gerente. Reactivar no se puede: quien regresa se da de alta otra vez.
grant select (tiene_pin, bloqueado_hasta) on public.miembros to authenticated;
grant update (nombre, roles, activo) on public.miembros to authenticated;

create policy "El gerente corrige y da de baja a su equipo"
on public.miembros for update to authenticated
using (
  restaurante_id in (select privado.mis_restaurantes_gerente())
  and activo
  and not ('gerente' = any (roles))
)
with check (
  restaurante_id in (select privado.mis_restaurantes_gerente())
  and not ('gerente' = any (roles))
);

-- dispositivos: solo el gerente los ve. Nadie escribe directo: se ligan con el código y se
-- desligan con desligar_aparato.
alter table public.dispositivos enable row level security;
revoke all on table public.dispositivos from anon, authenticated;

grant select (
  id, restaurante_id, nombre, miembro_id, vinculado_por, ultimo_uso_at, revocado_at,
  created_at, updated_at
) on public.dispositivos to authenticated;

create policy "El gerente ve los aparatos de sus restaurantes que funcionan"
on public.dispositivos for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes_gerente()));

-- codigos_vinculo: nadie la lee ni la escribe desde la API.
alter table public.codigos_vinculo enable row level security;
revoke all on table public.codigos_vinculo from anon, authenticated;
revoke all on sequence public.codigos_vinculo_id_seq from anon, authenticated;


-- ─── Funciones del gerente ────────────────────────────────────────────────────

-- Lo que pregunta el Worker antes de crearle su cuenta a Pepe: ¿quien llama es gerente de ese
-- restaurante y funciona hoy?
create function public.puedo_cambiar_equipo(p_restaurante_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_restaurante_id in (select privado.mis_restaurantes_gerente());
$$;

-- «Agregar empleado». El Worker ya creó su cuenta (marcada como del personal) y mezcló el PIN
-- con su llave; aquí se anota en miembros con la huella bcrypt del PIN. La cuenta tiene que ser
-- nueva: del personal y sin ningún restaurante.
create function public.alta_empleado(
  p_restaurante_id uuid,
  p_usuario_id uuid,
  p_nombre text,
  p_roles text[],
  p_pin_mezclado text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante puede cambiar su equipo' using errcode = '42501';
  end if;
  if p_roles is null or cardinality(p_roles) = 0
     or not (p_roles <@ array['mesero', 'caja', 'cocina']) then
    raise exception 'Elige al menos un rol: mesero, caja o cocina' using errcode = '22023';
  end if;
  if p_pin_mezclado is null or p_pin_mezclado !~ '^[0-9a-f]{64}$' then
    raise exception 'Falta el PIN' using errcode = '22023';
  end if;
  if not exists (
    select 1 from auth.users
    where id = p_usuario_id
      and raw_app_meta_data ->> 'personal' = 'true'
  ) or exists (
    select 1 from public.miembros where usuario_id = p_usuario_id
  ) then
    raise exception 'Esa cuenta no es una cuenta nueva del personal' using errcode = '42501';
  end if;

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles, pin_hash)
  values (
    p_restaurante_id,
    p_usuario_id,
    p_nombre,
    array(select r from unnest(array['mesero', 'caja', 'cocina']) as r where r = any (p_roles)),
    extensions.crypt(p_pin_mezclado, extensions.gen_salt('bf', 8))
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- «Guardar PIN». El gerente pone el PIN de su equipo activo, y el suyo; el de otro gerente, no.
-- Un PIN nuevo también desbloquea. Llega ya mezclado por el Worker.
create function public.asignar_pin(p_miembro_id bigint, p_pin_mezclado text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurante_id uuid;
  v_usuario_id uuid;
  v_roles text[];
begin
  select restaurante_id, usuario_id, roles into v_restaurante_id, v_usuario_id, v_roles
  from public.miembros
  where id = p_miembro_id
    and activo
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found or ('gerente' = any (v_roles) and v_usuario_id <> (select auth.uid())) then
    raise exception 'Solo el gerente de este restaurante puede cambiar ese PIN' using errcode = '42501';
  end if;
  if p_pin_mezclado is null or p_pin_mezclado !~ '^[0-9a-f]{64}$' then
    raise exception 'Falta el PIN' using errcode = '22023';
  end if;

  update public.miembros
  set pin_hash = extensions.crypt(p_pin_mezclado, extensions.gen_salt('bf', 8)),
      intentos_fallidos = 0,
      bloqueado_hasta = null
  where id = p_miembro_id;
end;
$$;

-- «Desbloquear»: a alguien de su equipo, o a sí mismo si se bloqueó autorizando.
create function public.desbloquear_miembro(p_miembro_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_roles text[];
begin
  select usuario_id, roles into v_usuario_id, v_roles
  from public.miembros
  where id = p_miembro_id
    and activo
    and restaurante_id in (select privado.mis_restaurantes_gerente())
  for update;
  if not found or ('gerente' = any (v_roles) and v_usuario_id <> (select auth.uid())) then
    raise exception 'Solo el gerente de este restaurante puede desbloquear a su equipo' using errcode = '42501';
  end if;

  update public.miembros
  set intentos_fallidos = 0, bloqueado_hasta = null
  where id = p_miembro_id;
end;
$$;

-- «Crear código» en «Vincular aparato». Regresa el código de 6 letras y cuándo vence. Si el
-- aparato es de una persona, tiene que ser alguien activo de su equipo, no un gerente.
create function public.crear_codigo_vinculo(
  p_restaurante_id uuid,
  p_nombre text,
  p_miembro_id bigint
)
returns table (codigo text, expira_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_creado_por bigint;
  v_nombre text := btrim(p_nombre);
  v_letras constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ';
  v_codigo text;
  v_byte integer;
  v_azar bytea;
  v_intento integer := 0;
begin
  select m.id into v_creado_por
  from public.miembros m
  where m.restaurante_id = p_restaurante_id
    and m.usuario_id = (select auth.uid())
    and m.restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede ligar aparatos' using errcode = '42501';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'Escribe el nombre del aparato' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.dispositivos d
    where d.restaurante_id = p_restaurante_id
      and d.revocado_at is null
      and lower(d.nombre) = lower(v_nombre)
  ) then
    raise exception 'Ya tienes un aparato que se llama «%»', v_nombre using errcode = '23505';
  end if;
  if p_miembro_id is not null and not exists (
    select 1 from public.miembros m
    where m.id = p_miembro_id
      and m.restaurante_id = p_restaurante_id
      and m.activo
      and not ('gerente' = any (m.roles))
  ) then
    raise exception 'Ese aparato solo puede ser de alguien activo de tu equipo' using errcode = '22023';
  end if;

  -- Los vencidos ya no sirven: se limpian al pedir uno nuevo.
  delete from public.codigos_vinculo c where c.expira_at <= now();

  loop
    v_intento := v_intento + 1;
    v_codigo := '';
    -- Letras al azar sin sesgo: cada byte de 0 a 229 elige una de las 23 (230 = 23 × 10).
    while char_length(v_codigo) < 6 loop
      v_azar := extensions.gen_random_bytes(12);
      for i in 0..11 loop
        v_byte := get_byte(v_azar, i);
        if v_byte < 230 and char_length(v_codigo) < 6 then
          v_codigo := v_codigo || substr(v_letras, (v_byte % 23) + 1, 1);
        end if;
      end loop;
    end loop;
    begin
      insert into public.codigos_vinculo (restaurante_id, codigo, nombre, miembro_id, creado_por, expira_at)
      values (p_restaurante_id, v_codigo, v_nombre, p_miembro_id, v_creado_por, now() + interval '10 minutes')
      returning codigos_vinculo.codigo, codigos_vinculo.expira_at into codigo, expira_at;
      return next;
      return;
    exception
      when unique_violation then
        if v_intento >= 5 then
          raise;
        end if;
    end;
  end loop;
end;
$$;

-- «Desligar»: el aparato ya no entra, y quien esté adentro sale en su siguiente consulta.
create function public.desligar_aparato(p_dispositivo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.dispositivos
  set revocado_at = now(), sesion_id = null
  where id = p_dispositivo_id
    and revocado_at is null
    and restaurante_id in (select privado.mis_restaurantes_gerente());
  if not found then
    raise exception 'Solo el gerente de este restaurante puede desligar sus aparatos' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function
  public.puedo_cambiar_equipo(uuid),
  public.alta_empleado(uuid, uuid, text, text[], text),
  public.asignar_pin(bigint, text),
  public.desbloquear_miembro(bigint),
  public.crear_codigo_vinculo(uuid, text, bigint),
  public.desligar_aparato(uuid)
from public, anon, service_role;

grant execute on function
  public.puedo_cambiar_equipo(uuid),
  public.alta_empleado(uuid, uuid, text, text[], text),
  public.asignar_pin(bigint, text),
  public.desbloquear_miembro(bigint),
  public.crear_codigo_vinculo(uuid, text, bigint),
  public.desligar_aparato(uuid)
to authenticated;


-- ─── Funciones del aparato (solo el Worker, con la llave secreta) ─────────────
-- El aparato no tiene sesión: el Worker llama a estas cuatro como service_role, con el secreto
-- del aparato. Ninguna la puede llamar un usuario.

-- La huella del secreto del aparato. El secreto son 32 bytes al azar en base64url.
create function privado.huella_aparato(p_token text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_token ~ '^[A-Za-z0-9_-]{43}$' then encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
  end;
$$;

-- El aparato ligado, en un restaurante que funciona hoy. Si no, un error que el aparato enseña.
create function privado.aparato_vigente(p_token text)
returns public.dispositivos
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_aparato public.dispositivos;
begin
  select * into v_aparato
  from public.dispositivos
  where token_hash = privado.huella_aparato(p_token)
    and revocado_at is null;
  if not found then
    raise exception 'Este aparato ya no está ligado. Pídele a tu gerente un código nuevo.' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.restaurantes r
    where r.id = v_aparato.restaurante_id
      and r.licencia_activa
      and r.licencia_fin >= privado.dia_local(r.zona_horaria)
  ) then
    raise exception 'La suscripción de este restaurante no está vigente. Avísale a tu gerente.' using errcode = '42501';
  end if;
  return v_aparato;
end;
$$;

revoke execute on function
  privado.huella_aparato(text),
  privado.aparato_vigente(text)
from public, anon, authenticated, service_role;

-- «Vincular»: Pepe escribe el código en su celular. Nace el aparato con la huella del secreto
-- que el Worker le generó, y el código se borra. Regresa cómo se llama y de quién es.
create function public.vincular_aparato(p_codigo text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_codigo public.codigos_vinculo;
  v_huella text := privado.huella_aparato(p_token);
  v_id uuid;
begin
  if v_huella is null then
    raise exception 'El secreto del aparato no es válido' using errcode = '22023';
  end if;

  select * into v_codigo
  from public.codigos_vinculo
  where codigo = upper(btrim(p_codigo))
    and expira_at > now()
  for update;
  if not found then
    raise exception 'Ese código no existe o ya venció. Pídele otro a tu gerente.' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.restaurantes r
    where r.id = v_codigo.restaurante_id
      and r.licencia_activa
      and r.licencia_fin >= privado.dia_local(r.zona_horaria)
  ) then
    raise exception 'La suscripción de este restaurante no está vigente. Avísale a tu gerente.' using errcode = '42501';
  end if;
  if v_codigo.miembro_id is not null and not exists (
    select 1 from public.miembros m
    where m.id = v_codigo.miembro_id
      and m.restaurante_id = v_codigo.restaurante_id
      and m.activo
      and not ('gerente' = any (m.roles))
  ) then
    raise exception 'La persona de este aparato ya no está en el equipo. Pídele otro código a tu gerente.' using errcode = '22023';
  end if;

  delete from public.codigos_vinculo where id = v_codigo.id;

  insert into public.dispositivos (restaurante_id, nombre, miembro_id, token_hash, vinculado_por)
  values (v_codigo.restaurante_id, v_codigo.nombre, v_codigo.miembro_id, v_huella, v_codigo.creado_por)
  returning id into v_id;

  return jsonb_build_object(
    'dispositivo_id', v_id,
    'aparato', v_codigo.nombre,
    'compartido', v_codigo.miembro_id is null
  );
end;
$$;

-- «¿Quién eres?»: el restaurante, el aparato y quiénes pueden entrar ahí. En uno compartido,
-- todo el equipo activo con PIN (sin los gerentes); en uno de una persona, solo ella. De quien
-- está bloqueado dice hasta qué hora (vacía = hasta que su gerente lo desbloquee).
create function public.nombres_del_aparato(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_aparato public.dispositivos := privado.aparato_vigente(p_token);
begin
  return jsonb_build_object(
    'restaurante', (select r.nombre from public.restaurantes r where r.id = v_aparato.restaurante_id),
    'aparato', v_aparato.nombre,
    'compartido', v_aparato.miembro_id is null,
    'personas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'nombre', m.nombre,
        'roles', to_jsonb(m.roles),
        'bloqueado', coalesce(m.bloqueado_hasta > now(), false),
        'bloqueado_hasta', case when m.bloqueado_hasta > now() and m.bloqueado_hasta <> 'infinity'
                                then m.bloqueado_hasta end
      ) order by lower(m.nombre), m.id)
      from public.miembros m
      where m.restaurante_id = v_aparato.restaurante_id
        and m.activo
        and m.pin_hash is not null
        and not ('gerente' = any (m.roles))
        and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
    ), '[]'::jsonb)
  );
end;
$$;

-- Pepe toca su nombre y pone su PIN. No lanza error con un PIN equivocado, para que el intento
-- quede guardado: regresa {ok: false} con cuántos quedan, o hasta cuándo está bloqueado (null =
-- hasta que su gerente lo desbloquee). Al quinto, 15 minutos; si ya le había pasado ese día de
-- negocio, hasta que lo desbloqueen. Si entra bien, regresa su cuenta para que el Worker le dé
-- su sesión.
create function public.entrar_con_pin(p_token text, p_miembro_id bigint, p_pin_mezclado text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_aparato public.dispositivos := privado.aparato_vigente(p_token);
  v_miembro public.miembros;
  v_zona text;
  v_corte smallint;
  v_hasta timestamptz;
begin
  select * into v_miembro
  from public.miembros m
  where m.id = p_miembro_id
    and m.restaurante_id = v_aparato.restaurante_id
    and m.activo
    and m.pin_hash is not null
    and not ('gerente' = any (m.roles))
    and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
  for update;
  if not found then
    raise exception 'Esa persona no puede entrar en este aparato' using errcode = '42501';
  end if;

  if v_miembro.bloqueado_hasta > now() then
    return jsonb_build_object('ok', false, 'motivo', 'bloqueado',
      'hasta', case when v_miembro.bloqueado_hasta <> 'infinity' then v_miembro.bloqueado_hasta end);
  end if;

  if p_pin_mezclado ~ '^[0-9a-f]{64}$'
     and extensions.crypt(p_pin_mezclado, v_miembro.pin_hash) = v_miembro.pin_hash then
    update public.miembros set intentos_fallidos = 0 where id = v_miembro.id;
    update public.dispositivos set ultimo_uso_at = now() where id = v_aparato.id;
    return jsonb_build_object(
      'ok', true,
      'usuario_id', v_miembro.usuario_id,
      'correo', (select u.email from auth.users u where u.id = v_miembro.usuario_id)
    );
  end if;

  if v_miembro.intentos_fallidos + 1 < 5 then
    update public.miembros set intentos_fallidos = intentos_fallidos + 1 where id = v_miembro.id;
    return jsonb_build_object('ok', false, 'motivo', 'pin', 'quedan', 4 - v_miembro.intentos_fallidos);
  end if;

  select zona_horaria, hora_corte into v_zona, v_corte
  from public.restaurantes where id = v_miembro.restaurante_id;

  -- bloqueado_hasta conserva el fin del bloqueo anterior: empezó 15 minutos antes.
  if v_miembro.bloqueado_hasta is not null
     and privado.dia_de_negocio(v_zona, v_corte, v_miembro.bloqueado_hasta - interval '15 minutes')
         = privado.dia_de_negocio(v_zona, v_corte) then
    v_hasta := 'infinity';
  else
    v_hasta := now() + interval '15 minutes';
  end if;

  update public.miembros
  set intentos_fallidos = 0, bloqueado_hasta = v_hasta
  where id = v_miembro.id;

  return jsonb_build_object('ok', false, 'motivo', 'bloqueado',
    'hasta', case when v_hasta <> 'infinity' then v_hasta end);
end;
$$;

-- Después de entrar_con_pin, el Worker le dio a Pepe su sesión de Supabase y la registra aquí:
-- es la única que funciona en ese aparato. La de quien estaba antes deja de funcionar.
create function public.registrar_sesion(p_token text, p_miembro_id bigint, p_sesion_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_aparato public.dispositivos := privado.aparato_vigente(p_token);
begin
  if p_sesion_id is null then
    raise exception 'Falta la sesión' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.miembros m
    where m.id = p_miembro_id
      and m.restaurante_id = v_aparato.restaurante_id
      and m.activo
      and not ('gerente' = any (m.roles))
      and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
  ) then
    raise exception 'Esa persona no puede entrar en este aparato' using errcode = '42501';
  end if;

  update public.dispositivos set sesion_id = null where sesion_id = p_sesion_id and id <> v_aparato.id;
  update public.dispositivos set sesion_id = p_sesion_id where id = v_aparato.id;
end;
$$;

revoke execute on function
  public.vincular_aparato(text, text),
  public.nombres_del_aparato(text),
  public.entrar_con_pin(text, bigint, text),
  public.registrar_sesion(text, bigint, uuid)
from public, anon, authenticated;

grant execute on function
  public.vincular_aparato(text, text),
  public.nombres_del_aparato(text),
  public.entrar_con_pin(text, bigint, text),
  public.registrar_sesion(text, bigint, uuid)
to service_role;
