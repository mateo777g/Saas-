<!--
  Un producto en la lista: su foto a la izquierda (sin foto, sin cuadro: no el negro del panel), su
  nombre, su precio a la derecha y dos renglones de su descripción. En la búsqueda lleva arriba su
  categoría. Al tocarlo se abre su ventana. Con la 6b, abajo a la derecha lleva su «+» del color de
  Don Chuy (sin pedidos no sale): sin opciones agrega 1 al momento, con opciones abre su ventana; ya
  en el pedido, dice cuántos lleva.
-->
<script lang="ts">
  import { urlImagen, type Producto } from '../lib/datos';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Icono from './Icono.svelte';
  import Precio from './Precio.svelte';

  let {
    producto,
    lengua,
    moneda,
    t,
    categoria,
    lleva = 0,
    alAbrir,
    alMas,
  }: {
    producto: Producto;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    categoria?: string;
    lleva?: number;
    alAbrir: () => void;
    alMas: (() => void) | null;
  } = $props();

  const nombre = $derived(enSuLengua(producto.nombre, producto.nombre_en, lengua));
  const descripcion = $derived(enSuLengua(producto.descripcion, producto.descripcion_en, lengua));
</script>

<!-- El «+» es un botón dentro de la fila, así que la fila no puede ser <button>. -->
<div
  class="producto"
  role="button"
  tabindex="0"
  onclick={alAbrir}
  onkeydown={(e) => {
    if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault();
      alAbrir();
    }
  }}
>
  {#if producto.imagen_ruta}
    <img class="foto" src={urlImagen(producto.imagen_ruta)} alt="" loading="lazy" decoding="async" />
  {/if}
  <span class="textos">
    {#if categoria}<span class="cat">{categoria}</span>{/if}
    <span class="renglon">
      <span class="nombre">{nombre}</span>
      <span class="precio"><Precio {producto} {moneda} {t} /></span>
    </span>
    {#if descripcion || alMas}
      <span class="abajo">
        {#if descripcion}<span class="desc">{descripcion}</span>{/if}
        {#if alMas}
          <button
            type="button"
            class="mas"
            class:lleva={lleva > 0}
            aria-label={producto.grupos.length ? t.elegirA(nombre) : t.agregarA(nombre)}
            onclick={(e) => {
              e.stopPropagation();
              alMas();
            }}
          >
            {#if lleva}{lleva}{:else}<Icono nombre="mas" tamano={16} />{/if}
          </button>
        {/if}
      </span>
    {/if}
  </span>
</div>

<style>
  .producto {
    display: flex;
    gap: 14px;
    width: 100%;
    padding: 14px 0;
    border: 0;
    border-bottom: 1px solid var(--m-linea);
    background: transparent;
    color: inherit;
    text-align: left;
    cursor: pointer;
  }

  .producto:last-child {
    border-bottom: 0;
  }

  .foto {
    width: 92px;
    height: 92px;
    border-radius: 16px;
    flex: none;
    object-fit: cover;
    background: var(--m-chip);
  }

  .textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .renglon {
    display: flex;
    align-items: flex-start;
    gap: 10px;
  }

  .nombre {
    flex: 1;
    min-width: 0;
    font-size: 15px;
    font-weight: 700;
    line-height: 1.3;
  }

  .precio {
    font-size: 14.5px;
    font-weight: 800;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
    text-align: right;
  }

  .abajo {
    display: flex;
    align-items: flex-end;
    gap: 10px;
  }

  .desc {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--m-suave);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .mas {
    margin-left: auto;
    width: 32px;
    height: 32px;
    flex: none;
    border-radius: 16px;
    border: 0;
    padding: 0;
    background: var(--m-acento);
    color: var(--m-sobre-acento);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 13px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }

  .mas.lleva {
    box-shadow:
      0 0 0 3px var(--m-fondo),
      0 0 0 4.5px var(--m-acento);
  }

  .cat {
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--m-tenue);
  }
</style>
