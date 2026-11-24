// La tarjeta de lealtad (parte B, paso 5c; maqueta v22 aprobada el 23 nov 2026, planes/trabajo/tarjeta-lealtad/): lo que
// leen y llaman la vista «Tarjeta de lealtad» del gerente, el cobro (la fila «Tarjeta de lealtad»), «Pasar tarjeta» de la
// Caja y Pedidos. Cada función recibe el cliente de Supabase, como lib/pos.ts, para que el panel y el aparato la
// compartan: por eso aquí no entra lib/supabase.ts.
//
// Las funciones de Postgres están en supabase/migrations/20261123200000_tarjeta_lealtad.sql; qué regresa cada una, en
// «Qué trae» de planes/trabajo/tarjeta-lealtad/migracion.md. Postgres cuenta todo (lo que suma, el premio, cuándo está
// listo): aquí solo se escribe para leerlo.
import type { SupabaseClient } from '@supabase/supabase-js';
import type { EstiloTarjeta, TextosTarjeta } from '../diseno/TarjetaLealtad.svelte';
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { dinero, plural } from './formato';

export type FormaLealtad = 'sellos' | 'puntos';
export type TipoPremio = 'producto' | 'pesos';

// La fila de `lealtad` de la sucursal (sin fila: como nace).
export type Lealtad = {
  prendida: boolean;
  forma: FormaLealtad;
  meta: number | null;
  minimo: number | null;
  pesos_por_punto: number | null;
  premio_tipo: TipoPremio | null;
  premio_producto_id: number | null;
  premio_pesos: number | null;
  estilo: EstiloTarjeta;
  color: string | null; // null: «Del color de tu menú»
};

// Como nace (diccionario-estilo-color.md): sin regla, apagada, con sellos, en Metal y negra.
export const NEGRO_TARJETA = '#121212';
// El motivo con el que Postgres pone el premio en la cuenta (privado.meter_premio): el descuento al 100 % del renglón del
// producto, o el descuento en pesos de la cuenta. Con él, «Cambiar descuento» avisa que el premio regresa a la tarjeta.
export const MOTIVO_PREMIO = 'Premio de la tarjeta';
export const LEALTAD_AL_NACER: Lealtad = {
  prendida: false,
  forma: 'sellos',
  meta: null,
  minimo: null,
  pesos_por_punto: null,
  premio_tipo: null,
  premio_producto_id: null,
  premio_pesos: null,
  estilo: 'metal',
  color: NEGRO_TARJETA,
};

// La regla son dos partes que se guardan juntas: los números y el premio. Sin las dos no se prende.
export const conRegla = (l: Lealtad) => l.meta !== null && l.premio_tipo !== null;

// El color con que se pinta: el suyo, o el del menú; sin color en el menú, el negro (como lo resuelve Postgres).
export const colorDeTarjeta = (color: string | null, colorMenu: string | null) => color || colorMenu || NEGRO_TARJETA;

// Los seis estilos, dos por fila (maqueta v3).
export const ESTILOS: { valor: EstiloTarjeta; nombre: string; sub: string }[] = [
  { valor: 'liquido', nombre: 'Líquido', sub: 'Un fondo que fluye' },
  { valor: 'agua', nombre: 'Agua', sub: 'Vidrio con agua adentro' },
  { valor: 'metal', nombre: 'Metal', sub: 'Metal cepillado, con su canto' },
  { valor: 'brillante', nombre: 'Brillante', sub: 'Un reflejo limpio, con su canto' },
  { valor: 'liso', nombre: 'Liso', sub: 'Tu color en degradado' },
  { valor: 'olas', nombre: 'Olas', sub: 'Tu color con olas suaves' },
];

// Los colores rápidos de «Tu tarjeta»; el negro es el de nacer.
export const COLORES_RAPIDOS: { color: string; nombre: string }[] = [
  { color: NEGRO_TARJETA, nombre: 'Negro' },
  { color: '#CF170D', nombre: 'Rojo' },
  { color: '#2F8A4E', nombre: 'Verde' },
  { color: '#3E9AD8', nombre: 'Azul cielo' },
  { color: '#6E3FB0', nombre: 'Morado' },
  { color: '#C99A2E', nombre: 'Dorado' },
  { color: '#D6457A', nombre: 'Rosa' },
];

// ─── Los textos ───────────────────────────────────────────────────────────────────────────────

// «10 sellos», «1 punto», «100 puntos».
export const cuantos = (forma: FormaLealtad, n: number) =>
  forma === 'sellos' ? plural(n, 'sello', 'sellos') : plural(n, 'punto', 'puntos');

// El premio en una frase: «una Gringa gratis» no (con cualquier producto el «una» sale mal): «tu Gringa gratis»; «$50 de
// descuento».
export function premioEscrito(tipo: TipoPremio | null, producto: string | null, pesos: number | null): string {
  if (tipo === 'producto') return `${producto ?? 'tu producto'} gratis`;
  if (tipo === 'pesos') return `${dinero(pesos ?? 0)} de descuento`;
  return '';
}

// Los textos de la tarjeta dibujada en el panel y en el cobro (los del menú en español, lib/textosTarjeta.ts de menu/).
export function textosDeTarjeta(tipo: TipoPremio | null, producto: string | null, pesos: number | null): TextosTarjeta {
  const conProducto = tipo === 'producto';
  const paraTu = conProducto ? `tu ${producto ?? 'premio'}` : tipo === 'pesos' ? `descuento de ${dinero(pesos ?? 0)}` : 'tu premio';
  return {
    etq: 'TARJETA DE LEALTAD',
    premioListo: 'Premio listo',
    de: 'de',
    puntos: 'puntos',
    yaJuntaste: '¡Ya lo juntaste!',
    faltan: (n) => `Te faltan ${n.toLocaleString('en-US')} para ${paraTu}`,
    teEspera: conProducto ? `Tu ${producto ?? 'premio'} te espera` : tipo === 'pesos' ? `Tus ${dinero(pesos ?? 0)} de descuento te esperan` : 'Tu premio te espera',
    voltear: 'La tarjeta de muestra: tócala para voltearla',
    sub: 'Tarjeta de lealtad',
    sinCamara: 'Sin cámara, diles este código',
    qr: 'Código QR de la tarjeta de muestra',
  };
}

// Atrás de la tarjeta de muestra del panel: la de Rosa, como el teléfono de «Tu tarjeta» (menu/, tarjetaDeRosa). La
// llave es de mentiras: solo dibuja su QR.
export const MUESTRA_ATRAS = {
  titular: 'Rosa Ramírez',
  telefono: '2229876543',
  codigo: 'K7MP2QXR',
  llave: 'muestra-de-la-tarjeta-de-lealtad-0000000000',
};

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

// «Hoy», «Ayer» o «18 nov», con el día de la sucursal.
export function diaDeTabla(dia: string, hoy: string): string {
  if (dia === hoy) return 'Hoy';
  const ayer = new Date(`${hoy}T12:00:00Z`);
  ayer.setUTCDate(ayer.getUTCDate() - 1);
  if (dia === ayer.toISOString().slice(0, 10)) return 'Ayer';
  const [, m, d] = dia.split('-').map(Number);
  return `${d} ${MESES[m - 1]}`;
}

// ─── Leer ────────────────────────────────────────────────────────────────────────────────────

function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[lealtad] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

async function llamar<T>(cliente: SupabaseClient, funcion: string, datos: Record<string, unknown>): Promise<T> {
  const { data, error } = await cliente.rpc(funcion, datos);
  if (error) throw fallo(`${funcion} no se pudo`, error);
  return data as T;
}

const COLUMNAS = 'prendida, forma, meta, minimo, pesos_por_punto, premio_tipo, premio_producto_id, premio_pesos, estilo, color';

export async function leerLealtad(cliente: SupabaseClient, restauranteId: string): Promise<Lealtad> {
  const { data, error } = await cliente.from('lealtad').select(COLUMNAS).eq('restaurante_id', restauranteId).maybeSingle();
  if (error) throw fallo('no se pudo leer la regla', error);
  if (!data) return { ...LEALTAD_AL_NACER };
  const n = (v: unknown) => (v === null || v === undefined ? null : Number(v));
  return {
    prendida: !!data.prendida,
    forma: data.forma as FormaLealtad,
    meta: n(data.meta),
    minimo: n(data.minimo),
    pesos_por_punto: n(data.pesos_por_punto),
    premio_tipo: (data.premio_tipo as TipoPremio | null) ?? null,
    premio_producto_id: n(data.premio_producto_id),
    premio_pesos: n(data.premio_pesos),
    estilo: data.estilo as EstiloTarjeta,
    color: (data.color as string | null) || null,
  };
}

// El color del menú (para «Del color de tu menú») y el logo (atrás de la tarjeta de muestra).
export async function leerMarca(cliente: SupabaseClient, restauranteId: string): Promise<{ colorMenu: string | null; logo: string | null }> {
  const { data, error } = await cliente.from('restaurantes').select('menu_color, logo_ruta').eq('id', restauranteId).single();
  if (error) throw fallo('no se pudo leer el color del menú', error);
  return { colorMenu: (data.menu_color as string | null) || null, logo: (data.logo_ruta as string | null) || null };
}

// El nombre del producto del premio (el cobro no tiene Mi menú a la mano).
export async function nombreDelPremio(cliente: SupabaseClient, restauranteId: string, productoId: number): Promise<string | null> {
  const { data, error } = await cliente.from('productos').select('nombre').eq('restaurante_id', restauranteId).eq('id', productoId).maybeSingle();
  if (error) throw fallo('no se pudo leer el producto del premio', error);
  return (data?.nombre as string | undefined) ?? null;
}

export type TarjetaCliente = {
  id: number;
  nombre: string;
  telefono: string; // 10 dígitos
  saldo: number;
  premio_listo: boolean;
  sacada: string; // AAAA-MM-DD, el día de la sucursal
  ultima_compra: string | null;
  pide_celular: boolean; // pidió pasarla a otro celular y su código no ha vencido
};

export type Tarjetas = { hoy: string; aviso_premio: string | null; tarjetas: TarjetaCliente[] };

export async function leerTarjetas(cliente: SupabaseClient, restauranteId: string): Promise<Tarjetas> {
  const d = await llamar<{ hoy: string; aviso_premio: string | null; tarjetas: TarjetaCliente[] }>(cliente, 'tarjetas_de_lealtad', {
    p_restaurante_id: restauranteId,
  });
  return { hoy: d.hoy, aviso_premio: d.aviso_premio || null, tarjetas: d.tarjetas ?? [] };
}

// ─── Lo que guarda el gerente ────────────────────────────────────────────────────────────────

export type Regla = {
  meta: number;
  minimo: number | null; // con sellos
  pesos_por_punto: number | null; // con puntos
  premio_tipo: TipoPremio;
  premio_producto_id: number | null;
  premio_pesos: number | null;
};

export function guardarRegla(cliente: SupabaseClient, restauranteId: string, r: Regla): Promise<void> {
  return llamar(cliente, 'guardar_regla_lealtad', {
    p_restaurante_id: restauranteId,
    p_meta: r.meta,
    p_minimo: r.minimo,
    p_pesos_por_punto: r.pesos_por_punto,
    p_premio_tipo: r.premio_tipo,
    p_premio_producto_id: r.premio_producto_id,
    p_premio_pesos: r.premio_pesos,
  });
}

// Regresa cuántas tarjetas volvieron a 0 (al pasar de sellos a puntos o al revés).
export function guardarTuTarjeta(
  cliente: SupabaseClient,
  restauranteId: string,
  t: { forma: FormaLealtad; estilo: EstiloTarjeta; color: string | null },
): Promise<number> {
  return llamar(cliente, 'guardar_tu_tarjeta', {
    p_restaurante_id: restauranteId,
    p_forma: t.forma,
    p_estilo: t.estilo,
    p_color: t.color,
  });
}

export function prenderLealtad(cliente: SupabaseClient, restauranteId: string, prendida: boolean): Promise<void> {
  return llamar(cliente, 'prender_lealtad', { p_restaurante_id: restauranteId, p_prendida: prendida });
}

// ─── Lo que hace quien cobra ─────────────────────────────────────────────────────────────────

export type TarjetaEnCuenta = { id: number; nombre: string; saldo: number; premio_listo: boolean };

// «Pasar su tarjeta»: el código de 6 letras y el número de su tarjeta.
export function pasarTarjeta(cliente: SupabaseClient, restauranteId: string, codigo: string, telefono: string): Promise<TarjetaEnCuenta> {
  return llamar(cliente, 'pasar_tarjeta', { p_restaurante_id: restauranteId, p_codigo: codigo, p_telefono: telefono });
}

// Con el QR (la llave), su código corto o su número. `con_qr`: llegó con el QR o el código, así que puede canjear.
export type Ligada = TarjetaEnCuenta & { con_qr: boolean };
export type ConQue = { telefono: string } | { llave: string } | { codigo: string };

export function ligarTarjeta(cliente: SupabaseClient, ventaId: number, con: ConQue): Promise<Ligada> {
  return llamar(cliente, 'ligar_tarjeta', {
    p_venta_id: ventaId,
    p_telefono: 'telefono' in con ? con.telefono : null,
    p_llave: 'llave' in con ? con.llave : null,
    p_codigo: 'codigo' in con ? con.codigo : null,
  });
}

export function quitarTarjeta(cliente: SupabaseClient, ventaId: number): Promise<void> {
  return llamar(cliente, 'quitar_tarjeta', { p_venta_id: ventaId });
}

// La misma clave dos veces canjea una vez.
export function canjearPremio(
  cliente: SupabaseClient,
  ventaId: number,
  clave: string,
  con: { llave: string } | { codigo: string },
): Promise<TarjetaEnCuenta> {
  return llamar(cliente, 'canjear_premio', {
    p_venta_id: ventaId,
    p_clave: clave,
    p_llave: 'llave' in con ? con.llave : null,
    p_codigo: 'codigo' in con ? con.codigo : null,
  });
}

export type TarjetaDeLaCuenta = TarjetaEnCuenta & { premio_en_cuenta: boolean };

export function tarjetaDeLaCuenta(cliente: SupabaseClient, ventaId: number): Promise<TarjetaDeLaCuenta | null> {
  return llamar(cliente, 'tarjeta_de_la_cuenta', { p_venta_id: ventaId });
}

// Lo que se escribe del código corto, como lo acepta Postgres (sin espacios ni guiones, en mayúsculas).
export const limpiarCodigo = (t: string) => t.toUpperCase().replace(/[\s-]/g, '');
// Los 10 dígitos de un teléfono escrito con espacios o guiones (null si no son 10).
export function diezDigitos(t: string): string | null {
  const d = t.replace(/[\s().-]/g, '');
  return /^\d{10}$/.test(d) ? d : null;
}
export const telefonoEscrito = (t: string) => t.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3');
