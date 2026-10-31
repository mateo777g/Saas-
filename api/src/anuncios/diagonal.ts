// Estilo 17 · Diagonal (diagonal.txt): el fondo partido por una diagonal, rojo arriba y crema abajo; arriba
// el nombre del restaurante, el nombre del producto en un renglón chiquito y una palabra gigante partida en
// dos («PAS / TOR», del paso de texto); el producto grande cruzando la diagonal; su mensaje en la insignia
// (vacío, no sale: nunca inventa una promoción) y abajo la descripción, «ORDENA AHORA» y el teléfono. Su
// color pinta lo rojo: la parte de arriba, la insignia y los textos; el crema se queda.
import { AUTENTICO, comoEs, legibleSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow.
const TONOS = { rojo: '#940601' };
const CREMA = '#FEFBD6';

export const diagonal: Estilo = {
  clave: 'diagonal',
  maximo: 1,
  minimo: 1,
  mensaje: 24,
  mayusculas: true,
  conColor: true,
  vacio: null,
  datos: {
    post: ['nombre', 'telefono', 'ordena'],
    historia: ['nombre', 'telefono', 'ordena'],
    cartel: ['nombre', 'telefono', 'direccion', 'ordena'],
  },
  lugares: [
    {
      clave: 'partida',
      nombre: 'La palabra gigante',
      tope: 14,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Una sola palabra del nombre del producto, la que más lo dice, en mayúsculas y partida en dos mitades casi iguales, con « / » entre ellas («Taco al pastor» → «PAS / TOR», «Agua de horchata» → «HOR / CHATA», «Gringa» → «GRIN / GA»).',
      forma: { regla: /^[^\s/]+ \/ [^\s/]+$/u, explica: 'va partida en dos, como «PAS / TOR».' },
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
  const rojo = color ? `deep ${nombreDelColor(color)}` : 'deep red';
  // Lo rojo que va sobre el crema se oscurece si hace falta para leerse.
  const enCrema = color ? legibleSobre(t.rojo, CREMA) : t.rojo;
  const [arriba, abajo] = a.palabras.partida.split(' / ');
  const renglon = mayus(p.nombre);
  const insignia = a.mensaje ? mayus(a.mensaje) : null;
  const parrafo = p.descripcion?.trim() || null;
  const marca = mayus(a.restaurante.nombre);
  const telefono = a.restaurante.telefono;
  const direccion = cartel && a.restaurante.direccion ? mayus(a.restaurante.direccion) : null;
  const datos = [telefono, direccion].filter((d): d is string => !!d);
  const bloque = [parrafo ? 'a short paragraph' : null, 'a pill button', datos.length ? (direccion ? 'the phone number and the address' : 'the phone number') : null].filter(Boolean).join(', ');

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT, FROM ABOUT 5% TO 50% OF THE WIDTH:',
        'The brand name at about 5% to 12% of the height, then the small line at about 15% to 20%, then the enormous two-line word from about 22% to 62%, aligned left.',
        `BOTTOM LEFT, FROM ABOUT 78% TO 96% OF THE HEIGHT, on the cream area:`,
        `${bloque.charAt(0).toUpperCase()}${bloque.slice(1)}, aligned left.`,
        'RIGHT, FROM ABOUT 52% TO 95% OF THE WIDTH:',
        'The product, large, crossing the diagonal, centered at about 72% of the width, between about 14% and 90% of the height.',
        ...(insignia ? ['The promotional badge, overlapping the right edge of the product, at about 30% to 52% of the height.'] : []),
        'The composition must feel bold, clean, and clearly designed.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP, FROM ABOUT 3% TO 12% OF THE HEIGHT:',
        'The brand name, centered.',
        'FROM ABOUT 13% TO 40%:',
        'A small line of text, then the enormous two-line word, centered.',
        'CENTER, FROM ABOUT 38% TO 76%:',
        'The product, large, crossing the diagonal.',
        ...(insignia ? ['RIGHT SIDE, AT ABOUT 58% TO 72%:', 'The promotional badge, overlapping the right edge of the product.'] : []),
        'BOTTOM, FROM ABOUT 78% TO 96%:',
        `${bloque.charAt(0).toUpperCase()}${bloque.slice(1)}, centered on the cream area.`,
        'The composition must feel bold, clean, and clearly designed.',
      ];

  const secciones = [
    `STYLE_20 — ${rojo.replace('deep ', '').toUpperCase()} DIAGONAL SPLIT`,
    `Bold Graphic Fast-Food Advertising — Classic Promo ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally designed ${QUE_ES[a.formato]} featuring one large product over a background split diagonally into ${rojo} and cream, with an enormous cream word split across two lines${insignia ? ', a promotional badge,' : ''} and a short call-to-action block ${cartel ? 'at the bottom left' : 'at the bottom'}.`,
    'THIS IS A CLEAN, BOLD, CLASSIC PROMO DESIGN: flat colors, one diagonal, huge typography, and one real photographed product placed on the design.',
    'Prioritize authentic food photography and physically believable food over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. BACKGROUND — DIAGONAL SPLIT',
    'The background is divided by one straight diagonal line:',
    `Above the line, solid ${rojo}, approximately ${t.rojo}.`,
    `Below the line, solid light cream, approximately ${CREMA}.`,
    cartel
      ? 'The line runs from the left edge at about 74% of the banner height up to the right edge at about 46% of the height.'
      : 'The line runs from the left edge at about 71% of the poster height up to the right edge at about 50% of the height.',
    'Both areas are perfectly flat: no gradient, no texture, no pattern, no shadow.',
    '3. BRAND',
    `${cartel ? 'At the top left, aligned left' : 'At the top center'}, place the brand name on one line, reading exactly:`,
    `"${marca}"`,
    'Use a clean, bold, friendly sans-serif, medium-small size.',
    `Text color: cream ${CREMA}.`,
    'Do not invent logos or icons.',
    '4. SMALL LINE AND ENORMOUS WORD',
    `Below the brand, ${cartel ? 'aligned left' : 'centered'}, place one small line reading exactly:`,
    `"${renglon}"`,
    'Use an ultra-heavy, wide, extended sans-serif, uppercase, small.',
    'Directly below it, place one enormous word split across two lines, reading exactly:',
    `"${arriba}\n${abajo}"`,
    `Use the same ultra-heavy, wide, extended sans-serif, uppercase, with very tight line spacing, so the two halves form one solid block about ${cartel ? '42% of the banner width' : '75% of the poster width'}.`,
    `Text color: cream ${CREMA}.`,
    `The top of the product may overlap the bottom of "${abajo}" slightly.`,
    'No outlines.',
    'No drop shadows.',
    'No 3D effects.',
    '5. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'Show the product from a slightly elevated three-quarter front view, about 25 degrees above, so its top and its filling are clearly visible.',
    cartel
      ? 'The product is large: about 40% of the banner width, crossing the diagonal line.'
      : 'The product is large: about 75% of the poster width, centered slightly left, crossing the diagonal line.',
    '6. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product must appear to have been photographed with a real camera under controlled studio lighting, then cleanly placed on the design.',
    'Use one large, soft but directional light from the upper-left, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
    ...luzCalida(color, `the background${insignia ? ', the badge,' : ''} and the ${rojo.replace('deep ', '')} texts`),
    'Preserve natural shadows and realistic textures inside the product.',
    'Add only a soft, subtle shadow under the product.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    ...(insignia
      ? [
          '7. PROMOTIONAL BADGE',
          `${cartel ? 'Overlapping the right edge of the product' : 'On the right side, overlapping the right edge of the product'}, place one rectangular badge made of two stacked blocks:`,
          `The top block is cream ${CREMA} with small ${rojo} text; the bottom block is ${rojo} ${t.rojo} with enormous cream text.`,
          'Together, the two blocks read exactly, with every word in its order:',
          `"${insignia}"`,
          'Put the shortest, strongest part of it (a number, a price, or a short offer like "2X1") in the bottom block, enormous, and the rest in the top block, small, on one or two lines. Do not change, add, or drop any word. If it is only one or two short words, put it all in the bottom block and leave out the top block.',
          'Use the same ultra-heavy, wide, extended sans-serif for the bottom block and a bold sans-serif for the top block.',
          'The badge has crisp straight edges, no outline, no shadow.',
        ]
      : []),
    `${insignia ? '8' : '7'}. BOTTOM BLOCK — ON THE CREAM AREA`,
    ...(parrafo
      ? [
          `${cartel ? 'At the bottom left, aligned left' : 'Centered below the product'}, place a short paragraph on one or two lines, reading exactly:`,
          `"${parrafo}"`,
          'Use a clean, bold, friendly sans-serif, in sentence case, small to medium size.',
          `Text color: ${rojo} ${enCrema}.`,
          `Below it, one rounded pill button in ${rojo} ${enCrema} with cream text reading exactly:`,
        ]
      : [`${cartel ? 'At the bottom left, aligned left' : 'Centered below the product'}, place one rounded pill button in ${rojo} ${enCrema} with cream text reading exactly:`]),
    '"ORDENA AHORA"',
    ...(datos.length
      ? [`Below the pill, one line in ${rojo} ${enCrema} reading exactly: ${datos.map((d) => `"${d}"`).join(' and ')}`]
      : []),
    'Spell every word exactly as written, with its accents.',
    `${insignia ? '9' : '8'}. GRAPHIC HIERARCHY`,
    'Maintain this visual order:',
    [
      '1. The product.',
      `2. The enormous word "${arriba} ${abajo}".`,
      ...(insignia ? ['3. The promotional badge.'] : []),
      `${insignia ? '4' : '3'}. The bottom ${parrafo ? 'paragraph, pill' : 'pill'}${datos.length ? ', and phone number' : ''}.`,
      `${insignia ? '5' : '4'}. The brand name and the small line.`,
    ].join('\n'),
    'Keep the design clean and uncluttered.',
    'Do not add extra graphic elements.',
    `${insignia ? '10' : '9'}. STRICT EXCLUSIONS`,
    'Do not include any food or drink other than the product described above.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, boards, cutlery, or napkins.',
    'Do not add splashes, sparkles, flames, ribbons, stars, or extra shapes.',
    `Do not include ${insignia ? '' : 'badges, promotions, discounts, '}prices, ${telefono ? '' : 'phone numbers, '}websites, social media handles or icons, logos, or trademark symbols.`,
    `Do not add any text beyond the brand name, the small line, the enormous word${insignia ? ', the badge' : ''}${parrafo ? ', the paragraph' : ''}, the pill${datos.length ? `, and the ${direccion ? (telefono ? 'phone number and the address' : 'address') : 'phone number'}` : ''}.`,
    'Do not use script fonts, distressed lettering, outlines, or 3D text.',
    'Do not make the food look like a 3D render.',
    `${insignia ? '11' : '10'}. FINAL PRIORITY`,
    `One large authentic product crossing a straight diagonal that splits the background into flat ${rojo} above and flat cream below.`,
    `An enormous cream word "${arriba} / ${abajo}" in an ultra-heavy wide sans-serif ${cartel ? 'on the left' : 'at the top'}${insignia ? `, a "${insignia}" badge on the right` : ''}, and ${parrafo ? `a short ${rojo} paragraph, ` : ''}an "ORDENA AHORA" pill${datos.length ? ', and the phone number' : ''} at the bottom.`,
    'Bold, clean, classic, premium fast-food promo advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'FLAT, CLEAN GRAPHIC DESIGN.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
