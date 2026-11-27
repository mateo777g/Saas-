// «Armar mi menú con tu carta» (planes/trabajo/menu-con-ia: encuestas.md, worker.md). Un trabajo, con
// la sesión del gerente:
//  - POST /agente/carta, multipart: `restaurante`, la `nota` (opcional, hasta 300 letras) y cada `hoja`
//    (hasta 6 fotos o un PDF). Postgres dice si le queda otra carta este mes (puedo_leer_carta; sin
//    eso no se llama a OpenAI, y ese «no» es un JSON normal). Después contesta por partes: sube las
//    hojas a OpenAI tal cual (sin leerlas, para no gastar CPU), una sola lectura con gpt-6.1-sol y su
//    esquema, sus pasos con lo que va encontrando, la revisión de lo que regresó y al final la carta
//    leída para la ventana de revisión. El gasto se anota siempre; solo la lectura que llega a la app
//    cuenta en las del mes. Las hojas se borran de OpenAI al terminar (y si no, OpenAI las borra sola
//    a la hora). Nada se guarda en la base: eso es «Subir a mi menú» (subir_a_mi_menu, desde la app).
// Ni las hojas, ni la nota, ni lo que escribió el modelo pasan al registro.
import { anotar } from './agente';
import type { Env } from './index';
import { borrarArchivo, lecturaDeLaCarta, modeloAgente, subirArchivo } from './openai';
import type { Hoja, Lectura } from './openai';
import { Pasos } from './pasos';
import type { Paso } from './pasos';
import { contestarPorPartes, POQUITO } from './porPartes';
import type { Avisar, LaApp } from './porPartes';
import { DUDAS, ICONOS, loDeEsteRestaurante, REGLAS_CARTA, SALIDA_CARTA } from './promptCarta';
import { json, Rechazo } from './respuestas';
import { leerFilas, leerSesion, llamar } from './supabase';

const ETIQUETA = '[carta]';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HOJAS = 6;
// La app las manda de 2048 px de lado largo (unos cientos de KB); el PDF, como lo tenga.
const MAXIMO_HOJA = 5 * 1024 * 1024;
const MAXIMO_PDF = 20 * 1024 * 1024;
const MAXIMO_PETICION = HOJAS * MAXIMO_HOJA + 1024 * 1024;
const LARGO_NOTA = 300;
// Lo que recibe subir_a_mi_menu de una vez (migracion.md, «Lo que decidí yo» 5).
const CATEGORIAS = 40;
const PRODUCTOS = 400;
// Para que un texto raro del modelo no llene la ventana.
const LARGO_NOMBRE = 120;
const LARGO_CATEGORIA = 80;
const LARGO_DESCRIPCION = 500;
const LARGO_SOBRE_LA_NOTA = 200;
// Lo que cabe en numeric(12,2).
const PRECIO_MAXIMO = 9_999_999_999.99;
// Las categorías de Mi menú que se le dicen al modelo.
const CATEGORIAS_QUE_TIENE = 100;
// El índice de la carta se busca solo al principio de lo que escribe.
const LARGO_INDICE = 20_000;

type Formato = 'webp' | 'jpeg' | 'png' | 'pdf';
type Duda = (typeof DUDAS)[number];
export type ProductoLeido = { nombre: string; descripcion: string | null; precio: number | null; duda: Duda | null };
export type CategoriaLeida = { nombre: string; icono: string; productos: ProductoLeido[] };
type Cuantas = { puede: boolean; quedan: number; de: number; vuelve: string };

export async function leerLaCarta(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const sesion = leerSesion(request);
  const { restaurante, nota, hojas } = await leerPeticion(request);

  // Antes de OpenAI: si le queda otra carta este mes (no mira el tope) y los nombres de sus categorías.
  const [cuantas, categorias] = await Promise.all([
    llamar<Cuantas>(env, { sesion }, 'puedo_leer_carta', { p_restaurante_id: restaurante }),
    leerFilas<{ nombre: unknown }>(
      env,
      sesion,
      `categorias?select=nombre&restaurante_id=eq.${restaurante}&archivado_at=is.null&order=orden.asc,id.asc&limit=${CATEGORIAS_QUE_TIENE}`,
    ),
  ]);
  if (!cuantas?.puede) return json(cuantas);
  const nombres = categorias.map((c) => c.nombre).filter((n): n is string => typeof n === 'string' && !!n.trim());

  const de = Number.isInteger(cuantas.de) ? cuantas.de : null;
  return contestarPorPartes(request, ctx, ETIQUETA, (avisar, app) => leer(env, restaurante, hojas, nombres, nota, de, avisar, app));
}

// ─── La petición ──────────────────────────────────────────────────────────────

async function leerPeticion(request: Request): Promise<{ restaurante: string; nota: string; hojas: Hoja[] }> {
  // Antes de leer las hojas: lo que dice el navegador que pesan.
  const largo = Number(request.headers.get('Content-Length'));
  if (!Number.isFinite(largo) || largo <= 0) throw new Rechazo(411, 'Agrega las hojas de tu carta.');
  if (largo > MAXIMO_PETICION) throw new Rechazo(413, 'Tu carta pesa mucho. Manda fotos más chicas.');
  if (!(request.headers.get('Content-Type') ?? '').toLowerCase().startsWith('multipart/form-data')) {
    throw new Rechazo(400, 'Agrega las hojas de tu carta.');
  }
  let forma: FormData;
  try {
    forma = await request.formData();
  } catch {
    throw new Rechazo(400, 'No pudimos leer tu carta. Intenta de nuevo.');
  }

  const restaurante = forma.get('restaurante');
  if (typeof restaurante !== 'string' || !UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');
  const notaCruda = forma.get('nota') ?? '';
  if (typeof notaCruda !== 'string') throw new Rechazo(400, 'La nota va como texto.');
  const nota = notaCruda.trim();
  if (nota.length > LARGO_NOTA) throw new Rechazo(400, `La nota es muy larga: hasta ${LARGO_NOTA} letras.`);

  const archivos = forma.getAll('hoja');
  if (!archivos.length) throw new Rechazo(400, 'Agrega las hojas de tu carta.');
  if (archivos.length > HOJAS) throw new Rechazo(400, `Caben ${HOJAS} hojas por carta.`);
  const hojas: Hoja[] = [];
  for (const [i, archivo] of archivos.entries()) {
    if (typeof archivo === 'string') throw new Rechazo(400, `La hoja ${i + 1} no es una foto ni un PDF.`);
    const formato = await formatoDe(archivo);
    if (!formato) throw new Rechazo(400, `La hoja ${i + 1} no es una foto ni un PDF.`);
    const esPdf = formato === 'pdf';
    if (esPdf && archivos.length > 1) throw new Rechazo(400, 'Manda las fotos o un PDF, no los dos.');
    if (archivo.size > (esPdf ? MAXIMO_PDF : MAXIMO_HOJA)) {
      throw new Rechazo(413, esPdf ? 'Tu PDF pesa más de 20 MB.' : `La hoja ${i + 1} pesa más de 5 MB.`);
    }
    // Con un nombre y un tipo de nosotros: el nombre del archivo de Don Chuy no sale de aquí. `slice` no copia
    // los bytes (medido: copiar 6 hojas de 1 MB gasta CPU de más).
    const nombre = esPdf ? 'carta.pdf' : `hoja-${i + 1}.${formato === 'jpeg' ? 'jpg' : formato}`;
    hojas.push({ archivo: archivo.slice(0, archivo.size, esPdf ? 'application/pdf' : `image/${formato}`), nombre, esPdf });
  }
  return { restaurante, nota, hojas };
}

// Lo que es de verdad, por sus primeros bytes (no por lo que diga el navegador).
async function formatoDe(archivo: File): Promise<Formato | null> {
  const b = new Uint8Array(await archivo.slice(0, 12).arrayBuffer());
  const letras = (desde: number, hasta: number) => String.fromCharCode(...b.subarray(desde, hasta));
  if (b.length >= 12 && letras(0, 4) === 'RIFF' && letras(8, 12) === 'WEBP') return 'webp';
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpeg';
  if (b.length >= 8 && b[0] === 0x89 && letras(1, 4) === 'PNG' && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return 'png';
  if (b.length >= 5 && letras(0, 5) === '%PDF-') return 'pdf';
  return null;
}

// ─── La lectura ───────────────────────────────────────────────────────────────

async function leer(
  env: Env,
  restaurante: string,
  hojas: Hoja[],
  categorias: string[],
  nota: string,
  de: number | null,
  avisar: Avisar,
  app: LaApp,
): Promise<void> {
  const cuenta = de === null ? '' : `: esta no cuenta en tus ${de}`;
  const pasos = new PasosDeLaCarta(new Pasos(avisar));
  const esPdf = hojas[0].esPdf;
  const ids: string[] = [];
  try {
    const subidas = await Promise.allSettled(hojas.map((h) => subirArchivo(env, h)));
    for (const s of subidas) if (s.status === 'fulfilled') ids.push(s.value);
    if (ids.length < hojas.length) {
      const fallo = subidas.find((s) => s.status === 'rejected');
      if (fallo && !(fallo.reason instanceof Rechazo)) console.error(`${ETIQUETA} subir una hoja falló`, fallo.reason);
      throw new Rechazo(502, `No pude leer tu carta. Intenta de nuevo${cuenta}.`);
    }
    // Se fue antes de leer: OpenAI no cobró nada.
    if (app.seFue()) return;

    let lectura: Lectura;
    try {
      lectura = await lecturaDeLaCarta(
        env,
        { instrucciones: `${REGLAS_CARTA}\n\n${loDeEsteRestaurante(categorias, nota)}`, ids, esPdf, formato: SALIDA_CARTA },
        { alEscribir: (parte) => pasos.parte(parte) },
        app.corte,
      );
    } catch (e) {
      // OpenAI contestó con error o no contestó a tiempo: ya quedó en el registro y no se sabe qué cobró.
      if (e instanceof Rechazo) throw new Rechazo(502, `No pude leer tu carta. Intenta de nuevo${cuenta}.`);
      throw e;
    }

    // Solo cuenta en las del mes la lectura que trae productos y que la app todavía espera.
    const carta = lectura.salida && !app.seFue() ? revisarCarta(lectura.salida, nota) : null;
    const productos = carta ? carta.categorias.reduce((n, c) => n + c.productos.length, 0) : 0;
    const leida = !!carta && productos > 0;
    let puede: boolean | null = null;
    if (leida || lectura.tokens.entrada || lectura.tokens.salida) {
      puede = await anotar(env, restaurante, leida ? 'carta' : 'carta_sin_lectura', modeloAgente(env), lectura.tokens);
    }
    // Si la app ya se fue, lo que sigue no le llega a nadie (avisar ya no escribe).
    if (!carta || !leida) {
      if (lectura.larga) throw new Rechazo(502, `Tu carta es muy larga para leerla de una vez. Prueba con menos hojas${cuenta}.`);
      if (carta) {
        throw new Rechazo(422, `No encontré productos ${esPdf ? 'en este PDF' : 'en estas fotos'}. Revisa que sean de tu carta y que se lean bien${cuenta}.`);
      }
      throw new Rechazo(502, `No pude leer tu carta. Intenta de nuevo${cuenta}.`);
    }

    const dudas = carta.categorias.reduce((n, c) => n + c.productos.filter((p) => p.duda).length, 0);
    pasos.terminar(carta.categorias.length, productos, dudas);
    const leiste = esPdf ? 'Leí tu carta en PDF' : hojas.length === 1 ? 'Leí tu hoja' : `Leí tus ${hojas.length} hojas`;
    const respuesta = `${leiste}${carta.sobreLaNota ? ` y, ${carta.sobreLaNota}` : ''}. Antes de subirlo, revisa lo que anoté${dudas ? ': lo que no pude leer bien va en amarillo' : ''}.`;
    avisar({ tipo: 'fin', respuesta, carta: { categorias: carta.categorias }, puede: puede !== false });
  } finally {
    await Promise.all(ids.map((id) => borrarArchivo(env, id)));
  }
}

// ─── La revisión de lo que escribió el modelo ─────────────────────────────────

// Lo que pasa a la ventana de revisión: los íconos de la lista, los precios como número de 2
// decimales (o null), los textos limpios y cortos, sin productos sin nombre ni categorías vacías, una
// sección repetida juntada en la primera, y a lo mucho lo que recibe subir_a_mi_menu de una vez.
export function revisarCarta(salida: Record<string, unknown>, nota: string): { categorias: CategoriaLeida[]; sobreLaNota: string } {
  const categorias: CategoriaLeida[] = [];
  let productos = 0;
  let sobran = 0;
  for (const c of Array.isArray(salida.categorias) ? (salida.categorias as Record<string, unknown>[]) : []) {
    if (!c || typeof c !== 'object') continue;
    const leidos: ProductoLeido[] = [];
    for (const p of Array.isArray(c.productos) ? (c.productos as Record<string, unknown>[]) : []) {
      const producto = p && typeof p === 'object' ? revisarProducto(p) : null;
      if (!producto) continue;
      if (productos >= PRODUCTOS) {
        sobran++;
        continue;
      }
      leidos.push(producto);
      productos++;
    }
    if (!leidos.length) continue;
    const nombre = limpio(c.nombre, LARGO_CATEGORIA) || 'Comida';
    const misma = categorias.find((ya) => ya.nombre.toLowerCase() === nombre.toLowerCase());
    if (misma) {
      misma.productos.push(...leidos);
    } else if (categorias.length < CATEGORIAS) {
      const icono = typeof c.icono === 'string' && (ICONOS as readonly string[]).includes(c.icono) ? c.icono : 'comida';
      categorias.push({ nombre, icono, productos: leidos });
    } else {
      sobran += leidos.length;
    }
  }
  if (sobran) console.warn(`${ETIQUETA} la carta trae más de lo que se sube de una vez: se quedaron fuera ${sobran} productos`);

  let sobreLaNota = nota ? limpio(salida.sobre_la_nota, LARGO_SOBRE_LA_NOTA).replace(/[.\s]+$/, '') : '';
  if (sobreLaNota) sobreLaNota = sobreLaNota[0].toLowerCase() + sobreLaNota.slice(1);
  return { categorias, sobreLaNota };
}

function revisarProducto(p: Record<string, unknown>): ProductoLeido | null {
  const nombre = limpio(p.nombre, LARGO_NOMBRE);
  if (!nombre) return null;
  const descripcion = limpio(p.descripcion, LARGO_DESCRIPCION) || null;
  const precio =
    typeof p.precio === 'number' && Number.isFinite(p.precio) && p.precio >= 0 && p.precio <= PRECIO_MAXIMO
      ? Math.round(p.precio * 100) / 100
      : null;
  let duda: Duda | null = typeof p.duda === 'string' && (DUDAS as readonly string[]).includes(p.duda) ? (p.duda as Duda) : null;
  // Sin precio, siempre «No se lee el precio»; con precio, esa duda es «Revisa este precio».
  if (precio === null) duda = 'sin_precio';
  else if (duda === 'sin_precio') duda = 'revisa_precio';
  return { nombre, descripcion, precio, duda };
}

function limpio(valor: unknown, largo: number): string {
  return typeof valor === 'string' ? valor.replace(/\s+/g, ' ').trim().slice(0, largo).trim() : '';
}

// ─── Los pasos ────────────────────────────────────────────────────────────────

const LEYENDO: Paso = { icono: 'foto', texto: 'Leyendo tu carta…', listo: 'Leí tu carta' };
const BUSCANDO: Paso = { icono: 'lupa', texto: 'Buscando las secciones…', listo: 'Encontré las secciones' };

const cuantos = (n: number, cosa: string, cosas: string) => `${n.toLocaleString('en-US')} ${n === 1 ? cosa : cosas}`;
const encontre = (n: number) => `Encontré ${cuantos(n, 'sección', 'secciones')}`;
const anotando = (n: number | null): Paso =>
  n === null
    ? { icono: 'tabla', texto: 'Anotando los productos…', listo: 'Anoté los productos' }
    : { icono: 'tabla', texto: `Anotando ${cuantos(n, 'producto', 'productos')}…`, listo: `Anoté ${cuantos(n, 'producto', 'productos')}` };

// Lo que ve Don Chuy mientras lee (maqueta, «Lo que elegí yo» 6): «Leyendo tu carta…» hasta que el
// modelo empieza a escribir; «Buscando las secciones…» mientras escribe el índice; con el índice,
// «Encontré 3 secciones» y «Anotando 19 productos…»; al final, lo que de verdad quedó («Anoté 18
// productos») y «Marqué 2 dudas». Lo escrito se guarda solo hasta encontrar el índice.
export class PasosDeLaCarta {
  private leyendo: number | null;
  private buscando: number | null = null;
  private anotando: number | null = null;
  private secciones: number | null = null;
  private texto = '';

  constructor(private pasos: Pasos) {
    this.leyendo = pasos.abrir(LEYENDO);
  }

  parte(parte: string): number | null {
    if (this.leyendo !== null) {
      this.pasos.cerrar(this.leyendo);
      this.leyendo = null;
      this.buscando = this.pasos.abrir(BUSCANDO);
    }
    this.texto += parte;
    const donde = this.texto.indexOf('"categorias"');
    if (donde === -1) {
      if (this.texto.length <= LARGO_INDICE) return POQUITO;
      this.texto = '';
      return null;
    }
    const indice = leerIndice(this.texto.slice(0, donde));
    this.texto = '';
    if (indice) {
      this.secciones = indice.secciones;
      this.pasos.cerrar(this.buscando, encontre(indice.secciones));
      this.anotando = this.pasos.abrir(anotando(indice.productos));
    } else {
      this.pasos.cerrar(this.buscando);
      this.anotando = this.pasos.abrir(anotando(null));
    }
    return null;
  }

  // Con lo que de verdad quedó después de la revisión.
  terminar(secciones: number, productos: number, dudas: number): void {
    if (this.leyendo !== null) this.pasos.cerrar(this.leyendo);
    if (this.buscando === null) this.buscando = this.pasos.abrir(BUSCANDO);
    if (this.anotando === null) {
      this.pasos.cerrar(this.buscando, encontre(secciones));
      this.anotando = this.pasos.abrir(anotando(productos));
    } else if (this.secciones !== secciones) {
      this.pasos.cerrar(this.buscando, encontre(secciones));
    }
    this.pasos.cerrar(this.anotando, anotando(productos).listo);
    if (dudas) {
      const marcando = this.pasos.abrir({ icono: 'alerta', texto: 'Marcando las dudas…', listo: `Marqué ${cuantos(dudas, 'duda', 'dudas')}` });
      this.pasos.cerrar(marcando);
    }
  }
}

// El índice que escribe primero el modelo: cuántas secciones y cuántos productos en total.
function leerIndice(inicio: string): { secciones: number; productos: number } | null {
  const llave = inicio.indexOf('"secciones"');
  const abre = inicio.indexOf('[', llave);
  const cierra = inicio.lastIndexOf(']');
  if (llave === -1 || abre === -1 || cierra < abre) return null;
  try {
    const secciones: unknown = JSON.parse(inicio.slice(abre, cierra + 1));
    if (!Array.isArray(secciones) || !secciones.length) return null;
    let productos = 0;
    for (const s of secciones as { productos?: unknown }[]) {
      if (!Number.isInteger(s?.productos) || (s.productos as number) < 0) return null;
      productos += s.productos as number;
    }
    return productos > 0 ? { secciones: secciones.length, productos } : null;
  } catch {
    return null;
  }
}
