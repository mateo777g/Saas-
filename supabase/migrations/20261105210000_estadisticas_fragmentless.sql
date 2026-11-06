-- Las estadísticas del Inicio de Fragmentless (rediseño del panel, 5 de noviembre de 2026; maqueta
-- 4Ryyf9E7u4vsDs57PdkAnz). Lo que el panel dibuja y no había de dónde sacar:
--   gasto: lo gastado en IA por todos los clientes en cada uno de los últimos 6 meses.
--   fotos: cuántos restaurantes funcionaban y cuántos no, cada uno de los últimos 30 días.
--   vencen: cuántas licencias vencen en cada uno de los próximos 7 días.
-- Las ventas de los restaurantes no entran: Fragmentless no las ve (libreta 2).


-- ─── fotos_licencias ──────────────────────────────────────────────────────────
-- La foto de cada día de cómo iban las licencias. La base solo sabe cómo está hoy cada una, y lo que
-- no se guarda hoy ya no se puede sacar después. No lleva restaurante_id: cuenta a todos juntos y
-- ninguna fila dice quién es quién. Nadie con sesión la lee ni la escribe. No se borra.

create table public.fotos_licencias (
  dia date primary key,
  funcionan integer not null constraint fotos_licencias_funcionan check (funcionan >= 0),
  sin_funcionar integer not null constraint fotos_licencias_sin_funcionar check (sin_funcionar >= 0)
);

alter table public.fotos_licencias enable row level security;

revoke all on table public.fotos_licencias from public, anon, authenticated, service_role;


-- ─── Tomar la foto ────────────────────────────────────────────────────────────
-- Cuenta con privado.vigencias(), igual que las cifras de Inicio (panel_resumen). El día es el de
-- México, donde está Fragmentless; cada licencia se cuenta en la zona de su restaurante. Tomarla otra
-- vez el mismo día la reemplaza.

create function privado.tomar_foto_licencias()
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
$$;

revoke execute on function privado.tomar_foto_licencias() from public, anon, authenticated, service_role;


-- ─── Lo que lee el panel ──────────────────────────────────────────────────────
-- Una sola lectura, ya contada: la app solo dibuja.
--   hoy y hora: el día y la hora de México, para el saludo y «Actualizado»; la app no usa el reloj del aparato.
--   gasto: 6 renglones, de lo más viejo a este mes, también los meses en 0.
--   fotos: los días con foto de los últimos 30, de lo más viejo a hoy. Hoy no sale de su foto: se cuenta
--     en vivo, así el último punto siempre es lo mismo que dice la tarjeta.
--   vencen: 8 renglones, de hoy a dentro de 7 días, también los días en 0. Los pausados no cuentan,
--     igual que en «Vencen en 7 días».

create function public.panel_estadisticas()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoy date := privado.dia_local('America/Mexico_City');
  v_mes date := date_trunc('month', v_hoy::timestamp)::date;
  v_gasto jsonb;
  v_fotos jsonb;
  v_vencen jsonb;
begin
  if not privado.soy_admin() then
    raise exception 'Solo Fragmentless puede hacer esto' using errcode = '42501';
  end if;

  select jsonb_agg(jsonb_build_object('mes', m.inicio, 'gastado', coalesce(u.gastado, 0)) order by m.inicio)
  into v_gasto
  from generate_series(5, 0, -1) as g(atras)
  cross join lateral (select (v_mes - make_interval(months => g.atras))::date as inicio) m
  left join lateral (
    select sum(x.costo_usd) as gastado from public.uso_ia x where x.mes = m.inicio
  ) u on true;

  select jsonb_agg(jsonb_build_object('dia', t.dia, 'funcionan', t.funcionan, 'sin_funcionar', t.sin_funcionar) order by t.dia)
  into v_fotos
  from (
    select f.dia, f.funcionan, f.sin_funcionar
    from public.fotos_licencias f
    where f.dia >= v_hoy - 29 and f.dia < v_hoy
    union all
    select v_hoy,
           (count(*) filter (where v.estado in ('vigente', 'vence_pronto')))::integer,
           (count(*) filter (where v.estado in ('vencida', 'pausada')))::integer
    from privado.vigencias() v
  ) t;

  with por_vencer as materialized (
    select v.dias_restantes from privado.vigencias() v where v.estado = 'vence_pronto'
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
    'fotos', v_fotos,
    'vencen', v_vencen);
end;
$$;

revoke execute on function public.panel_estadisticas() from public, anon, service_role;
grant execute on function public.panel_estadisticas() to authenticated;


-- ─── La foto de cada día, con pg_cron ─────────────────────────────────────────
-- A las 23:55 de México, que todo el año son las 05:55 UTC. La migración toma la primera.

select cron.schedule('foto-de-licencias', '55 5 * * *', 'select privado.tomar_foto_licencias()');

select privado.tomar_foto_licencias();
