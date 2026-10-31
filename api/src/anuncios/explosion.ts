// Estilo 4 · Explosión (explosion.txt, el prompt del desarrollador): el producto de Don Chuy partido en
// el aire, con sus ingredientes estallando entre las dos mitades, sobre un fondo plano. Su color pinta
// el fondo. No llevaba ningún texto: su sección 9 cambia por los de la tabla (arriba el nombre del
// producto; abajo su mensaje, si hay, y el nombre del restaurante chiquito). Un producto que no se parte
// en dos (una bebida, un postre en vaso) se queda entero y sus ingredientes estallan alrededor.
import { AUTENTICO, comoEs, contactoDelCartel, letraSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const TONOS = { fondo: '#D71920' };

export const explosion: Estilo = {
  clave: 'explosion',
  maximo: 1,
  minimo: 1,
  mensaje: 40,
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
  const p = a.productos[0];
  const color = a.color;
  const fondo = pintar(color, TONOS).fondo;
  const rojo = color ? nombreDelColor(color) : 'crimson-red';
  const letra = letraSobre(fondo);
  const mensaje = a.mensaje ? mayus(a.mensaje) : null;
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;

  const textos = cartel
    ? [
        `* On the left half, in the upper part: the product name, large, reading exactly: "${mayus(p.nombre)}"`,
        ...(mensaje ? [`* On the left half, below the product name, smaller: "${mensaje}"`] : []),
        `* On the left half, at the bottom: the restaurant name, small, reading exactly: "${marca}"`,
        ...(contacto ? [`* Below it, smaller still: ${contacto}`] : []),
      ]
    : [
        `* At the top, centered, from about 5% to 17% of the height: the product name, large, reading exactly: "${mayus(p.nombre)}"`,
        ...(mensaje ? [`* Near the bottom, centered, at about 84% to 90% of the height, smaller: "${mensaje}"`] : []),
        `* At the very bottom, centered, at about 92% to 96% of the height: the restaurant name, small, reading exactly: "${marca}"`,
      ];

  const secciones = [
    'STYLE_04 — CINEMATIC FOOD EXPLOSION V2',
    `Create an extraordinary, ultra-photorealistic cinematic commercial food advertisement featuring ONE PRODUCT, "${p.nombre}", dramatically exploding apart in midair.`,
    `IMPORTANT: The background is a perfectly flat, solid ${rojo} background. The background must not resemble a physical studio, restaurant, or room.`,
    '1. CORE CREATIVE CONCEPT',
    'Imagine a premium commercial food campaign with the visual intensity, precision, and dramatic impact of a Hollywood blockbuster.',
    'The freshly prepared product has been split apart in midair, revealing its delicious internal ingredients in an extraordinary frozen moment of explosive motion.',
    'Capture the exact fraction of a second when the two halves separate and the fillings burst outward between them.',
    'If the product cannot be split into two halves (a drink, a dessert in a cup), it stays whole at the center while its own ingredients burst outward around it.',
    'This is NOT an instructional anatomy diagram.',
    'This is a spectacular, high-end cinematic product advertisement.',
    'The result must feel energetic, powerful, delicious, dramatic, and meticulously art-directed.',
    '2. CANVAS AND BACKGROUND — STRICT FLAT COLOR',
    a.formato === 'post' ? 'Create a vertical 4:5 commercial advertising poster.' : lienzo(a.formato),
    `Use a completely solid, uniform, vivid ${rojo} background, exactly ${fondo}.`,
    'The entire canvas must have ONE SINGLE CONTINUOUS BACKGROUND COLOR from the top edge to the bottom edge.',
    'The background must be perfectly flat, seamless, and graphic, resembling a solid-color advertising backdrop rather than a physical photographic environment.',
    'ABSOLUTELY NO:',
    '* Floor or ground plane.',
    '* Horizon line.',
    '* Wall-to-floor transition.',
    '* Studio environment.',
    '* Surface beneath the product.',
    '* Background shadows.',
    '* Vignetting.',
    '* Gradients.',
    '* Darkened corners.',
    '* Darker color transitions.',
    '* Textures, grain, or patterns.',
    '* Atmospheric lighting effects on the background.',
    `The product must appear suspended in an infinite, perfectly uniform ${rojo} space.`,
    `The ${rojo} background must remain visually identical in color and brightness throughout the entire image, including the area beneath the floating product.`,
    '3. HERO PRODUCT',
    `Feature ONE large, authentic product: ${comoEs(p)}`,
    ...AUTENTICO.slice(0, 3),
    'If the product is a taco: one thin, soft tortilla that stays whole, folded into a natural U shape, never a crunchy shell, while its fillings burst upward and outward from its open top.',
    SOLO_LOS_SUYOS,
    'Avoid exaggerated or oversized ingredients.',
    '4. THE CINEMATIC EXPLOSION — MOST IMPORTANT',
    'The product must be dramatically separated into TWO DISTINCT HALVES, suspended vertically in midair.',
    'UPPER HALF',
    'Position the upper section of the product near the upper-middle portion of the composition.',
    'Angle it slightly upward and toward the viewer.',
    'Its cut opening must face downward toward the center of the explosion.',
    'Its outside should remain intact around the upper section, with realistic texture and visible internal filling near the opening.',
    'LOWER HALF',
    'Position the lower section of the product near the lower-middle portion of the composition.',
    'Angle it slightly downward and away from the upper half.',
    'Its cut opening must face upward toward the center of the explosion.',
    'The lower section must remain structurally intact and clearly recognizable as the other half of the same product.',
    'BETWEEN BOTH HALVES',
    "Create a breathtaking, suspended explosion of the product's actual ingredients, and only its own.",
    'Its ingredients should appear frozen in midair.',
    'The ingredients should form a dynamic, organic, three-dimensional burst connecting the two halves.',
    'Use realistic trajectories and physically believable ingredient movement.',
    'Some ingredients should remain clustered close to the openings, while smaller particles scatter naturally into the surrounding space.',
    'The explosion should feel powerful but carefully controlled.',
    'Maintain a clear visual relationship between the two halves and the suspended ingredients.',
    'The viewer must immediately recognize that all the flying ingredients came from inside this single product.',
    'Do not create separate ingredient shelves, rigid horizontal layers, or a scientific exploded diagram.',
    'This is a dynamic cinematic burst, not a technical disassembly.',
    '5. CAMERA AND PERSPECTIVE',
    'Use a slightly low, frontal three-quarter camera angle.',
    cartel
      ? 'Position the exploding product on the right half of the banner, occupying approximately 85% of the banner height; the texts go on the left half.'
      : `Position the exploding product in the central vertical axis of the ${pieza}, occupying approximately 60% of the image height, between the product name at the top and the texts at the bottom.`,
    'Give the upper and lower halves slightly different rotations to create natural motion and cinematic tension.',
    'Use a premium commercial food photography lens aesthetic, with crisp hero-product details and realistic depth of field.',
    'Keep the main ingredients and the two halves sharply defined while allowing only a few tiny background particles to soften naturally with depth.',
    'Avoid extreme wide-angle distortion or unrealistic proportions.',
    '6. CINEMATIC PRODUCT LIGHTING — ISOLATED FROM BACKGROUND',
    'Apply dramatic, premium commercial photography lighting EXCLUSIVELY to the product and its flying ingredients.',
    'Use a warm directional key light from the upper left to emphasize the realistic food textures.',
    `Use a subtle reddish-orange rim light to separate the product from the ${rojo} background.`,
    'Use controlled neutral fill lighting from the front-right to preserve natural detail in the ingredients.',
    'The food should have dimensional shadows, realistic highlights, rich contrast, and exceptional photographic depth.',
    'The lighting must emphasize the textures and the natural colors of every ingredient, and the three-dimensional depth of the ingredient explosion.',
    ...luzCalida(color, 'the background'),
    'CRITICAL: All lighting and shadows must affect ONLY the food itself.',
    'The background must remain perfectly flat and unaffected by the lighting setup.',
    'Do not create any cast shadow beneath the product.',
    'Do not simulate a floor, studio surface, or physical environment.',
    `The visual contrast must come from the realistic, dramatically illuminated food against the completely uniform ${rojo} background.`,
    'No artificial neon lighting, excessive lens flares, glowing food, or exaggerated visual effects.',
    '7. MOTION AND PARTICLE DETAIL',
    'Capture the explosion at an extremely high shutter speed, freezing the ingredients in a precise moment of motion.',
    "Include a restrained amount of tiny pieces of the product's own ingredients and natural food crumbs around the central explosion.",
    'Use subtle spatial depth, with some particles slightly closer to the camera and others farther away.',
    'The food must remain the primary visual attraction.',
    'No fireballs, smoke clouds, magical energy, electric effects, glowing particles, or science-fiction elements.',
    'The cinematic quality should come from photography, lighting, composition, and controlled motion — not artificial VFX.',
    '8. COMPOSITIONAL DISCIPLINE',
    'Maintain a bold, elegant advertising composition.',
    `The exploding product must remain ${cartel ? 'on the right half' : 'visually centered'} and instantly recognizable.`,
    'Leave sufficient negative space around the product.',
    'The upper and lower halves must be clearly separated, with the filling visibly suspended between them.',
    'The arrangement should create a strong diagonal sense of motion while retaining an overall vertical silhouette.',
    'Keep the image balanced, impactful, and visually clean.',
    'Do not add secondary products, plates, bowls, cutlery, hands, or packaging.',
    '9. TEXT',
    `Add only these texts, printed flat over the ${rojo} background, never over the food:`,
    ...textos,
    `Use a heavy, bold, condensed sans-serif, all uppercase, tight letter spacing, in clean ${letra}.`,
    'Spell every word exactly as written, with its accents.',
    'The texts stay secondary to the explosion: the food photography delivers the commercial impact.',
    'Do not include:',
    '* Logos.',
    '* Prices.',
    '* Promotions or calls to action other than the texts above.',
    ...(contacto ? [] : ['* Phone numbers.']),
    '* Websites.',
    '* Ingredient labels.',
    '* Decorative typography.',
    '* Watermarks.',
    '* Social media interface elements.',
    '10. STRICT VISUAL EXCLUSIONS',
    'Do not change the product into a different dish.',
    'Do not create more than two main halves.',
    'Do not duplicate the product.',
    'Do not make the product look like a plastic 3D render.',
    'Do not turn the filling into perfectly organized horizontal layers.',
    'Do not place ingredients in unnatural symmetrical patterns.',
    color ? 'Do not use a different color, a white, a cream, or a textured background.' : 'Do not use an orange, white, cream, or textured background.',
    'Do not include a restaurant interior.',
    'Do not include a floor, ground plane, horizon, surface, or background shadows.',
    'Do not introduce gradients, vignetting, darkened corners, or changes in background color.',
    'Do not add unrelated visual effects, decorative shapes, or typography.',
    '11. FINAL QUALITY STANDARD',
    'The finished advertisement must look like an exceptionally expensive, professionally photographed commercial campaign.',
    'The product must be unmistakably authentic, delicious, and physically believable.',
    'The two halves should float dramatically apart, while their actual fillings explode between them in a beautiful frozen moment of cinematic motion.',
    `The perfectly uniform ${rojo} background must enhance the warm colors of the food without any visual distractions.`,
    'The final image should feel like an iconic, high-impact commercial food photograph: bold, dramatic, photorealistic, and unforgettable.',
    'ABSOLUTE FINAL PRIORITY:',
    `One photorealistic product dramatically exploding into two separated halves, with its ingredients suspended between them, floating against a perfectly flat, uninterrupted ${fondo} ${rojo} background, with "${mayus(p.nombre)}" ${cartel ? 'on the left' : 'at the top'} and "${marca}" small ${cartel ? 'below it' : 'at the bottom'}.`,
    'NO FLOOR. NO HORIZON. NO BACKGROUND TEXTURE. NO GRADIENT. NO BACKGROUND SHADOWS.',
    'Premium cinematic food photography meets bold, minimalist graphic advertising.',
  ];
  return secciones.join('\n');
}
