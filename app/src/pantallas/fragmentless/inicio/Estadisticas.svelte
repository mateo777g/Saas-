<!--
  Las estadísticas del Inicio de Fragmentless, como la analítica de Cloudflare (maqueta
  4Ryyf9E7u4vsDs57PdkAnz): arriba, en grande, el gasto de IA y las altas, por mes; abajo, las 3 tarjetas.
  Funcionan hoy y Sin funcionar dibujan sus fotos de los últimos 30 días y, mientras no haya al menos dos
  días, «Aún sin historia». Vencen en 7 días mira hacia adelante. Sin funcionar va en rojo si hay alguno.
  Todo sale de Postgres ya contado (panel_estadisticas, panel_resumen, panel_altas_por_mes): aquí solo se
  escribe y se dibuja. Mientras lee, o si no pudo, cada valor dice «—»: nunca un 0 inventado.
-->
<script lang="ts">
  import GraficaLinea, { type EjeX, type Marca } from '../../../diseno/GraficaLinea.svelte';
  import SinDatos from '../../../diseno/SinDatos.svelte';
  import { ejeEntero, escala, SIN_MARCAS } from '../../../lib/ejes';
  import { diaCorto, diasEntre, dolares, mesCorto, plural, sumarDias } from '../../../lib/formato';
  import type { DatosPanel } from '../../../lib/panel';

  let { datos }: { datos: DatosPanel | null } = $props();

  const NO_SE_PUDO = 'No se pudo cargar.';
  const ANCHO_CHICA = 280;
  const ALTO_CHICA = 110;

  const e = $derived(datos?.estadisticas.ok ? datos.estadisticas.datos : null);
  const r = $derived(datos?.resumen.ok ? datos.resumen.datos : null);
  const altas = $derived(datos?.altas.ok ? datos.altas.datos : null);

  // «$20», «$0.5», «$0.015»: lo justo para que el eje no repita números con poco gasto.
  const usd = (v: number) => `$${Number(v.toFixed(4))}`;

  function ejeDeDolares(alto: number): { tope: number; marcas: Marca[] } {
    if (alto <= 0) return { tope: 1, marcas: [0, 0.5, 1].map((valor) => ({ valor, texto: usd(valor) })) };
    const { tope, paso } = escala(alto);
    return { tope, marcas: [0, paso, paso * 2].map((valor) => ({ valor, texto: usd(valor) })) };
  }

  const meses = (lista: { mes: string }[]): EjeX[] =>
    lista.map((m, x) => ({
      x,
      texto: mesCorto(m.mes),
      ancla: x === 0 ? ('start' as const) : x === lista.length - 1 ? ('end' as const) : undefined,
    }));

  const gasto = $derived.by(() => {
    if (!e) return null;
    const puntos = e.gasto.map((g) => g.gastado);
    return { puntos, valor: puntos[puntos.length - 1], ...ejeDeDolares(Math.max(0, ...puntos)), ejeX: meses(e.gasto) };
  });

  const deAltas = $derived.by(() => {
    if (!altas?.length) return null;
    const puntos = altas.map((a) => a.altas);
    return { puntos, valor: puntos[puntos.length - 1], total: altas[0].total_6_meses, ...ejeEntero(Math.max(0, ...puntos)), ejeX: meses(altas) };
  });

  // Las fotos van por día: un día sin foto (si un día el cron no corrió) deja su hueco, no se recorre.
  const conHistoria = $derived((e?.fotos.length ?? 0) >= 2);
  const equisFotos = $derived(e ? e.fotos.map((f) => 29 - diasEntre(f.dia, e.hoy)) : []);
  const ejeFotos = $derived<EjeX[]>(
    e
      ? [
          { x: 0, texto: diaCorto(sumarDias(e.hoy, -29)), ancla: 'start' },
          { x: 29, texto: 'hoy', ancla: 'end' },
        ]
      : [],
  );

  const funcionan = $derived.by(() => {
    if (!e) return null;
    const puntos = e.fotos.map((f) => f.funcionan);
    return { puntos, ...ejeEntero(Math.max(r?.total ?? 0, ...puntos)) };
  });

  const sinFuncionar = $derived.by(() => {
    if (!e) return null;
    const puntos = e.fotos.map((f) => f.sin_funcionar);
    return { puntos, ...ejeEntero(Math.max(0, ...puntos)) };
  });

  const vencen = $derived.by(() => {
    if (!e) return null;
    const puntos = e.vencen.map((v) => v.cuantos);
    const ultimo = e.vencen[e.vencen.length - 1].dia;
    return {
      puntos,
      ...ejeEntero(Math.max(0, ...puntos), 2),
      ejeX: [
        { x: 0, texto: 'hoy', ancla: 'start' as const },
        { x: 7, texto: diaCorto(ultimo), ancla: 'end' as const },
      ],
    };
  });

  // Si no se pudieron leer las fotos, la nota no promete nada de ellas.
  const hasta = $derived(!e ? '' : conHistoria ? ' · últimos 30 días' : ' · se llena con una foto al día');
  const notaFunciona = $derived(r ? `de ${plural(r.total, 'restaurante', 'restaurantes')}${hasta}` : datos ? NO_SE_PUDO : '');
  const notaVencen = $derived(
    !r
      ? datos
        ? NO_SE_PUDO
        : ''
      : r.vencen_pronto === 0
        ? 'Nada por vencer esta semana'
        : `${plural(r.vencen_hoy, 'vence hoy', 'vencen hoy')} · los próximos 7 días`,
  );
  const notaSin = $derived(
    !r
      ? datos
        ? NO_SE_PUDO
        : ''
      : r.sin_funcionar === 0
        ? `Ninguno pausado ni vencido${hasta}`
        : `${plural(r.vencidos, 'vencido', 'vencidos')} · ${plural(r.pausados, 'pausado', 'pausados')}${hasta}`,
  );
</script>

<div class="cifras">
  <div class="tarjeta">
    <span class="etiqueta cabeza">Gasto de IA este mes</span>
    <div class="valor-fila">
      <span class="valor">{gasto ? dolares(gasto.valor) : '—'}</span>
      {#if gasto}<span class="unidad">USD</span>{/if}
    </div>
    <GraficaLinea
      etiqueta="Lo gastado en IA cada mes, últimos 6 meses"
      tramo={5}
      puntos={gasto?.puntos ?? []}
      tope={gasto?.tope ?? 1}
      marcas={gasto?.marcas ?? SIN_MARCAS}
      ejeX={gasto?.ejeX ?? []}
    />
    <span class="nota">{gasto ? 'Lo que le pagas a OpenAI por todos tus clientes' : datos ? NO_SE_PUDO : ''}</span>
  </div>

  <div class="tarjeta">
    <span class="etiqueta cabeza">Altas este mes</span>
    <div class="valor-fila"><span class="valor">{deAltas ? deAltas.valor : '—'}</span></div>
    <GraficaLinea
      etiqueta="Restaurantes dados de alta cada mes, últimos 6 meses"
      tramo={5}
      puntos={deAltas?.puntos ?? []}
      tope={deAltas?.tope ?? 1}
      marcas={deAltas?.marcas ?? SIN_MARCAS}
      ejeX={deAltas?.ejeX ?? []}
    />
    <span class="nota">{deAltas ? `${deAltas.total} en 6 meses` : datos ? NO_SE_PUDO : ''}</span>
  </div>
</div>

<div class="cifras tres">
  <div class="tarjeta">
    <span class="etiqueta cabeza">Funcionan hoy</span>
    <div class="valor-fila"><span class="valor">{r ? r.funcionan : '—'}</span></div>
    {#if e && !conHistoria}
      <SinDatos texto="Aún sin historia" ancho={ANCHO_CHICA} alto={ALTO_CHICA} />
    {:else}
      <GraficaLinea
        etiqueta="Restaurantes funcionando cada día, últimos 30 días"
        ancho={ANCHO_CHICA}
        alto={ALTO_CHICA}
        tramo={29}
        equis={equisFotos}
        puntos={funcionan?.puntos ?? []}
        tope={funcionan?.tope ?? 1}
        marcas={funcionan?.marcas ?? SIN_MARCAS}
        ejeX={ejeFotos}
      />
    {/if}
    <span class="nota">{notaFunciona}</span>
  </div>

  <div class="tarjeta">
    <span class="etiqueta cabeza">Vencen en 7 días</span>
    <div class="valor-fila"><span class="valor">{r ? r.vencen_pronto : '—'}</span></div>
    <GraficaLinea
      etiqueta="Licencias que vencen en cada uno de los próximos 7 días"
      ancho={ANCHO_CHICA}
      alto={ALTO_CHICA}
      tramo={7}
      puntos={vencen?.puntos ?? []}
      tope={vencen?.tope ?? 1}
      marcas={vencen?.marcas ?? SIN_MARCAS}
      ejeX={vencen?.ejeX ?? []}
      sinPunto
    />
    <span class="nota">{notaVencen}</span>
  </div>

  <div class="tarjeta" class:mala={r && r.sin_funcionar > 0}>
    <span class="etiqueta cabeza">Sin funcionar</span>
    <div class="valor-fila"><span class="valor">{r ? r.sin_funcionar : '—'}</span></div>
    {#if e && !conHistoria}
      <SinDatos texto="Aún sin historia" ancho={ANCHO_CHICA} alto={ALTO_CHICA} />
    {:else}
      <GraficaLinea
        etiqueta="Restaurantes sin funcionar cada día, últimos 30 días"
        ancho={ANCHO_CHICA}
        alto={ALTO_CHICA}
        tramo={29}
        equis={equisFotos}
        puntos={sinFuncionar?.puntos ?? []}
        tope={sinFuncionar?.tope ?? 1}
        marcas={sinFuncionar?.marcas ?? SIN_MARCAS}
        ejeX={ejeFotos}
      />
    {/if}
    <span class="nota">{notaSin}</span>
  </div>
</div>

<style>
  .cifras {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
  }

  .cifras.tres {
    grid-template-columns: repeat(3, minmax(0, 1fr));
    margin-top: 12px;
  }

  .tarjeta {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 20px 22px 18px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
  }

  .tres .tarjeta {
    padding: 18px 20px 16px;
  }

  .cabeza {
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .valor-fila {
    min-width: 0;
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  .valor {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 28px;
    font-weight: 800;
    letter-spacing: -0.5px;
    font-variant-numeric: tabular-nums;
  }

  .tres .valor {
    font-size: 24px;
  }

  .unidad {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
  }

  .nota {
    min-height: 15px;
    font-size: 12px;
    font-weight: 400;
    color: var(--suave);
  }

  /* Decidido el 5 de noviembre de 2026: en los dos temas; en 0 no, porque es buena noticia. */
  .mala {
    --grafica: var(--rojo);
  }

  .mala .valor {
    color: var(--rojo);
  }
</style>
