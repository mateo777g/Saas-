// Estilo 20 · Ranura (ranura.txt): el producto de Don Chuy inclinado, saliendo de una ranura alta abierta
// en una superficie verde oscuro, con una luz suave que sale de adentro. Arriba, un renglón chiquito y
// espaciado (su mensaje; vacío, «RECIÉN SALIDO DE LA BARRA.»); abajo a la izquierda, el nombre del
// restaurante en manuscrita, tal cual. Su color pinta la superficie; la luz de la ranura se queda.
import { AUTENTICO, comoEs, contactoDelCartel, fotografia, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow: la superficie (el principal) y su parte de abajo.
const TONOS = { superficie: '#17563D', abajo: '#154B34' };
const LUZ = '#D8E2E5';

export const ranura: Estilo = {
  clave: 'ranura',
  maximo: 1,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: true,
  vacio: 'RECIÉN SALIDO DE LA BARRA.',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const p = a.productos[0];
  const color = a.color;
  const t = pintar(color, TONOS);
  const verde = color ? nombreDelColor(color) : 'green';
  const gris = color ? `${verde}-tinted gray` : 'greenish gray';
  const linea = mayus(a.mensaje ?? 'RECIÉN SALIDO DE LA BARRA.');
  const marca = a.restaurante.nombre;
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT, FROM ABOUT 6% TO 48% OF THE WIDTH, aligned left:',
        `The spaced line of text, larger than on a poster, on one to three lines, at about 28% to 52% of the height; the handwritten brand name below it, at about 64% to 74%${contacto ? '; and the phone and the address, small, at about 86% to 94%' : ''}.`,
        'RIGHT, FROM ABOUT 10% TO 90% OF THE HEIGHT AND FROM ABOUT 58% TO 76% OF THE WIDTH:',
        'The tall slot.',
        'RIGHT, FROM ABOUT 14% TO 88% OF THE HEIGHT:',
        'The product, tilted, centered over the slot and passing through it.',
        'Most of the banner is the surface. The composition must feel minimal, calm, and clearly designed.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP, AT ABOUT 4% OF THE HEIGHT:',
        'One small, wide-spaced line of text, centered.',
        'CENTER, FROM ABOUT 12% TO 76% OF THE HEIGHT AND FROM ABOUT 34% TO 66% OF THE WIDTH:',
        'The tall slot, about one third of the poster width.',
        'CENTER, FROM ABOUT 16% TO 77% OF THE HEIGHT:',
        'The product, tilted, centered over the slot and passing through it.',
        'LOWER LEFT, AT ABOUT 92% OF THE HEIGHT:',
        'The small handwritten brand name.',
        'Most of the poster is the surface. The composition must feel minimal, calm, and clearly designed.',
      ];

  const texto = cartel
    ? [
        `On the left, aligned left, place the line on one to three lines (breaking only between words), reading exactly:`,
        `"${linea}"`,
        'Use a clean, light, wide sans-serif, uppercase, with generous letter spacing, medium size, so it reads clearly when the banner is seen small on a phone.',
        `Text color: soft white, approximately ${LUZ}.`,
        'Below it, aligned left, place the brand name in an elegant, flowing handwritten script, medium-small, reading exactly:',
        `"${marca}"`,
        'Text color: white #FFFFFF.',
        ...(contacto ? [`At the bottom left, one small line in the same light, wide sans-serif as the top line, in soft white ${LUZ}, reading exactly: ${contacto}`] : []),
      ]
    : [
        'At the top center, place one small line, reading exactly:',
        `"${linea}"`,
        'Use a clean, light, wide sans-serif, uppercase, with generous letter spacing, small.',
        `Text color: soft white, approximately ${LUZ}.`,
        'In the lower left, place the brand name in an elegant, flowing handwritten script, small, reading exactly:',
        `"${marca}"`,
        'Text color: white #FFFFFF.',
      ];

  const secciones = [
    'STYLE_23 — PRODUCT THROUGH THE SLOT',
    `Conceptual Food Advertising — Minimal 3D Illusion ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally art-directed ${QUE_ES[a.formato]} for a Mexican restaurant, featuring one product emerging, tilted, through a tall rectangular slot cut into a deep ${verde} surface, with soft light glowing from inside the slot, one ${cartel ? 'spaced line of text on the left' : 'small spaced line of text at the top'}, and a small handwritten brand name ${cartel ? 'below it' : 'at the lower left'}.`,
    `THIS IS A CONCEPTUAL, MINIMAL, PHOTOREALISTIC ILLUSION: a flat ${verde} surface with one rectangular opening, and a real product coming out of it toward the viewer.`,
    'Prioritize believable photography and physically convincing light, depth, and shadows over exaggerated or artificial-looking effects.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    `2. THE ${verde.toUpperCase()} SURFACE`,
    `The whole background is one flat, deep ${verde} surface, approximately ${t.superficie}, slightly darker toward the bottom, approximately ${t.abajo}.`,
    'It has a very fine, even grain, like soft matte felt or fine paper, barely visible.',
    'No patterns.',
    'No other shapes.',
    'No scenery.',
    '3. THE SLOT',
    `In the surface, cut one tall, perfectly rectangular opening, about ${cartel ? 'one sixth of the banner width' : 'one third of the poster width'}, with crisp straight edges and a thin visible depth on its edges, like a real slot cut into a thick board.`,
    `Inside the opening, the depth is a slightly lighter ${verde} near its upper part and a soft ${gris} toward the bottom.`,
    `A soft, gentle white glow, approximately ${LUZ}, comes from inside the slot, behind the product, and spills a little out of its right edge onto the ${verde} surface, fading smoothly.`,
    'The glow is soft and diffused, never a bright beam: the slot must not look like a door left ajar.',
    '4. THE PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'If it is a drink, it is in its own plain cup or glass, with no logo, no text, no pattern, and no brand marks of any kind.',
    'The product is tilted about 20 degrees, with its top toward the upper left and its base toward the lower right.',
    'The product is centered over the slot and passes through it, as if it were sliding out of the surface toward the viewer:',
    `its upper-left part sticks out in front of the ${verde} surface, beyond the slot's left edge, casting a soft shadow on it;`,
    'the rest of it, about two thirds of it, sits inside the opening;',
    "at the slot's right edge, the product is cut cleanly in one straight vertical line and disappears behind the surface, as if it continued behind it.",
    'The straight cut along the right edge must be clearly visible.',
    `The product is large: about ${cartel ? '26% of the banner width' : '42% of the poster width'}.`,
    'It must look like a real product photographed in the studio, with soft realistic highlights.',
    fotografia(5, [
      'The product, the slot, and the surface must appear to have been photographed together as one real set with a real camera.',
      'The main light is the soft glow from inside the slot, plus a soft fill from the front-left so the product is clearly lit.',
      ...luzCalida(color, 'the surface'),
      'A soft shadow of the product falls on the surface to the left, and the inside of the slot darkens naturally.',
    ]),
    '6. TEXT',
    ...texto,
    'Spell every word exactly as written, with its accents.',
    '7. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product coming out of the slot.\n2. The slot and its glow.\n3. The ${cartel ? 'spaced line' : 'small line at the top'}.\n4. The handwritten brand name${contacto ? ', then the phone and the address' : ''}.`,
    'Keep the design minimal.',
    'Do not add extra graphic elements.',
    '8. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the product described above.',
    'Do not include any logo, brand, mermaid, seal, emblem, printed text, product name, or icons on the product, its cup, or its wrapper.',
    'Do not include plates, saucers, spoons, coffee beans, steam, or other objects.',
    'Do not create several copies of the product or more than one slot.',
    contacto
      ? 'Do not include prices, websites, social media handles, or trademark symbols.'
      : 'Do not include prices, phone numbers, addresses, websites, social media handles, or trademark symbols.',
    `Do not add any text beyond the ${cartel ? 'spaced' : 'top'} line and the brand name${contacto ? ', and the phone and the address' : ''}.`,
    'Do not make the food or the surface look like a 3D render.',
    '9. FINAL PRIORITY',
    `One authentic product, tilted, centered over a tall rectangular slot ${cartel ? 'on the right of' : 'one third of the poster wide in'} a flat deep ${verde} surface, passing through it: its upper-left part sticking out in front of the surface and its right part cut in a straight line by the slot's right edge, with a soft white glow from inside the slot.`,
    `A spaced line ${cartel ? 'on the left' : 'at the top'}, "${linea}", and a small handwritten "${marca}" ${cartel ? 'below it' : 'at the lower left'}.`,
    `Minimal, conceptual, calm, premium food advertising.`,
    'NO LOGOS ON THE PRODUCT.',
    'AUTHENTIC MEXICAN FOOD.',
    'CONVINCING DEPTH AND LIGHT.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
