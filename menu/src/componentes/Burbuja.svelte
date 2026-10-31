<!--
  La burbuja del asistente (parte 6c; maqueta 2UPwZw31WrcYRZkH8jaT1Y): abajo a la derecha, arriba de
  «Ver tu pedido» (o del aviso de los pedidos), o sola en la esquina. Siempre está, aunque el
  restaurante esté cerrado, en pausa o sin IA: ahí aparece Fragmentless. Va en el color de Don Chuy
  con la estrella de Fragmentless en degradado, en la versión del logo para ese fondo (decidido en la
  prueba de Banderitas, el 31 de octubre de 2026; antes iba en la tinta del tema con la ∫∫). Sin
  color, en los neutros del menú: negra en el tema claro, clara en el oscuro.
-->
<script lang="ts">
  import { esClaro } from '@app/lib/color';
  import type { Textos } from '../lib/textos';
  import Estrella, { type FondoEstrella } from './Estrella.svelte';

  let {
    color,
    tema,
    conBarra,
    t,
    alAbrir,
  }: { color: string | null; tema: string; conBarra: boolean; t: Textos; alAbrir: () => void } = $props();

  const fondo: FondoEstrella = $derived(
    color ? (esClaro(color) ? 'blanco' : 'azul') : tema === 'oscuro' ? 'blanco' : 'negro',
  );
</script>

<div class="lugar" class:con-barra={conBarra}>
  <button type="button" class="burbuja" aria-label={t.preguntale} onclick={alAbrir}><Estrella {fondo} tamano={32} /></button>
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
    background: var(--m-acento);
    color: var(--m-sobre-acento);
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 12px 30px var(--m-sombra);
  }
</style>
