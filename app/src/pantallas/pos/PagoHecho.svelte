<!--
  Un pago ya anotado (maquetas La caja y Cancelaciones y descuentos): cómo se pagó, quién lo anotó y
  a qué hora, la propina y el monto. Uno cancelado se queda tachado, con su motivo y quién lo canceló. Con
  `alCancelar`, lleva su botón «Cancelar».
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import { NOMBRE_METODO, type Pago } from '../../lib/caja';
  import { dinero, enZona } from '../../lib/formato';

  let {
    pago,
    nombres,
    zona,
    alCancelar,
  }: { pago: Pago; nombres: Map<number, string>; zona: string; alCancelar?: () => void } = $props();

  const nombre = (id: number | null) => (id === null ? '—' : (nombres.get(id) ?? '—'));
</script>

<div class="pago-hecho" class:cancelado={!!pago.cancelado_at}>
  <Icono nombre={pago.metodo === 'efectivo' ? 'billete' : pago.metodo === 'tarjeta' ? 'tarjeta' : 'banco'} tamano={16} />
  <span class="t">
    <b>{NOMBRE_METODO[pago.metodo]}</b>
    <span>
      {#if pago.cancelado_at}
        Cancelado · «{pago.cancelado_motivo}» · {nombre(pago.cancelado_por)}
      {:else}
        {pago.cobrado_por !== null ? nombre(pago.cobrado_por) : 'En línea'} · {enZona(pago.created_at, zona).hora}{pago.propina
          ? ` · propina ${dinero(pago.propina)}`
          : ''}
      {/if}
    </span>
  </span>
  <span class="m">{dinero(pago.monto)}</span>
  {#if alCancelar}<button type="button" class="boton-chico" onclick={alCancelar}>Cancelar</button>{/if}
</div>
