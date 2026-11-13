<!--
  La barra de arriba de cada vista (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D):
  pegada arriba, de la barra lateral al borde derecho, con su línea de 1 px a la altura de la de la marca.
  Lleva el título de la vista, la pastilla de estado (punto verde mientras todo se lee bien; amarillo
  con `pausa`, los pedidos en pausa de la parte 6b; hueco con `hueco`, cuando a ningún cliente le sale
  un estilo o no se pudo leer Estilos) y, a la derecha, los botones que le pase la vista. `junto` va
  pegado al título, antes del chip (el selector Productos | Categorías de Mi menú, el día de Cortes y
  reportes). Con `chipAntes` la pastilla va pegada al título, antes de `junto` (Mi menú, con el dock al
  centro; maqueta U9YqpsSb2PeB5pFXTPvh1C, versión 14). Los botones de aquí miden 34.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { ponerEnBarra } from './vidrio';

  // En Cristal, lo que se pica aquí es vidrio (los botones de solo ícono, la sucursal, «Ocultar varios»): se lo dice a
  // sus piezas (diseno/vidrio.ts).
  ponerEnBarra();

  let {
    titulo,
    estado = null,
    antes,
    junto,
    chipAntes = false,
    children,
  }: {
    titulo: string;
    estado?: { texto: string; vivo: boolean; pausa?: boolean; hueco?: boolean } | null;
    // Antes del título: la flecha de volver (el punto de venta abierto en el panel).
    antes?: Snippet;
    junto?: Snippet;
    chipAntes?: boolean;
    children?: Snippet;
  } = $props();
</script>

<header class="barra" class:con-volver={!!antes}>
  {@render antes?.()}
  <h1 class="titulo">{titulo}</h1>
  {#if chipAntes}{@render chip()}{/if}
  {@render junto?.()}
  {#if !chipAntes}{@render chip()}{/if}
  <span class="crece"></span>
  {@render children?.()}
</header>

{#snippet chip()}
  {#if estado}
    <span class="chip">
      {#if estado.vivo || estado.pausa || estado.hueco}
        <span class="punto" class:pausa={estado.pausa} class:hueco={estado.hueco}></span>
      {/if}
      <span>{estado.texto}</span>
    </span>
  {/if}
{/snippet}

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

  /* Cristal: la barra es transparente. Lo que pasa por debajo se borra y se oscurece (en claro, se aclara) poco a
     poco; el desvanecido corre a todo lo ancho, también por detrás del menú flotante (300 px a la izquierda; el marco
     recorta lo que sobra), para que junto al menú no quede una raya. El menú va encima (z-index 3 sobre este 2). Solo
     lo que se pica va en vidrio; el título, la pastilla y la hora van sin vidrio. */
  :global(:root[data-estilo='cristal']) .barra {
    background: transparent;
    border-bottom-color: transparent;
  }

  :global(:root[data-estilo='cristal']) .barra::before {
    content: '';
    position: absolute;
    inset: 0 0 -18px -300px;
    z-index: -1;
    pointer-events: none;
    -webkit-backdrop-filter: blur(10px);
    backdrop-filter: blur(10px);
    -webkit-mask-image: linear-gradient(#000 55%, transparent);
    mask-image: linear-gradient(#000 55%, transparent);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .barra::before {
    background: linear-gradient(rgba(0, 0, 0, 0.55), rgba(0, 0, 0, 0));
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .barra::before {
    background: linear-gradient(rgba(255, 255, 255, 0.5), rgba(255, 255, 255, 0));
  }

  /* Los botones de vidrio de aquí llevan su canto con position: relative (el dock ya va con absolute). */
  :global(:root[data-estilo='cristal']) .barra :global([data-vidrio='boton']) {
    position: relative;
  }
</style>
