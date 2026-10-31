// Estilo 13 · Mano (mano.txt): una mano sostiene el producto de Don Chuy, envuelto en papel encerado,
// delante de una palabra gigante repetida tres veces (la escoge el paso de texto: «Pastor»). Abajo, un
// párrafo justificado en mayúsculas: su mensaje (vacío, la descripción de Mi menú) y siempre, al final, el
// nombre del restaurante. Su color pinta la palabra; el crema se queda.
import { AUTENTICO, comoEs, contactoDelCartel, legibleSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const TONOS = { verde: '#448323' };
const CREMA = '#F3F0DD';
const LETRA = '#4A4733';

export const mano: Estilo = {
  clave: 'mano',
  maximo: 1,
  minimo: 1,
  mensaje: 160,
  mayusculas: true,
  conColor: true,
  vacio: '#desc',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [
    {
      clave: 'palabra',
      nombre: 'La palabra repetida',
      tope: 10,
      mayusculas: false,
      cuando: 'siempre',
      pide: 'Una sola palabra del nombre del producto, la que más lo dice, con mayúscula inicial y lo demás en minúsculas («Taco al pastor» → «Pastor», «Agua de horchata» → «Horchata», «Gringa» → «Gringa»).',
      forma: { regla: /^\S+$/u, explica: 'va en una sola palabra.' },
    },
  ],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const color = a.color;
  const verdeTono = color ? legibleSobre(pintar(color, TONOS).verde, CREMA) : TONOS.verde;
  const verde = color ? nombreDelColor(color) : 'green';
  const palabra = a.palabras.palabra;
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  // El párrafo: su mensaje o la descripción, y siempre al final el nombre del restaurante.
  const texto = a.mensaje ?? p.descripcion;
  const conPunto = texto ? (/[.!?…]$/u.test(texto.trim()) ? texto.trim() : `${texto.trim()}.`) : null;
  const parrafo = conPunto ? `${mayus(conPunto)} ${marca}.` : `${marca}.`;
  const corto = !conPunto;

  const filas = cartel
    ? [
        `The word "${palabra}" appears three times, stacked, each one spanning about 70% of the banner width, aligned to the left at about 6% of the width:`,
        `ROW 1, FROM ABOUT 6% TO 30% OF THE HEIGHT: solid ${verde}.`,
        'ROW 2, FROM ABOUT 36% TO 60%: outline only.',
        `ROW 3, FROM ABOUT 66% TO 90%: solid ${verde}.`,
        'The hand and the product rise from the bottom edge, at about 72% of the banner width, with the product between about 15% and 70% of the height.',
        `AT ABOUT 92% TO 97% OF THE HEIGHT, on the left: the small paragraph${contacto ? ' and, below or beside it, the phone and the address' : ''}.`,
      ]
    : [
        `The word "${palabra}" appears three times, stacked, each one spanning about 80% of the poster width:`,
        `ROW 1, FROM ABOUT 6% TO 20% OF THE HEIGHT: solid ${verde}.`,
        'ROW 2, FROM ABOUT 28% TO 42%: outline only.',
        `ROW 3, FROM ABOUT 56% TO 70%: solid ${verde}.`,
        'The hand and the product rise from the bottom edge, slightly right of center, with the product between about 22% and 62% of the height.',
        'AT ABOUT 84% TO 92% OF THE HEIGHT:',
        `A small ${corto ? 'centered line' : 'justified paragraph, about 80% of the poster width'}.`,
      ];

  const secciones = [
    'STYLE_16 — HAND-HELD REPEAT TYPE',
    'Bold Editorial Food Advertising — Hand-Held Product Poster',
    `Create a professionally designed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring one product, "${p.nombre}", wrapped at the bottom in white wax paper, held up by a real human hand rising from the bottom of the ${pieza}, in front of one huge ${verde} word repeated three times on a warm cream paper background, with a small ${corto ? 'line' : 'justified paragraph'} at the bottom.`,
    'THIS IS A BOLD EDITORIAL POSTER: giant repeated typography and one real photographed hand holding the product, layered together.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    lienzo(a.formato),
    ...filas,
    '2. BACKGROUND',
    `Use a warm cream paper background, approximately ${CREMA}.`,
    'It has a very subtle printed-paper feel: a few faint, soft, slightly darker cream patches, approximately #E9E4CF, mostly near the left edge.',
    `A very subtle fine film grain covers the whole image, like a printed ${pieza}.`,
    'No patterns.',
    'No strong textures.',
    'No gradients.',
    '3. THE REPEATED WORD — LAYERED TYPOGRAPHY',
    `The word is exactly "${palabra}", written three times, exactly as given.`,
    'Use a heavy, wide, soft-cornered grotesque sans-serif with friendly, slightly rounded letter shapes and tight letter spacing.',
    `Color: fresh ${verde} ${verdeTono}.`,
    ...luzCalida(color, 'the repeated word'),
    `ROW 1 is solid ${verde} and sits behind the top of the product: the top of the product overlaps its lower edge slightly.`,
    `ROW 2 is the same word drawn ONLY as a thin ${verde} outline, with no fill, and it is drawn ON TOP of the product, so the thin ${verde} lines cross over the food.`,
    `ROW 3 is solid ${verde} and sits BEHIND the hand and the product, partly hidden by them.`,
    `All three rows share the same size, font, and alignment, ${cartel ? 'aligned to the left' : 'perfectly centered'}.`,
    'No other words in this size.',
    'No trademark symbols.',
    '4. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'The product is held upright and slightly tilted toward the viewer, so its top and filling are clearly visible.',
    'The lower half of the product is wrapped in a sheet of slightly crumpled white wax paper, the kind a taquería uses, with soft natural folds.',
    `The product is large: about ${cartel ? '30% of the banner width' : '65% of the poster width'}.`,
    '5. THE HAND',
    `One real human hand rises from the bottom edge of the ${pieza}, ${cartel ? 'at about 72% of its width' : 'slightly right of center'}, holding the wrapped product from below with the fingers and thumb around the paper.`,
    'Natural skin with realistic texture and soft creases, short clean nails, no rings, no bracelets, no sleeve visible.',
    'Only the hand and part of the wrist are visible.',
    'The hand must look like a real photographed hand: correct anatomy, five fingers, natural proportions, never plastic or 3D-rendered.',
    '6. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    `The product, the paper, and the hand must appear to have been photographed together with a real camera under controlled studio lighting, then placed on the ${pieza}.`,
    'Use one large, soft but directional light from the upper-left, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
    'Preserve natural shadows and realistic textures.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    `7. ${corto ? 'BRAND LINE' : 'PARAGRAPH'}`,
    `Near the bottom of the ${pieza}, over the cream background and ${cartel ? 'on the left' : 'to the left of the wrist where needed'}, place ${corto ? 'one small line' : 'one small paragraph'} in uppercase, reading exactly:`,
    `"${parrafo}"`,
    'Use a clean, wide, light-weight geometric sans-serif, uppercase, small.',
    `Text color: dark olive gray ${LETRA}.`,
    corto
      ? 'Centered, with even letter spacing.'
      : 'Fully justified on two to four lines, including the last line, so the words spread out evenly across the full width.',
    ...(contacto ? [`Below it, one smaller line in the same font and color, reading exactly: ${contacto}`] : []),
    'Spell every word exactly as written, with its accents.',
    '8. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product held in the hand.\n2. The giant repeated word "${palabra}".\n3. The small ${corto ? 'line' : 'paragraph'}.`,
    'Keep the layout bold and clean.',
    'Do not add extra graphic elements.',
    '9. STRICT EXCLUSIONS',
    'Do not include any other food or drink.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, boards, cutlery, or napkins.',
    'Do not show more than one hand, a sleeve, jewelry, or a face.',
    contacto
      ? 'Do not include logos, trademark symbols, prices, websites, or social media handles.'
      : 'Do not include logos, trademark symbols, prices, phone numbers, websites, or social media handles.',
    `Do not add any text beyond the three repeated words and the ${corto ? 'line' : 'paragraph'}${contacto ? ', and the phone and the address' : ''}.`,
    'Do not use script fonts, distressed lettering, drop shadows, or 3D text.',
    'Do not make the food or the hand look like a 3D render.',
    '10. FINAL PRIORITY',
    `One authentic product, wrapped at the bottom in white wax paper, held up by a real hand rising from the bottom, layered with the giant ${verde} word "${palabra}" repeated three times: solid behind the product at the top, as a thin outline drawn over the product in the middle, and solid behind the hand below.`,
    `A small ${corto ? 'uppercase line' : 'justified uppercase paragraph'} at the bottom, on a warm cream paper background.`,
    'Bold, fresh, editorial, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'A REAL HAND, CORRECT ANATOMY.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
