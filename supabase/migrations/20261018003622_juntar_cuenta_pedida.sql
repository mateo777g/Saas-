-- Juntar mesas le quita la marca «Pidió la cuenta» a la cuenta que recibe (decidido el 17 de
-- octubre de 2026, en la prueba de verdad de la parte 4a): la cuenta que vio el cliente ya cambió,
-- igual que al mandar algo después de pedirla. Lo demás de juntar_mesas queda igual; reemplazarla
-- conserva sus permisos (solo authenticated la ejecuta).

create or replace function public.juntar_mesas(p_venta_id bigint, p_destino_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origen record;
  v_destino record;
  v_miembro bigint;
begin
  if p_venta_id is null or p_destino_id is null or p_venta_id = p_destino_id then
    raise exception 'Elige otra mesa para juntarla' using errcode = '22023';
  end if;

  -- Las dos cuentas se bloquean siempre en el mismo orden: dos juntas cruzadas no se atoran.
  perform 1
  from public.ventas
  where id in (p_venta_id, p_destino_id) and restaurante_id in (select privado.mis_restaurantes())
  order by id
  for update;

  select id, restaurante_id, tipo, mesa_nombre into v_origen
  from public.ventas
  where id = p_venta_id and estado = 'abierta' and restaurante_id in (select privado.mis_restaurantes());
  if not found then
    raise exception 'Esa cuenta ya no está abierta' using errcode = '55000';
  end if;
  v_miembro := privado.mi_miembro(v_origen.restaurante_id, array['mesero', 'caja', 'gerente']);
  if v_miembro is null then
    raise exception 'Solo meseros, caja y gerentes de este restaurante juntan mesas' using errcode = '42501';
  end if;

  select id, tipo, mesa_nombre into v_destino
  from public.ventas
  where id = p_destino_id and estado = 'abierta' and restaurante_id = v_origen.restaurante_id;
  if not found then
    raise exception 'La cuenta de esa mesa ya no está abierta' using errcode = '55000';
  end if;
  if v_origen.tipo <> 'mesa' or v_destino.tipo <> 'mesa' then
    raise exception 'Solo se juntan cuentas de mesa' using errcode = '22023';
  end if;

  update public.venta_items set venta_id = p_destino_id
  where restaurante_id = v_origen.restaurante_id and venta_id = p_venta_id;
  update public.comandas set venta_id = p_destino_id
  where restaurante_id = v_origen.restaurante_id and venta_id = p_venta_id;
  update public.ventas
  set estado = 'cancelada', cancelada_motivo = 'Se juntó con «' || v_destino.mesa_nombre || '»'
  where id = p_venta_id;
  -- La cuenta que vio el cliente ya cambió: la que recibe deja de decir «Pidió la cuenta».
  update public.ventas set cuenta_pedida_at = null
  where id = p_destino_id and cuenta_pedida_at is not null;

  insert into public.bitacora (restaurante_id, miembro_id, accion, tabla, registro_id, detalle)
  values (v_origen.restaurante_id, v_miembro, 'juntar_mesas', 'ventas', p_venta_id::text,
          jsonb_build_object('de', v_origen.mesa_nombre, 'a', v_destino.mesa_nombre, 'a_venta', p_destino_id));
end;
$$;
