// Estilo 16 · Reflector (mesa-roja.txt): el producto de Don Chuy sobre un cuadro de papel encerado, en
// una mesa redonda roja vista desde arriba, bajo un reflector, en un cuarto rojo vino. Arriba, el nombre
// del restaurante chiquito y el titular crema; abajo, la pastilla del teléfono (sin teléfono, no sale).
// Su color pinta el cuarto y la mesa, como en la prueba del color (mesa-roja-azul.txt).
import { AUTENTICO, comoEs, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow: la mesa donde le da la luz (el principal), sus orillas, el
// cuarto y sus esquinas.
const TONOS = { mesaLuz: '#E15951', mesaOrilla: '#A83937', cuarto: '#560F11', cuartoOrilla: '#34080A' };
const CREMA = '#F8EDDC';

export const reflector: Estilo = {
  clave: 'reflector',
  maximo: 1,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: true,
  vacio: 'HAY FILA POR ALGO',
  datos: { post: ['nombre', 'telefono'], historia: ['nombre', 'telefono'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const color = a.color;
  const t = pintar(color, TONOS);
  const rojo = color ? nombreDelColor(color) : 'red';
  const vino = color ? nombreDelColor(color) : 'wine-red';
  const titular = a.mensaje ? mayus(a.mensaje) : null;
  const titularEntero = titular ?? 'HAY FILA POR ALGO';
  const marca = mayus(a.restaurante.nombre);
  const telefono = a.restaurante.telefono;
  const direccion = cartel && a.restaurante.direccion ? mayus(a.restaurante.direccion) : null;

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT, FROM ABOUT 6% TO 42% OF THE WIDTH, over the dark room, aligned left:',
        `The small brand name at about 10% to 16% of the height, then the headline from about 20% to 54%${telefono ? ', then the phone pill at about 64%' : ''}${direccion ? ', and the address, small, at about 86% to 92%' : ''}.`,
        'RIGHT, FROM ABOUT 44% OF THE WIDTH TO THE RIGHT EDGE:',
        'The round tabletop, seen from above, with its far edge curving at about 22% of the height and its near edge cropped by the bottom and the right edges.',
        'The product in the spotlight, at about 70% of the width, between about 30% and 76% of the height.',
        'The composition must feel moody, bold, and clearly designed.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP, FROM ABOUT 4% TO 24% OF THE HEIGHT:',
        `The small brand name, then the headline, centered, over the dark ${rojo} wall.`,
        'MIDDLE AND BOTTOM, FROM ABOUT 28% TO THE BOTTOM EDGE:',
        `The round ${rojo} tabletop, seen from above, with its far edge curving across the poster at about 28% of the height and its near edge cropped by the bottom and the sides.`,
        'CENTER, FROM ABOUT 36% TO 66% OF THE HEIGHT:',
        'The product in the spotlight.',
        ...(telefono ? ['BOTTOM, AT ABOUT 84% OF THE HEIGHT:', 'One small pill, centered.'] : []),
        'The composition must feel moody, bold, centered, and clearly designed.',
      ];

  const secciones = [
    `STYLE_19 — ${rojo.toUpperCase()} SPOTLIGHT TABLE`,
    `Moody Food Advertising — Spotlight Product ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally art-directed ${QUE_ES[a.formato]} featuring one product on a small square of white wax paper, on a round ${rojo} tabletop lit by a single spotlight in a dark ${vino} room, with a bold cream headline ${cartel ? 'on the left' : 'at the top'}, a small brand name above it${telefono ? `, and one small pill with a phone number ${cartel ? 'below it' : 'at the bottom'}` : ''}.`,
    `THIS IS ONE REAL PHOTOGRAPHED SET: a round ${rojo} table seen from above, one spotlight, deep ${rojo} shadows, and one product in the light.`,
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    `2. THE SET — DARK ${vino.toUpperCase()} ROOM AND ROUND ${rojo.toUpperCase()} TABLE`,
    `Behind the table, a dark ${vino} room, about ${t.cuarto}, getting darker toward the top corners and the edges, about ${t.cuartoOrilla}.`,
    'The room is softly out of focus, with no visible objects, windows, furniture, or scenery.',
    `The round tabletop is painted ${rojo} and matte, like a real worn café table.`,
    `One spotlight from above lights its center, about ${t.mesaLuz}, and the light falls off smoothly toward its edges, about ${t.mesaOrilla}, and into deep shadow beyond them.`,
    'The tabletop has a few faint, natural scuffs and small paint marks, very subtle, like a real used table.',
    `The camera looks down at the table from about 35 degrees above, so the tabletop is a large ellipse filling most of the ${cartel ? 'right part' : 'lower part'} of the ${pieza}.`,
    '3. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'The product stands on a small square of slightly creased white wax paper, the kind a taquería uses, in the center of the tabletop, right in the spotlight. If it is a drink, it stands directly on the tabletop, without the paper.',
    'Seen from the same camera angle as the table, so its top and its filling are clearly visible.',
    `The product is about ${cartel ? '26% of the banner width' : '45% of the poster width'}.`,
    '4. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product, the paper, the table, and the room must appear to have been photographed together, in one real set, with a real camera.',
    'The main light is the single spotlight from above, which gives the food warm highlights and natural depth; a gentle fill keeps the front of the product clearly visible and appetizing.',
    ...luzCalida(color, 'the room and the table'),
    'The product casts a short, soft, dark shadow on the tabletop, behind and to the right.',
    'Preserve natural shadows and realistic textures.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '5. BRAND AND HEADLINE',
    `${cartel ? 'At the upper left, aligned left' : 'At the top center'}, place a small brand name in one or two lines (breaking only between words), reading exactly:`,
    `"${marca}"`,
    'Use a bold, compact, condensed sans-serif, uppercase, small.',
    `Text color: warm cream ${CREMA}.`,
    `Below it, ${cartel ? 'aligned left' : 'centered'}, place the headline${titular ? ' in one or two lines (breaking only between words)' : ' on two lines'}, reading exactly:`,
    ...(titular ? [`"${titular}"`] : ['"HAY FILA', 'POR ALGO"', '"HAY FILA" is large; "POR ALGO" is smaller, about half its height, directly below.']),
    'Use a tall, condensed, heavy display typeface with squared letter shapes, softly rounded corners, and even, thick strokes, uppercase.',
    `Text color: warm cream ${CREMA}.`,
    'No outlines.',
    'No drop shadows.',
    'No 3D effects.',
    `The headline sits over the dark wall and never touches the table's far edge or the product.`,
    ...(telefono
      ? [
          '6. PHONE PILL',
          `${cartel ? 'Below the headline, over the dark room, aligned left' : `Near the bottom, over the ${rojo} tabletop, centered`}, place one small rounded pill in warm cream ${CREMA}, with a small simple dark ${rojo} phone-handset icon and the text "${telefono}" in dark ${vino} ${t.cuarto}.`,
          'Use a clean, small, bold sans-serif.',
          'The pill is small and tidy, never competing with the product.',
        ]
      : []),
    ...(direccion
      ? [
          `${telefono ? '' : '6. ADDRESS\n'}Near the bottom left of the banner, over the dark room, one small line in the same font as the brand name, in warm cream ${CREMA}, reading exactly: "${direccion}"`,
        ]
      : []),
    'Spell every word exactly as written, with its accents.',
    '7. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product in the spotlight.\n2. The "${titularEntero}" headline.\n3. The round ${rojo} table and its light.\n4. The brand name.${telefono ? '\n5. The phone pill.' : ''}`,
    'Keep the design bold and uncluttered.',
    'Do not add extra graphic elements.',
    '8. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the product described above.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, cutlery, napkins, or salsa bowls.',
    'Do not include chairs, people, or other furniture.',
    `Do not include social media handles or icons, logos, prices, ${telefono ? '' : 'phone numbers, '}websites, or trademark symbols.`,
    `Do not add any text beyond the brand name, the headline${telefono ? ', and the phone pill' : ''}${direccion ? ', and the address' : ''}.`,
    'Do not use script fonts, distressed lettering, outlines, or 3D text.',
    'Do not make the food or the table look like a 3D render.',
    '9. FINAL PRIORITY',
    `One authentic product on a small square of white wax paper in the spotlight at the center of a round, matte ${rojo} tabletop seen from above, in a dark ${vino} room.`,
    `A bold cream headline ${cartel ? 'on the left' : 'at the top'}, "${titularEntero}", a small cream brand name above it${telefono ? `, and a small cream pill with the phone number ${cartel ? 'below it' : 'at the bottom'}` : ''}.`,
    'Moody, bold, warm, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'ONE REAL SET, ONE SPOTLIGHT.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
