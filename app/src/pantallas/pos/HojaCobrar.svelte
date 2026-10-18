<!--
  La hoja de cobro (parte 4b; maqueta La caja, estados «Cobrar», «Entre 3» y «Cuenta cerrada»):
  la misma en la caja y en el celular del mesero. El punto de venta nunca cobra: aquí se anota cómo
  pagó el cliente. Los números (lo que falta, las partes, la propina, lo que se cobra en la
  terminal y el cambio) los da resumen_cuenta mientras se escribe, y cobrar los vuelve a calcular
  al anotar. La clave del pago cambia con cada cambio en la hoja: pulsar dos veces lo mismo, o
  volver a pulsar tras perder el internet, no lo anota dos veces. Cuando los pagos cubren el
  total, la cuenta se cierra sola y la hoja enseña el folio y el cambio. Si resumen_cuenta falla,
  la hoja lo dice, no deja anotar con números viejos y vuelve a pedirlo al regresar el internet o
  con «Intentar de nuevo».
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import {
    cobrar,
    leerMonto,
    leerPagos,
    NOMBRE_METODO,
    resumenCuenta,
    type Metodo,
    type Pago,
    type Propina,
    type Resumen,
  } from '../../lib/caja';
  import { dinero } from '../../lib/formato';
  import { FalloPos } from '../../lib/pos';
  import Hoja from './Hoja.svelte';

  let {
    cliente,
    restauranteId,
    venta,
    pagado,
    turnoAbierto,
    nombres,
    alCerrar,
    alAviso,
    alListo,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    venta: { id: number; titulo: string; tipo: 'mesa' | 'para_llevar' | 'domicilio'; abrio: string | null };
    pagado: number | null; // lo pagado según el tiempo real: si cambia, la hoja se vuelve a pedir
    turnoAbierto: boolean;
    nombres: Map<number, string>;
    alCerrar: () => void;
    alAviso: (texto: string) => void;
    alListo: () => void;
  } = $props();

  type ElegidaPropina = 'no' | '10' | '15' | 'otra';

  let metodo = $state<Metodo>('efectivo');
  let partes = $state(1);
  let hechas = $state(0);
  let montoAuto = $state(true);
  let montoTexto = $state('');
  let propina = $state<ElegidaPropina>('no');
  let otraTexto = $state('');
  let recibidoTexto = $state('');
  let referencia = $state('');
  let clave = $state(crypto.randomUUID());

  let resumen = $state<Resumen | null>(null);
  let pagos = $state<Pago[]>([]);
  let error = $state<string | null>(null);
  let errorResumen = $state<{ texto: string; sinRed: boolean } | null>(null);
  let reintento = $state(0);
  let ocupado = $state(false);
  let cerrada = $state<{ folio: number | null; total: number; cambio: number } | null>(null);

  // Lo que se le pide a Postgres con lo escrito.
  const propinaPedida = $derived.by<Propina | 'mal'>(() => {
    if (propina === '10') return { porcentaje: 10 };
    if (propina === '15') return { porcentaje: 15 };
    if (propina === 'otra') {
      if (otraTexto.trim() === '') return null;
      const n = leerMonto(otraTexto);
      return n === null ? 'mal' : { cantidad: n };
    }
    return null;
  });
  const montoPedido = $derived(montoAuto ? null : leerMonto(montoTexto));
  const recibidoPedido = $derived(metodo === 'efectivo' && recibidoTexto.trim() ? leerMonto(recibidoTexto) : null);

  // Un cambio en la hoja es otro pago: otra clave.
  function cambio() {
    clave = crypto.randomUUID();
    error = null;
  }

  let pedidoNum = 0;
  $effect(() => {
    const pedido = {
      monto: montoPedido,
      partes: Math.max(partes - hechas, 1),
      propina: propinaPedida === 'mal' ? null : propinaPedida,
      recibido: recibidoPedido,
    };
    void pagado;
    void reintento;
    if (cerrada) return;
    const esta = ++pedidoNum;
    const espera = setTimeout(async () => {
      try {
        const r = await resumenCuenta(cliente, venta.id, pedido);
        if (esta === pedidoNum) {
          resumen = r;
          errorResumen = null;
        }
      } catch (falla) {
        if (esta !== pedidoNum) return;
        if (!(falla instanceof FalloPos)) console.error('[caja] resumen_cuenta falló:', falla);
        errorResumen =
          falla instanceof FalloPos ? { texto: falla.message, sinRed: falla.sinRed } : { texto: String(falla), sinRed: false };
      }
    }, 200);
    return () => clearTimeout(espera);
  });

  async function leerSusPagos() {
    try {
      pagos = await leerPagos(cliente, restauranteId, [venta.id]);
    } catch (falla) {
      console.error('[caja] no se pudieron leer los pagos de la cuenta:', falla);
    }
  }
  $effect(() => {
    void pagado;
    leerSusPagos();
  });

  const montoEnCampo = $derived(montoAuto ? (resumen ? resumen.monto.toFixed(2) : '') : montoTexto);
  const enCero = $derived(resumen !== null && resumen.falta === 0 && resumen.estado === 'abierta');
  const yaNoAbierta = $derived(resumen !== null && resumen.estado !== 'abierta' && !cerrada);
  const montoMal = $derived(!montoAuto && montoTexto.trim() !== '' && (montoPedido === null || (resumen !== null && !resumen.cabe)));
  const listo = $derived(
    turnoAbierto &&
      !ocupado &&
      errorResumen === null &&
      resumen !== null &&
      resumen.estado === 'abierta' &&
      (enCero ||
        (resumen.cabe &&
          (montoAuto || montoPedido !== null) &&
          propinaPedida !== 'mal' &&
          (metodo !== 'efectivo' || (recibidoPedido !== null && resumen.cambio !== null && resumen.cambio >= 0)))),
  );

  function elegirPartes(n: number) {
    partes = n;
    hechas = 0;
    montoAuto = true;
    cambio();
  }

  async function anotar() {
    if (!listo || !resumen) return;
    ocupado = true;
    error = null;
    try {
      const r = await cobrar(cliente, {
        ventaId: venta.id,
        clave,
        metodo: enCero ? null : metodo,
        monto: enCero ? null : (montoPedido ?? resumen.monto),
        propina: enCero || propinaPedida === 'mal' ? null : propinaPedida,
        recibido: recibidoPedido,
        referencia: referencia.trim(),
      });
      if (r.cerrada) {
        cerrada = { folio: r.folio, total: resumen.total, cambio: r.cambio };
        return;
      }
      alAviso(r.cambio > 0 ? `Pago anotado · cambio ${dinero(r.cambio)}` : `Pago anotado · falta ${dinero(r.falta)}`);
      if (partes > 1 && hechas + 1 < partes) hechas += 1;
      else elegirPartes(1);
      montoAuto = true;
      propina = 'no';
      otraTexto = '';
      recibidoTexto = '';
      referencia = '';
      cambio();
      leerSusPagos();
    } catch (falla) {
      if (falla instanceof FalloPos && falla.sinRed) {
        // Puede que sí haya llegado: la clave se queda, y volver a pulsar no lo anota dos veces.
        error = 'Sin conexión. No se sabe si el pago llegó: vuelve a pulsar «Anotar pago» cuando regrese el internet, y no se anota dos veces.';
      } else {
        error = falla instanceof FalloPos ? falla.message : String(falla);
        if (!(falla instanceof FalloPos)) console.error('[caja] el pago no se pudo anotar:', falla);
      }
    } finally {
      ocupado = false;
    }
  }

  const PROPINAS: { valor: ElegidaPropina; texto: string }[] = [
    { valor: 'no', texto: 'Sin propina' },
    { valor: '10', texto: '10 %' },
    { valor: '15', texto: '15 %' },
    { valor: 'otra', texto: 'Otra' },
  ];
</script>

<svelte:window ononline={() => errorResumen && (reintento += 1)} />

{#if cerrada}
  <Hoja titulo="{venta.titulo} cerrada" cabeza={false} alCerrar={alListo}>
    <div class="cerrada">
      <span class="sello"><Icono nombre="check" tamano={24} /></span>
      <h3>{venta.titulo} cerrada</h3>
      <span class="folio">{cerrada.folio !== null ? `Folio ${cerrada.folio} · ` : ''}{dinero(cerrada.total)}</span>
      {#if cerrada.cambio > 0}
        <div class="cambio-grande"><span>Cambio</span><b>{dinero(cerrada.cambio)}</b></div>
      {/if}
      <p class="pista">{venta.tipo === 'mesa' ? 'La mesa quedó libre.' : 'El pedido ya no sale en Por cobrar.'}</p>
    </div>
    <button type="button" class="cel-boton fijo" onclick={alListo}>Listo</button>
  </Hoja>
{:else}
  <Hoja titulo="Cobrar {venta.titulo}" sub={venta.abrio ? `Abrió ${venta.abrio} · la propina es suya` : ''} {alCerrar}>
    {#if !turnoAbierto}
      <CajaError mensaje="La caja no está abierta. Pídele a quien está en caja que la abra para anotar pagos." />
    {/if}
    {#if yaNoAbierta}
      <CajaError tipo="info" mensaje="Esta cuenta ya no está abierta: se cobró o se juntó en otro aparato." />
    {/if}

    {#if resumen}
      <div class="resumen">
        <div class="resumen-fila"><span>Total</span><span>{dinero(resumen.total)}</span></div>
        {#if resumen.pagado > 0}
          <div class="resumen-fila"><span>Pagado</span><span>{dinero(resumen.pagado)}</span></div>
        {/if}
        <div class="resumen-fila fuerte"><span>Falta</span><span>{dinero(resumen.falta)}</span></div>
      </div>
    {:else if !errorResumen}
      <span class="pista">Leyendo la cuenta…</span>
    {/if}
    {#if errorResumen}
      <CajaError tipo={errorResumen.sinRed ? 'sinred' : 'alerta'} mensaje={errorResumen.texto} />
      {#if !resumen}
        <button type="button" class="cel-boton contorno fijo" onclick={() => (reintento += 1)}>Intentar de nuevo</button>
      {/if}
    {/if}

    {#if pagos.length}
      <div class="grupo-op">
        {#each pagos as p (p.id)}
          <div class="pago-hecho">
            <Icono nombre={p.metodo === 'efectivo' ? 'billete' : p.metodo === 'tarjeta' ? 'tarjeta' : 'banco'} tamano={16} />
            <span class="t">
              <b>{NOMBRE_METODO[p.metodo]}</b>
              <span>{p.cobrado_por !== null ? (nombres.get(p.cobrado_por) ?? '—') : 'En línea'}{p.propina ? ` · propina ${dinero(p.propina)}` : ''}</span>
            </span>
            <span class="m">{dinero(p.monto)}</span>
          </div>
        {/each}
      </div>
    {/if}

    {#if enCero}
      <p class="pista">Esta cuenta es de {dinero(0)}: se cierra sin anotar ningún pago.</p>
    {:else if resumen && !yaNoAbierta}
      <Selector
        etiqueta="Cómo pagó"
        lleno
        alto={30}
        opciones={(['efectivo', 'tarjeta', 'transferencia'] as const).map((m) => ({ valor: m, texto: NOMBRE_METODO[m] }))}
        elegida={metodo}
        alElegir={(m) => {
          metodo = m;
          recibidoTexto = '';
          referencia = '';
          cambio();
        }}
      />

      <div class="campo">
        <label class="etq" for="cobro-monto">Paga</label>
        <input
          id="cobro-monto"
          inputmode="decimal"
          autocomplete="off"
          value={montoEnCampo}
          oninput={(e) => {
            montoTexto = e.currentTarget.value;
            montoAuto = false;
            partes = 1;
            hechas = 0;
            cambio();
          }}
        />
        <div class="chips-cobro" role="group" aria-label="Dividir">
          {#each [1, 2, 3, 4] as n (n)}
            <button type="button" class="chip-cat" aria-pressed={montoAuto && partes === n} onclick={() => elegirPartes(n)}>
              {n === 1 ? 'Todo' : `Entre ${n}`}
            </button>
          {/each}
        </div>
        {#if montoAuto && partes > 1}
          <p class="pista">
            Pago {hechas + 1} de {partes}.{resumen.partes.length > 1 ? ` Los demás: ${resumen.partes.slice(1).map(dinero).join(', ')}.` : ''}
          </p>
        {/if}
        {#if montoMal}
          <p class="pista fuerte">
            {montoPedido === null ? 'Escribe el monto en pesos, como «150» o «148.50».' : `No puede pasar de lo que falta (${dinero(resumen.falta)}).`}
          </p>
        {/if}
      </div>

      <div class="campo">
        <span class="etq">Propina</span>
        <div class="chips-cobro" role="group" aria-label="Propina">
          {#each PROPINAS as o (o.valor)}
            <button
              type="button"
              class="chip-cat"
              aria-pressed={propina === o.valor}
              onclick={() => {
                propina = o.valor;
                cambio();
              }}
            >
              {o.texto}{#if o.valor === '10'}<span class="mono">{dinero(resumen.propina_10)}</span>{:else if o.valor === '15'}<span class="mono">{dinero(resumen.propina_15)}</span>{/if}
            </button>
          {/each}
        </div>
        {#if propina === 'otra'}
          <input
            inputmode="decimal"
            autocomplete="off"
            placeholder="$0.00"
            aria-label="Otra cantidad"
            value={otraTexto}
            oninput={(e) => {
              otraTexto = e.currentTarget.value;
              cambio();
            }}
          />
          {#if propinaPedida === 'mal'}<p class="pista fuerte">Escribe la propina en pesos, como «20».</p>{/if}
        {/if}
      </div>

      {#if metodo === 'efectivo'}
        <div class="campo">
          <label class="etq" for="cobro-recibido">Con cuánto paga</label>
          <input
            id="cobro-recibido"
            inputmode="decimal"
            autocomplete="off"
            placeholder="Ej. $500.00"
            value={recibidoTexto}
            oninput={(e) => {
              recibidoTexto = e.currentTarget.value;
              cambio();
            }}
          />
        </div>
        {#if recibidoPedido !== null && resumen.cambio !== null && resumen.cambio >= 0}
          <div class="dato-grande"><b>Cambio</b><span>{dinero(resumen.cambio)}</span></div>
        {:else if recibidoTexto.trim() && resumen.cabe}
          <p class="pista fuerte">
            {recibidoPedido === null ? 'Escribe el billete en pesos, como «500».' : `No alcanza: son ${dinero(resumen.cobrar)} con la propina.`}
          </p>
        {/if}
      {:else}
        <div class="dato-grande">
          <b>{metodo === 'tarjeta' ? 'Cobra en la terminal' : 'Debe llegar'}</b>
          <span>{dinero(resumen.cabe ? resumen.cobrar : 0)}</span>
        </div>
        <div class="campo">
          <label class="etq" for="cobro-ref">Referencia · opcional</label>
          <input
            id="cobro-ref"
            autocomplete="off"
            placeholder={metodo === 'tarjeta' ? 'Últimos dígitos del voucher' : 'Folio de la transferencia'}
            value={referencia}
            oninput={(e) => {
              referencia = e.currentTarget.value;
              cambio();
            }}
          />
        </div>
      {/if}
    {/if}

    {#if error}<CajaError tipo={error.startsWith('Sin conexión') ? 'sinred' : 'alerta'} mensaje={error} />{/if}

    <button type="button" class="cel-boton fijo" disabled={!listo} onclick={anotar}>
      {#if enCero}
        Cerrar la cuenta
      {:else}
        Anotar pago{resumen && resumen.cabe && propinaPedida !== 'mal' ? ` · ${dinero(resumen.cobrar)}` : ''}
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
