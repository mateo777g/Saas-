-- Creación de contenido, parte 7b-2: Mi biblioteca (libreta 7; las respuestas de la 7b-2 en
-- planes/trabajo/7b, biblioteca-7b2.md y migracion-7b2.md; maqueta SMeWoa5ypbcVQmvBGyyytt).
--
-- Cada anuncio que sale se guarda 30 días en la biblioteca de su sucursal, y todos sus gerentes la
-- ven, haya hecho cada anuncio quien lo haya hecho (mi_biblioteca). Eliminar lo hace el Worker:
-- Postgres le dice si se puede y cuál es su archivo con la sesión de Don Chuy
-- (puedo_borrar_anuncio), el Worker lo borra de R2 y luego borra el renglón con la llave secreta
-- (borrar_anuncio), así nunca queda un archivo sin su renglón. El trabajo diario del Worker hace lo
-- mismo con los vencidos, también los que no salieron (anuncios_vencidos y borrar_vencidos). Borrar
-- no toca uso_ia: el anuncio sigue contando en sus 20 del mes y su costo se queda.
--
-- No hay tablas ni columnas nuevas: solo funciones.


-- ─── Lo que lee Don Chuy ──────────────────────────────────────────────────────

-- «Mi biblioteca» en una sola lectura, al entrar, al volver a la pestaña y cada vez que avisa
-- realtime: hoy en el calendario del restaurante (para «HOY» y «AYER») y sus anuncios. Primero el
-- que se está haciendo en la sucursal, de quien sea; luego los listos de todos sus gerentes, del
-- más nuevo al más viejo por la hora en que terminaron. Los que no salieron no vienen, ni uno cuyo
-- último día ya pasó aunque el trabajo diario todavía no lo borre. El día de un anuncio es su vence
-- menos 29, el mismo número con el que se apartaron sus 30 días, y le quedan vence menos hoy (0 es
-- «Se borra hoy»). Antes suelta uno atorado, como crear_contenido.
create function public.mi_biblioteca(p_restaurante_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_zona text;
  v_hoy date;
  v_anuncios jsonb;
begin
  if p_restaurante_id is null
     or p_restaurante_id not in (select privado.mis_restaurantes_gerente()) then
    raise exception 'Solo el gerente de este restaurante ve su biblioteca' using errcode = '42501';
  end if;
  perform privado.soltar_atorados(p_restaurante_id);

  select zona_horaria into v_zona from public.restaurantes where id = p_restaurante_id;
  v_hoy := privado.dia_local(v_zona);

  select coalesce(jsonb_agg(x.anuncio order by x.haciendo desc, x.terminado_at desc, x.id desc), '[]')
  into v_anuncios
  from (
    select a.id,
           a.estado = 'haciendo' as haciendo,
           a.terminado_at,
           jsonb_build_object(
             'id', a.id,
             'estado', a.estado,
             'formato', a.formato,
             'estilo', e.nombre,
             'productos', (select jsonb_agg(p -> 'nombre' order by n)
                           from jsonb_array_elements(a.productos) with ordinality as l (p, n))
           )
           || case when a.estado = 'haciendo' then
                jsonb_build_object('segundos', floor(extract(epoch from now() - a.created_at))::integer)
              else
                jsonb_build_object(
                  'ruta', a.ruta,
                  'dia', a.vence - 29,
                  'hora', to_char(a.terminado_at at time zone v_zona, 'HH24:MI'),
                  'dias_restantes', a.vence - v_hoy)
              end as anuncio
    from public.anuncios a
    join public.estilos e on e.id = a.estilo_id
    where a.restaurante_id = p_restaurante_id
      and (a.estado = 'haciendo'
           or (a.estado = 'listo' and a.vence >= v_hoy))
  ) x;

  return jsonb_build_object('hoy', v_hoy, 'anuncios', v_anuncios);
end;
$$;


-- ─── Eliminar ─────────────────────────────────────────────────────────────────

-- Con la sesión de Don Chuy, antes de que el Worker toque R2: si es un listo de una de sus
-- sucursales con la licencia al día, regresa su archivo. Uno que se está haciendo no se borra. Si
-- ya no está (la socia lo borró o el trabajo diario se lo llevó), o no es suyo, regresa null: el
-- Worker contesta que quedó borrado y la app lo quita, sin error.
create function public.puedo_borrar_anuncio(p_anuncio_id bigint)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_estado text;
  v_ruta text;
begin
  select a.estado, a.ruta into v_estado, v_ruta
  from public.anuncios a
  where a.id = p_anuncio_id
    and a.restaurante_id in (select privado.mis_restaurantes_gerente());
  if v_estado = 'haciendo' then
    raise exception 'Tu anuncio todavía se está haciendo.' using errcode = '22023';
  end if;
  return v_ruta;
end;
$$;

-- Solo la llave secreta, después de que R2 borró el archivo: borra el renglón si sigue listo con
-- ese mismo archivo. Regresa si lo borró; si ya no estaba, no pasa nada, así se termina al
-- reintentar.
create function public.borrar_anuncio(p_anuncio_id bigint, p_ruta text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.anuncios
  where id = p_anuncio_id
    and estado = 'listo'
    and ruta = p_ruta;
  return found;
end;
$$;


-- ─── El borrado de los 30 días (el trabajo diario, solo la llave secreta) ─────
-- Vencido es el que su último día ya pasó en el calendario de su restaurante, también en uno
-- pausado o con la licencia vencida: los 30 días no dependen de la licencia.

-- Primero suelta los atorados de todos los restaurantes (quedan con sus 30 días, como cualquiera
-- que no salió); luego regresa hasta 1,000 vencidos, los más viejos primero, cada uno con su
-- archivo (null en los que no salieron). Con más de 1,000, el resto se va al otro día.
create function public.anuncios_vencidos()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vencidos jsonb;
begin
  perform privado.soltar_atorados(h.restaurante_id)
  from (select distinct restaurante_id from public.anuncios where estado = 'haciendo') h;

  select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'ruta', v.ruta) order by v.vence, v.id), '[]')
  into v_vencidos
  from (
    select a.id, a.ruta, a.vence
    from public.anuncios a
    join public.restaurantes r on r.id = a.restaurante_id
    where a.vence < privado.dia_local(r.zona_horaria)
    order by a.vence, a.id
    limit 1000
  ) v;
  return v_vencidos;
end;
$$;

-- Después de que R2 borró sus archivos: borra los renglones de esos que de verdad están vencidos
-- (uno que no, se queda). Regresa cuántos borró.
create function public.borrar_vencidos(p_ids bigint[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_borrados integer;
begin
  delete from public.anuncios a
  using public.restaurantes r
  where r.id = a.restaurante_id
    and a.id = any (p_ids)
    and a.vence < privado.dia_local(r.zona_horaria);
  get diagnostics v_borrados = row_count;
  return v_borrados;
end;
$$;


-- ─── Quién llama a qué ────────────────────────────────────────────────────────

revoke execute on function
  public.mi_biblioteca(uuid),
  public.puedo_borrar_anuncio(bigint)
from public, anon, service_role;

grant execute on function
  public.mi_biblioteca(uuid),
  public.puedo_borrar_anuncio(bigint)
to authenticated;

revoke execute on function
  public.borrar_anuncio(bigint, text),
  public.anuncios_vencidos(),
  public.borrar_vencidos(bigint[])
from public, anon, authenticated;

grant execute on function
  public.borrar_anuncio(bigint, text),
  public.anuncios_vencidos(),
  public.borrar_vencidos(bigint[])
to service_role;
