// Lo que leen y escriben el punto de venta y la pantalla de cocina (parte 4a, migración cuentas;
// libreta 5). Lo usan el aparato del equipo, con su sesión, y el panel del gerente, con la suya:
// por eso cada función recibe la conexión y este archivo nunca importa lib/supabase.ts (el
// aparato no la carga). Nada se escribe directo en las tablas: las cuentas, sus renglones y las
// comandas solo cambian con las funciones de Postgres, que ponen los precios y el total.
import type { SupabaseClient } from '@supabase/supabase-js';
import { ALGO_SALIO_PANEL, esDeRed, Fallo, mensajeDeError, SIN_CONEXION, sinCentavos } from './errores';
import { dinero } from './formato';

// ─── El menú, como lo ve quien toma pedidos ─────────────────────────────────────────────────

export type Opcion = { id: number; nombre: string; precio_extra: number; visible: boolean };
export type Grupo = { id: number; nombre: string; minimo: number; maximo: number; opciones: Opcion[] };
// `grupos`: los que lleva, en el orden de la pestaña Opciones (uno solo por restaurante).
// `foto`: la dirección de su foto de Mi menú, o null (el cuadro negro); la usan los cuadros de Vender a lo ancho.
export type ProductoPos = { id: number; nombre: string; precio: number; visible: boolean; foto: string | null; grupos: Grupo[] };
// `area`: a qué pantalla de cocina va; null es «Se entrega directo». `icono`: el de Mi menú, para el filtro.
export type CategoriaPos = { id: number; nombre: string; icono: string; area: string | null; productos: ProductoPos[] };
export type Area = { id: number; nombre: string };
export type MenuPos = { categorias: CategoriaPos[]; areas: Area[] };

// Un producto se ve agotado con su ojito apagado, o si a un grupo que lleva le quedan a la vista
// menos opciones que su mínimo (la regla de mandar_a_cocina, decidida el 15 de octubre de 2026).
// Al mandar, quien decide es Postgres.
export function agotado(p: ProductoPos): boolean {
  return !p.visible || p.grupos.some((g) => g.opciones.filter((o) => o.visible).length < g.minimo);
}

export async function leerMenuPos(cliente: SupabaseClient, restauranteId: string): Promise<MenuPos> {
  const [categorias, productos, grupos, opciones, enlaces, areas] = await Promise.all([
    cliente
      .from('categorias')
      .select('id, nombre, icono, area_preparacion_id')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
    cliente
      .from('productos')
      .select('id, categoria_id, nombre, precio, visible, imagen_ruta')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('orden')
      .order('id'),
    cliente
      .from('grupos_opciones')
      .select('id, nombre, minimo, maximo')
      .eq('restaurante_id', restauranteId)
      .order('orden')
      .order('id'),
    cliente
      .from('opciones')
      .select('id, grupo_id, nombre, precio_extra, visible')
      .eq('restaurante_id', restauranteId)
      .order('orden')
      .order('id'),
    cliente.from('producto_grupos').select('producto_id, grupo_id').eq('restaurante_id', restauranteId),
    cliente
      .from('areas_preparacion')
      .select('id, nombre')
      .eq('restaurante_id', restauranteId)
      .is('archivado_at', null)
      .order('id'),
  ]);
  for (const r of [categorias, productos, grupos, opciones, enlaces, areas]) if (r.error) throw r.error;

  const porGrupo = new Map<number, Grupo>();
  for (const g of grupos.data!) porGrupo.set(g.id, { ...g, opciones: [] });
  for (const o of opciones.data!) {
    porGrupo.get(o.grupo_id)?.opciones.push({
      id: o.id,
      nombre: o.nombre,
      precio_extra: Number(o.precio_extra),
      visible: o.visible,
    });
  }
  const ordenGrupo = new Map(grupos.data!.map((g, i) => [g.id, i]));
  const gruposDe = new Map<number, number[]>();
  for (const e of enlaces.data!) gruposDe.set(e.producto_id, [...(gruposDe.get(e.producto_id) ?? []), e.grupo_id]);

  const nombreArea = new Map(areas.data!.map((a) => [a.id, a.nombre]));
  return {
    areas: areas.data!,
    categorias: categorias.data!.map((c) => ({
      id: c.id,
      nombre: c.nombre,
      icono: c.icono,
      area: c.area_preparacion_id === null ? null : (nombreArea.get(c.area_preparacion_id) ?? null),
      productos: productos.data!
        .filter((p) => p.categoria_id === c.id)
        .map((p) => ({
          id: p.id,
          nombre: p.nombre,
          precio: Number(p.precio),
          visible: p.visible,
          // Como urlFoto de lib/fotos.ts, que el aparato no importa (trae la conexión del panel).
          foto: p.imagen_ruta ? `${import.meta.env.VITE_R2_PUBLICO}/${p.imagen_ruta}` : null,
          grupos: (gruposDe.get(p.id) ?? [])
            .sort((a, b) => (ordenGrupo.get(a) ?? 0) - (ordenGrupo.get(b) ?? 0))
            .map((id) => porGrupo.get(id))
            .filter((g): g is Grupo => !!g),
        })),
    })),
  };
}

// ─── El restaurante, sus mesas y su equipo ──────────────────────────────────────────────────

export type Mesa = { id: number; nombre: string };

export async function leerZona(cliente: SupabaseClient, restauranteId: string): Promise<string> {
  const { data, error } = await cliente.from('restaurantes').select('zona_horaria').eq('id', restauranteId).single();
  if (error) throw error;
  return data.zona_horaria;
}

export async function leerMesasPos(cliente: SupabaseClient, restauranteId: string): Promise<Mesa[]> {
  const { data, error } = await cliente
    .from('mesas')
    .select('id, nombre')
    .eq('restaurante_id', restauranteId)
    .is('archivado_at', null)
    .order('orden')
    .order('id');
  if (error) throw error;
  return data;
}

// El nombre de pila de cada quien en el restaurante («Toño»), también de quien ya está de baja:
// sus cuentas siguen diciendo que las abrió.
export const pila = (nombre: string) => nombre.trim().split(/\s+/)[0];

export async function leerNombres(cliente: SupabaseClient, restauranteId: string): Promise<Map<number, string>> {
  const { data, error } = await cliente.from('miembros').select('id, nombre').eq('restaurante_id', restauranteId);
  if (error) throw error;
  return new Map(data.map((m) => [m.id, pila(m.nombre)]));
}

// Quién puede autorizar con su PIN lo que pide PIN (parte 4c; libreta 5): la caja y los gerentes
// activos que tienen PIN, sin quien pide. Quien pide y es de la caja o gerente no necesita a nadie:
// sus cancelaciones y descuentos quedan a su nombre. Lo decide privado.autoriza; aquí solo se
// pinta la lista. `bloqueadoHasta`: 'infinity' es hasta que su gerente lo desbloquee.
export type Autoriza = { id: number; nombre: string; roles: string[]; bloqueadoHasta: string | null };
export type Equipo = { nombres: Map<number, string>; yoAutorizo: boolean; autorizan: Autoriza[] };

export async function leerEquipo(cliente: SupabaseClient, restauranteId: string, miembroId: number): Promise<Equipo> {
  const { data, error } = await cliente
    .from('miembros')
    .select('id, nombre, roles, activo, tiene_pin, bloqueado_hasta')
    .eq('restaurante_id', restauranteId)
    .order('nombre');
  if (error) throw error;
  const deCaja = (roles: string[]) => roles.includes('caja') || roles.includes('gerente');
  const yo = data.find((m) => m.id === miembroId);
  return {
    nombres: new Map(data.map((m) => [m.id, pila(m.nombre)])),
    yoAutorizo: !!yo && deCaja(yo.roles),
    autorizan: data
      .filter((m) => m.id !== miembroId && m.activo && m.tiene_pin && deCaja(m.roles))
      .map((m) => ({ id: m.id, nombre: m.nombre, roles: m.roles, bloqueadoHasta: m.bloqueado_hasta })),
  };
}

// ─── Las cuentas abiertas ───────────────────────────────────────────────────────────────────

export type TipoCuenta = 'mesa' | 'comer_aqui' | 'para_llevar' | 'domicilio';

// Cómo se dice el tipo de una cuenta sin mesa (adaptabilidad, 12 de noviembre de 2026).
export const TIPO_EN_PALABRAS: Record<Exclude<TipoCuenta, 'mesa'>, string> = {
  comer_aqui: 'Comer aquí',
  para_llevar: 'Para llevar',
  domicilio: 'Domicilio',
};

// El ícono de cada tipo de cuenta (maqueta de la adaptabilidad v4).
export const ICONO_DE_TIPO: Record<TipoCuenta, string> = {
  mesa: 'mesas',
  comer_aqui: 'tienda',
  para_llevar: 'bolsa',
  domicilio: 'moto',
};
export type TipoDescuento = 'porcentaje' | 'pesos';

export type Venta = {
  id: number;
  tipo: TipoCuenta;
  mesa_id: number | null;
  mesa_nombre: string | null;
  cliente_nombre: string | null;
  cliente_telefono: string | null;
  cliente_direccion: string | null;
  subtotal: number; // la suma de los renglones activos, ya con su descuento (parte 4c)
  descuento: number; // el de toda la cuenta, en pesos; lo cuenta Postgres
  descuento_tipo: TipoDescuento | null;
  descuento_valor: number | null;
  descuento_motivo: string | null;
  total: number; // subtotal − descuento
  pagado: number; // la suma de sus pagos (parte 4b); la escribe un trigger
  folio: number | null; // abierta con folio: reabierta, porque se canceló un pago (parte 4c)
  abierta_por: number | null;
  cuenta_pedida_at: string | null;
  pedido_numero: number | null; // el número del día de una cuenta sin mesa: «#27» (partes 6b y adaptabilidad)
  origen: 'punto_de_venta' | 'menu_en_linea'; // menu_en_linea: nació de un pedido del menú en línea
  created_at: string;
};

// Cómo se llama una cuenta en la app: la de una mesa, por su mesa; con número del día y nombre,
// «#27 · Rosa Ramírez» (parte 6b); solo con número, «#23», y solo con nombre, el nombre (adaptabilidad:
// el nombre es opcional y sin él la cuenta toma su número).
export function nombreDeCuenta(v: {
  tipo: TipoCuenta;
  mesa_nombre: string | null;
  cliente_nombre: string | null;
  pedido_numero: number | null;
}): string {
  if (v.tipo === 'mesa') return v.mesa_nombre ?? '—';
  const nombre = v.cliente_nombre?.trim() || null;
  if (v.pedido_numero !== null) return nombre ? `#${v.pedido_numero} · ${nombre}` : `#${v.pedido_numero}`;
  return nombre ?? '—';
}

export type OpcionElegida = { grupo: string; opcion: string; precio_extra: number };

export type Renglon = {
  id: number;
  venta_id: number;
  nombre: string;
  cantidad: number;
  precio_unitario: number;
  descuento: number; // en pesos; lo cuenta Postgres
  descuento_tipo: TipoDescuento | null;
  descuento_valor: number | null;
  descuento_motivo: string | null;
  importe: number; // cantidad × precio, menos el descuento
  opciones: OpcionElegida[];
  nota: string | null;
  comanda_id: number | null;
  agregado_por: number | null;
  clave_envio: string;
  // Lo cancelado se queda en la cuenta, tachado, y no suma (parte 4c).
  estado: 'activo' | 'cancelado';
  autorizado_por: number | null;
  cancelado_motivo: string | null;
};

export type Comanda = {
  id: number;
  venta_id: number;
  area_preparacion_id: number;
  estado: 'pendiente' | 'lista';
  enviada_por: number | null;
  lista_at: string | null;
  created_at: string;
};

export type Abiertas = { ventas: Venta[]; renglones: Renglon[]; comandas: Comanda[] };

// Un solo texto cada una: así supabase-js sabe qué columnas trae.
const COLUMNAS_VENTA =
  'id, tipo, mesa_id, mesa_nombre, cliente_nombre, cliente_telefono, cliente_direccion, subtotal, descuento, descuento_tipo, descuento_valor, descuento_motivo, total, pagado, folio, abierta_por, cuenta_pedida_at, pedido_numero, origen, created_at';
const COLUMNAS_RENGLON =
  'id, venta_id, nombre, cantidad, precio_unitario, descuento, descuento_tipo, descuento_valor, descuento_motivo, importe, opciones, nota, comanda_id, agregado_por, clave_envio, estado, autorizado_por, cancelado_motivo';

const numeroONulo = (x: unknown) => (x === null || x === undefined ? null : Number(x));
const COLUMNAS_COMANDA = 'id, venta_id, area_preparacion_id, estado, enviada_por, lista_at, created_at';

function venta(v: Venta): Venta {
  return {
    ...v,
    subtotal: Number(v.subtotal),
    descuento: Number(v.descuento),
    descuento_valor: numeroONulo(v.descuento_valor),
    total: Number(v.total),
    pagado: Number(v.pagado),
  };
}

function renglon(r: Renglon): Renglon {
  return {
    ...r,
    precio_unitario: Number(r.precio_unitario),
    descuento: Number(r.descuento),
    descuento_valor: numeroONulo(r.descuento_valor),
    importe: Number(r.importe),
    opciones: (r.opciones ?? []).map((o) => ({ ...o, precio_extra: Number(o.precio_extra) })),
  };
}

// Todas las cuentas abiertas del restaurante, con sus renglones y sus comandas, en el orden en que
// se abrieron y se mandaron.
export async function leerAbiertas(cliente: SupabaseClient, restauranteId: string): Promise<Abiertas> {
  const ventas = await cliente
    .from('ventas')
    .select(COLUMNAS_VENTA)
    .eq('restaurante_id', restauranteId)
    .eq('estado', 'abierta')
    .order('created_at')
    .order('id');
  if (ventas.error) throw ventas.error;
  const ids = ventas.data.map((v) => v.id);
  if (ids.length === 0) return { ventas: [], renglones: [], comandas: [] };

  const [renglones, comandas] = await Promise.all([
    cliente
      .from('venta_items')
      .select(COLUMNAS_RENGLON)
      .eq('restaurante_id', restauranteId)
      .in('venta_id', ids)
      .order('id'),
    cliente
      .from('comandas')
      .select(COLUMNAS_COMANDA)
      .eq('restaurante_id', restauranteId)
      .in('venta_id', ids)
      .order('id'),
  ]);
  if (renglones.error) throw renglones.error;
  if (comandas.error) throw comandas.error;
  return {
    ventas: (ventas.data as Venta[]).map(venta),
    renglones: (renglones.data as Renglon[]).map(renglon),
    comandas: comandas.data as Comanda[],
  };
}

// Las comandas que mandó esta persona a cuentas que ya no están abiertas. En el mostrador se cobra
// antes de mandar (adaptabilidad, encuesta 4), así que la cuenta ya está cerrada cuando la cocina la
// marca, y el aviso de «Lista» tiene que llegar igual (encuesta 10: le suena a quien lo mandó y dice
// el nombre o el número). Trae las que siguen en la cocina y, de las que la lectura anterior traía
// pendientes (`vigiladas`), cómo quedaron; cada una con el nombre de su cuenta y si le queda algo sin
// cancelar (una comanda con todo cancelado no es «Lista»). Las de cuentas abiertas no: esas ya las
// trae leerAbiertas.
export type ComandaFuera = Comanda & { titulo: string; algo: boolean };

export async function leerComandasFuera(
  cliente: SupabaseClient,
  restauranteId: string,
  miembroId: number,
  abiertas: number[],
  vigiladas: number[],
): Promise<ComandaFuera[]> {
  const base = cliente
    .from('comandas')
    .select(COLUMNAS_COMANDA)
    .eq('restaurante_id', restauranteId)
    .eq('enviada_por', miembroId);
  const { data, error } = await (vigiladas.length > 0
    ? base.or(`estado.eq.pendiente,id.in.(${vigiladas.join(',')})`)
    : base.eq('estado', 'pendiente')
  ).order('id');
  if (error) throw error;
  const fuera = (data as Comanda[]).filter((c) => !abiertas.includes(c.venta_id));
  if (fuera.length === 0) return [];

  const [ventas, renglones] = await Promise.all([
    cliente
      .from('ventas')
      .select('id, tipo, mesa_nombre, cliente_nombre, pedido_numero')
      .eq('restaurante_id', restauranteId)
      .in('id', [...new Set(fuera.map((c) => c.venta_id))]),
    cliente
      .from('venta_items')
      .select('comanda_id')
      .eq('restaurante_id', restauranteId)
      .eq('estado', 'activo')
      .in(
        'comanda_id',
        fuera.map((c) => c.id),
      ),
  ]);
  if (ventas.error) throw ventas.error;
  if (renglones.error) throw renglones.error;
  const nombres = new Map(
    (ventas.data as Pick<Venta, 'id' | 'tipo' | 'mesa_nombre' | 'cliente_nombre' | 'pedido_numero'>[]).map((v) => [
      v.id,
      nombreDeCuenta(v),
    ]),
  );
  const conAlgo = new Set((renglones.data as { comanda_id: number | null }[]).map((r) => r.comanda_id));
  return fuera.map((c) => ({ ...c, titulo: nombres.get(c.venta_id) ?? '—', algo: conAlgo.has(c.id) }));
}

// ¿A qué cuenta llegó el envío con esa clave? Lo pregunta quien mandó sin saber si llegó (se cayó
// el internet a medio camino). Si no llegó, null.
export async function cuentaDelEnvio(cliente: SupabaseClient, restauranteId: string, clave: string): Promise<number | null> {
  const { data, error } = await cliente
    .from('venta_items')
    .select('venta_id')
    .eq('restaurante_id', restauranteId)
    .eq('clave_envio', clave)
    .limit(1);
  if (error) throw error;
  return data[0]?.venta_id ?? null;
}

// ─── La cocina ──────────────────────────────────────────────────────────────────────────────

// Lo que lleva cada tarjeta: la comanda, a qué cuenta va y sus renglones.
export type Tarjeta = Comanda & {
  titulo: string; // la mesa, el nombre del cliente o «#27 · Rosa Ramírez»
  tipo: TipoCuenta;
  whatsapp: boolean; // nació de un pedido del menú en línea (parte 6b)
  renglones: Renglon[];
};

export type EnCocina = { pendientes: Tarjeta[]; listas: Tarjeta[] };

// Las pendientes de todas las áreas, de la más vieja a la más nueva (cada pantalla filtra la
// suya y cuenta las de las demás al elegir), y las últimas 10 listas de hoy de esta área, de la
// más reciente a la más vieja. «Hoy» es el día de negocio del restaurante (inicio_del_dia).
export async function inicioDelDia(cliente: SupabaseClient, restauranteId: string): Promise<string> {
  const { data, error } = await cliente.rpc('inicio_del_dia', { p_restaurante_id: restauranteId });
  if (error) throw error;
  return data as string;
}

export async function leerCocina(
  cliente: SupabaseClient,
  restauranteId: string,
  areaId: number | null,
): Promise<EnCocina> {
  const desde = areaId === null ? null : await inicioDelDia(cliente, restauranteId);
  const [pendientes, listas] = await Promise.all([
    cliente
      .from('comandas')
      .select(COLUMNAS_COMANDA)
      .eq('restaurante_id', restauranteId)
      .eq('estado', 'pendiente')
      .order('created_at')
      .order('id'),
    areaId === null || desde === null
      ? Promise.resolve({ data: [] as Comanda[], error: null })
      : cliente
          .from('comandas')
          .select(COLUMNAS_COMANDA)
          .eq('restaurante_id', restauranteId)
          .eq('area_preparacion_id', areaId)
          .eq('estado', 'lista')
          .gte('lista_at', desde)
          .order('lista_at', { ascending: false })
          .order('id', { ascending: false })
          .limit(10),
  ]);
  if (pendientes.error) throw pendientes.error;
  if (listas.error) throw listas.error;
  const todas = [...(pendientes.data as Comanda[]), ...(listas.data as Comanda[])];
  if (todas.length === 0) return { pendientes: [], listas: [] };

  const [ventas, renglones] = await Promise.all([
    cliente
      .from('ventas')
      .select('id, tipo, mesa_nombre, cliente_nombre, pedido_numero, origen')
      .eq('restaurante_id', restauranteId)
      .in('id', [...new Set(todas.map((c) => c.venta_id))]),
    cliente
      .from('venta_items')
      .select(COLUMNAS_RENGLON)
      .eq('restaurante_id', restauranteId)
      .in('comanda_id', todas.map((c) => c.id))
      .order('id'),
  ]);
  if (ventas.error) throw ventas.error;
  if (renglones.error) throw renglones.error;
  const porVenta = new Map(ventas.data.map((v) => [v.id, v]));
  const tarjeta = (c: Comanda): Tarjeta => {
    const v = porVenta.get(c.venta_id);
    return {
      ...c,
      titulo: v ? nombreDeCuenta(v) : '—',
      tipo: (v?.tipo ?? 'mesa') as TipoCuenta,
      whatsapp: v?.origen === 'menu_en_linea',
      renglones: (renglones.data as Renglon[]).filter((r) => r.comanda_id === c.id).map(renglon),
    };
  };
  return { pendientes: (pendientes.data as Comanda[]).map(tarjeta), listas: (listas.data as Comanda[]).map(tarjeta) };
}

// A qué áreas fue una cuenta, en el orden de las áreas: «#12 confirmado · va a Cocina» (adaptabilidad,
// «Lo que decidí yo» 6). Sin comandas, ninguna.
export async function areasDeLaCuenta(cliente: SupabaseClient, restauranteId: string, ventaId: number): Promise<string[]> {
  const comandas = await cliente.from('comandas').select('area_preparacion_id').eq('restaurante_id', restauranteId).eq('venta_id', ventaId);
  if (comandas.error) throw comandas.error;
  const ids = [...new Set(comandas.data.map((c) => c.area_preparacion_id as number))];
  if (ids.length === 0) return [];
  const areas = await cliente.from('areas_preparacion').select('id, nombre').eq('restaurante_id', restauranteId).in('id', ids).order('id');
  if (areas.error) throw areas.error;
  return areas.data.map((a) => a.nombre as string);
}

// A qué áreas irá un pedido del menú en línea al confirmarlo (adaptabilidad: la hoja de Confirmar
// dice a dónde va, como el botón de la cuenta). Por sus productos, su categoría y el área de esa
// categoría hoy; en el orden de las áreas. Vacío: todo se entrega directo y no se manda nada.
export async function areasDelPedido(cliente: SupabaseClient, restauranteId: string, pedidoId: number): Promise<string[]> {
  const renglones = await cliente.from('pedido_items').select('producto_id').eq('restaurante_id', restauranteId).eq('pedido_id', pedidoId);
  if (renglones.error) throw renglones.error;
  const productoIds = [...new Set(renglones.data.map((r) => r.producto_id as number))];
  if (productoIds.length === 0) return [];
  const productos = await cliente.from('productos').select('id, categoria_id').eq('restaurante_id', restauranteId).in('id', productoIds);
  if (productos.error) throw productos.error;
  const categoriaIds = [...new Set(productos.data.map((p) => p.categoria_id as number))];
  const categorias = await cliente.from('categorias').select('id, area_preparacion_id').eq('restaurante_id', restauranteId).in('id', categoriaIds);
  if (categorias.error) throw categorias.error;
  const areaIds = [...new Set(categorias.data.map((c) => c.area_preparacion_id as number | null).filter((a): a is number => a !== null))];
  if (areaIds.length === 0) return [];
  const areas = await cliente.from('areas_preparacion').select('id, nombre').eq('restaurante_id', restauranteId).in('id', areaIds).order('id');
  if (areas.error) throw areas.error;
  return areas.data.map((a) => a.nombre as string);
}

// ─── Lo que cambia, siempre por una función de Postgres ─────────────────────────────────────

// Un «no» ya en español para la caja de error. `sinRed`: no se pudo hablar con el servidor, y
// no se sabe si llegó.
export class FalloPos extends Fallo {
  constructor(
    mensaje: string,
    readonly sinRed = false,
  ) {
    super(mensaje);
  }
}

function fallo(contexto: string, error: unknown): FalloPos {
  console.error(`[pos] ${contexto}:`, error);
  const sinRed = esDeRed(error);
  return new FalloPos(sinRed ? SIN_CONEXION : mensajeDeError(error), sinRed);
}

// Un renglón como lo pide mandar_a_cocina: el producto, cuántos, las opciones (ids) y la nota.
export type RenglonAMandar = { producto_id: number; cantidad: number; opciones: number[]; nota: string };

// A qué cuenta va: la abierta, la de una mesa (abierta o libre) o un pedido nuevo sin mesa. Sin
// nombre, Postgres le da su número del día.
export type Destino = { venta: number } | { mesa: number } | PedidoNuevo;

// Regresa el id de la cuenta. Con la misma clave, Postgres no guarda nada dos veces.
export async function mandarACocina(
  cliente: SupabaseClient,
  restauranteId: string,
  clave: string,
  renglones: RenglonAMandar[],
  destino: Destino,
): Promise<number> {
  const { data, error } = await cliente.rpc('mandar_a_cocina', {
    p_restaurante_id: restauranteId,
    p_clave: clave,
    p_renglones: renglones,
    p_venta_id: 'venta' in destino ? destino.venta : null,
    p_mesa_id: 'mesa' in destino ? destino.mesa : null,
    p_tipo: 'tipo' in destino ? destino.tipo : null,
    p_cliente_nombre: 'tipo' in destino ? destino.nombre.trim() || null : null,
    p_cliente_telefono: 'tipo' in destino && destino.tipo === 'domicilio' ? destino.telefono : null,
    p_cliente_direccion: 'tipo' in destino && destino.tipo === 'domicilio' ? destino.direccion : null,
  });
  if (error) throw fallo('mandar_a_cocina no se pudo', error);
  return data as number;
}

export async function pedirCuenta(cliente: SupabaseClient, ventaId: number): Promise<void> {
  const { error } = await cliente.rpc('pedir_cuenta', { p_venta_id: ventaId });
  if (error) throw fallo('pedir_cuenta no se pudo', error);
}

export async function cambiarMesa(cliente: SupabaseClient, ventaId: number, mesaId: number): Promise<void> {
  const { error } = await cliente.rpc('cambiar_mesa', { p_venta_id: ventaId, p_mesa_id: mesaId });
  if (error) throw fallo('cambiar_mesa no se pudo', error);
}

export async function juntarMesas(cliente: SupabaseClient, ventaId: number, destinoId: number): Promise<void> {
  const { error } = await cliente.rpc('juntar_mesas', { p_venta_id: ventaId, p_destino_id: destinoId });
  if (error) throw fallo('juntar_mesas no se pudo', error);
}

export async function marcarComanda(cliente: SupabaseClient, comandaId: number, lista: boolean): Promise<void> {
  const { error } = await cliente.rpc('marcar_comanda', { p_comanda_id: comandaId, p_lista: lista });
  if (error) throw fallo('marcar_comanda no se pudo', error);
}

// ─── Lo que pide PIN (parte 4c) ─────────────────────────────────────────────────────────────

// Cancelar un renglón (o parte), una cuenta o un pago, y los descuentos. Todo lleva motivo.
export type Pedido =
  | { funcion: 'cancelar_renglon'; datos: { p_renglon_id: number; p_cantidad: number; p_motivo: string } }
  | { funcion: 'cancelar_cuenta'; datos: { p_venta_id: number; p_motivo: string } }
  | { funcion: 'cancelar_pago'; datos: { p_pago_id: number; p_motivo: string } }
  | {
      funcion: 'descontar';
      datos: { p_venta_id: number; p_renglon_id: number | null; p_tipo: TipoDescuento; p_valor: number; p_motivo: string };
    };

// Un PIN equivocado no es un error: Postgres lo contesta así para que el intento quede contado.
export type Autorizacion =
  | { ok: true; autoriza: number; reabierta: boolean }
  | { ok: false; motivo: 'pin'; quedan: number }
  | { ok: false; motivo: 'bloqueado'; hasta: string | null };

function autorizacion(r: Record<string, unknown>): Autorizacion {
  if (r.ok) return { ok: true, autoriza: Number(r.autoriza), reabierta: r.reabierta === true };
  if (r.motivo === 'bloqueado') return { ok: false, motivo: 'bloqueado', hasta: (r.hasta as string | null) ?? null };
  return { ok: false, motivo: 'pin', quedan: Number(r.quedan) };
}

// Quien pide es de la caja o gerente: Postgres directo, sin PIN; queda a su nombre.
export async function pedirDirecto(cliente: SupabaseClient, pedido: Pedido): Promise<Autorizacion> {
  const { data, error } = await cliente.rpc(pedido.funcion, pedido.datos);
  if (error) throw fallo(`${pedido.funcion} no se pudo`, error);
  return autorizacion(data as Record<string, unknown>);
}

// Pepe pide y Lupita pone su PIN en el celular de Pepe: va al Worker (POST /pos/autorizar) con la
// sesión de Pepe. El Worker mezcla el PIN con su llave y llama a la misma función de Postgres,
// que revisa el PIN y aplica el cambio en el mismo paso.
export async function pedirConPin(cliente: SupabaseClient, pedido: Pedido, autoriza: number, pin: string): Promise<Autorizacion> {
  const { data, error } = await cliente.auth.getSession();
  if (error || !data.session) {
    console.error('[pos] no hay sesión para pedir la autorización:', error);
    throw new FalloPos('Tu sesión venció. Vuelve a entrar.');
  }
  let respuesta: Response;
  try {
    respuesta = await fetch(`${import.meta.env.VITE_API_URL}/pos/autorizar`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${data.session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ funcion: pedido.funcion, datos: pedido.datos, autoriza, pin }),
    });
  } catch (falla) {
    console.error(`[pos] ${pedido.funcion}: no se pudo hablar con el Worker:`, falla);
    throw new FalloPos(SIN_CONEXION, true);
  }
  const cuerpo = await respuesta.json().catch(() => null);
  if (!respuesta.ok) {
    console.error(`[pos] ${pedido.funcion}: el Worker dijo ${respuesta.status}:`, cuerpo);
    throw new FalloPos(typeof cuerpo?.error === 'string' ? sinCentavos(cuerpo.error) : ALGO_SALIO_PANEL);
  }
  return autorizacion(cuerpo as Record<string, unknown>);
}

// Quitar un descuento no pide PIN: la cuenta sube. Sin renglón, el de toda la cuenta.
export async function quitarDescuento(cliente: SupabaseClient, ventaId: number, renglonId: number | null): Promise<void> {
  const { error } = await cliente.rpc('quitar_descuento', { p_venta_id: ventaId, p_renglon_id: renglonId });
  if (error) throw fallo('quitar_descuento no se pudo', error);
}

// «10 %», «Regalo» (100 %) o «$50».
export function textoDescuento(tipo: TipoDescuento, valor: number): string {
  if (tipo === 'pesos') return dinero(valor);
  return valor === 100 ? 'Regalo' : `${valor} %`;
}

// En cuánto quedaría la cuenta, solo para verlo en la hoja y no dejar pedir lo que no cabe: es la
// cuenta de privado.descuento y de cancelar_renglon y descontar, en centavos. Al aplicar, quien
// decide es Postgres.
const centavos = (n: number) => Math.round(n * 100);

function descuentoEn(base: number, tipo: TipoDescuento | null, valor: number | null): number {
  if (tipo === null || valor === null) return 0;
  if (tipo === 'porcentaje') return Math.round((base * centavos(valor)) / 10000);
  return Math.min(centavos(valor), base);
}

function totalCon(v: Venta, subtotal: number): number {
  return subtotal - descuentoEn(subtotal, v.descuento_tipo, v.descuento_valor);
}

// Cancelar `cuantos` de un renglón: lo que se quita del renglón y en cuánto queda la cuenta.
export function siSeCancela(v: Venta, r: Renglon, cuantos: number): { menos: number; queda: number } {
  const resta = (r.cantidad - cuantos) * centavos(r.precio_unitario);
  const queda = resta - descuentoEn(resta, r.descuento_tipo, r.descuento_valor);
  const subtotal = centavos(v.subtotal) - centavos(r.importe) + queda;
  return { menos: (centavos(r.importe) - queda) / 100, queda: totalCon(v, subtotal) / 100 };
}

// Un descuento a un renglón (o a toda la cuenta, sin renglón): de cuánto es, sobre qué y en
// cuánto queda la cuenta.
export function siSeDescuenta(
  v: Venta,
  r: Renglon | null,
  tipo: TipoDescuento,
  valor: number,
): { descuento: number; base: number; queda: number } {
  if (r) {
    const base = r.cantidad * centavos(r.precio_unitario);
    const d = descuentoEn(base, tipo, valor);
    const subtotal = centavos(v.subtotal) - centavos(r.importe) + base - d;
    return { descuento: d / 100, base: base / 100, queda: totalCon(v, subtotal) / 100 };
  }
  const base = centavos(v.subtotal);
  const d = descuentoEn(base, tipo, valor);
  return { descuento: d / 100, base: base / 100, queda: (base - d) / 100 };
}

// ─── El tiempo real ─────────────────────────────────────────────────────────────────────────

// Avisa cuando cambia algo de esas tablas en este restaurante (Supabase revisa RLS en cada evento,
// con la sesión de quien escucha). Al conectarse, y al reconectarse tras perder la señal, también
// avisa: lo que pasó mientras tanto no llegó como evento. Regresa cómo dejar de escuchar.
export function escuchar(
  cliente: SupabaseClient,
  restauranteId: string,
  tablas: ('ventas' | 'venta_items' | 'comandas' | 'pagos' | 'turnos' | 'pedidos_en_linea' | 'anuncios')[],
  alCambiar: () => void,
): () => void {
  const canal = cliente.channel(`pos-${restauranteId}-${crypto.randomUUID()}`);
  for (const tabla of tablas) {
    canal.on(
      'postgres_changes',
      { event: '*', schema: 'public', table: tabla, filter: `restaurante_id=eq.${restauranteId}` },
      alCambiar,
    );
  }
  canal.subscribe((estado, error) => {
    if (estado === 'SUBSCRIBED') alCambiar();
    else if (estado === 'CHANNEL_ERROR' || estado === 'TIMED_OUT') {
      console.error(`[pos] el tiempo real se cortó (${estado}); se reconecta solo:`, error);
    }
  });
  return () => {
    cliente.removeChannel(canal).catch((e) => console.error('[pos] no se pudo cerrar el tiempo real:', e));
  };
}

// ─── Lo que vive en este aparato ────────────────────────────────────────────────────────────

// Lo anotado y todavía no mandado de una cuenta (libreta 5: vive solo en este aparato, aunque se
// cierre la app). `clave` es la del próximo envío: cambia con cada cambio del borrador, así que
// pulsar dos veces lo mismo no guarda dos veces. `enDuda`: un envío que se fue sin internet de
// regreso; hasta saber si llegó, se recuerda qué llevaba.
export type LineaBorrador = { producto_id: number; nombre: string; cantidad: number; opciones: number[]; nota: string };
export type PedidoNuevo = { tipo: Exclude<TipoCuenta, 'mesa'>; nombre: string; telefono: string; direccion: string };

// El último tipo de pedido nuevo que se usó en este aparato («Lo que decidí yo» 1 de la adaptabilidad).
const LLAVE_TIPO = 'fragmentless-pos-tipo';
const TIPOS_NUEVO: PedidoNuevo['tipo'][] = ['comer_aqui', 'para_llevar', 'domicilio'];

export function leerTipoPedido(): PedidoNuevo['tipo'] {
  try {
    const t = localStorage.getItem(LLAVE_TIPO) as PedidoNuevo['tipo'] | null;
    return t && TIPOS_NUEVO.includes(t) ? t : 'comer_aqui';
  } catch (error) {
    console.error('[pos] no se pudo leer el último tipo de pedido:', error);
    return 'comer_aqui';
  }
}

export function guardarTipoPedido(tipo: PedidoNuevo['tipo']) {
  try {
    localStorage.setItem(LLAVE_TIPO, tipo);
  } catch (error) {
    console.error('[pos] no se pudo guardar el tipo de pedido:', error);
  }
}

// Cuántas mesas tenía la sucursal la última vez que se abrió el punto de venta en este navegador (regla «Los
// esqueletos»): a lo ancho, mientras lee la primera vez, sale el esqueleto de las mesas (con esas) o el del menú (0), y
// sin mesas el pedido nuevo ya está listo. null = nunca se abrió aquí.
const prefijoMesas = 'fragmentless-pos-mesas-';

export function mesasDeLaUltimaVez(restauranteId: string): number | null {
  try {
    const n = JSON.parse(localStorage.getItem(prefijoMesas + restauranteId) ?? 'null');
    return typeof n === 'number' && Number.isFinite(n) && n >= 0 ? Math.round(n) : null;
  } catch (error) {
    console.error('[pos] no se pudo leer cuántas mesas había:', error);
    return null;
  }
}

export function recordarMesas(restauranteId: string, n: number) {
  try {
    localStorage.setItem(prefijoMesas + restauranteId, JSON.stringify(n));
  } catch (error) {
    console.error('[pos] no se pudo recordar cuántas mesas hay:', error);
  }
}

// Lo que dice el botón de la cuenta (adaptabilidad, encuesta 7): a dónde va lo anotado, en el orden de
// las áreas; con tres o más, «Mandar a cocina»; si nada va a una pantalla, «Anotar».
export function textoMandar(areas: string[]): string {
  if (areas.length === 0) return 'Anotar';
  if (areas.length >= 3) return 'Mandar a cocina';
  return `Mandar a ${areas.join(' y ')}`;
}
export type Borrador = {
  clave: string;
  lineas: LineaBorrador[];
  nuevo?: PedidoNuevo;
  enDuda?: { clave: string; lineas: LineaBorrador[] };
};

// Cada cuenta guarda su borrador con una llave: «m4» la mesa 4 (abierta o libre), «v12» la cuenta
// 12 sin mesa, «n…» un para llevar que todavía no se manda. `sinVer`: las cuentas cuya comanda
// marcó «Lista» la cocina y que aquí no se han abierto desde entonces.
export type Guardado = { borradores: Record<string, Borrador>; sinVer: number[] };

function llave(restauranteId: string, miembroId: number) {
  return `fragmentless-pos-${restauranteId}-${miembroId}`;
}

export function leerGuardado(restauranteId: string, miembroId: number): Guardado {
  try {
    const texto = localStorage.getItem(llave(restauranteId, miembroId));
    if (!texto) return { borradores: {}, sinVer: [] };
    const g = JSON.parse(texto) as Partial<Guardado>;
    return { borradores: g.borradores ?? {}, sinVer: g.sinVer ?? [] };
  } catch (error) {
    console.error('[pos] no se pudo leer lo anotado en este aparato:', error);
    return { borradores: {}, sinVer: [] };
  }
}

export function guardar(restauranteId: string, miembroId: number, g: Guardado): void {
  try {
    localStorage.setItem(llave(restauranteId, miembroId), JSON.stringify(g));
  } catch (error) {
    console.error('[pos] no se pudo guardar lo anotado en este aparato:', error);
  }
}

// Dos líneas iguales (mismo producto, mismas opciones, misma nota) se suman en una.
export function mismaLinea(a: LineaBorrador, b: { producto_id: number; opciones: number[]; nota: string }): boolean {
  return (
    a.producto_id === b.producto_id &&
    a.nota === b.nota &&
    [...a.opciones].sort((x, y) => x - y).join(',') === [...b.opciones].sort((x, y) => x - y).join(',')
  );
}

// Lo que queda del borrador si el envío en duda sí llegó: se le resta lo que llevaba.
export function restar(lineas: LineaBorrador[], mandadas: LineaBorrador[]): LineaBorrador[] {
  const quedan = lineas.map((l) => ({ ...l }));
  for (const m of mandadas) {
    const igual = quedan.find((l) => mismaLinea(l, m));
    if (igual) igual.cantidad -= m.cantidad;
  }
  return quedan.filter((l) => l.cantidad > 0);
}
