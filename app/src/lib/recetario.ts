// El recetario (19 nov 2026; planes/trabajo/recetario/, maqueta DFVTWEB3eZBEKctyxWjGjg v1): cómo se hace cada platillo
// y cada preparación, con sus pasos y sus fotos. Lo leen el cuarto botón «Recetario» de Inventario (el gerente, que
// también lo escribe) y la pestaña «Recetario» de la cocina y la caja. Lo que lleva no se escribe aquí: sale de la receta
// (lo que se resta), y el recetario no resta nada. Cada función recibe el cliente de Supabase, como lib/inventario.ts,
// para que el panel y el aparato la compartan: por eso aquí no entra lib/supabase.ts (ni lib/fotos.ts, que la trae).
//
// Las funciones de Postgres están en supabase/migrations/20261119220000_recetario.sql; lo que regresa cada una, en
// planes/trabajo/recetario/migracion.md («Lo que regresan»). La cocina y la caja solo reciben lo que tiene pasos.
import type { SupabaseClient } from '@supabase/supabase-js';
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { cantidad, type Unidad } from './inventario';

const R2_PUBLICO = import.meta.env.VITE_R2_PUBLICO;

// Hasta 20 pasos de hasta 300 letras (encuesta 4); la base dice lo mismo.
export const MAXIMO_PASOS = 20;
export const MAXIMO_LETRAS = 300;

// La dirección pública de una foto de R2 (la de lib/fotos.ts, que el aparato no puede importar).
export function urlDe(ruta: string | null): string | null {
  return ruta ? `${R2_PUBLICO}/${ruta}` : null;
}

// ─── Los cuadros ────────────────────────────────────────────────────────────────────────────

// Un cuadro: un platillo de Mi menú o una preparación, con su foto (la de cómo se sirve o, en un platillo, la de Mi menú;
// vacía = el cuadro negro) y cuántos pasos tiene (0 = «Sin escribir»).
export type Cuadro = { id: number; nombre: string; foto: string | null; pasos: number };
export type CategoriaRecetario = { id: number; nombre: string; icono: string; platillos: Cuadro[] };
export type Cuadros = { categorias: CategoriaRecetario[]; preparaciones: Cuadro[] };

// De qué es un recetario: un platillo (su producto) o una preparación.
export type De = { tipo: 'platillo' | 'preparacion'; id: number };

export async function leerCuadros(cliente: SupabaseClient, restauranteId: string): Promise<Cuadros> {
  const { data, error } = await cliente.rpc('recetario', { p_restaurante_id: restauranteId });
  if (error) throw error;
  return (data as Cuadros | null) ?? { categorias: [], preparaciones: [] };
}

// Cuántos hay y cuántos faltan por escribir (el chip «9 sin escribir»).
export function contar(c: Cuadros): { total: number; sinEscribir: number } {
  const todos = [...c.categorias.flatMap((x) => x.platillos), ...c.preparaciones];
  return { total: todos.length, sinEscribir: todos.filter((x) => x.pasos === 0).length };
}

// ─── La página ──────────────────────────────────────────────────────────────────────────────

// Un renglón de lo que lleva, como está escrito en la receta: «30 ml de Salsa verde». Si es una preparación, su id y si
// su recetario tiene pasos (en la cocina solo esa se abre).
export type Lleva = { nombre: string; cantidad: number; unidad: Unidad; preparacion_id: number | null; con_pasos: boolean | null };
export type OpcionQueLleva = { grupo: string; nombre: string; lleva: Lleva[] };
export type Paso = { orden: number; texto: string; imagen_ruta: string | null };

export type Pagina = {
  tipo: 'platillo' | 'preparacion';
  id: number;
  nombre: string;
  categoria: string | null;
  rinde: number | null; // en una preparación: cuánto sale (1 l)
  unidad: Unidad | null;
  foto: string | null; // la que se ve: la de cómo se sirve o la de Mi menú
  imagen_ruta: string | null; // la propia, para «Editar»
  foto_de_mi_menu: string | null;
  lleva: Lleva[];
  opciones: OpcionQueLleva[];
  pasos: Paso[];
};

// La página, o null si ya no está (o, en la cocina y la caja, si se quedó sin pasos).
export async function leerPagina(cliente: SupabaseClient, restauranteId: string, de: De): Promise<Pagina | null> {
  const { data, error } = await cliente.rpc('pagina_recetario', {
    p_restaurante_id: restauranteId,
    p_producto_id: de.tipo === 'platillo' ? de.id : null,
    p_preparacion_id: de.tipo === 'preparacion' ? de.id : null,
  });
  if (error) throw error;
  return (data as Pagina | null) ?? null;
}

// ─── «Para más porciones» ───────────────────────────────────────────────────────────────────

// Una cantidad multiplicada, escrita como el inventario, pero sin mil gramos ni mil mililitros: 2,000 g sale «2 kg» y
// 1,500 ml «1.5 l» («Lo que decidí yo» 4 de las encuestas).
export function cantidadPorciones(n: number, u: Unidad): string {
  if (u === 'g' && n >= 1000) return cantidad(n / 1000, 'kg');
  if (u === 'ml' && n >= 1000) return cantidad(n / 1000, 'l');
  return cantidad(n, u);
}

// Lo que se escribió en la caja de «Para más porciones», como número (con coma o punto); null si no es un número > 0.
export function leerPorciones(texto: string): number | null {
  const n = Number(texto.trim().replace(',', '.'));
  return Number.isFinite(n) && n > 0 ? n : null;
}

// ─── Guardar (solo el gerente) ──────────────────────────────────────────────────────────────

// Un paso para guardar: su texto y la ruta de su foto (vacía = sin foto), en orden.
export type PasoNuevo = { texto: string; imagen_ruta: string | null };

// Guarda el recetario entero: la foto de cómo se sirve (null = sin foto propia) y los pasos. Regresa cuántos quedaron.
export async function guardarRecetario(
  cliente: SupabaseClient,
  restauranteId: string,
  de: De,
  imagenRuta: string | null,
  pasos: PasoNuevo[],
): Promise<number> {
  const { data, error } = await cliente.rpc('guardar_recetario', {
    p_restaurante_id: restauranteId,
    p_imagen_ruta: imagenRuta,
    p_pasos: pasos,
    p_producto_id: de.tipo === 'platillo' ? de.id : null,
    p_preparacion_id: de.tipo === 'preparacion' ? de.id : null,
  });
  if (error) {
    console.error('[recetario] guardar_recetario no se pudo:', error);
    throw new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
  }
  return data as number;
}
