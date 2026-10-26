// El pedido por WhatsApp (libreta 6, parte 6b; maqueta G2nxGb3xBgiPEYrDb6CgcW). Lo que la señora
// Ramírez lleva en «Tu pedido» vive en su celular hasta mandarlo (12 horas sin tocarlo y se vacía);
// «Hacer pedido» lo manda al Worker (POST /menu/pedido), que lo revisa con Turnstile y lo guarda con
// hacer_pedido. El total que se ve aquí es solo la vista, como en el celular de Pepe: el que vale es
// el que regresa Postgres, y con ese se arma el mensaje de WhatsApp.
import { dinero } from '@app/lib/formato';
import type { Producto } from './datos';

const API = import.meta.env.VITE_API_URL;
if (!API) throw new Error('Falta VITE_API_URL en menu/.env');

// ─── Lo que lleva ───
export type Renglon = { producto_id: number; cantidad: number; opciones: number[]; nota: string };
// En «Tu pedido», cada renglón guarda su nombre y su precio (si el producto se agota ya no viene en el menú) y,
// después de un «cambios» de Postgres, lo que se le avisa: `fuera` se quita al volver a pedir.
// `precio` es el de uno cuando se agregó: solo para enseñar tachado lo que ya no viene en el menú.
export type EnCarrito = Renglon & {
  nombre: string;
  nombre_en: string | null;
  precio: number;
  aviso?: { fuera: boolean; texto: string };
};

// Dos renglones iguales (mismo producto, mismas opciones, misma nota) se suman en uno, como
// mismaLinea del punto de venta.
export function mismoRenglon(a: Renglon, b: Renglon): boolean {
  const ops = (r: Renglon) => [...r.opciones].sort((x, y) => x - y).join(',');
  return a.producto_id === b.producto_id && a.nota === b.nota && ops(a) === ops(b);
}

// El precio de uno, con sus opciones (el `precio` que viaja con cada renglón, para comparar).
export function precioUnitario(p: Producto, opciones: number[]): number {
  const extra = p.grupos.flatMap((g) => g.opciones).filter((o) => opciones.includes(o.id));
  return centavos(p.precio + extra.reduce((s, o) => s + o.precio_extra, 0));
}

export function centavos(n: number): number {
  return Math.round(n * 100) / 100;
}

// ─── En el celular ───
// Cada restaurante su carrito; el nombre, el teléfono y la dirección sirven para cualquiera. Si el
// navegador no deja guardar, todo funciona igual y se olvida al cerrar la pestaña.
const DOCE_HORAS = 12 * 60 * 60 * 1000;
const llaveCarrito = (slug: string) => `pidemenu-pedido-${slug}`;
const llaveHecho = (slug: string) => `pidemenu-hecho-${slug}`;
const LLAVE_CLIENTE = 'pidemenu-cliente';
const LLAVE_MARCA = 'pidemenu-marca';

function leer<T>(llave: string): T | null {
  try {
    const texto = localStorage.getItem(llave);
    return texto ? (JSON.parse(texto) as T) : null;
  } catch (error) {
    console.warn('[menu] no se pudo leer', llave, error);
    return null;
  }
}

function escribir(llave: string, valor: unknown) {
  try {
    if (valor === null) localStorage.removeItem(llave);
    else localStorage.setItem(llave, JSON.stringify(valor));
  } catch (error) {
    console.warn('[menu] no se pudo guardar', llave, error);
  }
}

export function leerCarrito(slug: string): EnCarrito[] {
  const g = leer<{ renglones: EnCarrito[]; tocado: number }>(llaveCarrito(slug));
  if (!g || !Array.isArray(g.renglones) || Date.now() - g.tocado > DOCE_HORAS) return [];
  return g.renglones;
}

// Los avisos no se guardan: al volver, el menú ya trae los precios y lo agotado de ese momento.
export function guardarCarrito(slug: string, renglones: EnCarrito[]) {
  const limpios = renglones.map(({ aviso: _aviso, ...r }) => r);
  escribir(llaveCarrito(slug), limpios.length ? { renglones: limpios, tocado: Date.now() } : null);
}

export type Cliente = { nombre: string; telefono: string; direccion: string; referencias: string };

export function leerCliente(): Cliente {
  const c = leer<Partial<Cliente>>(LLAVE_CLIENTE) ?? {};
  const s = (x: unknown) => (typeof x === 'string' ? x : '');
  return { nombre: s(c.nombre), telefono: s(c.telefono), direccion: s(c.direccion), referencias: s(c.referencias) };
}

export function guardarCliente(c: Cliente) {
  escribir(LLAVE_CLIENTE, c);
}

// La marca del celular: 32 bytes al azar, para contar 3 pedidos por hora. El Worker la mezcla antes
// de guardarla. Si no se puede recordar, una nueva en cada visita (el límite por conexión sigue).
let marcaSinGuardar: string | null = null;
export function marcaDelCelular(): string {
  const guardada = leer<string>(LLAVE_MARCA);
  if (guardada && /^[A-Za-z0-9_-]{43}$/.test(guardada)) return guardada;
  if (!marcaSinGuardar) {
    const azar = crypto.getRandomValues(new Uint8Array(32));
    marcaSinGuardar = btoa(String.fromCharCode(...azar)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  }
  escribir(LLAVE_MARCA, marcaSinGuardar);
  return marcaSinGuardar;
}

// ─── Mandarlo ───
export type Tipo = 'para_llevar' | 'domicilio';

// Lo que guardó Postgres (privado.pedido_en_json): con esto se arma el mensaje.
export type Guardado = {
  numero: number;
  tipo: Tipo;
  cliente_nombre: string;
  cliente_telefono: string | null;
  cliente_direccion: string | null;
  cliente_referencias: string | null;
  paga_con: number | null;
  total: number;
  renglones: {
    nombre: string;
    cantidad: number;
    importe: number;
    opciones: { grupo: string; opcion: string; precio_extra: number }[];
    nota: string | null;
  }[];
};

export type Cambio = { renglon: number; cambio: 'agotado' | 'opciones' | 'precio'; opcion?: string; precio?: number };

export type Respuesta =
  | ({ ok: true } & Guardado)
  | { ok: false; motivo: 'no_recibe' }
  | { ok: false; motivo: 'cambios'; cambios: Cambio[]; total: number };

// Un «no» que la clienta lee tal cual (el límite, un dato que falta, «No pudimos revisar que eres tú»).
export class NoSeMando extends Error {}

export type Envio = {
  slug: string;
  clave: string;
  tipo: Tipo;
  cliente_nombre: string;
  cliente_telefono: string | null;
  cliente_direccion: string | null;
  cliente_referencias: string | null;
  paga_con: number | null;
  renglones: (Renglon & { precio: number })[];
  turnstile: string;
};

export async function hacerPedido(envio: Envio, sinRed: string): Promise<Respuesta> {
  let respuesta: Response;
  try {
    respuesta = await fetch(`${API}/menu/pedido`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...envio, marca: marcaDelCelular() }),
    });
  } catch (error) {
    console.error('[menu] no se pudo mandar el pedido:', error);
    throw new NoSeMando(sinRed);
  }
  const cuerpo = (await respuesta.json().catch(() => null)) as (Respuesta & { error?: string }) | null;
  if (respuesta.ok && cuerpo && 'ok' in cuerpo) return cuerpo;
  if (cuerpo?.error && respuesta.status < 500) throw new NoSeMando(cuerpo.error);
  console.error('[menu] el pedido regresó', respuesta.status, cuerpo);
  throw new NoSeMando(cuerpo?.error ?? sinRed);
}

// ─── Hecho: «Falta un paso» y «Pedido enviado» ───
// Se queda en el celular hasta el siguiente pedido, hasta «Volver al menú» o hasta que cambie el día
// del restaurante, para que al volver de WhatsApp siga ahí. `ids`: qué producto y qué opciones lleva
// cada renglón, en el orden en que los guardó Postgres, para enseñarlos en inglés.
export type Hecho = { pedido: Guardado; ids: { producto_id: number; opciones: number[] }[]; fecha: string; enviado: boolean };

export function leerHecho(slug: string, hoy: string): Hecho | null {
  const h = leer<Hecho>(llaveHecho(slug));
  return h && h.fecha === hoy && h.pedido ? h : null;
}

export function guardarHecho(slug: string, h: Hecho | null) {
  escribir(llaveHecho(slug), h);
}

// ─── WhatsApp ───
// El mensaje de la decisión 5: en renglones, siempre en español y en pesos (lo lee el restaurante),
// con lo que guardó Postgres, nunca con lo que el celular creía. Las opciones van con su nombre,
// como en el punto de venta («Verde», «Medio litro»).
export function mensajeWhatsApp(p: Guardado): string {
  const telefono = (t: string) => t.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3');
  const dom = p.tipo === 'domicilio';
  const lineas = [`Pedido #${p.numero} · ${dom ? 'A domicilio' : 'Para llevar'}`];
  lineas.push(dom && p.cliente_telefono ? `${p.cliente_nombre} · ${telefono(p.cliente_telefono)}` : p.cliente_nombre);
  if (dom && p.cliente_direccion) {
    lineas.push([p.cliente_direccion, p.cliente_referencias].filter(Boolean).join(' · '));
  }
  if (dom && p.paga_con !== null) lineas.push(`Paga con ${dinero(p.paga_con)}`);
  lineas.push('');
  for (const r of p.renglones) {
    const ops = r.opciones.map((o) => ` · ${o.opcion}`).join('');
    lineas.push(`${r.cantidad} ${r.nombre}${ops} · ${dinero(r.importe)}`);
    if (r.nota) lineas.push(`   Nota: ${r.nota}`);
  }
  lineas.push('');
  lineas.push(`Total: ${dinero(p.total)}${dom ? ' + envío' : ''}`);
  return lineas.join('\n');
}

export function enlaceWhatsApp(telefono: string, texto?: string): string {
  return `https://wa.me/52${telefono}` + (texto ? `?text=${encodeURIComponent(texto)}` : '');
}
