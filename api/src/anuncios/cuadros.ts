// Estilo 24 · Cuadros (cuadros.txt): arriba el nombre del restaurante en manuscrita, tal cual; una palabra
// gigante del nombre del producto (la escoge el paso de texto: «PASTOR»); el producto de Don Chuy grande,
// flotando sobre una franja de cuadros azules y crema; abajo, un recuadro con su mensaje (vacío, el horario
// de «Tu restaurante»; sin horario, no sale) y hasta abajo el teléfono (sin teléfono, no sale). Su color
// pinta la palabra gigante, los cuadros y el recuadro; el crema se queda.
import { AUTENTICO, comoEs, fotografia, legibleSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

// Los de la referencia, sacados con Pillow.
const TONOS = { azul: '#0147B6' };
const CREMA = '#F6F1DC';
const NEGRO = '#1A1A1A';

export const cuadros: Estilo = {
  clave: 'cuadros',
  maximo: 1,
  minimo: 1,
  mensaje: 40,
  mayusculas: true,
  conColor: true,
  vacio: '#horario',
  datos: {
    post: ['nombre', 'telefono', 'horario'],
    historia: ['nombre', 'telefono', 'horario'],
    cartel: ['nombre', 'telefono', 'direccion', 'horario'],
  },
  lugares: [
    {
      clave: 'gigante',
      nombre: 'La palabra gigante',
      tope: 10,
      mayusculas: true,
      cuando: 'siempre',
      pide: 'Una sola palabra del nombre del producto, la que más lo dice, en mayúsculas («Taco al pastor» → «PASTOR», «Agua de horchata» → «HORCHATA», «Gringa» → «GRINGA»).',
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
  const t = pintar(color, TONOS);
  // Un solo tono para la palabra, los cuadros y el recuadro, como el azul de la muestra; si la marca es
  // tan clara que no se lee sobre el crema, se oscurece.
  const azul = color ? legibleSobre(t.azul, CREMA) : t.azul;
  const nombreAzul = color ? nombreDelColor(color) : 'blue';
  const palabra = a.palabras.gigante;
  const marca = a.restaurante.nombre;
  const telefono = a.restaurante.telefono;
  const direccion = cartel ? a.restaurante.direccion : null;
  // El recuadro: su mensaje o, vacío, el horario en sus uno o dos renglones; sin los dos, no sale.
  const recuadro = a.mensaje ? [mayus(a.mensaje)] : a.restaurante.horario?.map(mayus) ?? null;
  const loDelRecuadro = a.mensaje ? 'the message' : 'the hours';
  const abajo = [telefono, direccion].filter((d): d is string => !!d);

  const composicion = cartel
    ? [
        lienzo('cartel'),
        'LEFT, FROM ABOUT 5% TO 48% OF THE WIDTH, everything centered on that half:',
        'AT ABOUT 8% TO 16% OF THE HEIGHT: the restaurant name, handwritten.',
        'AT ABOUT 20% TO 46% OF THE HEIGHT: the giant word, spanning about 40% of the banner width.',
        ...(recuadro ? [`AT ABOUT 54% TO 68% OF THE HEIGHT: the outlined box with ${loDelRecuadro}, about 36% of the banner width.`] : []),
        ...(abajo.length ? [`AT ABOUT 88% TO 94% OF THE HEIGHT: the ${direccion ? (telefono ? 'phone number and the address' : 'address') : 'phone number'}, small.`] : []),
        'RIGHT, FROM ABOUT 50% OF THE WIDTH TO THE RIGHT EDGE, FROM ABOUT 28% TO 72% OF THE HEIGHT: the checkerboard band, reaching the right edge.',
        'THE PRODUCT floats over the band, centered at about 74% of the width, between about 10% and 90% of the height.',
      ]
    : [
        lienzo(a.formato),
        'AT ABOUT 6% TO 12% OF THE HEIGHT: the restaurant name, handwritten, centered.',
        'AT ABOUT 20% TO 36% OF THE HEIGHT: the giant word, centered, spanning about 85% of the width.',
        'FROM ABOUT 36% TO 71% OF THE HEIGHT: the checkerboard band, from the left edge to the right edge.',
        'THE PRODUCT floats over the band, centered, between about 30% and 75% of the height, so its top overlaps the bottom of the giant word slightly.',
        ...(recuadro ? [`AT ABOUT 78% TO 87% OF THE HEIGHT: the outlined box with ${loDelRecuadro}, centered, about 60% of the width.`] : []),
        ...(telefono ? ['AT ABOUT 93% OF THE HEIGHT: the phone number, small, centered.'] : []),
      ];

  // Las secciones de abajo se numeran según lo que haya.
  let n = 8;
  const caja = recuadro
    ? [
        `${n++}. ${a.mensaje ? 'MESSAGE BOX' : 'HOURS BOX'}`,
        `A rectangle with a thin solid ${nombreAzul} outline, approximately ${azul}, and no fill${cartel ? '' : ', centered'}.`,
        `Inside, in the same bold condensed sans-serif as the giant word, in ${nombreAzul}, ${recuadro.length === 2 ? 'on two lines' : a.mensaje ? 'on one or two lines (breaking only between words)' : 'on one line'}, reading exactly:`,
        ...recuadro.map((r) => `"${r}"`),
      ]
    : [];
  const datos = abajo.length
    ? [
        `${n++}. ${direccion ? (telefono ? 'PHONE AND ADDRESS' : 'ADDRESS') : 'PHONE'}`,
        `At the bottom, ${cartel ? 'centered on the left half' : 'centered'}, small, in a clean regular sans-serif, in near-black ${NEGRO}, reading exactly: ${abajo.map((d) => `"${d}"`).join(' and ')}`,
      ]
    : [];
  const orden = [
    'The product.',
    `The giant ${nombreAzul} word "${palabra}".`,
    'The checkerboard band.',
    ...(recuadro ? [`The ${a.mensaje ? 'message' : 'hours'} box.`] : []),
    `The restaurant name${abajo.length ? (direccion ? ', the phone and the address' : ' and the phone') : ''}.`,
  ].map((x, i) => `${i + 1}. ${x}`);
  const textos = [
    'the restaurant name',
    'the giant word',
    ...(recuadro ? [a.mensaje ? 'the message' : 'the hours'] : []),
    ...(telefono ? ['the phone number'] : []),
    ...(direccion ? ['the address'] : []),
  ];

  const secciones = [
    `STYLE_27 — ${nombreAzul.toUpperCase()} CHECKERBOARD`,
    'Clean Graphic Food Advertising — One Product Over a Checkerboard Band',
    `Create a professionally designed ${QUE_ES[a.formato]}: one authentic Mexican product, large and cleanly photographed, floating in front of a wide band of ${nombreAzul} and cream checkerboard squares on a flat cream background, ${cartel ? 'beside' : 'under'} one giant ${nombreAzul} word, with the restaurant name handwritten ${cartel ? 'above the word' : 'at the top'}${recuadro ? ` and a ${nombreAzul} outlined box with ${loDelRecuadro} below` : ''}.`,
    `THIS IS A CLEAN, SIMPLE GRAPHIC ${cartel ? 'BANNER' : 'POSTER'}: flat colors, one giant word, one checkerboard band, and one real photographed product.`,
    'Prioritize authentic food photography and physically believable ingredients over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...composicion,
    '2. BACKGROUND',
    `Use a flat, warm cream background, approximately ${CREMA}.`,
    'No gradients.',
    'No textures.',
    'No patterns outside the checkerboard band.',
    '3. THE CHECKERBOARD BAND',
    `A wide horizontal band of alternating squares, like a classic checkerboard: solid ${nombreAzul} squares, approximately ${azul}, alternating with squares of the same cream as the background.`,
    `Each square is about ${cartel ? '5% of the banner width' : '9% of the poster width'}; the band is about five squares tall.`,
    `The band runs ${cartel ? 'from about the middle of the banner to the right edge' : 'from the left edge to the right edge'}, with crisp, flat, perfectly straight edges, and the product covers most of its center.`,
    '4. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'The product floats slightly tilted, its top turned toward the viewer, so its top and its filling are clearly visible. If it is a drink, it floats upright in its own plain cup or glass, with no logo and no text.',
    `It is large: about ${cartel ? '42% of the banner width' : '75% of the poster width'}.`,
    'It casts a very soft, subtle shadow onto the checkerboard band behind it.',
    fotografia(5, [
      `The product must appear to have been photographed with a real camera under controlled studio lighting, then cleanly placed on the ${pieza}.`,
      'Use one large, soft but directional light from the upper-left, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
      ...luzCalida(color, 'the giant word, the checkerboard, and the box'),
    ]),
    '6. RESTAURANT NAME',
    `${cartel ? 'At the top of the left half, centered on it' : 'At the top, centered'}, reading exactly:`,
    `"${marca}"`,
    'In a casual, friendly handwritten marker script, black, medium size, like a quick signature.',
    '7. GIANT WORD',
    'Under the restaurant name, one word reading exactly:',
    `"${palabra}"`,
    'Use an ultra-bold, condensed, tall grotesque sans-serif, all uppercase, tight letter spacing.',
    `Color: solid ${nombreAzul} ${azul}, flat.`,
    ...caja,
    ...datos,
    `${n++}. GRAPHIC HIERARCHY`,
    'Maintain this visual order:',
    orden.join('\n'),
    'Keep the layout simple, clean, and balanced, with generous cream space around the texts.',
    'Spell every word exactly as written, with its accents.',
    `${n++}. STRICT EXCLUSIONS`,
    'Do not include any food or drink other than the product described above.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, boards, cutlery, napkins, hands, or people.',
    `Do not include logos, watermarks, trademark symbols, prices, ${telefono ? '' : 'phone numbers, '}websites, or social media handles.`,
    `Do not add any text beyond ${textos.length > 2 ? `${textos.slice(0, -1).join(', ')}, and ${textos[textos.length - 1]}` : textos.join(' and ')}.`,
    'Do not use distressed lettering, drop shadows on the text, or 3D text.',
    'Do not make the food look like a 3D render.',
    `${n++}. FINAL PRIORITY`,
    `One authentic product, large and floating over a wide ${nombreAzul} and cream checkerboard band on a flat cream background.`,
    `The handwritten "${marca}" ${cartel ? 'on the left' : 'at the top'}, the giant ${nombreAzul} word "${palabra}"${recuadro ? `, a ${nombreAzul} outlined box "${recuadro.join(' / ')}"` : ''}${abajo.length ? `, and ${abajo.map((d) => `"${d}"`).join(' and ')} small at the bottom` : ''}.`,
    'Clean, simple, appetizing, premium food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
