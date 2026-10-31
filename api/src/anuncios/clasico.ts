// Estilo 1 · Clásico (rojo-y-crema.txt). Es el armar_prompt de Flet (panel/models/generador_ia.py)
// pasado a TypeScript con dos cambios: la separación es la ola de rojo-y-crema.txt, no la línea
// recta, y ya no va la página web. Sin color y con un producto, el post y la historia salen byte por
// byte igual que Flet con esos dos cambios (lo revisa planes/trabajo/7b/worker/probar_clasico.mjs).
// Lleva hasta 5 productos: con varios, el titular es el del 1 y no va precio del menú. El cartel
// pone su color a la izquierda con los textos y el crema a la derecha con el producto.
import { mayus, esClaro } from './comun';
import type { Anuncio, Estilo, Formato } from './comun';

const LLAMADO_A_LA_ACCION = 'ORDENA AHORA';

// Cómo se dice el formato en el prompt (los dos primeros, tal cual Flet).
const DESCRIPCION_FORMATO: Record<Formato, string> = {
  post: 'vertical 4:5 Instagram feed post (1080x1350)',
  historia: 'vertical 9:16 Instagram story (1080x1920)',
  cartel: 'horizontal 16:9 menu banner (2048x1152)',
};

export const clasico: Estilo = {
  clave: 'clasico',
  maximo: 5,
  minimo: 1,
  mensaje: 40,
  mayusculas: false,
  conColor: true,
  vacio: null,
  datos: {
    post: ['nombre', 'precio', 'telefono', 'ordena'],
    historia: ['nombre', 'precio', 'telefono', 'direccion', 'ordena'],
    cartel: ['nombre', 'precio', 'telefono', 'direccion', 'ordena'],
  },
  lugares: [],
  prompt,
};

function prompt(a: Anuncio): string {
  const cartel = a.formato === 'cartel';
  const [principal, ...extras] = a.productos;
  const nombreProducto = principal.nombre.trim();
  const titular = mayus(nombreProducto);
  const precio = extras.length ? '' : (principal.precio ?? '');
  const mensaje = (a.mensaje ?? '').trim();
  const negocio = mayus(a.restaurante.nombre.trim());
  const telefono = (a.restaurante.telefono ?? '').trim();
  const direccion = a.formato === 'post' ? '' : (a.restaurante.direccion ?? '').trim();
  const color = a.color;
  const colorArriba = color ?? 'red';
  // Dónde va el producto: en el post y la historia, al centro sobre la ola; en el cartel, en el crema.
  const centro = cartel ? 'in the center of the cream right half' : 'in the center';

  let heroe: string;
  if (extras.length) {
    const nombresExtra = extras.map((p) => p.nombre.trim());
    const enReferencia = a.productos.filter((p) => p.referencia !== null).map((p) => p.nombre.trim());
    const acompanantes = nombresExtra.map((n) => `"${n}"`).join(' and ');
    const total = a.productos.length;
    heroe =
      `Show ${total} products together as one combo: the main product "${nombreProducto}", accompanied by ${acompanantes}. ` +
      `The main product is the largest, ${centro}, slightly overlapping the boundary between the ${colorArriba} and cream sections; ` +
      'the accompanying products sit beside it, smaller. ' +
      `Because there are ${total} products, draw each one smaller than a single hero product would be, so they all fit comfortably without crowding.`;
    if (enReferencia.length) {
      heroe +=
        '\n\nThe reference images show, in this order: ' +
        enReferencia.map((n) => `"${n}"`).join(', ') +
        '. ' +
        "Keep each product's real look: same food or drink, same ingredients, same shape and same presentation as in its reference image. " +
        'Do not replace them with different products.';
    }
    const sinFoto = a.productos.filter((p) => p.referencia === null).map((p) => p.nombre.trim());
    if (sinFoto.length) heroe += '\n\nDraw ' + sinFoto.map((n) => `"${n}"`).join(', ') + ' photorealistic.';
  } else if (principal.referencia !== null) {
    heroe =
      `Place the product shown in the reference image, "${nombreProducto}", large and prominently ${centro}, slightly overlapping the boundary ` +
      `between the ${colorArriba} and cream sections.\n\n` +
      'Keep its real look: same food, same ingredients, same shape and same presentation as in the reference image. Do not replace it with a different dish.';
  } else {
    heroe = `Place one large, photorealistic "${nombreProducto}" prominently ${centro}, slightly overlapping the boundary between the ${colorArriba} and cream sections.`;
  }

  // CONTENT: solo lo que hay, cada cosa con su etiqueta.
  const contenido: string[] = [];
  if (negocio) contenido.push(`Restaurant name:\n"${negocio}"`);
  contenido.push(`Main headline:\n"${titular}"`);
  if (precio) contenido.push(`Price:\n"${precio}"`);
  if (mensaje) contenido.push(`Promotion:\n"${mensaje}"`);
  if (telefono) contenido.push(`Phone number:\n"${telefono}"`);
  if (direccion) contenido.push(`Address:\n"${direccion}"`);
  contenido.push(`Call to action:\n"${LLAMADO_A_LA_ACCION}"`);

  const jerarquia = [`Make "${titular}" large and prominent, but keep it clean and refined.`];
  if (precio) jerarquia.push(`Make "${precio}" extremely large and visually dominant as the main price.`);
  if (mensaje) {
    jerarquia.push(
      precio
        ? 'Place the promotion close to the price in a compact, easy-to-read format.'
        : 'Place the promotion close to the headline in a compact, easy-to-read format.',
    );
  }
  if (negocio) jerarquia.push(`Place "${negocio}" as a smaller brand element.`);
  const contacto = [telefono, direccion].filter((x) => x);
  if (contacto.length) {
    jerarquia.push(
      'Place the contact details (' + contacto.map((x) => `"${x}"`).join(', ') + ') small, clean and legible near the bottom' + (cartel ? ' of the left half.' : '.'),
    );
  }
  jerarquia.push(`Place "${LLAMADO_A_LA_ACCION}" as a simple modern call-to-action.`);
  if (cartel) jerarquia.push(`Place every text on the ${colorArriba} left half, left-aligned, and keep the cream right half for the product.`);

  const secciones = [
    'Create a premium commercial restaurant advertising flyer for a modern Mexican fast-food chain.',
    `FORMAT:\nA ${DESCRIPCION_FORMATO[a.formato]}.`,
    'IMPORTANT:\nThis is a GRAPHIC DESIGN composition first and a food photograph second.\n' +
      'The design must feel like a professionally art-directed campaign from a large established restaurant brand, NOT like an AI-generated food poster.',
    cartel
      ? 'LAYOUT:\nCreate a clean horizontal advertising banner with a strict 50/50 split background.'
      : 'LAYOUT:\nCreate a clean vertical advertising poster with a strict 50/50 split background.',
    (cartel ? 'LEFT HALF:\n' : 'TOP HALF:\n') + (color ? `Solid ${color} background (use exactly this color).` : 'Solid vivid red background.'),
    (cartel ? 'RIGHT HALF:\n' : 'BOTTOM HALF:\n') + 'Solid very light warm cream background.',
    `The separation between the two colors must be one smooth, gentle wave that runs across the full ${cartel ? 'height of the banner' : 'width of the poster'}.\n` +
      'The wave must be clean and simple, with crisp solid edges.\nNO zigzag.\nNO multiple or stacked waves.\nNO gradient.\nNO texture.\n' +
      'NO decorative background pattern.',
    'HERO PRODUCT:\n' + heroe,
    'The product should look premium and extremely appetizing.\n\n' +
      'Keep the food photography highly realistic and detailed, but cleanly isolated from the background.',
    'GRAPHIC DESIGN STYLE:\nMinimal, bold, modern commercial fast-food advertising.',
    'Think sophisticated retail advertising rather than a traditional Mexican poster.',
    'Use strong visual hierarchy, generous negative space, clean alignment, simple geometric composition, and confident typography.',
    'TYPOGRAPHY:\nUse a bold modern condensed sans-serif typeface similar to contemporary fast-food advertising.',
    'Typography should be:\nclean, bold, highly legible, modern, compact, commercial and premium.',
    'DO NOT use:\n- distressed typography\n- grunge typography\n- hand-painted lettering\n- brush lettering\n- western fonts\n- vintage fonts\n' +
      '- decorative fonts\n- cartoon lettering\n- excessive outlines\n- fake 3D text\n- textured lettering',
    'The typography must look like professionally typeset brand advertising.',
    'CONTENT:',
    ...contenido,
    'TEXT HIERARCHY:\n' + jerarquia.join('\n\n'),
    'COLOR DIRECTION:\n' + direccionDelColor(color),
    'IMPORTANT:\nDo not add decorative brush strokes, paint splashes, grunge textures, ribbons, badges, stars, flames, random icons, unnecessary shapes, or extra visual elements.',
    'Do not make the design overly busy.',
    'The final composition should feel intentionally simple, premium, highly commercial, and suitable for a major restaurant chain campaign.',
    extras.length
      ? `The "${nombreProducto}" must remain the visual centerpiece; the accompanying products only complement it. Do not write the names of the accompanying products.`
      : `The "${nombreProducto}" must remain the visual centerpiece.`,
    'Do not invent additional text, prices, promotions, logos, addresses, phone numbers, or claims.',
    'Respect every provided business text exactly as written.',
  ];
  return secciones.join('\n\n');
}

function direccionDelColor(color: string | null): string {
  if (!color) {
    // El rojo de siempre: el texto probado, sin tocar.
    return (
      'Use the red background as the main brand color.\n' +
      'Use the cream background as the contrasting secondary color.\n' +
      'Use black, dark brown, and white typography where appropriate for maximum readability.'
    );
  }
  const lineas = [
    `Use the ${color} background as the main brand color. Do not use red anywhere: ${color} replaces it.`,
    `Use ${color} for the price text, the promotion card and the call-to-action button (every accent element).`,
    'Use the cream background as the contrasting secondary color.',
  ];
  if (esClaro(color)) lineas.push(`${color} is a light color: any text placed on ${color} must be black or dark brown, never white.`);
  lineas.push('Use black, dark brown, and white typography where appropriate for maximum readability.');
  return lineas.join('\n');
}
