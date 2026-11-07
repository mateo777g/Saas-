<!--
  «Ver inglés», al final de las ventanas de producto y de categoría de Mi menú (maqueta de Mi menú
  U9YqpsSb2PeB5pFXTPvh1C, versiones 1 y 7): la IA traduce sola al guardar, así que los campos en inglés
  van plegados. Cerrado es una píldora de 48 px; al picarla se abre como la caja del agente, con su
  mismo rebote (cubic-bezier(0.175, 0.885, 0.32, 1.275), 0.4 s), y los campos suben en 0.3 s con 80 ms
  de espera. Cerrado, sus campos no se alcanzan con Tab (`inert`). La pista de la derecha dice si falta
  traducir; abierto, que lo corregido se respeta. `columnas` acomoda los campos (dos lado a lado en
  producto). La ventana del grupo no usa esta: cambia sus mismos campos de idioma.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    children,
    traducido,
    columnas = 'minmax(0, 1fr)',
  }: { children: Snippet; traducido: boolean; columnas?: string } = $props();

  let caja = $state<HTMLDivElement>();
  let pista = $state<HTMLSpanElement>();
  let abierto = $state(false);

  const texto = $derived(
    abierto
      ? traducido
        ? 'Lo tradujo la IA. Si corriges algo, se respeta.'
        : 'La IA lo traduce sola. Si prefieres, escríbelo tú.'
      : traducido
        ? ''
        : 'La IA lo traduce sola.',
  );

  const quieto = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  function alternar() {
    if (!caja) return;
    abierto = !abierto;
    if (abierto) {
      caja.style.height = `${caja.scrollHeight}px`;
    } else {
      // Abierto pudo quedar en «auto» (si sus campos crecieron): primero su alto de ahorita, y luego cierra.
      if (caja.style.height === 'auto') {
        caja.style.height = `${caja.offsetHeight}px`;
        void caja.offsetHeight;
      }
      caja.style.height = '';
    }
    if (!quieto())
      pista?.animate([{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], { duration: 300, easing: 'ease-out' });
  }

  // Ya abierto, se suelta su alto: así crece si uno de sus campos crece.
  function alTerminar(e: TransitionEvent) {
    if (e.target === caja && e.propertyName === 'height' && abierto && caja) caja.style.height = 'auto';
  }
</script>

<div class="ver-ingles" class:abierto bind:this={caja} ontransitionend={alTerminar}>
  <button type="button" class="ver-ingles-fila" aria-expanded={abierto} onclick={alternar}>
    <span class="vi-titulo">Ver inglés</span>
    <span class="vi-pista" bind:this={pista}>{texto}</span>
    <svg class="vi-flecha" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
      ><path d="M6 9l6 6 6-6"></path></svg
    >
  </button>
  <div class="en-ingles" style:grid-template-columns={columnas} inert={!abierto}>
    {@render children()}
  </div>
</div>

<style>
  .ver-ingles {
    margin-top: 4px;
    height: 48px;
    overflow: hidden;
    border-radius: 24px;
    background: var(--chip);
    transition: height 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .ver-ingles-fila {
    width: 100%;
    min-height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 16px;
    border: 0;
    border-radius: 24px;
    background: transparent;
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  .ver-ingles-fila:hover {
    background: var(--chip);
  }

  .ver-ingles-fila:focus-visible {
    outline: 2px solid var(--acento);
    outline-offset: -2px;
  }

  .vi-titulo {
    font-size: 13px;
    font-weight: 700;
    flex: none;
  }

  .vi-pista {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    text-align: right;
  }

  .vi-flecha {
    flex: none;
    color: var(--suave);
    transition: transform 0.15s ease;
  }

  .abierto .vi-flecha {
    transform: rotate(180deg);
  }

  .en-ingles {
    display: grid;
    gap: 12px 16px;
    align-items: start;
    padding: 4px 16px 16px;
    opacity: 0;
    transform: translateY(8px);
    transition:
      opacity 0.2s ease,
      transform 0.2s ease;
  }

  .abierto .en-ingles {
    opacity: 1;
    transform: none;
    transition:
      opacity 0.3s ease 0.08s,
      transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) 0.08s;
  }

  /* Los campos de adentro, sólidos sobre el gris del bloque. */
  .en-ingles :global(input),
  .en-ingles :global(textarea) {
    background: var(--solido);
  }

  @media (prefers-reduced-motion: reduce) {
    .ver-ingles,
    .ver-ingles * {
      transition: none !important;
    }
  }
</style>
