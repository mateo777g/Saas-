<!--
  Los carteles de Don Chuy (libreta 6): hasta 5, cambian solos cada 5 segundos y se pasan con el dedo,
  con puntitos abajo. Con uno solo se queda quieto y sin puntitos; sin ninguno, este espacio no aparece.

  Desde «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r):
  - Tres formas: con sus esquinas (la de siempre), a pantalla completa (de orilla a orilla, con una raya
    del color arriba y otra abajo y una sombra), o bajitos (de 3 a 1, con las esquinas bien suaves).
  - Cada cartel es una imagen subida o la foto de un producto de Mi menú, que se recorta al centro y, si
    así lo eligió, lleva su nombre y su precio encima; al tocarlo se abre ese producto.
  - La «i» y si está abierto van dentro del cartel y no pasan con ellos: en una cápsula de vidrio oscuro
    o solos en un círculo del mismo vidrio, arriba o abajo a la derecha (f-info-abajo, en Menu.svelte).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { urlImagen, type Producto } from '../lib/datos';
  import type { Formas } from '../lib/formas';
  import { monto } from '../lib/precio';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  type Cartel = { ruta: string; producto: Producto | null };

  let {
    carteles,
    formas,
    estado,
    abierto,
    lengua,
    moneda,
    t,
    alInfo,
    alProducto,
  }: {
    carteles: Cartel[];
    formas: Formas;
    // «Abierto · cierra a las 23:00»; sin horario, null (entonces la cápsula queda en solo la «i»).
    estado: string | null;
    abierto: boolean;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    // La ventana de la «i» crece desde aquí; mientras está abierta, la propia ventana esconde esta «i».
    alInfo: (desde: HTMLElement) => void;
    alProducto: (p: Producto) => void;
  } = $props();

  let tira: HTMLDivElement;
  let actual = $state(0);
  let ultimoToque = 0;

  const capsula = $derived(formas.info === 'capsula' && !!estado);
  const [estadoUno, estadoDos] = $derived((estado ?? '').split(' · '));

  // El que se ve es el más cerca del centro de la tira.
  function alMover() {
    if (!tira.clientWidth) return;
    actual = Math.max(0, Math.min(carteles.length - 1, Math.round(tira.scrollLeft / tira.clientWidth)));
  }

  onMount(() => {
    const tocar = () => (ultimoToque = Date.now());
    tira.addEventListener('pointerdown', tocar, { passive: true });
    tira.addEventListener('touchstart', tocar, { passive: true });
    const reloj = setInterval(() => {
      // Si la clienta acaba de pasarlos con el dedo, se espera a la siguiente vuelta.
      if (carteles.length < 2 || document.hidden || Date.now() - ultimoToque < 5000) return;
      const siguiente = (actual + 1) % carteles.length;
      tira.scrollTo({ left: siguiente * tira.clientWidth, behavior: 'smooth' });
    }, 5000);
    return () => {
      clearInterval(reloj);
      tira.removeEventListener('pointerdown', tocar);
      tira.removeEventListener('touchstart', tocar);
    };
  });
</script>

<div class="carteles" class:f-completo={formas.carteles === 'completo'} class:f-bajito={formas.carteles === 'bajito'}>
  <div class="tira" bind:this={tira} onscroll={alMover}>
    {#each carteles as c, i (c.ruta + ':' + i)}
      {#if c.producto}
        {@const p = c.producto}
        <button type="button" class="cartel f-cartel-prod" aria-label={enSuLengua(p.nombre, p.nombre_en, lengua)} onclick={() => alProducto(p)}>
          <img src={urlImagen(c.ruta)} alt="" loading={i === 0 ? 'eager' : 'lazy'} draggable="false" />
          {#if formas.carteles_producto === 'nombre'}
            <span class="f-cp-texto">
              <b>{enSuLengua(p.nombre, p.nombre_en, lengua)}</b>
              <span>{#if p.desde}{t.desde} {/if}{monto(p.precio, p.precio_usd, moneda)}</span>
            </span>
          {/if}
        </button>
      {:else}
        <img class="cartel" src={urlImagen(c.ruta)} alt={t.cartel(i + 1, carteles.length)} loading={i === 0 ? 'eager' : 'lazy'} draggable="false" />
      {/if}
    {/each}
  </div>
  {#if formas.carteles === 'completo'}<div class="f-sombra"></div>{/if}
  {#if carteles.length > 1}
    <div class="puntos" aria-hidden="true">
      {#each carteles as c, i (c.ruta + ':' + i)}<i class:si={i === actual}></i>{/each}
    </div>
  {/if}
  <button
    type="button"
    class="f-cartel-info"
    class:f-ci-icono={!capsula}
    class:cerrado={capsula && !abierto}
    aria-label={t.info}
    onclick={(e) => alInfo(e.currentTarget)}
  >
    {#if capsula}
      <span class="f-ci-textos">
        <span class="f-ci-estado"><i></i>{estadoUno}</span>
        {#if estadoDos}<span class="f-ci-segundo">{estadoDos}</span>{/if}
      </span>
    {/if}
    <Icono nombre="info" tamano={19} />
  </button>
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
