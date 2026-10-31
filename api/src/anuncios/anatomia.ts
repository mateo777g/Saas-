// Estilo 3 · Anatomía (anatomia.txt, el prompt del desarrollador): el producto de Don Chuy desarmado en
// el aire, capa por capa, con sus 5 etiquetas. Las capas y sus etiquetas las escoge el paso de texto,
// cada una «NOMBRE / descripción» (worker-7b1.md, 25). Su color pinta el fondo con la luz del marfil. No
// lleva mensaje ni datos del restaurante; el cartel, el teléfono y la dirección.
import { AUTENTICO, comoEs, contactoDelCartel, lienzo, luzCalida, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo, Lugar } from './comun';

const TONOS = { fondo: '#F5F0E9' };

const CAPAS: Lugar[] = [1, 2, 3, 4, 5].map((i) => ({
  clave: `capa_${i}`,
  nombre: `La capa ${i}`,
  tope: 50,
  mayusculas: false,
  cuando: 'siempre',
  pide: `La capa ${i} de 5 del producto desarmado, de arriba abajo (la 1 hasta arriba; la 5, la base que sostiene lo demás): un ingrediente que ese platillo lleva de verdad, por su nombre y su descripción. Su nombre en MAYÚSCULAS, una diagonal y una descripción corta con punto, como «CILANTRO FRESCO / El toque verde y aromático.». Cada capa distinta de las demás.`,
  forma: {
    regla: /^[^a-záéíóúüñ/]+ \/ [^/]+$/u,
    explica: 'va como «NOMBRE / descripción»: el nombre en mayúsculas, una diagonal y la descripción.',
  },
}));

export const anatomia: Estilo = {
  clave: 'anatomia',
  maximo: 1,
  minimo: 1,
  mensaje: 0,
  mayusculas: false,
  conColor: true,
  vacio: null,
  datos: { post: [], historia: [], cartel: ['telefono', 'direccion'] },
  lugares: CAPAS,
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const p = a.productos[0];
  const color = a.color;
  const fondo = pintar(color, TONOS).fondo;
  const contacto = cartel ? contactoDelCartel(a.restaurante, false) : null;
  // «CILANTRO FRESCO / El toque verde y aromático.» → su nombre y su descripción.
  const capas = [1, 2, 3, 4, 5].map((i) => {
    const [nombre, descripcion] = a.palabras[`capa_${i}`].split(' / ');
    return { nombre, descripcion };
  });

  const secciones = [
    `Create an exceptionally high-quality, photorealistic commercial food advertising ${cartel ? 'banner' : 'poster'} featuring an EXPLODED ANATOMY VIEW OF ONE AUTHENTIC PRODUCT: ${comoEs(p)}`,
    '',
    '### 1. CREATIVE CONCEPT',
    '',
    'Present the product as a visually spectacular, vertically exploded arrangement of its individual ingredients.',
    '',
    'The concept is a premium food anatomy advertisement: the viewer should immediately understand how the product is assembled by seeing its ingredients suspended in midair.',
    '',
    'Imagine a professional advertising photographer capturing every ingredient in perfect alignment, frozen at the exact moment before the product assembles itself.',
    '',
    'The design should feel precise, appetizing, sophisticated, educational, and visually extraordinary.',
    '',
    '### 2. CANVAS AND BACKGROUND',
    '',
    a.formato === 'post' ? 'Vertical 4:5 advertising poster, approximately 1080 × 1350.' : lienzo(a.formato),
    '',
    color
      ? `Use a bright, uniform, soft ${nombreDelColor(color)} background, approximately ${fondo}.`
      : `Use a bright, uniform, warm ivory background, approximately ${fondo}.`,
    '',
    'The background must be clean, minimal, and softly illuminated, with a seamless studio photography appearance.',
    '',
    'Maintain generous negative space around the floating ingredients and annotations.',
    '',
    'Do not use gradients, colorful geometric shapes, decorative patterns, or split-color backgrounds.',
    '',
    'The food itself should provide the strongest colors in the composition.',
    ...luzCalida(color, 'the background'),
    '',
    '### 3. EXPLODED STRUCTURE — CRITICAL',
    '',
    'Arrange the product\'s components in a carefully controlled vertical exploded stack, with visible empty gaps between ingredient groups.',
    '',
    'From TOP to BOTTOM, exactly these five layers:',
    '',
    ...capas.flatMap((c, i) => [
      `LAYER ${i + 1} — ${c.nombre}`,
      '',
      i === 4
        ? 'At the very bottom: the base that holds everything, shown open and empty because the other ingredients are floating above it.'
        : 'A natural, appetizing group of this ingredient, prepared and cut exactly as it is in the product, floating in its place in the stack.',
      '',
    ]),
    ...AUTENTICO.slice(0, 3),
    'If the product is a taco: ONE soft tortilla at the bottom, gently curved into an open U-shaped taco cradle, empty because the fillings are floating above it; never a second tortilla above the fillings, never a crunchy taco shell or a flat circular plate.',
    SOLO_LOS_SUYOS,
    '',
    'The vertically aligned ingredients should visually suggest that they could fall directly into place to form the complete product.',
    '',
    '### 4. SPATIAL COMPOSITION',
    '',
    cartel
      ? 'Position the exploded product in the center of the banner, occupying approximately 75–85% of the banner height, with the labels on both sides.'
      : 'Position the exploded product centrally, occupying approximately 65–75% of the canvas height.',
    '',
    'Maintain clear and intentional vertical separation between the ingredient groups.',
    '',
    'Each group must have enough breathing room to be individually recognized.',
    '',
    'The largest visual masses should be the main filling and the base.',
    '',
    'Every ingredient should remain proportionally realistic, not oversized.',
    '',
    'Use a slightly frontal three-quarter camera angle, similar to premium commercial food photography.',
    '',
    'The exploded arrangement must remain physically coherent and visually understandable.',
    '',
    'Do not let ingredients overlap so heavily that the exploded structure becomes unreadable.',
    '',
    '### 5. FOOD PHOTOGRAPHY AND LIGHTING',
    '',
    'Use extremely realistic high-end studio food photography.',
    '',
    'Sharp details, beautiful ingredient textures, natural reflections, realistic color, and carefully controlled highlights.',
    '',
    'Soft but directional lighting from the upper left, producing convincing depth and delicate shadows on each suspended ingredient group.',
    '',
    'Use subtle ambient occlusion and natural shadows to reinforce the dimensional separation.',
    '',
    `The bottom layer should cast a soft contact shadow onto the ${color ? 'background' : 'ivory'} surface.`,
    '',
    'Add a very restrained amount of tiny food particles between layers only if they improve realism.',
    '',
    'No dramatic smoke, flames, excessive flying debris, artificial splashes, or exaggerated cinematic effects.',
    '',
    '### 6. EDITORIAL ANATOMY ANNOTATIONS',
    '',
    'Surround the exploded product with five small, sophisticated editorial ingredient labels.',
    '',
    'Use thin, precise, muted dark-brown or charcoal-gray leader lines extending from the labels toward the corresponding ingredient groups.',
    '',
    'Each line should terminate with a tiny circular anchor point near the relevant ingredient.',
    '',
    'Alternate labels between the left and right sides to create a balanced technical-diagram composition.',
    '',
    'The lines must not cross each other or obscure the food.',
    '',
    'Include EXACTLY these Spanish labels and descriptions, from the top layer to the bottom one:',
    '',
    ...capas.flatMap((c) => [`"${c.nombre}"`, `"${c.descripcion}"`, '']),
    'Ingredient names must be uppercase, bold, clean, and highly legible.',
    '',
    'Descriptions must appear below their corresponding names in smaller, regular-weight sans-serif typography.',
    '',
    'Use refined editorial typography, similar to a premium culinary magazine or modern food science illustration.',
    '',
    'Text must be horizontally aligned and neatly spaced.',
    '',
    'Maintain enough contrast against the light background for comfortable reading.',
    '',
    'No extra labels, no invented ingredients, and no misspellings: spell every word exactly as written, with its accents.',
    ...(contacto
      ? ['', `At the bottom center of the banner, add one small line in the same regular-weight sans-serif, reading exactly: ${contacto}`]
      : []),
    '',
    '### 7. VISUAL HIERARCHY',
    '',
    'The exploded product is the absolute hero.',
    '',
    'Ingredient labels are secondary and should never dominate the composition.',
    '',
    'The design must look like a premium food anatomy advertisement, not a classroom diagram, an infographic template, or a scientific textbook page.',
    '',
    'Use generous whitespace and disciplined typography.',
    '',
    'Do not introduce a large headline at the top.',
    '',
    'Do not include the words "ANATOMY" or "1. ANATOMY".',
    '',
    'Do not include any inset product photograph, thumbnail, decorative arrow, numbering system, Instagram interface, or carousel navigation.',
    '',
    '### 8. STRICT EXCLUSIONS',
    '',
    'No ingredient other than the five layers.',
    '',
    'No duplicate layers.',
    '',
    'No fully assembled product floating alongside the ingredient layers.',
    '',
    'No giant headline.',
    '',
    contacto
      ? 'No price, promotion, discount, logo, website, or call to action, and no contact detail other than the line above.'
      : 'No price, promotion, discount, logo, phone number, address, website, or call to action.',
    '',
    'No illustrations, cartoon effects, plastic-looking food, or artificial 3D rendering.',
    '',
    'No random decorative elements.',
    '',
    '### 9. FINAL QUALITY STANDARD',
    '',
    `The final ${cartel ? 'banner' : 'poster'} must immediately communicate:`,
    '',
    `"This is the anatomy of a real ${p.nombre}."`,
    '',
    'Every ingredient should be clearly identifiable, beautifully photographed, and logically positioned above its base.',
    '',
    'Keep the exploded-food advertising concept and the elegant ingredient annotation system, adapted authentically to this product.',
    '',
    'The final image should look like an expensive, professionally art-directed food advertising campaign with exceptional photographic realism, disciplined composition, and precise Spanish typography.',
  ];
  return secciones.join('\n');
}
