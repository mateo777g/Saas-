// El PDF del reporte por dentro (maqueta KhJcfGHEMiKoakTbNr9cgy, planes/maquetas/reporte-pdf.html): hoja carta,
// en blanco y negro, solo con el nombre del restaurante. Todo va en puntos, medido de la maqueta. Una tabla
// que cabe entera en una hoja no se parte; la que no cabe en ninguna sigue en la otra y repite sus títulos.
// Este archivo y lo que importa solo se bajan al picar «Descargar» (reporte.ts).
import fontkit from '@pdf-lib/fontkit';
import { PDFDocument, popGraphicsState, pushGraphicsState, rgb, setCharacterSpacing, type PDFFont, type PDFPage } from 'pdf-lib';
import jakarta400 from '@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-400-normal.woff?url';
import jakarta600 from '@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-600-normal.woff?url';
import jakarta700 from '@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-700-normal.woff?url';
import jakarta800 from '@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-800-normal.woff?url';
import mono400 from '@fontsource/jetbrains-mono/files/jetbrains-mono-latin-400-normal.woff?url';
import mono500 from '@fontsource/jetbrains-mono/files/jetbrains-mono-latin-500-normal.woff?url';
import mono700 from '@fontsource/jetbrains-mono/files/jetbrains-mono-latin-700-normal.woff?url';

export type Fila = { celdas: string[]; nota?: string; suave?: boolean };
export type Tabla = {
  titulo: string;
  columnas: string[]; // la primera es de texto; las demás, números a la derecha
  filas: Fila[];
  total?: string[];
  nota?: string;
  vacio?: string; // lo que dice si no hay filas; sin esto, la tabla no sale
};
export type DatosPdf = {
  restaurante: string;
  titulo: string;
  fechas: string;
  armado: string;
  archivo: string;
  cifras: { etiqueta: string; valor: string }[];
  tablas: Tabla[];
};

// La hoja, en puntos, con y desde abajo, como cuenta el PDF.
const ANCHO_HOJA = 612;
const ALTO_HOJA = 792;
const IZQUIERDA = 48;
const DERECHA = ANCHO_HOJA - 48;
const ARRIBA = ALTO_HOJA - 42;
const LINEA_PIE = 53.27;
const BASE_PIE = 36.08;
const LIMITE = LINEA_PIE + 6; // hasta aquí baja lo de la hoja
const ANCHO = DERECHA - IZQUIERDA;
const ANCHO_NUMERO = 84;

// Lo que mide cada renglón de una tabla.
const ALTO_TITULO = 13.13; // el título con su margen
const ALTO_CABEZA = 17.18;
const ALTO_FILA = 19.76;
const ALTO_RENGLON = 12.825; // un renglón más de texto
const ALTO_NOTA_FILA = 10.54;
const ALTO_TOTAL = 20.29;
const ALTO_NOTA = 14.8;
const ENTRE_TABLAS = 15;
// Dónde va cada letra dentro de su renglón.
const BASE_TITULO = 7.76;
const BASE_CABEZA = 11.66;
const BASE_FILA = 13.39;
const BASE_TOTAL = 14.29;
const BASE_NOTA = 12.66;
const BASE_NOTA_FILA = 24.87;

const TINTA = rgb(11 / 255, 11 / 255, 11 / 255);
const SUAVE = rgb(95 / 255, 95 / 255, 90 / 255);
const TENUE = rgb(139 / 255, 139 / 255, 133 / 255);
const LINEA = rgb(0.9, 0.9, 0.9);
const LINEA_FUERTE = rgb(0.72, 0.72, 0.72);

async function bytes(url: string): Promise<ArrayBuffer> {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`no se pudo bajar la letra ${url}: ${r.status}`);
  return r.arrayBuffer();
}

export async function armarPdf(d: DatosPdf): Promise<Blob> {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const cargar = async (url: string) => pdf.embedFont(await bytes(url), { subset: true });
  const [normal, seminegra, negrita, negra, numero, etiqueta, numeroFuerte] = await Promise.all(
    [jakarta400, jakarta600, jakarta700, jakarta800, mono400, mono500, mono700].map(cargar),
  );

  // Solo su nombre: nada de quién armó el archivo.
  pdf.setTitle(d.archivo.replace(/\.pdf$/, ''));
  pdf.setAuthor(d.restaurante);
  pdf.setCreator(d.restaurante);
  pdf.setProducer(d.restaurante);

  // Lo que la letra no tiene (un emoji en el nombre de un producto) se quita: si no, sale un cuadrito.
  const tiene = new Map<PDFFont, Set<number>>();
  function limpiar(texto: string, fuente: PDFFont): string {
    let juego = tiene.get(fuente);
    if (!juego) {
      juego = new Set(fuente.getCharacterSet());
      tiene.set(fuente, juego);
    }
    const j = juego;
    return [...texto].filter((c) => j.has(c.codePointAt(0) as number)).join('').trim();
  }

  const anchoDe = (t: string, f: PDFFont, s: number, espacio = 0) => {
    const limpio = limpiar(t, f);
    return f.widthOfTextAtSize(limpio, s) + espacio * [...limpio].length;
  };

  // Un texto largo en varios renglones, por palabras.
  function partir(texto: string, fuente: PDFFont, tamano: number, ancho: number): string[] {
    const renglones: string[] = [];
    let actual = '';
    for (const palabra of limpiar(texto, fuente).split(/\s+/)) {
      const con = actual ? `${actual} ${palabra}` : palabra;
      if (actual && anchoDe(con, fuente, tamano) > ancho) {
        renglones.push(actual);
        actual = palabra;
      } else {
        actual = con;
      }
    }
    if (actual) renglones.push(actual);
    return renglones.length ? renglones : [''];
  }

  let hoja: PDFPage = pdf.addPage([ANCHO_HOJA, ALTO_HOJA]);
  let y = ARRIBA;

  function hojaNueva() {
    hoja = pdf.addPage([ANCHO_HOJA, ALTO_HOJA]);
    y = ARRIBA;
  }

  function escribir(
    texto: string,
    x: number,
    base: number,
    fuente: PDFFont,
    tamano: number,
    color = TINTA,
    espacio = 0,
  ) {
    const limpio = limpiar(texto, fuente);
    if (!limpio) return;
    if (espacio) hoja.pushOperators(pushGraphicsState(), setCharacterSpacing(espacio));
    hoja.drawText(limpio, { x, y: base, font: fuente, size: tamano, color });
    if (espacio) hoja.pushOperators(setCharacterSpacing(0), popGraphicsState());
  }

  const raya = (alto: number, grosor: number, color = LINEA) =>
    hoja.drawLine({ start: { x: IZQUIERDA, y: alto }, end: { x: DERECHA, y: alto }, thickness: grosor, color });

  // ─── La cabeza ─────────────────────────────────────────────────────────────────────────

  for (const r of partir(d.restaurante, negra, 21, ANCHO)) {
    escribir(r, IZQUIERDA, y - 20.64, negra, 21, TINTA, -0.3);
    y -= 24.14;
  }
  y -= 3;
  escribir(d.titulo, IZQUIERDA, y - 13, negrita, 12);
  y -= 17.19;
  escribir(d.fechas, IZQUIERDA, y - 10.83, normal, 10, SUAVE);
  y -= 25.49;
  raya(y - 0.6, 1.2, TINTA);
  y -= 15.19;

  // Las cifras, en un renglón, pegadas abajo. Si son números muy grandes, se juntan para caber.
  const ETIQUETA = 6.8;
  const ESPACIO_ETIQUETA = 0.54;
  const medidas = d.cifras.map((c, i) => {
    const et = c.etiqueta.toLocaleUpperCase('es-MX');
    const [f, s, espacio] = i === 0 ? ([negra, 19, -0.3] as const) : ([negrita, 13, 0] as const);
    return { et, valor: c.valor, f, s, espacio, ancho: Math.max(anchoDe(et, numero, ETIQUETA, ESPACIO_ETIQUETA), anchoDe(c.valor, f, s, espacio)) };
  });
  const suma = medidas.reduce((n, m) => n + m.ancho, 0);
  const hueco = Math.min(22, medidas.length > 1 ? (ANCHO - suma) / (medidas.length - 1) : 22);
  let x = IZQUIERDA;
  medidas.forEach((m, i) => {
    escribir(m.et, x, y - (i === 0 ? 7.04 : 10.39), numero, ETIQUETA, TENUE, ESPACIO_ETIQUETA);
    escribir(m.valor, x, y - (i === 0 ? 29.37 : 28.6), m.f, m.s, TINTA, m.espacio);
    x += m.ancho + hueco;
  });
  y -= 50.06;

  // ─── Las tablas ────────────────────────────────────────────────────────────────────────

  const N = 8.8; // los números
  const T = 9.5; // el texto
  const C = 7.8; // la nota de una fila

  function medirFila(f: Fila, ancho: number) {
    const renglones = partir(f.celdas[0], normal, T, ancho);
    const notas = f.nota ? partir(f.nota, normal, C, ancho) : [];
    const alto = ALTO_FILA + (renglones.length - 1) * ALTO_RENGLON + (notas.length ? 0.5 + notas.length * ALTO_NOTA_FILA : 0);
    return { renglones, notas, alto };
  }

  function dibujarTitulo(t: Tabla) {
    escribir(t.titulo.toLocaleUpperCase('es-MX'), IZQUIERDA, y - BASE_TITULO, etiqueta, 7.5, SUAVE, 0.75);
    y -= ALTO_TITULO;
  }

  function dibujarCabeza(t: Tabla, xs: number[]) {
    dibujarTitulo(t);
    escribir(t.columnas[0], IZQUIERDA, y - BASE_CABEZA, seminegra, 8, SUAVE);
    t.columnas.slice(1).forEach((c, i) => {
      escribir(c, xs[i] - anchoDe(c, seminegra, 8), y - BASE_CABEZA, seminegra, 8, SUAVE);
    });
    y -= ALTO_CABEZA;
    raya(y, 0.8, LINEA_FUERTE);
  }

  function dibujarTabla(t: Tabla) {
    const numeros = t.columnas.length - 1;
    const anchoTexto = ANCHO - numeros * ANCHO_NUMERO;
    // La orilla derecha de cada número.
    const xs = Array.from({ length: numeros }, (_, i) => DERECHA - (numeros - 1 - i) * ANCHO_NUMERO);
    const hayFilas = t.filas.length > 0;

    const altos = t.filas.map((f) => medirFila(f, anchoTexto));
    const altoFilas = altos.reduce((n, a) => n + a.alto, 0);
    const altoNota = t.nota ? ALTO_NOTA : 0;
    const altoTotal = t.total && hayFilas ? ALTO_TOTAL : 0;
    const altoEntero = hayFilas ? ALTO_TITULO + ALTO_CABEZA + altoFilas + altoTotal + altoNota : ALTO_TITULO + ALTO_RENGLON;

    // Si cabe entera en una hoja, no se parte.
    if (altoEntero > y - LIMITE && altoEntero <= ARRIBA - LIMITE) hojaNueva();

    if (!hayFilas) {
      dibujarTitulo(t);
      escribir(t.vacio ?? '', IZQUIERDA, y - 10.29, normal, T, SUAVE);
      y -= ALTO_RENGLON + ENTRE_TABLAS;
      return;
    }

    // Que no quede el puro título al final de la hoja.
    if (ALTO_TITULO + ALTO_CABEZA + altos[0].alto > y - LIMITE) hojaNueva();
    dibujarCabeza(t, xs);

    t.filas.forEach((f, i) => {
      const a = altos[i];
      if (a.alto > y - LIMITE) {
        hojaNueva();
        dibujarCabeza(t, xs);
      }
      const color = f.suave ? SUAVE : TINTA;
      a.renglones.forEach((r, k) => {
        escribir(r, IZQUIERDA, y - BASE_FILA - k * ALTO_RENGLON, normal, T, color);
      });
      const extra = (a.renglones.length - 1) * ALTO_RENGLON;
      a.notas.forEach((r, k) => {
        escribir(r, IZQUIERDA, y - BASE_NOTA_FILA - extra - k * ALTO_NOTA_FILA, normal, C, SUAVE);
      });
      f.celdas.slice(1).forEach((c, j) => {
        escribir(c, xs[j] - anchoDe(c, numero, N), y - BASE_FILA, numero, N, color);
      });
      y -= a.alto;
      raya(y, 0.5);
    });

    if (t.total) {
      if (altoTotal > y - LIMITE) {
        hojaNueva();
        dibujarCabeza(t, xs);
      }
      raya(y, 0.8, LINEA_FUERTE);
      escribir(t.total[0], IZQUIERDA, y - BASE_TOTAL, negrita, T);
      t.total.slice(1).forEach((c, j) => {
        escribir(c, xs[j] - anchoDe(c, numeroFuerte, N), y - BASE_TOTAL, numeroFuerte, N);
      });
      y -= altoTotal;
    }
    if (t.nota) {
      if (altoNota > y - LIMITE) hojaNueva();
      escribir(t.nota, IZQUIERDA, y - BASE_NOTA, normal, 8, SUAVE);
      y -= altoNota;
    }
    y -= ENTRE_TABLAS;
  }

  for (const t of d.tablas) {
    if (t.filas.length || t.vacio) dibujarTabla(t);
  }

  // ─── El pie de cada hoja ───────────────────────────────────────────────────────────────

  const hojas = pdf.getPages();
  hojas.forEach((h, i) => {
    hoja = h;
    raya(LINEA_PIE, 0.5);
    escribir(d.armado, IZQUIERDA, BASE_PIE, normal, C, TENUE);
    const cuenta = `Hoja ${i + 1} de ${hojas.length}`;
    escribir(cuenta, DERECHA - anchoDe(cuenta, normal, C), BASE_PIE, normal, C, TENUE);
  });

  const salida = await pdf.save();
  return new Blob([salida as BlobPart], { type: 'application/pdf' });
}
