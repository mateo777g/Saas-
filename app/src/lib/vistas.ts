// Las vistas y las acciones del panel del gerente, para la búsqueda y las columnas de Inicio (rediseño
// del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D). La búsqueda no lee la base: solo esto.
// Recientes son las últimas 5 vistas abiertas, en este navegador y por sucursal; «Cerrar sesión» las borra
// (lib/supabase.ts).

export type VistaGerente =
  | 'inicio'
  | 'pedidos'
  | 'mesas'
  | 'cortes'
  | 'restaurante'
  | 'menu-en-linea'
  | 'menu'
  | 'equipo'
  | 'agente'
  | 'crear'
  | 'biblioteca'
  | 'ayuda'
  | 'ajustes';

// La ventana que se abre al llegar a la vista.
export type NuevoAlEntrar = 'producto' | 'mesa' | 'empleado';

export type Destino = { vista: VistaGerente | 'caja'; nuevo?: NuevoAlEntrar };

type DatosVista = { texto: string; grupo?: string; icono: string };

export const VISTAS: Record<VistaGerente, DatosVista> = {
  inicio: { texto: 'Inicio', icono: 'r-inicio' },
  pedidos: { texto: 'Pedidos', grupo: 'Operación', icono: 'r-bolsa' },
  mesas: { texto: 'Mesas', grupo: 'Operación', icono: 'r-mesas' },
  cortes: { texto: 'Cortes y reportes', grupo: 'Operación', icono: 'r-corte' },
  restaurante: { texto: 'Tu restaurante', grupo: 'Tu negocio', icono: 'r-tienda' },
  'menu-en-linea': { texto: 'Tu menú en línea', grupo: 'Tu negocio', icono: 'r-celular' },
  menu: { texto: 'Mi menú', grupo: 'Tu negocio', icono: 'r-menu' },
  equipo: { texto: 'Empleados', grupo: 'Tu negocio', icono: 'r-usuarios' },
  agente: { texto: 'Agente IA', grupo: 'IA y contenido', icono: 'r-ia' },
  crear: { texto: 'Crear anuncios', grupo: 'IA y contenido', icono: 'r-crear' },
  biblioteca: { texto: 'Mi biblioteca', grupo: 'IA y contenido', icono: 'r-biblio' },
  // No es una vista: abre el WhatsApp de Fragmentless. Sale en la búsqueda, pero nunca en Recientes.
  ayuda: { texto: 'Ayuda', icono: 'r-ayuda' },
  ajustes: { texto: 'Ajustes', icono: 'r-ajustes' },
};

export const ACCIONES: { texto: string; de: string; icono: string; destino: Destino }[] = [
  { texto: 'Agregar producto', de: 'Mi menú', icono: 'r-producto', destino: { vista: 'menu', nuevo: 'producto' } },
  { texto: 'Agregar mesa', de: 'Mesas', icono: 'r-mas', destino: { vista: 'mesas', nuevo: 'mesa' } },
  { texto: 'Dar de alta a un empleado', de: 'Empleados', icono: 'r-usuarios', destino: { vista: 'equipo', nuevo: 'empleado' } },
  { texto: 'Crear anuncio', de: 'Crear anuncios', icono: 'r-crear', destino: { vista: 'crear' } },
  { texto: 'Ver el corte de hoy', de: 'Cortes y reportes', icono: 'r-corte', destino: { vista: 'cortes' } },
  { texto: 'Abrir la caja', de: 'Accesos', icono: 'r-billete', destino: { vista: 'caja' } },
  { texto: 'Pausar pedidos', de: 'Pedidos', icono: 'r-bolsa', destino: { vista: 'pedidos' } },
];

const PREFIJO = 'fragmentless-recientes-';
const CUANTOS = 5;

export function esVista(valor: string): valor is VistaGerente {
  return valor in VISTAS;
}

export function leerRecientes(restauranteId: string): VistaGerente[] {
  try {
    const crudo = localStorage.getItem(PREFIJO + restauranteId);
    if (!crudo) return [];
    const lista: unknown = JSON.parse(crudo);
    if (!Array.isArray(lista)) return [];
    return lista.filter((v): v is VistaGerente => typeof v === 'string' && esVista(v) && v !== 'inicio').slice(0, CUANTOS);
  } catch (error) {
    console.error('[vistas] no se pudieron leer las recientes de este navegador:', error);
    return [];
  }
}

// La vista que se acaba de abrir va hasta arriba. Inicio no cuenta: es donde se ven.
export function anotarReciente(restauranteId: string, vista: string): void {
  if (!esVista(vista) || vista === 'inicio') return;
  const lista = [vista, ...leerRecientes(restauranteId).filter((v) => v !== vista)].slice(0, CUANTOS);
  try {
    localStorage.setItem(PREFIJO + restauranteId, JSON.stringify(lista));
  } catch (error) {
    console.error('[vistas] no se pudo recordar la vista reciente:', error);
  }
}
