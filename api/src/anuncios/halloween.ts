// Estilo 9 · Halloween (halloween.txt): el producto de Don Chuy en un bloque naranja dentro de un arco
// que brilla, con la sombra de una garra que va por él, en un cuarto rojo oscuro. De temporada (10 al 31
// de octubre) y sin color. Lleva 1 o 2 productos: el segundo va en el bloque bajo, donde la muestra
// tenía el refresco (con uno, el refresco se queda y solo rellena). El titular es su mensaje (vacío,
// «¿DULCE O TRUCO?»); abajo a la izquierda, el nombre del restaurante. Sin el nombre del producto.
import { AUTENTICO, comoEs, contactoDelCartel, lienzo, mayus } from './comun';
import type { Anuncio, Estilo } from './comun';

const CREMA = '#F4EBDC';

export const halloween: Estilo = {
  clave: 'halloween',
  maximo: 2,
  minimo: 1,
  mensaje: 24,
  mayusculas: true,
  conColor: false,
  vacio: '¿DULCE O TRUCO?',
  datos: { post: ['nombre'], historia: ['nombre'], cartel: ['nombre', 'telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const pieza = cartel ? 'banner' : 'poster';
  const dos = a.productos.length === 2;
  const titular = a.mensaje ? `"${mayus(a.mensaje)}"` : '"¿DULCE\nO TRUCO?"';
  const titularCorrido = a.mensaje ? mayus(a.mensaje) : '¿DULCE O TRUCO?';
  const marca = mayus(a.restaurante.nombre);
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;
  const bajo = dos ? 'product 2' : 'the glass of cola';

  const zonas = cartel
    ? [
        lienzo('cartel'),
        'Organize the banner into these zones:',
        'LEFT HALF:',
        'The headline, over the deep red wall, in the upper and middle part.',
        'RIGHT HALF:',
        `A tall arched niche in the wall, glowing orange inside, from about 10% to 80% of the banner height, with two orange blocks standing on a deep red floor: a tall block inside the niche with product 1 on top, and a lower block in front of it, to the left, with ${bajo}.`,
        'LOWER-LEFT CORNER:',
        `A small brand name${contacto ? ', with the phone and the address below it, smaller' : ''}.`,
      ]
    : [
        lienzo(a.formato),
        'Organize the poster into these zones:',
        'TOP 20%:',
        'The headline, centered, over the deep red wall.',
        'CENTER:',
        'A tall arched niche in the wall, glowing orange inside, from about 22% to 72% of the poster height, centered slightly to the right.',
        'LOWER PART:',
        `Two orange blocks standing on a deep red floor: a tall block inside the niche with product 1 on top, and a lower block in front of it, to the left, with ${bajo}.`,
        'LOWER-LEFT CORNER:',
        'A small brand name.',
      ];

  const productos = a.productos.map((p, i) => `* Product ${i + 1}: ${comoEs(p)}`);

  const secciones = [
    'STYLE_12 — HALLOWEEN ARCH',
    'Premium Mexican Food Advertising — Halloween Campaign',
    `Create a professionally art-directed ${cartel ? 'horizontal 16:9 menu banner' : a.formato === 'historia' ? 'vertical 9:16 Instagram story' : 'vertical 4:5 Instagram'} food advertisement featuring ${dos ? 'two products' : 'one product'} in a glowing orange arched niche: product 1 on a tall orange block, with the dark shadow of a clawed hand reaching toward it, ${dos ? 'product 2' : 'a glass of unbranded cola'} on a lower orange block in front, and three small black spiders, in a deep red room.`,
    'THIS IS A MOODY, PLAYFUL, MINIMAL HALLOWEEN PRODUCT SET: a real photographed set with simple geometric blocks, one dramatic light, one spooky shadow, a bold rounded headline, and a small brand name.',
    'Prioritize authentic food photography and physically believable objects over exaggerated or artificial-looking styling.',
    '1. CANVAS AND COMPOSITION',
    ...zonas,
    'The composition must feel simple, bold, theatrical, and clearly designed.',
    '2. THE SET — DEEP RED ROOM WITH A GLOWING ARCH',
    'The background is a smooth, matte, deep red wall, about #560703, slightly darker toward the top edge, about #380502.',
    `In the wall, a tall arched niche with a rounded top and straight sides, about ${cartel ? '32% of the banner width' : '60% of the poster width'}.`,
    'Inside the niche, the back wall glows with warm orange-amber light: brightest behind product 1, about #FDCA5D, and deeper orange toward the edges of the arch, about #F78901.',
    'The edges of the arch are clean and crisp, with a thin visible depth to the wall.',
    'The floor is the same deep red, about #4D0703, with a soft pool of warm light spilling out of the arch onto it, about #902016.',
    'The wall and floor are smooth, matte, and uniform, like a real painted photography set.',
    'No patterns.',
    'No textures.',
    'No windows, doors, furniture, or scenery.',
    '3. THE BLOCKS',
    'Two simple, solid, matte orange rectangular blocks, about #D25D0A on the lit faces and #B64208 on the shaded faces.',
    `The TALL BLOCK stands inside the arch, in its lower part, centered under the glowing light. Its top surface holds product 1, at about 55–60% of the ${pieza} height.`,
    `The LOW BLOCK stands in front of it and to the left, partly overlapping its lower corner, about half its height. Its top surface holds ${bajo}.`,
    'Both blocks have crisp edges, flat faces, and soft, realistic shadows.',
    'No logos, no text, no patterns on the blocks.',
    `4. ${dos ? 'THE PRODUCTS' : 'HERO PRODUCT'}`,
    ...productos,
    ...AUTENTICO,
    dos
      ? 'Show only these products, each one once. Do not add any other food or drink, and do not repeat a product to fill space.'
      : 'Show only this product, once. Besides the glass of cola of the set, do not add any other food or drink, and do not repeat a product to fill space.',
    `Each product rests on a small square of slightly crumpled matte black paper on top of its block.`,
    'Show the food from a slightly elevated front view, so its top and filling are clearly visible.',
    `Product 1 is the largest object in the scene: about ${cartel ? '20% of the banner width' : '40% of the poster width'}, centered in the glow of the arch.${dos ? ' Product 2 is clearly smaller and remains secondary.' : ''}`,
    '5. THE CLAWED-HAND SHADOW',
    'On the glowing back wall of the arch, above and to the left of product 1, cast one sharp, dark shadow of a bony, long-fingered clawed hand reaching down toward it, as if about to grab it.',
    'Only the shadow is visible: there is no actual hand, arm, or creature in the scene.',
    'The shadow is a clean, dark silhouette, slightly softened at the edges like a real cast shadow.',
    'It never covers the food.',
    ...(dos
      ? []
      : [
          '6. GLASS OF COLA',
          'On top of the low block, place ONE clear, simple drinking glass of dark cola.',
          'Include:',
          '* Dark carbonated soda.',
          '* Several natural ice cubes.',
          '* Small realistic bubbles.',
          '* Subtle condensation on the glass.',
          'NO branding.',
          'NO logos.',
          'NO text printed on the glass.',
          'NO fabricated brand labels.',
          'The glass is clearly smaller than the product and remains secondary.',
        ]),
    '7. THREE BLACK SPIDERS',
    'Add exactly three small black spiders, like quality Halloween decorations: realistic shape, long thin legs, satin black finish.',
    'One climbs on the glowing back wall of the arch, to the right of product 1.',
    'One sits on the floor at the lower left.',
    `One sits on the top of the low block, beside ${bajo}.`,
    `The spiders never touch the food${dos ? '' : ' or the glass'}.`,
    'They stay small and playful, never gross or frightening.',
    '8. NATURAL COMMERCIAL FOOD PHOTOGRAPHY',
    'Use believable professional food photography.',
    `The food, ${dos ? '' : 'the glass, '}the blocks, and the set must appear to have been photographed with a real camera.`,
    'The main light is the warm glow inside the arch, behind and above product 1, plus a soft front-left fill light so everything on the blocks is clearly lit and appetizing, never lost in the dark mood.',
    'Preserve natural shadows and realistic textures.',
    'The blocks cast soft, realistic shadows on the floor.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
    '9. HEADLINE — BOLD ROUNDED TYPOGRAPHY',
    `${cartel ? 'On the left half of the banner, over the deep red wall' : 'At the top of the poster, over the deep red wall and above the arch'}, place a headline, centered, ${a.mensaje ? 'in one or two lines (breaking only between words), ' : 'on two lines, '}reading exactly:`,
    titular,
    `The lines are large and about the same height, spanning about ${cartel ? '40% of the banner width' : '70% of the poster width'}.`,
    'Use a heavy, rounded, playful display typeface with a bold contemporary personality.',
    'The typography should resemble a professionally designed fast-food campaign, with slightly organic letter shapes and strong visual impact.',
    `Text color: warm cream ${CREMA}.`,
    'Use tight but controlled letter spacing.',
    'No dripping or melting letters.',
    'No horror or Halloween lettering.',
    'No outlines.',
    'No drop shadows.',
    'No 3D extrusion.',
    'No textures.',
    'The headline never overlaps the arch.',
    'Avoid generic default fonts or distorted lettering.',
    '10. BRAND',
    `In the lower-left corner, over the dark red floor, place a small, compact brand name, in one or two lines:\n"${marca}"`,
    'Use the same rounded typeface, bold, uppercase, small.',
    `Text color: warm cream ${CREMA}.`,
    ...(contacto ? [`Below it, in the same typeface, smaller, one line reading exactly: ${contacto}`] : []),
    'The brand remains secondary.',
    'Do not invent logos or symbols.',
    'Spell every word exactly as written, with its accents.',
    '11. GRAPHIC HIERARCHY',
    'Maintain this visual order:',
    `1. Product 1 in the glowing arch.\n2. The clawed-hand shadow reaching for it.\n3. The "${titularCorrido}" headline.\n4. ${dos ? 'Product 2' : 'The glass of cola'}.\n5. The spiders.\n6. The small brand name${contacto ? ', then the phone and the address' : ''}.`,
    'Keep the design balanced and uncluttered.',
    `Do not overcrowd the ${pieza} with unnecessary elements.`,
    '12. STRICT EXCLUSIONS',
    `Do not include fries, candy, or any other food${dos ? ' or drink' : ''}.`,
    'Do not create several copies of a product, or split one into halves.',
    "Do not include pumpkins, jack-o'-lanterns, bats, ghosts, witches, skulls, skeletons, cobwebs, candles, or tombstones.",
    'Do not show any actual hand, arm, monster, or person: only the shadow.',
    `Do not add more than three spiders, and never place them on the food${dos ? '' : ' or the glass'}.`,
    ...(dos ? [] : ['Do not include Coca-Cola, Pepsi, or any brand on the glass.']),
    contacto
      ? 'Do not include prices, promotions, websites, calls to action, logos, or trademark symbols.'
      : 'Do not include prices, promotions, phone numbers, addresses, websites, calls to action, logos, or trademark symbols.',
    `Do not add any text beyond the headline and the brand name${contacto ? ' with its phone and address' : ''}.`,
    'Do not use dripping, melting, horror, or distressed lettering.',
    `Do not make the food, ${dos ? '' : 'the glass, '}or the blocks look like a 3D render.`,
    '13. FINAL PRIORITY',
    'One authentic product on black paper on a tall orange block, inside a glowing orange arch in a deep red wall, with the dark shadow of a clawed hand reaching for it.',
    `${dos ? 'Product 2' : 'A clear glass of unbranded cola with ice'} on a lower orange block in front, and three small black spiders.`,
    `A bold rounded cream headline ${cartel ? 'on the left' : 'at the top'}: "${titularCorrido}", and a small cream brand name at the lower left.`,
    'Moody, playful, minimal, premium Halloween fast-food advertising.',
    'AUTHENTIC MEXICAN FOOD.',
    'NATURAL PHOTOGRAPHIC FOOD TEXTURES.',
    'A REAL PHOTOGRAPHED SET.',
    'NO CGI-LOOKING FOOD.',
  ];
  return secciones.join('\n');
}
