// Crear contenido (libreta 7, parte 7b-1; sus decisiones en planes/trabajo/7b/worker-7b1.md). Cuatro
// trabajos, todos con la sesión de Don Chuy:
//  - GET /anuncios/estilos?restaurante=<id>: los estilos que le salen hoy (estilos_de_hoy) y que ya
//    tienen su prompt aquí, en su orden, cada uno con sus reglas del código.
//  - POST /anuncios/palabras {restaurante, estilo_id, productos}: el paso de texto, solo en los
//    estilos que lo llevan. Regresa {ok: true, palabras} o el mismo {ok: false, motivo} que apartar.
//  - POST /anuncios {restaurante, estilo_id, formato, productos, mensaje, color, palabras}: revisa
//    todo contra las reglas del estilo, aparta su lugar (apartar_anuncio), arranca el trabajo en
//    segundo plano (hacerAnuncio.ts) y regresa {ok: true, anuncio_id}.
//  - GET /anuncios/archivo?id=<id>: el JPG para «Descargar», con su nombre.
// El Worker no decide nada: Postgres dice si se puede, qué productos van y cuánto costó.
import { anotar } from './agente';
import { lugaresDe } from './anuncios/comun';
import type { Estilo, Formato, RestauranteDelAnuncio } from './anuncios/comun';
import { FORMATOS } from './anuncios/comun';
import { ESTILOS } from './anuncios/estilos';
import { esquemaDePalabras, preguntaDePalabras, REGLAS_PALABRAS, revisarPalabras } from './anuncios/palabras';
import { leerCuerpo } from './equipo';
import type { Env } from './index';
import { modeloImagen, modeloPalabras, palabrasDeLaIa } from './openai';
import { json, Rechazo } from './respuestas';
import { leerFilas, leerSesion, llamar } from './supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const COLOR = /^#[0-9A-Fa-f]{6}$/;
const NO_PREPARO = 'No pudimos preparar tu anuncio. Inténtalo otra vez.';
const NO_EMPEZO = 'No pudimos empezar tu anuncio. Inténtalo otra vez.';
const YA_NO_ESTA = 'Ese anuncio ya no está.';

type EstiloDeHoy = {
  id: number;
  clave: string;
  nombre: string;
  descripcion: string;
  grupo: string;
  muestra_post_ruta: string;
  muestra_historia_ruta: string;
  muestra_cartel_ruta: string;
};

// Lo que contestan datos_para_anuncio y apartar_anuncio cuando no se puede (sin_ia, limite, veinte,
// estilo, haciendo): pasa tal cual a la app.
type NoSePuede = { ok: false; motivo: string };
type Revision = NoSePuede | { ok: true; estilo: string; productos: ProductoRevisado[]; restaurante: RestauranteDelAnuncio };
type ProductoRevisado = { id: number; nombre: string; descripcion: string | null };

export async function crearContenido(request: Request, env: Env, url: URL): Promise<Response> {
  const sesion = leerSesion(request);
  if (url.pathname === '/anuncios/estilos' && request.method === 'GET') return estilosDeHoy(env, sesion, url);
  if (url.pathname === '/anuncios/archivo' && request.method === 'GET') return archivo(env, sesion, url);
  if (url.pathname === '/anuncios/palabras' && request.method === 'POST') return palabras(env, sesion, await leerCuerpo(request));
  if (url.pathname === '/anuncios' && request.method === 'POST') return hacer(env, sesion, await leerCuerpo(request));
  throw new Rechazo(404, 'Ese trabajo no existe.');
}

// ─── GET /anuncios/estilos ────────────────────────────────────────────────────

async function estilosDeHoy(env: Env, sesion: string, url: URL): Promise<Response> {
  const restaurante = url.searchParams.get('restaurante') ?? '';
  if (!UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');
  const filas = await llamar<EstiloDeHoy[]>(env, { sesion }, 'estilos_de_hoy', { p_restaurante_id: restaurante });
  const estilos = filas.flatMap((fila) => {
    const estilo = ESTILOS.get(fila.clave);
    if (!estilo) return [];
    return [
      {
        id: fila.id,
        clave: fila.clave,
        nombre: fila.nombre,
        descripcion: fila.descripcion,
        grupo: fila.grupo,
        muestras: { post: fila.muestra_post_ruta, historia: fila.muestra_historia_ruta, cartel: fila.muestra_cartel_ruta },
        maximo: estilo.maximo,
        minimo: estilo.minimo,
        mensaje: estilo.mensaje,
        mayusculas: estilo.mayusculas,
        color: estilo.conColor,
        vacio: estilo.vacio,
        datos: estilo.datos,
        lugares: estilo.lugares.map((l) => ({
          clave: l.clave,
          nombre: l.nombre,
          tope: l.tope,
          mayusculas: l.mayusculas,
          cuando: l.cuando,
          ...(l.vacio ? { vacio: true } : {}),
        })),
      },
    ];
  });
  return json({ estilos });
}

// ─── POST /anuncios/palabras ──────────────────────────────────────────────────

async function palabras(env: Env, sesion: string, cuerpo: Record<string, unknown>): Promise<Response> {
  const { restaurante, estiloId, productos } = leerLoComun(cuerpo);
  const revision = await revisar(env, sesion, restaurante, estiloId, productos);
  if (!revision.ok) return json(revision.respuesta);
  const { estilo, datos } = revision;
  if (!lugaresDe(estilo, productos.length).length) throw new Rechazo(400, 'Este estilo no lleva palabras.');

  const deLosProductos = datos.productos.map((p) => ({ nombre: p.nombre, descripcion: p.descripcion }));
  const pregunta = preguntaDePalabras(estilo, deLosProductos);
  const esquema = esquemaDePalabras(estilo, productos.length);
  const modelo = modeloPalabras(env);
  // Si lo que escribió no cabe, se pregunta una vez más; cada llamada se anota, también la que no cupo.
  for (let intento = 1; intento <= 2; intento++) {
    let salida: Record<string, unknown> | null;
    try {
      const r = await palabrasDeLaIa(env, { instrucciones: REGLAS_PALABRAS, pregunta, esquema });
      await anotar(env, restaurante, 'palabras', modelo, r.tokens);
      salida = r.salida;
    } catch (e) {
      if (e instanceof Rechazo) throw new Rechazo(502, NO_PREPARO);
      throw e;
    }
    const revisadas = salida ? revisarPalabras(estilo, productos.length, salida) : null;
    if (revisadas?.ok) return json({ ok: true, palabras: revisadas.palabras });
    console.warn('[anuncios] las palabras de la IA no cupieron', estilo.clave, `intento ${intento}`, revisadas ? revisadas.falta : 'sin JSON');
  }
  throw new Rechazo(502, NO_PREPARO);
}

// ─── POST /anuncios ───────────────────────────────────────────────────────────

async function hacer(env: Env, sesion: string, cuerpo: Record<string, unknown>): Promise<Response> {
  const { restaurante, estiloId, productos } = leerLoComun(cuerpo);
  const formato = cuerpo.formato;
  if (typeof formato !== 'string' || !FORMATOS.includes(formato as Formato)) throw new Rechazo(400, 'Ese formato no existe.');
  if (cuerpo.mensaje !== undefined && cuerpo.mensaje !== null && typeof cuerpo.mensaje !== 'string') throw new Rechazo(400, 'Faltan los datos.');
  const mensaje = typeof cuerpo.mensaje === 'string' ? cuerpo.mensaje.trim() : '';
  if (cuerpo.color !== undefined && cuerpo.color !== null && (typeof cuerpo.color !== 'string' || !COLOR.test(cuerpo.color))) {
    throw new Rechazo(400, 'El color va como #RRGGBB.');
  }
  const color = typeof cuerpo.color === 'string' ? cuerpo.color.toUpperCase() : null;

  const revision = await revisar(env, sesion, restaurante, estiloId, productos);
  if (!revision.ok) return json(revision.respuesta);
  const { estilo } = revision;

  // Lo que la app ya evita, revisado otra vez contra las reglas del estilo.
  if (!estilo.mensaje && mensaje) throw new Rechazo(400, 'Este estilo no lleva mensaje.');
  if ([...mensaje].length > estilo.mensaje) throw new Rechazo(400, `Tu mensaje puede tener hasta ${estilo.mensaje} letras.`);
  if (!estilo.conColor && color) throw new Rechazo(400, 'Este estilo no lleva color.');
  const revisadas = revisarPalabras(estilo, productos.length, cuerpo.palabras);
  if (!revisadas.ok) throw new Rechazo(400, revisadas.falta);

  const apartado = await llamar<NoSePuede | { ok: true; anuncio_id: number }>(env, { sesion }, 'apartar_anuncio', {
    p_restaurante_id: restaurante,
    p_estilo_id: estiloId,
    p_formato: formato,
    p_productos: productos,
    p_mensaje: mensaje || null,
    p_color: color,
    p_con_color: estilo.conColor,
    p_palabras: revisadas.palabras,
  });
  if (!apartado.ok) return json(apartado);

  const id = apartado.anuncio_id;
  try {
    await env.HACER_ANUNCIO.create({ id: `anuncio-${id}`, params: { anuncio: id } });
  } catch (e) {
    console.error('[anuncios] no arrancó el trabajo del anuncio', id, e);
    // Que no se quede «haciendo» 15 minutos: no salió y no cuenta.
    try {
      await llamar(env, 'worker', 'fallar_anuncio', {
        p_anuncio_id: id,
        p_motivo: 'no_salio',
        p_modelo: modeloImagen(env),
        p_entrada_texto: 0,
        p_entrada_imagen: 0,
        p_salida: 0,
      });
    } catch (falla) {
      console.error('[anuncios] tampoco se pudo marcar como no salió', id, falla);
    }
    throw new Rechazo(503, NO_EMPEZO);
  }
  console.log('[anuncios] empezó', id, estilo.clave, formato, `${productos.length} productos`);
  return json({ ok: true, anuncio_id: id });
}

// ─── GET /anuncios/archivo ────────────────────────────────────────────────────

// El JPG con su nombre: el del producto 1, el formato y el día en que salió (vence menos 29), así
// ni el reloj del Worker ni el del aparato cuentan. El renglón se lee con la sesión de Don Chuy:
// RLS solo le enseña los de sus sucursales que funcionan.
async function archivo(env: Env, sesion: string, url: URL): Promise<Response> {
  const id = Number(url.searchParams.get('id'));
  if (!Number.isSafeInteger(id) || id <= 0) throw new Rechazo(400, 'Falta el anuncio.');
  const [fila] = await leerFilas<{ ruta: string | null; formato: string; productos: { nombre: string }[]; vence: string | null; estado: string }>(
    env,
    sesion,
    `anuncios?id=eq.${id}&select=ruta,formato,productos,vence,estado`,
  );
  if (!fila || fila.estado !== 'listo' || !fila.ruta || !fila.vence) throw new Rechazo(404, YA_NO_ESTA);

  const objeto = await env.BUCKET.get(fila.ruta);
  if (!objeto) {
    console.error('[anuncios] el JPG de un anuncio listo no está en R2', id, fila.ruta);
    throw new Rechazo(404, YA_NO_ESTA);
  }
  const nombre = `${enSlug(fila.productos[0]?.nombre ?? '')}-${fila.formato}-${diaEnQueSalio(fila.vence)}.jpg`;
  return new Response(objeto.body, {
    headers: {
      'Content-Type': 'image/jpeg',
      'Content-Disposition': `attachment; filename="${nombre}"`,
      'Access-Control-Expose-Headers': 'Content-Disposition',
      'Cache-Control': 'private, no-store',
    },
  });
}

// «Taco al pastor» → «taco-al-pastor».
export function enSlug(texto: string): string {
  const slug = texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug || 'anuncio';
}

function diaEnQueSalio(vence: string): string {
  const dia = new Date(`${vence}T00:00:00Z`);
  dia.setUTCDate(dia.getUTCDate() - 29);
  return dia.toISOString().slice(0, 10);
}

// ─── Lo de las dos rutas que hacen ────────────────────────────────────────────

function leerLoComun(cuerpo: Record<string, unknown>): { restaurante: string; estiloId: number; productos: number[] } {
  const restaurante = typeof cuerpo.restaurante === 'string' ? cuerpo.restaurante : '';
  if (!UUID.test(restaurante)) throw new Rechazo(400, 'Falta el restaurante.');
  const estiloId = cuerpo.estilo_id;
  if (typeof estiloId !== 'number' || !Number.isSafeInteger(estiloId) || estiloId <= 0) throw new Rechazo(400, 'Falta el estilo.');
  const productos = cuerpo.productos;
  if (!Array.isArray(productos) || !productos.length || productos.some((p) => typeof p !== 'number' || !Number.isSafeInteger(p) || p <= 0)) {
    throw new Rechazo(400, 'Elige al menos un producto.');
  }
  return { restaurante, estiloId, productos: productos as number[] };
}

// datos_para_anuncio con la sesión de Don Chuy (gerente con la licencia al día, el estilo de hoy,
// sus productos en Mi menú y la IA que puede) y, si todo está bien, las reglas de su estilo.
async function revisar(
  env: Env,
  sesion: string,
  restaurante: string,
  estiloId: number,
  productos: number[],
): Promise<{ ok: false; respuesta: NoSePuede } | { ok: true; estilo: Estilo; datos: Revision & { ok: true } }> {
  const datos = await llamar<Revision>(env, { sesion }, 'datos_para_anuncio', {
    p_restaurante_id: restaurante,
    p_estilo_id: estiloId,
    p_productos: productos,
  });
  if (!datos.ok) return { ok: false, respuesta: datos };
  const estilo = ESTILOS.get(datos.estilo);
  if (!estilo) {
    console.error('[anuncios] un estilo prendido no tiene su prompt en el Worker', datos.estilo);
    return { ok: false, respuesta: { ok: false, motivo: 'estilo' } };
  }
  if (productos.length > estilo.maximo) {
    throw new Rechazo(400, estilo.maximo === 1 ? 'Este estilo lleva 1 producto.' : `Este estilo lleva hasta ${estilo.maximo} productos.`);
  }
  if (productos.length < estilo.minimo) throw new Rechazo(400, `Este estilo es para combos: pica ${estilo.minimo} o ${estilo.maximo}.`);
  return { ok: true, estilo, datos };
}
