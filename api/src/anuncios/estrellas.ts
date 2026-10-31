// Estilo 14 · Estrellas (estrellas-blancas.txt): una mano sostiene desde abajo un platito de papel con
// los productos de Don Chuy (de 1 a 3), delante de dos estrellas blancas de picos sobre papel azul rey,
// con un titular blanco redondo, una línea a mano alrededor y destellos. Arriba, un párrafo en itálica:
// la descripción de Mi menú y «Así se come en <restaurante>.». Su color pinta el fondo; lo blanco se queda.
import { AUTENTICO, comoEs, contactoDelCartel, CUANTOS, fotografia, letraSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// El de la referencia, sacado con Pillow.
const TONOS = { fondo: '#1F4F9B' };
const BLANCO = '#FEFEFC';

export const estrellas: Estilo = {
  clave: 'estrellas',
  maximo: 3,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: true,
  vacio: '#nombre',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const n = a.productos.length;
  const uno = n === 1;
  const p = a.productos[0];
  const color = a.color;
  const t = pintar(color, TONOS);
  const azul = color ? nombreDelColor(color) : 'royal-blue';
  const titular = mayus(a.mensaje ?? p.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, false) : null;
  const lo = uno ? 'the product' : 'the products';
  const LO = uno ? 'THE PRODUCT' : 'THE PRODUCTS';
  // Con un color claro, lo que va sobre el fondo se escribe oscuro; el titular del post va sobre la
  // comida y se queda blanco.
  const sobreFondo = letraSobre(t.fondo);
  const enFondo = sobreFondo === 'white' ? `white ${BLANCO}` : sobreFondo;
  // El párrafo: la descripción del producto 1 y siempre «Así se come en <restaurante>.».
  const descripcion = p.descripcion?.trim();
  const conPunto = descripcion ? (/[.!?…]$/u.test(descripcion) ? descripcion : `${descripcion}.`) : null;
  const parrafo = [conPunto, `Así se come en ${a.restaurante.nombre}.`].filter(Boolean).join(' ');
  const breve = !conPunto;

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'RIGHT HALF, FROM ABOUT 50% TO 95% OF THE WIDTH:',
        `The hand rising from the bottom edge, at about 72% of the width, holding the plate with ${lo}, from about 15% of the height down to the bottom edge.`,
        `BEHIND ${LO}:`,
        `Two large white starbursts: one behind the upper left of ${lo}, one behind the lower right.`,
        'LEFT HALF, FROM ABOUT 6% TO 46% OF THE WIDTH, ALIGNED LEFT:',
        'Three small sparkles in a row at about 10% of the height.',
        'The bold headline, in one or two lines, from about 18% to 52% of the height.',
        `The short italic ${breve ? 'line' : 'paragraph'} below it, from about 58% to 76% of the height.`,
        ...(contacto ? ['AT ABOUT 86% TO 94% OF THE HEIGHT, on the left: the phone and the address, small.'] : []),
        'The composition must feel lively, bold, and clearly designed.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP, FROM ABOUT 3% TO 16% OF THE HEIGHT:',
        `Three small sparkles in a row, and below them the short italic ${breve ? 'line' : 'paragraph'}, centered.`,
        'CENTER AND BOTTOM, FROM ABOUT 30% TO THE BOTTOM EDGE:',
        `The hand rising from the bottom edge, at the center, holding the plate with ${lo}, which ${uno ? 'fills' : 'fill'} the middle of the poster.`,
        `BEHIND ${LO}:`,
        `Two large white starbursts: one behind the upper left of ${lo}, one behind the lower right.`,
        `OVER ${LO}, AT ABOUT 55% OF THE HEIGHT:`,
        'The bold headline, in one or two lines.',
        'The composition must feel lively, bold, centered, and clearly designed.',
      ];

  const producto = uno
    ? [`Feature ONE genuine product on a small round white paper plate lined with a sheet of white wax paper, the way a Mexican restaurant serves it: ${comoEs(p)}`]
    : [
        `Feature ONE order of ${CUANTOS[n]} genuine products, side by side, slightly overlapping, on a small round white paper plate lined with a sheet of white wax paper, the way a Mexican restaurant serves them, product 1 ${n === 3 ? 'at the center' : 'on the left'}, slightly in front:`,
        ...a.productos.map((x, i) => `* Product ${i + 1}: ${comoEs(x)}`),
      ];

  const secciones = [
    `STYLE_17 — ${(color ? nombreDelColor(color) : 'blue').toUpperCase()} STARBURST HAND`,
    `Playful Graphic Food Advertising — Hand-Held ${uno ? 'Product' : 'Order'} ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally designed ${QUE_ES[a.formato]} featuring ${uno ? 'one product' : `an order of ${CUANTOS[n]} products`} on a small round paper plate, held up from below by a real human hand, in front of two large white spiky starbursts on a ${azul} paper background, with a bold rounded headline ${cartel ? 'on the left' : `over ${lo}`}, a thin hand-drawn white line around ${uno ? 'it' : 'them'}, small white sparkles, and a short italic ${breve ? 'line' : 'paragraph'} ${cartel ? 'below the headline' : 'at the top'}.`,
    `THIS IS A PLAYFUL, ENERGETIC GRAPHIC ${cartel ? 'BANNER' : 'POSTER'}: flat graphic shapes and doodles layered with one real photographed hand and ${uno ? 'product' : 'order'}.`,
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. BACKGROUND',
    `Use a ${azul} background, approximately ${t.fondo}, covering the whole canvas.`,
    'It has a very subtle printed-paper feel: a few faint soft creases and a very fine halftone grain, barely visible.',
    'No gradients.',
    'No patterns.',
    'No strong textures.',
    '3. THE TWO WHITE STARBURSTS',
    `Two large, flat, white starbursts, approximately ${BLANCO}, each with about 10 long, sharp, slightly irregular spiky points, like a comic-style burst.`,
    `The first sits behind the upper-left part of ${lo} and reaches toward ${cartel ? 'the center of the banner' : 'the left edge'}.`,
    `The second sits behind the lower-right part of ${lo} and reaches toward the right edge.`,
    `Both are partly hidden by ${lo} and the hand.`,
    'They are perfectly flat: no outline, no gradient, no shadow, no 3D effect.',
    `4. HERO ${uno ? 'PRODUCT' : 'PRODUCTS'}`,
    ...producto,
    'If a product is a drink, it stands upright on the plate in its own glass or cup.',
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    `The plate is tilted gently toward the viewer, seen from about 25 degrees above, so the top and the filling of ${uno ? 'the product are' : 'every product are'} clearly visible.`,
    `The plate with ${lo} is large: about ${cartel ? '38% of the banner width' : '70% of the poster width'}.`,
    ...(uno ? ['With a single product, draw it larger, filling the plate, as the clear hero.'] : []),
    '5. THE HAND',
    `One real human hand rises from the bottom edge of the ${pieza}, ${cartel ? 'at about 72% of its width' : 'at the center'}, holding the plate from below with the fingertips and the palm.`,
    'Only the fingers, the palm, and part of the wrist are visible.',
    'Natural skin with realistic texture and soft creases, short clean nails, no rings, no bracelets, no sleeve.',
    'The hand must look like a real photographed hand: correct anatomy, natural proportions, never plastic or 3D-rendered.',
    fotografia(6, [
      `${uno ? 'The product' : 'The products'}, the plate, and the hand must appear to have been photographed together with a real camera under controlled studio lighting, then placed on the ${pieza}.`,
      'Use one large, soft but directional light from the upper-left, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
      ...luzCalida(color, 'the background'),
    ]),
    ...(cartel
      ? [
          '7. HEADLINE — ON THE LEFT',
          'On the left half of the banner, aligned left, from about 18% to 52% of the height, place a headline in one or two lines (breaking only between words), reading exactly:',
          `"${titular}"`,
          'Use a heavy, rounded, playful display typeface with a bold contemporary personality, uppercase.',
          `Text color: ${enFondo}.`,
          'Large: about 38% of the banner width.',
          'Tight but controlled letter spacing and line spacing.',
          'The headline sits on the background, crisp and fully legible.',
        ]
      : [
          `7. HEADLINE — OVER ${LO}`,
          `Over the middle of ${lo}, at about 55% of the poster height, centered, place a headline in one or two lines (breaking only between words), reading exactly:`,
          `"${titular}"`,
          'Use a heavy, rounded, playful display typeface with a bold contemporary personality, uppercase.',
          `Text color: white ${BLANCO}.`,
          'Large: about 55% of the poster width.',
          'Tight but controlled letter spacing and line spacing.',
          `The headline sits on top of the photo of ${lo}, crisp and fully legible.`,
        ]),
    'No outlines.',
    'No drop shadows.',
    'No 3D extrusion.',
    'No textures.',
    '8. HAND-DRAWN LINE AND SPARKLES',
    `Around ${lo} and the plate, draw one thin white hand-drawn line that loosely follows their silhouette at a small distance, slightly wobbly, with one or two small loops, like a playful doodle.`,
    'Add exactly five small white four-pointed sparkle stars:',
    cartel ? 'Three in a row at the top left, above the headline.' : `Three in a row at the top center, above the ${breve ? 'line' : 'paragraph'}.`,
    `One to the right of ${lo}.`,
    `One at the lower left of ${lo}.`,
    'Keep the line and the sparkles thin, small, and secondary.',
    `9. ${breve ? 'LINE' : 'PARAGRAPH'} — ${cartel ? 'BELOW THE HEADLINE' : 'AT THE TOP'}`,
    `${cartel ? 'Below the headline, aligned left' : 'Below the three sparkles at the top, centered'}, place ${breve ? 'one short line' : 'a short paragraph on two or three lines'}, reading exactly:`,
    `"${parrafo}"`,
    'Use an elegant, condensed, italic serif typeface, small, in sentence case.',
    `Text color: ${enFondo}.`,
    `Tight line spacing, ${cartel ? 'aligned left' : 'centered'}.`,
    ...(contacto ? [`Near the bottom left of the banner, one smaller line in the same font and color, reading exactly: ${contacto}`] : []),
    'Spell every word exactly as written, with its accents.',
    '10. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. ${uno ? 'The product' : 'The order of products'} held up in the hand.\n2. The two white starbursts.\n3. The "${titular}" headline.\n4. The hand-drawn line and the sparkles.\n5. The small ${breve ? 'line' : 'paragraph'}${contacto ? ', then the phone and the address' : ''}.`,
    'Keep the design lively but uncluttered.',
    'Do not add extra graphic elements.',
    '11. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the products described above.',
    'Do not create several copies of a product, or split it into halves.',
    'Do not include cutlery, napkins, or salsa bowls.',
    'Do not show more than one hand, a sleeve, jewelry, or a face.',
    contacto
      ? 'Do not include logos, trademark symbols, prices, websites, or social media handles.'
      : 'Do not include logos, trademark symbols, prices, phone numbers, websites, or social media handles.',
    `Do not add any text beyond the headline and the ${breve ? 'line' : 'paragraph'}${contacto ? ', and the phone and the address' : ''}.`,
    'Do not add more than two starbursts or more than five sparkles.',
    'Do not make the food or the hand look like a 3D render.',
    '12. FINAL PRIORITY',
    `${uno ? 'One authentic product' : `An order of ${CUANTOS[n]} authentic products`} on a small round paper plate, held up from below by a real hand, in front of two flat white spiky starbursts on a ${azul} paper background.`,
    `A bold rounded headline ${cartel ? 'on the left' : `over ${lo}`}, "${titular}", a thin hand-drawn white line around ${uno ? 'it' : 'them'}, five small white sparkles, and a short italic ${breve ? 'line' : 'paragraph'} ${cartel ? 'below the headline' : 'at the top'}.`,
    'Playful, energetic, bold, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'A REAL HAND, CORRECT ANATOMY.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
