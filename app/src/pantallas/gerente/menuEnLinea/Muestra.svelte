<!--
  La tira de la ventana del color de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59, abrirColor): el menú de
  verdad (?muestra=barra) con el color que se prueba y lo demás como va en el teléfono, sin poder tocarse. Lleva la
  barra de arriba y, según el color, las categorías (el de tu menú), la búsqueda y las categorías (el de la barra) o los
  productos de su primera categoría (el fondo). Mide lo que el menú le dice; si es más alta que su recorte, se desvanece
  abajo. El teléfono de la vista es aparte (Telefono.svelte).
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { alListo, linkDeMuestra, mandarMuestra, oirAlMenu, type Muestra, type TiraDeColor } from '../../../lib/vistaMenu';

  let { slug, tira, muestra }: { slug: string; tira: TiraDeColor; muestra: Muestra } = $props();

  let marco = $state<HTMLIFrameElement>();
  let alto = $state(168);
  const recorte = $derived(tira === 'colorBarra' ? 300 : 210);

  // Lo que se prueba le llega al menú en cuanto cambia, y otra vez cuando avisa que ya pintó.
  $effect(() => {
    mandarMuestra(marco, muestra);
  });

  onMount(() => {
    const quitarListo = alListo(
      () => marco,
      () => mandarMuestra(marco, muestra),
    );
    // La tira dice cuánto mide, por si el nombre del restaurante ocupa dos renglones.
    const quitarAlto = oirAlMenu(
      () => marco,
      (m) => {
        if (m.fragmentless === 'alto' && typeof m.alto === 'number') alto = m.alto;
      },
    );
    return () => {
      quitarListo();
      quitarAlto();
    };
  });
</script>

<div class="recorte" class:corta={alto > recorte} style:height="{Math.min(alto, recorte)}px">
  <iframe bind:this={marco} style:height="{alto}px" src={linkDeMuestra(slug, 'barra', tira)} title="Tu menú con este color" tabindex="-1"
  ></iframe>
</div>

<style>
  .recorte {
    overflow: hidden;
    border-radius: 14px;
    box-shadow: 0 0 0 1px var(--borde-tarjeta);
  }

  .recorte.corta {
    -webkit-mask-image: linear-gradient(to bottom, #000 calc(100% - 56px), transparent);
    mask-image: linear-gradient(to bottom, #000 calc(100% - 56px), transparent);
  }

  iframe {
    display: block;
    width: 100%;
    border: 0;
  }
</style>
