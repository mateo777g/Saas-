// Las vistas del panel del distribuidor, para la búsqueda y las columnas de su Inicio (8 nov 2026, como el Inicio de
// Fragmentless). No tiene acciones: solo ve. La búsqueda no lee la base: solo esto. Recientes son las últimas vistas
// abiertas en este navegador; «Cerrar sesión» las borra (lib/supabase.ts, todo lo que empieza con
// fragmentless-recientes-).

import type { RenglonBusqueda } from '../diseno/Buscador.svelte';

export type VistaDistribuidor = 'inicio' | 'clientes' | 'ajustes';

export const VISTAS: Record<VistaDistribuidor, { texto: string; icono: string }> = {
  inicio: { texto: 'Inicio', icono: 'r-inicio' },
  clientes: { texto: 'Clientes', icono: 'r-tienda' },
  ajustes: { texto: 'Ajustes', icono: 'r-ajustes' },
};

// Los renglones de su búsqueda: la grande de Inicio y la que se abre en cualquier otra vista (BuscarAqui).
export function renglonesDeBusqueda(alIr: (vista: VistaDistribuidor) => void) {
  const deVista = (v: VistaDistribuidor): RenglonBusqueda => ({
    clave: v,
    texto: VISTAS[v].texto,
    icono: VISTAS[v].icono,
    alPicar: () => alIr(v),
  });
  return { deVista, vistas: (['clientes', 'ajustes'] as const).map(deVista) };
}

const LLAVE = 'fragmentless-recientes-distribuidor';
const CUANTOS = 5;

function esVista(valor: unknown): valor is VistaDistribuidor {
  return typeof valor === 'string' && valor in VISTAS;
}

export function leerRecientes(): VistaDistribuidor[] {
  try {
    const crudo = localStorage.getItem(LLAVE);
    if (!crudo) return [];
    const lista: unknown = JSON.parse(crudo);
    if (!Array.isArray(lista)) return [];
    return lista.filter((v): v is VistaDistribuidor => esVista(v) && v !== 'inicio').slice(0, CUANTOS);
  } catch (error) {
    console.error('[vistas] no se pudieron leer las recientes de este navegador:', error);
    return [];
  }
}

// La vista que se acaba de abrir va hasta arriba. Inicio no cuenta: es donde se ven.
export function anotarReciente(vista: VistaDistribuidor): void {
  if (vista === 'inicio') return;
  const lista = [vista, ...leerRecientes().filter((v) => v !== vista)].slice(0, CUANTOS);
  try {
    localStorage.setItem(LLAVE, JSON.stringify(lista));
  } catch (error) {
    console.error('[vistas] no se pudo recordar la vista reciente:', error);
  }
}
