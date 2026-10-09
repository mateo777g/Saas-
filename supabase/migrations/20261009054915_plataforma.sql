-- Plataforma: las 4 tablas del paso 1 (libreta 8, "Qué se construye primero").
--
-- restaurantes, plataforma_admins, distribuidores y miembros, con sus columnas del
-- Diccionario de datos (libreta 2), salvo las que llegan después: miembros.pin_hash,
-- intentos_fallidos y bloqueado_hasta (migración del PIN) y restaurantes.modulos
-- (primer módulo).
--
-- Nadie escribe directo en estas tablas: anon no tiene ningún permiso, authenticated
-- solo lee (por columnas y con RLS), y Fragmentless cambia datos únicamente con sus
-- 4 funciones de abajo. La fila del developer en plataforma_admins se pone a mano,
-- una sola vez, después del push.


-- ─── Esquema privado ──────────────────────────────────────────────────────────
-- La Data API expone solo public y graphql_public: nada de aquí se puede llamar
-- desde la API. authenticated necesita usage porque las reglas RLS llaman a sus
-- funciones.

create schema privado;
grant usage on schema privado to authenticated;

create function privado.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- El día de calendario en una zona horaria. Es la única forma de contar "hoy" en la
-- base: la licencia vale hasta las 11:59 pm de su día de fin en la zona del
-- restaurante. p_momento existe para que las pruebas fijen la hora.
create function privado.dia_local(p_zona text, p_momento timestamptz default now())
returns date
language sql
stable
set search_path = ''
as $$
  select (p_momento at time zone p_zona)::date;
$$;


-- ─── distribuidores ───────────────────────────────────────────────────────────
-- Quienes venden Fragmentless en persona (Juanito). Solo Fragmentless la escribe;
-- cada distribuidor lee su propia fila.

create table public.distribuidores (
  id bigint generated always as identity primary key,
  nombre text not null check (btrim(nombre) <> ''),
  telefono text,
  correo text,
  usuario_id uuid unique references auth.users (id),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger distribuidores_updated_at
before update on public.distribuidores
for each row execute function privado.set_updated_at();


-- ─── restaurantes ─────────────────────────────────────────────────────────────
-- Una fila por cliente (la fonda de Don Chuy). Su id es el restaurante_id de todo
-- lo demás y el nombre de su carpeta en R2.

create table public.restaurantes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (btrim(nombre) <> ''),
  slug text not null unique
    constraint restaurantes_slug_formato check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  telefono text,
  pagina_web text,
  direccion text,
  logo_ruta text,
  zona_horaria text not null default 'America/Mexico_City',
  hora_corte smallint not null default 6 check (hora_corte between 0 and 23),
  licencia_activa boolean not null default false,
  licencia_inicio date,
  licencia_fin date,
  tope_ia_usd_mes numeric(10,2) not null default 0 check (tope_ia_usd_mes >= 0),
  distribuidor_id bigint references public.distribuidores (id),
  plan text not null default 'basico' check (plan in ('basico', 'pro')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Con licencia_fin vacía la licencia no vale, así que tampoco se puede prender.
  constraint restaurantes_licencia_con_fin check (not licencia_activa or licencia_fin is not null)
);

create index restaurantes_distribuidor_id_idx on public.restaurantes (distribuidor_id);

create trigger restaurantes_updated_at
before update on public.restaurantes
for each row execute function privado.set_updated_at();

-- Una zona mal escrita rompería los días y la licencia. Un check no puede consultar
-- pg_timezone_names, por eso es un trigger.
create function privado.validar_zona_horaria()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.zona_horaria) then
    raise exception 'Zona horaria desconocida: %', new.zona_horaria
      using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger restaurantes_zona_horaria
before insert or update of zona_horaria on public.restaurantes
for each row execute function privado.validar_zona_horaria();


-- ─── plataforma_admins ────────────────────────────────────────────────────────
-- Las cuentas de Fragmentless. No hay función para agregar admins.

create table public.plataforma_admins (
  usuario_id uuid primary key references auth.users (id),
  created_at timestamptz not null default now()
);


-- ─── miembros ─────────────────────────────────────────────────────────────────
-- Quién trabaja en cada restaurante. Una persona puede estar en varios, con una
-- fila en cada uno. La baja es activo = false: la fila se queda.

create table public.miembros (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references public.restaurantes (id) on delete cascade,
  usuario_id uuid not null references auth.users (id),
  nombre text not null check (btrim(nombre) <> ''),
  roles text[] not null
    check (cardinality(roles) > 0 and roles <@ array['gerente', 'caja', 'mesero', 'cocina']),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (restaurante_id, id),
  unique (restaurante_id, usuario_id)
);

create index miembros_usuario_id_idx on public.miembros (usuario_id);

create trigger miembros_updated_at
before update on public.miembros
for each row execute function privado.set_updated_at();

-- Siempre queda un gerente: nadie le quita el rol ni da de baja (ni borra) al
-- último gerente activo de un restaurante. Es after para ver el cambio completo
-- (si una sola orden da de baja a dos gerentes, también falla). Lo único que pasa
-- es el borrado en cascada del restaurante completo: ahí el restaurante ya no existe.
create function privado.siempre_un_gerente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (old.activo and 'gerente' = any (old.roles)) then
    return null;
  end if;

  if not exists (select 1 from public.restaurantes where id = old.restaurante_id) then
    return null;
  end if;

  if not exists (
    select 1 from public.miembros
    where restaurante_id = old.restaurante_id
      and activo
      and 'gerente' = any (roles)
  ) then
    raise exception 'No se puede quitar al último gerente activo del restaurante';
  end if;

  return null;
end;
$$;

create trigger miembros_siempre_un_gerente
after update of roles, activo, restaurante_id or delete on public.miembros
for each row execute function privado.siempre_un_gerente();


-- ─── Funciones auxiliares de RLS ──────────────────────────────────────────────
-- security definer para leer miembros y restaurantes sin pasar por su propio RLS.
-- Las reglas las envuelven en (select …) para que corran una vez por consulta.

-- ¿Quien llama es de Fragmentless?
create function privado.soy_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.plataforma_admins
    where usuario_id = (select auth.uid())
  );
$$;

-- Restaurantes donde soy miembro activo, con o sin licencia. Solo para leer la fila
-- del propio restaurante y mostrar que la suscripción terminó.
create function privado.mis_membresias()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select restaurante_id
  from public.miembros
  where usuario_id = (select auth.uid())
    and activo;
$$;

-- Restaurantes donde soy miembro activo y la licencia vale: prendida y con su fecha
-- de fin hoy o después, contando el día en la zona del restaurante.
create function privado.mis_restaurantes()
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
    and r.licencia_fin >= privado.dia_local(r.zona_horaria);
$$;

revoke execute on all functions in schema privado from public, anon, authenticated, service_role;
grant execute on function
  privado.soy_admin(),
  privado.mis_membresias(),
  privado.mis_restaurantes()
to authenticated;


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────
-- Fuera todo lo que Supabase da por defecto; authenticated solo lee, columna por
-- columna. No hay reglas de insert, update ni delete.

alter table public.restaurantes enable row level security;
alter table public.plataforma_admins enable row level security;
alter table public.distribuidores enable row level security;
alter table public.miembros enable row level security;

revoke all on table
  public.restaurantes,
  public.plataforma_admins,
  public.distribuidores,
  public.miembros
from anon, authenticated;

revoke all on sequence
  public.distribuidores_id_seq,
  public.miembros_id_seq
from anon, authenticated;

grant select (
  id, nombre, slug, telefono, pagina_web, direccion, logo_ruta, zona_horaria, hora_corte,
  licencia_activa, licencia_inicio, licencia_fin, tope_ia_usd_mes, distribuidor_id, plan,
  created_at, updated_at
) on public.restaurantes to authenticated;

grant select (usuario_id, created_at) on public.plataforma_admins to authenticated;

grant select (
  id, nombre, telefono, correo, usuario_id, activo, created_at, updated_at
) on public.distribuidores to authenticated;

grant select (
  id, restaurante_id, usuario_id, nombre, roles, activo, created_at, updated_at
) on public.miembros to authenticated;

create policy "Cada miembro activo lee su restaurante"
on public.restaurantes for select to authenticated
using (id in (select privado.mis_membresias()));

create policy "Fragmentless lee todos los restaurantes"
on public.restaurantes for select to authenticated
using ((select privado.soy_admin()));

create policy "Fragmentless lee plataforma_admins"
on public.plataforma_admins for select to authenticated
using ((select privado.soy_admin()));

create policy "Cada distribuidor lee su propia fila"
on public.distribuidores for select to authenticated
using (usuario_id = (select auth.uid()));

create policy "Fragmentless lee todos los distribuidores"
on public.distribuidores for select to authenticated
using ((select privado.soy_admin()));

-- Fragmentless no lee miembros de ningún restaurante.
create policy "Los miembros leen los miembros de sus restaurantes con licencia vigente"
on public.miembros for select to authenticated
using (restaurante_id in (select privado.mis_restaurantes()));


-- ─── Funciones de Fragmentless ────────────────────────────────────────────────
-- Lo único que cambia datos en estas tablas. Lo primero que hacen es revisar que
-- quien llama esté en plataforma_admins.

-- Da de alta un restaurante con la licencia prendida. El fin son los meses contados
-- desde el inicio: alta el 8 de octubre con 1 mes, fin el 8 de noviembre.
create function public.alta_restaurante(
  p_nombre text,
  p_slug text,
  p_inicio date,
  p_meses integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if p_inicio is null then
    raise exception 'Falta la fecha de inicio' using errcode = '22023';
  end if;
  if p_meses is null or p_meses < 1 then
    raise exception 'Los meses deben ser 1 o más' using errcode = '22023';
  end if;

  insert into public.restaurantes (nombre, slug, licencia_activa, licencia_inicio, licencia_fin)
  values (p_nombre, p_slug, true, p_inicio, (p_inicio + make_interval(months => p_meses))::date)
  returning id into v_id;

  return v_id;
end;
$$;

-- Anota como gerente una cuenta que Fragmentless creó a mano en el dashboard
-- (Authentication → Add user). Una persona puede ser gerente de varios
-- restaurantes, pero no puede ligarse dos veces al mismo.
create function public.ligar_gerente(
  p_restaurante_id uuid,
  p_correo text,
  p_nombre text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_miembro_id bigint;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if not exists (select 1 from public.restaurantes where id = p_restaurante_id) then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;

  begin
    select id into strict v_usuario_id
    from auth.users
    where lower(email) = lower(btrim(p_correo));
  exception
    when no_data_found then
      raise exception 'No hay ninguna cuenta con el correo %; créala primero en Authentication → Add user', p_correo
        using errcode = 'P0002';
    when too_many_rows then
      raise exception 'Hay más de una cuenta con el correo %', p_correo
        using errcode = '21000';
  end;

  if exists (
    select 1 from public.miembros
    where restaurante_id = p_restaurante_id and usuario_id = v_usuario_id
  ) then
    raise exception 'La cuenta % ya está ligada a este restaurante', p_correo
      using errcode = '23505';
  end if;

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles)
  values (p_restaurante_id, v_usuario_id, p_nombre, array['gerente'])
  returning id into v_miembro_id;

  return v_miembro_id;
end;
$$;

-- Suma meses a la licencia y regresa el nuevo fin. Cuenta desde la fecha mayor
-- entre su fin y hoy (en su zona): si Don Chuy paga antes, se suma a su fin; si
-- paga tarde, cuenta desde el día que paga. No prende la licencia si está pausada.
create function public.extender_licencia(
  p_restaurante_id uuid,
  p_meses integer
)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fin date;
  v_zona text;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if p_meses is null or p_meses < 1 then
    raise exception 'Los meses deben ser 1 o más' using errcode = '22023';
  end if;

  select licencia_fin, zona_horaria into v_fin, v_zona
  from public.restaurantes
  where id = p_restaurante_id
  for update;
  if not found then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;

  v_fin := (greatest(v_fin, privado.dia_local(v_zona)) + make_interval(months => p_meses))::date;

  update public.restaurantes
  set licencia_fin = v_fin
  where id = p_restaurante_id;

  return v_fin;
end;
$$;

-- Pausa, reactiva o corrige las fechas de una licencia, tal cual se le dan.
create function public.fijar_licencia(
  p_restaurante_id uuid,
  p_activa boolean,
  p_inicio date,
  p_fin date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  update public.restaurantes
  set licencia_activa = p_activa,
      licencia_inicio = p_inicio,
      licencia_fin = p_fin
  where id = p_restaurante_id;
  if not found then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function
  public.alta_restaurante(text, text, date, integer),
  public.ligar_gerente(uuid, text, text),
  public.extender_licencia(uuid, integer),
  public.fijar_licencia(uuid, boolean, date, date)
from public, anon, service_role;

grant execute on function
  public.alta_restaurante(text, text, date, integer),
  public.ligar_gerente(uuid, text, text),
  public.extender_licencia(uuid, integer),
  public.fijar_licencia(uuid, boolean, date, date)
to authenticated;
