<!--
  Los carteles de Don Chuy, abajo del buscador (libreta 6): hasta 5, cambian solos cada 5 segundos
  y se pasan con el dedo, con puntitos abajo. Con uno solo se queda quieto y sin puntitos; sin
  ninguno, este espacio no aparece (lo decide quien lo pone). Al tocarlos no pasa nada.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { urlImagen } from '../lib/datos';
  import type { Textos } from '../lib/textos';

  let { rutas, t }: { rutas: string[]; t: Textos } = $props();

  let tira: HTMLDivElement;
  let actual = $state(0);
  let ultimoToque = 0;

  // El que se ve es el más cerca del centro de la tira.
  function alMover() {
    if (!tira.clientWidth) return;
    actual = Math.max(0, Math.min(rutas.length - 1, Math.round(tira.scrollLeft / tira.clientWidth)));
  }

  onMount(() => {
    const tocar = () => (ultimoToque = Date.now());
    tira.addEventListener('pointerdown', tocar, { passive: true });
    tira.addEventListener('touchstart', tocar, { passive: true });
    const reloj = setInterval(() => {
      // Si la clienta acaba de pasarlos con el dedo, se espera a la siguiente vuelta.
      if (rutas.length < 2 || document.hidden || Date.now() - ultimoToque < 5000) return;
      const siguiente = (actual + 1) % rutas.length;
      tira.scrollTo({ left: siguiente * tira.clientWidth, behavior: 'smooth' });
    }, 5000);
    return () => {
      clearInterval(reloj);
      tira.removeEventListener('pointerdown', tocar);
      tira.removeEventListener('touchstart', tocar);
    };
  });
</script>

<div class="carteles">
  <div class="tira" bind:this={tira} onscroll={alMover}>
    {#each rutas as ruta, i (ruta)}
      <img class="cartel" src={urlImagen(ruta)} alt={t.cartel(i + 1, rutas.length)} loading={i === 0 ? 'eager' : 'lazy'} draggable="false" />
    {/each}
  </div>
  {#if rutas.length > 1}
    <div class="puntos" aria-hidden="true">
      {#each rutas as ruta, i (ruta)}<i class:si={i === actual}></i>{/each}
    </div>
  {/if}
</div>

<style>
  .carteles {
    padding: 14px 16px 0;
  }

  .tira {
    display: flex;
    width: 100%;
    aspect-ratio: 16 / 9;
    border-radius: 18px;
    overflow-x: auto;
    overflow-y: hidden;
    scroll-snap-type: x mandatory;
    scrollbar-width: none;
    background: var(--m-chip);
  }

  .tira::-webkit-scrollbar {
    display: none;
  }

  .cartel {
    flex: none;
    width: 100%;
    height: 100%;
    object-fit: cover;
    scroll-snap-align: start;
    scroll-snap-stop: always;
    user-select: none;
    -webkit-user-drag: none;
  }

  .puntos {
    display: flex;
    justify-content: center;
    gap: 6px;
    padding-top: 10px;
  }

  .puntos i {
    width: 6px;
    height: 6px;
    border-radius: 3px;
    background: var(--m-linea);
    transition: width 0.25s ease;
  }

  .puntos i.si {
    width: 18px;
    background: var(--m-texto);
  }

  @media (prefers-reduced-motion: reduce) {
    .puntos i {
      transition: none;
    }
  }
</style>
