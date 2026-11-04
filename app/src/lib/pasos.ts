// Lo que el Agente IA y el asistente del menú comparten para leer al Worker por partes (planes/trabajo/
// estrella/worker.md y vista.md): un renglón de JSON por aviso, y un compás para que cada paso se deje
// leer. Este archivo también lo usa el menú en línea: no importa supabase.

export type Paso = {
  clave: string | number;
  icono: string;
  texto: string; // mientras corre
  listo: string; // al terminar
  hecho: boolean;
};

export type Aviso = Record<string, unknown> & { tipo?: unknown };

// Lo que se rechaza antes de empezar sigue llegando en JSON normal: se distingue por el Content-Type.
export function vienePorPartes(respuesta: Response): boolean {
  return (respuesta.headers.get('Content-Type') ?? '').startsWith('application/x-ndjson');
}

// Da cada aviso completo, aunque llegue cortado a media línea. Un aviso que `alAviso` no acepta
// (porque lanza) termina la lectura.
export async function leerRenglones(respuesta: Response, alAviso: (aviso: Aviso) => void): Promise<void> {
  if (!respuesta.body) throw new Error('la respuesta no trae cuerpo');
  const lector = respuesta.body.getReader();
  const decodificador = new TextDecoder();
  let pendiente = '';
  for (;;) {
    const { done, value } = await lector.read();
    if (done) break;
    pendiente += decodificador.decode(value, { stream: true });
    let fin: number;
    while ((fin = pendiente.indexOf('\n')) !== -1) {
      const renglon = pendiente.slice(0, fin).trim();
      pendiente = pendiente.slice(fin + 1);
      if (renglon) alAviso(JSON.parse(renglon) as Aviso);
    }
  }
  const resto = pendiente.trim();
  if (resto) alAviso(JSON.parse(resto) as Aviso);
}

// Cada paso se queda a la vista al menos 400 ms (worker.md, punto 36): el paso sí pasó, solo se deja
// leer. Los cambios se hacen en orden, y ninguno le quita su tiempo al último paso que entró.
const MINIMO_A_LA_VISTA = 400;

export class Compas {
  #cola: Promise<void> = Promise.resolve();
  #entro = 0;
  #parado = false;
  #soltar: (() => void) | null = null;

  #esperar(ms: number): Promise<void> {
    return new Promise((listo) => {
      const reloj = setTimeout(listo, ms);
      this.#soltar = () => {
        clearTimeout(reloj);
        listo();
      };
    });
  }

  // Un paso nuevo: empieza a contar desde que se ve.
  entra(cambio: () => void) {
    this.#poner(() => {
      cambio();
      this.#entro = performance.now();
    });
  }

  // Lo que le quita la vista al último paso: lo termina o lo quita.
  sale(cambio: () => void) {
    this.#poner(cambio);
  }

  // Lo que ya nace terminado: va enseguida de lo anterior, sin esperar.
  ahora(cambio: () => void) {
    this.#cola = this.#cola.then(() => {
      if (!this.#parado) cambio();
    });
  }

  #poner(cambio: () => void) {
    this.#cola = this.#cola.then(async () => {
      const falta = this.#entro + MINIMO_A_LA_VISTA - performance.now();
      if (falta > 0 && !this.#parado) await this.#esperar(falta);
      if (!this.#parado) cambio();
    });
  }

  // Cuando ya se hizo todo lo pedido (o se paró).
  termina(): Promise<void> {
    return this.#cola;
  }

  // Se suelta lo que falte, sin esperar: «Detener», o un error a media pregunta.
  parar() {
    this.#parado = true;
    this.#soltar?.();
  }
}
