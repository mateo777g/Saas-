// El inventario con sus recetas (19 nov 2026; planes/trabajo/inventario/, maqueta BBBNJST5w9qZfHWNdovGgb v3): lo que
// leen y llaman la vista «Inventario» del gerente y, en el aparato, la pestaña Inventario de la cocina y la vista
// chiquita de Mi menú de la cocina y la caja. Cada función recibe el cliente de Supabase, como lib/pos.ts, para que el
// panel y el aparato la compartan: por eso aquí no entra lib/supabase.ts (ni lib/fotos.ts, que la trae).
//
// Las funciones de Postgres están en supabase/migrations/20261119200000_inventario.sql (arriba de cada una dice qué
// regresa). Postgres hace todas las cuentas: aquí solo se escriben las cantidades para leerlas.
import type { SupabaseClient } from '@supabase/supabase-js';
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { enZona, diasEntre } from './formato';
import { nombreDeCuenta, type TipoCuenta } from './pos';

// ─── Las unidades ───────────────────────────────────────────────────────────────────────────

export type Unidad = 'kg' | 'g' | 'l' | 'ml' | 'pieza';
export const UNIDADES: Unidad[] = ['kg', 'g', 'l', 'ml', 'pieza'];

// Cómo se llama en las listas («Kilos (kg)») y qué se escribe a la derecha de una caja de texto («kg», «piezas»).
export const NOMBRE_UNIDAD: Record<Unidad, string> = {
  kg: 'Kilos (kg)',
  g: 'Gramos (g)',
  l: 'Litros (l)',
  ml: 'Mililitros (ml)',
  pieza: 'Piezas',
};
export const SUFIJO_UNIDAD: Record<Unidad, string> = { kg: 'kg', g: 'g', l: 'l', ml: 'ml', pieza: 'piezas' };

// Kilos y gramos son de una familia, litros y mililitros de otra, y las piezas solas (Postgres convierte dentro de
// cada familia): las unidades que puede llevar un renglón de receta de algo que se cuenta en `u`.
export function deSuFamilia(u: Unidad): Unidad[] {
  if (u === 'kg' || u === 'g') return ['kg', 'g'];
  if (u === 'l' || u === 'ml') return ['l', 'ml'];
  return ['pieza'];
}

// Un número como se lee: hasta tres decimales, sin ceros de más, con comas en los miles (4.6, 0.25, 1,200).
export function numero(n: number): string {
  return Math.abs(n).toLocaleString('en-US', { maximumFractionDigits: 3 });
}

// «4.6 kg», «−0.4 kg», «46 piezas», «1 pieza». Con `signo`, también el «+» de lo que sube.
export function cantidad(n: number, u: Unidad, signo = false): string {
  const s = n < 0 ? '−' : signo && n > 0 ? '+' : '';
  const nombre = u === 'pieza' ? (Math.abs(n) === 1 ? 'pieza' : 'piezas') : u;
  return `${s}${numero(n)} ${nombre}`;
}

// Lo que se escribe en una caja de texto: con punto decimal y sin comas.
export function enCaja(n: number | null): string {
  return n === null ? '' : String(Math.round(n * 1000) / 1000);
}

// Una opción del filtro de las tablas (pantallas/gerente/inventario/Filtro.svelte): con su ícono, el de una categoría o
// el punto de un color, y cuántos tiene.
export type OpcionFiltro = { valor: string; nombre: string; cuenta: number; icono?: string; categoria?: string; color?: string };

// ─── Los ingredientes ───────────────────────────────────────────────────────────────────────

export type Ingrediente = {
  id: number;
  nombre: string;
  unidad: Unidad;
  por_caja: number | null;
  minimo: number | null;
  existencia: number;
};

// Cómo va: en rojo en 0 o abajo, en amarillo al llegar a su mínimo, y bien. Sin mínimo, solo rojo.
export type ComoVa = 'rojo' | 'amarillo' | 'verde';
export const TEXTO_COMO_VA: Record<ComoVa, string> = { rojo: 'Se acabó', amarillo: 'Se acaba', verde: 'Bien' };

export function comoVa(i: Pick<Ingrediente, 'existencia' | 'minimo'>): ComoVa {
  if (i.existencia <= 0) return 'rojo';
  if (i.minimo !== null && i.existencia <= i.minimo) return 'amarillo';
  return 'verde';
}

// Cuántos se acaban o se acabaron: el numerito de «Inventario» en la barra lateral y en la pestaña de la cocina.
export function cuantosSeAcaban(lista: Ingrediente[]): number {
  return lista.filter((i) => comoVa(i) !== 'verde').length;
}

const ORDEN_COMO_VA: Record<ComoVa, number> = { rojo: 0, amarillo: 1, verde: 2 };
const porNombre = (a: { nombre: string }, b: { nombre: string }) => a.nombre.localeCompare(b.nombre, 'es');

// Los que se acabaron primero, luego los que se acaban y luego los demás, por nombre (maqueta, «Lo que elegí yo» 3).
export function ordenarIngredientes(lista: Ingrediente[]): Ingrediente[] {
  return [...lista].sort((a, b) => ORDEN_COMO_VA[comoVa(a)] - ORDEN_COMO_VA[comoVa(b)] || porNombre(a, b));
}

const num = (x: unknown) => (x === null || x === undefined ? null : Number(x));

export async function leerIngredientes(cliente: SupabaseClient, restauranteId: string): Promise<Ingrediente[]> {
  const { data, error } = await cliente
    .from('ingredientes')
    .select('id, nombre, unidad, por_caja, minimo, existencia')
    .eq('restaurante_id', restauranteId)
    .is('archivado_at', null);
  if (error) throw error;
  return ordenarIngredientes(
    (data as Record<string, unknown>[]).map((i) => ({
      id: Number(i.id),
      nombre: String(i.nombre),
      unidad: i.unidad as Unidad,
      por_caja: num(i.por_caja),
      minimo: num(i.minimo),
      existencia: Number(i.existencia),
    })),
  );
}

// ─── Las preparaciones y las recetas (solo el gerente las lee) ─────────────────────────────────

export type Preparacion = { id: number; nombre: string; rinde: number; unidad: Unidad };

// Un renglón de receta: de un platillo, de una opción o de una preparación; lleva un ingrediente o una preparación.
export type RenglonReceta = {
  id: number;
  producto_id: number | null;
  opcion_id: number | null;
  preparacion_id: number | null;
  ingrediente_id: number | null;
  lleva_preparacion_id: number | null;
  cantidad: number;
  unidad: Unidad;
};

export type Recetario = { preparaciones: Preparacion[]; recetas: RenglonReceta[] };

export async function leerRecetas(cliente: SupabaseClient, restauranteId: string): Promise<Recetario> {
  const [preparaciones, recetas] = await Promise.all([
    cliente.from('preparaciones').select('id, nombre, rinde, unidad').eq('restaurante_id', restauranteId),
    cliente
      .from('recetas')
      .select('id, producto_id, opcion_id, preparacion_id, ingrediente_id, lleva_preparacion_id, cantidad, unidad')
      .eq('restaurante_id', restauranteId)
      .order('id'),
  ]);
  if (preparaciones.error) throw preparaciones.error;
  if (recetas.error) throw recetas.error;
  return {
    preparaciones: (preparaciones.data as Record<string, unknown>[])
      .map((p) => ({ id: Number(p.id), nombre: String(p.nombre), rinde: Number(p.rinde), unidad: p.unidad as Unidad }))
      .sort(porNombre),
    recetas: (recetas.data as Record<string, unknown>[]).map((r) => ({
      id: Number(r.id),
      producto_id: num(r.producto_id),
      opcion_id: num(r.opcion_id),
      preparacion_id: num(r.preparacion_id),
      ingrediente_id: num(r.ingrediente_id),
      lleva_preparacion_id: num(r.lleva_preparacion_id),
      cantidad: Number(r.cantidad),
      unidad: r.unidad as Unidad,
    })),
  };
}

// «100 g de Pastor», «2 piezas de Tortilla», «30 ml de Salsa verde», como está escrita la receta.
export function lineaReceta(c: number, u: Unidad, nombre: string): string {
  return `${cantidad(c, u)} de ${nombre}`;
}

// Lo que lleva una receta, renglón por renglón, con los nombres de sus ingredientes y preparaciones.
export function loQueLleva(renglones: RenglonReceta[], ingredientes: Pick<Ingrediente, 'id' | 'nombre'>[], preparaciones: Preparacion[]): string[] {
  const ing = new Map(ingredientes.map((i) => [i.id, i.nombre]));
  const prep = new Map(preparaciones.map((p) => [p.id, p.nombre]));
  return renglones.map((r) =>
    lineaReceta(r.cantidad, r.unidad, (r.ingrediente_id !== null ? ing.get(r.ingrediente_id) : prep.get(r.lleva_preparacion_id ?? 0)) ?? '—'),
  );
}

// ─── Lo que se escribe en las ventanas ──────────────────────────────────────────────────────

// Un renglón de receta para guardar: un ingrediente o una preparación, cuánto y en qué.
export type RenglonNuevo = { ingrediente_id?: number; preparacion_id?: number; cantidad: number; unidad: Unidad };

// Los errores de las funciones ya vienen en español; los de la red, «Sin conexión».
function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[inventario] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

async function llamar<T>(cliente: SupabaseClient, funcion: string, datos: Record<string, unknown>): Promise<T> {
  const { data, error } = await cliente.rpc(funcion, datos);
  if (error) throw fallo(`${funcion} no se pudo`, error);
  return data as T;
}

export function guardarIngrediente(
  cliente: SupabaseClient,
  restauranteId: string,
  datos: { id: number | null; nombre: string; unidad: Unidad; por_caja: number | null; minimo: number | null; hay: number | null; clave: string | null },
): Promise<number> {
  return llamar(cliente, 'guardar_ingrediente', {
    p_restaurante_id: restauranteId,
    p_nombre: datos.nombre,
    p_unidad: datos.unidad,
    p_por_caja: datos.por_caja,
    p_minimo: datos.minimo,
    p_id: datos.id,
    p_hay: datos.hay,
    p_clave: datos.clave,
  });
}

// Regresa de cuántas recetas salió.
export function archivarIngrediente(cliente: SupabaseClient, restauranteId: string, id: number): Promise<number> {
  return llamar(cliente, 'archivar_ingrediente', { p_restaurante_id: restauranteId, p_id: id });
}

export function guardarReceta(
  cliente: SupabaseClient,
  restauranteId: string,
  de: { producto: number } | { opcion: number },
  renglones: RenglonNuevo[],
): Promise<number> {
  return llamar(cliente, 'guardar_receta', {
    p_restaurante_id: restauranteId,
    p_renglones: renglones,
    p_producto_id: 'producto' in de ? de.producto : null,
    p_opcion_id: 'opcion' in de ? de.opcion : null,
  });
}

export function guardarPreparacion(
  cliente: SupabaseClient,
  restauranteId: string,
  datos: { id: number | null; nombre: string; rinde: number; unidad: Unidad; renglones: RenglonNuevo[] },
): Promise<number> {
  return llamar(cliente, 'guardar_preparacion', {
    p_restaurante_id: restauranteId,
    p_nombre: datos.nombre,
    p_rinde: datos.rinde,
    p_unidad: datos.unidad,
    p_renglones: datos.renglones,
    p_id: datos.id,
  });
}

// Regresa de cuántos platillos u opciones salió.
export function eliminarPreparacion(cliente: SupabaseClient, restauranteId: string, id: number): Promise<number> {
  return llamar(cliente, 'eliminar_preparacion', { p_restaurante_id: restauranteId, p_id: id });
}

export function anotarLlegada(
  cliente: SupabaseClient,
  restauranteId: string,
  clave: string,
  renglones: ({ ingrediente_id: number; cantidad: number } | { ingrediente_id: number; cajas: number })[],
): Promise<number> {
  return llamar(cliente, 'anotar_llegada', { p_restaurante_id: restauranteId, p_clave: clave, p_renglones: renglones });
}

export type Motivo = 'se_echo_a_perder' | 'se_cayo_o_quemo' | 'caduco' | 'otro';
export const MOTIVOS: { valor: Motivo; texto: string }[] = [
  { valor: 'se_echo_a_perder', texto: 'Se echó a perder' },
  { valor: 'se_cayo_o_quemo', texto: 'Se cayó o se quemó' },
  { valor: 'caduco', texto: 'Caducó' },
  { valor: 'otro', texto: 'Otro' },
];

export function anotarMerma(
  cliente: SupabaseClient,
  restauranteId: string,
  datos: { clave: string; motivo: Motivo; nota: string } & ({ ingrediente: number; cantidad: number } | { producto: number; platillos: number }),
): Promise<number> {
  return llamar(cliente, 'anotar_merma', {
    p_restaurante_id: restauranteId,
    p_clave: datos.clave,
    p_motivo: datos.motivo,
    p_nota: datos.nota.trim() || null,
    p_ingrediente_id: 'ingrediente' in datos ? datos.ingrediente : null,
    p_cantidad: 'ingrediente' in datos ? datos.cantidad : null,
    p_producto_id: 'producto' in datos ? datos.producto : null,
    p_platillos: 'producto' in datos ? datos.platillos : null,
  });
}

// Los platillos con receta, en el orden del menú: los que se pueden anotar como merma entera.
export function platillosParaMerma(cliente: SupabaseClient, restauranteId: string): Promise<{ id: number; nombre: string }[]> {
  return llamar(cliente, 'platillos_para_merma', { p_restaurante_id: restauranteId });
}

// Lo que resta la merma de `platillos` de un platillo, como está escrita su receta: «300 g de Pastor · 90 ml de Salsa verde».
export async function loQueResta(cliente: SupabaseClient, restauranteId: string, producto: number, platillos: number): Promise<string> {
  const filas = await llamar<{ nombre: string; cantidad: number; unidad: Unidad }[]>(cliente, 'lo_que_resta', {
    p_restaurante_id: restauranteId,
    p_producto_id: producto,
    p_platillos: platillos,
  });
  return filas.map((f) => lineaReceta(Number(f.cantidad), f.unidad, f.nombre)).join(' · ');
}

export function anotarConteo(
  cliente: SupabaseClient,
  restauranteId: string,
  clave: string,
  conteos: { ingrediente_id: number; contado: number }[],
): Promise<number> {
  return llamar(cliente, 'anotar_conteo', { p_restaurante_id: restauranteId, p_clave: clave, p_conteos: conteos });
}

export function deshacerMovimiento(cliente: SupabaseClient, restauranteId: string, movimiento: number, clave: string): Promise<number> {
  return llamar(cliente, 'deshacer_movimiento', { p_restaurante_id: restauranteId, p_movimiento_id: movimiento, p_clave: clave });
}

// El ojito de la vista chiquita de Mi menú: regresa si quedó a la vista.
export function marcarAgotado(cliente: SupabaseClient, restauranteId: string, producto: number, agotado: boolean): Promise<boolean> {
  return llamar(cliente, 'marcar_agotado', { p_restaurante_id: restauranteId, p_producto_id: producto, p_agotado: agotado });
}

// ─── El historial de un ingrediente (solo el gerente) ─────────────────────────────────────────

export type Movimiento = {
  id: number;
  tipo: 'venta' | 'regreso' | 'llegada' | 'merma' | 'conteo' | 'deshacer';
  cantidad: number;
  cuando: string; // «Hoy 14:05», «Ayer 23:30», «Lun 12:15», «12 nov 09:10»
  titulo: string; // «Venta · Mesa 4», «Llegó · 2 cajas», «Merma · Se cayó o se quemó»
  quien: string; // «se cerró sola», «Don Chuy», «Chente · cocina»
  tachado: boolean; // un «Deshacer» y lo que anuló
  sePuedeDeshacer: boolean;
};

const DIAS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

// Cuándo, en la zona del restaurante, contado desde su día de hoy.
function cuandoFue(momento: string, zona: string, hoy: string): string {
  const { dia, hora } = enZona(momento, zona);
  const hace = diasEntre(dia, hoy);
  const [a, m, d] = dia.split('-').map(Number);
  if (hace <= 0) return `Hoy ${hora}`;
  if (hace === 1) return `Ayer ${hora}`;
  if (hace < 7) return `${DIAS[new Date(Date.UTC(a, m - 1, d)).getUTCDay()]} ${hora}`;
  return `${d} ${MESES_CORTOS[m - 1]} ${hora}`;
}

const TEXTO_MOTIVO = Object.fromEntries(MOTIVOS.map((m) => [m.valor, m.texto])) as Record<string, string>;

// Los últimos 200 movimientos, del más nuevo al más viejo, ya escritos para leerse.
export async function leerHistorial(
  cliente: SupabaseClient,
  restauranteId: string,
  ingrediente: Pick<Ingrediente, 'id' | 'unidad'>,
  zona: string,
  hoy: string,
): Promise<Movimiento[]> {
  const { data, error } = await cliente
    .from('movimientos_inventario')
    .select('id, tipo, cantidad, contado, cajas, motivo, venta_id, producto_id, platillos, deshace_id, anotado_por, created_at')
    .eq('restaurante_id', restauranteId)
    .eq('ingrediente_id', ingrediente.id)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(200);
  if (error) throw error;
  type Fila = {
    id: number;
    tipo: Movimiento['tipo'];
    cantidad: number;
    contado: number | null;
    cajas: number | null;
    motivo: string | null;
    venta_id: number | null;
    producto_id: number | null;
    platillos: number | null;
    deshace_id: number | null;
    anotado_por: number | null;
    created_at: string;
  };
  const filas = data as Fila[];
  const ids = (k: 'venta_id' | 'producto_id' | 'anotado_por') => [...new Set(filas.map((f) => f[k]).filter((x): x is number => x !== null))];
  const [ventas, productos, miembros] = await Promise.all([
    ids('venta_id').length
      ? cliente.from('ventas').select('id, tipo, mesa_nombre, cliente_nombre, pedido_numero').eq('restaurante_id', restauranteId).in('id', ids('venta_id'))
      : Promise.resolve({ data: [], error: null }),
    ids('producto_id').length
      ? cliente.from('productos').select('id, nombre').eq('restaurante_id', restauranteId).in('id', ids('producto_id'))
      : Promise.resolve({ data: [], error: null }),
    ids('anotado_por').length
      ? cliente.from('miembros').select('id, nombre, roles').eq('restaurante_id', restauranteId).in('id', ids('anotado_por'))
      : Promise.resolve({ data: [], error: null }),
  ]);
  // Sin los nombres, el historial sale igual, con «—» donde iban.
  if (ventas.error) console.error('[inventario] no se pudieron leer las cuentas del historial:', ventas.error);
  if (productos.error) console.error('[inventario] no se pudieron leer los platillos del historial:', productos.error);
  if (miembros.error) console.error('[inventario] no se pudo leer quién anotó cada cosa:', miembros.error);
  const cuenta = new Map(
    ((ventas.data ?? []) as { id: number; tipo: TipoCuenta; mesa_nombre: string | null; cliente_nombre: string | null; pedido_numero: number | null }[]).map(
      (v) => [v.id, nombreDeCuenta(v)],
    ),
  );
  const platillo = new Map(((productos.data ?? []) as { id: number; nombre: string }[]).map((p) => [p.id, p.nombre]));
  const persona = new Map(
    ((miembros.data ?? []) as { id: number; nombre: string; roles: string[] }[]).map((m) => [
      m.id,
      m.roles.includes('gerente') ? m.nombre : m.roles.includes('cocina') ? `${m.nombre} · cocina` : m.nombre,
    ]),
  );
  const deshechos = new Set(filas.map((f) => f.deshace_id).filter((x) => x !== null));
  const porId = new Map(filas.map((f) => [f.id, f]));
  const u = ingrediente.unidad;

  function titulo(f: Fila): string {
    switch (f.tipo) {
      case 'venta':
        return `Venta · ${cuenta.get(f.venta_id ?? 0) ?? '—'}`;
      case 'regreso':
        return `Venta regresó · ${cuenta.get(f.venta_id ?? 0) ?? '—'}`;
      case 'llegada':
        return f.cajas ? `Llegó · ${f.cajas} ${f.cajas === 1 ? 'caja' : 'cajas'}` : 'Llegó';
      case 'merma':
        return f.producto_id !== null
          ? `Merma · ${f.platillos ?? 1} × ${platillo.get(f.producto_id) ?? '—'}`
          : `Merma · ${TEXTO_MOTIVO[f.motivo ?? ''] ?? '—'}`;
      case 'conteo':
        return `Conteo · contaste ${cantidad(Number(f.contado ?? 0), u)}`;
      case 'deshacer': {
        const otro = f.deshace_id !== null ? porId.get(f.deshace_id) : undefined;
        return otro ? `Deshecho · ${titulo(otro)}` : 'Deshecho';
      }
    }
  }

  return filas.map((f) => ({
    id: f.id,
    tipo: f.tipo,
    cantidad: Number(f.cantidad),
    cuando: cuandoFue(f.created_at, zona, hoy),
    titulo: titulo(f),
    quien:
      f.tipo === 'venta' ? 'se cerró sola' : f.tipo === 'regreso' ? 'se canceló un pago' : (persona.get(f.anotado_por ?? 0) ?? '—'),
    tachado: f.tipo === 'deshacer' || deshechos.has(f.id),
    sePuedeDeshacer: (f.tipo === 'llegada' || f.tipo === 'merma' || f.tipo === 'conteo') && !deshechos.has(f.id),
  }));
}

// ─── La vista chiquita de Mi menú (cocina y caja) ─────────────────────────────────────────────

export type CategoriaChica = { id: number; nombre: string; icono: string };
export type Platillo = { id: number; categoria_id: number; nombre: string; foto: string | null; visible: boolean };

// Los platillos de Mi menú sin envíos ni archivados, en el orden del menú, con sus categorías.
export async function leerPlatillos(
  cliente: SupabaseClient,
  restauranteId: string,
): Promise<{ categorias: CategoriaChica[]; platillos: Platillo[] }> {
  const [categorias, productos] = await Promise.all([
    cliente
      .from('categorias')
      .select('id, nombre, icono')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
    cliente
      .from('productos')
      .select('id, categoria_id, nombre, imagen_ruta, visible')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .eq('es_envio', false)
      .order('orden')
      .order('id'),
  ]);
  if (categorias.error) throw categorias.error;
  if (productos.error) throw productos.error;
  const cats = categorias.data as CategoriaChica[];
  const lugar = new Map(cats.map((c, i) => [c.id, i]));
  const platillos = (productos.data as { id: number; categoria_id: number; nombre: string; imagen_ruta: string | null; visible: boolean }[])
    .filter((p) => lugar.has(p.categoria_id))
    .sort((a, b) => (lugar.get(a.categoria_id) ?? 0) - (lugar.get(b.categoria_id) ?? 0))
    .map((p) => ({
      id: p.id,
      categoria_id: p.categoria_id,
      nombre: p.nombre,
      foto: p.imagen_ruta ? `${import.meta.env.VITE_R2_PUBLICO}/${p.imagen_ruta}` : null,
      visible: p.visible,
    }));
  return { categorias: cats, platillos };
}
