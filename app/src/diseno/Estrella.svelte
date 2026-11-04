<!--
  El logo de Fragmentless, la estrella (artifact «Logo Fragmentless» SHTPz8pWF583hNnotBWPpz; maqueta
  AyS4xUfa5XmDaPJG1iqSgw): sus dos piezas, siempre en degradado, nunca de un color plano, y siempre
  sola, sin cuadro. Cada fondo lleva su versión oficial: «blanco» sobre un fondo claro, «azul» sobre un
  color oscuro, «negro» sobre negro y «gris» en la etiqueta del login. «panel» sigue al tema con
  --estrella-1…4 de colores.css: la naranja en claro y la de fondo negro en oscuro.
-->
<script lang="ts" module>
  export type FondoEstrella = 'blanco' | 'azul' | 'negro' | 'gris' | 'panel';
</script>

<script lang="ts">
  let { fondo, tamano }: { fondo: FondoEstrella; tamano: number } = $props();

  // Los cuatro tonos de cada versión, del pico de abajo a la punta de arriba (offsets 0, 0.45, 0.8, 1).
  const TONOS: Record<FondoEstrella, string[]> = {
    blanco: ['#0A2470', '#1355E8', '#4FA3FF', '#9FE6FF'],
    azul: ['#8EAEFF', '#C4D6FF', '#EAF2FF', '#FFFFFF'],
    negro: ['#1B3FB5', '#1F5EF0', '#4FA3FF', '#9FE6FF'],
    gris: ['#B2B2B2', '#CCCCCC', '#E7E7E7', '#FFFFFF'],
    panel: ['var(--estrella-1)', 'var(--estrella-2)', 'var(--estrella-3)', 'var(--estrella-4)'],
  };
  const PASOS = [0, 0.45, 0.8, 1];

  // Un id por estrella, para que dos en la página no compartan su degradado.
  const id = $props.id();
</script>

<svg viewBox="179 33 180 180" width={tamano} height={tamano} aria-hidden="true">
  <defs>
    <linearGradient {id} gradientUnits="userSpaceOnUse" x1="192" y1="200" x2="350" y2="46">
      {#each TONOS[fondo] as tono, i (i)}
        <stop offset={PASOS[i]} style:stop-color={tono} />
      {/each}
    </linearGradient>
  </defs>
  <g fill="url(#{id})" stroke="url(#{id})" stroke-width="8" stroke-linejoin="round">
    <path d="M214 92 Q282.3 83.6 346.4 49.7 Q309.6 112.2 298 180 Z" />
    <path d="M196 108 Q204 157 192 196 Q232 186 280 196 Z" />
  </g>
</svg>

<style>
  svg {
    display: block;
    flex: none;
    overflow: visible;
  }
</style>
