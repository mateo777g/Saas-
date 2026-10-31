// Estilo 11 · Minimalista (minimalista.txt): el producto de Don Chuy chiquito sobre papel encerado, solo
// en un estudio crema sin fin, con mucho espacio y dos renglones chiquitos: su mensaje (vacío, el nombre
// del producto) y el nombre del restaurante. Su color pinta el estudio (pared y piso) con la misma luz; la
// letra oscura se queda.
import { AUTENTICO, comoEs, contactoDelCartel, lienzo, luzCalida, mayus, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const TONOS = {
  pared: '#D8CAB0',
  paredAbajo: '#E2D6C0',
  piso: '#F4EEE3',
  curva: '#CFC0A6',
};
const LETRA = '#393F33';

export const minimalista: Estilo = {
  clave: 'minimalista',
  maximo: 1,
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
  const p = a.productos[0];
  const color = a.color;
  const t = pintar(color, TONOS);
  const crema = color ? `soft, light ${nombreDelColor(color)}` : 'warm cream';
  const primero = mayus(a.mensaje ?? p.nombre);
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  const renglones = [primero, marca, ...(contacto ? [contacto.replace(/"/g, '').replace(' and ', ' · ')] : [])];

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'UPPER 52%:',
        'The empty wall of the studio. Nothing else.',
        'RIGHT HALF, FROM ABOUT 42% TO 78% OF THE HEIGHT:',
        'The product on its wax paper, centered in the right half, standing on the floor just in front of where the wall meets it.',
        'LEFT HALF, AT ABOUT 72% TO 84% OF THE HEIGHT:',
        `${renglones.length === 3 ? 'Three' : 'Two'} small lines of text, left-aligned, starting at about 10% of the banner width.`,
        'The product is small in the frame: about 20% of the banner width.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'UPPER 52%:',
        'The empty wall of the studio. Nothing else.',
        'FROM ABOUT 48% TO 72% OF THE HEIGHT:',
        'The product on its wax paper, centered horizontally, standing on the floor just in front of where the wall meets it.',
        'AT ABOUT 80% OF THE HEIGHT:',
        'Two small centered lines of text.',
        'The product is small in the frame: about 40% of the poster width.',
      ];

  const secciones = [
    `STYLE_14 — ${color ? nombreDelColor(color).toUpperCase() : 'CREAM'} STUDIO MINIMAL`,
    'Premium Mexican Food Advertising — Minimal Product Campaign',
    `Create a professionally art-directed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring one product, "${p.nombre}", on a small square of white wax paper, alone in a seamless ${crema} photography studio, with a lot of empty space and ${renglones.length === 3 ? 'three' : 'two'} small lines of text ${cartel ? 'beside' : 'below'} it.`,
    'THIS IS A QUIET, MINIMAL, GALLERY-LIKE PRODUCT SHOT: one product, one soft light, a seamless backdrop where the wall meets the floor in a soft curve, and almost nothing else.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    `Most of the ${pieza} is empty space. The emptiness is part of the design.`,
    `2. THE STUDIO — SEAMLESS ${color ? nombreDelColor(color).toUpperCase() : 'CREAM'} WALL AND FLOOR`,
    `The background is a real seamless photography backdrop in ${crema}.`,
    `The wall is slightly darker: about ${t.pared} at the top edge, getting lighter toward the floor, about ${t.paredAbajo}.`,
    `The floor is lighter, about ${t.piso}, and stays light down to the bottom edge.`,
    `The wall meets the floor at about 52% of the ${pieza} height in one soft but clearly visible curve, like a real paper sweep: just above it, the wall is a little darker, about ${t.curva}, and just below it the floor turns light.`,
    'The two planes must be clearly distinguishable: the wall darker, the floor lighter, with the curve between them easy to see across the whole width.',
    'The camera focuses on the product, so the wall behind it is slightly soft.',
    'The surfaces are matte and clean, with the natural, subtle tonal variation of a real paper backdrop under soft light.',
    'No patterns.',
    'No textures.',
    'No objects, props, or decorations in the studio.',
    ...luzCalida(color, 'the studio'),
    '3. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'The product stands upright on a small square of slightly creased white wax paper; the paper lies flat on the floor.',
    'Show the product from a slightly elevated three-quarter front view, about 25 degrees above, so its top and filling are clearly visible.',
    '4. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product, the paper, and the studio must appear to have been photographed with a real camera.',
    'Use one large, soft but directional light from the upper-right, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
    'Preserve natural shadows and realistic textures.',
    'Add a soft, natural shadow of the product and the paper on the floor, falling toward the lower left.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '5. TEXT',
    cartel
      ? `On the left half, at about 72% to 84% of the banner height, place ${renglones.length === 3 ? 'three' : 'two'} short lines, left-aligned, reading exactly:`
      : `Centered below the product, at about 80% of the ${pieza} height, place two short lines, reading exactly:`,
    `"${renglones.join('\n')}"`,
    `Use a clean, condensed, medium-weight sans-serif, uppercase, small: each line about ${cartel ? '3%' : '2%'} of the ${pieza} height${renglones.length === 3 ? ', the third line a little smaller' : ''}.`,
    `Text color: dark olive gray ${LETRA}.`,
    `Even letter spacing, ${cartel ? 'neatly aligned' : 'perfectly centered'}, like a quiet museum caption.`,
    'Spell every word exactly as written, with its accents.',
    'No other text.',
    '6. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product.\n2. The empty space around it.\n3. The small lines of text.`,
    'Do not fill the empty space.',
    'Do not add graphic elements.',
    '7. STRICT EXCLUSIONS',
    'Do not include any other food or drink.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include boxes, plates, trays, cutlery, napkins, or any object other than the product and its wax paper.',
    color ? `Do not use any strong background color: the studio stays a soft, light ${nombreDelColor(color)}.` : 'Do not use pink, red, or any strong background color.',
    'Do not show a sharp, hard horizon line or a hard corner: the wall and the floor meet in a soft but clearly visible curve.',
    'Do not include large headlines, badges, stickers, or decorative shapes.',
    contacto
      ? 'Do not include prices, promotions, websites, calls to action, logos, or trademark symbols.'
      : 'Do not include prices, promotions, phone numbers, addresses, websites, calls to action, logos, or trademark symbols.',
    `Do not add any text beyond the ${renglones.length === 3 ? 'three' : 'two'} lines.`,
    'Do not make the food look like a 3D render.',
    '8. FINAL PRIORITY',
    `One authentic product, standing on a small square of white wax paper, small and ${cartel ? 'in the right half' : 'centered'}, in a seamless ${crema} studio where the darker wall curves softly but visibly into the lighter floor, with a soft shadow and a lot of empty space.`,
    `Small lines of dark olive-gray text ${cartel ? 'on the left' : 'below it'}.`,
    'Quiet, minimal, elegant, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'A VISIBLE SOFT CURVE BETWEEN WALL AND FLOOR.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
