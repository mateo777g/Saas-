-- Lectura del gerente: qué restaurantes tiene y si funcionan hoy (libreta 4, lo decidido
-- el 11 de octubre de 2026). La app no puede contar qué día es, así que Postgres le
-- entrega todo ya contado: de aquí salen la cajita de sucursales, la pantalla de
-- suscripción terminada y la fecha y el saludo de Inicio.
--
-- Es una sola función y no cambia datos. No revisa plataforma_admins: cada quien ve
-- solo lo suyo, por su sesión.


-- ─── Función del gerente ──────────────────────────────────────────────────────

-- Una fila por restaurante donde quien llama es gerente activo, funcione o no: con la
-- licencia vencida o pausada también sale, para que vea la pantalla de suscripción
-- terminada y, si tiene otra sucursal que funciona, "Ir a ella". Quien no es gerente
-- de ningún restaurante (Juanito, o Fragmentless) recibe la lista vacía. Donde solo es
-- cajero, mesero o cocinero no sale: eso es el punto de venta.
--
--   estado        funciona, vencida o pausada, con la regla de privado.vigencias:
--                 vigente y vence_pronto funcionan, y la pausa gana aunque haya vencido
--   licencia_fin  hasta cuándo funcionó o funciona
--   hoy, hora     la fecha y la hora de ahora en la zona del restaurante; la fecha y el
--                 saludo de Inicio salen de aquí, nunca del reloj del dispositivo
--   mi_nombre     su nombre en miembros de ese restaurante, para el saludo
--
-- Va por nombre: la primera que funciona es la que se abre la primera vez en un aparato.

create function public.mis_sucursales()
returns table (
  id uuid,
  nombre text,
  slug text,
  estado text,
  licencia_fin date,
  hoy date,
  hora integer,
  mi_nombre text
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.nombre, r.slug,
         case when v.estado in ('vigente', 'vence_pronto') then 'funciona' else v.estado end,
         r.licencia_fin,
         privado.dia_local(r.zona_horaria),
         extract(hour from now() at time zone r.zona_horaria)::integer,
         m.nombre
  from public.miembros m
  join public.restaurantes r on r.id = m.restaurante_id
  join privado.vigencias() v on v.restaurante_id = r.id
  where m.usuario_id = (select auth.uid())
    and m.activo
    and 'gerente' = any (m.roles)
  order by r.nombre, r.id;
$$;

revoke execute on function public.mis_sucursales() from public, anon, service_role;

grant execute on function public.mis_sucursales() to authenticated;
