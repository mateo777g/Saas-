<!--
  Las tres columnas de Inicio (maqueta V64Pv4gmANPRZuJW5hTe5D): Abrir, Atajos y Recientes, las últimas 5
  vistas que se abrieron en este navegador. Cada panel pone sus renglones.
-->
<script lang="ts" module>
  export type ItemColumna = {
    clave: string;
    texto: string;
    de?: string;
    icono: string;
    // Lo que abre aparte lleva la flecha hacia afuera.
    flecha?: 'r-derecha' | 'r-afuera';
    alPicar: () => void;
  };
</script>

<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    abrir,
    atajos,
    recientes,
  }: {
    abrir: ItemColumna[];
    atajos: ItemColumna[];
    recientes: ItemColumna[];
  } = $props();
</script>

{#snippet renglones(lista: ItemColumna[])}
  {#each lista as a (a.clave)}
    <button type="button" class="item" onclick={a.alPicar}>
      <span class="icono"><Icono nombre={a.icono} tamano={18} /></span>
      <span class="t">{#if a.de}<span class="de">{a.de} /</span>{' '}{/if}{a.texto}</span>
      <span class="ir"><Icono nombre={a.flecha ?? 'r-derecha'} tamano={14} /></span>
    </button>
  {/each}
{/snippet}

<div class="columnas">
  <div>
    <div class="titulo">Abrir <Icono nombre="r-derecha" tamano={14} /></div>
    {@render renglones(abrir)}
  </div>

  <div>
    <div class="titulo">Atajos <Icono nombre="r-derecha" tamano={14} /></div>
    {@render renglones(atajos)}
  </div>

  <div>
    <div class="titulo">Recientes</div>
    {#if !recientes.length}
      <p class="vacio">Aquí salen las vistas que abras</p>
    {/if}
    {@render renglones(recientes)}
  </div>
</div>

<style>
  .columnas {
    width: 100%;
    max-width: 1000px;
    margin: 34px auto 0;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 32px;
  }

  .titulo {
    display: flex;
    align-items: center;
    gap: 4px;
    padding-bottom: 8px;
    font-size: 13px;
    font-weight: 400;
    color: var(--suave);
  }

  .item {
    width: 100%;
    height: 52px;
    display: flex;
    align-items: center;
    gap: 11px;
    padding: 0;
    border: 0;
    border-bottom: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 14.5px;
    font-weight: 500;
    text-align: left;
  }

  .item:last-child {
    border-bottom: 0;
  }

  .icono {
    display: flex;
    color: var(--suave);
  }

  .t {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .de {
    font-weight: 400;
    color: var(--tenue);
  }

  .ir {
    display: flex;
    color: var(--tenue);
  }

  .item:hover .ir {
    color: var(--texto);
  }

  .vacio {
    margin: 0;
    padding-top: 8px;
    font-size: 13.5px;
    font-weight: 400;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
