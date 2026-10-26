<!--
  Abajo del menú, fija (maqueta de la 6b): «Ver tu pedido» del color de Don Chuy, con cuántos lleva y
  su total, desde el primer producto. Si no se reciben pedidos, en su lugar dice por qué: «Recibimos
  pedidos de 9:00 a 18:00» (cerrado) o «Por ahora no recibimos pedidos» (pausa, sin teléfono o sin
  horario).
-->
<script lang="ts">
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    cuantos,
    total,
    aviso,
    t,
    alAbrir,
  }: {
    cuantos: number;
    total: string;
    aviso: { icono: 'reloj' | 'apagado'; texto: string } | null;
    t: Textos;
    alAbrir: () => void;
  } = $props();
</script>

<div class="fija">
  {#if aviso}
    <div class="aviso"><Icono nombre={aviso.icono} tamano={18} />{aviso.texto}</div>
  {:else}
    <button type="button" class="carrito" onclick={alAbrir}>
      <span class="n">{cuantos}</span>
      <span class="crece">{t.ver}</span>
      <span class="tot">{total}</span>
    </button>
  {/if}
</div>

<style>
  .fija {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 4;
    max-width: 520px;
    margin: 0 auto;
    padding: 18px 16px calc(28px + env(safe-area-inset-bottom, 0px));
    background: linear-gradient(to top, var(--m-fondo) 62%, transparent);
  }

  .carrito {
    width: 100%;
    height: 56px;
    border: 0;
    border-radius: 16px;
    padding: 0 18px 0 10px;
    display: flex;
    align-items: center;
    gap: 12px;
    background: var(--m-acento);
    color: var(--m-sobre-acento);
    font: inherit;
    font-size: 15px;
    font-weight: 800;
    text-align: left;
    box-shadow: 0 12px 30px var(--m-sombra);
  }

  .n {
    min-width: 36px;
    height: 36px;
    padding: 0 8px;
    border-radius: 11px;
    background: color-mix(in srgb, var(--m-sobre-acento) 18%, transparent);
    display: flex;
    align-items: center;
    justify-content: center;
    font-variant-numeric: tabular-nums;
  }

  .crece {
    flex: 1;
    min-width: 0;
  }

  .tot {
    font-variant-numeric: tabular-nums;
  }

  .aviso {
    height: 52px;
    border-radius: 16px;
    padding: 0 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    background: var(--m-chip);
    color: var(--m-texto);
    font-size: 14px;
    font-weight: 700;
  }

  .aviso :global(svg) {
    color: var(--m-suave);
  }
</style>
