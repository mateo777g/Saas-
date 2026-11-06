<!--
  La mini tabla que a veces no cabe en su tarjeta (maqueta ETbzaVwaJXE2xgucmK6x9u,
  planes/trabajo/rediseno/barrita-tablas.md): en vez de salirse, se desliza de lado y abajo sale una
  barrita corta que la sigue y se puede arrastrar. Si la tabla cabe, no sale nada ni ocupa lugar.

  La barra del navegador va escondida: mide según lo que falta por ver y no se puede acortar. Con
  el teclado o el dedo la tabla se desliza sola, así que la barrita es solo para el mouse.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children }: { children: Snippet } = $props();

  // El largo de la barrita, el mismo de su CSS.
  const LARGO = 48;

  let caja = $state<HTMLDivElement | null>(null);
  let sobra = $state(0);
  let ancho = $state(0);
  let x = $state(0);
  let arrastre: { mouse: number; tabla: number } | null = null;

  const viaje = $derived(ancho - LARGO);
  const lugar = $derived(sobra > 0 ? (x / sobra) * viaje : 0);

  function medir() {
    if (!caja) return;
    sobra = caja.scrollWidth - caja.clientWidth;
    ancho = caja.clientWidth;
    x = caja.scrollLeft;
  }

  // La tabla cambia con la búsqueda, con los datos y al cargar la letra.
  $effect(() => {
    if (!caja) return;
    medir();
    const vigia = new ResizeObserver(medir);
    vigia.observe(caja);
    if (caja.firstElementChild) vigia.observe(caja.firstElementChild);
    return () => vigia.disconnect();
  });

  function agarrar(e: PointerEvent) {
    if (!caja) return;
    arrastre = { mouse: e.clientX, tabla: caja.scrollLeft };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    e.preventDefault();
  }

  function mover(e: PointerEvent) {
    if (arrastre && caja) caja.scrollLeft = arrastre.tabla + ((e.clientX - arrastre.mouse) * sobra) / viaje;
  }

  function soltar() {
    arrastre = null;
  }
</script>

<div class="con-barrita">
  <div class="desliza" bind:this={caja} onscroll={medir}>
    {@render children()}
  </div>
  {#if sobra > 0}
    <div class="pista" aria-hidden="true">
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <span
        class="barrita"
        style:transform="translateX({lugar}px)"
        onpointerdown={agarrar}
        onpointermove={mover}
        onpointerup={soltar}
        onpointercancel={soltar}
      ></span>
    </div>
  {/if}
</div>

<style>
  .con-barrita {
    min-width: 0;
  }

  .desliza {
    overflow-x: auto;
    scrollbar-width: none;
  }

  .desliza::-webkit-scrollbar {
    display: none;
  }

  .pista {
    position: relative;
    height: 6px;
  }

  .barrita {
    position: absolute;
    left: 0;
    top: 0;
    width: 48px;
    height: 6px;
    border-radius: 3px;
    background: var(--barrita);
    cursor: grab;
    touch-action: none;
  }

  .barrita:active {
    cursor: grabbing;
  }

  /* Para agarrarla sin atinarle a 6 px. */
  .barrita::before {
    content: '';
    position: absolute;
    inset: -7px -4px;
  }
</style>
