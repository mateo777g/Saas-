<!--
  Un producto en la lista: su foto a la izquierda (sin foto, sin cuadro: no el negro del panel), su
  nombre, su precio a la derecha y dos renglones de su descripción. En la búsqueda lleva arriba su
  categoría. Al tocarlo se abre su ventana.
-->
<script lang="ts">
  import { urlImagen, type Producto } from '../lib/datos';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Precio from './Precio.svelte';

  let {
    producto,
    lengua,
    moneda,
    t,
    categoria,
    alAbrir,
  }: {
    producto: Producto;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    categoria?: string;
    alAbrir: () => void;
  } = $props();

  const descripcion = $derived(enSuLengua(producto.descripcion, producto.descripcion_en, lengua));
</script>

<button type="button" class="producto" onclick={alAbrir}>
  {#if producto.imagen_ruta}
    <img class="foto" src={urlImagen(producto.imagen_ruta)} alt="" loading="lazy" decoding="async" />
  {/if}
  <span class="textos">
    {#if categoria}<span class="cat">{categoria}</span>{/if}
    <span class="renglon">
      <span class="nombre">{enSuLengua(producto.nombre, producto.nombre_en, lengua)}</span>
      <span class="precio"><Precio {producto} {moneda} {t} /></span>
    </span>
    {#if descripcion}<span class="desc">{descripcion}</span>{/if}
  </span>
</button>

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

  .desc {
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

  .cat {
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--m-tenue);
  }
</style>
