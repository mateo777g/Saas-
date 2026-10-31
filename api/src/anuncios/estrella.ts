// Estilo 12 · Estrella (estrella.txt): el producto de Don Chuy sobre una estrella grande de puntas
// redondas, en un fondo durazno. Dentro de la estrella, el nombre del producto chiquito y su mensaje en
// grande (vacío, «DEL MERO BUENO.»); arriba, el nombre del restaurante; abajo, las pastillas del teléfono,
// la dirección y «ORDENA AHORA» (un dato vacío no se manda). Su color pinta la estrella, la marca y las
// pastillas; el durazno se queda.
import { AUTENTICO, comoEs, legibleSobre, letraSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const TONOS = { rojo: '#B70608' };
const DURAZNO = '#FDD8A9';

export const estrella: Estilo = {
  clave: 'estrella',
  maximo: 1,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: true,
  vacio: 'DEL MERO BUENO.',
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
  const estrellaTono = pintar(color, TONOS).rojo;
  const rojo = color ? nombreDelColor(color) : 'red';
  // La marca va en el color sobre el durazno: si salió claro, se oscurece hasta leerse.
  const marcaTono = color ? legibleSobre(estrellaTono, DURAZNO) : estrellaTono;
  const enEstrella = letraSobre(estrellaTono);
  const grandes = a.mensaje ? `"${mayus(a.mensaje)}"` : '"DEL MERO\nBUENO."';
  const grandesCorrido = a.mensaje ? mayus(a.mensaje) : 'DEL MERO BUENO.';
  const nombre = mayus(p.nombre);
  const marca = mayus(a.restaurante.nombre);
  const r = a.restaurante;

  const pastillas = [
    ...(r.telefono ? [`deep ${rojo} ${estrellaTono}, with a small simple ${enEstrella} phone-handset icon and the ${enEstrella} text "${r.telefono}"`] : []),
    ...(r.direccion ? [`deep ${rojo} ${estrellaTono}, with a small simple ${enEstrella} map-pin icon and the ${enEstrella} text "${r.direccion}"`] : []),
    `white #FFFFFF, with the deep ${rojo} text "ORDENA AHORA"`,
  ];
  const lados = pastillas.length === 3 ? ['LEFT PILL', 'CENTER PILL', 'RIGHT PILL'] : pastillas.length === 2 ? ['LEFT PILL', 'RIGHT PILL'] : ['PILL'];
  const cuantas = ['', 'one small rounded pill', 'two small rounded pills', 'three small rounded pills'][pastillas.length];

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'TOP LEFT, AT ABOUT 10% OF THE HEIGHT:',
        'The brand name.',
        'CENTER AND RIGHT, FROM ABOUT 6% TO 94% OF THE HEIGHT:',
        `The large ${rojo} starburst badge, with the headline in its left part and the product in its right part.`,
        'BOTTOM LEFT, AT ABOUT 92% OF THE HEIGHT:',
        `One row of ${cuantas.replace('small rounded ', 'information ')}.`,
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP, AT ABOUT 8% OF THE HEIGHT:',
        'The brand name, centered.',
        'CENTER, FROM ABOUT 15% TO 85% OF THE HEIGHT:',
        `The large ${rojo} starburst badge, with the headline in its upper part and the product in its lower part.`,
        'BOTTOM, AT ABOUT 91% OF THE HEIGHT:',
        `One row of ${cuantas.replace('small rounded ', 'information ')}.`,
      ];

  const secciones = [
    `STYLE_15 — ${rojo.toUpperCase()} STARBURST`,
    'Bold Graphic Fast-Food Advertising — Product Badge Campaign',
    `Create a professionally designed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring one product, "${p.nombre}", in front of a large deep-${rojo} starburst badge with rounded points, on a soft peach background, with a bold ${enEstrella} headline inside the badge, the brand name at the top, and a row of information pills at the bottom.`,
    'THIS IS A BOLD, CLEAN GRAPHIC DESIGN: flat colors, one big badge shape, and one real photographed product placed on the design.',
    'Prioritize authentic food photography and physically believable food over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    'The composition must feel bold, centered, balanced, and clearly designed.',
    '2. BACKGROUND',
    `Use one flat, solid, soft peach background, approximately ${DURAZNO}, covering the whole canvas.`,
    'No gradient.',
    'No texture.',
    'No pattern.',
    'No shadows on the background.',
    '3. THE STARBURST BADGE',
    `${cartel ? 'In the center and right part' : 'In the center'}, place one large flat starburst shape in deep ${rojo}, approximately ${estrellaTono}.`,
    'It has 8 broad points with softly rounded tips and smooth curved inner corners, like a playful sticker badge, not a sharp star.',
    cartel
      ? 'It spans about 88% of the banner height and about 60% of its width, from about 30% to 90% of the width.'
      : 'It spans about 85% of the poster width and sits from about 15% to 85% of the poster height.',
    'The shape is perfectly flat and solid: no outline, no gradient, no texture, no 3D effect, no drop shadow.',
    ...luzCalida(color, 'the badge, the brand name, and the pills'),
    '4. HEADLINE — INSIDE THE BADGE',
    `In the ${cartel ? 'left' : 'upper'} part of the badge, place the headline: first one small line, reading exactly:`,
    `"${nombre}"`,
    'and below it, larger, bold, and tightly stacked, in one, two, or three lines, reading exactly:',
    grandes,
    'Use a heavy, clean, slightly condensed geometric sans-serif, uppercase.',
    `Text color: ${enEstrella}${enEstrella === 'white' ? ' #FFFFFF' : ''}.`,
    'Tight but controlled letter spacing and line spacing, left-aligned as one compact block.',
    'No outlines.',
    'No drop shadows.',
    'No 3D effects.',
    'The headline never touches the product.',
    '5. HERO PRODUCT',
    `Feature ONE genuine product: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'Show the product from a slightly elevated three-quarter front view, about 25 degrees above, so its top and filling are clearly visible.',
    cartel
      ? 'The product is large: about 30% of the banner width, in the right part of the badge, between roughly 25% and 85% of the banner height, with its right edge slightly overlapping the edge of the badge onto the peach background.'
      : 'The product is large: about 60% of the poster width, centered in the lower part of the badge, between roughly 48% and 80% of the poster height, with its lower edge slightly overlapping the bottom edge of the badge onto the peach background.',
    'The whole product is visible: the badge never cuts or hides any part of it.',
    '6. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    'The product must appear to have been photographed with a real camera under controlled studio lighting, then cleanly placed on the design.',
    'Use one large, soft but directional light from the upper-left, which gives the food gentle highlights and natural depth, plus gentle neutral fill lighting.',
    'Preserve natural shadows and realistic textures inside the product.',
    'Add only a soft, subtle contact shadow under the product on the badge.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '7. BRAND',
    `${cartel ? 'At the top left of the banner' : 'At the top of the poster, centered, above the badge'}, place the brand name on one line:\n"${marca}"`,
    'Use the same heavy geometric sans-serif, uppercase, medium-small size.',
    `Text color: deep ${rojo} ${marcaTono}.`,
    'Do not invent logos or symbols.',
    '8. INFORMATION PILLS',
    `At the bottom of the ${pieza}, place one horizontal row of ${cuantas}, evenly spaced, ${cartel ? 'starting at the left' : 'centered'}:`,
    ...pastillas.map((pastilla, i) => `${lados[i]}: ${pastilla}.`),
    'Use a clean, small, bold sans-serif. Write each text exactly as given, with its accents.',
    'The pills are small and tidy, like a footer, never competing with the badge.',
    'No social media icons or logos.',
    '9. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. The product.\n2. The ${rojo} starburst badge.\n3. The headline.\n4. The brand name.\n5. The information pills.`,
    'Keep the design clean and uncluttered.',
    'Do not add extra graphic elements.',
    '10. STRICT EXCLUSIONS',
    'Do not include any other food or drink.',
    'Do not create several copies of the product, or split it into halves.',
    'Do not include plates, boards, cutlery, or napkins.',
    'Do not add extra shapes, splashes, sparkles, flames, ribbons, or confetti.',
    'Do not include social media logos, QR codes, prices, or trademark symbols.',
    `Do not add any text beyond the brand name, the headline, and the ${pastillas.length === 1 ? 'pill' : 'pills'}.`,
    'Do not use script fonts, distressed lettering, outlines, or 3D text.',
    'Do not make the food look like a 3D render.',
    '11. FINAL PRIORITY',
    `One authentic product, large, over the ${cartel ? 'right' : 'lower'} part of a big flat deep-${rojo} starburst badge with rounded points, on a flat soft-peach background.`,
    `A bold ${enEstrella} headline inside the badge: "${nombre}" and "${grandesCorrido}", the deep-${rojo} brand name at the top, and a tidy row of information pills at the bottom.`,
    'Bold, clean, friendly, premium fast-food graphic advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'FLAT, CLEAN GRAPHIC SHAPES.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
