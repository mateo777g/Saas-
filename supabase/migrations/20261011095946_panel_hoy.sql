-- El día de hoy para el panel de Fragmentless (decidido el 11 de octubre de 2026).
-- La ventana «Dar de alta» trae puesta la fecha de inicio, y la app no saca fechas
-- del reloj del aparato: se la pregunta a Postgres. Se cuenta en la hora de México,
-- la zona con la que nace todo restaurante, con privado.dia_local como todo "hoy".
--
-- Empieza revisando que quien llama esté en plataforma_admins y no cambia datos.

create function public.panel_hoy()
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  return privado.dia_local('America/Mexico_City');
end;
$$;

revoke execute on function public.panel_hoy() from public, anon, service_role;
grant execute on function public.panel_hoy() to authenticated;
