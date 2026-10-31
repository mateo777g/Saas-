// Estilo 7 · Navidad (mano-de-santa.txt): el producto de Don Chuy en la palma de la mano enguantada de
// Santa, sobre rojo con nieve, bajo «NAVIDAD» y su mensaje (vacío, «CON TODO»; uno largo, más chico). De
// temporada (1 al 25 de diciembre) y sin color. La etiqueta chiquita es el nombre del producto tal cual;
// abajo a la izquierda, el nombre del restaurante.
import { AUTENTICO, comoEs, contactoDelCartel, lienzo, mayus, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const ROJO = '#D72302';
const CREMA = '#F4EBDC';

export const navidad: Estilo = {
  clave: 'navidad',
  maximo: 1,
  minimo: 1,
  mensaje: 20,
  mayusculas: true,
  conColor: false,
  vacio: 'CON TODO',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const segundo = a.mensaje ? mayus(a.mensaje) : 'CON TODO';
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into three zones:',
        'LEFT 50%:',
        'The enormous two-line headline, centered in the left half, in its upper and middle part.',
        'RIGHT 50%:',
        'The product resting on the gloved hand, with a small product label to its left.',
        'LOWER-LEFT CORNER:',
        `A small brand name${contacto ? ', with the phone and the address below it, smaller' : ''}.`,
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into three zones:',
        'TOP 32%:',
        'The enormous two-line headline, centered.',
        'MIDDLE AND LOWER PART:',
        'The product resting on the gloved hand, centered slightly left, with a small product label to its right.',
        'LOWER-LEFT CORNER:',
        'A small brand name.',
      ];

  const secciones = [
    "STYLE_10 — SANTA'S HAND",
    'Premium Mexican Food Advertising — Christmas Campaign',
    `Create a professionally art-directed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring one product, "${p.nombre}", resting on the open palm of Santa Claus's white-gloved hand, against a solid vivid red background with soft falling snow, ${cartel ? 'beside' : 'under'} an enormous warm-cream headline.`,
    'THIS IS A BOLD, MINIMAL CHRISTMAS PRODUCT SHOWCASE: one enormous headline, one hero product presented on a gloved hand, and a flat red background.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    `The entire ${pieza} shares ONE continuous red background.`,
    'The composition must feel simple, bold, spacious, and clearly designed.',
    '2. BACKGROUND — SOLID RED WITH SOFT SNOW',
    `Use a solid, uniform, vivid warm red background, approximately ${ROJO}, from the top edge to the bottom edge.`,
    'The background is a flat graphic advertising backdrop, not a physical wall, room, or studio.',
    'No floor.',
    'No horizon.',
    'No gradient.',
    'No vignetting.',
    'No texture.',
    'No background shadows.',
    'Over the red, add soft falling snow:',
    '* Small, round, out-of-focus white snowflakes of different sizes, like real snow photographed with a shallow depth of field.',
    '* A few tiny, sharper white specks.',
    '* Sparse near the center, slightly more frequent near the edges and corners.',
    'The snow is subtle and restrained: a light scattering, never a blizzard.',
    'It must not cover the headline letters or the product.',
    'It must not form piles or a snowy ground.',
    '3. HEADLINE — ENORMOUS ROUNDED TYPOGRAPHY',
    `${cartel ? 'On the left half of the banner' : 'At the very top of the poster'}, place an enormous headline on two lines, centered, reading exactly:`,
    `"NAVIDAD\n${segundo}"`,
    cartel
      ? '"NAVIDAD" is the dominant line: extremely large, spanning about 44% of the banner width.'
      : '"NAVIDAD" is the dominant line: extremely large, spanning about 88% of the poster width and about 18% of the poster height.',
    `"${segundo}" sits directly below it, about half the height of the first line, centered.`,
    ...(a.mensaje ? ['If the second line is long, set it smaller so it fits on one line, never wider than "NAVIDAD".'] : []),
    'Use a heavy, rounded, playful display typeface with a bold contemporary personality.',
    'The typography should resemble a professionally designed fast-food campaign, with slightly organic letter shapes and strong visual impact.',
    `Text color: warm cream ${CREMA}.`,
    'Use tight but controlled letter spacing.',
    'No outlines.',
    'No drop shadows.',
    'No 3D extrusion.',
    'No snow caps or decorations on the letters.',
    'No textures.',
    'Maintain a clean separation between the headline and the product.',
    'Avoid generic default fonts or distorted lettering.',
    '4. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'Show the product from a slightly elevated front view, so its top and filling are clearly visible.',
    cartel
      ? 'The product is large in the frame: about 28–32% of the banner width, in the right half, between roughly 30% and 70% of the banner height.'
      : 'The product is large in the frame: about 55–60% of the poster width, centered slightly left, between roughly 40% and 72% of the poster height.',
    "5. SANTA'S GLOVED HAND",
    'The product rests directly on the open, upturned palm of a gloved hand.',
    'The hand enters the frame from the lower-right corner, palm facing up, fingers extended toward the left, held horizontally just below the product.',
    'The gloved fingers curve gently upward to cradle the product and keep it upright.',
    `At the wrist, a thick, fluffy cuff of white fur fills the lower-right corner of the ${pieza} and is cropped by the right and bottom edges.`,
    'Only the gloved hand and the fur cuff are visible: no face, no beard, no hat, no body.',
    'The glove must look like a real white fabric glove: soft cotton with a slight sheen, natural creases at the knuckles and palm, and fine stitched seams.',
    'The fur must look like real soft fur, with natural irregular strands.',
    'In realistic proportion: the product is a little shorter than the gloved palm and fingers together.',
    'Neither the glove nor the fur may look like plastic, clay, foam, or a 3D render.',
    '6. PRODUCT LABEL',
    `To the ${cartel ? 'left' : 'right'} of the product, at about its mid-height, place a small label, in one or two lines, reading exactly:`,
    `"${p.nombre}"`,
    'Use the same rounded typeface, bold, written exactly as above, small like a caption.',
    'Text color: white #FFFFFF.',
    'It must not touch the product.',
    '7. BRAND',
    `In the lower-left corner, place a small, compact brand name, in one or two lines:\n"${marca}"`,
    'Use the same rounded typeface, bold, uppercase, small.',
    `Text color: warm cream ${CREMA}.`,
    ...(contacto ? [`Below it, in the same typeface, smaller, one line reading exactly: ${contacto}`] : []),
    'The brand remains secondary.',
    'Do not invent logos or symbols.',
    'Spell every word exactly as written, with its accents.',
    '8. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product, the glove, and the fur must appear to have been photographed with a real camera under controlled studio lighting.',
    'Use a large soft light from the upper-left and gentle neutral fill lighting.',
    'Preserve natural shadows and realistic textures.',
    'Add a natural, soft contact shadow of the product on the gloved palm.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '9. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product on the gloved hand.\n2. The enormous "NAVIDAD ${segundo}" headline.\n3. The small product label.\n4. The small brand name${contacto ? ', then the phone and the address' : ''}.`,
    'Keep generous red negative space.',
    `Do not overcrowd the ${pieza} with unnecessary graphic elements.`,
    '10. STRICT EXCLUSIONS',
    'Do not include any other food or drink.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not place the product on a plate, a napkin, a board, or any surface other than the gloved hand.',
    "Do not show Santa's face, beard, hat, body, or a second hand.",
    'Do not add Christmas trees, ornaments, gift boxes, string lights, holly, candy canes, ribbons, stars, sparkles, or confetti.',
    'Do not add a snowy ground, snow piles, or a heavy blizzard.',
    contacto
      ? 'Do not include prices, promotions, websites, calls to action, logos, or trademark symbols.'
      : 'Do not include prices, promotions, phone numbers, addresses, websites, calls to action, logos, or trademark symbols.',
    `Do not add any text beyond the headline, the product label, and the brand name${contacto ? ' with its phone and address' : ''}.`,
    'Do not add a gradient, texture, floor, or background shadows.',
    'Do not make the food, the glove, or the fur look like a 3D render.',
    '11. FINAL PRIORITY',
    `One authentic product resting on Santa's white-gloved open palm, with a fluffy white fur cuff in the lower-right corner, against a flat vivid red background with soft falling snow.`,
    `An enormous rounded cream headline ${cartel ? 'on the left' : 'at the top'}: "NAVIDAD ${segundo}".`,
    `A small white "${p.nombre}" label beside the product and a small cream brand name in the lower-left corner.`,
    'Bold, minimal, warm, premium Christmas fast-food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'REAL GLOVE, REAL FUR.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
