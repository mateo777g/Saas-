// Las fotos del menú, el logo y los carteles. El navegador las achica y las convierte a WebP (las
// fotos a 1600 px de lado mayor, calidad 80, como Flet en models/cloudflare_storage.py; el logo a
// 512 px con su transparencia; el cartel a 1600 × 900, calidad 90), y el Worker api-pruebas las guarda en R2
// o las borra, después de preguntarle a Postgres con la sesión de quien llama (libreta 3, «Las
// fotos en R2»). La app nunca escribe en R2 directo: solo guarda la ruta que le da el Worker.
import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from './errores';
import { llamarWorker } from './worker';

const R2_PUBLICO = import.meta.env.VITE_R2_PUBLICO;
if (!R2_PUBLICO) throw new Error('Falta VITE_R2_PUBLICO en app/.env');

const LADO_MAXIMO = 1600;
const CALIDAD = 80;
// El logo: chico (va en una barra de 48 px) y más nítido, porque casi siempre trae letras.
const LADO_LOGO = 512;
const CALIDAD_LOGO = 90;
// El cartel: 16:9, como lo pinta el menú. Calidad 90 porque a 80 el desenfoque de los lados sale con
// escalones (decidido el 24 de octubre de 2026).
const ANCHO_CARTEL = 1600;
const ALTO_CARTEL = 900;
const CALIDAD_CARTEL = 90;

// Las carpetas de un restaurante en R2 (las mismas que acepta el Worker).
export type Carpeta = 'menu' | 'logo' | 'carteles';
const MAXIMO_ORIGINAL = 15 * 1024 * 1024;

// La dirección pública de una foto (la del bucket; libreta 3: el Worker no sirve las fotos).
export function urlFoto(ruta: string): string {
  return `${R2_PUBLICO}/${ruta}`;
}

// Al elegir una foto: que no pese de más y que el navegador la pueda abrir. Regresa el error para
// la caja, o nada si está bien. Los textos son los de Flet (validar_y_comprimir).
export async function revisarFoto(archivo: File): Promise<string | null> {
  if (archivo.size > MAXIMO_ORIGINAL) {
    return 'La imagen pesa más de 15 MB. Elige una foto más ligera.';
  }
  try {
    const imagen = await createImageBitmap(archivo);
    imagen.close();
    return null;
  } catch (error) {
    console.error('[fotos] el navegador no pudo abrir la foto elegida:', error);
    return 'El archivo seleccionado no es una imagen válida.';
  }
}

// La foto lista para subir: WebP de 1600 px de lado mayor, calidad 80, derecha aunque el celular
// la haya guardado de lado (imageOrientation).
export async function convertirAWebp(archivo: File): Promise<Blob> {
  const imagen = await abrir(archivo);
  const { lienzo, pincel } = lienzoDe(imagen, LADO_MAXIMO);
  imagen.close();
  return aWebp(lienzo, pincel, CALIDAD);
}

// El logo listo para subir: WebP de 512 px de lado mayor que conserva su fondo transparente.
export async function convertirLogo(archivo: File): Promise<Blob> {
  const imagen = await abrir(archivo);
  const { lienzo, pincel } = lienzoDe(imagen, LADO_LOGO);
  imagen.close();
  return aWebp(lienzo, pincel, CALIDAD_LOGO);
}

// El cartel listo para subir: WebP de 1600 × 900. Si no viene en 16:9 (un flyer vertical de
// Instagram), sale entero, sin cortar nada, y lo que sobra a los lados se rellena con la misma
// imagen desenfocada (decidido el 20 de octubre de 2026).
export async function convertirCartel(archivo: File): Promise<Blob> {
  const imagen = await abrir(archivo);
  const lienzo = document.createElement('canvas');
  lienzo.width = ANCHO_CARTEL;
  lienzo.height = ALTO_CARTEL;
  const pincel = lienzo.getContext('2d');
  if (!pincel) throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  pincel.imageSmoothingQuality = 'high';

  if (Math.abs(imagen.width / imagen.height - ANCHO_CARTEL / ALTO_CARTEL) < 0.02) {
    pincel.drawImage(imagen, 0, 0, ANCHO_CARTEL, ALTO_CARTEL);
  } else {
    // El desenfoque: la imagen llenando el cuadro en 48 × 27 y estirada de vuelta al doble en cada
    // paso, para que la orilla salga lisa y no en escalones. Así funciona en todos los navegadores
    // (Safari no tiene ctx.filter).
    let chico = document.createElement('canvas');
    chico.width = 48;
    chico.height = 27;
    const pc = chico.getContext('2d');
    if (!pc) throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
    // Sin esto, al achicarla tanto, la orilla ya sale en escalones desde aquí.
    pc.imageSmoothingQuality = 'high';
    const llena = Math.max(48 / imagen.width, 27 / imagen.height);
    const al = imagen.width * llena;
    const bl = imagen.height * llena;
    pc.drawImage(imagen, (48 - al) / 2, (27 - bl) / 2, al, bl);
    while (chico.width * 2 < ANCHO_CARTEL) {
      const doble = document.createElement('canvas');
      doble.width = chico.width * 2;
      doble.height = chico.height * 2;
      const pd = doble.getContext('2d');
      if (!pd) throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
      pd.imageSmoothingQuality = 'high';
      pd.drawImage(chico, 0, 0, doble.width, doble.height);
      chico = doble;
    }
    pincel.drawImage(chico, 0, 0, ANCHO_CARTEL, ALTO_CARTEL);

    const cabe = Math.min(ANCHO_CARTEL / imagen.width, ALTO_CARTEL / imagen.height);
    const ancho = imagen.width * cabe;
    const alto = imagen.height * cabe;
    pincel.drawImage(imagen, (ANCHO_CARTEL - ancho) / 2, (ALTO_CARTEL - alto) / 2, ancho, alto);
  }
  imagen.close();
  return aWebp(lienzo, pincel, CALIDAD_CARTEL);
}

// La imagen derecha aunque el celular la haya guardado de lado (imageOrientation).
async function abrir(archivo: File): Promise<ImageBitmap> {
  try {
    return await createImageBitmap(archivo, { imageOrientation: 'from-image' });
  } catch (error) {
    console.error('[fotos] no se pudo abrir la foto para convertirla:', error);
    throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  }
}

// Un lienzo con la imagen achicada a ese lado mayor (nunca agrandada).
function lienzoDe(imagen: ImageBitmap, lado: number) {
  const escala = Math.min(1, lado / Math.max(imagen.width, imagen.height));
  const ancho = Math.max(1, Math.round(imagen.width * escala));
  const alto = Math.max(1, Math.round(imagen.height * escala));
  const lienzo = document.createElement('canvas');
  lienzo.width = ancho;
  lienzo.height = alto;
  const pincel = lienzo.getContext('2d');
  if (!pincel) throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  pincel.imageSmoothingQuality = 'high';
  pincel.drawImage(imagen, 0, 0, ancho, alto);
  return { lienzo, pincel };
}

async function aWebp(lienzo: HTMLCanvasElement, pincel: CanvasRenderingContext2D, calidad: number): Promise<Blob> {
  const foto = await new Promise<Blob | null>((listo) => lienzo.toBlob(listo, 'image/webp', calidad / 100));
  if (foto?.type === 'image/webp') return foto;
  // Safari (Mac, iPhone, iPad) no sabe hacer WebP y regresa un PNG sin avisar: entonces lo hace
  // el convertidor de respaldo (decidido el 13 de octubre de 2026).
  return webpDeRespaldo(pincel.getImageData(0, 0, lienzo.width, lienzo.height), calidad);
}

// El convertidor de respaldo: libwebp hecho para el navegador (@jsquash/webp, Apache-2.0). Solo se
// descarga la primera vez que hace falta.
export async function webpDeRespaldo(datos: ImageData, calidad = CALIDAD): Promise<Blob> {
  try {
    const { default: codificar } = await import('@jsquash/webp/encode.js');
    const bytes = await codificar(datos, { quality: calidad });
    return new Blob([bytes], { type: 'image/webp' });
  } catch (error) {
    console.error('[fotos] el convertidor de respaldo falló:', error);
    if (esDeRed(error)) throw new Fallo(SIN_CONEXION);
    throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  }
}

// Sube la imagen a una carpeta del restaurante y regresa su ruta en R2
// ('restaurantes/<id>/<carpeta>/<32 caracteres>.webp'), que es lo que se guarda en la base.
export async function subirFoto(restauranteId: string, foto: Blob, carpeta: Carpeta = 'menu'): Promise<string> {
  const respuesta = await llamarWorker(
    'fotos',
    'POST',
    `/menu/foto?restaurante=${encodeURIComponent(restauranteId)}&carpeta=${carpeta}`,
    foto,
  );
  if (typeof respuesta?.ruta !== 'string') {
    console.error('[fotos] el Worker no regresó la ruta:', respuesta);
    throw new Fallo(ALGO_SALIO_PANEL);
  }
  return respuesta.ruta;
}

// Borra una imagen que ya nada usa (la vieja al cambiarla, la de un producto eliminado, un cartel
// quitado o la de algo que no se pudo guardar). Si falla, el guardado ya salió bien: no se le muestra a Don
// Chuy, pero queda en la consola, nunca se traga.
export async function borrarFoto(ruta: string): Promise<void> {
  try {
    await llamarWorker('fotos', 'DELETE', `/menu/foto?ruta=${encodeURIComponent(ruta)}`);
  } catch (error) {
    console.error(`[fotos] no se pudo borrar la foto ${ruta}; queda en R2:`, error);
  }
}
