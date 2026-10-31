// Estilo 23 · Barda (muro-azul.txt): el producto de Don Chuy parado en la orilla de una barda de aplanado
// azul, al sol, contra un cielo azul; arriba, un titular blanco enorme con la broma del paso de texto
// («ESTO NO ES / UN TACO»); dos flechas amarillas a mano que lo señalan; su mensaje en la etiqueta amarilla
// (vacío, «ES EL MEJOR / DE LA CUADRA») y el nombre del restaurante chiquito en la barda. Su color pinta la
// barda y el cielo; las flechas y la etiqueta siguen amarillas.
import { AUTENTICO, cap, comoEs, contactoDelCartel, fotografia, letraSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow: la cara de la barda (el principal), donde le da el sol, su
// sombra y el cielo arriba y abajo.
const TONOS = { barda: '#007AF0', bardaSol: '#0685EE', sombra: '#004499', cieloArriba: '#004891', cieloAbajo: '#0081F7' };
const FLECHAS = '#DCFE04';
const ETIQUETA = '#F4E300';

export const barda: Estilo = {
  clave: 'barda',
  maximo: 1,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: true,
  vacio: 'ES EL MEJOR DE LA CUADRA',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [
    {
      clave: 'broma',
      nombre: 'El titular',
      tope: 26,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Una broma con el producto en dos renglones separados por « / »: «ESTO NO ES» y, abajo, la palabra que más dice el producto con su artículo («Taco al pastor» → «ESTO NO ES / UN TACO», «Torta ahogada» → «ESTO NO ES / UNA TORTA», «Gringa de suadero» → «ESTO NO ES / UNA GRINGA»).',
      forma: { regla: /^[^/]+ \/ [^/]+$/u, explica: 'va en dos renglones, como «ESTO NO ES / UN TACO».' },
    },
  ],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const p = a.productos[0];
  const color = a.color;
  const t = pintar(color, TONOS);
  const azul = color ? nombreDelColor(color) : 'blue';
  // Con un color claro, las letras de encima van oscuras: el titular sobre el cielo y la marca sobre la barda.
  const enCielo = letraSobre(t.cieloArriba, 'clean white');
  const enBarda = letraSobre(t.barda);
  const [arriba, abajo] = a.palabras.broma.split(' / ');
  const etiqueta = a.mensaje ? mayus(a.mensaje) : null;
  const etiquetaEntera = etiqueta ?? 'ES EL MEJOR / DE LA CUADRA';
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'The sky fills the banner from the top down to about 62% of the height.',
        'The top edge of the wall is one straight, slightly tilted line at about 60% to 64% of the height, rising a little toward the right.',
        'The front face of the wall fills the banner from that edge down to the bottom.',
        'AT ABOUT 8% TO 52% OF THE HEIGHT, FROM ABOUT 5% TO 52% OF THE WIDTH: the headline, in two lines, aligned left.',
        'THE PRODUCT stands on the edge of the wall, at about 56% to 86% of the width, between about 8% and 63% of the height.',
        'THE LABEL sits to the right of the product, near the wall edge, at about 50% to 58% of the height.',
        'THE ARROWS: one curving from the end of the headline toward the product; one rising from the wall face below the product, pointing up at it.',
        `AT ABOUT 80% TO 94% OF THE HEIGHT, bottom left, on the wall face: the restaurant name${contacto ? ', and below it the phone and the address, smaller' : ''}.`,
      ]
    : [
        lienzo(a.formato),
        'The sky fills the poster from the top down to about 68% of the height.',
        'The top edge of the wall is one straight, slightly tilted line at about 66% to 70% of the height, rising a little toward the right.',
        'The front face of the wall fills the poster from that edge down to the bottom.',
        'AT ABOUT 6% TO 26% OF THE HEIGHT: the headline, in two lines, spanning about 90% of the width.',
        'THE PRODUCT stands on the edge of the wall, centered, slightly right of center, between about 28% and 69% of the height.',
        'THE LABEL sits to the right of the product, near the wall edge, at about 62% to 68% of the height.',
        "THE ARROWS: one on the left side, curving up toward the product; one rising from the wall face below, pointing up at the product.",
        'AT ABOUT 92% OF THE HEIGHT, bottom left, on the wall face: the restaurant name.',
      ];

  const secciones = [
    'STYLE_26 — SUNLIT WALL LEDGE',
    `Bold Playful Food Advertising — One Product on a ${cap(azul)} Wall in the Sun`,
    `Create a professionally art-directed ${QUE_ES[a.formato]}: a real photograph of one authentic Mexican product standing on the top edge of a ${azul} painted stucco wall, in hard direct sunlight, against a deep ${azul} sky, with a huge ${enCielo} headline ${cartel ? 'beside' : 'above'} it, two hand-drawn neon yellow arrows pointing at it, one small yellow label, and the restaurant name small on the wall.`,
    'THIS IS A REAL PHOTOGRAPHED SCENE with one strong light, the sun: the product, the wall, and the shadow share the same light. The headline, the arrows, and the label are graphics placed on top, like a bold street poster.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. THE SKY',
    `A clear, deep ${azul} sky with no clouds, darker at the top, approximately ${t.cieloArriba}, and brighter toward the wall, approximately ${t.cieloAbajo}.`,
    'A smooth, natural photographic gradient, with a very subtle fine film grain.',
    'No clouds, no sun disc, no birds, no other objects.',
    `3. THE ${azul.toUpperCase()} WALL`,
    `A real wall covered in coarse cement stucco plaster, painted a vivid, slightly saturated ${azul}, approximately ${t.barda}, a little brighter where the sun hits, approximately ${t.bardaSol}.`,
    'The plaster has a clearly visible rough, bumpy texture with small irregular dents and grains, especially on the front face.',
    'Its top edge is a clean, slightly rounded concrete edge.',
    `The product casts one long, hard, dark shadow, approximately ${t.sombra}, that falls down the front face of the wall, below and slightly to the left of the product.`,
    'A single small drip runs down from the edge of the wall, just below the product: a drop of its own salsa or sauce or, if it has none, a drop that fits it, like syrup or condensation.',
    '4. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'It stands on the edge of the wall, slightly turned toward the viewer so its top and its filling are clearly visible.',
    `It is photographed up close so it fills about ${cartel ? '30% of the banner width' : '65% of the poster width'}.`,
    'It stands on a small square of white wax paper on the edge of the wall. If it is a drink, it stands directly on the edge, in its own plain cup or glass, with no logo and no text.',
    fotografia(5, [
      'The scene must appear to have been photographed outdoors with a real camera, from slightly below the edge of the wall, looking a little upward at the product against the sky.',
      'Use one hard, direct sunlight from the upper right, which gives the food bright highlights and crisp, dark shadows, and shows every bump of the plaster.',
      'The light on the food stays warm and natural.',
      ...luzCalida(color, 'the wall and the sky'),
    ]),
    '6. HEADLINE',
    `${cartel ? 'On the left, over the sky, in two lines aligned left' : 'At the top, over the sky, in two centered lines'}, reading exactly:`,
    `"${arriba}"`,
    `"${abajo}"`,
    'Use a heavy, bold, wide geometric sans-serif, all uppercase, tight letter spacing.',
    `Color: ${enCielo}.`,
    cartel
      ? 'Both lines are huge, about 47% of the banner width.'
      : 'Both lines are huge, about 90% of the poster width; the top of the product may overlap the bottom of the second line slightly.',
    '7. THE ARROWS',
    `Two hand-drawn arrows, like thick marker strokes, in neon yellow, approximately ${FLECHAS}, flat, with no shadow:`,
    cartel
      ? '* One curving from the end of the headline and pointing at the upper left of the product.'
      : '* One on the left, curving up from about 55% of the height and pointing at the upper left of the product.',
    '* One rising from the wall face below the product and pointing up at it.',
    '8. THE LABEL',
    `One small flat rectangle in bright yellow, approximately ${ETIQUETA}, with bold black uppercase text inside, ${etiqueta ? 'on one or two lines (breaking only between words)' : 'on two lines'}, reading exactly:`,
    ...(etiqueta ? [`"${etiqueta}"`] : ['"ES EL MEJOR"', '"DE LA CUADRA"']),
    `Use a bold, condensed sans-serif. The label looks like a sticker placed flat on the ${pieza}.`,
    '9. BRAND',
    `At the bottom left, on the wall face, one small line in the same font as the headline, in ${enBarda}, reading exactly:`,
    `"${marca}"`,
    ...(contacto ? [`Below it, one smaller line in the same font, in ${enBarda}, reading exactly: ${contacto}`] : []),
    '10. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product on the edge of the wall.\n2. The ${enCielo} headline.\n3. The yellow arrows and the yellow label.\n4. The restaurant name${contacto ? ', then the phone and the address' : ''}.`,
    `Keep the composition bold, playful, and clean, with plenty of ${azul} sky around the product.`,
    'Spell every word exactly as written, with its accents.',
    '11. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the product described above.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, boards, cutlery, napkins, hands, or people.',
    'Do not include clouds, buildings, plants, or other objects in the sky.',
    `Do not include logos, watermarks, trademark symbols, prices, ${contacto ? '' : 'phone numbers, '}websites, or social media handles.`,
    `Do not add any text beyond the headline, the label, and the restaurant name${contacto ? ', the phone and the address' : ''}.`,
    'Do not use script fonts, distressed lettering, drop shadows on the text, or 3D text.',
    'Do not make the food or the wall look like a 3D render.',
    '12. FINAL PRIORITY',
    `A real outdoor photograph of one authentic product standing on the edge of a rough ${azul} stucco wall in hard sunlight, its long dark shadow falling down the wall, against a deep ${azul} sky.`,
    `The huge ${enCielo} headline "${arriba} / ${abajo}", two neon yellow hand-drawn arrows pointing at the product, a yellow label "${etiquetaEntera}", and "${marca}" small at the bottom left.`,
    'Bold, playful, appetizing, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
