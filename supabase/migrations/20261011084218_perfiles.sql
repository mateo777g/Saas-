-- Perfiles: lo que es de la persona y no de un restaurante (libreta 2, Diccionario de
-- datos; libreta 4, lo decidido el 11 de octubre de 2026). Por ahora solo el apodo, que
-- usan el saludo de Inicio y el agente IA y vale en todas las sucursales de la persona.
-- El nombre completo se queda en miembros, una fila por restaurante.
--
-- Nadie escribe directo en perfiles: cada quien lee su fila y la cambia con
-- guardar_perfil, que además corrige su nombre en todas sus sucursales.


-- ─── perfiles ─────────────────────────────────────────────────────────────────
-- Una fila por cuenta. Nace la primera vez que la persona guarda su perfil; sin fila,
-- o con el apodo vacío, la llaman por su nombre de miembros.

create table public.perfiles (
  usuario_id uuid primary key references auth.users (id),
  apodo text
    constraint perfiles_apodo_formato check (apodo is null or (btrim(apodo) <> '' and char_length(apodo) <= 20)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger perfiles_updated_at
before update on public.perfiles
for each row execute function privado.set_updated_at();


-- ─── Permisos y RLS ───────────────────────────────────────────────────────────

alter table public.perfiles enable row level security;

revoke all on table public.perfiles from anon, authenticated;

grant select (usuario_id, apodo, created_at, updated_at) on public.perfiles to authenticated;

create policy "Cada quien lee su propio perfil"
on public.perfiles for select to authenticated
using (usuario_id = (select auth.uid()));


-- ─── Función del perfil ───────────────────────────────────────────────────────

-- Lo que hace el botón Guardar de la ventana Perfil. Corrige el nombre de quien llama
-- en todas sus sucursales (cada fila activa suya en miembros, sea gerente, cajero o lo
-- que sea ahí) y guarda su apodo; un apodo vacío lo deja sin apodo. Los dos se guardan
-- sin espacios sobrantes. Solo la usa quien es gerente activo de un restaurante que
-- funciona: Toño, el mesero, no se cambia el nombre solo; se lo cambia su gerente en
-- Empleados.
create function public.guardar_perfil(p_nombre text, p_apodo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid := (select auth.uid());
  v_nombre text := btrim(p_nombre);
  v_apodo text := nullif(btrim(p_apodo), '');
begin
  if not exists (
    select 1 from public.miembros
    where usuario_id = v_usuario_id
      and activo
      and 'gerente' = any (roles)
      and restaurante_id in (select privado.mis_restaurantes())
  ) then
    raise exception 'Solo el gerente de un restaurante que funciona puede cambiar su perfil'
      using errcode = '42501';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'Escribe tu nombre completo' using errcode = '22023';
  end if;
  if char_length(v_apodo) > 20 then
    raise exception 'Cómo te llamamos: máximo 20 letras' using errcode = '22023';
  end if;

  update public.miembros
  set nombre = v_nombre
  where usuario_id = v_usuario_id
    and activo
    and nombre is distinct from v_nombre;

  insert into public.perfiles (usuario_id, apodo)
  values (v_usuario_id, v_apodo)
  on conflict (usuario_id) do update set apodo = excluded.apodo;
end;
$$;

revoke execute on function public.guardar_perfil(text, text) from public, anon, service_role;

grant execute on function public.guardar_perfil(text, text) to authenticated;
