<!--
  Cancelar lo mandado (maqueta Cancelaciones y descuentos, estados «Cancelar 1 de 2» y «Ya se
  pagaron»): cuántos (si son varios), el motivo, que se escribe a mano, y en cuánto queda la cuenta.
  Si ya hay pagos, nada puede dejar el total abajo de lo pagado: la hoja lo dice y no deja seguir.
  Cancelar 1 de 3 baja el renglón a 2 y crea otro con 1, ya cancelado (cancelar_renglon).
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { dinero } from '../../lib/formato';
  import { siSeCancela, type Autoriza, type Renglon, type Venta } from '../../lib/pos';
  import HojaPedir from './HojaPedir.svelte';

  let {
    cliente,
    venta,
    renglon,
    area,
    autorizan,
    zona,
    alCerrar,
    alListo,
  }: {
    cliente: SupabaseClient;
    venta: Venta;
    renglon: Renglon;
    area: string | null; // a qué área se mandó; null: lo sirve el mesero
    autorizan: Autoriza[] | null;
    zona: string;
    alCerrar: () => void;
    alListo: (globo: string) => void;
  } = $props();

  let cuantos = $state(1);
  let motivo = $state('');

  const r = $derived(renglon);
  const detalle = $derived(r.opciones.map((o) => o.opcion).join(' · '));
  const si = $derived(siSeCancela(venta, r, cuantos));
  const cabe = $derived(si.queda >= venta.pagado);
  const pedido = $derived(
    cabe && motivo.trim()
      ? { funcion: 'cancelar_renglon' as const, datos: { p_renglon_id: r.id, p_cantidad: cuantos, p_motivo: motivo.trim() } }
      : null,
  );
</script>

<HojaPedir
  {cliente}
  titulo="Cancelar {r.nombre}"
  sub="{detalle ? `${detalle} · ` : ''}{r.cantidad} mandado{r.cantidad > 1 ? 's' : ''}{area ? ` a ${area.toLowerCase()}` : ''}"
  {pedido}
  resumen="Cancelar {cuantos} {r.nombre} · «{motivo.trim()}»"
  texto="Cancelar {cuantos}"
  {autorizan}
  {zona}
  {alCerrar}
  alListo={(autorizo) => alListo(autorizo ? `Cancelado · autorizó ${autorizo}` : 'Cancelado')}
>
  {#if r.cantidad > 1}
    <div class="campo">
      <span class="etq">Cuántos</span>
      <div class="fila-cant">
        <span class="paso">
          <button type="button" aria-label="Uno menos" disabled={cuantos <= 1} onclick={() => (cuantos -= 1)}>
            <Icono nombre="menos" tamano={16} />
          </button>
          <span>{cuantos}</span>
          <button type="button" aria-label="Uno más" disabled={cuantos >= r.cantidad} onclick={() => (cuantos += 1)}>
            <Icono nombre="mas" tamano={16} />
          </button>
        </span>
        <span class="pista">de {r.cantidad}</span>
      </div>
    </div>
  {/if}
  <div class="campo">
    <label class="etq" for="motivo-cancelar">Motivo</label>
    <input id="motivo-cancelar" placeholder="Ej. «Eran de suadero»" autocomplete="off" bind:value={motivo} />
  </div>
  <div class="resumen">
    <div class="resumen-fila"><span>Se cancela</span><span>−{dinero(si.menos)}</span></div>
    <div class="resumen-fila fuerte"><span>La cuenta queda en</span><span>{dinero(si.queda)}</span></div>
  </div>
  {#if !cabe}<CajaError mensaje="Ya se pagaron {dinero(venta.pagado)}. Cancela antes un pago." />{/if}
</HojaPedir>
