<!--
  Una cuenta cobrada a lo ancho (maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, pantalla «Cobrada»): la palomita de línea que se dibuja
  (la de «Pedido enviado» del menú digital), «#24 cerrada», el folio con cómo pagó y el ticket. Con `animar` en falso
  (una cobrada que se abre desde la lista de la Caja) la palomita ya está dibujada y nada sube. Con «reducir
  movimiento», quieta. Mientras se leen lo que llevaba y sus pagos (`cargando`), el ticket sale en esqueleto.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { NOMBRE_METODO, type LineaTicket, type Metodo } from '../../../lib/caja';
  import type { PagoTicket } from './cobro.svelte';
  import Ticket from './Ticket.svelte';

  let {
    titulo,
    folio,
    cuando = '',
    lineas,
    subtotal,
    descuento = null,
    total,
    pagos,
    metodos = [],
    animar = true,
    cargando = false,
    children,
  }: {
    titulo: string; // «#24 cerrada»
    folio: number | null;
    cuando?: string; // «13:50», para una cobrada que se abre desde la lista
    lineas: LineaTicket[];
    subtotal: number;
    descuento?: { texto: string; monto: number } | null;
    total: number;
    pagos: PagoTicket[] | null;
    metodos?: Metodo[]; // cómo pagó, mientras llegan sus pagos
    animar?: boolean;
    cargando?: boolean;
    children?: Snippet; // lo que va debajo del ticket (los pagos que se pueden cancelar)
  } = $props();

  const como = $derived([...new Set((pagos?.length ? pagos.map((p) => p.metodo) : metodos).map((m) => NOMBRE_METODO[m]))].join(' + '));
  const linea = $derived([folio !== null ? `Folio ${folio}` : '', como, cuando].filter(Boolean).join(' · '));
</script>

<div class="cerrada" class:animar>
  <div class="cerrada-arriba">
    <svg class="exito" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle class="aro" cx="24" cy="24" r="19"></circle>
      <path class="pal" d="M16 24.5l5.5 5.5L32.5 19"></path>
    </svg>
    <h3>{titulo}</h3>
    {#if linea}<p class="folio">{linea}</p>{/if}
  </div>
  <div class="sube-ticket">
    {#if cargando}
      <div class="ticket-esqueleto" aria-hidden="true">
        {#each ['58%', '46%', '52%'] as a, i (i)}
          <span class="r"><Esqueleto ancho={a} alto="12px" /><Esqueleto ancho="52px" alto="12px" /></span>
        {/each}
        <span class="corte"></span>
        <span class="r"><Esqueleto ancho="40px" alto="12px" /><Esqueleto ancho="60px" alto="12px" /></span>
        <span class="r"><Esqueleto ancho="36px" alto="12px" /><Esqueleto ancho="60px" alto="12px" /></span>
      </div>
    {:else}
      <Ticket {lineas} {subtotal} {descuento} {total} {pagos} />
    {/if}
  </div>
  {@render children?.()}
</div>

<style>
  .cerrada {
    display: flex;
    flex-direction: column;
    gap: 24px;
    padding: 18px 0 4px;
  }
  .cerrada-arriba {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    text-align: center;
  }
  .exito {
    width: 56px;
    height: 56px;
    margin-bottom: 8px;
    color: var(--verde);
  }
  .exito .aro {
    transform-box: fill-box;
    transform-origin: center;
    transform: rotate(-90deg);
  }
  h3 {
    margin: 0;
    font-size: 22px;
    font-weight: 800;
    letter-spacing: -0.4px;
  }
  .folio {
    margin: 0;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--suave);
  }

  /* El ticket mientras se lee: sus renglones en bloques, con las medidas del de Ticket.svelte. */
  .ticket-esqueleto {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 16px 18px;
    border-radius: 12px;
    background: var(--fondo);
  }

  .ticket-esqueleto .r {
    display: flex;
    justify-content: space-between;
    align-items: center;
    height: 17px;
  }

  .ticket-esqueleto .corte {
    border-top: 1.5px dashed var(--linea-fuerte, var(--linea));
    margin: 4px 0;
  }

  /* Al cobrar: el aro y la palomita se dibujan, y lo demás sube, uno tras otro. */
  .animar .exito .aro {
    stroke-dasharray: 120;
    stroke-dashoffset: 120;
    animation: traza 0.6s cubic-bezier(0.65, 0, 0.35, 1) 0.05s forwards;
  }
  .animar .exito .pal {
    stroke-dasharray: 24;
    stroke-dashoffset: 24;
    animation: traza 0.32s cubic-bezier(0.65, 0, 0.35, 1) 0.5s forwards;
  }
  @keyframes traza {
    to {
      stroke-dashoffset: 0;
    }
  }
  .animar h3 {
    animation: sube 0.55s cubic-bezier(0.22, 1, 0.36, 1) 0.12s both;
  }
  .animar .folio {
    animation: sube 0.55s cubic-bezier(0.22, 1, 0.36, 1) 0.2s both;
  }
  .animar .sube-ticket {
    animation: sube 0.55s cubic-bezier(0.22, 1, 0.36, 1) 0.32s both;
  }
  @keyframes sube {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .animar .exito .aro,
    .animar .exito .pal {
      stroke-dashoffset: 0;
    }
  }
</style>
