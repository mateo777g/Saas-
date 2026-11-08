-- Las gráficas del Inicio del distribuidor (8 de noviembre de 2026; el developer: «quiero que en el panel de mi
-- distribuidor haya gráficas, como las mías»). Las mismas del Inicio de Fragmentless (migración
-- estadisticas_fragmentless), solo con sus clientes:
--   gasto: lo gastado en IA por sus clientes en cada uno de los últimos 6 meses (encuesta: sí lo ve, porque la IA de
--     sus clientes se descuenta de su parte).
--   altas: sus clientes dados de alta en cada uno de los últimos 6 meses.
--   fotos: cuántos de sus restaurantes funcionaban y cuántos no, cada uno de los últimos 30 días.
--   vencen: cuántas de sus licencias vencen en cada uno de los próximos 7 días.
-- La lectura trae también la fecha y la hora de México, para su saludo (encuesta: «Buenas tardes», con su fecha).
-- El gasto y las altas cuentan a los clientes que tiene hoy: si Fragmentless le pasa uno de otro distribuidor, su
-- historia se va con él.


-- ─── fotos_distribuidores ─────────────────────────────────────────────────────
-- La foto de cada día de cómo iban las licencias de los clientes de cada distribuidor: la base solo sabe cómo está hoy
-- cada una, y lo que no se guarda hoy ya no se puede sacar después. Nadie con sesión la lee ni la escribe: cada
-- distribuidor ve las suyas con distribuidor_estadisticas. No se borra (los distribuidores tampoco).

create table public.fotos_distribuidores (
  distribuidor_id bigint not null references public.distribuidores (id),
  dia date not null,
  funcionan integer not null constraint fotos_distribuidores_funcionan check (funcionan >= 0),
  sin_funcionar integer not null constraint fotos_distribuidores_sin_funcionar check (sin_funcionar >= 0),
  primary key (distribuidor_id, dia)
);

alter table public.fotos_distribuidores enable row level security;
revoke all on table public.fotos_distribuidores from public, anon, authenticated, service_role;


-- ─── Tomar la foto ────────────────────────────────────────────────────────────
-- La misma de antes (fotos_licencias, sin cambiar nada) y, con ella, una fila por distribuidor: también los que no
-- tienen clientes o están de baja, en 0. Cuenta con privado.vigencias(), como sus cifras (distribuidor_resumen).
-- Tomarla otra vez el mismo día la reemplaza. La sigue llamando el mismo pg_cron, a las 23:55 de México.

create or replace function privado.tomar_foto_licencias()
returns void
language sql
set search_path = ''
as $$
  insert into public.fotos_licencias (dia, funcionan, sin_funcionar)
  select privado.dia_local('America/Mexico_City'),
         count(*) filter (where v.estado in ('vigente', 'vence_pronto')),
         count(*) filter (where v.estado in ('vencida', 'pausada'))
  from privado.vigencias() v
  on conflict (dia) do update
    set funcionan = excluded.funcionan,
        sin_funcionar = excluded.sin_funcionar;

  insert into public.fotos_distribuidores (distribuidor_id, dia, funcionan, sin_funcionar)
  select d.id,
         privado.dia_local('America/Mexico_City'),
         count(v.restaurante_id) filter (where v.estado in ('vigente', 'vence_pronto')),
         count(v.restaurante_id) filter (where v.estado in ('vencida', 'pausada'))
  from public.distribuidores d
  left join public.restaurantes r on r.distribuidor_id = d.id
  left join privado.vigencias() v on v.restaurante_id = r.id
  group by d.id
  on conflict (distribuidor_id, dia) do update
    set funcionan = excluded.funcionan,
        sin_funcionar = excluded.sin_funcionar;
$$;

revoke execute on function privado.tomar_foto_licencias() from public, anon, authenticated, service_role;


-- ─── Lo que lee su Inicio ─────────────────────────────────────────────────────
-- Una sola lectura, ya contada: la app solo dibuja. Solo le responde a un distribuidor activo, como
-- distribuidor_resumen y distribuidor_clientes.
--   hoy y hora: el día y la hora de México, para el saludo y «Actualizado»; la app no usa el reloj del aparato.
--   gasto: 6 renglones, de lo más viejo a este mes, también los meses en 0.
--   altas: 6 renglones igual, cada uno con total_6_meses, la suma de los 6.
--   fotos: los días con foto de los últimos 30, de lo más viejo a hoy. Hoy no sale de su foto: se cuenta en vivo, así
--     el último punto siempre es lo mismo que dice la tarjeta.
--   vencen: 8 renglones, de hoy a dentro de 7 días, también los días en 0. Los pausados no cuentan, igual que en
--     «Vencen en 7 días».

create function public.distribuidor_estadisticas()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_distribuidor bigint := privado.mi_distribuidor();
  v_hoy date := privado.dia_local('America/Mexico_City');
  v_mes date := date_trunc('month', v_hoy::timestamp)::date;
  v_gasto jsonb;
  v_altas jsonb;
  v_fotos jsonb;
  v_vencen jsonb;
begin
  if v_distribuidor is null then
    raise exception 'Solo un distribuidor activo puede ver esto' using errcode = '42501';
  end if;

  select jsonb_agg(jsonb_build_object('mes', m.inicio, 'gastado', coalesce(u.gastado, 0)) order by m.inicio)
  into v_gasto
  from generate_series(5, 0, -1) as g(atras)
  cross join lateral (select (v_mes - make_interval(months => g.atras))::date as inicio) m
  left join lateral (
    select sum(x.costo_usd) as gastado
    from public.uso_ia x
    join public.restaurantes r on r.id = x.restaurante_id
    where x.mes = m.inicio
      and r.distribuidor_id = v_distribuidor
  ) u on true;

  select jsonb_agg(jsonb_build_object('mes', a.inicio, 'altas', a.altas, 'total_6_meses', a.total) order by a.inicio)
  into v_altas
  from (
    select m.inicio,
           count(r.id)::integer as altas,
           (sum(count(r.id)) over ())::integer as total
    from generate_series(5, 0, -1) as g(atras)
    cross join lateral (select (v_mes - make_interval(months => g.atras))::date as inicio) m
    left join public.restaurantes r
      on r.distribuidor_id = v_distribuidor
     and date_trunc('month', r.created_at at time zone 'America/Mexico_City')::date = m.inicio
    group by m.inicio
  ) a;

  select jsonb_agg(jsonb_build_object('dia', t.dia, 'funcionan', t.funcionan, 'sin_funcionar', t.sin_funcionar) order by t.dia)
  into v_fotos
  from (
    select f.dia, f.funcionan, f.sin_funcionar
    from public.fotos_distribuidores f
    where f.distribuidor_id = v_distribuidor
      and f.dia >= v_hoy - 29 and f.dia < v_hoy
    union all
    select v_hoy,
           (count(*) filter (where v.estado in ('vigente', 'vence_pronto')))::integer,
           (count(*) filter (where v.estado in ('vencida', 'pausada')))::integer
    from public.restaurantes r
    join privado.vigencias() v on v.restaurante_id = r.id
    where r.distribuidor_id = v_distribuidor
  ) t;

  with por_vencer as materialized (
    select v.dias_restantes
    from public.restaurantes r
    join privado.vigencias() v on v.restaurante_id = r.id
    where r.distribuidor_id = v_distribuidor
      and v.estado = 'vence_pronto'
  )
  select jsonb_agg(jsonb_build_object(
           'dia', v_hoy + g.n,
           'cuantos', (select count(*) from por_vencer p where p.dias_restantes = g.n)
         ) order by g.n)
  into v_vencen
  from generate_series(0, 7) as g(n);

  return jsonb_build_object(
    'hoy', v_hoy,
    'hora', to_char(now() at time zone 'America/Mexico_City', 'HH24:MI'),
    'gasto', v_gasto,
    'altas', v_altas,
    'fotos', v_fotos,
    'vencen', v_vencen);
end;
$$;

revoke execute on function public.distribuidor_estadisticas() from public, anon, service_role;
grant execute on function public.distribuidor_estadisticas() to authenticated;


-- ─── La primera foto de cada distribuidor ─────────────────────────────────────
-- Vuelve a tomar la de hoy (fotos_licencias queda igual) y así cada distribuidor empieza su historia hoy.

select privado.tomar_foto_licencias();
