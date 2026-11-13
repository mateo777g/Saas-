// Los esqueletos del menú digital («Tu menú en línea», 12 nov 2026, el developer: «el menú digital, ¿no debería de
// tener esqueletos?»; maqueta UDArhiEZceT7rmSKxqRA5r v59, «TU CLIENTE ABRE TU MENÚ»). Mientras llega menu_publico,
// bloques que laten. La primera vez va uno general en blanco y gris, porque todavía no sabe sus formas ni su color;
// al regresar, el de su menú, que este navegador recuerda: se mide del menú ya armado (como esqueletoDelMenu de la
// maqueta) y se guarda por slug. Solo se guardan rectángulos y colores, nunca lo que dice el menú.
//
// Un bloque en el lugar y del tamaño de cada cosa que se ve: cada foto, ícono y botón con fondo (con sus esquinas;
// una foto sin esquinas toma las de la caja que la recorta, como el cartel), y cada renglón de texto, una raya de 12
// del largo de lo escrito. Lo que flota con su fondo tapa lo de debajo. La barra va de su color, y sus bloques, de un
// tono de sus letras. La barra de abajo (Menú · Pedido · Asistente) se mide aparte, pegada abajo, porque el alto de
// la pantalla cambia (la barra del navegador del celular sale y se esconde).

// [x, y, ancho, alto, esquinas] desde la orilla de arriba a la izquierda de la columna del menú; con un 1 al final es
// una tapa (del color del fondo), no un bloque.
export type Pieza = [number, number, number, number, number] | [number, number, number, number, number, 1];

export type Recuerdo = {
  v: 1;
  // El ancho de la columna al medir: con otro ancho (otra pantalla, el celular de lado) sale el general.
  ancho: number;
  fondo: string;
  texto: string;
  barra: { x: number; ancho: number; alto: number; fondo: string; texto: string } | null;
  piezas: Pieza[];
  // La barra de abajo: lo que mide de su orilla de arriba al fondo de la pantalla, y sus piezas desde ahí.
  abajo: { alto: number; piezas: Pieza[] } | null;
};

const llave = (slug: string) => `pidemenu-esqueleto-${slug}`;
const transparente = (c: string) => c === 'transparent' || /rgba\(.*,\s*0\)$/.test(c);
const r1 = (n: number) => Math.round(n * 10) / 10;

export function leerEsqueleto(slug: string): Recuerdo | null {
  try {
    const r = JSON.parse(localStorage.getItem(llave(slug)) ?? 'null') as Recuerdo | null;
    if (!r) return null;
    if (r.v !== 1 || typeof r.ancho !== 'number' || !Array.isArray(r.piezas)) throw new Error('no tiene la forma de un esqueleto');
    return r;
  } catch (error) {
    console.error('[menu] no se pudo leer el esqueleto que este navegador recordaba; sale el general:', error);
    return null;
  }
}

export function guardarEsqueleto(slug: string, r: Recuerdo | null) {
  try {
    if (r) localStorage.setItem(llave(slug), JSON.stringify(r));
    else localStorage.removeItem(llave(slug));
  } catch (error) {
    console.error('[menu] no se pudo recordar el esqueleto del menú:', error);
  }
}

type Caja = [number, number, number, number];

// Mide el menú ya armado. `columna` es la columna del menú, que tiene que estar hasta arriba (sin bajar); `abajo`, la
// barra de abajo si la hay. `alto` es hasta dónde se mide desde arriba.
export function medirEsqueleto(menu: HTMLElement, columna: HTMLElement, abajo: HTMLElement | null, alto: number): Recuerdo {
  const base = columna.getBoundingClientRect();
  const cm = getComputedStyle(menu);

  function medir(raiz: HTMLElement, arriba: number, clip: Caja, conRaiz: boolean): Pieza[] {
    const piezas: Pieza[] = [];
    const rel = (r: { left: number; top: number; width: number; height: number }) => [r.left - base.left, r.top - arriba, r.width, r.height];
    // Cada bloque se recorta a lo que deja ver su caja (la tira de los carteles, las categorías que se deslizan).
    const recorte = (x: number, y: number, w: number, h: number, [cx1, cy1, cx2, cy2]: Caja): Caja | null => {
      const x1 = Math.max(x, cx1), y1 = Math.max(y, cy1), x2 = Math.min(x + w, cx2), y2 = Math.min(y + h, cy2);
      return x2 - x1 < 2 || y2 - y1 < 2 ? null : [x1, y1, x2, y2];
    };
    const bloque = (x: number, y: number, w: number, h: number, radio: number, clip: Caja) => {
      const c = recorte(x, y, w, h, clip);
      if (c) piezas.push([r1(c[0]), r1(c[1]), r1(c[2] - c[0]), r1(c[3] - c[1]), r1(radio)]);
    };
    const tapa = (x: number, y: number, w: number, h: number, radio: number, clip: Caja) => {
      const c = recorte(x, y, w, h, clip);
      if (c) piezas.push([r1(c[0]), r1(c[1]), r1(c[2] - c[0]), r1(c[3] - c[1]), r1(Math.min(radio, (c[2] - c[0]) / 2, (c[3] - c[1]) / 2)), 1]);
    };
    const conFondo = (cs: CSSStyleDeclaration) => parseFloat(cs.borderTopWidth) > 0 || !transparente(cs.backgroundColor);
    const visto = (cs: CSSStyleDeclaration) => cs.visibility !== 'hidden' && cs.display !== 'none' && Number(cs.opacity) > 0.05;
    // Un texto: una raya de 12 por renglón, del largo de lo escrito.
    const rayas = (nodo: Text, clip: Caja) => {
      const rg = document.createRange();
      rg.selectNodeContents(nodo);
      const renglones = new Map<number, { l: number; r: number; t: number; b: number }>();
      for (const r of rg.getClientRects()) {
        if (r.width < 1) continue;
        const k = Math.round(r.top / 4), v = renglones.get(k);
        renglones.set(k, v ? { l: Math.min(v.l, r.left), r: Math.max(v.r, r.right), t: v.t, b: Math.max(v.b, r.bottom) } : { l: r.left, r: r.right, t: r.top, b: r.bottom });
      }
      for (const v of renglones.values()) {
        const [x, y, w, h] = rel({ left: v.l, top: v.t, width: v.r - v.l, height: v.b - v.t });
        bloque(x, y + (h - 12) / 2, w, 12, 6, clip);
      }
    };
    const una = (el: Element, clip: Caja, radioClip: number) => {
      const cs = getComputedStyle(el);
      if (!visto(cs)) return;
      const tag = el.tagName.toLowerCase(), radio = parseFloat(cs.borderTopLeftRadius) || 0;
      const [x, y, w, h] = rel(el.getBoundingClientRect());
      // Lo que queda debajo de lo que se mide no hace falta recorrerlo.
      if (y > clip[3] && cs.position === 'static') return;
      if (tag === 'img' || tag === 'svg' || tag === 'input' || tag === 'textarea' || (tag === 'button' && conFondo(cs))) {
        bloque(x, y, w, h, Math.min(radio || (tag === 'img' && radioClip) || 6, h / 2), clip);
        return;
      }
      if (/absolute|fixed|sticky/.test(cs.position) && conFondo(cs)) tapa(x, y, w, h, radio, clip);
      const recorta = cs.overflowX !== 'visible' || cs.overflowY !== 'visible';
      recorrer(el, recorta ? [Math.max(clip[0], x), Math.max(clip[1], y), Math.min(clip[2], x + w), Math.min(clip[3], y + h)] : clip, recorta && radio ? radio : radioClip);
    };
    const recorrer = (el: Element, clip: Caja, radioClip: number) => {
      for (const h of el.childNodes) {
        if (h.nodeType === Node.TEXT_NODE) {
          if (h.textContent?.trim()) rayas(h as Text, clip);
        } else if (h.nodeType === Node.ELEMENT_NODE) una(h as Element, clip, radioClip);
      }
    };
    if (conRaiz) una(raiz, clip, 0);
    else recorrer(raiz, clip, 0);
    return piezas;
  }

  const piezas = medir(columna, base.top, [0, 0, base.width, alto], false);

  // La barra va de su color (si no es transparente).
  const header = columna.querySelector<HTMLElement>('header.barra');
  let barra: Recuerdo['barra'] = null;
  if (header) {
    const rb = header.getBoundingClientRect(), bs = getComputedStyle(header);
    if (!transparente(bs.backgroundColor))
      barra = { x: r1(rb.left - base.left), ancho: r1(rb.width), alto: r1(rb.bottom - base.top), fondo: bs.backgroundColor, texto: bs.color };
  }

  let deAbajo: Recuerdo['abajo'] = null;
  if (abajo) {
    const ra = abajo.getBoundingClientRect();
    const altoAbajo = innerHeight - ra.top;
    if (ra.height > 0 && altoAbajo > 0) deAbajo = { alto: r1(altoAbajo), piezas: medir(abajo, ra.top, [0, 0, base.width, altoAbajo], true) };
  }

  return { v: 1, ancho: r1(base.width), fondo: cm.backgroundColor, texto: cm.color, barra, piezas, abajo: deAbajo };
}
