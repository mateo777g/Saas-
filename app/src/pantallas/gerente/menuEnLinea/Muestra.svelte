<!--
  La vista previa del menú en línea en «Tu menú en línea» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn,
  sección 3): el menú de verdad, dentro de un marco, con el tema, el color y el tipo de cambio que Don
  Chuy todavía no guarda (lib/vistaMenu.ts). «menu» es el celular chico de «Así lo ven tus
  clientes», sin poder tocarse; «barra» es la tira de la ventana del color: la barra de arriba y las
  categorías, de su alto.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { alListo, linkDeMuestra, mandarMuestra, recargarMuestra, type Muestra } from '../../../lib/vistaMenu';

  let { slug, como, muestra }: { slug: string; como: 'menu' | 'barra'; muestra: Muestra } = $props();

  let marco = $state<HTMLIFrameElement>();
  let alto = $state(168);

  // Lo que no se ha guardado le llega al menú en cuanto cambia, y otra vez cuando avisa que ya pintó.
  $effect(() => {
    mandarMuestra(marco, { tema: muestra.tema, color: muestra.color, tipo_cambio_usd: muestra.tipo_cambio_usd });
  });

  onMount(() => {
    const quitar = alListo(
      () => marco,
      () => mandarMuestra(marco, muestra),
    );
    // La tira dice cuánto mide, por si el nombre del restaurante ocupa dos renglones.
    const medir = (e: MessageEvent) => {
      if (e.source === marco?.contentWindow && e.data?.fragmentless === 'alto' && typeof e.data.alto === 'number') {
        alto = e.data.alto;
      }
    };
    window.addEventListener('message', medir);
    return () => {
      quitar();
      window.removeEventListener('message', medir);
    };
  });

  // Después de cambiar un cartel: que el menú lo vuelva a pedir.
  export function recargar() {
    recargarMuestra(marco);
  }
</script>

{#if como === 'menu'}
  <div class="mini-marco">
    <iframe bind:this={marco} class="mini" src={linkDeMuestra(slug, 'menu')} title="Así ven tu menú tus clientes" tabindex="-1"></iframe>
  </div>
{:else}
  <iframe bind:this={marco} class="tira" style:height="{alto}px" src={linkDeMuestra(slug, 'barra')} title="Tu menú con este color"></iframe>
{/if}

<style>
  .mini-marco {
    width: 254px;
    height: 550px;
    border-radius: 34px;
    border: 7px solid #111;
    background: #111;
    overflow: hidden;
    position: relative;
    flex: none;
    box-shadow: 0 18px 40px var(--sombra);
  }

  .mini {
    position: absolute;
    left: 0;
    top: 0;
    width: 390px;
    height: 844px;
    border: 0;
    transform: scale(0.6154);
    transform-origin: 0 0;
    pointer-events: none;
  }

  .tira {
    display: block;
    width: 100%;
    border: 0;
  }
</style>
