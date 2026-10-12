<!--
  ventana() de diseno.py: una tarjeta sólida de radio 26 con la sombra del vidrio, sobre el velo
  del tema. Arriba, la cabeza de la maqueta: la etiqueta ("NUEVO CLIENTE"), el título de 24 y la
  X; debajo, si hay, un texto (13, o 12.5 en Perfil, como en Flet). Lo demás lo pone quien la abre (casi siempre un Formulario).

  Es un <dialog> del navegador: mientras está abierta, lo de atrás no se puede tocar ni recibe
  el foco. Se cierra con la X, con Escape o con un clic en el velo, como en la maqueta
  (Tbt7H3G1QRXykzNKe1GXHh); el panel decide qué pasa al cerrar (alCerrar).
-->
<script lang="ts">
  import { onMount, type Snippet } from 'svelte';
  import BotonCuadro from './BotonCuadro.svelte';

  let {
    etiqueta,
    titulo,
    texto,
    ancho = 460,
    tamanoTexto = 13,
    alCerrar,
    children,
  }: {
    etiqueta: string;
    titulo: string;
    texto?: string;
    ancho?: number;
    tamanoTexto?: number;
    alCerrar: () => void;
    children: Snippet;
  } = $props();

  let dialogo: HTMLDialogElement;
  const idTitulo = $props.id();

  onMount(() => {
    dialogo.showModal();
    // Como en la maqueta: el foco va al primer campo, no a la X.
    dialogo.querySelector<HTMLElement>('input, select, textarea')?.focus({ preventScroll: true });
  });

  function alCancelar(e: Event) {
    // Escape: no la cierra el navegador por su cuenta, la cierra el panel.
    e.preventDefault();
    alCerrar();
  }
</script>

<!-- El clic en el velo es un atajo del ratón; con el teclado se cierra con Escape (oncancel). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogo}
  class="velo"
  aria-labelledby={idTitulo}
  oncancel={alCancelar}
  onclick={(e) => {
    if (e.target === dialogo) alCerrar();
  }}
>
  <div class="ventana" style:width="{ancho}px">
    <div class="cabeza">
      <div class="titulos">
        <span class="etiqueta">{etiqueta}</span>
        <h2 class="titulo" id={idTitulo}>{titulo}</h2>
      </div>
      <BotonCuadro icono="cerrar" ayuda="Cerrar" onclick={alCerrar} />
    </div>
    {#if texto}
      <p class="texto" style:font-size="{tamanoTexto}px">{texto}</p>
    {/if}
    {@render children()}
  </div>
</dialog>

<style>
  .velo[open] {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    max-width: none;
    max-height: none;
    margin: 0;
    padding: 16px;
    border: 0;
    background: var(--velo);
    color: var(--texto);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: auto;
  }

  .velo::backdrop {
    background: transparent;
  }

  .ventana {
    max-width: 100%;
    margin: auto;
    padding: 28px;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 26px;
    box-shadow: 0 24px 60px var(--sombra);
  }

  .cabeza {
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .titulo {
    margin: 0;
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.5px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .texto {
    margin: 6px 0 0;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }
</style>
