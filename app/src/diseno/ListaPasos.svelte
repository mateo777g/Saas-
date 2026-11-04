<!--
  La lista de pasos del «Pensando…» (tercera referencia de planes/trabajo/estrella/referencias-cargas.md;
  maqueta AyS4xUfa5XmDaPJG1iqSgw). Mientras corre, un paso lleva su ícono en el acento, latiendo; al
  terminar, ✓ y su texto en pasado. Con `entran`, cada paso nuevo entra desde abajo. Sus colores son los
  del panel; el menú en línea, que tiene los suyos, los cambia con --pensando-*.
-->
<script lang="ts">
  import type { Paso } from '../lib/pasos';
  import Icono from './Icono.svelte';

  let { pasos, entran = false }: { pasos: Paso[]; entran?: boolean } = $props();
</script>

<ol class="pasos">
  {#each pasos as p (p.clave)}
    <li class="paso" class:en-curso={!p.hecho} class:entra={entran}>
      <span class="marca">
        {#if p.hecho}<Icono nombre="check" tamano={12} />{:else}<Icono nombre={p.icono} tamano={15} />{/if}
      </span>
      <span>{p.hecho ? p.listo : p.texto}</span>
    </li>
  {/each}
</ol>

<style>
  .pasos {
    list-style: none;
    margin: 4px 0 0;
    padding: 0 0 0 26px;
    display: flex;
    flex-direction: column;
  }

  .paso {
    position: relative;
    min-height: 32px;
    padding: 6px 0;
    display: flex;
    align-items: center;
    font-size: 13px;
    line-height: 1.45;
    color: var(--pensando-suave, var(--suave));
  }

  .paso.en-curso {
    color: var(--pensando-texto, var(--texto));
  }

  .paso::before,
  .paso::after {
    content: '';
    position: absolute;
    left: -20px;
    width: 1px;
    height: calc(50% - 10px);
    background: var(--pensando-raya, var(--linea-fuerte));
    opacity: var(--pensando-raya-opacidad, 1);
  }

  .paso::before {
    top: 0;
  }

  .paso::after {
    bottom: 0;
  }

  .paso:first-child::before,
  .paso:last-child::after {
    display: none;
  }

  .marca {
    position: absolute;
    left: -28px;
    top: 50%;
    width: 16px;
    height: 16px;
    margin-top: -8px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--pensando-texto, var(--texto));
  }

  .en-curso .marca {
    color: var(--pensando-acento, var(--acento));
  }

  .en-curso .marca :global(svg) {
    animation: latido 1.2s ease-in-out infinite;
  }

  .entra {
    animation: entra-paso 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
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

  @keyframes entra-paso {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
    to {
      opacity: 1;
      transform: none;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .entra {
      animation: none;
    }
  }
</style>
