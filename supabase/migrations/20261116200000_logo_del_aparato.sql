-- El logo del restaurante en el aparato del equipo (16 de noviembre de 2026; planes/trabajo/aparato-logo/): en /equipo
-- ya no sale la estrella de Fragmentless sino el logo de «Tu restaurante» (el mismo del menú en línea) junto al nombre,
-- desde «¿Quién eres?» y el PIN, antes de que alguien entre. Por eso «¿Quién eres?» también lo dice.
--
-- No hay tablas ni columnas nuevas. El Worker no cambia: pasa la respuesta tal cual.


-- ─── «¿Quién eres?» con el logo ───────────────────────────────────────────────
-- Como en la migración pedidos, y además la ruta en R2 del logo del restaurante (restaurantes.logo_ruta; null: sin
-- logo, el aparato enseña solo el nombre). Reemplazarla conserva sus permisos: solo el Worker la ejecuta.

create or replace function public.nombres_del_aparato(p_token text)
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
    'logo', (select r.logo_ruta from public.restaurantes r where r.id = v_aparato.restaurante_id),
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
    ), '[]'::jsonb),
    'pedidos_por_confirmar', case when exists (
        select 1 from public.miembros m
        where m.restaurante_id = v_aparato.restaurante_id
          and m.activo
          and m.pin_hash is not null
          and 'caja' = any (m.roles)
          and not ('gerente' = any (m.roles))
          and (v_aparato.miembro_id is null or m.id = v_aparato.miembro_id)
      ) then (
        select count(*)
        from public.pedidos_en_linea p
        join public.restaurantes r on r.id = p.restaurante_id
        where p.restaurante_id = v_aparato.restaurante_id
          and p.estado = 'por_confirmar'
          and p.dia = privado.dia_de_negocio(r.zona_horaria, r.hora_corte))
      end
  );
end;
$$;
