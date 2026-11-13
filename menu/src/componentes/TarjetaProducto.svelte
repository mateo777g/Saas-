<!--
  Un producto en tarjeta, con las formas de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r):
  - De dos en dos: la foto entera, el «+» en un cuadrito de vidrio arriba a la derecha y abajo, al
    centro, el nombre y el precio en un vidrio oscuro. Sin foto, su lugar en el gris con el ícono de su
    categoría.
  - Clásicas: la tarjeta blanca de siempre con la foto cuadrada arriba, y abajo a la izquierda el nombre
    y el precio, con el «+» a la derecha del precio.
  Al tocarla, o su «+», se abre el producto; ya en el pedido, el «+» dice cuántos lleva. Sin pedidos no
  hay «+».
-->
<script lang="ts">
  import { urlImagen, type Producto } from '../lib/datos';
  import { monto } from '../lib/precio';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    producto,
    forma,
    icono,
    lengua,
    moneda,
    t,
    lleva = 0,
    alAbrir,
    alMas,
  }: {
    producto: Producto;
    forma: 'dos_en_dos' | 'clasicas';
    // El ícono de su categoría, para la tarjeta sin foto.
    icono: string;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    lleva?: number;
    alAbrir: () => void;
    alMas: (() => void) | null;
  } = $props();

  const nombre = $derived(enSuLengua(producto.nombre, producto.nombre_en, lengua));
  const enDolares = $derived(moneda === 'usd' && producto.precio_usd !== null);
</script>

{#snippet precio()}{#if producto.desde}{t.desde} {/if}{monto(producto.precio, producto.precio_usd, moneda)}{#if enDolares}<small>{t.aprox}</small>{/if}{/snippet}

{#snippet mas(clase: string, tamano: number)}
  {#if alMas}
    <button
      type="button"
      class={clase}
      class:lleva={lleva > 0}
      aria-label={producto.grupos.length ? t.elegirA(nombre) : t.agregarA(nombre)}
      onclick={(e) => {
        e.stopPropagation();
        alMas();
      }}>{#if lleva}{lleva}{:else}<Icono nombre="mas" {tamano} grosor={2.2} />{/if}</button
    >
  {/if}
{/snippet}

<!-- El «+» es un botón dentro de la tarjeta, así que la tarjeta no puede ser <button>. -->
<div
  class={forma === 'clasicas' ? 'f-clasica' : 'f-tarjeta'}
  role="button"
  tabindex="0"
  aria-label={nombre}
  onclick={alAbrir}
  onkeydown={(e) => {
    if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault();
      alAbrir();
    }
  }}
>
  {#if forma === 'clasicas'}
    {#if producto.imagen_ruta}
      <img src={urlImagen(producto.imagen_ruta)} alt="" loading="lazy" decoding="async" />
    {:else}
      <span class="sin-foto"><Icono categoria={icono} tamano={30} /></span>
    {/if}
    <b>{nombre}</b>
    <div class="f-clasica-abajo">
      <span>{@render precio()}</span>
      {@render mas('f-mas-c', 18)}
    </div>
  {:else}
    {#if producto.imagen_ruta}
      <img src={urlImagen(producto.imagen_ruta)} alt="" loading="lazy" decoding="async" />
    {:else}
      <span class="f-sin-foto"><Icono categoria={icono} tamano={30} /></span>
    {/if}
    {@render mas('f-mas', 19)}
    <div class="f-vidrio">
      <b>{nombre}</b>
      <span>{@render precio()}</span>
    </div>
  {/if}
</div>

<style>
  /* La clásica sin foto: el cuadro de la foto en su gris, con el ícono de la categoría. */
  .sin-foto {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    aspect-ratio: 1 / 1;
    border-radius: 16px;
    background: var(--m-chip);
    color: var(--m-tenue);
  }
</style>
