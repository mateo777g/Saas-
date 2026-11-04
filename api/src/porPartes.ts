// Contestar y leer por partes (planes/trabajo/estrella/worker.md). Dos mitades:
//  - contestarPorPartes: lo que el Worker le manda a la app mientras trabaja, un renglón de JSON por
//    aviso. El trabajo corre dentro de waitUntil: si la app se va («Detener» o cerrar la pestaña),
//    Cloudflare todavía le da 30 segundos para terminar la vuelta pedida y anotar el gasto.
//  - leerEventos: lo que OpenAI manda por partes, evento por evento. Solo convierte el JSON de los
//    eventos que hacen falta: lo demás no gasta los 10 ms de CPU del plan gratis.
import { Rechazo } from './respuestas';

// A los 25 s de irse la app se corta la vuelta, para que alcance a anotar lo demás antes de los 30.
const ESPERA_AL_IRSE = 25_000;

export type Avisar = (aviso: Record<string, unknown>) => void;
// `seFue` dice si la app ya no espera; `corte` se enciende cuando se acaba el tiempo para terminar.
export type LaApp = { seFue: () => boolean; corte: AbortSignal };

export function contestarPorPartes(
  request: Request,
  ctx: ExecutionContext,
  etiqueta: string,
  trabajo: (avisar: Avisar, app: LaApp) => Promise<void>,
): Response {
  const codificador = new TextEncoder();
  const corte = new AbortController();
  let seFue = false;
  let reloj: ReturnType<typeof setTimeout> | null = null;
  const { readable, writable } = new IdentityTransformStream();
  const escritor = writable.getWriter();

  const avisar: Avisar = (aviso) => {
    if (seFue) return;
    // Si la app se acaba de ir y Cloudflare todavía no enciende la señal, no hay a quién avisarle.
    escritor.write(codificador.encode(`${JSON.stringify(aviso)}\n`)).catch(() => {});
  };
  const alIrse = () => {
    seFue = true;
    reloj = setTimeout(() => {
      console.error(`${etiqueta} la vuelta no terminó en ${ESPERA_AL_IRSE / 1000} s después de que la app se fue; si cobró algo, no quedó anotado`);
      corte.abort();
    }, ESPERA_AL_IRSE);
  };
  if (request.signal.aborted) alIrse();
  else request.signal.addEventListener('abort', alIrse, { once: true });

  ctx.waitUntil(
    trabajo(avisar, { seFue: () => seFue, corte: corte.signal })
      .catch((e: unknown) => {
        if (e instanceof Rechazo) return avisar({ tipo: 'error', mensaje: e.message });
        console.error(`${etiqueta} falló por partes`, e);
        avisar({ tipo: 'error', mensaje: 'Algo salió mal. Intenta de nuevo.' });
      })
      .finally(() => {
        clearTimeout(reloj);
        // Si la app se fue, ya estaba cerrado.
        escritor.close().catch(() => {});
      }),
  );
  return new Response(readable, {
    headers: { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-store, no-transform' },
  });
}

// Lo que gasta CPU es despertar al Worker, no leer (medido en Cloudflare: 50 ms contra 4 ms en una
// pregunta normal, si despierta con cada parte). Por eso cada lectura espera a juntar unos bytes:
// EN_CUANTO llegue algo, POQUITO (unas cuantas partes) o JUNTAR (un segundo de texto, más o menos);
// la lectura vuelve antes si se acaba la respuesta.
export const EN_CUANTO = 1;
export const POQUITO = 1_024;
export const JUNTAR = 16_384;
const BOLSA = 65_536;

// Llama `alEvento` con cada evento que `interesa`. Un renglón puede llegar cortado entre dos partes.

export async function leerEventos(
  cuerpo: ReadableStream<Uint8Array>,
  cuantosBytes: () => number,
  interesa: (evento: string) => boolean,
  alEvento: (evento: string, datos: Record<string, unknown>) => void,
): Promise<void> {
  const decodificador = new TextDecoder();
  const lector = cuerpo.getReader({ mode: 'byob' });
  let bolsa: Uint8Array = new Uint8Array(BOLSA);
  let pendiente = '';
  let evento = '';
  for (;;) {
    const { done, value } = await lector.readAtLeast(cuantosBytes(), bolsa);
    if (value?.byteLength) {
      const yaRevisado = pendiente.length;
      pendiente += decodificador.decode(value, { stream: true });
      let inicio = 0;
      let fin = pendiente.indexOf('\n', yaRevisado);
      while (fin !== -1) {
        if (pendiente.startsWith('event: ', inicio)) {
          evento = pendiente.slice(inicio + 7, fin).trim();
        } else if (pendiente.startsWith('data: ', inicio) && interesa(evento)) {
          const datos = convertir(pendiente.slice(inicio + 6, fin), evento);
          if (datos) alEvento(evento, datos);
        }
        inicio = fin + 1;
        fin = pendiente.indexOf('\n', inicio);
      }
      pendiente = pendiente.slice(inicio);
    }
    if (done) return;
    // La lectura se queda con la bolsa y la regresa en `value`.
    bolsa = new Uint8Array((value as Uint8Array).buffer);
  }
}

function convertir(texto: string, evento: string): Record<string, unknown> | null {
  try {
    return JSON.parse(texto) as Record<string, unknown>;
  } catch {
    console.error('[openai] una parte no trae JSON', evento, `(${texto.length} letras)`);
    return null;
  }
}
