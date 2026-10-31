// Estilo 22 · Banderitas (banderitas.txt): los productos de Don Chuy en fila sobre azulejo, cada uno
// con su banderita de papel. Su color pinta el azulejo y las banderitas. Lleva de 1 a 5 productos:
// con menos de los 3 de la muestra van solo los suyos, más grandes; con más, más chicos. Cada
// banderita lleva el nombre corto de su producto (el paso de texto, 12 letras).
import { AUTENTICO, cap, comoEs,contactoDelCartel, CUANTOS, fotografia, letraSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow.
const TONOS = {
  pared: '#BD2622',
  paredSombra: '#B52420',
  pisoLuz: '#ED5A55',
  pisoFondo: '#C42D29',
  bandera: '#DE3835',
  sombras: '#7E201F',
};

// De izquierda a derecha, qué producto va en cada lugar: el 1 al centro (o lo más cerca), al frente.
const ACOMODO: Record<number, number[]> = { 1: [1], 2: [1, 2], 3: [3, 1, 2], 4: [3, 1, 2, 4], 5: [4, 2, 1, 3, 5] };
const LUGAR = ['FAR LEFT', 'LEFT', 'CENTER', 'RIGHT', 'FAR RIGHT'];
const LUGARES: Record<number, string[]> = {
  1: ['CENTER'],
  2: ['LEFT', 'RIGHT'],
  3: ['LEFT', 'CENTER', 'RIGHT'],
  4: ['FAR LEFT', 'LEFT', 'RIGHT', 'FAR RIGHT'],
  5: LUGAR,
};
// Cuánto del ancho ocupa la fila.
const ANCHO: Record<number, number> = { 1: 45, 2: 75, 3: 90, 4: 92, 5: 94 };

export const banderitas: Estilo = {
  clave: 'banderitas',
  maximo: 5,
  minimo: 1,
  mensaje: 20,
  mayusculas: true,
  conColor: true,
  vacio: 'HAY PARA TODOS',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [
    {
      clave: 'banderita',
      nombre: 'La banderita',
      tope: 12,
      mayusculas: true,
      cuando: 'por_producto',
      pide: 'El nombre corto del producto para su banderita de papel: la palabra que más lo dice («Torta de pastor con queso» → «TORTA», «Agua de horchata» → «HORCHATA»). Si el nombre ya es corto, el nombre tal cual. Cada banderita distinta de las demás.',
    },
  ],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const n = a.productos.length;
  const color = a.color;
  const t = pintar(color, TONOS);
  const rojo = color ? nombreDelColor(color) : 'red';
  const banderas = `${n === 1 ? '' : 'each one with '}a small ${rojo} paper flag on a white toothpick`;
  // Con un color claro, las letras de encima van oscuras: el titular sobre la pared, el nombre de
  // cada banderita sobre su papel y la marca sobre el piso de enfrente.
  const enPared = letraSobre(t.pared);
  const enBandera = letraSobre(t.bandera);
  const enPiso = letraSobre(t.pisoLuz);
  const titular = a.mensaje ? mayus(a.mensaje) : null;
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  const banderita = (i: number) => a.palabras[`banderita_${i}`];
  const productos = n === 1 ? 'one Mexican product' : `${CUANTOS[n]} Mexican products`;
  const fila = n === 1 ? 'standing alone on the tiled floor' : 'standing in a row on the tiled floor';

  // Dónde va cada producto, de izquierda a derecha.
  const enFila = ACOMODO[n].map((numero, i) => {
    const lugar = LUGARES[n][i];
    const foco = numero === 1 && n > 1 ? ', slightly in front of the others, the focus of the image' : '';
    return `* ${lugar}: product ${numero}${foco}.`;
  });

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'The tiled wall fills the banner from the top down to about 55% of the height.',
        'The tiled floor fills the banner from about 55% of the height down to the bottom, seen in gentle perspective, with its grout lines running toward the back.',
        `AT ABOUT 8% TO 30% OF THE HEIGHT, on the wall: the headline, centered.`,
        `THE ${n === 1 ? 'PRODUCT stands' : 'PRODUCTS stand in one row'} on the floor, across about ${Math.min(ANCHO[n], 80)}% of the banner width, with ${n === 1 ? 'its base' : 'their bases'} at about 78% to 82% of the height:`,
        ...enFila,
        `${n === 1 ? 'The product has its flag' : 'Each product has its flag'} sticking up from it, rising to between about 36% and 50% of the height${n === 1 ? '' : ', at slightly different heights and angles'}.`,
        'AT ABOUT 87% TO 96% OF THE HEIGHT, on the floor: the restaurant name, centered' + (contacto ? ', and below it the phone and the address, smaller.' : '.'),
      ]
    : [
        lienzo(a.formato),
        'The tiled wall fills the poster from the top down to about 60% of the height.',
        'The tiled floor fills the poster from about 60% of the height down to the bottom, seen in gentle perspective, with its grout lines running toward the back.',
        'AT ABOUT 8% TO 30% OF THE HEIGHT, on the wall: the headline, centered.',
        `THE ${n === 1 ? 'PRODUCT stands' : `${CUANTOS[n].toUpperCase()} PRODUCTS stand in one row`} on the floor, across about ${ANCHO[n]}% of the poster width, with ${n === 1 ? 'its base' : 'their bases'} at about 72% to 76% of the height:`,
        ...enFila,
        `${n === 1 ? 'The product has its flag' : 'Each product has its flag'} sticking up from it, rising to between about 34% and 46% of the height${n === 1 ? '' : ', at slightly different heights and angles'}.`,
        'AT ABOUT 90% TO 94% OF THE HEIGHT, on the floor: the restaurant name, centered.',
      ];
  if (n === 1) composicion.push('With a single product, draw it larger, as the clear hero of the set.');
  if (n >= 4) composicion.push(`Because there are ${CUANTOS[n]} products, draw each one smaller than in a row of three, so they all fit comfortably without crowding.`);

  const cadaProducto = a.productos.flatMap((p, i) => [
    `* Product ${i + 1}: ${comoEs(p)}`,
    `  It sits on a small square of white wax paper on the tiles${i === 0 && n > 1 ? ', and it is the focus of the image' : ''}.`,
  ]);

  const banderasTexto = a.productos.map((_, i) => `* On product ${i + 1}'s flag: "${banderita(i + 1)}"`);

  const secciones = [
    `STYLE_25 — FLAG PICKS ON ${rojo.toUpperCase()} TILE`,
    `Bold Food Photography Advertising — ${n === 1 ? 'A Product' : 'A Row of Products'} on a ${cap(rojo)} Tiled Set`,
    `Create a professionally art-directed ${QUE_ES[a.formato]}: a real photograph of a corner covered in glossy ${rojo} square ceramic tiles with white grout, wall and floor, with ${productos} ${fila}, ${banderas}, a bold ${enPared} headline on the tiled wall, and the restaurant name small on the floor.`,
    `THIS IS A REAL PHOTOGRAPHED SET with one strong light, not a collage: the ${n === 1 ? 'product, the flag' : 'products, the flags'}, and the tiles share the same light, shadows, and reflections.`,
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    `2. THE ${rojo.toUpperCase()} TILED SET`,
    `Square glossy ceramic tiles, all the same size, each about ${cartel ? '8% of the banner width' : '13% of the poster width'} on the wall.`,
    `Wall tiles: deep ${rojo}, approximately ${t.pared}, slightly darker in the shadows, approximately ${t.paredSombra}.`,
    `Floor tiles: the same ${rojo}, brighter where the light hits, approximately ${t.pisoLuz} near the front, and approximately ${t.pisoFondo} toward the back.`,
    'Grout: thin, clean, very light warm white lines, perfectly straight, on the wall and the floor.',
    'The wall meets the floor in one straight horizontal line.',
    `The tiles are glossy: soft highlights and gentle reflections of the ${n === 1 ? 'product' : 'products'} on the floor, never mirror-like.`,
    'No dirt, no cracks, no patterns, no other objects on the set.',
    `3. THE ${n === 1 ? 'PRODUCT' : 'PRODUCTS'}`,
    ...cadaProducto,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    '4. THE FLAGS',
    `${n === 1 ? 'The product has' : 'Each product has'} one small rectangular ${rojo} paper flag, approximately ${t.bandera}, glued around the top of a plain white wooden toothpick that is pushed into the product.`,
    `${n === 1 ? 'The flag is' : "Each flag is"} printed with its product's name in bold ${enBandera} uppercase letters, centered, reading exactly:`,
    ...banderasTexto,
    'Use a bold, slightly rounded, heavy sans-serif, sized to fill the flag.',
    `The ${n === 1 ? 'flag is' : 'flags are'} real paper: flat, slightly bent at the edges, catching the same light as the food.`,
    fotografia(5, [
      `The scene must appear to have been photographed with a real camera at food level, looking slightly down at the ${n === 1 ? 'product' : 'products'}, about 15° above the floor.`,
      `Use one strong, hard light from the upper front-left, which casts crisp dark shadows, approximately ${t.sombras}, from the ${n === 1 ? 'product and the flag' : 'products and the flags'} onto the tiles behind and to the right, plus gentle fill so the food stays bright and appetizing.`,
      'The light on the food stays warm and natural.',
      ...luzCalida(color, 'the tiles and the flags'),
    ]),
    '6. HEADLINE',
    titular
      ? `On the tiled wall, centered, in one or two lines (breaking only between words), reading exactly:\n"${titular}"`
      : 'On the tiled wall, in two centered lines, reading exactly:\n"HAY PARA"\n"TODOS"',
    'Use a heavy, bold, slightly condensed sans-serif, all uppercase, tight letter spacing.',
    `Color: clean ${enPared}.`,
    `The headline is printed flat on the ${cartel ? 'banner' : 'poster'}, over the tiles, large and confident, about ${cartel ? '50% of the banner width' : '80% of the poster width'}.`,
    '7. BRAND',
    `On the floor, centered, one small line in the same font as the headline, in ${enPiso}, reading exactly:\n"${marca}"`,
    ...(contacto ? [`Below it, one smaller line in the same font, in ${enPiso}, with the phone and the address, reading exactly: ${contacto}`] : []),
    '8. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. ${n === 1 ? 'The product' : 'The products in a row, product 1 first'}.\n2. The ${enPared} headline on the wall.\n3. The ${n === 1 ? 'flag with the product name' : 'flags with the product names'}.\n4. The restaurant name${contacto ? ', then the phone and the address' : ''}.`,
    `Keep the composition clean, symmetrical, and bold, with the ${rojo} tiles visible around everything.`,
    'Spell every word exactly as written, with its accents.',
    '9. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the products described above.',
    'Do not include plates, boards, trays, cutlery, napkins, hands, or people.',
    `Do not include logos, watermarks, badges, award seals, trademark symbols, prices, ${contacto ? '' : 'phone numbers, '}websites, or social media handles.`,
    `Do not add any text beyond the headline, the ${n === 1 ? 'flag' : 'flags'}, and the restaurant name${contacto ? ', the phone and the address' : ''}.`,
    'Do not use script fonts, distressed lettering, drop shadows on the printed text, or 3D text.',
    `Do not make the food, the ${n === 1 ? 'flag' : 'flags'}, or the tiles look like a 3D render.`,
    '10. FINAL PRIORITY',
    `A real photograph of a glossy ${rojo} tiled corner with white grout, lit by one strong hard light: ${n === 1 ? 'the product, on white wax paper with a small paper flag on a white toothpick naming it' : `${CUANTOS[n]} products in a row, product 1 at the front, each on white wax paper with a small paper flag on a white toothpick naming it`}.`,
    `The ${enPared} headline ${titular ? `"${titular}"` : '"HAY PARA / TODOS"'} on the wall and "${marca}" small on the floor.`,
    'Bold, appetizing, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
