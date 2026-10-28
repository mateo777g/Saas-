<!--
  La burbuja del asistente (parte 6c; maqueta 2UPwZw31WrcYRZkH8jaT1Y): abajo a la derecha, arriba de
  «Ver tu pedido» (o del aviso de los pedidos), o sola en la esquina. Siempre está, aunque el
  restaurante esté cerrado, en pausa o sin IA: ahí aparece Fragmentless. Va en la tinta del tema, no
  en el color de Don Chuy, para no competir con «Ver tu pedido».
-->
<script lang="ts">
  import Integral from '@app/diseno/Integral.svelte';
  import type { Textos } from '../lib/textos';

  let { conBarra, t, alAbrir }: { conBarra: boolean; t: Textos; alAbrir: () => void } = $props();
</script>

<div class="lugar" class:con-barra={conBarra}>
  <button type="button" class="burbuja" aria-label={t.preguntale} onclick={alAbrir}><Integral ancho={26} alto={28} /></button>
</div>

<style>
  /* En la compu, en la orilla de la columna del menú, como «Ver tu pedido». */
  .lugar {
    position: fixed;
    left: 0;
    right: 0;
    bottom: calc(28px + env(safe-area-inset-bottom, 0px));
    z-index: 4;
    max-width: 520px;
    margin: 0 auto;
    padding: 0 16px;
    display: flex;
    justify-content: flex-end;
    pointer-events: none;
  }

  .lugar.con-barra {
    bottom: calc(96px + env(safe-area-inset-bottom, 0px));
  }

  .burbuja {
    pointer-events: auto;
    width: 56px;
    height: 56px;
    border-radius: 28px;
    border: 0;
    padding: 0;
    background: var(--m-texto);
    color: var(--m-fondo);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 12px 30px var(--m-sombra);
  }
</style>
