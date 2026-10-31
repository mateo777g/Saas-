// Estilo 10 · Desayunos (cafeteria.txt): un titular de letra de cafetería (palabras grandes en
// manuscrita y chiquitas en mayúsculas condensadas) sobre el producto de Don Chuy en su plato largo y un
// capuchino que rellena, en un fondo crema a verde salvia. Lleva 1 o 2 productos; una bebida toma el lugar
// del capuchino. El titular es su mensaje tal cual (la IA de la imagen escoge qué palabras van grandes, sin
// cambiar ninguna); vacío, «EL Café SABE MEJOR EN BUENA compañía». Su color pinta el fondo, el recuadro y
// las letras, con su misma luz.
import { AUTENTICO, comoEs, contactoDelCartel, lienzo, luzCalida, mayus, nombreDelColor, pintar } from './comun';
import type { Anuncio, Estilo } from './comun';

// El salvia primero: con él se mide la saturación de la marca.
const TONOS = {
  salvia: '#C8C685',
  crema: '#F4F3E9',
  cremaMedio: '#E7E2C9',
  salviaHondo: '#BFBE77',
  olivo: '#2B3900',
};
const CREMA_LETRA = '#F4F3E9';

export const desayunos: Estilo = {
  clave: 'desayunos',
  maximo: 2,
  minimo: 1,
  mensaje: 40,
  mayusculas: false,
  conColor: true,
  vacio: 'EL Café SABE MEJOR EN BUENA compañía',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const n = a.productos.length;
  const color = a.color;
  const t = pintar(color, TONOS);
  const salvia = color ? nombreDelColor(color) : 'sage green';
  const olivo = color ? `dark ${nombreDelColor(color)}` : 'dark olive green';
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, false) : null;

  const titular = a.mensaje
    ? [
        `Build one centered typographic lockup, in ${olivo} ${t.olivo}, that reads exactly, with every word in this order and nothing added or removed:`,
        `"${a.mensaje}"`,
        'It combines two kinds of lettering:',
        '* LARGE SCRIPT WORDS: choose the one or two most expressive words and write them in a smooth, elegant, monoline handwritten script with long, flowing, rounded strokes, exactly as written above, with their accents.',
        '* SMALL WORDS: every other word, in a tall, condensed, clean sans-serif, uppercase, much smaller than the script words.',
        'Arrange it on two or three rows, centered, with thin horizontal lines and short rows of evenly spaced small dots beside the small words, like a premium café menu.',
      ]
    : [
        `Build one centered typographic lockup, in ${olivo} ${t.olivo}, that reads exactly, in this order:`,
        '"EL Café SABE MEJOR EN BUENA compañía"',
        'It combines two kinds of lettering:',
        '* LARGE SCRIPT WORDS: "Café" and "compañía", in a smooth, elegant, monoline handwritten script with long, flowing, rounded strokes and a large decorative capital C in "Café". Exactly as written: "Café" with a capital C and an accent on the é, "compañía" all lowercase, with its ñ and its accent on the í.',
        '* SMALL WORDS: "EL", "SABE MEJOR", "EN", and "BUENA", in a tall, condensed, clean sans-serif, uppercase, much smaller than the script words.',
        'Arrange it on three rows:',
        'ROW 1:',
        `"Café" very large, spanning about ${cartel ? '35% of the banner width' : '65% of the poster width'}. The small word "EL" sits in the empty space above the right part of "Café", followed by one thin horizontal line extending to the right.`,
        'ROW 2:',
        '"SABE MEJOR", small and centered, with a short row of evenly spaced small dots on each side of it.',
        'ROW 3:',
        'On the left, "EN" above "BUENA", stacked, small. To their right, "compañía" very large. One thin horizontal line runs under "EN BUENA".',
      ];

  // Dónde va cada producto: una bebida toma el lugar del capuchino; lo demás va en el plato.
  const acomodo =
    n === 1
      ? [
          `On a long, narrow, rectangular white porcelain plate, placed diagonally in the lower ${cartel ? 'part of the right half' : 'right'}, put product 1.`,
          'Behind the plate, on the left, a plain cappuccino in a paper cup fills the set (see below).',
          'If product 1 is a drink, it takes the place of the cappuccino, there is no cappuccino, and the plate is left out.',
        ]
      : [
          `On a long, narrow, rectangular white porcelain plate, placed diagonally in the lower ${cartel ? 'part of the right half' : 'right'}, put product 1 and product 2 side by side, product 1 in front.`,
          'If one of the two products is a drink, it takes the place of the cappuccino, there is no cappuccino, and the other product goes alone on the plate.',
        ];

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'TOP-LEFT CORNER:',
        `A small ${olivo} brand block.`,
        'TOP-RIGHT CORNER:',
        'A small round typographic seal.',
        'LEFT HALF, FROM ABOUT 22% TO 85% OF THE HEIGHT:',
        'The typographic headline, centered in the left half.',
        'RIGHT HALF:',
        'The food and the drink on the seamless backdrop.',
        ...(contacto ? ['BOTTOM-LEFT CORNER:', 'The phone and the address, small.'] : []),
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP-LEFT CORNER:',
        `A small ${olivo} brand block.`,
        'TOP-RIGHT CORNER:',
        'A small round typographic seal.',
        'CENTER, FROM ABOUT 18% TO 58% OF THE HEIGHT:',
        'The typographic headline, centered.',
        'BOTTOM, FROM ABOUT 60% TO 95% OF THE HEIGHT:',
        'The food and the drink.',
      ];

  const secciones = [
    'STYLE_13 — MORNING CAFÉ LETTERING',
    'Premium Mexican Café Advertising — Breakfast Campaign',
    `Create a professionally art-directed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} advertisement for a Mexican café, featuring an elegant typographic headline that mixes large flowing script words with small condensed uppercase words, ${cartel ? 'beside' : 'above'} ${n === 1 ? 'one product' : 'two products'} photographed simply and naturally, against a soft cream-to-${salvia} background.`,
    'THIS IS A TYPOGRAPHY-LED, CALM, ELEGANT BREAKFAST AD: the headline lettering is the main design element, and the food and the drink are photographed simply and naturally.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    'The composition must feel calm, airy, balanced, and clearly designed.',
    `2. BACKGROUND — CREAM TO ${salvia.toUpperCase()}`,
    'Use a smooth diagonal gradient:',
    `* Almost white warm cream at the top right, about ${t.crema}.`,
    `* Warm cream at the top center, about ${t.cremaMedio}.`,
    `* Soft ${color ? salvia : 'yellowish sage green'} at mid-height on the left, about ${t.salvia}.`,
    `* Deeper ${salvia} at the bottom left, about ${t.salviaHondo}.`,
    'The gradient is soft, smooth, and photographic, like a seamless studio backdrop lit from the upper right.',
    'The surface under the plate and the cup is the same seamless backdrop: no table edge, no horizon, no wood, no tablecloth.',
    'No patterns.',
    'No textures.',
    'No decorative shapes.',
    ...luzCalida(color, 'the background, the brand block, and the lettering'),
    '3. THE TYPOGRAPHIC HEADLINE — THE MAIN DESIGN ELEMENT',
    ...titular,
    'The script words are the largest and most expressive; the small words are neat, evenly spaced, and aligned.',
    'Every word must be correctly spelled, with its accents.',
    'The lockup must look professionally lettered and typeset, like a premium café campaign.',
    'No outlines.',
    'No drop shadows.',
    'No 3D effects.',
    'No textures.',
    'No extra words.',
    '4. THE CAPPUCCINO',
    'Unless a product is a drink, place ONE plain takeaway paper cup of cappuccino behind the plate, on the left.',
    'The cup is white with a plain terracotta-orange band around its middle, and no logo, no text, and no lid.',
    'A soft dome of creamy milk foam rises slightly above the rim, with a light dusting of cinnamon.',
    'The cup stands on the backdrop surface, with a soft natural shadow.',
    'NO branding.',
    'NO logos.',
    'NO text on the cup.',
    'NO fabricated brand labels.',
    `5. ${n === 1 ? 'HERO PRODUCT' : 'THE PRODUCTS'}`,
    ...a.productos.map((p, i) => `* Product ${i + 1}: ${comoEs(p)}`),
    ...acomodo,
    ...AUTENTICO,
    'Show only these products, each one once. Besides the cappuccino of the set, do not add any other food or drink, and do not repeat a product to fill space.',
    'Show the plate from a slightly elevated front view, so the top of the food is clearly visible.',
    '6. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The cup, the food, and the plate must appear to have been photographed with a real camera under controlled studio lighting.',
    'Use a large soft light from the upper-right and gentle neutral fill lighting.',
    'Preserve natural shadows and realistic textures.',
    'Add natural, soft contact shadows under the plate and the cup, falling toward the lower left.',
    'Bread should look soft and freshly baked, and cooked meat moist, never lacquered.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '7. BRAND BLOCK',
    `In the top-left corner, place a small solid ${olivo} rectangle, ${t.olivo}, attached to the top edge of the ${pieza}, about ${cartel ? '13% of the banner width and 22% of its height' : '22% of the poster width and 16% of its height'}.`,
    `Inside it, centered, the brand name, in one, two, or three lines:\n"${marca}"`,
    'Use a bold, clean sans-serif, uppercase.',
    `Text color: warm cream ${CREMA_LETRA}.`,
    'Do not invent logos or symbols.',
    '8. SEAL',
    `In the top-right corner, place a small round typographic seal, without a filled background, in ${olivo} ${t.olivo}:`,
    'The word "Desayunos" in the same script as the headline, in the center, and the words "BUENOS DÍAS" in small condensed uppercase letters curving along an arc below it.',
    'Keep it small and secondary.',
    ...(contacto
      ? [`In the bottom-left corner, one small line in the condensed sans-serif, in ${olivo} ${t.olivo}, reading exactly: ${contacto}`]
      : []),
    '9. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The typographic headline.\n2. ${n === 1 ? 'Product 1' : 'The two products'}.\n3. The drink.\n4. The brand block.\n5. The seal.`,
    'Keep generous empty space around the headline.',
    `Do not overcrowd the ${pieza} with unnecessary graphic elements.`,
    '10. STRICT EXCLUSIONS',
    'Do not include toast, tomato, salsa, butter, jam, fruit, cutlery, napkins, or any other food or object.',
    'Do not include more than one cup.',
    'Do not include any logo, brand, or text on the cup or the plate.',
    contacto
      ? 'Do not include prices, promotions, websites, calls to action, or trademark symbols.'
      : 'Do not include prices, promotions, phone numbers, addresses, websites, calls to action, or trademark symbols.',
    `Do not add any text beyond the headline, the brand name, and the seal${contacto ? ', and the phone and the address' : ''}.`,
    'Do not add small print, disclaimers, or legal notes.',
    'Do not use a wooden table, tablecloth, marble, or a visible table edge.',
    'Do not make the food, the cup, or the plate look like a 3D render.',
    '11. FINAL PRIORITY',
    `An elegant ${olivo} typographic headline that mixes large flowing script words with small condensed uppercase words, thin lines, and dotted rules, reading "${a.mensaje ?? 'EL Café SABE MEJOR EN BUENA compañía'}".`,
    `${cartel ? 'Beside' : 'Below'} it, the food and the drink, photographed simply and naturally, against a soft cream-to-${salvia} background.`,
    `A small ${color ? nombreDelColor(color) : 'olive'} brand block at the top left and a small typographic seal at the top right.`,
    'Calm, warm, elegant, premium café breakfast advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'PROFESSIONAL LETTERING, CORRECTLY SPELLED.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
