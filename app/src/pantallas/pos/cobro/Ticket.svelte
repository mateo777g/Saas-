<!--
  El ticket de una cuenta cobrada a lo ancho (maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, pantalla «Cobrada»): en el gris de las
  vistas, lo que llevaba («1 × Latte · $48.00»), un corte punteado, el total y cómo pagó. Con un solo pago: «Pagó $100.00»
  en efectivo (con cuánto pagó) o «$98.00 con tarjeta»; con varios, uno por renglón. El cambio en verde, solo si el último
  fue en efectivo y hubo cambio (con «Exacto» no sale). Todos los números vienen de Postgres; sin `pagos`, solo hasta el total.
-->
<script lang="ts">
  import { conPropina, NOMBRE_METODO, type LineaTicket } from '../../../lib/caja';
  import { pesos } from '../../../lib/formato';
  import type { PagoTicket } from './cobro.svelte';

  let {
    lineas,
    subtotal,
    descuento = null,
    total,
    pagos = null,
  }: {
    lineas: LineaTicket[];
    subtotal: number;
    descuento?: { texto: string; monto: number } | null;
    total: number;
    pagos?: PagoTicket[] | null;
  } = $props();

  const ultimo = $derived(pagos?.at(-1) ?? null);
  const propinas = $derived((pagos ?? []).filter((p) => p.propina > 0));
  const entrego = (p: PagoTicket) => (p.metodo === 'efectivo' && p.recibido !== null ? p.recibido : conPropina(p));
</script>

<section class="ticket">
  {#if lineas.length}
    <div class="ticket-l">
      {#each lineas as l (l.id)}
        <div class="ticket-r"><span><b>{l.cantidad} ×</b> {l.nombre}</span><span class="mono">{pesos(l.importe)}</span></div>
      {/each}
    </div>
    <div class="ticket-corte" aria-hidden="true"></div>
  {/if}
  {#if descuento}
    <div class="ticket-f"><span>Subtotal</span><b>{pesos(subtotal)}</b></div>
    <div class="ticket-f"><span>Descuento {descuento.texto}</span><b>−{pesos(descuento.monto)}</b></div>
  {/if}
  <div class="ticket-f"><span>Total</span><b>{pesos(total)}</b></div>
  {#each propinas as p, i (i)}
    <div class="ticket-f"><span>Propina</span><b>{pesos(p.propina)}</b></div>
  {/each}
  {#if pagos && pagos.length === 1 && ultimo}
    <div class="ticket-f">
      <span>Pagó</span>
      <b>{ultimo.metodo === 'efectivo' ? pesos(entrego(ultimo)) : `${pesos(entrego(ultimo))} con ${NOMBRE_METODO[ultimo.metodo].toLowerCase()}`}</b>
    </div>
  {:else if pagos}
    {#each pagos as p, i (i)}
      <div class="ticket-f"><span>Pagó con {NOMBRE_METODO[p.metodo].toLowerCase()}</span><b>{pesos(entrego(p))}</b></div>
    {/each}
  {/if}
  {#if ultimo?.metodo === 'efectivo' && ultimo.cambio > 0}
    <div class="ticket-f cambio-f"><span>Cambio</span><b>{pesos(ultimo.cambio)}</b></div>
  {/if}
</section>

<style>
  .ticket {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 16px 18px;
    border-radius: 12px;
    background: var(--fondo);
  }
  .ticket-l {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .ticket-r,
  .ticket-f {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 13px;
  }
  .ticket-r span:last-child,
  .ticket-f b {
    font-family: var(--mono);
    font-weight: 500;
    white-space: nowrap;
  }
  .ticket-r b {
    font-weight: 700;
  }
  .ticket-corte {
    height: 0;
    border-top: 1.5px dashed var(--linea-fuerte, var(--linea));
    margin: 4px 0;
  }
  .ticket-f span {
    color: var(--suave);
    font-weight: 600;
  }
  .ticket-f.cambio-f span,
  .ticket-f.cambio-f b {
    color: var(--verde);
  }
</style>
