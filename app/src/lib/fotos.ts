// Las fotos del menú. El navegador las achica y las convierte a WebP (1600 px de lado mayor,
// calidad 80, como Flet en models/cloudflare_storage.py), y el Worker api-pruebas las guarda en
// R2 o las borra, después de preguntarle a Postgres con la sesión de quien llama (libreta 3, «Las
// fotos en R2»). La app nunca escribe en R2 directo: solo guarda la ruta que le da el Worker.
import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from './errores';
import { llamarWorker } from './worker';

const R2_PUBLICO = import.meta.env.VITE_R2_PUBLICO;
if (!R2_PUBLICO) throw new Error('Falta VITE_R2_PUBLICO en app/.env');

const LADO_MAXIMO = 1600;
const CALIDAD = 80;
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
  let imagen: ImageBitmap;
  try {
    imagen = await createImageBitmap(archivo, { imageOrientation: 'from-image' });
  } catch (error) {
    console.error('[fotos] no se pudo abrir la foto para convertirla:', error);
    throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  }
  const escala = Math.min(1, LADO_MAXIMO / Math.max(imagen.width, imagen.height));
  const ancho = Math.max(1, Math.round(imagen.width * escala));
  const alto = Math.max(1, Math.round(imagen.height * escala));
  const lienzo = document.createElement('canvas');
  lienzo.width = ancho;
  lienzo.height = alto;
  const pincel = lienzo.getContext('2d');
  if (!pincel) throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  pincel.imageSmoothingQuality = 'high';
  pincel.drawImage(imagen, 0, 0, ancho, alto);
  imagen.close();

  const foto = await new Promise<Blob | null>((listo) => lienzo.toBlob(listo, 'image/webp', CALIDAD / 100));
  if (foto?.type === 'image/webp') return foto;
  // Safari (Mac, iPhone, iPad) no sabe hacer WebP y regresa un PNG sin avisar: entonces lo hace
  // el convertidor de respaldo (decidido el 13 de octubre de 2026).
  return webpDeRespaldo(pincel.getImageData(0, 0, ancho, alto));
}

// El convertidor de respaldo: libwebp hecho para el navegador (@jsquash/webp, Apache-2.0). Solo se
// descarga la primera vez que hace falta.
export async function webpDeRespaldo(datos: ImageData): Promise<Blob> {
  try {
    const { default: codificar } = await import('@jsquash/webp/encode.js');
    const bytes = await codificar(datos, { quality: CALIDAD });
    return new Blob([bytes], { type: 'image/webp' });
  } catch (error) {
    console.error('[fotos] el convertidor de respaldo falló:', error);
    if (esDeRed(error)) throw new Fallo(SIN_CONEXION);
    throw new Fallo('No se pudo procesar la foto. Intenta con otra imagen.');
  }
}

// Sube la foto al menú del restaurante y regresa su ruta en R2
// ('restaurantes/<id>/menu/<32 caracteres>.webp'), que es lo que se guarda en el producto.
export async function subirFoto(restauranteId: string, foto: Blob): Promise<string> {
  const respuesta = await llamarWorker(
    'fotos',
    'POST',
    `/menu/foto?restaurante=${encodeURIComponent(restauranteId)}`,
    foto,
  );
  if (typeof respuesta?.ruta !== 'string') {
    console.error('[fotos] el Worker no regresó la ruta:', respuesta);
    throw new Fallo(ALGO_SALIO_PANEL);
  }
  return respuesta.ruta;
}

// Borra una foto que ya ningún producto usa (la vieja al cambiarla, la de un producto eliminado o
// la de uno que no se pudo guardar). Si falla, el guardado ya salió bien: no se le muestra a Don
// Chuy, pero queda en la consola, nunca se traga.
export async function borrarFoto(ruta: string): Promise<void> {
  try {
    await llamarWorker('fotos', 'DELETE', `/menu/foto?ruta=${encodeURIComponent(ruta)}`);
  } catch (error) {
    console.error(`[fotos] no se pudo borrar la foto ${ruta}; queda en R2:`, error);
  }
}
