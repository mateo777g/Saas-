<!--
  La hoja de cobro (parte 4b; maqueta La caja, estados «Cobrar», «Entre 3» y «Cuenta cerrada»):
  la misma en la caja y en el celular del mesero. El punto de venta nunca cobra: aquí se anota cómo
  pagó el cliente. Lo de adentro (los números de resumen_cuenta, la clave del pago, anotar, quitar el
  descuento) vive en pos/cobro/cobro.svelte.ts desde la adaptabilidad (3b), para que la tarjeta a lo
  ancho cobre igual; esta hoja solo lo pinta. Cuando los pagos cubren el total, la cuenta se cierra
  sola y la hoja enseña el folio y el cambio. Si resumen_cuenta falla, la hoja lo dice, no deja
  anotar con números viejos y vuelve a pedirlo al regresar el internet o con «Intentar de nuevo».

  Con la parte 4c (maqueta Cancelaciones y descuentos, estado «Cobrar con descuento»): «Descuento a
  la cuenta» y «Quitar descuento», y el resumen con el subtotal y el descuento con su motivo. Un pago
  del turno abierto se cancela aquí con su motivo; el cancelado se queda en la lista, tachado. Si
  quien cobra no es de la caja ni gerente, los dos piden el PIN de otra persona.

  Con la adaptabilidad (encuesta 17; encuesta 8 de cobro-caja.md): en efectivo, «Exacto» y hasta tres
  billetes que alcanzan, en chips como los de la propina; un toque llena «Con cuánto paga».
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onDestroy } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import { NOMBRE_METODO } from '../../lib/caja';
  import { dinero } from '../../lib/formato';
  import type { Autoriza, Renglon, TipoCuenta, Venta } from '../../lib/pos';
  import { Cobro, type ElegidaPropina } from './cobro/cobro.svelte';
  import Encima from './cobro/Encima.svelte';
  import Hoja from './Hoja.svelte';
  import PagoHecho from './PagoHecho.svelte';

  let {
    cliente,
    restauranteId,
    venta,
    cuenta,
    turnoId,
    nombres,
    autorizan,
    zona,
    renglones,
    alCerrar,
    alAviso,
    alListo,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    venta: { id: number; titulo: string; tipo: TipoCuenta; abrio: string | null };
    cuenta: Venta | null; // la cuenta según el tiempo real: si cambia su total o lo pagado, la hoja se vuelve a pedir
    turnoId: number | null; // el turno abierto; sin turno no se anotan pagos
    nombres: Map<number, string>;
    autorizan: Autoriza[] | null; // quién pone su PIN para descontar o cancelar un pago; null: quien cobra es de la caja o gerente
    zona: string;
    renglones?: Renglon[];
    alCerrar: () => void;
    alAviso: (texto: string) => void;
    alListo: () => void;
  } = $props();

  const c = new Cobro(() => ({ cliente, restauranteId, venta, cuenta, turnoId, nombres, autorizan, zona, renglones, alAviso }));
  onDestroy(() => c.destruir());

  const PROPINAS: { valor: ElegidaPropina; texto: string }[] = [
    { valor: 'no', texto: 'Sin propina' },
    { valor: '10', texto: '10 %' },
    { valor: '15', texto: '15 %' },
    { valor: 'otra', texto: 'Otra' },
  ];
</script>

{#if c.encima}
  <Encima cobro={c} />
{:else if c.cerrada}
  {@const cerrada = c.cerrada}
  <Hoja titulo="{venta.titulo} cerrada" cabeza={false} alCerrar={alListo}>
    <div class="cerrada">
      <span class="sello"><Icono nombre="check" tamano={24} /></span>
      <h3>{venta.titulo} cerrada</h3>
      <span class="folio">{cerrada.folio !== null ? `Folio ${cerrada.folio} · ` : ''}{dinero(cerrada.total)}</span>
      {#if cerrada.cambio > 0}
        <div class="cambio-grande"><span>Cambio</span><b>{dinero(cerrada.cambio)}</b></div>
      {/if}
      <p class="pista">
        {cerrada.reabierta
          ? 'Ya no sale en Por cobrar.'
          : venta.tipo === 'mesa'
            ? 'La mesa quedó libre.'
            : 'El pedido ya no sale en Por cobrar.'}
      </p>
    </div>
    <button type="button" class="cel-boton fijo" onclick={alListo}>Listo</button>
  </Hoja>
{:else}
  <Hoja
    titulo="Cobrar {venta.titulo}"
    sub="{cuenta?.folio != null ? `Folio ${cuenta.folio} · reabierta · ` : ''}{venta.abrio ? `Abrió ${venta.abrio} · la propina es suya` : ''}"
    {alCerrar}
  >
    {#if !c.turnoAbierto}
      <CajaError mensaje="La caja no está abierta. Pídele a quien está en caja que la abra para anotar pagos." />
    {/if}
    {#if c.yaNoAbierta}
      <CajaError tipo="info" mensaje="Esta cuenta ya no está abierta: se cobró o se juntó en otro aparato." />
    {/if}

    {#if c.resumen}
      <div class="resumen">
        {#if c.descuento && cuenta}
          <div class="resumen-fila"><span>Subtotal</span><span>{dinero(cuenta.subtotal)}</span></div>
          <div class="resumen-fila desc">
            <span>Descuento {c.descuento.texto} <small>«{c.descuento.motivo}»</small></span><span>−{dinero(cuenta.descuento)}</span>
          </div>
        {/if}
        <div class="resumen-fila"><span>Total</span><span>{dinero(c.resumen.total)}</span></div>
        {#if c.resumen.pagado > 0}
          <div class="resumen-fila"><span>Pagado</span><span>{dinero(c.resumen.pagado)}</span></div>
        {/if}
        <div class="resumen-fila fuerte"><span>Falta</span><span>{dinero(c.resumen.falta)}</span></div>
      </div>
    {:else if !c.errorResumen}
      <span class="pista">Leyendo la cuenta…</span>
    {/if}
    {#if c.errorResumen}
      <CajaError tipo={c.errorResumen.sinRed ? 'sinred' : 'alerta'} mensaje={c.errorResumen.texto} />
      {#if !c.resumen}
        <button type="button" class="cel-boton contorno fijo" onclick={() => c.reintentar()}>Intentar de nuevo</button>
      {/if}
    {/if}

    {#if c.resumen && c.resumen.estado === 'abierta' && cuenta}
      <div class="botones-fila">
        <button type="button" class="boton-chico" disabled={c.ocupado} onclick={() => c.abrirDescuento()}>
          <Icono nombre="porcentaje" tamano={14} />{c.descuento ? 'Cambiar descuento' : 'Descuento a la cuenta'}
        </button>
        {#if c.descuento}
          <button type="button" class="boton-chico" disabled={c.ocupado} onclick={() => c.quitarDescuento()}>
            <Icono nombre="regresar" tamano={14} />Quitar descuento
          </button>
        {/if}
      </div>
    {/if}

    {#if c.pagos.length}
      <div class="grupo-op">
        {#each c.pagos as p (p.id)}
          <PagoHecho pago={p} {nombres} {zona} alCancelar={c.seCancela(p) ? () => c.abrirCancelarPago(p) : undefined} />
        {/each}
      </div>
    {/if}

    {#if c.enCero}
      <p class="pista">Esta cuenta es de {dinero(0)}: se cierra sin anotar ningún pago.</p>
    {:else if c.resumen && !c.yaNoAbierta}
      {@const resumen = c.resumen}
      <Selector
        etiqueta="Cómo pagó"
        lleno
        alto={30}
        opciones={(['efectivo', 'tarjeta', 'transferencia'] as const).map((m) => ({ valor: m, texto: NOMBRE_METODO[m] }))}
        elegida={c.metodo}
        alElegir={(m) => c.elegirMetodo(m)}
      />

      <div class="campo">
        <label class="etq" for="cobro-monto">Paga</label>
        <input
          id="cobro-monto"
          inputmode="decimal"
          autocomplete="off"
          value={c.montoEnCampo}
          oninput={(e) => c.escribirMontoHoja(e.currentTarget.value)}
        />
        <div class="chips-cobro" role="group" aria-label="Dividir">
          {#each [1, 2, 3, 4] as n (n)}
            <button type="button" class="chip-cat" aria-pressed={c.montoAuto && c.partes === n} onclick={() => c.elegirPartes(n)}>
              {n === 1 ? 'Todo' : `Entre ${n}`}
            </button>
          {/each}
        </div>
        {#if c.montoAuto && c.partes > 1}
          <p class="pista">
            Pago {c.hechas + 1} de {c.partes}.{resumen.partes.length > 1 ? ` Los demás: ${resumen.partes.slice(1).map(dinero).join(', ')}.` : ''}
          </p>
        {/if}
        {#if c.montoMal}
          <p class="pista fuerte">
            {c.montoPedido === null ? 'Escribe el monto en pesos, como «150» o «148.50».' : `No puede pasar de lo que falta (${dinero(resumen.falta)}).`}
          </p>
        {/if}
      </div>

      <div class="campo">
        <span class="etq">Propina</span>
        <div class="chips-cobro" role="group" aria-label="Propina">
          {#each PROPINAS as o (o.valor)}
            <button type="button" class="chip-cat" aria-pressed={c.propina === o.valor} onclick={() => c.elegirPropina(o.valor)}>
              {o.texto}{#if o.valor === '10'}<span class="mono">{dinero(resumen.propina_10)}</span>{:else if o.valor === '15'}<span class="mono">{dinero(resumen.propina_15)}</span>{/if}
            </button>
          {/each}
        </div>
        {#if c.propina === 'otra'}
          <input
            inputmode="decimal"
            autocomplete="off"
            placeholder="$0.00"
            aria-label="Otra cantidad"
            value={c.otraTexto}
            oninput={(e) => c.escribirOtra(e.currentTarget.value)}
          />
          {#if c.propinaPedida === 'mal'}<p class="pista fuerte">Escribe la propina en pesos, como «20».</p>{/if}
        {/if}
      </div>

      {#if c.metodo === 'efectivo'}
        <div class="campo">
          <label class="etq" for="cobro-recibido">Con cuánto paga</label>
          {#if resumen.cabe && c.propinaPedida !== 'mal'}
            <!-- Los montos sugeridos (encuesta 17): un toque llena el campo; otro monto se sigue escribiendo. -->
            <div class="chips-cobro" role="group" aria-label="Montos sugeridos">
              <button type="button" class="chip-cat" aria-pressed={c.recibido.tipo === 'exacto'} onclick={() => c.elegirRecibido({ tipo: 'exacto' })}>
                Exacto<span class="mono">{dinero(resumen.cobrar)}</span>
              </button>
              {#each c.sugeridos as b (b)}
                <button
                  type="button"
                  class="chip-cat"
                  aria-pressed={c.recibido.tipo === 'billete' && c.recibido.n === b}
                  onclick={() => c.elegirRecibido({ tipo: 'billete', n: b })}
                >
                  {dinero(b)}
                </button>
              {/each}
            </div>
          {/if}
          <input
            id="cobro-recibido"
            inputmode="decimal"
            autocomplete="off"
            placeholder="Ej. $500.00"
            value={c.recibidoEnCampo}
            oninput={(e) => c.elegirRecibido({ tipo: 'texto', texto: e.currentTarget.value })}
          />
        </div>
        {#if c.cambioVisto !== null && c.cambioVisto >= 0}
          <div class="dato-grande"><b>Cambio</b><span>{dinero(c.cambioVisto)}</span></div>
        {:else if c.recibido.tipo === 'texto' && c.recibido.texto.trim() && resumen.cabe}
          <p class="pista fuerte">
            {c.recibidoPedido === null ? 'Escribe el billete en pesos, como «500».' : `No alcanza: son ${dinero(resumen.cobrar)} con la propina.`}
          </p>
        {/if}
      {:else}
        <div class="dato-grande">
          <b>{c.metodo === 'tarjeta' ? 'Cobra en la terminal' : 'Debe llegar'}</b>
          <span>{dinero(resumen.cabe ? resumen.cobrar : 0)}</span>
        </div>
        <div class="campo">
          <label class="etq" for="cobro-ref">Referencia · opcional</label>
          <input
            id="cobro-ref"
            autocomplete="off"
            placeholder={c.metodo === 'tarjeta' ? 'Últimos dígitos del voucher' : 'Folio de la transferencia'}
            value={c.referencia}
            oninput={(e) => c.escribirReferencia(e.currentTarget.value)}
          />
        </div>
      {/if}
    {/if}

    {#if c.error}<CajaError tipo={c.error.startsWith('Sin conexión') ? 'sinred' : 'alerta'} mensaje={c.error} />{/if}

    <button type="button" class="cel-boton fijo" disabled={!c.listo} onclick={() => c.anotar()}>
      {#if c.enCero}
        Cerrar la cuenta
      {:else}
        Anotar pago{c.cobrarEnBoton !== null ? ` · ${dinero(c.cobrarEnBoton)}` : ''}
      {/if}
    </button>
  </Hoja>
{/if}

<style>
  .cel-boton.fijo {
    flex: none;
  }

  .pista.fuerte {
    color: var(--texto);
  }
</style>
