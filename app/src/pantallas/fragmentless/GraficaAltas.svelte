<!--
  Las columnas de «Altas por mes», como las dibuja la maqueta: una por cada uno de los 6 meses
  que da panel_altas_por_mes (el último es el que va en curso), con la rejilla en 0, la mitad y
  el tope, el número encima del mes más alto y del último, y un globito al pasar el cursor. Para
  un lector de pantalla va la misma información en una tabla que no se ve.
-->
<script lang="ts">
  import { mesCorto, mesLargo, plural } from '../../lib/formato';
  import type { AltaMes } from '../../lib/panel';

  let { altas }: { altas: AltaMes[] } = $props();

  // Las medidas de la maqueta, en px.
  const IZQUIERDA = 26;
  const ABAJO = 22;
  const ARRIBA = 20;
  const COLUMNA = 24;

  let ancho = $state(0);
  let alto = $state(0);
  let foco = $state<number | null>(null);

  const mayor = $derived(Math.max(0, ...altas.map((m) => m.altas)));
  // El tope de la rejilla es par, para que la mitad sea un entero (2, 4, 6…).
  const tope = $derived(Math.max(2, Math.ceil(mayor / 2) * 2));
  const util = $derived(Math.max(0, alto - ABAJO - ARRIBA));
  const banda = $derived(altas.length ? (ancho - IZQUIERDA) / altas.length : 0);
  const conNumero = $derived(new Set([altas.findIndex((m) => m.altas === mayor), altas.length - 1]));
  const ultimo = $derived(altas.length - 1);

  function y(valor: number) {
    return ARRIBA + util - (valor / tope) * util;
  }

  function centro(i: number) {
    return IZQUIERDA + banda * (i + 0.5);
  }

  // La columna con las esquinas de arriba redondeadas (radio 4, o menos si es muy bajita).
  function columna(i: number, valor: number) {
    const x = centro(i) - COLUMNA / 2;
    const arriba = y(valor);
    const base = ARRIBA + util;
    const r = Math.min(4, base - arriba);
    return (
      `M${x},${base}V${arriba + r}Q${x},${arriba} ${x + r},${arriba}` +
      `H${x + COLUMNA - r}Q${x + COLUMNA},${arriba} ${x + COLUMNA},${arriba + r}V${base}Z`
    );
  }
</script>

<!-- Al salir el cursor se quita el globito (extra del ratón, como el de cada columna). -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="area"
  class:con-foco={foco !== null}
  bind:clientWidth={ancho}
  bind:clientHeight={alto}
  onpointerleave={() => (foco = null)}
>
  {#if ancho > 0 && alto > 0 && altas.length}
    <svg
      viewBox="0 0 {ancho} {alto}"
      role="img"
      aria-label="Altas por mes, de {mesLargo(altas[0].mes)} a {mesLargo(altas[ultimo].mes)}"
    >
      {#each [0, tope / 2, tope] as valor (valor)}
        <line class="rejilla" x1={IZQUIERDA} x2={ancho} y1={y(valor)} y2={y(valor)} />
        <text class="eje" x={IZQUIERDA - 8} y={y(valor) + 3.5} text-anchor="end">{valor}</text>
      {/each}
      {#each altas as m, i (m.mes)}
        {#if m.altas > 0}
          <path class="columna" class:foco={foco === i} d={columna(i, m.altas)} />
          {#if conNumero.has(i)}
            <text class="valor" x={centro(i)} y={y(m.altas) - 6} text-anchor="middle">{m.altas}</text>
          {/if}
        {/if}
        <text class="eje" x={centro(i)} y={alto - 4} text-anchor="middle">{mesCorto(m.mes)}</text>
        <!-- El globito es un extra del ratón: lo mismo está en la tabla para lectores de pantalla. -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <rect
          class="zona"
          x={IZQUIERDA + banda * i}
          y="0"
          width={banda}
          height={alto - ABAJO}
          onpointerenter={() => (foco = i)}
        />
      {/each}
    </svg>
  {/if}

  <table class="solo-lector">
    <caption>Altas por mes</caption>
    <thead><tr><th>Mes</th><th>Altas</th></tr></thead>
    <tbody>
      {#each altas as m (m.mes)}
        <tr><td>{mesLargo(m.mes)}</td><td>{m.altas}</td></tr>
      {/each}
    </tbody>
  </table>

  {#if altas.length && altas[0].total_6_meses === 0}
    <div class="vacia">Todavía no das de alta ningún restaurante.</div>
  {/if}

  {#if foco !== null}
    {@const m = altas[foco]}
    <div class="globo" style:left="{centro(foco)}px" style:top="{Math.max(0, y(m.altas))}px">
      <span class="etiqueta">
        {mesLargo(m.mes).toUpperCase()}{foco === ultimo ? ' · VA EN CURSO' : ''}
      </span>
      <b>{plural(m.altas, 'alta', 'altas')}</b>
    </div>
  {/if}
</div>

<style>
  .area {
    position: relative;
    flex: 1;
    min-height: 0;
  }

  svg {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  .rejilla {
    stroke: var(--linea);
    stroke-width: 1;
  }

  .eje {
    font-family: var(--mono);
    font-size: 10.5px;
    fill: var(--tenue);
  }

  .columna {
    fill: var(--tinta);
    transition: opacity 120ms;
  }

  .con-foco .columna {
    opacity: 0.35;
  }

  .con-foco .columna.foco {
    opacity: 1;
  }

  .valor {
    font-family: var(--jakarta);
    font-size: 12px;
    font-weight: 700;
    fill: var(--texto);
  }

  .zona {
    fill: transparent;
  }

  .vacia {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .globo {
    position: absolute;
    transform: translate(-50%, calc(-100% - 8px));
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 8px 12px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 10px;
    box-shadow: 0 8px 24px var(--sombra);
    pointer-events: none;
    white-space: nowrap;
  }

  .globo b {
    font-size: 13px;
    font-weight: 700;
  }
</style>
