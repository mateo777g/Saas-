<!--
  «Usa su premio de la tarjeta» (maqueta v22, pantalla «Pedidos»): el pedido del menú que usa el premio de su tarjeta de
  lealtad, en el verde del premio, o en ámbar si ya no alcanza («se confirma sin él»). Lo pintan la tarjeta del Tablero
  (TarjetaPedido.svelte, a lo ancho) y la lista angosta de Pedidos.svelte: salió aparte en la prueba de verdad del 23 nov,
  que encontró que la lista angosta no lo enseñaba.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { dinero } from '../../../lib/formato';
  import type { PorConfirmar } from '../../../lib/pedidos.svelte';

  let { premio }: { premio: NonNullable<PorConfirmar['premio']> } = $props();
</script>

<div class="usa-premio" class:no={!premio.alcanza}>
  <span class="premio-i"><Icono nombre="regalo" tamano={17} /></span>
  <span class="premio-t">
    <b>Usa su premio de la tarjeta</b>
    <span
      >{premio.tipo === 'producto' ? `${premio.nombre ?? 'Su producto'} gratis` : `${dinero(premio.pesos ?? 0)} de descuento`}: {premio.alcanza
        ? premio.tipo === 'producto'
          ? 'entra a la cuenta al confirmar'
          : 'se resta al confirmar'
        : 'ya no alcanza; se confirma sin él'}</span
    >
  </span>
</div>

<style>
  /* El pedido que usa el premio de la tarjeta de lealtad, en el verde del premio (en ámbar si ya no alcanza). */
  .usa-premio {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 12px 0 2px;
    padding: 9px 12px;
    border-radius: 12px;
    background: color-mix(in srgb, var(--verde) 12%, transparent);
  }

  .usa-premio.no {
    background: rgba(245, 166, 35, 0.13);
  }

  .premio-i {
    width: 28px;
    height: 28px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--verde);
    color: #fff;
  }

  .usa-premio.no .premio-i {
    background: #c98a1a;
  }

  .premio-t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .premio-t b {
    font-size: 13px;
    font-weight: 700;
    color: var(--texto);
  }

  .premio-t > span {
    font-size: 12px;
    color: var(--suave);
  }
</style>
