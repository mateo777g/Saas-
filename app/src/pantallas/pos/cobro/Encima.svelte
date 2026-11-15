<!--
  Lo que se abre encima del cobro (parte 4c): el descuento a la cuenta o cancelar un pago, con el PIN de otra persona si
  quien cobra no es de la caja ni gerente. Son las hojas del celular; a lo ancho van en la capa de hojas de quien pinta
  el cobro (al centro, de 440), porque la tarjeta las cortaría.
-->
<script lang="ts">
  import HojaCancelarPago from '../HojaCancelarPago.svelte';
  import HojaDescuento from '../HojaDescuento.svelte';
  import type { Cobro } from './cobro.svelte';

  let { cobro }: { cobro: Cobro } = $props();
</script>

{#if cobro.encima?.tipo === 'descuento' && cobro.cuenta}
  <HojaDescuento
    cliente={cobro.e.cliente}
    venta={cobro.cuenta}
    titulo={cobro.e.venta.titulo}
    autorizan={cobro.e.autorizan}
    zona={cobro.e.zona}
    alCerrar={() => (cobro.encima = null)}
    alListo={(globo) => cobro.alEncimaListo(globo)}
  />
{:else if cobro.encima?.tipo === 'pago'}
  {@const p = cobro.encima.pago}
  <HojaCancelarPago
    cliente={cobro.e.cliente}
    pago={p}
    titulo={cobro.e.venta.titulo}
    folio={cobro.cuenta?.folio ?? null}
    cerrada={false}
    cobro={p.cobrado_por !== null ? (cobro.e.nombres.get(p.cobrado_por) ?? '—') : 'En línea'}
    abrio={cobro.e.venta.abrio}
    autorizan={cobro.e.autorizan}
    zona={cobro.e.zona}
    alCerrar={() => (cobro.encima = null)}
    alListo={(globo) => cobro.alEncimaListo(globo)}
  />
{/if}
