<!--
  Un descuento (maqueta Cancelaciones y descuentos, estado «Regalar la jamaica», y «Descuento a la
  cuenta» de la hoja de cobro): en % o en pesos, a un renglón o a toda la cuenta. Regalar es 100 %.
  Uno nuevo reemplaza al anterior. No tiene tope, pero nada deja el total abajo de lo pagado. Un %
  a toda la cuenta alcanza lo que se agregue después; uno en pesos se queda fijo (decidido el 18 de
  octubre de 2026). Quitarlo no pide PIN: está en la hoja del renglón y en «⋯».
  Si lo de ahora es el premio de la tarjeta de lealtad (el renglón del producto al 100 % o los pesos de la cuenta, con el
  motivo «Premio de la tarjeta»), avisa antes que el descuento nuevo lo reemplaza y el premio regresa a la tarjeta
  (Diccionario de la tarjeta, punto 6; Postgres lo regresa solo).
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import CajaError from '../../diseno/CajaError.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { leerMonto } from '../../lib/caja';
  import Icono from '../../diseno/Icono.svelte';
  import { dinero } from '../../lib/formato';
  import { MOTIVO_PREMIO } from '../../lib/lealtad';
  import { siSeDescuenta, textoDescuento, type Autoriza, type Renglon, type TipoDescuento, type Venta } from '../../lib/pos';
  import HojaPedir from './HojaPedir.svelte';

  let {
    cliente,
    venta,
    titulo,
    renglon = null,
    autorizan,
    zona,
    alCerrar,
    alListo,
  }: {
    cliente: SupabaseClient;
    venta: Venta;
    titulo: string; // la mesa o el cliente
    renglon?: Renglon | null; // null: a toda la cuenta
    autorizan: Autoriza[] | null;
    zona: string;
    alCerrar: () => void;
    alListo: (globo: string) => void;
  } = $props();

  // Lo de ahora, si ya hay uno: se propone para cambiarlo.
  // svelte-ignore state_referenced_locally
  const ahora = renglon
    ? renglon.descuento_tipo && { tipo: renglon.descuento_tipo, valor: renglon.descuento_valor! }
    : venta.descuento_tipo && { tipo: venta.descuento_tipo, valor: venta.descuento_valor! };

  // svelte-ignore state_referenced_locally
  const esPremio = (renglon ? renglon.descuento_motivo : venta.descuento_motivo) === MOTIVO_PREMIO && !!ahora;

  let tipo = $state<TipoDescuento>(ahora ? ahora.tipo : 'porcentaje');
  let valorTexto = $state(ahora ? String(ahora.valor) : '');
  let motivo = $state('');

  const pct = $derived(tipo === 'porcentaje');
  const valor = $derived(leerMonto(valorTexto.replace('%', '')));
  const valido = $derived(valor !== null && valor > 0 && (!pct || valor <= 100));
  const si = $derived(valido ? siSeDescuenta(venta, renglon, tipo, valor!) : null);
  const pasa = $derived(!!si && !pct && valor! > si.base);
  const cabe = $derived(!si || si.queda >= venta.pagado);
  const pedido = $derived(
    si && !pasa && cabe && motivo.trim()
      ? {
          funcion: 'descontar' as const,
          datos: { p_venta_id: venta.id, p_renglon_id: renglon?.id ?? null, p_tipo: tipo, p_valor: valor!, p_motivo: motivo.trim() },
        }
      : null,
  );
  const bruto = $derived(renglon ? renglon.importe + renglon.descuento : 0);
</script>

<HojaPedir
  {cliente}
  titulo={renglon ? `Descuento · ${renglon.nombre}` : 'Descuento a la cuenta'}
  sub={renglon ? `${renglon.cantidad} ${renglon.nombre} · ${dinero(bruto)}` : `${titulo} · subtotal ${dinero(venta.subtotal)}`}
  {pedido}
  resumen="{renglon ? `Descuento a ${renglon.nombre}` : 'Descuento a la cuenta'} · {valido ? textoDescuento(tipo, valor!) : ''} · «{motivo.trim()}»"
  texto="Aplicar descuento"
  {autorizan}
  {zona}
  {alCerrar}
  alListo={(autorizo) => alListo(autorizo ? `Descuento aplicado · autorizó ${autorizo}` : 'Descuento aplicado')}
>
  <Selector
    etiqueta="En % o en pesos"
    lleno
    alto={30}
    opciones={[
      { valor: 'porcentaje', texto: 'En %' },
      { valor: 'pesos', texto: 'En pesos' },
    ]}
    elegida={tipo}
    alElegir={(t) => ((tipo = t), (valorTexto = ''))}
  />
  <div class="campo">
    <label class="etq" for="valor-descuento">{pct ? 'Porcentaje' : 'Pesos'}</label>
    <input id="valor-descuento" inputmode="decimal" autocomplete="off" placeholder={pct ? 'Ej. 10' : 'Ej. $50'} bind:value={valorTexto} />
    {#if pct}
      <div class="chips-cobro" role="group" aria-label="Cuánto">
        {#each [10, 15, 20, 50, 100] as x (x)}
          <button type="button" class="chip-cat" aria-pressed={valor === x} onclick={() => (valorTexto = String(x))}>
            {x === 100 ? 'Regalar · 100 %' : `${x} %`}
          </button>
        {/each}
      </div>
    {/if}
    {#if valorTexto.trim() && !valido}
      <p class="pista fuerte">{pct ? 'Va de 1 a 100 %.' : 'Escribe cuántos pesos.'}</p>
    {:else if pasa && si}
      <p class="pista fuerte">No puede pasar de {dinero(si.base)}.</p>
    {/if}
  </div>
  <div class="campo">
    <label class="etq" for="motivo-descuento">Motivo</label>
    <input id="motivo-descuento" placeholder="Ej. «Cliente de siempre»" autocomplete="off" bind:value={motivo} />
  </div>
  <div class="resumen">
    <div class="resumen-fila desc"><span>Descuento</span><span>−{dinero(si && !pasa ? si.descuento : 0)}</span></div>
    <div class="resumen-fila fuerte"><span>La cuenta queda en</span><span>{dinero(si && !pasa ? si.queda : venta.total)}</span></div>
  </div>
  {#if !cabe}<CajaError mensaje="Ya se pagaron {dinero(venta.pagado)}. Cancela antes un pago." />{/if}
  {#if esPremio}
    <p class="aviso-premio" role="note">
      <Icono nombre="alerta" tamano={16} /><span
        ><b>{renglon ? `${renglon.nombre} es el premio de la tarjeta.` : `Esta cuenta lleva el premio de la tarjeta (−${dinero(venta.descuento)}).`}</b>
        El descuento nuevo lo reemplaza y el premio regresa a la tarjeta de lealtad.</span
      >
    </p>
  {:else if ahora}<p class="pista">Reemplaza al de ahora ({textoDescuento(ahora.tipo, ahora.valor)}).</p>{/if}
</HojaPedir>

<style>
  .pista.fuerte {
    color: var(--texto);
  }

  /* Como las notas ámbar del cobro (cobro/terminal.css, .t-nota.ambar), que aquí no siempre se cargan. */
  .aviso-premio {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin: 0;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--amarillo-fondo);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
    text-align: left;
  }

  .aviso-premio :global(svg) {
    flex: none;
    margin-top: 2px;
    color: var(--amarillo-texto);
  }

  .aviso-premio b {
    color: var(--texto);
    font-weight: 700;
  }
</style>
