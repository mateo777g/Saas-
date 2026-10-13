<!--
  La foto de un producto en su cuadro negro: 44 en la tabla, 72 en la ventana. Sin foto, o si no
  carga, se queda el cuadro negro (como sin-foto.png de Flet, negro a propósito). Un producto
  oculto la lleva al 40 %.
-->
<script lang="ts">
  let {
    src,
    tamano = 44,
    radio = 11,
    oculta = false,
  }: { src: string | null; tamano?: number; radio?: number; oculta?: boolean } = $props();

  let rota = $state<string | null>(null);
</script>

<span
  class="foto"
  class:oculta
  style:width="{tamano}px"
  style:height="{tamano}px"
  style:border-radius="{radio}px"
>
  {#if src && rota !== src}
    <img
      {src}
      alt=""
      loading="lazy"
      decoding="async"
      onerror={() => {
        console.error('[menu] no cargó la foto', src);
        rota = src;
      }}
    />
  {/if}
</span>

<style>
  .foto {
    flex: none;
    display: block;
    overflow: hidden;
    background: #000000;
  }

  .oculta {
    opacity: 0.4;
  }

  img {
    width: 100%;
    height: 100%;
    display: block;
    object-fit: cover;
  }
</style>
