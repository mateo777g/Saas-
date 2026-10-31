// Estilo 18 · Menú de café (cafe-diagonal.txt): dos palabras gigantes en diagonal sobre papel salvia y,
// alrededor, hasta 3 productos de Don Chuy, cada uno con su etiqueta: nombre, descripción y precio de Mi
// menú. Abajo, un renglón de tres palabras, un párrafo (los dos del paso de texto) y el nombre del
// restaurante. Su mensaje son las palabras gigantes; vacío, las de sus dos primeros productos unidas con
// «Y» (el paso de texto). Su color pinta el fondo y las letras lo siguen.
import { AUTENTICO, cap, comoEs, contactoDelCartel, CUANTOS, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow: el fondo (el principal) y las letras.
const TONOS = { fondo: '#D6D9C5', letras: '#535925' };

// Dónde va cada producto, en el orden de la muestra (el capuchino, la concha de vainilla, la de chocolate),
// y qué tan grande: con menos productos, los mismos lugares, más grandes.
const LUGAR = ['at the upper left', 'at the middle right', 'at the lower left'];
const LUGAR_CARTEL = ['at the upper right, at about 64% of the width', 'in the middle, at about 84% of the width', 'at the lower right, at about 64% of the width'];
const TAMANO: Record<number, number> = { 1: 34, 2: 26, 3: 20 };

export const menuDeCafe: Estilo = {
  clave: 'menu-de-cafe',
  maximo: 3,
  minimo: 1,
  mensaje: 20,
  mayusculas: true,
  conColor: true,
  vacio: '#y',
  datos: { post: ['nombre', 'precio'], historia: ['nombre', 'precio'], cartel: ['nombre', 'telefono', 'direccion', 'precio'] },
  lugares: [
    {
      clave: 'tres',
      nombre: 'El renglón de tres palabras',
      tope: 30,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Tres palabras cortas que digan cómo son estos productos, separadas por « • » («CALIENTITO • DULCE • CASERO»), sacadas de sus nombres y descripciones, sin precios ni promociones.',
    },
    {
      clave: 'parrafo',
      nombre: 'El párrafo',
      tope: 120,
      mayusculas: false,
      cuando: 'siempre',
      pide: 'Un párrafo corto y cálido sobre estos productos, desde sus descripciones, en dos o tres frases cortas, con mayúscula solo al empezar cada frase («Para empezar el día con calma. Café recién hecho y pan dulce, como en casa.»), sin precios, promociones ni el nombre del restaurante.',
    },
    {
      clave: 'gigantes',
      nombre: 'Las palabras gigantes',
      tope: 20,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Con un producto, la palabra que más lo dice («Concha de vainilla» → «CONCHA»); con dos o más, la palabra que más dice el producto 1 y la que más dice el producto 2, unidas con « Y » («Capuchino» y «Concha de vainilla» → «CAPUCHINO Y CONCHA»).',
      vacio: true,
    },
  ],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const n = a.productos.length;
  const uno = n === 1;
  const color = a.color;
  const t = pintar(color, TONOS);
  const salvia = color ? `pale ${nombreDelColor(color)}` : 'pale sage-gray';
  const olivo = color ? `dark ${nombreDelColor(color)}` : 'dark olive green';
  const gigantes = mayus(a.mensaje ?? a.palabras.gigantes);
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  const lugares = cartel ? LUGAR_CARTEL : LUGAR;
  const tamano = cartel ? Math.round(TAMANO[n] * 0.6) : TAMANO[n];

  const donde = a.productos.map((_, i) => `product ${i + 1} ${lugares[i]}`);
  const composicion = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT, FROM ABOUT 5% TO 55% OF THE WIDTH, FROM ABOUT 8% TO 70% OF THE HEIGHT:',
        'The enormous words on a diagonal, running from the upper left down to the lower right.',
        'RIGHT, FROM ABOUT 58% TO 95% OF THE WIDTH:',
        `${uno ? 'The product' : 'The products'}: ${donde.join(', ')}, each with its small label beside it.`,
        'BOTTOM LEFT, FROM ABOUT 76% TO 96% OF THE HEIGHT:',
        `The spaced tagline, the short paragraph, the small brand name${contacto ? ', and the phone and the address' : ''}, aligned left.`,
        'The composition must feel calm, airy, balanced, and clearly designed.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'CENTER, FROM ABOUT 15% TO 75% OF THE HEIGHT:',
        'The enormous words on a diagonal, running from the upper left down to the lower right.',
        'AROUND THE WORDS:',
        `${cap(donde.join(', '))}, each with its small label beside it.`,
        'BOTTOM, FROM ABOUT 80% TO 96%:',
        'The spaced tagline, the short paragraph, and the small brand name, centered.',
        'The composition must feel calm, airy, balanced, and clearly designed.',
      ];

  const cadaProducto = a.productos.map((p, i) => `* Product ${i + 1}, ${lugares[i]}: ${comoEs(p)}`);

  // La etiqueta de cada producto: su nombre, su descripción y su precio de Mi menú, lo que haya.
  const etiquetas = a.productos.flatMap((p, i) => [
    `Next to product ${i + 1}, reading exactly:`,
    ...[mayus(p.nombre), p.descripcion, p.precio].filter((x): x is string => !!x).map((x) => `"${x}"`),
  ]);

  const secciones = [
    'STYLE_21 — CAFÉ DIAGONAL MENU',
    `Calm Editorial Café Advertising — ${uno ? 'Product' : 'Combo'} Menu ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally designed ${QUE_ES[a.formato]} for a Mexican restaurant, featuring enormous ${olivo} words set on a diagonal across a ${salvia} paper background, with ${uno ? 'one real photographed product' : `${CUANTOS[n]} real photographed products`} placed around them, each with its own small label, plus a spaced tagline and a short paragraph ${cartel ? 'at the bottom left' : 'at the bottom'}.`,
    `THIS IS A CALM, TYPOGRAPHY-LED, MENU-LIKE ${cartel ? 'BANNER' : 'POSTER'}: one huge diagonal typographic block, ${uno ? 'one product photo with a soft shadow' : 'small product photos with soft shadows'}, and quiet small text.`,
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. BACKGROUND',
    `Use a ${salvia} paper background, approximately ${t.fondo}, covering the whole canvas.`,
    'It has a very subtle printed-paper feel: a few tiny faint specks, barely visible.',
    'No gradients.',
    'No patterns.',
    'No strong textures.',
    '3. THE DIAGONAL WORDS',
    'Write the enormous words in one or two lines (breaking only between words), reading exactly:',
    `"${gigantes}"`,
    'Use a tall, condensed, heavy sans-serif, uppercase, tightly spaced, so the lines form one solid block.',
    `Rotate the whole block about ${cartel ? '30' : '50'} degrees clockwise, so it reads from the upper left down toward the lower right, crossing ${cartel ? 'the left part of the banner' : 'the center of the poster'}.`,
    `The block is very large: its length spans most of ${cartel ? 'the left part of the banner' : "the poster's diagonal"}.`,
    `Text color: ${olivo} ${t.letras}.`,
    'The letters are flat and solid: no outline, no shadow, no texture.',
    `${uno ? 'The product sits' : 'The products sit'} on top of the letters where ${uno ? 'it overlaps' : 'they overlap'}, and ${uno ? 'its soft shadow falls' : 'their soft shadows fall'} across them.`,
    `4. THE ${uno ? 'PRODUCT' : 'PRODUCTS'}`,
    ...cadaProducto,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    `${uno ? 'It rests' : 'Each one rests'} directly on the paper background, seen from about 25 degrees above, so ${uno ? 'its' : 'each'} top is clearly visible; a drink stands in its own plain glass or cup, with no logo and no text.`,
    `${uno ? 'The product is' : 'Each product is'} about ${tamano}% of the ${pieza} width${n < 3 ? ', larger than in a set of three' : ''}.`,
    'NO branding.',
    'NO logos.',
    '5. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    `${uno ? 'The product' : 'The products'} must appear to have been photographed with a real camera under controlled studio lighting, then placed on the ${pieza}.`,
    `Use one large, soft light from the upper-left and gentle neutral fill lighting${uno ? '' : ', the same for every product'}.`,
    ...luzCalida(color, 'the background and the letters'),
    `${uno ? 'The product casts' : 'Each product casts'} one soft, natural shadow toward the lower right, onto the paper and the letters.`,
    'Preserve natural shadows and realistic textures.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    `6. ${uno ? 'PRODUCT LABEL' : 'PRODUCT LABELS'}`,
    `Beside ${uno ? 'the product' : 'each product'}, place one small left-aligned label with up to three lines: the name in bold uppercase, a short description in small regular text, and the price.`,
    ...etiquetas,
    'Use a clean, simple sans-serif, small.',
    `Text color: ${olivo} ${t.letras}.`,
    `The ${uno ? 'label never overlaps the product' : 'labels never overlap the products'} or the big words.`,
    '7. BOTTOM TEXT',
    `Below the diagonal block, ${cartel ? 'aligned left' : 'centered'}, place one wide-spaced line reading exactly:`,
    `"${a.palabras.tres}"`,
    'Use a clean, light, wide sans-serif, uppercase, with generous letter spacing, medium size.',
    'Below it, a short paragraph on two or three lines, reading exactly:',
    `"${a.palabras.parrafo}"`,
    `Use the same clean sans-serif, small, in sentence case, ${cartel ? 'aligned left' : 'centered'}.`,
    `${cartel ? 'Below it' : 'At the very bottom'}, the brand name in small, wide-spaced uppercase, reading exactly:`,
    `"${marca}"`,
    ...(contacto ? [`Below it, one smaller line in the same font, reading exactly: ${contacto}`] : []),
    `Text color for all: ${olivo} ${t.letras}.`,
    'Spell every word exactly as written, with its accents.',
    '8. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The diagonal words "${gigantes}".\n2. ${uno ? 'The product' : 'The products'}.\n3. The ${uno ? 'product label' : 'product labels'}.\n4. The bottom tagline and paragraph.\n5. The brand name${contacto ? ', the phone and the address' : ''}.`,
    'Keep the design calm and uncluttered.',
    'Do not add extra graphic elements.',
    '9. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the products described above.',
    'Do not create several copies of a product, or split it into halves.',
    'Do not include plates, trays, cutlery, or napkins.',
    'Do not include any logo, brand, or text on a cup or a glass.',
    `Do not include ${contacto ? '' : 'phone numbers, '}websites, social media handles, or trademark symbols.`,
    `Do not add any text beyond the diagonal words, the ${uno ? 'label' : 'labels'}, the tagline, the paragraph, and the brand name${contacto ? ', the phone and the address' : ''}.`,
    'Do not use script fonts, distressed lettering, outlines, or 3D text.',
    'Do not make the food or the cups look like a 3D render.',
    '10. FINAL PRIORITY',
    `Enormous ${olivo} words, "${gigantes}", set on a diagonal across a ${salvia} paper background, with ${uno ? 'one product' : `${CUANTOS[n]} products`} placed around them with soft shadows, each with its small name, description, and price.`,
    `A spaced "${a.palabras.tres}" line, a short paragraph, and a small "${marca}" ${cartel ? 'at the bottom left' : 'at the bottom'}.`,
    'Calm, warm, editorial, premium advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'CLEAN DIAGONAL TYPOGRAPHY, CORRECTLY SPELLED.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
