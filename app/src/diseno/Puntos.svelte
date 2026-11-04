<!--
  Los tres puntos del «Pensando…» (las dos primeras referencias de planes/trabajo/estrella/referencias-cargas.md,
  juntas; maqueta AyS4xUfa5XmDaPJG1iqSgw). Una vuelta dura 3.2 s: brincan en fila uno tras otro, se juntan
  y se funden en uno (el «goo»), se abren en triángulo, giran y vuelven a la fila. Los tres de un solo color,
  el que manda quien los usa. Con «reducir movimiento» solo laten por turnos.
-->
<script lang="ts">
  let { color }: { color: string } = $props();

  const id = $props.id();
</script>

<svg class="filtro" width="0" height="0" aria-hidden="true" focusable="false">
  <defs>
    <filter {id}>
      <feGaussianBlur in="SourceGraphic" stdDeviation="1.6" result="blur" />
      <feColorMatrix in="blur" mode="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 18 -7" />
    </filter>
  </defs>
</svg>
<span class="puntos" style:filter="url(#{id})" aria-hidden="true">
  <span class="giro">
    <i style:background={color}></i>
    <i style:background={color}></i>
    <i style:background={color}></i>
  </span>
</span>

<style>
  .filtro {
    position: absolute;
  }

  .puntos {
    position: relative;
    display: block;
    width: 30px;
    height: 30px;
    flex: none;
  }

  .giro {
    position: absolute;
    inset: 0;
    animation: giro 3.2s ease-in-out infinite;
  }

  i {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 8px;
    height: 8px;
    margin: -4px 0 0 -4px;
    border-radius: 50%;
  }

  i:nth-child(1) {
    animation: punto-1 3.2s ease-in-out infinite;
  }

  i:nth-child(2) {
    animation: punto-2 3.2s ease-in-out infinite;
  }

  i:nth-child(3) {
    animation: punto-3 3.2s ease-in-out infinite;
  }

  @keyframes giro {
    0%,
    64% {
      transform: rotate(0deg);
    }
    84%,
    100% {
      transform: rotate(360deg);
    }
  }

  @keyframes punto-1 {
    0% {
      transform: translate(-12px, 0) scale(1);
    }
    5% {
      transform: translate(-12px, -7px) scale(1);
    }
    11%,
    28% {
      transform: translate(-12px, 0) scale(1);
    }
    40%,
    55% {
      transform: translate(0, 0) scale(1.5);
    }
    64%,
    84% {
      transform: translate(-7.5px, 5.5px) scale(0.75);
    }
    96%,
    100% {
      transform: translate(-12px, 0) scale(1);
    }
  }

  @keyframes punto-2 {
    0%,
    6% {
      transform: translate(0, 0) scale(1);
    }
    11% {
      transform: translate(0, -7px) scale(1);
    }
    17%,
    28% {
      transform: translate(0, 0) scale(1);
    }
    40%,
    55% {
      transform: translate(0, 0) scale(1.5);
    }
    64%,
    84% {
      transform: translate(0, -8.5px) scale(0.75);
    }
    96%,
    100% {
      transform: translate(0, 0) scale(1);
    }
  }

  @keyframes punto-3 {
    0%,
    12% {
      transform: translate(12px, 0) scale(1);
    }
    17% {
      transform: translate(12px, -7px) scale(1);
    }
    23%,
    28% {
      transform: translate(12px, 0) scale(1);
    }
    40%,
    55% {
      transform: translate(0, 0) scale(1.5);
    }
    64%,
    84% {
      transform: translate(7.5px, 5.5px) scale(0.75);
    }
    96%,
    100% {
      transform: translate(12px, 0) scale(1);
    }
  }

  @keyframes latido {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.35;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .giro {
      animation: none;
    }

    i:nth-child(1) {
      transform: translate(-12px, 0);
      animation: latido 1.2s ease-in-out infinite;
    }

    i:nth-child(2) {
      animation: latido 1.2s ease-in-out 0.2s infinite;
    }

    i:nth-child(3) {
      transform: translate(12px, 0);
      animation: latido 1.2s ease-in-out 0.4s infinite;
    }
  }
</style>
