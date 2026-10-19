<!--
  La barra de arriba de cada vista ("ESTRUCTURA DE UNA VISTA" en plan panel.txt): vidrio sin
  sombra, 60 de alto, radio 18, de la barra lateral hasta 16 del borde derecho. Lleva el título
  de la vista, el chip de estado (punto verde mientras todo se lee bien) y, a la derecha, los
  botones que le pase la vista. `junto` va pegado al título, antes del chip (el selector
  Productos | Categorías de Mi menú, el día de Cortes y reportes), y `despues`, justo después del
  chip («Actualizado 18:05» de Inicio).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Vidrio from './Vidrio.svelte';

  let {
    titulo,
    estado = null,
    junto,
    despues,
    children,
  }: {
    titulo: string;
    estado?: { texto: string; vivo: boolean } | null;
    junto?: Snippet;
    despues?: Snippet;
    children?: Snippet;
  } = $props();
</script>

<Vidrio como="header" class="barra-arriba" radio={18} sombra={false}>
  <h1 class="titulo">{titulo}</h1>
  {@render junto?.()}
  {#if estado}
    <span class="chip">
      {#if estado.vivo}<span class="punto"></span>{/if}
      <span>{estado.texto}</span>
    </span>
  {/if}
  {@render despues?.()}
  <span class="crece"></span>
  {@render children?.()}
</Vidrio>

<style>
  :global(.barra-arriba) {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 16px;
    height: 60px;
    z-index: 2;
    padding: 0 12px 0 20px;
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .titulo {
    margin: 0;
    font-size: 15px;
    font-weight: 700;
  }

  .chip {
    height: 28px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 12px;
    border-radius: 14px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
  }

  .punto {
    width: 7px;
    height: 7px;
    flex: none;
    border-radius: 4px;
    background: var(--verde);
  }

  .crece {
    flex-grow: 1;
  }
</style>
