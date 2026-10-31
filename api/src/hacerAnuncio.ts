// El trabajo en segundo plano que hace un anuncio (worker-7b1.md, 7 a 11): un Workflow de Cloudflare,
// así el anuncio se termina aunque Don Chuy cierre la ventana. Tres pasos:
//  - «datos»: datos_del_anuncio; si ya no está «haciendo» (pasaron los 15 minutos), termina sin
//    llamar a OpenAI.
//  - «imagen», sin reintentos (cada intento a OpenAI puede cobrar): baja las fotos de R2, arma el
//    prompt de su estilo, llama a OpenAI, guarda el JPG en la biblioteca del restaurante y regresa
//    su ruta y los tokens. Nunca lanza: lo que falle vuelve como «rechazado» o «no_salio».
//  - «terminar»: terminar_anuncio, o fallar_anuncio si no salió. Este sí se reintenta, porque
//    Postgres no cuenta dos veces. Si terminar_anuncio dice que llegó tarde, borra el JPG.
import { WorkflowEntrypoint } from 'cloudflare:workers';
import type { WorkflowEvent, WorkflowStep } from 'cloudflare:workers';
import type { Formato, Producto, RestauranteDelAnuncio } from './anuncios/comun';
import { ESTILOS } from './anuncios/estilos';
import { nombreAlAzar } from './fotos';
import type { Env } from './index';
import { imagenDelAnuncio, modeloImagen, SIN_TOKENS_IMAGEN } from './openai';
import type { Foto, TokensImagen } from './openai';
import { llamar } from './supabase';

export type Parametros = { anuncio: number };

// Lo que regresa datos_del_anuncio: los productos con el nombre que se guardó y, si siguen en Mi
// menú, su descripción, su foto y su precio de hoy.
type DatosDelAnuncio = {
  id: number;
  restaurante_id: string;
  estado: string;
  estilo: string;
  formato: Formato;
  productos: { id: number; nombre: string; descripcion?: string | null; imagen_ruta?: string | null; precio_escrito?: string | null }[];
  mensaje: string | null;
  color: string | null;
  palabras: Record<string, string> | null;
  restaurante: RestauranteDelAnuncio;
};

type Imagen =
  | { ok: true; ruta: string; modelo: string; tokens: TokensImagen }
  | { ok: false; motivo: 'rechazado' | 'no_salio'; modelo: string; tokens: TokensImagen };

const TAMANOS: Record<Formato, string> = { post: '1152x1440', historia: '1152x2048', cartel: '2048x1152' };
const ETIQUETA = '[anuncios]';

export class HacerAnuncio extends WorkflowEntrypoint<Env, Parametros> {
  async run(evento: Readonly<WorkflowEvent<Parametros>>, paso: WorkflowStep): Promise<void> {
    const id = evento.payload.anuncio;
    const datos = await paso.do('datos', async () => llamar<DatosDelAnuncio>(this.env, 'worker', 'datos_del_anuncio', { p_anuncio_id: id }));
    if (datos.estado !== 'haciendo') {
      console.warn(ETIQUETA, 'el anuncio ya no estaba haciéndose: no se llamó a OpenAI', id, datos.estado);
      return;
    }

    let imagen: Imagen;
    try {
      imagen = await paso.do('imagen', { retries: { limit: 0, delay: '1 second' }, timeout: '12 minutes' }, async () => hacerImagen(this.env, datos));
    } catch (e) {
      console.error(ETIQUETA, 'el paso de la imagen se cayó', id, e);
      imagen = { ok: false, motivo: 'no_salio', modelo: modeloImagen(this.env), tokens: SIN_TOKENS_IMAGEN };
    }

    await paso.do('terminar', async () => terminar(this.env, id, imagen));
  }
}

async function hacerImagen(env: Env, datos: DatosDelAnuncio): Promise<Imagen> {
  const modelo = modeloImagen(env);
  const noSalio = (tokens = SIN_TOKENS_IMAGEN): Imagen => ({ ok: false, motivo: 'no_salio', modelo, tokens });
  const estilo = ESTILOS.get(datos.estilo);
  if (!estilo) {
    console.error(ETIQUETA, 'el estilo del anuncio no tiene su prompt en el Worker', datos.id, datos.estilo);
    return noSalio();
  }

  // Las fotos en el orden de sus productos. Si la de uno no está en R2 no sale: dibujar otro
  // platillo en lugar del suyo sería peor.
  const fotos: Foto[] = [];
  const productos: Producto[] = [];
  for (const p of datos.productos) {
    let referencia: number | null = null;
    if (p.imagen_ruta) {
      const objeto = await env.BUCKET.get(p.imagen_ruta);
      if (!objeto) {
        console.error(ETIQUETA, 'la foto de un producto no está en R2', datos.id, p.imagen_ruta);
        return noSalio();
      }
      const tipo = objeto.httpMetadata?.contentType ?? 'image/webp';
      fotos.push({ nombre: `producto-${fotos.length + 1}.${tipo === 'image/jpeg' ? 'jpg' : tipo === 'image/png' ? 'png' : 'webp'}`, tipo, bytes: await objeto.arrayBuffer() });
      referencia = fotos.length;
    }
    productos.push({ nombre: p.nombre, descripcion: p.descripcion ?? null, precio: p.precio_escrito ?? null, referencia });
  }

  const prompt = estilo.prompt({
    formato: datos.formato,
    productos,
    mensaje: datos.mensaje,
    color: datos.color,
    palabras: datos.palabras ?? {},
    restaurante: datos.restaurante,
  });
  const hecha = await imagenDelAnuncio(env, { prompt, fotos, tamano: TAMANOS[datos.formato], usuario: await conHash(datos.restaurante_id) });
  if (!hecha.ok) return { ...hecha, modelo };

  const ruta = `restaurantes/${datos.restaurante_id}/biblioteca/${nombreAlAzar()}.jpg`;
  try {
    await env.BUCKET.put(ruta, hecha.jpg, {
      // El nombre nunca se repite, así que el archivo nunca cambia: se puede guardar en caché un año.
      httpMetadata: { contentType: 'image/jpeg', cacheControl: 'public, max-age=31536000, immutable' },
    });
  } catch (e) {
    console.error(ETIQUETA, 'R2 no guardó el anuncio', datos.id, e);
    return noSalio(hecha.tokens);
  }
  console.log(ETIQUETA, 'imagen guardada', datos.id, ruta, hecha.jpg.byteLength, JSON.stringify(hecha.tokens));
  return { ok: true, ruta, modelo, tokens: hecha.tokens };
}

async function terminar(env: Env, id: number, imagen: Imagen): Promise<void> {
  const tokens = { p_modelo: imagen.modelo, p_entrada_texto: imagen.tokens.texto, p_entrada_imagen: imagen.tokens.imagen, p_salida: imagen.tokens.salida };
  if (!imagen.ok) {
    const r = await llamar<{ costo: unknown }>(env, 'worker', 'fallar_anuncio', { p_anuncio_id: id, p_motivo: imagen.motivo, ...tokens });
    console.warn(ETIQUETA, 'no salió', id, imagen.motivo, 'costo', r.costo, JSON.stringify(imagen.tokens));
    return;
  }
  const r = await llamar<{ ok: boolean; costo: unknown }>(env, 'worker', 'terminar_anuncio', { p_anuncio_id: id, p_ruta: imagen.ruta, ...tokens });
  if (r.ok) {
    console.log(ETIQUETA, 'listo', id, 'costo', r.costo, JSON.stringify(imagen.tokens));
    return;
  }
  // Llegó tarde: ya contaba como que no salió. Su costo quedó anotado; el archivo sobra.
  console.warn(ETIQUETA, 'llegó tarde: se borra el JPG', id, imagen.ruta, 'costo', r.costo);
  await env.BUCKET.delete(imagen.ruta);
}

// El restaurante con hash, para el `user` de OpenAI.
async function conHash(restaurante: string): Promise<string> {
  const huella = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`fragmentless:${restaurante}`));
  return Array.from(new Uint8Array(huella), (b) => b.toString(16).padStart(2, '0')).join('');
}
