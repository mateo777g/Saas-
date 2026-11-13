<!--
  Ajustes («Tu menú en línea», detalle 10 de la maqueta UDArhiEZceT7rmSKxqRA5r): con el logo al centro,
  el engrane de la barra lo abre desde la derecha sobre un velo, con el idioma y la moneda en renglones
  con su flechita y su listita. Se cierra con su X, con el velo, con Escape o con «atrás» del celular
  (el historial lo lleva Menu.svelte). Sin dólares, solo el idioma. Le cabe crecer: aquí entrarán otros
  ajustes de la clienta.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { desliza, velo } from '../lib/movimiento';
  import type { Moneda } from '../lib/preferencias';
  import type { Lengua, Textos } from '../lib/textos';
  import Icono from './Icono.svelte';
  import ListaBoton from './ListaBoton.svelte';

  let {
    lengua,
    moneda,
    conDolares,
    t,
    alLengua,
    alMoneda,
    alCerrar,
  }: {
    lengua: Lengua;
    moneda: Moneda;
    conDolares: boolean;
    t: Textos;
    alLengua: (l: Lengua) => void;
    alMoneda: (m: Moneda) => void;
    alCerrar: () => void;
  } = $props();

  let panel: HTMLElement;

  onMount(() => {
    panel.focus({ preventScroll: true });
  });

  const idiomas = $derived([
    { valor: 'es', texto: t.idiomas[0], bandera: 'mx' as const },
    { valor: 'en', texto: t.idiomas[1], bandera: 'us' as const },
  ]);
  const monedas = $derived([
    { valor: 'mxn', texto: t.monedas[0], bandera: 'mx' as const },
    { valor: 'usd', texto: t.monedas[1], bandera: 'us' as const },
  ]);
</script>

<!-- El velo es un atajo del dedo; con el teclado se cierra con Escape. -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="f-aj-velo" onclick={alCerrar} in:velo={{ intro: true }} out:velo={{ intro: false }}></div>
<div
  class="f-aj"
  role="dialog"
  aria-label={t.ajustes}
  tabindex="-1"
  bind:this={panel}
  in:desliza={{ lado: 'derecha', intro: true }}
  out:desliza={{ lado: 'derecha', intro: false }}
>
  <div class="f-aj-cabeza">
    <b>{t.ajustes}</b>
    <button type="button" class="f-aj-cerrar" aria-label={t.cerrar} onclick={alCerrar}><Icono nombre="cerrar" tamano={18} grosor={2} /></button>
  </div>
  <div class="f-aj-grupo">
    <span class="f-aj-etiqueta">{t.idioma}</span>
    <ListaBoton opciones={idiomas} elegida={lengua} etiqueta={t.idioma} alElegir={(v) => alLengua(v as Lengua)}>
      {#snippet boton({ abierta, alternar })}
        <button type="button" class="f-aj-boton" aria-haspopup="listbox" aria-expanded={abierta} onclick={alternar}>
          <Icono nombre="mundo" tamano={18} grosor={1.6} />
          <span class="f-aj-valor">{idiomas.find((o) => o.valor === lengua)?.texto}</span>
          <span class="f-aj-flecha"><Icono nombre="chevron" tamano={18} grosor={2} /></span>
        </button>
      {/snippet}
    </ListaBoton>
  </div>
  {#if conDolares}
    <div class="f-aj-grupo">
      <span class="f-aj-etiqueta">{t.moneda}</span>
      <ListaBoton opciones={monedas} elegida={moneda} etiqueta={t.moneda} alElegir={(v) => alMoneda(v as Moneda)}>
        {#snippet boton({ abierta, alternar })}
          <button type="button" class="f-aj-boton" aria-haspopup="listbox" aria-expanded={abierta} onclick={alternar}>
            <Icono nombre="monedas" tamano={20} grosor={1.3} />
            <span class="f-aj-valor">{monedas.find((o) => o.valor === moneda)?.texto}</span>
            <span class="f-aj-flecha"><Icono nombre="chevron" tamano={18} grosor={2} /></span>
          </button>
        {/snippet}
      </ListaBoton>
    </div>
  {/if}
</div>

<style>
  .f-aj:focus {
    outline: none;
  }
</style>
