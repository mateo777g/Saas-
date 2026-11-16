<!--
  Cancelar un pago mal anotado (maqueta Cancelaciones y descuentos, estado «Cancelar un pago»): con
  motivo. Si la cuenta ya se había cerrado, se reabre con el mismo folio y sale en Por cobrar como
  «Reabierta», sin volver a ocupar su mesa; ahí se anota el pago correcto. La propina de ese pago
  deja de contar para quien abrió la cuenta, y la hoja lo avisa antes. Solo se cancelan pagos del
  turno abierto.

  Con la terminal conectada (16 nov 2026, libreta 5, «La terminal conectada»): si el pago se cobró en la Point
  (cobros_terminal.pago_id), cancelarlo devuelve el dinero por el Worker (lib/pos.ts, «devolver_pago»), con el mismo
  PIN de siempre, y solo se cancela si Mercado Pago dice que sí lo devolvió. Mientras se sabe de dónde vino, el botón
  espera.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount } from 'svelte';
  import { NOMBRE_METODO, type Pago } from '../../lib/caja';
  import { dinero } from '../../lib/formato';
  import type { Autoriza } from '../../lib/pos';
  import HojaPedir from './HojaPedir.svelte';

  let {
    cliente,
    pago,
    titulo,
    folio,
    cerrada,
    cobro,
    abrio,
    autorizan,
    zona,
    alCerrar,
    alListo,
  }: {
    cliente: SupabaseClient;
    pago: Pago;
    titulo: string;
    folio: number | null;
    cerrada: boolean;
    cobro: string; // quién anotó el pago
    abrio: string | null; // de quién es la propina
    autorizan: Autoriza[] | null;
    zona: string;
    alCerrar: () => void;
    alListo: (globo: string, reabierta: boolean) => void;
  } = $props();

  let motivo = $state('');
  // ¿Se cobró en la terminal? null = todavía no se sabe. Si no se pudo leer, se cancela como siempre y Postgres
  // rechaza el de la terminal con su mensaje.
  // svelte-ignore state_referenced_locally
  let deTerminal = $state<boolean | null>(pago.metodo === 'tarjeta' ? null : false); // la hoja es de un solo pago

  onMount(() => {
    if (deTerminal !== null) return;
    cliente
      .from('cobros_terminal')
      .select('id')
      .eq('pago_id', pago.id)
      .maybeSingle()
      .then(({ data, error }) => {
        if (error) console.error('[pos] no se pudo saber si el pago se cobró en la terminal:', error);
        deTerminal = !!data;
      });
  });

  const pedido = $derived(
    motivo.trim() && deTerminal !== null
      ? { funcion: deTerminal ? ('devolver_pago' as const) : ('cancelar_pago' as const), datos: { p_pago_id: pago.id, p_motivo: motivo.trim() } }
      : null,
  );
</script>

<HojaPedir
  {cliente}
  titulo="Cancelar pago"
  sub="{NOMBRE_METODO[pago.metodo]} {dinero(pago.monto)}{pago.propina ? ` · propina ${dinero(pago.propina)}` : ''} · {cobro}{folio !== null ? ` · folio ${folio}` : ''}"
  {pedido}
  resumen="Cancelar el pago · «{motivo.trim()}»"
  texto="Cancelar pago"
  {autorizan}
  {zona}
  {alCerrar}
  alListo={(_, reabierta) => {
    const que = deTerminal ? 'Pago devuelto' : 'Pago cancelado';
    alListo(reabierta ? `${que} · folio ${folio} reabierto` : que, reabierta);
  }}
>
  <p class="confirmar-texto">
    {cerrada
      ? `«${titulo}» se reabre con el folio ${folio} y queda en Por cobrar con ${dinero(pago.monto)} por pagar.`
      : `A «${titulo}» le vuelven a faltar ${dinero(pago.monto)}.`}{pago.propina && abrio
      ? ` La propina de ${dinero(pago.propina)} deja de contar para ${abrio}.`
      : ''}{deTerminal ? ' Se cobró en la terminal: el dinero regresa a la tarjeta del cliente desde tu Mercado Pago.' : ''}
  </p>
  <div class="campo">
    <label class="etq" for="motivo-pago">Motivo</label>
    <input id="motivo-pago" placeholder="Ej. «Era efectivo, no tarjeta»" autocomplete="off" bind:value={motivo} />
  </div>
</HojaPedir>
