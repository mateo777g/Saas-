<!--
  Cancelar toda la cuenta (maqueta Cancelaciones y descuentos, estado «Cancelar cuenta», en «⋯»):
  se cancela todo lo que lleva con un motivo, y la mesa queda libre. La cocina lo ve tachado. Con
  pagos no se puede: primero se cancelan desde la caja.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import CajaError from '../../diseno/CajaError.svelte';
  import { dinero, plural } from '../../lib/formato';
  import type { Autoriza, Renglon, Venta } from '../../lib/pos';
  import HojaPedir from './HojaPedir.svelte';

  let {
    cliente,
    venta,
    titulo,
    sub,
    renglones,
    autorizan,
    zona,
    alCerrar,
    alListo,
  }: {
    cliente: SupabaseClient;
    venta: Venta;
    titulo: string;
    sub: string; // «Abrió Toño · 13:05»
    renglones: Renglon[]; // los de esta cuenta
    autorizan: Autoriza[] | null;
    zona: string;
    alCerrar: () => void;
    alListo: (globo: string) => void;
  } = $props();

  let motivo = $state('');

  const productos = $derived(renglones.filter((r) => r.estado === 'activo').reduce((s, r) => s + r.cantidad, 0));
  const libre = $derived(venta.tipo === 'mesa' && venta.folio === null);
  const pedido = $derived(
    venta.pagado === 0 && motivo.trim()
      ? { funcion: 'cancelar_cuenta' as const, datos: { p_venta_id: venta.id, p_motivo: motivo.trim() } }
      : null,
  );
</script>

<HojaPedir
  {cliente}
  titulo="Cancelar {titulo}"
  {sub}
  {pedido}
  resumen="Cancelar {titulo} · «{motivo.trim()}»"
  texto="Cancelar cuenta"
  {autorizan}
  {zona}
  {alCerrar}
  alListo={(autorizo) => alListo(autorizo ? `${titulo} cancelada · autorizó ${autorizo}` : `${titulo} cancelada`)}
>
  <p class="confirmar-texto">
    Se cancela todo lo de «{titulo}» ({plural(productos, 'producto', 'productos')}, {dinero(venta.total)}){libre
      ? ' y la mesa queda libre'
      : ''}. La cocina lo ve tachado.
  </p>
  <div class="campo">
    <label class="etq" for="motivo-cuenta">Motivo</label>
    <input id="motivo-cuenta" placeholder="Ej. «Se fue sin pagar»" autocomplete="off" bind:value={motivo} />
  </div>
  {#if venta.pagado > 0}
    <CajaError mensaje="Esta cuenta tiene pagos ({dinero(venta.pagado)}). Cancélalos antes desde la caja." />
  {/if}
</HojaPedir>
