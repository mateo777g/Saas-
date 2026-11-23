// La tarjeta de lealtad en el menú (parte B, 23 nov 2026). El celular guarda la llave de su tarjeta y su código corto en
// `pidemenu-tarjeta-<slug>` (cada sucursal, la suya); Postgres solo guarda su huella y los regresa una sola vez, al sacarla
// o al pedir el código para pasarla a este celular. Todo pasa por el Worker (api/src/tarjeta.ts): sacarla y pedir el
// código llevan Turnstile y la marca del celular; verla y borrarla, solo la llave. El menú nunca lee ni escribe la base.
// «Borrar mis datos» olvida la llave en este celular (lib/pedido.ts); la tarjeta sigue y se recupera con un código.
import { API, escribir, leer, marcaDelCelular } from './pedido';

export type Movimiento = { tipo: string; cantidad: number; dia: string; origen: string | null };

export type Tarjeta = {
  nombre: string;
  telefono: string;
  saldo: number;
  premio_listo: boolean;
  sacada: string;
  ultima_compra: string | null;
  movimientos: Movimiento[];
};

// Lo que recuerda el celular. `esperando`: pidió pasarla aquí y todavía no lo confirma quien cobra (el código de 6 letras
// y cuándo vence).
export type Guardada = { llave: string; codigo: string; esperando?: { codigo: string; vence: string } | null };

// Cómo llegó la tarjeta a la vista: recién sacada, o pasada a este celular (sale el aviso verde una vez).
export type Llegada = 'normal' | 'nueva' | 'pasada';

// Un «no» que la clienta lee tal cual (un dato mal escrito, «No pudimos revisar que eres tú»).
export class NoSalio extends Error {}

const llaveDe = (slug: string) => `pidemenu-tarjeta-${slug}`;

async function alWorker<T>(ruta: string, cuerpo: Record<string, unknown>, sinRed: string): Promise<T> {
  let respuesta: Response;
  try {
    // Sin encabezados propios, como el pedido: sin la pregunta de antes (el «preflight»).
    respuesta = await fetch(`${API}/menu/tarjeta${ruta}`, { method: 'POST', body: JSON.stringify(cuerpo) });
  } catch (error) {
    console.error('[tarjeta] no se pudo llegar al servidor:', error);
    throw new NoSalio(sinRed);
  }
  const datos = (await respuesta.json().catch(() => null)) as (T & { error?: string }) | null;
  if (respuesta.ok && datos && 'ok' in datos) return datos;
  if (datos?.error && respuesta.status < 500) throw new NoSalio(datos.error);
  console.error('[tarjeta] el servidor regresó', ruta, respuesta.status, datos);
  throw new NoSalio(datos?.error ?? sinRed);
}

type RespuestaVer =
  | { ok: true; hoy: string; tarjeta: Tarjeta }
  | { ok: false; motivo: 'no_hay' | 'no_existe' }
  | { ok: false; motivo: 'esperando'; codigo: string; vence: string };

export type RespuestaSacar =
  | { ok: true; llave: string; codigo: string; tarjeta: Tarjeta }
  | { ok: false; motivo: 'no_hay' | 'ya_existe' | 'limite_celular' | 'limite_conexion' };

export type RespuestaCodigo =
  | { ok: true; codigo: string; vence: string; llave: string; codigo_corto: string }
  | { ok: false; motivo: 'no_hay' | 'sin_tarjeta' | 'limite_celular' | 'limite_conexion' };

// La tarjeta de este celular en una sucursal. `estado`: leyendo (la primera vez), sin (este celular no tiene), con,
// esperando (pidió pasarla aquí) o error (no se pudo leer; se dice, nunca se inventa).
export class MiTarjeta {
  estado = $state<'leyendo' | 'sin' | 'con' | 'esperando' | 'error'>('leyendo');
  tarjeta = $state<Tarjeta | null>(null);
  hoy = $state<string | null>(null);
  guardada = $state<Guardada | null>(null);
  llegada = $state<Llegada>('normal');

  constructor(
    private slug: string,
    // En el teléfono de la vista previa del panel no se guarda ni se pide nada.
    private deVerdad: boolean,
  ) {
    this.guardada = deVerdad ? leer<Guardada>(llaveDe(slug)) : null;
    if (!this.guardada) this.estado = 'sin';
  }

  private recordar(g: Guardada | null) {
    this.guardada = g;
    if (this.deVerdad) escribir(llaveDe(this.slug), g);
  }

  // Lee la tarjeta con la llave. Sin llave, «sin». Con una llave que ya no es de ninguna tarjeta (la borró, se pasó a otro
  // celular o el código venció), la olvida.
  async leer(sinRed: string) {
    const g = this.guardada;
    if (!g) {
      this.estado = 'sin';
      return;
    }
    try {
      const r = await alWorker<RespuestaVer>('/ver', { slug: this.slug, llave: g.llave }, sinRed);
      if (this.guardada?.llave !== g.llave) return;
      if (r.ok) {
        // Si la esperaba, ya la confirmaron: llegó a este celular.
        if (g.esperando) {
          this.recordar({ llave: g.llave, codigo: g.codigo, esperando: null });
          this.llegada = 'pasada';
        }
        this.tarjeta = r.tarjeta;
        this.hoy = r.hoy;
        this.estado = 'con';
      } else if (r.motivo === 'esperando') {
        this.recordar({ ...g, esperando: { codigo: r.codigo, vence: r.vence } });
        this.estado = 'esperando';
      } else {
        this.recordar(null);
        this.tarjeta = null;
        this.estado = 'sin';
      }
    } catch (error) {
      if (this.estado === 'leyendo') this.estado = 'error';
      console.warn('[tarjeta] no se pudo leer la tarjeta:', error);
    }
  }

  async sacar(nombre: string, telefono: string, acepta: boolean, turnstile: string, sinRed: string): Promise<RespuestaSacar> {
    const r = await alWorker<RespuestaSacar>(
      '',
      { slug: this.slug, nombre, telefono, acepta, marca: marcaDelCelular(), turnstile },
      sinRed,
    );
    if (r.ok) {
      this.recordar({ llave: r.llave, codigo: r.codigo, esperando: null });
      this.tarjeta = r.tarjeta;
      this.llegada = 'nueva';
      this.estado = 'con';
    }
    return r;
  }

  async pedirCodigo(telefono: string, turnstile: string, sinRed: string): Promise<RespuestaCodigo> {
    const r = await alWorker<RespuestaCodigo>('/codigo', { slug: this.slug, telefono, marca: marcaDelCelular(), turnstile }, sinRed);
    if (r.ok) {
      this.recordar({ llave: r.llave, codigo: r.codigo_corto, esperando: { codigo: r.codigo, vence: r.vence } });
      this.estado = 'esperando';
    }
    return r;
  }

  // «Borrar mi tarjeta»: se va de la base para siempre. Regresa true si se borró (o ya no existía).
  async borrar(sinRed: string): Promise<boolean> {
    const g = this.guardada;
    if (!g) return true;
    const r = await alWorker<{ ok: boolean; motivo?: string }>('/borrar', { slug: this.slug, llave: g.llave }, sinRed);
    if (!r.ok && r.motivo === 'no_hay') return false;
    this.olvidar();
    return true;
  }

  // Este celular deja de recordarla (la tarjeta sigue en la base).
  olvidar() {
    this.recordar(null);
    this.tarjeta = null;
    this.hoy = null;
    this.llegada = 'normal';
    this.estado = 'sin';
  }

  // La muestra del panel: la tarjeta de Rosa, con 8 de 10 (o 86 puntos), sin tocar la red.
  deMuestra(tarjeta: Tarjeta, codigo: string) {
    this.guardada = { llave: 'muestra-de-la-tarjeta-de-lealtad-del-panel-0', codigo, esperando: null };
    this.tarjeta = tarjeta;
    this.estado = 'con';
  }
}
