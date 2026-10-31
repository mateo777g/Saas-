// Estilo 2 · Letra gigante (letra-gigante.txt, el prompt del desarrollador): el nombre del producto
// enorme arriba, un subtítulo chiquito y el producto abajo, sobre marfil. Su color pinta la letra; el
// marfil se queda. Los renglones de su referencia (un póster de hamburguesa) se quitan: los colores, el
// acomodo y la letra que daba ya los describe el prompt. El subtítulo es su mensaje; vacío, la
// descripción de Mi menú; sin descripción, no lleva.
import { AUTENTICO, cap, comoEs, contactoDelCartel, legibleSobre, lienzo, luzCalida, mayus, nombreDelColor, pintar, SOLO_LOS_SUYOS } from './comun';
import type { Anuncio, Estilo } from './comun';

const TONOS = { letra: '#F52216' };
const MARFIL = '#F5F0E9';

export const letraGigante: Estilo = {
  clave: 'letra-gigante',
  maximo: 1,
  minimo: 1,
  mensaje: 60,
  mayusculas: true,
  conColor: true,
  vacio: '#desc',
  datos: { post: [], historia: [], cartel: ['telefono', 'direccion'] },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const p = a.productos[0];
  const color = a.color;
  // Con un color claro la letra se oscurece hasta leerse sobre el marfil.
  const letra = color ? legibleSobre(pintar(color, TONOS).letra, MARFIL) : TONOS.letra;
  const rojo = color ? nombreDelColor(color) : 'red';
  const subtitulo = a.mensaje ? mayus(a.mensaje) : p.descripcion ? mayus(p.descripcion) : null;
  const contacto = cartel ? contactoDelCartel(a.restaurante, true) : null;

  const subtituloTexto = subtitulo
    ? [
        '4. SMALL EDITORIAL SUBHEADLINE',
        `Below the oversized headline, place a small centered ${rojo} uppercase subtitle reading exactly:`,
        `"${subtitulo}"`,
        'Use a bold condensed sans-serif font. Keep it significantly smaller than the main headline, with generous empty space around it. If it is long, set it in two or three short centered lines.',
        'This subtitle should feel like a restrained editorial caption, not a promotional badge.',
      ]
    : ['4. NO SUBHEADLINE', 'Do not add a subtitle below the headline: leave generous empty space there.'];
  if (contacto) {
    subtituloTexto.push(`At the bottom left of the banner, place one small ${rojo} line in the same bold condensed sans-serif, much smaller than everything else, reading exactly: ${contacto}`);
  }
  subtituloTexto.push('Do not add any other headlines, slogans, labels, or invented text.');

  const composicion = cartel
    ? [
        'Follow this restrained horizontal composition:',
        '',
        `* Left side, about 55% of the banner width: the enormous ${rojo} headline${subtitulo ? `, with the small centered ${rojo} subtitle below it, surrounded by generous negative space` : ''}.`,
        '* Right side: one large, realistic photograph of the product.',
        ...(contacto ? ['* Bottom left, small: the phone and the address.'] : []),
        '',
      ]
    : [
        'Follow this restrained vertical composition:',
        '',
        `* Upper section: enormous ${rojo} headline.`,
        subtitulo ? `* Middle section: small centered ${rojo} subtitle surrounded by generous negative space.` : '* Middle section: generous negative space.',
        '* Lower section: one large, realistic photograph of the product.',
        '',
      ];

  const secciones = [
    `Create a premium commercial fast-food advertising ${cartel ? 'banner' : 'poster'} with a bold editorial art direction: a minimalist composition, extreme typography scale, generous negative space, and a premium product-photography treatment.`,
    `THE PRODUCT IS "${p.nombre}". DO NOT CREATE A DIFFERENT DISH.`,
    '1. CORE CREATIVE DIRECTION',
    `The visual philosophy: oversized, bold ${rojo} typography against a warm off-white background, a remarkably simple editorial layout, and one large, photorealistic food hero ${cartel ? 'on the right side' : 'in the lower portion'} of the composition.`,
    'The design must feel confident, iconic, minimal, modern, and commercially art-directed. Its visual impact comes from extreme typographic scale, generous negative space, strong contrast, and appetizing product photography — not from decorative graphics.',
    'Treat this as a professional fast-food brand campaign photographed and designed by an experienced advertising agency.',
    '2. CANVAS AND BACKGROUND',
    a.formato === 'post' ? 'Create a vertical 4:5 advertising poster.' : lienzo(a.formato),
    `Use a uniform warm ivory / off-white background, approximately ${MARFIL}, covering the entire canvas.`,
    'The background must remain clean, bright, and uninterrupted. A very subtle natural paper-like photographic character is acceptable, but do not introduce visible paper fibers, grunge, noise, patterns, gradients, or decorative textures.',
    `Use vivid, saturated ${color ? rojo : 'vermilion red'}, approximately ${letra}, as the primary typography color.`,
    `The composition must remain predominantly off-white, ${rojo}, and the natural warm colors of the food.`,
    ...luzCalida(color, 'the letters'),
    '3. OVERSIZED TYPOGRAPHY — THE MAIN VISUAL SIGNATURE',
    `${cartel ? 'On the left side of the banner' : 'At the very top of the poster'}, place an enormous ${rojo} headline with the product name, reading exactly:`,
    `"${mayus(p.nombre)}"`,
    `The words must be extremely large, occupying almost the entire available width of the ${cartel ? 'left side of the banner' : 'upper canvas'}. Use heavy, bold, condensed sans-serif typography with clean geometric construction and strong editorial character.`,
    'The letters should feel monumental and tightly composed.',
    `If the name has more than one word, you may break it into two lines, only between words: the first line enormous, and the second line also bold, ${rojo}, and highly prominent, but carefully balanced with the first so the overall typography remains intentional and refined.`,
    'Preserve clear, correctly spelled lettering, with its accents. Do not crop letters in ways that make the words unreadable. The typography must look professionally typeset, with consistent alignment and deliberate spacing.',
    ...subtituloTexto,
    '5. HERO PRODUCT',
    `${cartel ? 'On the right side of the banner' : 'In the lower half of the poster'}, feature one exceptionally appetizing, photorealistic product as the dominant food subject: ${comoEs(p)}`,
    ...AUTENTICO,
    SOLO_LOS_SUYOS,
    'The food must look freshly prepared, juicy, warm, and genuinely edible.',
    'Photograph the product from a low, slightly frontal three-quarter angle, close to the viewer, with a powerful commercial food-photography presence.',
    `Make the product large enough to anchor the ${cartel ? 'right side' : 'lower half'} of the composition. It should feel substantial and visually striking without becoming oversized to the point of looking physically implausible.`,
    'Use crisp focus on the food, visible texture, subtle natural highlights, realistic shadows, and professional studio food photography.',
    'Place the product directly against the same warm off-white environment. Give it a convincing contact shadow extending naturally across the surface toward one side, like a grounded studio shadow.',
    'Do not use a floating product, cutout collage, illustrated food, 3D-rendered appearance, or artificial plastic-looking ingredients.',
    '6. COMPOSITION AND NEGATIVE SPACE',
    ...composicion,
    'Maintain a strong separation between typography and product. The product should not obscure the headline or subtitle.',
    'Keep the layout simple and asymmetrical only where the food photography naturally requires it. Every element must have a clear purpose.',
    'Do not fill empty areas simply because they are empty. Negative space is an essential part of the design.',
    '7. STRICT EXCLUSIONS',
    'Do not include:',
    '',
    '* Any food or drink other than the product described above.',
    `* ${cap(rojo)}-and-cream horizontal split backgrounds.`,
    '* Price tags, discount bursts, stickers, badges, or promotional shapes.',
    '* Flames, smoke effects, flying ingredients, or excessive food splashes.',
    '* Mexican folk patterns, sombreros, flags, or stereotypical decorative motifs.',
    '* Decorative borders, icons, random geometric shapes, or unnecessary logos.',
    '* Multiple food products or several copies of the product.',
    contacto
      ? '* Unrequested business names, prices, or calls to action, or any contact detail other than the line above.'
      : '* Unrequested business names, prices, phone numbers, addresses, or calls to action.',
    '* Script fonts, western fonts, distressed typography, gradients, or 3D lettering.',
    '',
    '8. FINAL QUALITY STANDARD',
    `The finished image must have this distinctive visual language: enormous vivid-${rojo} typography, warm ivory negative space, ${subtitulo ? 'a tiny restrained editorial subtitle, ' : ''}and a single photorealistic food hero.`,
    'Prioritize professional typography, authentic Mexican food, visual simplicity, appetizing realism, and immediate readability.',
    'The final result should look like an original, premium fast-food advertising campaign — minimal, bold, confident, and unmistakably art-directed.',
  ];
  return secciones.join('\n');
}
