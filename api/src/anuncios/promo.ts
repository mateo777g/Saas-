// Estilo 5 · Promo (promo-verde.txt, el favorito del desarrollador): el producto flotando sobre un
// degradado verde, su nombre en letras grandes y juguetonas, su mensaje en un círculo con flechita (vacío,
// no sale), la marca arriba a la izquierda y abajo «ORDENA AHORA · teléfono · dirección». Su color pinta
// el fondo, siempre oscuro como el verde: las letras crema se quedan.
import { AUTENTICO, comoEs, lienzo, luzCalida, mayus, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const TONOS = { fondo: '#003D28' };
const MARFIL = '#F5F0E9';

export const promo: Estilo = {
  clave: 'promo',
  maximo: 1,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: true,
  vacio: null,
  datos: {
    post: ['nombre', 'telefono', 'direccion', 'ordena'],
    historia: ['nombre', 'telefono', 'direccion', 'ordena'],
    cartel: ['nombre', 'telefono', 'direccion', 'ordena'],
  },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const color = a.color;
  const fondo = pintar(color, TONOS).fondo;
  const verde = color ? nombreDelColor(color) : 'emerald-green';
  const bosque = color ? `${nombreDelColor(color)}` : 'forest green';
  const titular = mayus(p.nombre);
  const insignia = a.mensaje ? mayus(a.mensaje) : null;
  const marca = mayus(a.restaurante.nombre);
  const r = a.restaurante;
  // Abajo: «ORDENA AHORA», el teléfono y la dirección que haya.
  const renglon = ['ORDENA AHORA', r.telefono, r.direccion ? mayus(r.direccion) : null].filter((d): d is string => !!d);
  const lados = renglon.length === 3 ? ['LEFT', 'CENTER', 'RIGHT'] : renglon.length === 2 ? ['LEFT', 'RIGHT'] : ['CENTER'];

  const secciones = [
    `STYLE_07 — ${verde.toUpperCase()} FLOATING PROMO`,
    'Bold Contemporary Fast-Food Advertising Campaign',
    `Create a professional, visually striking commercial food advertisement featuring one product, "${p.nombre}", floating against a rich ${verde} background.`,
    `The design uses a bold contemporary composition: a strong graphic hierarchy, playful typography, floating product photography,${insignia ? ' a promotional badge,' : ''} and a contemporary fast-food campaign aesthetic.`,
    'Prioritize authentic food photography and physically believable ingredients over exaggerated or artificial-looking food styling.',
    '1. FORMAT AND DESIGN DIRECTION',
    a.formato === 'post' ? 'Create a vertical 4:5 advertising poster.' : lienzo(a.formato),
    'The visual aesthetic must combine:',
    '* Bold contemporary fast-food advertising.',
    '* Premium commercial food photography.',
    '* Playful, oversized typography.',
    '* Strong graphic hierarchy.',
    `* A rich ${verde} background.`,
    '* A dynamic floating hero product.',
    ...(insignia ? ['* A clearly visible promotional offer.'] : []),
    'The finished advertisement should feel like a professionally art-directed social media campaign for a modern Mexican restaurant.',
    `2. BACKGROUND — ${verde.toUpperCase()} GRADIENT`,
    `Use a rich, deep ${verde} background.`,
    `Base color: ${fondo}.`,
    'Create a restrained, smooth tonal gradient:',
    `* Slightly lighter ${bosque} toward the upper-left and central-left portions.`,
    `* Deep ${verde} through the middle.`,
    `* Darker ${color ? verde : 'green'} toward the bottom and outer edges.`,
    'The gradient should be smooth, elegant, and subtle.',
    'It must not resemble a physical wall, floor, or studio backdrop.',
    'Do not introduce visible textures, patterns, horizon lines, or environmental scenery.',
    'The background should feel like a premium graphic advertising canvas.',
    `Keep the ${color ? verde : 'green'} sufficiently dark to create strong contrast with the cream-colored typography.`,
    ...luzCalida(color, 'the background'),
    '3. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    '4. FLOATING PRODUCT COMPOSITION',
    cartel
      ? 'Position the product prominently on the right half of the banner.'
      : 'Position the product prominently in the upper half of the poster.',
    'Use a dynamic diagonal orientation, with its most appetizing side facing partially toward the viewer.',
    'The product should appear suspended in midair.',
    'It must remain fully assembled and recognizable.',
    cartel
      ? 'The product should occupy approximately 35–40% of the banner width.'
      : 'The product should occupy approximately 55–65% of the poster width.',
    `Leave sufficient space around the product for ${insignia ? 'the promotional badge and ' : ''}the typography.`,
    'Do not place the product on a plate or physical surface.',
    'Do not create a visible floor or cast shadow beneath the product.',
    'The floating composition should feel energetic but believable.',
    '5. CONTROLLED INGREDIENT MOVEMENT',
    'Surround the product with a restrained amount of floating ingredients: a few small pieces of its own ingredients, and nothing it does not contain.',
    'The ingredients should appear naturally suspended around the product.',
    'Keep their proportions realistic.',
    'Most of the filling must remain inside the product.',
    'Do not create an enormous explosion.',
    'Do not separate the product from its filling.',
    'The floating ingredients should add freshness and energy without distracting from the hero product.',
    'Add two or three softly blurred pieces of its fresh herbs or ingredients near the extreme edges of the composition to create subtle foreground depth.',
    'These foreground pieces must remain secondary and unobtrusive.',
    '6. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product must appear to have been photographed with a real camera under controlled studio lighting.',
    'Use a large soft light from the upper-left and gentle neutral fill lighting.',
    'Preserve natural shadows and realistic ingredient textures.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '7. MAIN HEADLINE — BOLD PLAYFUL TYPOGRAPHY',
    cartel
      ? 'Place a very large headline on the left half of the banner, in its middle.'
      : 'Place a very large headline in the lower-middle portion of the poster.',
    'Use the exact text:',
    `"${titular}"`,
    'Set it on one or two lines, breaking only between words.',
    'Use a heavy, rounded, playful display typeface with a bold contemporary personality.',
    'The typography should resemble a professionally designed fast-food campaign, with slightly organic letter shapes and strong visual impact.',
    `Text color: warm ivory ${MARFIL}.`,
    'The headline must be large, highly legible, and visually dominant.',
    'Use tight but controlled letter spacing.',
    'Maintain a clean separation between the headline and the floating product.',
    'Do not overlap the text with the product.',
    'The typography should feel fun, confident, modern, and professionally designed.',
    'Avoid generic default fonts or distorted lettering.',
    ...(insignia
      ? [
          '8. PROMOTIONAL BADGE',
          cartel
            ? 'Place a clean circular promotional badge to the left of the floating product, between the product and the headline, in the upper-middle area.'
            : 'Place a clean circular promotional badge to the right of the floating product, approximately in the upper-middle area.',
          `Badge color: warm ivory ${MARFIL}.`,
          `Inside the badge, use bold dark-${color ? verde : 'green'} uppercase typography.`,
          'Use the exact promotional text, in two or three centered lines:',
          `"${insignia}"`,
          'Keep the text centered and highly legible.',
          'The badge should be prominent but smaller than the hero product.',
          'Add one small, clean, curved white arrow pointing from the badge toward the product.',
          'The arrow should resemble a simple hand-drawn advertising graphic.',
          'Avoid excessive decoration.',
        ]
      : ['8. NO BADGE', 'Do not add any promotional badge, circle, sticker, or arrow.']),
    '9. BRAND AREA',
    `In the upper-left corner, include a small, refined brand name:\n"${marca}"`,
    'Use clean, compact, white sans-serif typography.',
    'The brand should remain secondary to the product and main headline.',
    'Do not invent additional logos or symbols.',
    '10. BOTTOM INFORMATION',
    `At the bottom of the ${pieza}, include a compact horizontal information row.`,
    `Use ${['', 'one small element', 'two small elements', 'three small elements'][renglon.length]}:`,
    ...renglon.map((dato, i) => `${lados[i]}:\n"${dato}"`),
    'Use small, clean, cream-colored typography.',
    'You may use restrained thin outlines or small separators to organize the information.',
    ...(r.direccion ? ['If the address is long, set it smaller so the whole row fits on one line.'] : []),
    'Keep the bottom row elegant and legible.',
    'Do not invent phone numbers, addresses, websites, or social media handles.',
    '11. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. Floating product.\n2. Large "${titular}" headline.\n${insignia ? '3. Circular promotional badge.\n4. Small brand name.\n5. Bottom information row.' : '3. Small brand name.\n4. Bottom information row.'}`,
    `The design must feel balanced and intentional.`,
    'Use generous negative space where possible.',
    `Do not overcrowd the ${pieza} with unnecessary graphic elements.`,
    'The product and headline must remain the strongest visual features.',
    '12. STRICT EXCLUSIONS',
    'Do not change the product into a different dish.',
    'Do not create several copies of the product.',
    'Do not split the product into separate halves.',
    color ? 'Do not use a background of a different color, or a white or black background.' : 'Do not use a red, white, orange, or black background.',
    'Do not add a visible floor or tabletop.',
    'Do not add unrelated ingredients.',
    'Do not make the food look like a 3D render.',
    'Do not use excessive gloss, plastic-looking textures, or artificial lighting effects.',
    'Do not add any text beyond the explicitly requested copy, and spell every word exactly as written, with its accents.',
    'Do not distort the headline or promotional text.',
    '13. FINAL QUALITY STANDARD',
    `The finished ${pieza} must look like a genuine professionally designed fast-food advertising campaign.`,
    `One authentic product floats dynamically against a rich ${verde} gradient background.`,
    'A restrained number of fresh ingredients surrounds the product.',
    `A large, playful, warm-ivory "${titular}" headline occupies the ${cartel ? 'left half' : 'lower-middle section'}.`,
    ...(insignia ? ['A circular promotional badge communicates the offer clearly.'] : []),
    'Small, clean brand and informational elements complete the design.',
    'The product must look physically believable, freshly prepared, and genuinely appetizing.',
    'The composition must be bold, contemporary, commercial, and polished.',
    'ABSOLUTE FINAL PRIORITY',
    'AUTHENTIC MEXICAN FOOD.',
    `DEEP ${verde.toUpperCase()} GRADIENT.`,
    'DYNAMIC FLOATING HERO PRODUCT.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    `LARGE PLAYFUL "${titular}" TYPOGRAPHY.`,
    ...(insignia ? ['CLEAR CIRCULAR PROMOTIONAL BADGE.'] : []),
    'PROFESSIONAL FAST-FOOD ADVERTISING DESIGN.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
