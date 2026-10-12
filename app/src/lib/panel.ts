// Lo que lee y escribe el panel de Fragmentless. Todo pasa por funciones de Postgres que
// primero revisan que quien llama esté en plataforma_admins: las de lectura (migraciones
// panel_lectura y panel_hoy) ya traen todo contado, y las 4 de escritura de los restaurantes
// (migración plataforma) y las 5 de los distribuidores (migración distribuidores) son lo único
// que cambia datos. La app no cuenta nada.
import { esDeRed, mensajeDeError } from './errores';
import { supabase } from './supabase';

// Las 3 cifras de Inicio (panel_resumen).
export type Resumen = {
  total: number;
  funcionan: number;
  vencen_pronto: number;
  vencen_hoy: number;
  sin_funcionar: number;
  vencidos: number;
  pausados: number;
};

// Un mes de Altas por mes (panel_altas_por_mes): los últimos 6, el actual al final.
export type AltaMes = { mes: string; altas: number; total_6_meses: number };

// Una fila de Clientes (panel_clientes), ya ordenada por fecha de fin.
export type Cliente = {
  id: string;
  nombre: string;
  slug: string;
  licencia_activa: boolean;
  licencia_inicio: string | null;
  licencia_fin: string | null;
  dias_restantes: number | null;
  estado: 'vigente' | 'vence_pronto' | 'vencida' | 'pausada';
  distribuidor_id: number | null;
  distribuidor_nombre: string | null;
};

// Una fila de Tus distribuidores (panel_distribuidores).
export type Distribuidor = {
  id: number;
  nombre: string;
  telefono: string | null;
  correo: string | null;
  activo: boolean;
  cuenta_ligada: boolean;
  clientes: number;
};

// Cada parte del panel se lee por separado: si una falla, las demás se ven igual.
export type Lectura<T> = { ok: true; datos: T } | { ok: false; mensaje: string; deRed: boolean };

export type DatosPanel = {
  resumen: Lectura<Resumen>;
  altas: Lectura<AltaMes[]>;
  clientes: Lectura<Cliente[]>;
  distribuidores: Lectura<Distribuidor[]>;
};

async function leer<T>(funcion: string): Promise<Lectura<T>> {
  const { data, error } = await supabase.rpc(funcion);
  if (error) {
    console.error(`[panel] no se pudo leer ${funcion}:`, error);
    return { ok: false, mensaje: mensajeDeError(error), deRed: esDeRed(error) };
  }
  return { ok: true, datos: data as T };
}

// Todo lo que muestran Inicio y Clientes, de una vez: al abrir, con Actualizar y después de
// cada cambio.
export async function leerPanel(): Promise<DatosPanel> {
  const [resumen, altas, clientes, distribuidores] = await Promise.all([
    leer<Resumen[]>('panel_resumen'),
    leer<AltaMes[]>('panel_altas_por_mes'),
    leer<Cliente[]>('panel_clientes'),
    leer<Distribuidor[]>('panel_distribuidores'),
  ]);
  return {
    resumen: resumen.ok ? { ok: true, datos: resumen.datos[0] } : resumen,
    altas,
    clientes,
    distribuidores,
  };
}

// El día de hoy en la hora de México ('aaaa-mm-dd'), para la fecha de inicio que trae puesta
// «Dar de alta». Si no se puede leer, la ventana deja el campo vacío.
export async function leerHoy(): Promise<string | null> {
  const { data, error } = await supabase.rpc('panel_hoy');
  if (error) {
    console.error('[panel] no se pudo leer panel_hoy:', error);
    return null;
  }
  return data as string;
}

// ─── Las funciones que cambian datos ──────────────────────────────────────────
// Cada una regresa lo que devuelve la función, o el mensaje para la caja de error.

export type Resultado<T> = { ok: true; valor: T } | { ok: false; mensaje: string };

async function escribir<T>(funcion: string, argumentos: Record<string, unknown>): Promise<Resultado<T>> {
  const { data, error } = await supabase.rpc(funcion, argumentos);
  if (error) {
    console.error(`[panel] ${funcion} no se pudo:`, error);
    return { ok: false, mensaje: mensajeDeError(error) };
  }
  return { ok: true, valor: data as T };
}

// Nace con la licencia prendida; el fin lo calcula Postgres con los meses. Regresa su id.
export function altaRestaurante(nombre: string, slug: string, inicio: string | null, meses: number | null) {
  return escribir<string>('alta_restaurante', {
    p_nombre: nombre,
    p_slug: slug,
    p_inicio: inicio,
    p_meses: meses,
  });
}

// La cuenta ya debe existir (Authentication → Add user). Regresa el id de su fila en miembros.
export function ligarGerente(restauranteId: string, correo: string, nombre: string) {
  return escribir<number>('ligar_gerente', {
    p_restaurante_id: restauranteId,
    p_correo: correo,
    p_nombre: nombre,
  });
}

// Regresa la nueva fecha de fin ('aaaa-mm-dd').
export function extenderLicencia(restauranteId: string, meses: number | null) {
  return escribir<string>('extender_licencia', { p_restaurante_id: restauranteId, p_meses: meses });
}

// Guarda la licencia tal cual: prendida o pausada, con sus fechas (vacía = sin fecha).
export function fijarLicencia(restauranteId: string, activa: boolean, inicio: string | null, fin: string | null) {
  return escribir<null>('fijar_licencia', {
    p_restaurante_id: restauranteId,
    p_activa: activa,
    p_inicio: inicio,
    p_fin: fin,
  });
}

// ─── Las 5 de los distribuidores (migración distribuidores, paso 2) ──────────
// Postgres quita los espacios de más y guarda vacío un teléfono o un correo en blanco.

// Nace activo, sin cuenta y sin clientes. Regresa su id.
export function altaDistribuidor(nombre: string, telefono: string, correo: string) {
  return escribir<number>('alta_distribuidor', { p_nombre: nombre, p_telefono: telefono, p_correo: correo });
}

// La cuenta ya debe existir (Authentication → Add user) y no puede ser de Fragmentless ni de
// nadie en un restaurante: una cuenta, un panel.
export function ligarDistribuidor(distribuidorId: number, correo: string) {
  return escribir<null>('ligar_distribuidor', { p_distribuidor_id: distribuidorId, p_correo: correo });
}

export function editarDistribuidor(distribuidorId: number, nombre: string, telefono: string, correo: string) {
  return escribir<null>('editar_distribuidor', {
    p_distribuidor_id: distribuidorId,
    p_nombre: nombre,
    p_telefono: telefono,
    p_correo: correo,
  });
}

// Asignar un cliente (aunque hoy sea de otro distribuidor) o, con null, quitárselo: pasa a directo.
export function asignarDistribuidor(restauranteId: string, distribuidorId: number | null) {
  return escribir<null>('asignar_distribuidor', {
    p_restaurante_id: restauranteId,
    p_distribuidor_id: distribuidorId,
  });
}

// Dar de baja (false) o reactivar (true). Con clientes no se da de baja.
export function fijarDistribuidorActivo(distribuidorId: number, activo: boolean) {
  return escribir<null>('fijar_distribuidor_activo', { p_distribuidor_id: distribuidorId, p_activo: activo });
}

// En negritas, lo que ya venció o vence hoy (Clientes, Vencen pronto y los clientes de cada
// distribuidor).
export function urgente(c: Cliente): boolean {
  return c.estado === 'vencida' || (c.estado === 'vence_pronto' && c.dias_restantes === 0);
}
