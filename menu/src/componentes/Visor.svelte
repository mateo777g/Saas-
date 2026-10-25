<!--
  La foto del producto entera, sobre negro (maqueta de la 6a, estado «Foto»), con su nombre y su
  descripción abajo. La X (o Escape, o «atrás»: Menu.svelte) regresa a la ventana del producto.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { urlImagen } from '../lib/datos';
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let { ruta, nombre, descripcion, t, alCerrar }: { ruta: string; nombre: string; descripcion: string | null; t: Textos; alCerrar: () => void } =
    $props();

  let visor: HTMLDivElement;
  onMount(() => visor.focus({ preventScroll: true }));
</script>

<div class="visor" role="dialog" aria-modal="true" aria-label={nombre} tabindex="-1" bind:this={visor}>
  <button type="button" class="cerrar-flota" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} /></button>
  <img src={urlImagen(ruta)} alt={nombre} />
  <div class="pie">
    <b>{nombre}</b>
    {#if descripcion}<span>{descripcion}</span>{/if}
  </div>
</div>

<style>
  .visor {
    position: fixed;
    inset: 0;
    z-index: 8;
    background: #000;
    color: #fff;
    display: flex;
    flex-direction: column;
    justify-content: center;
    outline: none;
  }

  img {
    width: 100%;
    max-height: 100%;
    object-fit: contain;
  }

  .cerrar-flota {
    position: absolute;
    top: calc(16px + var(--arriba-seguro));
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

  .pie {
    position: absolute;
    left: 0;
    right: 0;
    bottom: calc(36px + env(safe-area-inset-bottom, 0px));
    padding: 0 20px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .pie b {
    font-size: 18px;
    font-weight: 800;
  }

  .pie span {
    font-size: 13px;
    color: rgba(255, 255, 255, 0.7);
  }
</style>
