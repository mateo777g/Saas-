<!--
  Lo de abajo del menú («Tu menú en línea», maqueta UDArhiEZceT7rmSKxqRA5r; la burbuja flotando se quitó
  el 11 de noviembre de 2026): Menú, Pedido y Asistente como pestañas de una app. Una barra pegada abajo
  del color del fondo (con la que nace cada menú) o la misma en una píldora que flota, donde la elegida
  lleva detrás una pastilla del color del restaurante que se desliza. Con o sin el nombre de cada una
  (sin nombre se queda para el lector de pantalla). Pedido lleva cuántos productos van en el pedido.
  Sin WhatsApp no sale Pedido y sin asistente no sale Asistente; si solo queda Menú, no sale nada (eso
  lo decide Menu.svelte).
-->
<script lang="ts">
  import type { Formas, Pestana } from '../lib/formas';
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    pestanas,
    activa,
    cuantos,
    formas,
    t,
    alElegir,
  }: {
    pestanas: Pestana[];
    activa: Pestana;
    cuantos: number;
    formas: Formas;
    t: Textos;
    alElegir: (p: Pestana) => void;
  } = $props();

  const DE: Record<Pestana, { icono: string; texto: number }> = {
    menu: { icono: 'lista', texto: 0 },
    pedido: { icono: 'bolsa-app', texto: 1 },
    asistente: { icono: 'asistente', texto: 2 },
  };

  const pildora = $derived(formas.abajo === 'pildora');
</script>

<nav
  class="f-app"
  class:f-pildora={pildora}
  class:f-solo-iconos={!formas.abajo_con_nombres}
  aria-label={t.tuMenu}
  style:--n={pestanas.length}
  style:--i={Math.max(0, pestanas.indexOf(activa))}
>
  {#if pildora}<span class="f-app-luz" aria-hidden="true"></span>{/if}
  {#each pestanas as p (p)}
    <button type="button" class:activa={p === activa} aria-current={p === activa ? 'page' : undefined} data-app={p} onclick={() => alElegir(p)}>
      <span class="f-app-icono">
        <Icono nombre={DE[p].icono} tamano={24} />
        {#if p === 'pedido' && cuantos}<span class="f-app-cuenta">{cuantos}</span>{/if}
      </span>
      <span class="f-app-texto">{t.app[DE[p].texto]}</span>
    </button>
  {/each}
</nav>
