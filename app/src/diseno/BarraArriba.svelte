<!--
  La barra de arriba de cada vista (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D):
  pegada arriba, de la barra lateral al borde derecho, con su línea de 1 px a la altura de la de la marca.
  Lleva el título de la vista, la pastilla de estado (punto verde mientras todo se lee bien; amarillo
  con `pausa`, los pedidos en pausa de la parte 6b; hueco con `hueco`, cuando a ningún cliente le sale
  un estilo o no se pudo leer Estilos) y, a la derecha, los botones que le pase la vista. `junto` va
  pegado al título, antes del chip (el selector Productos | Categorías de Mi menú, el día de Cortes y
  reportes). Los botones de aquí miden 34.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    titulo,
    estado = null,
    antes,
    junto,
    children,
  }: {
    titulo: string;
    estado?: { texto: string; vivo: boolean; pausa?: boolean; hueco?: boolean } | null;
    // Antes del título: la flecha de volver (el punto de venta abierto en el panel).
    antes?: Snippet;
    junto?: Snippet;
    children?: Snippet;
  } = $props();
</script>

<header class="barra" class:con-volver={!!antes}>
  {@render antes?.()}
  <h1 class="titulo">{titulo}</h1>
  {@render junto?.()}
  {#if estado}
    <span class="chip">
      {#if estado.vivo || estado.pausa || estado.hueco}
        <span class="punto" class:pausa={estado.pausa} class:hueco={estado.hueco}></span>
      {/if}
      <span>{estado.texto}</span>
    </span>
  {/if}
  <span class="crece"></span>
  {@render children?.()}
</header>

<style>
  .barra {
    position: absolute;
    left: 0;
    right: 0;
    top: 0;
    height: 56px;
    z-index: 2;
    padding: 0 20px 0 24px;
    display: flex;
    align-items: center;
    gap: 12px;
    background: var(--solido);
    border-bottom: 1px solid var(--linea);
  }

  .barra.con-volver {
    padding-left: 16px;
  }

  /* Un título largo (la primera pregunta de una conversación del agente) se corta con «…». */
  .titulo {
    max-width: 300px;
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 15.5px;
    font-weight: 700;
  }

  .chip {
    height: 26px;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 0 10px;
    border: 1px solid var(--linea);
    border-radius: 999px;
    font-size: 12px;
    font-weight: 400;
    color: var(--suave);
    white-space: nowrap;
  }

  .punto {
    width: 7px;
    height: 7px;
    flex: none;
    border-radius: 50%;
    background: var(--verde);
  }

  .punto.pausa {
    background: var(--amarillo);
  }

  .punto.hueco {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }

  .crece {
    flex-grow: 1;
  }

  /* Los botones de la barra: 34 de alto, radio 9 e icono de 18, como en la maqueta. */
  .barra :global(.boton) {
    height: 34px;
    padding: 0 13px;
    border-radius: 9px;
  }

  .barra :global(.boton.tinta),
  .barra :global(.boton.acento) {
    padding: 0 14px;
  }

  .barra :global(.boton > svg) {
    width: 18px;
    height: 18px;
  }

  .barra :global(.cuadro) {
    width: 34px;
    height: 34px;
    border-radius: 9px;
    color: var(--suave);
  }

  .barra :global(.cuadro > svg) {
    width: 18px;
    height: 18px;
  }
</style>
