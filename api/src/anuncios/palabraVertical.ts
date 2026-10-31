// Estilo 19 · Palabra vertical (cafe-vertical.txt): una palabra del nombre del producto (la escoge el paso
// de texto: «PASTOR») de pie, gigante, en crema sobre un panel salvia, pegada al panel crema de la derecha
// para fundirse con él; el producto de Don Chuy encima, con su sombra dura. Arriba a la izquierda, su
// mensaje como título (vacío, «El / Especial / de hoy»); abajo, el nombre, la dirección y el teléfono del
// restaurante, lo que haya. Su color pinta el panel de la izquierda; el crema se queda.
import { AUTENTICO, comoEs, fotografia, lienzo, luzCalida, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow.
const TONOS = { panel: '#849159' };
const CREMA = '#F4EDE5';

export const palabraVertical: Estilo = {
  clave: 'palabra-vertical',
  maximo: 1,
  minimo: 1,
  mensaje: 30,
  mayusculas: false,
  conColor: true,
  vacio: 'El Especial de hoy',
  datos: {
    post: ['nombre', 'telefono', 'direccion'],
    historia: ['nombre', 'telefono', 'direccion'],
    cartel: ['nombre', 'telefono', 'direccion'],
  },
  lugares: [
    {
      clave: 'vertical',
      nombre: 'La palabra vertical',
      tope: 10,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Una sola palabra del nombre del producto, la que más lo dice, en mayúsculas («Taco al pastor» → «PASTOR», «Agua de horchata» → «HORCHATA», «Capuchino» → «CAPUCHINO»).',
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
  const verde = color ? `muted ${nombreDelColor(color)}` : 'sage-green';
  const palabra = a.palabras.vertical;
  // Abajo a la izquierda, lo que haya, en el orden de la muestra: el nombre, la dirección y el teléfono.
  const r = a.restaurante;
  const datos = [r.nombre, r.direccion, r.telefono].filter((d): d is string => !!d);
  const renglones = ['zero', 'one', 'two', 'three'][datos.length];
  const alto = historia ? 'safe zone' : pieza;

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT 64% OF THE WIDTH:',
        `A flat ${verde} panel.`,
        'RIGHT 36%:',
        'A flat cream panel.',
        'FROM ABOUT 46% TO 64% OF THE WIDTH, FULL HEIGHT:',
        `The enormous vertical word, in cream, inside the ${verde} panel, with the right edge of its letters touching the cream panel.`,
        'RIGHT, FROM ABOUT 55% TO 85% OF THE WIDTH, FROM ABOUT 12% TO 88% OF THE HEIGHT:',
        'The product, large, standing over the right part of the letters and the cream panel.',
        'UPPER LEFT, FROM ABOUT 5% TO 40% OF THE WIDTH:',
        'The small title.',
        'LOWER LEFT:',
        `${renglones.charAt(0).toUpperCase()}${renglones.slice(1)} small ${datos.length === 1 ? 'line' : 'lines'} with the restaurant's details.`,
        'The composition must feel clean, bold, and clearly designed.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'LEFT 70% OF THE WIDTH:',
        `A flat ${verde} panel.`,
        'RIGHT 30%:',
        'A flat cream panel.',
        `FROM ABOUT 31% TO 70% OF THE WIDTH, ${historia ? 'THE FULL HEIGHT OF THE SAFE ZONE' : 'FULL HEIGHT'}:`,
        `The enormous vertical word, in cream, inside the ${verde} panel, with the right edge of its letters touching the cream panel.`,
        'RIGHT SIDE, FROM ABOUT 30% TO 78% OF THE HEIGHT:',
        'The product, large, standing over the right part of the letters and the cream panel.',
        'UPPER LEFT:',
        'The small title.',
        'LOWER LEFT:',
        `${renglones.charAt(0).toUpperCase()}${renglones.slice(1)} small ${datos.length === 1 ? 'line' : 'lines'} with the restaurant's details.`,
        'The composition must feel clean, bold, and clearly designed.',
      ];

  // El título: su mensaje tal cual, y la IA de la imagen escoge la palabra fuerte; vacío, el de la muestra.
  const titulo = a.mensaje
    ? [
        `On the ${verde} panel, at about ${cartel ? '12% to 40%' : '15% to 25%'} of the height, left-aligned, place a small title on two or three lines (breaking only between words), reading exactly:`,
        `"${a.mensaje}"`,
        'Choose its one or two most important words and write them in a bold clean sans-serif; write every other word in an elegant classic serif. Do not change, add, or drop any word, and keep each word exactly as written, with its capitals and its accents.',
      ]
    : [
        `On the ${verde} panel, at about ${cartel ? '12% to 40%' : '15% to 25%'} of the height, left-aligned, place a small title on three lines, reading exactly:`,
        '"El',
        'Especial',
        'de hoy"',
        '"El" and "de hoy" in an elegant classic serif; "Especial" in a bold clean sans-serif.',
      ];

  const secciones = [
    'STYLE_22 — VERTICAL WORD',
    `Clean Graphic Food Advertising — Today's Special ${cartel ? 'Banner' : 'Poster'}`,
    `Create a professionally designed ${QUE_ES[a.formato]} for a Mexican restaurant, featuring one large product standing in front of an enormous vertical word in cream, on a background split into a ${verde} panel on the left and a cream panel on the right, with a small title at the upper left and the restaurant's details at the lower left.`,
    'THIS IS A CLEAN, BOLD GRAPHIC DESIGN: two flat color panels, one giant vertical word that melts into the cream panel, and one real photographed product with a crisp shadow.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. BACKGROUND PANELS',
    `The left panel is flat ${verde}, approximately ${t.panel}.`,
    `The right panel is flat warm cream, approximately ${CREMA}.`,
    `The boundary between them is one straight vertical line at about ${cartel ? '64%' : '70%'} of the width.`,
    'Both panels are perfectly flat: no gradient, no texture, no pattern.',
    '3. THE VERTICAL WORD',
    'Write one word, reading exactly:',
    `"${palabra}"`,
    `Rotate it 90 degrees counterclockwise, so it reads from the bottom of the ${pieza} up to the top.`,
    `Use an ultra-heavy, tall, condensed sans-serif, uppercase, so the word runs almost the full height of the ${alto}.`,
    `Text color: the same cream as the right panel, ${CREMA}.`,
    'The bottoms of the rotated letters (their baseline side, now facing right) touch the cream panel, so the letters seem to grow out of it.',
    'The letters are flat and solid: no outline, no shadow, no texture.',
    '4. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'Show it standing on the right side, seen from a slightly elevated front view, about 25 degrees above, so its top and its filling are clearly visible. If it is a drink, it stands in its own plain cup or glass, with no logo and no text.',
    `The product is about ${cartel ? '30% of the banner width' : '40% of the poster width'}, overlapping the right part of the vertical word and the cream panel.`,
    'NO branding.',
    'NO logos.',
    fotografia(5, [
      'The product must appear to have been photographed with a real camera under controlled studio lighting, then placed on the design.',
      'Use one large, soft but directional light from the upper-left and gentle neutral fill lighting.',
      ...luzCalida(color, 'the left panel'),
      'The product casts one crisp, soft-edged shadow toward the lower right, onto the cream panel.',
    ]),
    '6. TITLE — UPPER LEFT',
    ...titulo,
    'Below it, one short thin wavy line.',
    `Text and line color: cream ${CREMA}.`,
    '7. DETAILS — LOWER LEFT',
    `On the ${verde} panel, at about ${cartel ? '80% to 92%' : '92% to 97%'} of the height, left-aligned, place ${renglones} small ${datos.length === 1 ? 'line' : 'lines'}, each with a small bullet, reading exactly:`,
    ...datos.map((d) => `"${d}"`),
    'Use a clean, bold sans-serif, small.',
    `Text color: cream ${CREMA}.`,
    'Spell every word exactly as written, with its accents.',
    '8. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product.\n2. The vertical word "${palabra}".\n3. The small title.\n4. The restaurant's details.`,
    'Keep the design clean and uncluttered.',
    'Do not add extra graphic elements.',
    '9. STRICT EXCLUSIONS',
    'Do not include any food or drink other than the product described above.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, saucers, spoons, or napkins.',
    'Do not include any logo, brand, or text on the product, its cup, or its wrapper.',
    `Do not include websites, social media handles, prices, ${r.telefono ? '' : 'phone numbers, '}${r.direccion ? '' : 'addresses, '}or trademark symbols.`,
    `Do not add any text beyond the vertical word, the title, and the ${renglones} detail ${datos.length === 1 ? 'line' : 'lines'}.`,
    'Do not use distressed lettering, outlines, or 3D text.',
    'Do not make the product look like a 3D render.',
    '10. FINAL PRIORITY',
    `One large authentic product standing over an enormous vertical cream word "${palabra}" that grows out of the cream panel, on a background split into flat ${verde} on the left and flat cream on the right.`,
    `A small "${a.mensaje ?? 'El Especial de hoy'}" title at the upper left and ${renglones} small ${datos.length === 1 ? 'line' : 'lines'} with the restaurant's details at the lower left.`,
    'Clean, bold, calm, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'FLAT, CLEAN GRAPHIC DESIGN, CORRECTLY SPELLED.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
