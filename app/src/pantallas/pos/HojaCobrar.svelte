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

  Con la terminal conectada (libreta 5, «La terminal conectada»; maqueta 8aJ1RUKVd2xA5kgawVpDkQ v2, «Celular · Cobrar»):
  con Tarjeta y una Point, el botón grande es «Mandar a la terminal · $489.50» y abajo, chico, «La cobré a mano». Al
  mandarlo, la hoja espera («Esperando en la terminal», los segundos, «Revisar» y «Cancelar cobro»); si Mercado Pago no
  sabe, «Revisa la terminal» con «Sí se pagó / No se pagó»; si no se cobró, la nota roja con el porqué y «Reintentar».

  Con la tarjeta de lealtad (encuesta del 23 nov 2026, planes/trabajo/tarjeta-lealtad/construir.md): la misma fila
  «Tarjeta de lealtad» del cobro a lo ancho (cobro/Lealtad.svelte), abajo de los botones del descuento, para que la cuenta
  que Pepe cobra en la mesa sume y canjee ahí mismo. Sale sola si la sucursal la tiene prendida.
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
  import type { VigiaTerminal } from '../../lib/terminal.svelte';
  import { Cobro, type ElegidaPropina } from './cobro/cobro.svelte';
  import Encima from './cobro/Encima.svelte';
  import Lealtad from './cobro/Lealtad.svelte';
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
    terminal = null,
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
    terminal?: VigiaTerminal | null;
    alCerrar: () => void;
    alAviso: (texto: string) => void;
    alListo: () => void;
  } = $props();

  const c = new Cobro(() => ({ cliente, restauranteId, venta, cuenta, turnoId, nombres, autorizan, zona, renglones, terminal, alAviso }));
  onDestroy(() => c.destruir());

  const PROPINAS: { valor: ElegidaPropina; texto: string }[] = [
    { valor: 'no', texto: 'Sin propina' },
    { valor: '10', texto: '10 %' },
    { valor: '15', texto: '15 %' },
    { valor: 'otra', texto: 'Otra' },
  ];

  // Lo que dice cada motivo de «No se cobró» («cancelada» es la de Pepe y regresa a elegir, sin nota).
  const MOTIVOS: Record<string, string> = {
    rechazada: 'La tarjeta fue rechazada. Pide otra tarjeta o elige otra forma de pago.',
    vencida: 'Pasaron 5 minutos y nadie pagó en la terminal.',
    cancelada_terminal: 'Se canceló en la terminal.',
    sin_conexion: 'No se pudo mandar a la terminal. Cóbrala a mano.',
  };
</script>

{#snippet senal(ambar: boolean)}
  <div class="t-senal" class:ambar aria-hidden="true">
    <span class="t-onda"></span><span class="t-onda dos"></span>
    <span class="t-centro"><Icono nombre={ambar ? 'alerta' : 'tarjeta'} tamano={22} /></span>
  </div>
{/snippet}

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

    {#if c.fase === 'esperando' && c.cobroT}
      {@const t = c.cobroT}
      <div class="t-espera-cel t-entra">
        <div class="t-espera">
          {@render senal(false)}
          <b class="t-espera-tit">Esperando en la terminal</b>
          <span class="t-espera-monto">{dinero(t.monto)}</span>
          <span class="t-espera-linea">{c.vigia?.point ?? 'Point'}{t.propina > 0 ? ` · propina ${dinero(t.propina)}` : ''}</span>
          <span class="t-seg">{c.segundos} s</span>
        </div>
        {#if c.aviso5}
          <p class="t-aviso5" role="status">
            <Icono nombre="alerta" tamano={16} /><span><b>La terminal no lo ha recibido:</b> abre «Cobros vinculados» en la Point.</span>
          </p>
        {/if}
        {#if c.error}<CajaError tipo={c.error.startsWith('Sin conexión') ? 'sinred' : 'alerta'} mensaje={c.error} />{/if}
        <p class="t-pista">Puedes cerrar esto y atender otra mesa: la cuenta se cierra sola cuando paguen.</p>
        <div class="t-par">
          <button type="button" class="cel-boton contorno" class:t-girando={c.revisando} disabled={c.revisando} onclick={() => c.revisar()}>
            <Icono nombre="actualizar" tamano={16} />Revisar
          </button>
          <button type="button" class="cel-boton contorno t-rojo" disabled={c.ocupado} onclick={() => c.cancelarTerminal()}>Cancelar cobro</button>
        </div>
      </div>
    {:else if c.fase === 'revisa' && c.cobroT}
      {@const t = c.cobroT}
      <div class="t-espera-cel t-entra">
        <div class="t-espera">
          {@render senal(true)}
          <b class="t-espera-tit">Revisa la terminal</b>
          <span class="t-espera-monto">{dinero(t.monto)}</span>
          <span class="t-espera-linea">Mercado Pago no sabe si se pagó. Mira la Point: ¿salió el comprobante?</span>
        </div>
        {#if c.error}<CajaError mensaje={c.error} />{/if}
        <p class="t-pista">Lo que elijas queda en la bitácora, y el corte lo compara con el cierre de la terminal.</p>
        <div class="t-par">
          <button type="button" class="cel-boton contorno t-rojo" disabled={c.ocupado} onclick={() => c.confirmar(false)}>No se pagó</button>
          <button type="button" class="cel-boton" disabled={c.ocupado} onclick={() => c.confirmar(true)}>Sí se pagó</button>
        </div>
      </div>
    {:else}
    {#if c.notaTerminal}
      {@const nota = c.notaTerminal}
      {#if nota.tipo === 'no-cobro'}
        <div class="t-nota roja t-entra" role="alert">
          <Icono nombre="alerta" tamano={16} /><span><b>No se cobró.</b> {MOTIVOS[nota.motivo] ?? ''}</span>
        </div>
      {:else if nota.tipo === 'ocupada'}
        <div class="t-nota ambar t-entra" role="alert">
          <Icono nombre="alerta" tamano={16} /><span><b>La terminal está atendiendo otro cobro.</b> Cuando termine, vuelve a mandarlo.</span>
        </div>
      {:else}
        <div class="t-nota ambar t-entra" role="alert">
          <Icono nombre="alerta" tamano={16} /><span><b>La terminal tiene algo pendiente: revisa el papel.</b> Lo pendiente sale solo cuando la Point tiene papel y está en «Cobros vinculados».</span>
        </div>
      {/if}
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
      {#key venta.id}
        <Lealtad {cliente} {restauranteId} ventaId={venta.id} total={c.resumen.total} />
      {/key}
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

    {#if c.conTerminal && !c.enCero}
      <div class="t-pie-cel">
        <button type="button" class="cel-boton fijo" disabled={!c.listoTerminal} onclick={() => c.mandar()}>
          {c.notaTerminal ? 'Reintentar' : 'Mandar a la terminal'}{c.cobrarEnBoton !== null ? ` · ${dinero(c.cobrarEnBoton)}` : ''}
        </button>
        {#if c.poco}<p class="t-razon">Menos de $5.00 no se puede mandar a la terminal</p>{/if}
        <button type="button" class="boton-chico t-a-mano" disabled={!c.listo} onclick={() => c.anotar()}>La cobré a mano</button>
      </div>
    {:else}
      <button type="button" class="cel-boton fijo" disabled={!c.listo} onclick={() => c.anotar()}>
        {#if c.enCero}
          Cerrar la cuenta
        {:else}
          Anotar pago{c.cobrarEnBoton !== null ? ` · ${dinero(c.cobrarEnBoton)}` : ''}
        {/if}
      </button>
    {/if}
    {/if}
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
