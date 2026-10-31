// Lo que comparten los prompts de los 24 estilos (libreta 7; decisiones en planes/trabajo/7b/worker-7b1.md):
// cómo se ve un estilo desde fuera (sus reglas), los datos que van, las mayúsculas, el lienzo de cada
// formato, el color de la marca y el bloque del producto y la fotografía de los estilos 7 a 24.
// Los prompts van en inglés, como los que se probaron; lo que se escribe en el anuncio va en español.

export type Formato = 'post' | 'historia' | 'cartel';
export const FORMATOS: readonly Formato[] = ['post', 'historia', 'cartel'];

// Los datos del restaurante que lleva un estilo en cada formato, para «Irá en el anuncio».
export type Dato = 'nombre' | 'telefono' | 'direccion' | 'horario' | 'precio' | 'ordena';

// El restaurante como lo escribe Postgres (privado.restaurante_del_anuncio): el teléfono ya
// escrito («551 234 5678») y el horario de Cuadros en uno o dos renglones. Un dato vacío va null.
export type RestauranteDelAnuncio = {
  nombre: string;
  telefono: string | null;
  direccion: string | null;
  color: string | null;
  horario: string[] | null;
};

// Un producto ya listo para el prompt: su nombre, su descripción de Mi menú (solo para dibujarlo),
// su precio como va en el anuncio y el número de su foto entre las imágenes de referencia (null =
// la IA lo dibuja). Uno que ya no está en Mi menú va solo con su nombre.
export type Producto = {
  nombre: string;
  descripcion: string | null;
  precio: string | null;
  referencia: number | null;
};

export type Anuncio = {
  formato: Formato;
  productos: Producto[];
  mensaje: string | null;
  color: string | null;
  palabras: Record<string, string>;
  restaurante: RestauranteDelAnuncio;
};

// Un lugar del paso de texto: lo que escoge gpt-5.6-luna antes de la imagen y Don Chuy puede cambiar.
//  - cuando: siempre, uno por producto (banderita_1, banderita_2…) o solo con un producto.
//  - forma: lo que debe cumplir además del tope («PAS / TOR», «ESTO NO ES / UN TACO»).
//  - vacio: lo que sale con el mensaje vacío (Menú de café): se ve en gris, sin «Cambiar».
export type Lugar = {
  clave: string;
  nombre: string;
  tope: number;
  mayusculas: boolean;
  cuando: 'siempre' | 'por_producto' | 'con_uno';
  pide: string;
  forma?: { regla: RegExp; explica: string };
  vacio?: true;
};

// Un estilo: sus reglas (las de la tabla de worker-7b1.md) y su prompt. «vacio» es lo que sale con
// el mensaje vacío: un texto fijo, «#desc» (la descripción de Mi menú), «#nombre» (el nombre del
// producto), «#horario» (el de «Tu restaurante»), «#y» (las palabras gigantes del paso de texto) o
// null (no sale nada).
export type Estilo = {
  clave: string;
  maximo: number;
  minimo: number;
  mensaje: number;
  mayusculas: boolean;
  conColor: boolean;
  vacio: string | null;
  datos: Record<Formato, Dato[]>;
  lugares: Lugar[];
  prompt: (anuncio: Anuncio) => string;
};

// Los lugares del paso de texto de un estilo con tantos productos: los de «uno por producto» se
// repiten con su número y los de «con uno» solo salen con un producto.
export type LugarListo = Lugar & { llave: string; producto: number | null };

export function lugaresDe(estilo: Estilo, productos: number): LugarListo[] {
  return estilo.lugares.flatMap((lugar): LugarListo[] => {
    if (lugar.cuando === 'con_uno') return productos === 1 ? [{ ...lugar, llave: lugar.clave, producto: null }] : [];
    if (lugar.cuando === 'siempre') return [{ ...lugar, llave: lugar.clave, producto: null }];
    return Array.from({ length: productos }, (_, i) => ({ ...lugar, llave: `${lugar.clave}_${i + 1}`, producto: i + 1 }));
  });
}

// ─── Las letras ───────────────────────────────────────────────────────────────

// En mayúsculas, como la regla de Flet (str.upper): «Agua de jamaica» → «AGUA DE JAMAICA».
export function mayus(texto: string): string {
  return texto.toUpperCase();
}

// Un texto ya en mayúsculas: lo que dice igual a sí mismo en mayúsculas.
export function enMayusculas(texto: string): boolean {
  return texto === mayus(texto);
}

// ─── El lienzo ────────────────────────────────────────────────────────────────

// Cómo se nombra el anuncio en el primer renglón de cada prompt.
export const QUE_ES: Record<Formato, string> = {
  post: 'vertical 4:5 Instagram food advertisement',
  historia: 'vertical 9:16 Instagram story food advertisement',
  cartel: 'horizontal 16:9 menu banner food advertisement',
};

// El primer renglón de la sección del lienzo. En la historia, los porcentajes del prompt cuentan
// dentro de la zona segura (del 13 % al 82 % de la altura) y el fondo llega a las orillas.
export function lienzo(formato: Formato): string {
  if (formato === 'post') return 'Vertical 4:5 format, designed for a 1152 × 1440 image.';
  if (formato === 'cartel') return 'Horizontal 16:9 format, designed for a 2048 × 1152 menu banner, seen about 460 pixels wide on a phone.';
  return [
    'Vertical 9:16 format, designed for a 1152 × 2048 Instagram story image.',
    'Instagram covers the top 13% and the bottom 18% of a story: keep every text and every product inside the safe zone, from 13% to 82% of the height.',
    'Every height percentage in this prompt counts inside that safe zone, not on the full image.',
    'The background and the set still reach every edge of the image, above and below the safe zone.',
  ].join('\n');
}

// Los datos chiquitos de abajo del cartel: el teléfono y la dirección que haya, cada uno entre
// comillas, como van. Null si no hay ninguno.
export function contactoDelCartel(r: RestauranteDelAnuncio, enMayus: boolean): string | null {
  const datos = [r.telefono, r.direccion].filter((d): d is string => !!d);
  if (!datos.length) return null;
  return datos.map((d) => `"${enMayus ? mayus(d) : d}"`).join(' and ');
}

// ─── El color de la marca ─────────────────────────────────────────────────────

// Luminancia relativa (WCAG) de «#RRGGBB»: 0 negro, 1 blanco. La misma cuenta que Flet.
export function luminancia(hex: string): number {
  const valor = parseInt(hex.slice(1), 16);
  const canal = (c: number) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const [r, g, b] = [16, 8, 0].map((corrimiento) => canal(((valor >> corrimiento) & 255) / 255));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// Sobre un color así el texto blanco no se lee: las letras encima van oscuras (es_claro de Flet).
export function esClaro(hex: string): boolean {
  return luminancia(hex) > 0.45;
}

type Hsl = { h: number; s: number; l: number };

function aHsl(hex: string): Hsl {
  const valor = parseInt(hex.slice(1), 16);
  const [r, g, b] = [16, 8, 0].map((c) => ((valor >> c) & 255) / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return { h: 0, s: 0, l };
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: h * 60, s, l };
}

function deHsl({ h, s, l }: Hsl): string {
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const canal = (t: number) => {
    const x = (t + 1) % 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  };
  const rgb = s === 0 ? [l, l, l] : [canal(h / 360 + 1 / 3), canal(h / 360), canal(h / 360 - 1 / 3)];
  return '#' + rgb.map((c) => Math.round(c * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
}

// Los tonos del estilo girados al color de la marca con la misma luz, como en la prueba de la mesa
// en azul: cada tono toma el matiz de la marca y conserva su luminosidad. Su saturación baja con la
// de la marca (una marca gris o negra da tonos grises), comparada con la del tono principal del
// estilo (el primero).
export function pintar<T extends Record<string, string>>(color: string | null, tonos: T): T {
  if (!color) return tonos;
  const marca = aHsl(color);
  const principal = aHsl(Object.values(tonos)[0]);
  const factor = principal.s > 0 ? Math.min(1, marca.s / principal.s) : 0;
  const girados = Object.entries(tonos).map(([nombre, tono]) => {
    const t = aHsl(tono);
    return [nombre, deHsl({ h: marca.h, s: t.s * factor, l: t.l })];
  });
  return Object.fromEntries(girados) as T;
}

// El nombre del color de la marca en inglés, para las palabras del prompt («red tiles» → «blue
// tiles»). Una marca casi sin saturación es gris.
export function nombreDelColor(hex: string): string {
  const { h, s } = aHsl(hex);
  if (s < 0.12) return 'gray';
  const nombres: [number, string][] = [
    [12, 'red'], [40, 'orange'], [66, 'yellow'], [160, 'green'], [195, 'teal'],
    [255, 'blue'], [290, 'purple'], [335, 'magenta'], [360, 'red'],
  ];
  return nombres.find(([hasta]) => h < hasta)![1];
}

// La letra sobre un tono del estilo: la suya (casi siempre blanca), u oscura si el tono salió claro
// (es_claro). Sin color los tonos son los de la referencia y la letra queda como en la muestra.
export function letraSobre(tono: string, suya = 'white'): string {
  return esClaro(tono) ? 'very dark brown' : suya;
}

// El contraste WCAG entre dos tonos: de 1 (iguales) a 21 (negro sobre blanco).
export function contraste(a: string, b: string): number {
  const [claro, oscuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (oscuro + 0.05);
}

// Una letra de la marca sobre un fondo que se queda (el marfil, el crema): si el tono girado salió tan
// claro que no se lee, se oscurece con su mismo matiz hasta el contraste de un titular (3 a 1). Los
// tonos de las referencias ya lo cumplen, así que sin color nada cambia.
export function legibleSobre(tono: string, fondo: string): string {
  const hsl = aHsl(tono);
  let resultado = tono;
  while (contraste(resultado, fondo) < 3 && hsl.l > 0) {
    hsl.l = Math.max(0, hsl.l - 0.02);
    resultado = deHsl(hsl);
  }
  return resultado;
}

// «Red» → «Red-and-cream», para el principio de un renglón.
export function cap(texto: string): string {
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

// Con color, la luz sobre la comida sigue cálida: con luz del color de la marca se ve fría.
export function luzCalida(color: string | null, pintado: string): string[] {
  if (!color) return [];
  const nombre = nombreDelColor(color);
  return [`The light is a warm, neutral white: the food keeps its natural warm colors and is never tinted ${nombre}; the ${nombre} color is only for ${pintado}.`];
}

// ─── El producto y la fotografía (estilos 7 a 24, y los productos de los 2 a 6) ─

// Cómo es el producto de Don Chuy: con foto, el de su imagen de referencia; sin foto, la IA lo
// dibuja con su nombre y su descripción, que solo sirve para dibujarlo.
export function comoEs(p: Producto): string {
  if (p.referencia !== null) {
    return `the product shown in reference image ${p.referencia}, "${p.nombre}": the same dish, with the same ingredients, the same shape, and the same presentation as in its reference image. Do not replace it with a different dish.`;
  }
  const descripcion = p.descripcion ? ` It is described on the menu as "${p.descripcion}"; this description is only to draw it, never write it.` : '';
  return `"${p.nombre}", drawn as the real dish a Mexican restaurant serves under that name.${descripcion}`;
}

// Lo que se aprendió en los estilos 7 a 21 y vale para cualquier producto. Lo del taco va como «si
// es un taco»: con la foto de Don Chuy manda su foto. La cebolla ya no se pide por tamaño.
export const AUTENTICO: readonly string[] = [
  'Every product must look freshly prepared in a real Mexican restaurant.',
  'Allow small imperfections in the food.',
  'Every product should look genuinely edible and professionally photographed.',
  'If a product is a taco, unless its reference image shows it otherwise: one thin, soft, slightly irregular tortilla, folded into a soft, natural U shape around the filling, standing upright on its folded edge; a real street-size taco, about the size of a palm.',
  'Do not create a thick, rigid, crunchy, or perfectly symmetrical taco shell, a taco split into halves, or a taco laid open and flat like a tostada.',
];

// Con menos productos de los que dibuja el estilo, van solo los suyos, más grandes: nunca se
// repiten ni se inventa otra comida.
export const SOLO_LOS_SUYOS = 'Show only these products, each one once. Do not add any other food or drink, and do not repeat a product to fill space.';

// La sección de la fotografía: lo de siempre, con la cámara y la luz de cada estilo en medio.
export function fotografia(numero: number, escena: string[]): string {
  return [
    `${numero}. NATURAL COMMERCIAL FOOD PHOTOGRAPHY`,
    'Use believable professional food photography.',
    ...escena,
    'Preserve natural shadows and realistic textures.',
    'Cooked meat should look cooked and moist, not lacquered.',
    'Tortillas should remain mostly matte.',
    'Avoid excessive HDR, artificial sharpening, plastic surfaces, unrealistic reflections, or CGI-like food textures.',
    'Natural photographic authenticity is more important than visual perfection.',
  ].join('\n');
}

// «Uno, dos, tres…» para el prompt.
export const CUANTOS = ['zero', 'one', 'two', 'three', 'four', 'five'];
