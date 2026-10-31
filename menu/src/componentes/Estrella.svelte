<!--
  La estrella de Fragmentless, el logo nuevo (artifact «Logo Fragmentless» SHTPz8pWF583hNnotBWPpz):
  sus dos piezas, siempre en degradado, nunca de un color plano. Por ahora solo va en la burbuja
  del asistente del menú y en su plática (decidido en la prueba de Banderitas, el 31 de octubre de
  2026). Cada fondo lleva su versión del logo oficial: «blanco» sobre un fondo claro, «azul» sobre un
  color oscuro y «negro» sobre negro.

  Con `pensando`, las dos piezas se separan un poco por el corte y se vuelven a juntar, por turnos
  («Pensando…», como la ∫∫ que se mecía). Con «reducir movimiento» solo parpadea.
-->
<script lang="ts" module>
  export type FondoEstrella = 'blanco' | 'azul' | 'negro';
</script>

<script lang="ts">
  let {
    fondo,
    tamano,
    pensando = false,
  }: { fondo: FondoEstrella; tamano: number; pensando?: boolean } = $props();

  // Los cuatro tonos de cada versión, del pico de abajo a la punta de arriba (offsets 0, 0.45, 0.8, 1).
  const TONOS: Record<FondoEstrella, string[]> = {
    blanco: ['#0A2470', '#1355E8', '#4FA3FF', '#9FE6FF'],
    azul: ['#8EAEFF', '#C4D6FF', '#EAF2FF', '#FFFFFF'],
    negro: ['#1B3FB5', '#1F5EF0', '#4FA3FF', '#9FE6FF'],
  };
  const PASOS = [0, 0.45, 0.8, 1];

  // Un id por estrella, para que dos en la página no compartan su degradado.
  const id = $props.id();
</script>

<svg viewBox="179 33 180 180" width={tamano} height={tamano} aria-hidden="true" class:pensando>
  <defs>
    <linearGradient {id} gradientUnits="userSpaceOnUse" x1="192" y1="200" x2="350" y2="46">
      {#each TONOS[fondo] as tono, i (i)}
        <stop offset={PASOS[i]} stop-color={tono} />
      {/each}
    </linearGradient>
  </defs>
  <g fill="url(#{id})" stroke="url(#{id})" stroke-width="8" stroke-linejoin="round">
    <path class="pieza" d="M214 92 Q282.3 83.6 346.4 49.7 Q309.6 112.2 298 180 Z" />
    <path class="pieza chica" d="M196 108 Q204 157 192 196 Q232 186 280 196 Z" />
  </g>
</svg>

<style>
  svg {
    display: block;
    flex: none;
    overflow: visible;
  }

  /* En unidades del dibujo: 25 a lo ancho del corte (de 180), hacia afuera de cada pieza. */
  .pensando .pieza {
    animation: separar 1.5s ease-in-out infinite;
  }

  .pensando .pieza.chica {
    animation-name: separar-chica;
    animation-delay: 0.2s;
  }

  @keyframes separar {
    0%,
    70%,
    100% {
      transform: translate(0, 0);
    }
    25% {
      transform: translate(18px, -17px);
    }
    45% {
      transform: translate(-4px, 4px);
    }
  }

  @keyframes separar-chica {
    0%,
    70%,
    100% {
      transform: translate(0, 0);
    }
    25% {
      transform: translate(-18px, 17px);
    }
    45% {
      transform: translate(4px, -4px);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .pensando .pieza,
    .pensando .pieza.chica {
      animation: latir 1.6s ease-in-out infinite;
    }

    @keyframes latir {
      0%,
      100% {
        opacity: 1;
      }
      50% {
        opacity: 0.35;
      }
    }
  }
</style>
