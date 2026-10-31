// Estilo 8 · Día de Muertos (dia-de-muertos.txt): el producto de Don Chuy en un platito de barro, en un
// altar de terciopelo entre cempasúchil y velas. De temporada (15 de octubre al 2 de noviembre) y sin
// color. Titular: el nombre del producto y «DE MUERTE»; la insignia, su mensaje (vacío, «DÍA DE MUERTOS»:
// nunca promete lo que él no dijo); «Hasta los muertos regresan por otro.» y el nombre del restaurante.
import { AUTENTICO, comoEs, contactoDelCartel, lienzo, mayus, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const CREMA = '#F4EBDC';
const VINO = '#3C0C18';

export const diaDeMuertos: Estilo = {
  clave: 'dia-de-muertos',
  maximo: 1,
  minimo: 1,
  mensaje: 24,
  mayusculas: true,
  conColor: false,
  vacio: 'DÍA DE MUERTOS',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const nombre = mayus(p.nombre);
  const insignia = a.mensaje ? mayus(a.mensaje) : 'DÍA DE MUERTOS';
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT HALF, UPPER PART:',
        'The two-line headline, with a small rounded badge below it.',
        'LEFT HALF, LOWER PART:',
        `A short phrase, and below it a small brand name${contacto ? ' with the phone and the address' : ''}.`,
        'RIGHT HALF:',
        'The product on its clay plate on the velvet-draped table, between the two flower clusters and the two candles.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP 26%:',
        'The two-line headline, centered.',
        'UPPER RIGHT, BELOW THE HEADLINE:',
        'A small rounded badge.',
        'CENTER:',
        'The product on its clay plate, between the two flower clusters and the two candles.',
        'BOTTOM 25%:',
        'The front of the velvet-draped table, with soft smoke, a short phrase on the right and a small brand name on the left.',
      ];

  const secciones = [
    'STYLE_11 — DÍA DE MUERTOS ALTAR',
    'Premium Mexican Food Advertising — Day of the Dead Campaign',
    `Create a professionally art-directed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring one product, "${p.nombre}", on a small clay plate, set on a velvet-draped table like a Day of the Dead altar, between two clusters of orange cempasúchil flowers and two lit candles, with soft incense smoke, against a deep wine-magenta background lit by a soft spotlight.`,
    'THIS IS A WARM, MOODY, ELEGANT DAY OF THE DEAD PRODUCT SHOWCASE: one hero product on an altar-like table, a bold rounded headline, a small badge, and a short phrase.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    'The composition must feel balanced, warm, spacious, and clearly designed.',
    '2. BACKGROUND — DEEP WINE-MAGENTA WITH A SOFT SPOTLIGHT',
    'Use a deep wine-magenta background.',
    'A soft, round spotlight glow sits behind the headline and the upper part of the product, about #973657 at its brightest.',
    `From there, the color fades smoothly to deep burgundy, about ${VINO}, toward the sides, and to almost black, about #150206, in the top corners.`,
    'The gradient is smooth and photographic, like a real studio backdrop lit by one spotlight from above.',
    'It must not show a visible wall, room, window, or scenery.',
    'No patterns.',
    'No textures.',
    'No decorative shapes in the background.',
    '3. THE ALTAR TABLE',
    `The lower part of the ${cartel ? 'right half' : 'poster'} is a table draped with dark plum velvet cloth.`,
    'The top surface of the table, where the plate sits, catches the light: about #632541.',
    'The front of the cloth falls into soft folds and deep shadow, about #1D1318, toward the bottom edge.',
    'The velvet must look like real fabric: soft sheen, natural folds, slightly irregular.',
    'No tablecloth patterns, no embroidery, no lace.',
    '4. CEMPASÚCHIL FLOWERS AND CANDLES',
    'On the left and on the right of the product, at about the same height as the plate and slightly behind it, place one large cluster of real orange cempasúchil (Mexican marigold) flowers, about #E24913.',
    cartel ? 'The right cluster is partially cropped by the right edge of the banner.' : 'Each cluster is partially cropped by the side edge of the poster.',
    'The flowers must look like real marigolds photographed with a real camera: ruffled petals, natural variations in orange, a few darker centers, slightly soft focus because they are behind the product.',
    'Behind each flower cluster stands one white pillar candle with a lit, small, natural flame.',
    `The candle flames sit at about 45% of the ${pieza} height, one on each side of the product.`,
    'The candles cast a warm orange glow on the flowers and on the nearby cloth.',
    'Keep the flowers and candles secondary: they frame the product and never cover it.',
    '5. SOFT INCENSE SMOKE',
    'Add soft, thin, white copal incense smoke drifting low across the front of the cloth and rising gently at the sides.',
    'The smoke is translucent, natural, and photographic, with irregular wisps.',
    'It may pass in front of the bottom of the cloth, but never in front of the product, the headline, or the phrase.',
    'No thick fog.',
    'No glowing or colored smoke.',
    '6. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'The product rests on one small, round, traditional glazed Mexican clay plate (barro), in warm terracotta brown, slightly irregular and handmade.',
    'The plate sits on the top of the velvet table, centered.',
    'Show the product from a slightly elevated front view, so its top and filling are clearly visible.',
    cartel
      ? 'The product is large in the frame: about 28% of the banner width, in the right half, between roughly 35% and 72% of the banner height.'
      : 'The product is large in the frame: about 55% of the poster width, between roughly 45% and 75% of the poster height.',
    '7. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product, the plate, the flowers, the candles, and the cloth must appear to have been photographed with a real camera.',
    'Light the product with a soft spotlight from above, plus the warm glow of the candles from both sides.',
    'The product must be clearly lit, warm, and appetizing, never lost in the dark mood.',
    'Preserve natural shadows and realistic textures.',
    'Add a natural, soft contact shadow of the plate on the cloth.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '8. HEADLINE — BOLD ROUNDED TYPOGRAPHY',
    `${cartel ? 'In the upper part of the left half' : 'At the top of the poster'}, place a headline on two lines, centered, reading exactly:`,
    `"${nombre}\nDE MUERTE"`,
    `"${nombre}" is the first line, large${nombre.length > 16 ? ' (if it is long, set it smaller so it fits on one line)' : ''}.`,
    `"DE MUERTE" is the second line and the dominant one: enormous, about twice the height of the first line, spanning about ${cartel ? '42% of the banner width' : '85% of the poster width'}.`,
    'Use a heavy, rounded, playful display typeface with a bold contemporary personality.',
    'The typography should resemble a professionally designed fast-food campaign, with slightly organic letter shapes and strong visual impact.',
    `Text color: warm cream ${CREMA}.`,
    'Use tight but controlled letter spacing.',
    'No dripping or melting letters.',
    'No horror or Halloween lettering.',
    'No outlines.',
    'No drop shadows.',
    'No 3D extrusion.',
    'No textures.',
    'Maintain a clean separation between the headline and the product.',
    'Avoid generic default fonts or distorted lettering.',
    '9. BADGE',
    `Below the headline, ${cartel ? 'centered under it' : 'on the right side'}, place one small rounded-rectangle badge.`,
    'Badge color: soft pink, about #DEB3C7.',
    'Inside, on one or two centered lines, reading exactly:',
    `"${insignia}"`,
    'Use the same rounded typeface, bold, uppercase, small.',
    `Text color: deep burgundy ${VINO}.`,
    'The badge is clearly smaller than the headline and does not touch the product or the candles.',
    '10. PHRASE',
    cartel
      ? 'In the lower part of the left half, place a short phrase on three lines, left-aligned, reading exactly:'
      : 'In the lower-right area, over the dark front of the cloth, place a short phrase on three lines, right-aligned, reading exactly:',
    '"Hasta los muertos\nregresan\npor otro."',
    'Use the same rounded typeface, bold, in sentence case, small to medium size.',
    'Text color: white #FFFFFF.',
    '11. BRAND',
    `In the lower-left corner, place a small, compact brand name, in one or two lines:\n"${marca}"`,
    'Use the same rounded typeface, bold, uppercase, small.',
    `Text color: warm cream ${CREMA}.`,
    ...(contacto ? [`Below it, in the same typeface, smaller, one line reading exactly: ${contacto}`] : []),
    'The brand remains secondary.',
    'Do not invent logos or symbols.',
    'Spell every word exactly as written, with its accents.',
    '12. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product on its clay plate.\n2. The "${nombre} DE MUERTE" headline.\n3. The cempasúchil flowers and candles framing the product.\n4. The badge.\n5. The phrase.\n6. The small brand name${contacto ? ', then the phone and the address' : ''}.`,
    'Keep the design balanced and uncluttered.',
    `Do not overcrowd the ${pieza} with unnecessary elements.`,
    '13. STRICT EXCLUSIONS',
    'Do not include pan de muerto or any other food or drink.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include skulls, sugar skulls, skeletons, Catrinas, papel picado, crosses, religious images, photographs of people, or portraits.',
    'Do not include Halloween elements: pumpkins, bats, ghosts, witches, spiders, or cobwebs.',
    'Do not add more flowers, candles, or decorations than described.',
    contacto
      ? 'Do not include prices, websites, calls to action, logos, or trademark symbols.'
      : 'Do not include prices, phone numbers, addresses, websites, calls to action, logos, or trademark symbols.',
    `Do not add any text beyond the headline, the badge, the phrase, and the brand name${contacto ? ' with its phone and address' : ''}.`,
    'Do not use dripping, melting, horror, or distressed lettering.',
    'Do not make the food, the plate, the flowers, the candles, or the cloth look like a 3D render.',
    '14. FINAL PRIORITY',
    'One authentic product on a small clay plate, on a dark plum velvet table, between two clusters of real orange cempasúchil flowers and two lit white candles, with soft copal smoke, against a deep wine-magenta background with a soft spotlight.',
    `A bold rounded cream headline ${cartel ? 'on the left' : 'at the top'}: "${nombre} DE MUERTE".`,
    `A small pink "${insignia}" badge, a short white phrase, and a small cream brand name at the lower left.`,
    'Warm, elegant, moody, premium Day of the Dead fast-food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'REAL FLOWERS, REAL CANDLES, REAL VELVET.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
