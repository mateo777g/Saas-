// Estilo 6 · Fútbol (futbol.txt, el prompt del desarrollador): los productos de Don Chuy sobre una cancha
// verde, con un balón que solo rellena. De temporada (siempre) y sin color. Desde el 22 nov 2026 (el
// developer: «que lleve solamente los productos… vistos desde arriba, en un grado de 60»): sin el refresco,
// las dos salsas, el limón y el cilantro que traía de su referencia de taquería, y toda la escena a unos 60°
// en vez del cenital (la hamburguesa salía de lado, con el ángulo de su foto). Con un producto lo dibuja dos veces, como sus dos tacos, y su titular va en
// plural (el paso de texto); con varios, el nombre del producto 1 tal cual. Debajo, su mensaje o «EL
// SABOR DEL PARTIDO», y «ORDENA AHORA». Las dos referencias (la cancha y la letra de Promo) se quitan:
// lo que daban ya lo describe el prompt.
import { AUTENTICO, comoEs, contactoDelCartel, CUANTOS, lienzo, mayus } from './comun';
import type { Anuncio, Estilo } from './comun';

const VERDE = '#126847';
const VERDE_OSCURO = '#0B543A';
const MARFIL = '#F5F0E9';

export const futbol: Estilo = {
  clave: 'futbol',
  maximo: 5,
  minimo: 1,
  mensaje: 30,
  mayusculas: true,
  conColor: false,
  vacio: 'EL SABOR DEL PARTIDO',
  datos: { post: ['ordena'], historia: ['ordena'], cartel: ['ordena', 'telefono', 'direccion'] },
  lugares: [
    {
      clave: 'titular',
      nombre: 'El titular',
      tope: 30,
      mayusculas: true,
      cuando: 'con_uno',
      pide: 'El nombre del producto en plural, como se dice cuando salen dos en la foto («Taco al pastor» → «TACOS AL PASTOR», «Agua de horchata» → «AGUAS DE HORCHATA»).',
    },
  ],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const n = a.productos.length;
  const uno = n === 1;
  const titular = uno ? a.palabras.titular : mayus(a.productos[0].nombre);
  const frase = a.mensaje ? mayus(a.mensaje) : 'EL SABOR DEL PARTIDO';
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  const comida = uno ? 'the product, served twice' : `${CUANTOS[n]} products`;

  const cadaProducto = a.productos.map((p, i) => `* Product ${i + 1}: ${comoEs(p)}`);
  const acomodo = uno
    ? [
        'Arrange TWO small, naturally prepared servings of the product together as a restrained hero grouping, like a pair of tacos.',
        cartel
          ? 'Position them in the lower-center area of the banner.'
          : 'Position them diagonally in the lower-center and lower-left area of the composition.',
      ]
    : [
        `Arrange the ${CUANTOS[n]} products together as a restrained hero grouping, ${cartel ? 'in one row along the lower part of the banner' : 'in the lower half of the poster, diagonally from the lower-left toward the center'}, with product 1 slightly in front, the focus of the image.`,
        ...(n >= 4 ? [`Because there are ${CUANTOS[n]} products, draw each one smaller, so they all fit comfortably without crowding.`] : []),
      ];

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into two visually connected zones:',
        'TOP 35%:',
        'Large, beautiful advertising typography against an uninterrupted section of the green pitch.',
        'BOTTOM 65%:',
        'High-angle food photography arranged directly on the football-field-inspired surface, in a row along the banner.',
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into two visually connected zones:',
        'TOP 38%:',
        'Large, beautiful advertising typography against an uninterrupted section of the green pitch.',
        'BOTTOM 62%:',
        'High-angle food photography arranged directly on the football-field-inspired surface.',
      ];

  const secciones = [
    'STYLE_08 V4 — FOOTBALL PITCH, HIGH ANGLE',
    'Premium Mexican Food Advertising — Modern Football Pitch Campaign',
    `Create a professionally art-directed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring ${comida} arranged on a stylized green football pitch.`,
    `IMPORTANT: Use a high-angle football-field composition, designed specifically for a ${cartel ? 'HORIZONTAL advertising banner' : 'VERTICAL advertising poster'}.`,
    'THIS IS A HIGH-ANGLE TABLETOP ADVERTISING COMPOSITION.',
    'It must NOT look like a restaurant table placed inside a stadium.',
    'It must NOT look like food standing on real grass.',
    'The football pitch is the actual designed surface on which the products are arranged.',
    'Think premium food photography combined with a minimal, contemporary football-themed editorial graphic layout.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    `The entire ${pieza} must share ONE continuous green background.`,
    'Do not create a hard horizontal split between text and product sections.',
    'The composition should feel spacious, carefully balanced, and genuinely designed.',
    cartel
      ? 'The layout must be optimized specifically for a horizontal menu banner, not stretched or cropped from a vertical poster.'
      : 'The layout must be optimized specifically for vertical social media, not stretched or cropped from a horizontal banner.',
    '2. BACKGROUND — MODERN GREEN FOOTBALL PITCH',
    'Use a beautifully designed, rich emerald-green football pitch surface.',
    `Primary green: ${VERDE}.`,
    `Secondary green: ${VERDE_OSCURO}.`,
    'The surface should resemble a premium matte green football-themed tabletop or advertising set.',
    'Use extremely subtle surface texture.',
    'Avoid visible long grass blades, fuzzy artificial turf, realistic mud, and stadium scenery.',
    'The background should look clean, sophisticated, and flat.',
    'Add thin, precise white football pitch markings, seen from the same high angle as the rest of the scene.',
    'Include portions of:',
    '* The center circle.',
    '* The midfield line.',
    '* A penalty-box outline.',
    '* Small portions of the side markings.',
    'The markings must follow believable football pitch geometry.',
    'The field lines should continue naturally behind the food objects.',
    'Do not draw multiple overlapping football pitches.',
    'Do not place markings randomly.',
    'Use the football-field markings as a beautiful integrated graphic structure.',
    'The appearance should be similar to professional food advertising photographed on a stylized football pitch.',
    "3. CAMERA ANGLE — ABSOLUTELY ESSENTIAL",
    'Photograph the whole scene from a steep high angle, about 60 degrees above the surface, like someone standing and looking down at a table: the whole top of every product is visible, and only a little of its side.',
    "Use each product's reference image only to know what it looks like; photograph it again from this angle, never from the angle of its reference photo.",
    'The pitch markings, the football and every product share this same angle.',
    'No low-angle camera.',
    'No eye-level photography.',
    'No front view of the products.',
    'No visible horizon.',
    'No background stadium.',
    'No wooden table.',
    'No visible edge of the surface.',
    'The image must look like one carefully photographed advertising scene.',
    '4. MAIN PRODUCTS',
    ...cadaProducto,
    ...acomodo,
    'They should look like genuine Mexican restaurant food, not oversized American portions.',
    ...AUTENTICO.slice(0, 3),
    'If a product is a taco, unless its reference image shows it otherwise: one thin, flexible tortilla, soft, slightly imperfect, and naturally folded, seen from this high angle; never a hard taco shell, an overly thick tortilla, or an oversized portion.',
    uno
      ? 'Show this product exactly twice, as a pair of servings. Do not add any other food or drink, and do not repeat a product to fill space beyond those two servings.'
      : 'Show only these products, each one once. Do not add any other food or drink, and do not repeat a product to fill space.',
    'No salsa bowls, lime wedges, herbs, or garnishes that are not part of a product.',
    'A drink stands in its own plain glass or cup, with no logo, no brand, and no text.',
    'Leave enough surrounding space for the pitch markings to remain visible.',
    `The food must never cover the entire ${cartel ? 'lower zone' : 'lower half'}.`,
    'No floating ingredients.',
    'No exaggerated ingredient explosions.',
    'No giant piles of ingredients.',
    'Keep every element clean and intentional.',
    '5. FOOTBALL DETAIL',
    'Include ONE small traditional black-and-white football.',
    'Position it near the center-right portion of the pitch, between the typography and food composition.',
    'Show it from the same high angle as the rest of the scene.',
    'The football should appear to be resting on the green surface.',
    'Its size must remain modest.',
    'The ball should support the football theme rather than dominate the design.',
    'Do not add players, jerseys, trophies, goalposts, stadium lights, or spectator crowds.',
    'The pitch markings and small football are enough to communicate the theme.',
    '6. TYPOGRAPHY — MODERN PLAYFUL FAST-FOOD CAMPAIGN',
    'Use a heavy, rounded, playful fast-food campaign typography.',
    'The main headline must be:',
    `"${titular}"`,
    'Exactly these words, on one or two lines, breaking only between words.',
    'No spelling changes.',
    'Use a heavy, rounded, modern display typeface.',
    'Typography should be:',
    '* Bold and playful.',
    '* Professionally kerned.',
    '* Clean and readable.',
    '* Smooth-edged.',
    '* Consistent in weight.',
    '* Commercially polished.',
    '* Slightly organic without looking childish.',
    `Typography color: warm ivory ${MARFIL}.`,
    'Place this headline predominantly in the top section.',
    'Center it horizontally or use a very carefully balanced slight left alignment.',
    'The words must remain completely legible.',
    'Use generous margins.',
    'Do not overlap the food with the headline.',
    'No black outlines.',
    'No giant drop shadows.',
    'No fake 3D extrusions.',
    'No grunge textures.',
    'No distressed lettering.',
    'No hand-painted brush effects.',
    'No warped or randomly stretched characters.',
    'The headline should look like a real professional graphic designer typeset it.',
    '7. SECONDARY COPY',
    'Under the main headline, add this exact phrase:',
    `"${frase}"`,
    'Use a much smaller clean sans-serif font.',
    `Color: warm ivory ${MARFIL}.`,
    'Use restrained letter spacing and elegant alignment.',
    'At the bottom, if there is sufficient space, include a small CTA:',
    '"ORDENA AHORA"',
    ...(contacto ? [`Below it, at the very bottom, in the same small clean sans-serif, one line reading exactly: ${contacto}`] : []),
    'Do not include any prices, discounts, special offers, dates, or other promotional claims beyond the copy above.',
    'Do not invent business names or logos.',
    'Spell every word exactly as written, with its accents.',
    '8. ART DIRECTION AND SPACING',
    `The ${pieza} must feel like a cohesive professional graphic design.`,
    'The top typography should have enough breathing room.',
    'The football-field lines should help guide the viewer through the composition.',
    'The products and the football should be arranged asymmetrically but harmoniously.',
    'Preserve visible green negative space between all major elements.',
    'Do not fill every available area.',
    'Avoid graphic clutter.',
    'The composition should look intentional, modern, and premium.',
    '9. LIGHTING AND PHOTOGRAPHIC AUTHENTICITY',
    'Use soft, broad commercial photography lighting from the upper-left.',
    'Shadows should fall naturally onto the green surface.',
    'Maintain consistent shadows for every object.',
    'The food must retain real-life imperfections.',
    'The food should look freshly prepared, not sculpted from plastic.',
    'Avoid excessive gloss, fake sharpness, HDR textures, and overly dramatic lighting.',
    'A drink, if there is one, must look physically believable.',
    'The finished scene should resemble a genuine food photography set photographed from a high angle and finished by a professional graphic designer.',
    '10. STRICT NEGATIVE REQUIREMENTS',
    'NO STADIUM.',
    'NO REALISTIC GRASS FIELD.',
    'NO WOODEN TABLE.',
    'NO CUTTING BOARD.',
    'NO WOODEN SERVING TRAY.',
    'NO EYE-LEVEL FOOD PERSPECTIVE.',
    'NO FRONT VIEW.',
    'NO HORIZON.',
    'NO GIANT FOOD.',
    'NO CGI FOOD.',
    'NO RANDOM BRANDING.',
    'NO COCA-COLA LOGO.',
    'NO INVENTED PROMOTIONS.',
    'NO MEXICAN FLAGS OR DECORATIVE BANNERS.',
    'NO COMIC-BOOK OUTLINES.',
    'NO THICK BLACK TEXT SHADOWS.',
    'NO EXCESSIVE GRAPHIC STICKERS.',
    'NO RANDOM FOOTBALL TACTICAL ARROWS.',
    'NO OVERCROWDED COMPOSITION.',
    'NO EXTRA FOOD ITEMS.',
    'NO SALSA BOWLS, LIME WEDGES, OR GARNISHES.',
    'NO TEXT OTHER THAN THE SPECIFIED COPY.',
    '11. FINAL CREATIVE TARGET',
    'Produce a sophisticated, fun, modern Mexican food advertisement based on the visual language of a football pitch seen from a high angle.',
    `A rich emerald-green football-themed surface fills the entire ${cartel ? 'horizontal banner' : 'vertical poster'}.`,
    'Precise white field markings are visible and form part of the design.',
    'At the top, beautifully typeset rounded ivory lettering reads:',
    `"${titular}"`,
    'Below it:',
    `"${frase}"`,
    `In the ${cartel ? 'lower zone' : 'lower half'}, only ${uno ? 'two servings of the product' : `the ${CUANTOS[n]} products`}, thoughtfully arranged on the same green surface and seen from about 60 degrees above.`,
    'A small football reinforces the theme.',
    'The design must look clean, natural, cohesive, and professionally art-directed.',
    'It should feel like a contemporary advertising campaign from a talented food branding studio, not like an AI-generated restaurant collage.',
    'FINAL PRIORITY ORDER:',
    '1. ONE STEEP HIGH ANGLE, ABOUT 60 DEGREES, FOR THE WHOLE SCENE.',
    '2. COHESIVE GREEN FOOTBALL PITCH SURFACE.',
    '3. CLEAN ROUNDED PREMIUM TYPOGRAPHY.',
    '4. AUTHENTIC MEXICAN FOOD, ONLY THE PRODUCTS DESCRIBED.',
    '5. NATURAL PHOTOGRAPHY AND CONSISTENT PERSPECTIVE.',
    '6. GENEROUS NEGATIVE SPACE AND PROFESSIONAL DESIGN BALANCE.',
  ];
  return secciones.join('\n');
}
