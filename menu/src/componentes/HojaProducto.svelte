<!--
  La ventana del producto, como la de SOHO (maqueta de la 6a, estado «Producto»): su foto grande (al
  tocarla se ve entera), su nombre, su precio, su descripción y sus grupos de opciones. En la 6a las
  opciones solo se leen; con la 6b se eligen aquí. Sin foto, la X va junto al nombre.
-->
<script lang="ts">
  import { urlImagen, type Producto } from '../lib/datos';
  import { monto } from '../lib/precio';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, textoRegla, type Lengua, type Textos } from '../lib/textos';
  import Hoja from './Hoja.svelte';
  import Icono from './Icono.svelte';
  import Precio from './Precio.svelte';

  let {
    producto,
    lengua,
    moneda,
    t,
    alVerFoto,
    alCerrar,
  }: {
    producto: Producto;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    alVerFoto: () => void;
    alCerrar: () => void;
  } = $props();

  const nombre = $derived(enSuLengua(producto.nombre, producto.nombre_en, lengua));
  const descripcion = $derived(enSuLengua(producto.descripcion, producto.descripcion_en, lengua));
</script>

<Hoja etiqueta={nombre} {alCerrar}>
  {#if producto.imagen_ruta}
    <div class="arriba">
      <button type="button" class="foto-grande" aria-label={t.verFoto} onclick={alVerFoto}>
        <img src={urlImagen(producto.imagen_ruta)} alt="" />
        <span class="lupa"><Icono nombre="lupa" tamano={18} /></span>
      </button>
      <button type="button" class="cerrar-flota" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
    </div>
    <h3 class="nombre">{nombre}</h3>
  {:else}
    <div class="cabeza">
      <h3 class="nombre sin-foto">{nombre}</h3>
      <button type="button" class="cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
    </div>
  {/if}
  <div class="precio"><Precio {producto} {moneda} {t} /></div>
  {#if descripcion}<p class="desc">{descripcion}</p>{/if}
  {#each producto.grupos as g, i (i)}
    <div class="grupo">
      <div class="grupo-cabeza">
        <span class="grupo-titulo">{enSuLengua(g.nombre, g.nombre_en, lengua)}</span>
        <span class="regla">{textoRegla(g.minimo, g.maximo, lengua)}</span>
      </div>
      {#each g.opciones as o, j (j)}
        <div class="op">
          <span>{enSuLengua(o.nombre, o.nombre_en, lengua)}</span>
          <span class="extra" class:cero={!o.precio_extra}>
            {o.precio_extra ? `+${monto(o.precio_extra, o.precio_extra_usd, moneda)}` : t.incluido}
          </span>
        </div>
      {/each}
    </div>
  {/each}
</Hoja>

<style>
  .arriba {
    position: relative;
  }

  .foto-grande {
    position: relative;
    width: 100%;
    aspect-ratio: 16 / 11;
    border-radius: 20px;
    overflow: hidden;
    border: 0;
    padding: 0;
    display: block;
    background: var(--m-chip);
  }

  .foto-grande img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .lupa {
    position: absolute;
    right: 10px;
    bottom: 10px;
    width: 34px;
    height: 34px;
    border-radius: 17px;
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .cerrar-flota {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 36px;
    height: 36px;
    border-radius: 18px;
    border: 0;
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1;
    padding: 0;
  }

  .cabeza {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
  }

  .cerrar {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 20px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .nombre {
    margin: 16px 0 0;
    font-size: 23px;
    font-weight: 800;
    letter-spacing: -0.4px;
    line-height: 1.2;
  }

  .nombre.sin-foto {
    margin-top: 6px;
  }

  .precio {
    margin-top: 6px;
    font-size: 17px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }

  .desc {
    margin: 8px 0 0;
    font-size: 14px;
    line-height: 1.55;
    color: var(--m-suave);
  }

  .grupo {
    margin-top: 22px;
  }

  .grupo-cabeza {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--m-linea);
  }

  .grupo-titulo {
    font-family: var(--mono);
    font-size: 11px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--m-texto);
    font-weight: 600;
  }

  .regla {
    font-size: 12px;
    color: var(--m-tenue);
  }

  .op {
    display: flex;
    justify-content: space-between;
    gap: 10px;
    padding: 12px 0;
    border-bottom: 1px solid var(--m-linea);
    font-size: 14.5px;
  }

  .op:last-child {
    border-bottom: 0;
  }

  .extra {
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .extra.cero {
    color: var(--m-tenue);
    font-weight: 500;
  }
</style>
