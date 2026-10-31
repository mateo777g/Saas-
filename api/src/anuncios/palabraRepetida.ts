// Estilo 15 · Palabra repetida (palabra-rosa.txt): una palabra del nombre del producto (la escoge el
// paso de texto: «PASTOR») repetida en filas de lado a lado, en rosa palo sobre crema, y el producto de
// Don Chuy visto desde muy arriba al centro, con su sombra dura. Arriba, chiquito, el nombre del
// restaurante. No lleva mensaje. Su color pinta las letras; el crema se queda.
import { AUTENTICO, comoEs, contactoDelCartel, legibleSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow: las letras de abajo (el principal), las de arriba y la marca.
const TONOS = { abajo: '#DBA098', arriba: '#EDD8CB', marca: '#A83937' };
const CREMA = '#F3EADB';

export const palabraRepetida: Estilo = {
  clave: 'palabra-repetida',
  maximo: 1,
  minimo: 1,
  mensaje: 0,
  mayusculas: false,
  conColor: true,
  vacio: null,
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [
    {
      clave: 'repetida',
      nombre: 'La palabra repetida',
      tope: 10,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Una sola palabra del nombre del producto, la que más lo dice, en mayúsculas («Taco al pastor» → «PASTOR», «Agua de horchata» → «HORCHATA», «Gringa» → «GRINGA»).',
      forma: { regla: /^\S+$/u, explica: 'va en una sola palabra.' },
    },
  ],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const historia = a.formato === 'historia';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const color = a.color;
  const t = pintar(color, TONOS);
  const rosa = color ? nombreDelColor(color) : 'rose';
  const marcaTono = color ? legibleSobre(t.marca, CREMA) : t.marca;
  const rojo = color ? `deep ${nombreDelColor(color)}` : 'deep red';
  const palabra = a.palabras.repetida;
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  // Cuántas filas caben: en el cartel la palabra va dos veces en cada fila, para que el patrón no
  // quede en dos filas enormes.
  const filas = cartel ? 'four' : historia ? 'eight' : 'five';
  const fila = cartel ? `the word "${palabra}" written twice, side by side` : `the word "${palabra}"`;

  const composicion = [
    lienzo(a.formato),
    `The background is filled ${historia ? 'from the top edge to the bottom edge of the image' : `from top to bottom`} with ${filas} rows of ${fila}, each row spanning the full width of the ${pieza}, the last row cropped by the bottom edge.`,
    cartel
      ? 'The product sits in the center of the banner, between about 25% and 75% of the height, over the middle rows.'
      : 'The product sits in the center of the poster, between about 30% and 62% of the height, over the second and third rows.',
    `A small brand name sits at the top center, over the first row.`,
    ...(contacto ? ['At the bottom center, over the last row, the phone and the address, smaller.'] : []),
    'The composition must feel minimal, bold, centered, and clearly designed.',
  ];

  const secciones = [
    `STYLE_18 — ${rosa.toUpperCase()} REPEAT TYPE`,
    `Minimal Graphic Food Advertising — Repeated Word ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally designed ${QUE_ES[a.formato]} featuring one product seen from a steep high angle, centered over a warm cream background filled with the word "${palabra}" repeated in rows of tall dusty-${rosa} letters, with a small ${rojo} brand name at the top.`,
    `THIS IS A MINIMAL, BOLD GRAPHIC ${cartel ? 'BANNER' : 'POSTER'}: one repeated word as a typographic pattern, and one real photographed product with a crisp shadow placed in the middle of it.`,
    'Prioritize authentic food photography and physically believable food over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. BACKGROUND',
    `Use a flat, warm cream background, approximately ${CREMA}.`,
    'No texture.',
    'No gradient on the background itself.',
    'No patterns other than the repeated word.',
    '3. THE REPEATED WORD — TYPOGRAPHIC PATTERN',
    `Write ${cartel ? `the word "${palabra}" twice in each of the four rows` : `the word "${palabra}" ${filas} times, one per row`}, stacked tightly with very little space between the rows, exactly as given.`,
    'Use a tall, condensed, heavy display typeface with squared letter shapes, softly rounded corners, and even, thick strokes, with a slightly retro feel.',
    `Each row is as wide as the ${pieza}: the letters touch or almost touch the left and right edges, and may be very slightly cropped by them.`,
    `Color: dusty ${rosa}, getting slightly deeper from top to bottom: about ${t.arriba} in the first row and about ${t.abajo} in the last rows.`,
    'The letters are flat and solid: no outline, no shadow, no texture.',
    'The word pattern is a background: soft in color, never competing with the product.',
    '4. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'Show the product from a steep high angle, about 60 degrees above, so its top and its filling are the main thing the viewer sees.',
    `The product is about ${cartel ? '26% of the banner width' : '45% of the poster width'}, centered.`,
    '5. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product must appear to have been photographed with a real camera under bright, controlled studio lighting, then placed on the design.',
    'Use one strong, slightly hard light from the upper-left, which gives the food crisp highlights and natural depth, plus gentle neutral fill lighting.',
    ...luzCalida(color, 'the repeated word and the brand name'),
    'The product casts one crisp, soft-edged shadow toward the lower right onto the cream background and the letters, like a bright product shot.',
    'Preserve natural shadows and realistic textures.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '6. BRAND',
    `At the top center of the ${pieza}, over the first row of letters, place a small brand name in one or two lines (breaking only between words), reading exactly:`,
    `"${marca}"`,
    'Use a bold, compact, condensed sans-serif, uppercase, small.',
    `Text color: ${rojo} ${marcaTono}.`,
    ...(contacto ? [`At the bottom center, over the last row of letters, one smaller line in the same font and color, reading exactly: ${contacto}`] : []),
    'Spell every word exactly as written, with its accents.',
    'Do not invent logos or symbols.',
    '7. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product.\n2. The repeated word "${palabra}".\n3. The small brand name${contacto ? ', then the phone and the address' : ''}.`,
    'Keep the design minimal and clean.',
    'Do not add extra graphic elements.',
    '8. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the product described above.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, boards, paper, cutlery, or napkins.',
    contacto
      ? 'Do not include prices, promotions, websites, logos, or trademark symbols.'
      : 'Do not include prices, promotions, phone numbers, addresses, websites, logos, or trademark symbols.',
    `Do not add any text beyond the repeated word and the brand name${contacto ? ', and the phone and the address' : ''}.`,
    'Do not use script fonts, distressed lettering, outlines, or 3D text.',
    'Do not make the food look like a 3D render.',
    '9. FINAL PRIORITY',
    `One authentic product, seen from a steep high angle, centered with a crisp shadow over a warm cream background filled with ${filas} full-width rows of the word "${palabra}" in tall, squared, dusty-${rosa} letters that deepen toward the bottom.`,
    `A small ${rojo} brand name at the top.`,
    'Minimal, bold, graphic, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'CLEAN REPEATED TYPOGRAPHY.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
