<!--
  La hoja que sube desde abajo (maqueta de la 6a: el producto, Ordenar por y la información), sobre
  el velo. Se cierra con su X, con un toque en el velo, con Escape o con «atrás» del celular (esos
  dos los lleva Menu.svelte, con el historial). Con la 6b puede llevar un pie fijo abajo («Agregar al
  pedido», «Hacer pedido»), y «Falta un paso» no se cierra con el velo.
-->
<script lang="ts">
  import { onMount, type Snippet } from 'svelte';

  let {
    etiqueta,
    alCerrar,
    children,
    pie,
  }: { etiqueta: string; alCerrar: (() => void) | null; children: Snippet; pie?: Snippet } = $props();

  let hoja: HTMLDivElement;

  onMount(() => {
    hoja.focus({ preventScroll: true });
  });
</script>

<!-- El velo es un atajo del dedo; con el teclado se cierra con Escape. -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="velo" onclick={() => alCerrar?.()}></div>
<div class="hoja" role="dialog" aria-modal="true" aria-label={etiqueta} tabindex="-1" bind:this={hoja}>
  <div class="agarre"></div>
  <div class="cuerpo" class:con-pie={!!pie}>
    {@render children()}
  </div>
  {#if pie}
    <div class="pie">{@render pie()}</div>
  {/if}
</div>

<style>
  .velo {
    position: fixed;
    inset: 0;
    background: var(--m-velo);
    z-index: 5;
  }

  .hoja {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    width: 100%;
    max-width: 520px;
    margin: 0 auto;
    z-index: 6;
    background: var(--m-hoja);
    border-radius: 26px 26px 0 0;
    box-shadow: 0 -12px 40px var(--m-sombra);
    display: flex;
    flex-direction: column;
    max-height: 92%;
    outline: none;
  }

  .agarre {
    width: 38px;
    height: 5px;
    border-radius: 3px;
    background: var(--m-linea);
    margin: 9px auto 0;
    flex: none;
  }

  .cuerpo {
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 14px 18px calc(28px + env(safe-area-inset-bottom, 0px));
    scrollbar-width: none;
  }

  /* Con pie, la orilla segura del celular la deja el pie. */
  .cuerpo.con-pie {
    padding-bottom: 28px;
  }

  /* La maqueta de la 6b: abajo, fijo, con su raya arriba. */
  .pie {
    flex: none;
    display: flex;
    gap: 10px;
    padding: 12px 18px calc(28px + env(safe-area-inset-bottom, 0px));
    border-top: 1px solid var(--m-linea);
  }

  .cuerpo::-webkit-scrollbar {
    display: none;
  }
</style>
