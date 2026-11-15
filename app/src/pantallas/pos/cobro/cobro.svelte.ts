// El cobro de una cuenta (partes 4b y 4c; adaptabilidad 3b, maqueta GBWEGCsQFcwKkWm7Qe9FPA v4): lo que antes vivía
// dentro de pos/HojaCobrar.svelte, para que lo pinten la hoja del celular y la tarjeta a lo ancho (Vender y la Caja). El
// punto de venta nunca cobra: aquí se anota cómo pagó el cliente. Los números (lo que falta, las partes, la propina, lo
// que se cobra y el cambio) los da resumen_cuenta mientras se elige, y cobrar los vuelve a calcular al anotar. La clave
// del pago cambia con cada cambio: pulsar dos veces lo mismo, o volver a pulsar tras perder el internet, no lo anota dos
// veces. Cuando los pagos cubren el total, la cuenta se cierra sola y `cerrada` trae el folio, el cambio y el ticket.
//
// Se crea con `new Cobro(() => ({ ... }))`: la función da lo de afuera (la cuenta según el tiempo real, el turno…) y se
// vuelve a leer sola. Puede nacer en cualquier momento (también al tocar una fila); quien la crea la suelta con
// `destruir()` cuando ya no se ve.
import type { SupabaseClient } from '@supabase/supabase-js';
import { untrack } from 'svelte';
import {
  billetesQueAlcanzan,
  cobrar,
  leerMonto,
  leerPagos,
  resumenCuenta,
  type LineaTicket,
  type Metodo,
  type Pago,
  type Propina,
  type Resumen,
} from '../../../lib/caja';
import { dinero } from '../../../lib/formato';
import { FalloPos, quitarDescuento, textoDescuento, type Autoriza, type Renglon, type TipoCuenta, type Venta } from '../../../lib/pos';

export type EntradaCobro = {
  cliente: SupabaseClient;
  restauranteId: string;
  venta: { id: number; titulo: string; tipo: TipoCuenta; abrio: string | null };
  cuenta: Venta | null; // la cuenta según el tiempo real: si cambia su total o lo pagado, el resumen se vuelve a pedir
  turnoId: number | null; // el turno abierto; sin turno no se anotan pagos
  nombres: Map<number, string>;
  autorizan: Autoriza[] | null; // quién pone su PIN para descontar o cancelar un pago; null: quien cobra es de la caja o gerente
  zona: string;
  renglones?: Renglon[]; // lo que lleva la cuenta, para el ticket de «Cobrada» (a lo ancho)
  alAviso: (texto: string) => void;
};

export type ElegidaPropina = 'no' | '10' | '15' | 'otra';
// Con cuánto paga en efectivo: nada todavía (encuesta 1 de cobro-caja.md), «Exacto», un billete o lo que se escribe.
export type Recibido = { tipo: 'nada' } | { tipo: 'exacto' } | { tipo: 'billete'; n: number } | { tipo: 'texto'; texto: string };

export type PagoTicket = { metodo: Metodo; monto: number; propina: number; recibido: number | null; cambio: number };
export type Cerrada = {
  folio: number | null;
  total: number;
  subtotal: number;
  descuento: { texto: string; monto: number } | null;
  cambio: number;
  reabierta: boolean; // ya traía folio: se cobró otra vez tras cancelar un pago
  lineas: LineaTicket[];
  pagos: PagoTicket[];
};

export class Cobro {
  metodo = $state<Metodo>('efectivo');
  partes = $state(1);
  hechas = $state(0);
  montoAuto = $state(true);
  montoTexto = $state('');
  propina = $state<ElegidaPropina>('no');
  otraTexto = $state('');
  recibido = $state<Recibido>({ tipo: 'nada' });
  referencia = $state('');
  clave = $state(crypto.randomUUID());

  resumen = $state<Resumen | null>(null);
  pagos = $state<Pago[]>([]);
  error = $state<string | null>(null);
  errorResumen = $state<{ texto: string; sinRed: boolean } | null>(null);
  reintento = $state(0);
  ocupado = $state(false);
  cerrada = $state<Cerrada | null>(null);
  // La hoja de encima: el descuento a la cuenta o cancelar un pago. El cobro se queda como estaba.
  encima = $state<{ tipo: 'descuento' } | { tipo: 'pago'; pago: Pago } | null>(null);

  #entrada: () => EntradaCobro;
  #soltar: () => void;

  constructor(entrada: () => EntradaCobro) {
    this.#entrada = entrada;
    this.#soltar = $effect.root(() => {
      // Los números de lo elegido, 200 ms después del último cambio.
      let pedidoNum = 0;
      $effect(() => {
        const pedido = {
          monto: this.montoPedido,
          partes: Math.max(this.partes - this.hechas, 1),
          propina: this.propinaPedida === 'mal' ? null : this.propinaPedida,
          // «Exacto» no se manda: es lo que se cobra, y al anotarlo va lo último que dijo Postgres.
          recibido: this.recibido.tipo === 'exacto' ? null : this.recibidoPedido,
        };
        void this.pagado;
        void this.total;
        void this.reintento;
        if (this.cerrada) return;
        const { cliente, venta } = untrack(() => this.e);
        const esta = ++pedidoNum;
        const espera = setTimeout(async () => {
          try {
            const r = await resumenCuenta(cliente, venta.id, pedido);
            if (esta === pedidoNum) {
              this.resumen = r;
              this.errorResumen = null;
            }
          } catch (falla) {
            if (esta !== pedidoNum) return;
            if (!(falla instanceof FalloPos)) console.error('[caja] resumen_cuenta falló:', falla);
            this.errorResumen =
              falla instanceof FalloPos ? { texto: falla.message, sinRed: falla.sinRed } : { texto: String(falla), sinRed: false };
          }
        }, 200);
        return () => clearTimeout(espera);
      });

      // Los pagos ya anotados, cada vez que cambia lo pagado.
      $effect(() => {
        void this.pagado;
        untrack(() => this.leerSusPagos());
      });

      // Un billete que ya no alcanza (subió la propina o se cambió la parte) deja de estar elegido.
      $effect(() => {
        const r = this.resumen;
        const x = untrack(() => this.recibido);
        if (r && x.tipo === 'billete' && x.n < r.cobrar) this.recibido = { tipo: 'nada' };
      });

      // Al regresar el internet, si el resumen había fallado, se vuelve a pedir.
      const alVolver = () => {
        if (this.errorResumen) this.reintento += 1;
      };
      window.addEventListener('online', alVolver);
      return () => window.removeEventListener('online', alVolver);
    });
  }

  get e(): EntradaCobro {
    return this.#entrada();
  }

  destruir() {
    this.#soltar();
  }

  // ─── Lo que se ve ───
  cuenta = $derived(this.e.cuenta);
  turnoAbierto = $derived(this.e.turnoId !== null);
  pagado = $derived(this.cuenta?.pagado ?? null);
  total = $derived(this.cuenta?.total ?? null);
  descuento = $derived(
    this.cuenta?.descuento_tipo && this.cuenta.descuento_valor !== null
      ? {
          texto: textoDescuento(this.cuenta.descuento_tipo, this.cuenta.descuento_valor),
          motivo: this.cuenta.descuento_motivo ?? '',
          monto: this.cuenta.descuento,
        }
      : null,
  );

  // Lo que se le pide a Postgres con lo elegido.
  propinaPedida = $derived.by<Propina | 'mal'>(() => {
    if (this.propina === '10') return { porcentaje: 10 };
    if (this.propina === '15') return { porcentaje: 15 };
    if (this.propina === 'otra') {
      if (this.otraTexto.trim() === '') return null;
      const n = leerMonto(this.otraTexto);
      return n === null ? 'mal' : { cantidad: n };
    }
    return null;
  });
  montoPedido = $derived(this.montoAuto ? null : leerMonto(this.montoTexto));
  recibidoPedido = $derived.by<number | null>(() => {
    if (this.metodo !== 'efectivo') return null;
    const x = this.recibido;
    if (x.tipo === 'exacto') return this.resumen?.cobrar ?? null;
    if (x.tipo === 'billete') return x.n;
    if (x.tipo === 'texto') return x.texto.trim() ? leerMonto(x.texto) : null;
    return null;
  });
  // Lo que dice la caja del cambio: con «Exacto» no hay cambio; con un monto, el de Postgres (negativo: no alcanza).
  cambioVisto = $derived.by<number | null>(() => {
    if (this.metodo !== 'efectivo' || !this.resumen || !this.resumen.cabe) return null;
    if (this.recibido.tipo === 'exacto') return 0;
    return this.recibidoPedido === null ? null : this.resumen.cambio;
  });
  sugeridos = $derived(this.resumen ? billetesQueAlcanzan(this.resumen.cobrar) : []);

  montoEnCampo = $derived(this.montoAuto ? (this.resumen ? this.resumen.monto.toFixed(2) : '') : this.montoTexto);
  recibidoEnCampo = $derived.by(() => {
    const x = this.recibido;
    if (x.tipo === 'texto') return x.texto;
    if (x.tipo === 'billete') return x.n.toFixed(2);
    if (x.tipo === 'exacto') return this.resumen ? this.resumen.cobrar.toFixed(2) : '';
    return '';
  });
  enCero = $derived(this.resumen !== null && this.resumen.falta === 0 && this.resumen.estado === 'abierta');
  yaNoAbierta = $derived(this.resumen !== null && this.resumen.estado !== 'abierta' && !this.cerrada);
  montoMal = $derived(
    !this.montoAuto && this.montoTexto.trim() !== '' && (this.montoPedido === null || (this.resumen !== null && !this.resumen.cabe)),
  );
  listo = $derived(
    this.turnoAbierto &&
      !this.ocupado &&
      this.errorResumen === null &&
      this.resumen !== null &&
      this.resumen.estado === 'abierta' &&
      (this.enCero ||
        (this.resumen.cabe &&
          (this.montoAuto || this.montoPedido !== null) &&
          this.propinaPedida !== 'mal' &&
          (this.metodo !== 'efectivo' ||
            this.recibido.tipo === 'exacto' ||
            (this.recibidoPedido !== null && this.resumen.cambio !== null && this.resumen.cambio >= 0)))),
  );
  // Lo que dice el botón: «Anotar pago · $98.00» (sin monto mientras no se sabe), o «Cerrar la cuenta» si es de $0.
  cobrarEnBoton = $derived(
    this.resumen && this.resumen.cabe && this.propinaPedida !== 'mal' ? this.resumen.cobrar : null,
  );

  // Un pago se cancela mientras su turno sigue abierto; uno en línea, nunca desde aquí.
  seCancela = (p: Pago) => !p.cancelado_at && p.cobrado_por !== null && p.turno_id !== null && p.turno_id === this.e.turnoId;

  // ─── Lo que se elige ───
  // Un cambio en el cobro es otro pago: otra clave.
  cambio() {
    this.clave = crypto.randomUUID();
    this.error = null;
  }

  elegirMetodo(m: Metodo) {
    this.metodo = m;
    this.recibido = { tipo: 'nada' };
    this.referencia = '';
    this.cambio();
  }

  elegirPartes(n: number) {
    this.partes = n;
    this.hechas = 0;
    this.montoAuto = true;
    this.montoTexto = '';
    this.cambio();
  }

  // A lo ancho, «Otra cantidad»: con algo escrito paga eso; vacío, vuelve a «Todo».
  escribirMonto(texto: string) {
    this.montoTexto = texto;
    this.montoAuto = texto.trim() === '';
    this.partes = 1;
    this.hechas = 0;
    this.cambio();
  }

  // En la hoja del celular el campo «Paga» siempre está lleno: lo escrito manda, aunque se borre todo.
  escribirMontoHoja(texto: string) {
    this.montoTexto = texto;
    this.montoAuto = false;
    this.partes = 1;
    this.hechas = 0;
    this.cambio();
  }

  elegirPropina(p: ElegidaPropina) {
    this.propina = p;
    this.cambio();
  }

  escribirOtra(texto: string) {
    this.otraTexto = texto;
    this.cambio();
  }

  elegirRecibido(r: Recibido) {
    this.recibido = r;
    this.cambio();
  }

  escribirReferencia(texto: string) {
    this.referencia = texto;
    this.cambio();
  }

  reintentar() {
    this.reintento += 1;
  }

  async leerSusPagos() {
    const { cliente, restauranteId, venta } = this.e;
    try {
      this.pagos = await leerPagos(cliente, restauranteId, [venta.id]);
    } catch (falla) {
      console.error('[caja] no se pudieron leer los pagos de la cuenta:', falla);
    }
  }

  // ─── Anotar ───
  async anotar() {
    const resumen = this.resumen;
    if (!this.listo || !resumen) return;
    const { cliente, venta, alAviso } = this.e;
    this.ocupado = true;
    this.error = null;
    // Antes de cobrar: al cerrarse, toda cuenta tiene folio. Una reabierta ya lo traía y no ocupa su mesa.
    const cuenta = this.cuenta;
    const reabierta = cuenta?.folio != null;
    const metodo = this.enCero ? null : this.metodo;
    const monto = this.enCero ? null : (this.montoPedido ?? resumen.monto);
    const recibido = this.recibidoPedido;
    const lineas = (this.e.renglones ?? [])
      .filter((r) => r.venta_id === venta.id && r.estado === 'activo')
      .map((r) => ({ id: r.id, cantidad: r.cantidad, nombre: r.nombre, importe: r.importe }));
    try {
      const r = await cobrar(cliente, {
        ventaId: venta.id,
        clave: this.clave,
        metodo,
        monto,
        propina: this.enCero || this.propinaPedida === 'mal' ? null : this.propinaPedida,
        recibido,
        referencia: this.referencia.trim(),
      });
      if (r.cerrada) {
        // El ticket: los pagos de antes (sin el que se acaba de anotar, si el tiempo real ya lo trajo) y este.
        const pagos: PagoTicket[] = this.pagos
          .filter((p) => !p.cancelado_at && p.id !== r.pago_id)
          .map((p) => ({ metodo: p.metodo, monto: p.monto, propina: p.propina, recibido: p.recibido, cambio: p.cambio ?? 0 }));
        if (metodo && monto !== null)
          pagos.push({ metodo, monto, propina: resumen.propina, recibido: metodo === 'efectivo' ? recibido : null, cambio: r.cambio });
        this.cerrada = {
          folio: r.folio,
          total: resumen.total,
          subtotal: cuenta?.subtotal ?? resumen.total,
          descuento: this.descuento ? { texto: this.descuento.texto, monto: this.descuento.monto } : null,
          cambio: r.cambio,
          reabierta,
          lineas,
          pagos,
        };
        return;
      }
      alAviso(r.cambio > 0 ? `Pago anotado · cambio ${dinero(r.cambio)}` : `Pago anotado · falta ${dinero(r.falta)}`);
      if (this.partes > 1 && this.hechas + 1 < this.partes) this.hechas += 1;
      else this.elegirPartes(1);
      this.montoAuto = true;
      this.montoTexto = '';
      this.propina = 'no';
      this.otraTexto = '';
      this.recibido = { tipo: 'nada' };
      this.referencia = '';
      this.cambio();
      this.leerSusPagos();
    } catch (falla) {
      if (falla instanceof FalloPos && falla.sinRed) {
        // Puede que sí haya llegado: la clave se queda, y volver a pulsar no lo anota dos veces.
        this.error =
          'Sin conexión. No se sabe si el pago llegó: vuelve a pulsar «Anotar pago» cuando regrese el internet, y no se anota dos veces.';
      } else {
        this.error = falla instanceof FalloPos ? falla.message : String(falla);
        if (!(falla instanceof FalloPos)) console.error('[caja] el pago no se pudo anotar:', falla);
      }
    } finally {
      this.ocupado = false;
    }
  }

  async quitarDescuento() {
    if (this.ocupado) return;
    const { cliente, venta, alAviso } = this.e;
    this.ocupado = true;
    this.error = null;
    try {
      await quitarDescuento(cliente, venta.id, null);
      alAviso('Descuento quitado');
      this.cambio();
    } catch (falla) {
      this.error = falla instanceof FalloPos ? falla.message : String(falla);
      if (!(falla instanceof FalloPos)) console.error('[caja] no se pudo quitar el descuento:', falla);
    } finally {
      this.ocupado = false;
    }
  }

  // ─── Lo de encima: el descuento y cancelar un pago ───
  abrirDescuento() {
    this.encima = { tipo: 'descuento' };
    this.error = null;
  }

  abrirCancelarPago(p: Pago) {
    this.encima = { tipo: 'pago', pago: p };
    this.error = null;
  }

  // Lo que pasa al terminar lo de encima: el globo, otra clave y, si se canceló un pago, los pagos otra vez.
  // Un pago cancelado vuelve a faltar, así que «Entre 2» empieza a contar de nuevo («Pago 1 de 2» sobre lo que falta
  // ahora); antes seguía en «Pago 2 de 2» y cobraba todo lo que faltaba de una vez.
  alEncimaListo(globo: string) {
    const eraPago = this.encima?.tipo === 'pago';
    this.encima = null;
    this.e.alAviso(globo);
    if (eraPago && this.montoAuto) this.hechas = 0;
    this.cambio();
    if (eraPago) this.leerSusPagos();
  }
}
