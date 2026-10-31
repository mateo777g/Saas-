// Estilo 21 · Combo en mano (combo-en-mano.txt): tres manos de verdad entran desde las orillas con el combo
// de Don Chuy, encimadas sobre dos renglones de letra roja gigante, siempre «COMBO / &YA», sobre crema.
// Cada producto lleva su etiqueta con su nombre de Mi menú; su mensaje va en la insignia negra (vacío, no
// sale: nunca inventa un precio ni una promoción); abajo, «Buen provecho» en manuscrita y el nombre del
// restaurante. Es para combos: lleva 2 o 3 productos, y con 2 la tercera mano lleva una bebida del estilo,
// sin etiqueta. Su color pinta las letras gigantes; la insignia negra se queda.
import { AUTENTICO, comoEs, contactoDelCartel, fotografia, legibleSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, QUE_ES } from './comun';
import type { Anuncio, Estilo, Producto } from './comun';

// Los de la referencia, sacados con Pillow.
const TONOS = { letras: '#D80A10' };
const CREMA = '#FCF4EC';
const NEGRO = '#0A0D0A';
const LETRA = '#111111';

// La bebida del estilo que completa un combo de 2, sin etiqueta; si uno de sus productos ya es horchata, jamaica.
const HORCHATA = { nombre: 'agua de horchata', como: 'a creamy, milky white rice drink with a light dusting of ground cinnamon on top' };
const JAMAICA = { nombre: 'agua de jamaica', como: 'a deep ruby-red hibiscus drink' };

export const comboEnMano: Estilo = {
  clave: 'combo-en-mano',
  maximo: 3,
  minimo: 2,
  mensaje: 20,
  mayusculas: true,
  conColor: true,
  vacio: null,
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const [p1, p2, p3] = a.productos as [Producto, Producto, Producto | undefined];
  const color = a.color;
  const t = pintar(color, TONOS);
  const rojo = color ? nombreDelColor(color) : 'red';
  // La letra de la marca sobre el crema que se queda: se oscurece si hace falta para leerse.
  const letras = color ? legibleSobre(t.letras, CREMA) : t.letras;
  const insignia = a.mensaje ? mayus(a.mensaje) : null;
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  const bebida = a.productos.some((p) => /horchata/i.test(p.nombre)) ? JAMAICA : HORCHATA;
  // Lo que va en la mano de arriba a la izquierda: su producto 3 o, en un combo de 2, la bebida del estilo.
  const arriba = p3 ? 'product 3' : `the cup of ${bebida.nombre}`;

  const lugares = cartel
    ? {
        fila1: 'ROW 1 OF GIANT TYPE, FROM ABOUT 4% TO 40% OF THE HEIGHT: the word "COMBO", from the left edge to about 60% of the width.',
        fila2: 'ROW 2 OF GIANT TYPE, FROM ABOUT 44% TO 80% OF THE HEIGHT: "&YA", starting at the left edge and spanning about 42% of the width.',
        arriba: `${arriba === 'product 3' ? 'Product 3' : `The cup of ${bebida.nombre}`}: upper middle, at about 50% to 64% of the width, between about 6% and 50% of the height, held by a hand coming in from the top edge. It overlaps the last letters of "COMBO".`,
        dos: 'Product 2: right side, at about 80% to 98% of the width, between about 14% and 78% of the height, held by a hand coming in from the right edge, tilted diagonally with its top pointing up and to the left.',
        uno: 'Product 1: lower middle, the largest of the three, at about 50% to 78% of the width, between about 40% and 100% of the height, held by a hand rising from the bottom edge.',
        insignia: 'THE BADGE: a round black badge at the upper right, at about 66% to 80% of the width, between about 6% and 30% of the height.',
        frase: 'THE HANDWRITTEN PHRASE: lower right, at about 80% to 97% of the width, between about 82% and 96% of the height.',
        marca: `THE BRAND: a small line at the bottom left, at about 88% of the height${contacto ? ', with the phone and the address below it, smaller, at about 94%' : ''}.`,
      }
    : {
        fila1: 'ROW 1 OF GIANT TYPE, FROM ABOUT 2% TO 31% OF THE HEIGHT: the word "COMBO", spanning almost the full width of the poster, from edge to edge.',
        fila2: 'ROW 2 OF GIANT TYPE, FROM ABOUT 40% TO 69% OF THE HEIGHT: "&YA", starting at the left edge and spanning about 75% of the width.',
        arriba: `${arriba === 'product 3' ? 'Product 3' : `The cup of ${bebida.nombre}`}: upper left, between about 12% and 44% of the height, held by a hand coming in from the left edge. It overlaps the first letters of "COMBO".`,
        dos: 'Product 2: right side, between about 28% and 66% of the height, held by a hand coming in from the right edge, tilted diagonally with its top pointing up and to the left. It overlaps the last letters of "COMBO" and the right end of "&YA".',
        uno: 'Product 1: lower left, the largest of the three, between about 60% and 96% of the height, held by a hand rising from the bottom-left corner. It overlaps the bottom of "&YA".',
        insignia: 'THE BADGE: a round black badge between the upper-left and the right products, at about 36% to 50% of the height, slightly left of center.',
        frase: 'THE HANDWRITTEN PHRASE: lower right, between about 78% and 92% of the height.',
        marca: 'THE BRAND: a small line at the bottom-left corner, at about 96% of the height.',
      };
  const tamano = cartel ? { uno: 26, dos: 20, arriba: 14, insignia: 12 } : { uno: 50, dos: 40, arriba: 28, insignia: 22 };

  const tercero = p3
    ? [
        `6. PRODUCT 3 — ${cartel ? 'UPPER MIDDLE' : 'UPPER LEFT'}`,
        `ONE genuine product: ${comoEs(p3)}`,
        `It is about ${tamano.arriba}% of the ${pieza} width.`,
      ]
    : [
        `6. THE CUP OF ${bebida.nombre.toUpperCase()} — ${cartel ? 'UPPER MIDDLE' : 'UPPER LEFT'}`,
        `One clear, unbranded plastic cup of ${bebida.nombre}: ${bebida.como}, a few clear ice cubes, and light natural condensation on the cup.`,
        'No lid, no straw, no label, no print on the cup.',
        'It only completes the combo: it has no label and it is never named in any text.',
        `The cup is about ${tamano.arriba}% of the ${pieza} width.`,
      ];

  const cadaEtiqueta = [
    `* Next to product 1, on its left, on one to three lines (breaking only between words): "${mayus(p1.nombre)}".`,
    `* Next to product 2, above it, on one or two lines: "${mayus(p2.nombre)}".`,
    ...(p3 ? [`* Next to product 3, below it and to the right, on one or two lines: "${mayus(p3.nombre)}".`] : []),
  ];

  const secciones = [
    'STYLE_24 — COMBO IN HAND',
    'Bold Fast-Food Advertising — Three Hands, One Combo',
    `Create a professionally designed ${QUE_ES[a.formato]} featuring a Mexican restaurant combo: ${p3 ? 'three products' : `two products and one cup of ${bebida.nombre}`}, each held by a real human hand reaching in from the edges of the ${pieza}, layered over two rows of giant ${rojo} typography on a warm cream background.`,
    `THIS IS A BOLD GRAPHIC ${cartel ? 'BANNER' : 'POSTER'}: giant ${cartel ? 'typography on the left' : 'edge-to-edge typography'} behind three real photographed hands holding ${p3 ? 'three real products' : 'the combo'}, with small callout labels${insignia ? ', one round badge,' : ''} and one handwritten phrase.`,
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    lienzo(a.formato),
    lugares.fila1,
    lugares.fila2,
    'WHAT THE THREE HANDS HOLD:',
    `* ${lugares.arriba}`,
    `* ${lugares.dos}`,
    `* ${lugares.uno}`,
    ...(insignia ? [lugares.insignia] : []),
    lugares.frase,
    lugares.marca,
    '2. BACKGROUND',
    `Use a flat warm cream background, approximately ${CREMA}.`,
    'A very subtle fine film grain covers the whole image, like a printed poster.',
    'No patterns.',
    'No textures.',
    'No gradients.',
    '3. THE GIANT TYPOGRAPHY',
    'Two rows, reading exactly:',
    '"COMBO"',
    '"&YA"',
    'Use an ultra-bold, tightly condensed, tall grotesque sans-serif, all uppercase, with very tight letter spacing, so the letters almost touch.',
    'Both rows share the same letter height and the same font.',
    `Color: bold ${rojo} ${letras}, flat and solid.`,
    'The giant letters sit BEHIND all three hands and what they hold: the hands and the products overlap them and hide parts of some letters, but every letter remains recognizable.',
    'No outlines, no shadows, no other words in this size.',
    `4. PRODUCT 1 — THE LARGEST, ${cartel ? 'LOWER MIDDLE' : 'LOWER LEFT'}`,
    `ONE genuine product: ${comoEs(p1)}`,
    'It is held upright and slightly tilted toward the viewer, so its top and its filling are clearly visible.',
    'If it is food, its lower half is wrapped in a sheet of slightly crumpled white wax paper, with soft natural folds.',
    `It is about ${tamano.uno}% of the ${pieza} width.`,
    '5. PRODUCT 2 — RIGHT SIDE',
    `ONE genuine product: ${comoEs(p2)}`,
    'If it is food, its lower two-thirds sit in a plain white paper sleeve with soft folds, completely blank: no logo, no stripes, no print.',
    `It is about ${tamano.dos}% of the ${pieza} width.`,
    ...tercero,
    'A product that is a drink is in its own clear or plain cup or glass, with no lid, no straw, no label, and no print, held from the side.',
    ...AUTENTICO,
    p3
      ? 'Show only these products, each one once. Do not add any other food or drink, and do not repeat a product to fill space.'
      : `Show only these products, each one once. Besides the cup of ${bebida.nombre} of the set, do not add any other food or drink, and do not repeat a product to fill space.`,
    '7. THE THREE HANDS',
    'Three real human hands, each holding one thing:',
    `* The ${cartel ? 'top' : 'left'} hand comes in from the ${cartel ? 'top' : 'left'} edge and holds ${arriba} from the side, with the fingers wrapped around it.`,
    '* The right hand comes in from the right edge and holds product 2, by its paper sleeve if it has one.',
    `* The bottom hand rises from the bottom${cartel ? ' edge' : '-left corner'} and holds product 1 from below, around the wax paper if it has it.`,
    'Natural skin with realistic texture and soft creases, short clean nails, no rings, no bracelets, no sleeves visible.',
    'Only the hands and part of the wrists are visible.',
    'Each hand must look like a real photographed hand: correct anatomy, five fingers, natural proportions, never plastic or 3D-rendered.',
    fotografia(8, [
      `The products and the three hands must appear to have been photographed with a real camera under the same controlled studio lighting, then placed on the ${pieza}.`,
      'Use one large, soft but directional light from the upper-left, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
      ...luzCalida(color, 'the giant letters'),
      `Each product casts a soft, natural shadow onto the ${rojo} letters behind it.`,
    ]),
    '9. CALLOUT LABELS',
    `Each of ${p3 ? 'the three products' : 'the two products'} has one small label with its name, connected to the product by a thin, straight black line that ends in a small black dot on the product:`,
    ...cadaEtiqueta,
    ...(p3 ? [] : [`The cup of ${bebida.nombre} has no label.`]),
    `Use a bold, condensed, uppercase sans-serif, small, in near-black ${LETRA}.`,
    `The labels sit on the cream background, never on top of the ${rojo} letters or the food.`,
    ...(insignia
      ? [
          '10. BADGE',
          `A perfect black circle, approximately ${NEGRO}, about ${tamano.insignia}% of the ${pieza} width.`,
          'Inside, in white bold condensed uppercase, on one to three lines (breaking only between words), reading exactly:',
          `"${insignia}"`,
          'If it has a number or a price, make that part much larger than the other words. Do not change, add, or drop any word.',
        ]
      : []),
    `${insignia ? '11' : '10'}. HANDWRITTEN PHRASE`,
    `In the lower right, a short phrase in a flowing black brush-pen script, on two staggered lines, reading exactly:`,
    '"Buen"',
    '"provecho"',
    'With one loose hand-drawn underline swash below the last word.',
    'It looks like real handwriting, natural and confident, not a decorative font.',
    `${insignia ? '12' : '11'}. BRAND`,
    `${cartel ? 'At the bottom left' : 'At the bottom-left corner'}, one small line in the same bold condensed uppercase as the labels, in near-black ${LETRA}, reading exactly:`,
    `"${marca}"`,
    ...(contacto ? [`Below it, one smaller line in the same font and color, reading exactly: ${contacto}`] : []),
    `${insignia ? '13' : '12'}. GRAPHIC HIERARCHY`,
    'Maintain this visual order:',
    [
      `1. The ${p3 ? 'three products' : 'combo'} held in the hands, product 1 first.`,
      `2. The giant ${rojo} "COMBO &YA".`,
      ...(insignia ? ['3. The black badge.'] : []),
      `${insignia ? '4' : '3'}. The handwritten phrase.`,
      `${insignia ? '5' : '4'}. The callout labels and the brand${contacto ? ', then the phone and the address' : ''}.`,
    ].join('\n'),
    'Keep the layout bold, clean, and balanced, with the cream background visible around the products.',
    'Spell every word exactly as written, with its accents.',
    `${insignia ? '14' : '13'}. STRICT EXCLUSIONS`,
    `Do not include any food or drink other than the ${p3 ? 'products' : `products and the cup of ${bebida.nombre}`} described above.`,
    'Do not include plates, boards, trays, cutlery, napkins, straws, or lids.',
    'Do not show more than three hands, sleeves, jewelry, or a face.',
    `Do not include logos, mascots, animal icons, stripes on the packaging, trademark symbols, ${contacto ? '' : 'phone numbers, '}websites, or social media handles.`,
    insignia ? 'Do not include menu prices or promotions outside the badge.' : 'Do not include badges, prices, or promotions.',
    `Do not write "FROM", legal text, or any text beyond the giant words, the ${p3 ? 'three' : 'two'} labels${insignia ? ', the badge' : ''}, the handwritten phrase, and the brand${contacto ? ', the phone and the address' : ''}.`,
    'Do not use distressed lettering, drop shadows on the text, or 3D text.',
    'Do not make the food or the hands look like a 3D render.',
    `${insignia ? '15' : '14'}. FINAL PRIORITY`,
    `Three real hands reaching in from the edges, holding ${p3 ? 'three authentic products' : `two authentic products and one clear cup of ${bebida.nombre}`}, layered over the giant ${rojo} condensed words "COMBO" and "&YA" on a warm cream background.`,
    `Small black callout labels with thin lines${insignia ? `, a round black badge "${insignia}"` : ''}, the black script "Buen provecho", and "${marca}" small at the bottom left.`,
    'Bold, appetizing, premium fast-food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'REAL HANDS, CORRECT ANATOMY.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
