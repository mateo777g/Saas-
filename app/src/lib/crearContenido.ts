// Lo que usa «Crear contenido» (parte 7b-1 de la libreta 7; maqueta JQBw2yGFSiky1x9twUyYbe, sus
// decisiones en planes/trabajo/7b/lista-7b.md y worker-7b1.md):
//  - crear_contenido: en una sola lectura, «Te quedan N de 20», si la IA puede, su restaurante como
//    va en el anuncio, sus productos de Mi menú y el resultado (el que se está haciendo o el último
//    suyo que todavía no ve). Se vuelve a leer cada vez que realtime avisa de un cambio en anuncios.
//  - el Worker, con la sesión: los estilos que le salen hoy con las reglas de su prompt
//    (GET /anuncios/estilos), el paso de texto (POST /anuncios/palabras), hacer el anuncio
//    (POST /anuncios) y el JPG para «Descargar» (GET /anuncios/archivo).
// Lo que dice «Irá en el anuncio» sale de esas reglas, las mismas con las que el Worker arma el
// prompt, así nunca dice otra cosa. Ningún número sale de aquí: los precios ya vienen escritos.
import type { EstadoIa } from './agente';
import { mensajeDeError } from './errores';
import { escuchar } from './pos';
import { supabase } from './supabase';
import { bajarDelWorker, llamarWorker } from './worker';

export type Formato = 'post' | 'historia' | 'cartel';
export const FORMATOS: { valor: Formato; texto: string; corto: string; medida: string; ancho: number; alto: number }[] = [
  // ancho y alto: el marco del resultado, con la forma del anuncio.
  { valor: 'post', texto: 'Post', corto: 'POST', medida: '1152 × 1440', ancho: 360, alto: 450 },
  { valor: 'historia', texto: 'Historia', corto: 'HISTORIA', medida: '1152 × 2048', ancho: 288, alto: 512 },
  { valor: 'cartel', texto: 'Cartel del menú', corto: 'CARTEL', medida: '2048 × 1152', ancho: 400, alto: 225 },
];
export function formatoDe(valor: Formato) {
  return FORMATOS.find((f) => f.valor === valor) ?? FORMATOS[0];
}

// Lo que cada estilo pone de su restaurante en cada formato (el código del prompt).
export type Dato = 'nombre' | 'telefono' | 'direccion' | 'horario' | 'precio' | 'ordena';

// Un lugar de las palabras del paso de texto: uno por anuncio, uno por producto o solo con un
// producto. `vacio`: lo que sale con el mensaje vacío (Menú de café), en gris y sin «Cambiar».
export type Lugar = {
  clave: string;
  nombre: string;
  tope: number;
  mayusculas: boolean;
  cuando: 'siempre' | 'por_producto' | 'con_uno';
  vacio?: true;
};

export type EstiloDeHoy = {
  id: number;
  clave: string;
  nombre: string;
  descripcion: string;
  grupo: 'temporada' | 'para_todos';
  muestras: Record<Formato, string>;
  maximo: number;
  minimo: number;
  // El tope de letras del mensaje; 0 = no lleva.
  mensaje: number;
  mayusculas: boolean;
  color: boolean;
  // Lo que sale con el mensaje vacío: un texto, «#desc», «#nombre», «#horario», «#y» o null.
  vacio: string | null;
  datos: Record<Formato, Dato[]>;
  lugares: Lugar[];
};

export type ProductoDelMenu = {
  id: number;
  nombre: string;
  descripcion: string | null;
  imagen_ruta: string | null;
  precio: number;
  // Como va en el anuncio («$75»), escrito por Postgres.
  precio_escrito: string;
};

export type RestauranteDelAnuncio = {
  nombre: string | null;
  telefono: string | null;
  direccion: string | null;
  color: string | null;
  horario: string | null;
};

export type Resultado = {
  id: number;
  estado: 'haciendo' | 'listo' | 'fallo';
  motivo: 'rechazado' | 'no_salio' | null;
  estilo_id: number;
  formato: Formato;
  productos: { id: number; nombre: string }[];
  mensaje: string | null;
  color: string | null;
  palabras: Record<string, string> | null;
  ruta: string | null;
  // Cuántos segundos lleva desde que empezó, con el reloj de Postgres.
  segundos: number;
};

export type DatosCrearContenido = {
  de: number;
  quedan: number;
  // El día en que vuelven los 20 ('2026-11-01').
  vuelve: string;
  ia: EstadoIa;
  restaurante: RestauranteDelAnuncio;
  productos: ProductoDelMenu[];
  resultado: Resultado | null;
};

// Lo que contestan el paso de texto y hacer el anuncio cuando no se puede.
export type NoSePuede = {
  ok: false;
  motivo: 'sin_ia' | 'limite' | 'veinte' | 'estilo' | 'haciendo';
  con_distribuidor?: boolean;
  vuelve?: string | null;
};

export async function leerCrearContenido(restauranteId: string): Promise<DatosCrearContenido> {
  const { data, error } = await supabase.rpc('crear_contenido', { p_restaurante_id: restauranteId });
  if (error) {
    console.error('[crear contenido] no se pudo leer:', error);
    throw error;
  }
  return data as DatosCrearContenido;
}

export async function leerEstilosDeHoy(restauranteId: string): Promise<EstiloDeHoy[]> {
  const r = await llamarWorker('anuncios', 'GET', `/anuncios/estilos?restaurante=${restauranteId}`);
  return (r?.estilos ?? []) as EstiloDeHoy[];
}

export async function pedirPalabras(
  restauranteId: string,
  estiloId: number,
  productos: number[],
): Promise<{ ok: true; palabras: Record<string, string> } | NoSePuede> {
  const r = await llamarWorker('anuncios', 'POST', '/anuncios/palabras', { restaurante: restauranteId, estilo_id: estiloId, productos });
  return r as { ok: true; palabras: Record<string, string> } | NoSePuede;
}

export type Pedido = {
  estiloId: number;
  formato: Formato;
  productos: number[];
  mensaje: string;
  // Solo el color que eligió para este anuncio; sin elegir, el Worker pone el de su marca.
  color: string | null;
  palabras: Record<string, string>;
};

export async function hacerAnuncio(restauranteId: string, p: Pedido): Promise<{ ok: true; anuncio_id: number } | NoSePuede> {
  const r = await llamarWorker('anuncios', 'POST', '/anuncios', {
    restaurante: restauranteId,
    estilo_id: p.estiloId,
    formato: p.formato,
    productos: p.productos,
    mensaje: p.mensaje || null,
    color: p.color,
    palabras: p.palabras,
  });
  return r as { ok: true; anuncio_id: number } | NoSePuede;
}

// La app lo marca en cuanto lo enseña terminado; si falla, solo queda en la consola: el anuncio ya
// se vio y lo peor es que salga otra vez al volver.
export async function anuncioVisto(id: number): Promise<void> {
  const { error } = await supabase.rpc('anuncio_visto', { p_anuncio_id: id });
  if (error) console.error('[crear contenido] no se pudo marcar el anuncio como visto:', id, mensajeDeError(error), error);
}

// «Descargar»: el JPG con el nombre que le pone el Worker.
export async function descargarAnuncio(id: number): Promise<void> {
  const { archivo, nombre } = await bajarDelWorker('anuncios', `/anuncios/archivo?id=${id}`);
  const enlace = document.createElement('a');
  enlace.href = URL.createObjectURL(archivo);
  enlace.download = nombre ?? 'anuncio.jpg';
  enlace.click();
  setTimeout(() => URL.revokeObjectURL(enlace.href), 10_000);
}

export function escucharAnuncios(restauranteId: string, alCambiar: () => void): () => void {
  return escuchar(supabase, restauranteId, ['anuncios'], alCambiar);
}

// ─── Las reglas del estilo, como las usa el Worker ───────────────────────────────────────────

// Un lugar ya puesto en un anuncio: su llave en las palabras («banderita_2») y, si es de un
// producto, cuál (1 a 5). Igual que lugaresDe del Worker (api/src/anuncios/comun.ts).
export type LugarListo = Lugar & { llave: string; producto: number | null };
export function lugaresDe(estilo: EstiloDeHoy, productos: number): LugarListo[] {
  return estilo.lugares.flatMap((lugar): LugarListo[] => {
    if (lugar.cuando === 'con_uno') return productos === 1 ? [{ ...lugar, llave: lugar.clave, producto: null }] : [];
    if (lugar.cuando === 'siempre') return [{ ...lugar, llave: lugar.clave, producto: null }];
    return Array.from({ length: productos }, (_, i) => ({ ...lugar, llave: `${lugar.clave}_${i + 1}`, producto: i + 1 }));
  });
}

// Lo que sale con el mensaje vacío, ya con sus datos; null si no sale nada.
export function vacioDe(
  estilo: EstiloDeHoy,
  van: ProductoDelMenu[],
  restaurante: RestauranteDelAnuncio,
  palabras: Record<string, string> | null,
): string | null {
  const p1 = van[0];
  switch (estilo.vacio) {
    case null:
      return null;
    case '#desc':
      return p1?.descripcion || null;
    case '#nombre':
      return p1?.nombre ?? null;
    case '#horario':
      return restaurante.horario;
    case '#y': {
      const lugar = lugaresDe(estilo, van.length).find((l) => l.vacio);
      return (lugar && palabras?.[lugar.llave]) || null;
    }
    default:
      return estilo.vacio;
  }
}

// La pista de la cajita del mensaje: lo que sale si la deja vacía.
export function pistaDe(estilo: EstiloDeHoy): string {
  switch (estilo.vacio) {
    case null:
      return estilo.clave === 'clasico' ? 'Ej. 2x1 los martes. Vacío, no sale promoción.' : 'Vacío, no sale.';
    case '#desc':
      return 'Vacío, sale la descripción de tu producto.';
    case '#nombre':
      return 'Vacío, sale el nombre de tu producto.';
    case '#horario':
      return 'Vacío, sale tu horario.';
    case '#y':
      return 'Vacío, salen tus dos primeros productos unidos con Y.';
    default:
      return `Vacío, sale ${estilo.vacio}`;
  }
}

// Los datos de su restaurante que van en este estilo y formato, en su orden; los vacíos no van.
// El precio: con un producto, el suyo; con varios, el de cada uno, salvo en el Clásico, que con
// varios no lleva precio del menú (como en Flet).
export function datosQueVan(
  estilo: EstiloDeHoy,
  formato: Formato,
  restaurante: RestauranteDelAnuncio,
  van: ProductoDelMenu[],
): string[] {
  return estilo.datos[formato].flatMap((dato): string[] => {
    switch (dato) {
      case 'nombre':
        return restaurante.nombre ? [restaurante.nombre] : [];
      case 'telefono':
        return restaurante.telefono ? [restaurante.telefono] : [];
      case 'direccion':
        return restaurante.direccion ? [restaurante.direccion] : [];
      case 'horario':
        return restaurante.horario ? [restaurante.horario] : [];
      case 'precio':
        if (van.length === 1) return [van[0].precio_escrito];
        return estilo.clave === 'clasico' ? [] : van.map((p) => p.precio_escrito);
      case 'ordena':
        return ['ORDENA AHORA'];
    }
  });
}

// Cuántos productos lleva, como lo dice la ventana de estilos.
export function cuantosLleva(estilo: EstiloDeHoy): string {
  if (estilo.minimo > 1) return `${estilo.minimo} o ${estilo.maximo} productos`;
  return estilo.maximo === 1 ? '1 producto' : `Hasta ${estilo.maximo} productos`;
}

// Lo que pinta el color en cada estilo (libreta 7, la tabla «Los estilos»). Solo se enseña: el
// prompt de cada estilo es el que lo pinta.
const PINTA: Record<string, string> = {
  clasico: 'la mitad de arriba, el precio, la promoción y el botón; el crema se queda',
  'letra-gigante': 'la letra gigante; el marfil se queda',
  anatomia: 'el fondo',
  explosion: 'el fondo',
  promo: 'el fondo',
  minimalista: 'el estudio (pared y piso)',
  estrella: 'la estrella, la marca y las pastillas; el durazno se queda',
  mano: 'la palabra repetida; el crema se queda',
  estrellas: 'el fondo; lo blanco se queda',
  'palabra-repetida': 'las letras; el crema se queda',
  reflector: 'el cuarto y la mesa',
  diagonal: 'la parte de arriba, la insignia y los textos rojos; el crema se queda',
  'combo-en-mano': 'las letras gigantes; la insignia negra se queda',
  banderitas: 'el azulejo y las banderitas',
  barda: 'la barda y el cielo; las flechas y la etiqueta siguen amarillas',
  cuadros: 'la palabra gigante, los cuadros y el recuadro',
  desayunos: 'el fondo, el recuadro y las letras',
  'menu-de-cafe': 'el fondo (las letras se oscurecen o aclaran con él)',
  'palabra-vertical': 'el panel de la izquierda; el crema se queda',
  ranura: 'la superficie',
};
export function loQuePinta(estilo: EstiloDeHoy): string | null {
  return PINTA[estilo.clave] ?? null;
}

// «Banderitas, sin acentos» → para buscar en su menú como en Flet.
export function sinAcentos(texto: string): string {
  return texto.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}
