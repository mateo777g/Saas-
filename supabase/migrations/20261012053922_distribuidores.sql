-- Distribuidores: las 5 funciones del paso 2 (libreta 8, "Qué se construye primero"; la
-- vista Distribuidores de la maqueta del panel de Fragmentless, aprobada el 10 de octubre
-- de 2026).
--
-- Con ellas tu panel da de alta a Juanito, liga su cuenta, corrige sus datos, le asigna y
-- le quita clientes, y lo da de baja o lo reactiva. Como las 4 del paso 1, lo primero que
-- hacen es revisar que quien llama esté en plataforma_admins, y sus errores salen en
-- español, tal cual en el panel. Guardan el nombre, el teléfono y el correo sin espacios
-- sobrantes, y un teléfono o un correo en blanco como vacío.
--
-- Una cuenta, un panel (decidido el 11 de octubre de 2026): la cuenta de un distribuidor
-- no puede ser la de Fragmentless ni la de nadie en un restaurante, y al revés. Si Juanito
-- abre su propia taquería, la liga con otra cuenta. Por eso ligar_gerente se vuelve a crear
-- aquí, con esa revisión de más.


-- ─── Una cuenta, un panel ─────────────────────────────────────────────────────

-- ¿La cuenta ya entra a otro panel? Es de Fragmentless, o está en algún restaurante (con
-- cualquier rol, activa o de baja: una fila de baja se puede reactivar en Empleados).
create function privado.cuenta_de_restaurante_o_admin(p_usuario_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.plataforma_admins where usuario_id = p_usuario_id)
      or exists (select 1 from public.miembros where usuario_id = p_usuario_id);
$$;

revoke execute on function privado.cuenta_de_restaurante_o_admin(uuid)
from public, anon, authenticated, service_role;


-- ─── Las 5 funciones de los distribuidores ────────────────────────────────────

-- Nuevo distribuidor. Nace activo, sin cuenta y sin clientes. Regresa su id.
create function public.alta_distribuidor(
  p_nombre text,
  p_telefono text,
  p_correo text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text := btrim(p_nombre);
  v_id bigint;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'Falta el nombre' using errcode = '22023';
  end if;

  insert into public.distribuidores (nombre, telefono, correo)
  values (v_nombre, nullif(btrim(p_telefono), ''), nullif(btrim(p_correo), ''))
  returning id into v_id;

  return v_id;
end;
$$;

-- Anota como suya una cuenta que Fragmentless creó a mano en el dashboard
-- (Authentication → Add user), para que entre a su panel de distribuidor. Cada
-- distribuidor tiene una sola cuenta y cada cuenta es de un solo distribuidor; no hay
-- función para cambiarla ni para desligarla.
create function public.ligar_distribuidor(
  p_distribuidor_id bigint,
  p_correo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_correo text := btrim(p_correo);
  v_nombre text;
  v_cuenta uuid;
  v_usuario_id uuid;
  v_otro text;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if v_correo is null or v_correo = '' then
    raise exception 'Falta el correo' using errcode = '22023';
  end if;

  select nombre, usuario_id into v_nombre, v_cuenta
  from public.distribuidores
  where id = p_distribuidor_id
  for update;
  if not found then
    raise exception 'No existe el distribuidor %', p_distribuidor_id using errcode = 'P0002';
  end if;
  if v_cuenta is not null then
    raise exception '% ya tiene su cuenta ligada', v_nombre using errcode = '23505';
  end if;

  begin
    select id into strict v_usuario_id
    from auth.users
    where lower(email) = lower(v_correo);
  exception
    when no_data_found then
      raise exception 'No hay ninguna cuenta con el correo %; créala primero en Authentication → Add user', v_correo
        using errcode = 'P0002';
    when too_many_rows then
      raise exception 'Hay más de una cuenta con el correo %', v_correo
        using errcode = '21000';
  end;

  select nombre into v_otro
  from public.distribuidores
  where usuario_id = v_usuario_id;
  if found then
    raise exception 'La cuenta % ya está ligada a %', v_correo, v_otro using errcode = '23505';
  end if;
  if privado.cuenta_de_restaurante_o_admin(v_usuario_id) then
    raise exception 'Esa cuenta ya se usa en otro panel; crea otra para su panel de distribuidor'
      using errcode = '23505';
  end if;

  update public.distribuidores
  set usuario_id = v_usuario_id
  where id = p_distribuidor_id;
end;
$$;

-- Corregir datos: su nombre, su teléfono y su correo de contacto. Ese correo no cambia la
-- cuenta con la que entra a su panel.
create function public.editar_distribuidor(
  p_distribuidor_id bigint,
  p_nombre text,
  p_telefono text,
  p_correo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text := btrim(p_nombre);
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'Falta el nombre' using errcode = '22023';
  end if;

  update public.distribuidores
  set nombre = v_nombre,
      telefono = nullif(btrim(p_telefono), ''),
      correo = nullif(btrim(p_correo), '')
  where id = p_distribuidor_id;
  if not found then
    raise exception 'No existe el distribuidor %', p_distribuidor_id using errcode = 'P0002';
  end if;
end;
$$;

-- Asignar y Quitar, desde la ventana de cada distribuidor. Con el distribuidor vacío, el
-- restaurante pasa a ser cliente directo de Fragmentless. Si era de otro distribuidor,
-- pasa en un solo paso: Don Chuy deja a Lupita y queda con Juanito. A quien está de baja
-- no se le asigna nada.
--
-- Bloquea la fila del distribuidor (for share) para que no lo den de baja mientras se le
-- asigna un cliente: fijar_distribuidor_activo espera, y luego cuenta ese cliente.
create function public.asignar_distribuidor(
  p_restaurante_id uuid,
  p_distribuidor_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
  v_activo boolean;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  perform 1 from public.restaurantes where id = p_restaurante_id for update;
  if not found then
    raise exception 'No existe el restaurante %', p_restaurante_id using errcode = 'P0002';
  end if;

  if p_distribuidor_id is not null then
    select nombre, activo into v_nombre, v_activo
    from public.distribuidores
    where id = p_distribuidor_id
    for share;
    if not found then
      raise exception 'No existe el distribuidor %', p_distribuidor_id using errcode = 'P0002';
    end if;
    if not v_activo then
      raise exception '% está de baja; primero usa Reactivar', v_nombre using errcode = '55000';
    end if;
  end if;

  update public.restaurantes
  set distribuidor_id = p_distribuidor_id
  where id = p_restaurante_id
    and distribuidor_id is distinct from p_distribuidor_id;
end;
$$;

-- Dar de baja y Reactivar. No se da de baja a quien todavía tiene clientes, funcionen o
-- no (los mismos que cuenta panel_distribuidores): primero se los quitas. La fila se
-- queda, con su cuenta, para que sus cobros pasados sigan firmados.
create function public.fijar_distribuidor_activo(
  p_distribuidor_id bigint,
  p_activo boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
  v_clientes integer;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  select nombre into v_nombre
  from public.distribuidores
  where id = p_distribuidor_id
  for update;
  if not found then
    raise exception 'No existe el distribuidor %', p_distribuidor_id using errcode = 'P0002';
  end if;

  if not p_activo then
    select count(*)::integer into v_clientes
    from public.restaurantes
    where distribuidor_id = p_distribuidor_id;
    if v_clientes = 1 then
      raise exception '% todavía tiene 1 cliente; quítaselo primero', v_nombre using errcode = '55000';
    elsif v_clientes > 1 then
      raise exception '% todavía tiene % clientes; quítaselos primero', v_nombre, v_clientes
        using errcode = '55000';
    end if;
  end if;

  update public.distribuidores
  set activo = p_activo
  where id = p_distribuidor_id
    and activo is distinct from p_activo;
end;
$$;

revoke execute on function
  public.alta_distribuidor(text, text, text),
  public.ligar_distribuidor(bigint, text),
  public.editar_distribuidor(bigint, text, text, text),
  public.asignar_distribuidor(uuid, bigint),
  public.fijar_distribuidor_activo(bigint, boolean)
from public, anon, service_role;

grant execute on function
  public.alta_distribuidor(text, text, text),
  public.ligar_distribuidor(bigint, text),
  public.editar_distribuidor(bigint, text, text, text),
  public.asignar_distribuidor(uuid, bigint),
  public.fijar_distribuidor_activo(bigint, boolean)
to authenticated;


-- ─── ligar_gerente, con una cuenta, un panel ──────────────────────────────────
-- La misma de la migración plataforma, más una revisión al final: la cuenta no puede ser
-- de un distribuidor (activo o de baja: se puede reactivar) ni de Fragmentless. Si Juanito
-- abre su taquería, se liga con otra cuenta. create or replace conserva sus permisos.

create or replace function public.ligar_gerente(
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

  if exists (select 1 from public.distribuidores where usuario_id = v_usuario_id)
     or exists (select 1 from public.plataforma_admins where usuario_id = v_usuario_id) then
    raise exception 'Esa cuenta ya se usa en otro panel; crea otra para su restaurante'
      using errcode = '23505';
  end if;

  insert into public.miembros (restaurante_id, usuario_id, nombre, roles)
  values (p_restaurante_id, v_usuario_id, p_nombre, array['gerente'])
  returning id into v_miembro_id;

  return v_miembro_id;
end;
$$;
