<!--
  Lo que ve el cliente mientras llega su menú («Los esqueletos del menú digital», 12 nov 2026; maqueta
  UDArhiEZceT7rmSKxqRA5r v59, «TU CLIENTE ABRE TU MENÚ»: esqueletoGeneral y esqueletoQueRecuerda). Bloques que laten
  como los del panel (2 s), quietos con «reducir movimiento». La primera vez, uno general en blanco: la barra en gris
  clarito con el logo y el nombre, el cartel, la búsqueda, cuatro categorías, el título y los productos a lo largo, y
  la barra de abajo. Al regresar, el de su menú (lib/esqueleto.ts): sus bloques en el gris de su fondo y la barra de su
  color. Tapa toda la pantalla y se va con un desvanecido de 0.2 s cuando el menú ya está debajo.
-->
<script lang="ts">
  import { quieto } from '../lib/movimiento';
  import type { Recuerdo } from '../lib/esqueleto';

  let { recuerdo, texto }: { recuerdo: Recuerdo | null; texto: string } = $props();

  function sale(_el: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 200, easing: (x: number) => 1 - (1 - x) * (1 - x), css: (x: number) => `opacity: ${x}` };
  }

  const px = (n: number) => `${n}px`;
  const lugar = (p: number[]) => `left:${px(p[0])};top:${px(p[1])};width:${px(p[2])};height:${px(p[3])};border-radius:${px(p[4])}`;
  // Los bloques de la barra, un tono de sus letras.
  const enBarra = (p: number[]) => (recuerdo?.barra && p[1] < recuerdo.barra.alto ? `;background:color-mix(in oklab, ${recuerdo.barra.texto} 26%, transparent)` : '');
  const ANCHOS_CATS = [84, 102, 76, 92];
</script>

<div
  class="f-esq"
  class:primera={!recuerdo}
  style:background={recuerdo?.fondo}
  style:--esq={recuerdo ? `color-mix(in oklab, ${recuerdo.texto} 9%, ${recuerdo.fondo})` : undefined}
  out:sale
>
  <p class="f-esq-lector" role="status">{texto}</p>
  {#if recuerdo}
    <div class="f-esq-col" style:width={px(recuerdo.ancho)} aria-hidden="true">
      {#if recuerdo.barra}
        <span class="f-esq-pieza" style="left:{px(recuerdo.barra.x)};top:0;width:{px(recuerdo.barra.ancho)};height:{px(recuerdo.barra.alto)};background:{recuerdo.barra.fondo}"></span>
      {/if}
      {#each recuerdo.piezas as p, i (i)}
        {#if p[5]}
          <span class="f-esq-pieza" style="{lugar(p)};background:{recuerdo.fondo}"></span>
        {:else}
          <span class="f-esq-pieza f-esq-b" style="{lugar(p)}{enBarra(p)}"></span>
        {/if}
      {/each}
    </div>
    {#if recuerdo.abajo}
      <div class="f-esq-abajo-r" style:width={px(recuerdo.ancho)} style:height={px(recuerdo.abajo.alto)} aria-hidden="true">
        {#each recuerdo.abajo.piezas as p, i (i)}
          {#if p[5]}
            <span class="f-esq-pieza" style="{lugar(p)};background:{recuerdo.fondo}"></span>
          {:else}
            <span class="f-esq-pieza f-esq-b" style={lugar(p)}></span>
          {/if}
        {/each}
      </div>
    {/if}
  {:else}
    <div class="f-esq-gen" aria-hidden="true">
      <div class="f-esq-barra"><span class="f-esq-b logo"></span><span class="f-esq-b nombre"></span></div>
      <div class="f-esq-cuerpo">
        <span class="f-esq-b cartel"></span>
        <span class="f-esq-b busca"></span>
        <div class="f-esq-cats">
          {#each ANCHOS_CATS as w (w)}<span class="f-esq-b cat" style:width={px(w)}></span>{/each}
        </div>
        <span class="f-esq-b titulo"></span>
        <!-- Seis por si la pantalla es alta; en un celular se ven tres, como en la maqueta. -->
        {#each [0, 1, 2, 3, 4, 5] as i (i)}
          <div class="f-esq-fila">
            <span class="f-esq-b foto"></span>
            <div class="f-esq-textos"><span class="f-esq-b" style="width:120px;height:14px"></span><span class="f-esq-b" style="width:150px;height:11px"></span></div>
            <div class="f-esq-precio"><span class="f-esq-b" style="width:34px;height:14px"></span><span class="f-esq-b mas"></span></div>
          </div>
        {/each}
      </div>
      <div class="f-esq-abajo"><span class="f-esq-b ico"></span><span class="f-esq-b ico"></span><span class="f-esq-b ico"></span></div>
    </div>
  {/if}
</div>

<style>
  .f-esq {
    --esq: #ececec;
    position: fixed;
    inset: 0;
    z-index: 50;
    overflow: hidden;
    background: #ffffff;
    pointer-events: none;
  }

  .f-esq-lector {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: 0;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }

  /* Los bloques: el --chip del panel aquí es un gris del menú; laten cada 2 s como diseno/Esqueleto.svelte. */
  .f-esq-b {
    display: block;
    flex: none;
    background: var(--esq);
    border-radius: 6px;
    animation: f-esq-late 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }

  @keyframes f-esq-late {
    50% {
      opacity: 0.5;
    }
  }

  /* El que recuerda: medido de su columna (del ancho de un celular, o 520 en la compu). */
  .f-esq-col {
    position: relative;
    height: 100%;
    margin: 0 auto;
  }

  .f-esq-pieza {
    position: absolute;
  }

  .f-esq-abajo-r {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    margin: 0 auto;
  }

  /* El general (la primera vez): como esqueletoGeneral de la maqueta, en la columna del menú. */
  .f-esq-gen {
    height: 100%;
    max-width: 520px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
  }

  .f-esq-barra {
    flex: none;
    height: calc(76px + var(--arriba-seguro));
    display: flex;
    align-items: flex-start;
    gap: 14px;
    padding: calc(9px + var(--arriba-seguro)) 16px 0;
    background: #f4f4f4;
  }

  .f-esq-barra .logo {
    width: 48px;
    height: 48px;
    border-radius: 12px;
  }

  .f-esq-barra .nombre {
    width: 170px;
    height: 18px;
    margin-top: 15px;
  }

  .f-esq-cuerpo {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 14px 16px 0;
    overflow: hidden;
  }

  .cartel {
    width: 100%;
    aspect-ratio: 358 / 201;
    border-radius: 18px;
  }

  .busca {
    width: 100%;
    height: 46px;
    border-radius: 14px;
  }

  .f-esq-cats {
    display: flex;
    gap: 8px;
  }

  .cat {
    height: 36px;
    border-radius: 18px;
  }

  .titulo {
    width: 120px;
    height: 20px;
    margin-top: 8px;
  }

  .f-esq-fila {
    flex: none;
    display: flex;
    gap: 14px;
    padding: 12px 0;
    border-top: 1px solid #f1f1f1;
  }

  .foto {
    width: 92px;
    height: 92px;
    border-radius: 14px;
  }

  .f-esq-textos {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding-top: 6px;
  }

  .f-esq-precio {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    justify-content: space-between;
    padding: 6px 0 4px;
  }

  .mas {
    width: 28px;
    height: 28px;
    border-radius: 14px;
  }

  .f-esq-abajo {
    flex: none;
    height: calc(66px + env(safe-area-inset-bottom, 0px));
    display: flex;
    justify-content: space-around;
    align-items: center;
    padding: 0 40px calc(10px + env(safe-area-inset-bottom, 0px));
    border-top: 1px solid #f1f1f1;
  }

  .ico {
    width: 24px;
    height: 24px;
    border-radius: 7px;
  }

  @media (prefers-reduced-motion: reduce) {
    .f-esq-b {
      animation: none;
    }
  }
</style>
