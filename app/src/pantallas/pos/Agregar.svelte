<!--
  Agregar productos a una cuenta (maqueta Mesero y cocina, estado «Agregar»): las categorías en
  pastillas y sus productos con su precio. Un producto con opciones abre la hoja que las pregunta;
  uno sin opciones se suma al borrador con un toque. Lo agotado sale en gris y no se toca. La
  bolita dice cuántos van anotados de cada uno.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { dinero } from '../../lib/formato';
  import { agotado, type CategoriaPos, type ProductoPos } from '../../lib/pos';

  let {
    titulo,
    categorias,
    cat,
    cuantos,
    porMandar,
    aviso,
    alCategoria,
    alProducto,
    alVer,
  }: {
    titulo: string;
    categorias: CategoriaPos[];
    cat: number;
    cuantos: Map<number, number>; // anotados de cada producto
    porMandar: number;
    aviso: Snippet;
    alCategoria: (i: number) => void;
    alProducto: (p: ProductoPos) => void;
    alVer: () => void;
  } = $props();

  const categoria = $derived(categorias[cat] ?? categorias[0]);

  // «Elige salsa y extras», «Va a Cocina» o «Lo sirve el mesero».
  function detalle(p: ProductoPos): string {
    if (agotado(p)) return 'Agotado';
    if (p.grupos.length) {
      const nombres = p.grupos.map((g) => g.nombre.toLowerCase());
      const ultimo = nombres.pop();
      return `Elige ${nombres.length ? `${nombres.join(', ')} y ${ultimo}` : ultimo}`;
    }
    return categoria.area ? `Va a ${categoria.area}` : 'Lo sirve el mesero';
  }
</script>

<div class="cel-arriba">
  <button type="button" class="cel-volver" onclick={alVer}><Icono nombre="anterior" tamano={16} />{titulo}</button>
  <span class="crece"></span>
  <span class="etq">Agregar</span>
</div>
{@render aviso()}

{#if categorias.length === 0}
  <div class="desliza">
    <div class="vacio">
      <b>El menú está vacío</b>
      <span>Tu gerente agrega los productos en Mi menú, en su panel.</span>
    </div>
  </div>
{:else}
  <div class="chips" role="group" aria-label="Categorías">
    {#each categorias as c, i (c.id)}
      <button type="button" class="chip-cat" aria-pressed={i === cat} onclick={() => alCategoria(i)}>{c.nombre}</button>
    {/each}
  </div>
  <div class="desliza lista-productos">
    {#each categoria.productos as p (p.id)}
      {@const sinHay = agotado(p)}
      {@const n = cuantos.get(p.id) ?? 0}
      <button type="button" class="producto" class:agotado={sinHay} disabled={sinHay} onclick={() => alProducto(p)}>
        <span class="t">
          <b>{p.nombre}</b>
          <span class="det">{detalle(p)}</span>
        </span>
        <span class="precio">{dinero(p.precio)}</span>
        {#if !sinHay}
          {#if n}
            <span class="cuantos">{n}</span>
          {:else}
            <span class="cuantos fantasma"><Icono nombre="mas" tamano={14} /></span>
          {/if}
        {/if}
      </button>
    {:else}
      <div class="vacio"><b>Sin productos en {categoria.nombre}</b></div>
    {/each}
  </div>
{/if}

<div class="cel-pie">
  <button type="button" class="cel-boton" onclick={alVer}>
    Ver {titulo}{porMandar ? ` · ${porMandar} por mandar` : ''}
  </button>
</div>

<style>
  .desliza.lista-productos {
    gap: 8px;
  }
</style>
