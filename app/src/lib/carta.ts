// El menú con IA (27 nov 2026; planes/trabajo/menu-con-ia/): Don Chuy sube las fotos de su carta (hasta 6) o un PDF
// (hasta 6 páginas), con una nota si quiere, y la IA la lee y arma Mi menú. Aquí vive lo que la app necesita:
//  - cuántas cartas le quedan este mes (puedo_leer_carta: 3 al mes, fuera del tope de IA; el 3 lo dice Postgres);
//  - las hojas listas para mandar (2048 px en WebP; el PDF tal cual, con sus páginas contadas aquí);
//  - leerla con el Worker (POST /agente/carta, multipart, por partes como una pregunta: worker.md);
//  - lo que se guarda con la plática (la lectura, con lo que Don Chuy corrige; nunca las fotos) y subirla
//    (subir_a_mi_menu: todo o nada, solo agrega).
// Ningún número sale de aquí: los precios los lee la IA, los revisa el Worker y los guarda Postgres.
import { leerPorPartes, type Oyentes } from './agente';
import { Fallo, mensajeDeError } from './errores';
import { convertirHoja } from './fotos';
import type { Menu } from './menu';
import { vienePorPartes } from './pasos';
import { supabase } from './supabase';
import { abrirWorker } from './worker';

export const MAXIMO_HOJAS = 6;
export const MAXIMO_PAGINAS = 6;
export const MAXIMO_NOTA = 300;
// Lo mismo que acepta el Worker (worker.md, «Qué entra»): cada foto ya achicada, hasta 5 MB; el PDF, hasta 20 MB.
const MAXIMO_FOTO = 15 * 1024 * 1024;
const MAXIMO_PDF = 20 * 1024 * 1024;

// ─── Cuántas quedan ─────────────────────────────────────────────────────────────────────────

export type CartasDelMes = { puede: boolean; quedan: number; de: number; vuelve: string };

export async function leerCartasDelMes(restauranteId: string): Promise<CartasDelMes> {
  const { data, error } = await supabase.rpc('puedo_leer_carta', { p_restaurante_id: restauranteId });
  if (error) throw error;
  return data as CartasDelMes;
}

// ─── Las hojas ──────────────────────────────────────────────────────────────────────────────

// Una hoja elegida: la foto tal cual (para la miniatura) o el PDF con sus páginas. Solo viven mientras la pestaña
// está abierta.
export type Hoja = { tipo: 'foto'; archivo: File; url: string } | { tipo: 'pdf'; archivo: File; paginas: number };

export const esFoto = (a: File) => a.type.startsWith('image/');
export const esPdf = (a: File) => a.type === 'application/pdf' || /\.pdf$/i.test(a.name);

// Las páginas de un PDF, con pdf-lib (el mismo del «Reporte en PDF»; se trae solo aquí). null si no se pudo abrir.
async function contarPaginas(archivo: File): Promise<number | null> {
  try {
    const { PDFDocument } = await import('pdf-lib');
    const pdf = await PDFDocument.load(await archivo.arrayBuffer(), { ignoreEncryption: true, updateMetadata: false });
    return pdf.getPageCount();
  } catch (error) {
    console.error('[carta] no se pudo abrir el PDF para contar sus páginas:', error);
    return null;
  }
}

// Lo que se eligió en «Tu carta»: fotos (hasta completar 6) o un PDF, nunca juntos. Regresa las hojas nuevas y,
// si algo no entró, por qué (para su caja de error).
export async function elegirHojas(
  archivos: File[],
  yaHay: Hoja[],
): Promise<{ hojas: Hoja[]; problema: string | null }> {
  const pdfs = archivos.filter(esPdf);
  const fotos = archivos.filter((a) => esFoto(a) && !esPdf(a));
  if (!pdfs.length && !fotos.length) return { hojas: [], problema: 'Elige fotos de tu carta (JPG o PNG) o un PDF.' };
  if (pdfs.length) {
    if (pdfs.length > 1 || fotos.length || yaHay.length) {
      return { hojas: [], problema: 'Manda las fotos o un PDF, no los dos. Quita las hojas para subir un PDF.' };
    }
    const pdf = pdfs[0];
    if (pdf.size > MAXIMO_PDF) return { hojas: [], problema: 'Tu PDF pesa más de 20 MB. Manda uno más ligero o fotos.' };
    const paginas = await contarPaginas(pdf);
    if (paginas === null) return { hojas: [], problema: 'No pudimos abrir ese PDF. Prueba con otro o manda fotos.' };
    if (paginas > MAXIMO_PAGINAS) {
      return { hojas: [], problema: `Tu PDF tiene ${paginas} páginas: caben ${MAXIMO_PAGINAS}. Manda las hojas como fotos.` };
    }
    return { hojas: [{ tipo: 'pdf', archivo: pdf, paginas }], problema: null };
  }
  if (yaHay.some((h) => h.tipo === 'pdf')) return { hojas: [], problema: 'Manda las fotos o un PDF, no los dos.' };
  const pesadas = fotos.filter((f) => f.size > MAXIMO_FOTO);
  const buenas = fotos.filter((f) => f.size <= MAXIMO_FOTO).slice(0, MAXIMO_HOJAS - yaHay.length);
  const hojas: Hoja[] = buenas.map((archivo) => ({ tipo: 'foto', archivo, url: URL.createObjectURL(archivo) }));
  if (pesadas.length) return { hojas, problema: 'Una foto pesa más de 15 MB. Elige una más ligera.' };
  return { hojas, problema: null };
}

export function soltarHojas(hojas: Hoja[]) {
  for (const h of hojas) if (h.tipo === 'foto') URL.revokeObjectURL(h.url);
}

// «Lee mi carta · 3 hojas», «Lee mi carta · 1 hoja» o «Lee mi carta · PDF de 3 páginas».
export function textoDeHojas(cuantas: number, pdf: boolean): string {
  if (pdf) return `Lee mi carta · PDF de ${cuantas} ${cuantas === 1 ? 'página' : 'páginas'}`;
  return `Lee mi carta · ${cuantas} ${cuantas === 1 ? 'hoja' : 'hojas'}`;
}

// ─── La lectura ─────────────────────────────────────────────────────────────────────────────

// Las dudas llegan como claves (worker.md); el texto es de la app. «Falta el precio» es cuando alguien lo borró.
export type Duda = 'sin_precio' | 'sin_nombre' | 'revisa_precio';
export const TEXTO_DUDA: Record<Duda | 'falta_precio', string> = {
  sin_precio: 'No se lee el precio',
  sin_nombre: 'No se lee el nombre',
  revisa_precio: 'Revisa este precio',
  falta_precio: 'Falta el precio',
};

// Un producto como se guarda con la plática: lo leído y lo que Don Chuy corrigió. El precio va como texto, como se
// escribe en la revisión («2,500»); `sube` sin poner = lo de siempre (palomeado, salvo «Ya lo tienes»); `arreglada`
// = ya tocó la duda que no impide subir.
export type ProductoLeido = {
  nombre: string;
  descripcion: string;
  precio: string;
  duda: Duda | null;
  sube?: boolean;
  arreglada?: boolean;
};
export type CategoriaLeida = { nombre: string; icono: string; productos: ProductoLeido[] };

// Lo que vive en el turno de la plática. `hojas` = cuántas fotos o páginas; `subida`, lo que de verdad subió.
export type CartaGuardada = {
  hojas: number;
  pdf?: boolean;
  nota?: string;
  categorias: CategoriaLeida[];
  subida?: { productos: number; nuevas: string[]; existentes: string[] };
};

// El precio en la revisión: «25», «22.50», «2,500».
export function textoPrecio(n: number | null): string {
  if (n === null) return '';
  return n.toLocaleString('en-US', { minimumFractionDigits: Number.isInteger(n) ? 0 : 2, maximumFractionDigits: 2 });
}

export function precioDeTexto(t: string): number | null {
  const limpio = t.trim().replace(/,/g, '');
  if (!/^(\d+\.?\d*|\.\d+)$/.test(limpio)) return null;
  return Math.round(Number(limpio) * 100) / 100;
}

function aLectura(crudo: unknown): CategoriaLeida[] {
  const categorias = (crudo as { categorias?: unknown })?.categorias;
  if (!Array.isArray(categorias)) throw new Error('la carta no trae sus categorías');
  return categorias.map((c) => ({
    nombre: String(c?.nombre ?? ''),
    icono: String(c?.icono ?? 'comida'),
    productos: (Array.isArray(c?.productos) ? c.productos : []).map(
      (p: { nombre?: unknown; descripcion?: unknown; precio?: unknown; duda?: unknown }) => ({
        nombre: String(p?.nombre ?? ''),
        descripcion: typeof p?.descripcion === 'string' ? p.descripcion : '',
        precio: textoPrecio(typeof p?.precio === 'number' ? p.precio : null),
        duda: p?.duda === 'sin_precio' || p?.duda === 'sin_nombre' || p?.duda === 'revisa_precio' ? p.duda : null,
      }),
    ),
  }));
}

export type Lectura =
  | { tipo: 'leida'; respuesta: string; categorias: CategoriaLeida[]; puede: boolean; pasos: string[] }
  | { tipo: 'sin_cartas'; cartas: CartasDelMes };

// Manda las hojas al Worker y lee su respuesta por partes, con sus pasos, como una pregunta. Las fotos se achican
// aquí a 2048 px; el PDF va tal cual. Lo que el Worker rechaza antes de empezar llega en JSON normal.
export async function leerCarta(
  restauranteId: string,
  hojas: Hoja[],
  nota: string,
  oyentes: Oyentes,
): Promise<Lectura> {
  const forma = new FormData();
  forma.append('restaurante', restauranteId);
  if (nota.trim()) forma.append('nota', nota.trim().slice(0, MAXIMO_NOTA));
  for (const [i, h] of hojas.entries()) {
    if (h.tipo === 'pdf') forma.append('hoja', h.archivo, 'carta.pdf');
    else {
      let webp: Blob;
      try {
        webp = await convertirHoja(h.archivo);
      } catch (error) {
        console.error('[carta] no se pudo preparar la hoja', i + 1, error);
        throw new Fallo(`No pudimos abrir la hoja ${i + 1}. Quítala y prueba con otra foto.`);
      }
      oyentes.senal.throwIfAborted();
      forma.append('hoja', webp, `hoja-${i + 1}.webp`);
    }
  }
  const respuesta = await abrirWorker('carta', '/agente/carta', forma, oyentes.senal);
  if (!vienePorPartes(respuesta)) {
    const r = await respuesta.json().catch((error) => {
      if (oyentes.senal.aborted) throw error;
      return null;
    });
    if (r?.puede === false) return { tipo: 'sin_cartas', cartas: r as CartasDelMes };
    console.error('[carta] el Worker contestó algo que no se entiende:', r);
    throw new Error('El Worker no mandó la lectura');
  }
  const { fin, pasos } = await leerPorPartes(respuesta, oyentes);
  if (typeof fin.respuesta !== 'string') {
    console.error('[carta] el Worker contestó algo que no se entiende:', fin);
    throw new Error('El Worker no mandó la lectura');
  }
  return { tipo: 'leida', respuesta: fin.respuesta, categorias: aLectura(fin.carta), puede: fin.puede !== false, pasos };
}

// ─── La revisión y «Subir a mi menú» ────────────────────────────────────────────────────────

const igual = (a: string, b: string) => a.trim().toLocaleLowerCase('es') === b.trim().toLocaleLowerCase('es');

// «Ya la tienes» y «Ya lo tienes», con lo que la app lee de Mi menú: la categoría existe con el mismo nombre (sin
// contar mayúsculas), y el producto también, dentro de ella.
export function comparar(menu: Menu, c: CategoriaLeida): { existe: boolean; tiene: boolean[] } {
  const suya = menu.categorias.find((x) => igual(x.nombre, c.nombre));
  if (!suya) return { existe: false, tiene: c.productos.map(() => false) };
  const nombres = menu.productos.filter((p) => p.categoria_id === suya.id).map((p) => p.nombre);
  return { existe: true, tiene: c.productos.map((p) => nombres.some((n) => igual(n, p.nombre))) };
}

export const sube = (p: ProductoLeido, tiene: boolean) => p.sube ?? !tiene;

// La duda que se ve ahora: la de la IA mientras no se arregle, o «Falta el precio» si alguien lo borró.
export function dudaAhora(p: ProductoLeido): keyof typeof TEXTO_DUDA | null {
  const falta = !p.precio.trim();
  if (p.duda === 'sin_precio' && falta) return 'sin_precio';
  if (p.duda && p.duda !== 'sin_precio' && !p.arreglada) return p.duda;
  return falta ? 'falta_precio' : null;
}

export type SubidaAMiMenu = { categorias_nuevas: number; productos: number };

// Todo o nada (subir_a_mi_menu): solo lo palomeado, en el orden de la carta; una categoría sin nada que subir no va.
export async function subirAMiMenu(
  restauranteId: string,
  categorias: { nombre: string; icono: string; productos: { nombre: string; descripcion: string; precio: number }[] }[],
): Promise<SubidaAMiMenu> {
  const { data, error } = await supabase.rpc('subir_a_mi_menu', {
    p_restaurante_id: restauranteId,
    p_categorias: categorias.map((c) => ({
      nombre: c.nombre.trim(),
      icono: c.icono,
      productos: c.productos.map((p) => ({
        nombre: p.nombre.trim(),
        descripcion: p.descripcion.trim() || null,
        precio: p.precio,
      })),
    })),
  });
  if (error) {
    console.error('[carta] no se pudo subir la carta a Mi menú:', error);
    throw new Fallo(mensajeDeError(error));
  }
  return data as SubidaAMiMenu;
}

// «Tacos y Bebidas», «Tacos, Tortas y Bebidas», «Tacos, Tortas y 3 más».
export function lista(nombres: string[]): string {
  if (nombres.length <= 1) return nombres[0] ?? '';
  if (nombres.length > 3) return `${nombres.slice(0, 2).join(', ')} y ${nombres.length - 2} más`;
  return `${nombres.slice(0, -1).join(', ')} y ${nombres[nombres.length - 1]}`;
}

// Lo que dice la tarjeta ya subida: «Tortas es nueva; lo demás entró en Tacos y Bebidas. Sin fotos todavía.»
export function textoSubida(s: NonNullable<CartaGuardada['subida']>): string {
  const n = s.nuevas;
  const nuevas =
    n.length === 0 ? '' : n.length === 1 ? `${n[0]} es nueva` : n.length <= 3 ? `${lista(n)} son nuevas` : `Las ${n.length} categorías son nuevas`;
  if (nuevas && s.existentes.length) return `${nuevas}; lo demás entró en ${lista(s.existentes)}. Sin fotos todavía.`;
  if (nuevas) return `${nuevas}. Sin fotos todavía.`;
  return `Todo entró en ${lista(s.existentes)}. Sin fotos todavía.`;
}
