// Las vistas y las acciones del panel de Fragmentless, para su búsqueda y las columnas de su Inicio
// (maqueta 4Ryyf9E7u4vsDs57PdkAnz). La búsqueda no lee la base: solo esto. Recientes son las últimas 5
// vistas abiertas en este navegador; «Cerrar sesión» las borra (lib/supabase.ts).

// Decidido el 5 de noviembre de 2026: solo existe esta cuenta y no tiene Perfil.
export const MI_NOMBRE = 'Mateo';

export type VistaPanel = 'inicio' | 'clientes' | 'distribuidores' | 'estilos' | 'ajustes';

// La ventana que se abre al elegir el atajo.
export type NuevoAlEntrar = 'alta' | 'alta-distribuidor' | 'estilo';

export type DestinoPanel = { vista: VistaPanel; nuevo?: NuevoAlEntrar };

export const VISTAS: Record<VistaPanel, { texto: string; icono: string }> = {
  inicio: { texto: 'Inicio', icono: 'r-inicio' },
  clientes: { texto: 'Clientes', icono: 'r-tienda' },
  distribuidores: { texto: 'Distribuidores', icono: 'r-usuarios' },
  estilos: { texto: 'Estilos', icono: 'r-biblio' },
  ajustes: { texto: 'Ajustes', icono: 'r-ajustes' },
};

export const ACCIONES: { texto: string; de: string; icono: string; destino: DestinoPanel }[] = [
  { texto: 'Dar de alta', de: 'Clientes', icono: 'r-mas', destino: { vista: 'clientes', nuevo: 'alta' } },
  { texto: 'Nuevo distribuidor', de: 'Distribuidores', icono: 'r-usuarios', destino: { vista: 'distribuidores', nuevo: 'alta-distribuidor' } },
  { texto: 'Nuevo estilo', de: 'Estilos', icono: 'r-biblio', destino: { vista: 'estilos', nuevo: 'estilo' } },
];

const LLAVE = 'fragmentless-recientes-panel';
const CUANTOS = 5;

function esVista(valor: unknown): valor is VistaPanel {
  return typeof valor === 'string' && valor in VISTAS;
}

export function leerRecientes(): VistaPanel[] {
  try {
    const crudo = localStorage.getItem(LLAVE);
    if (!crudo) return [];
    const lista: unknown = JSON.parse(crudo);
    if (!Array.isArray(lista)) return [];
    return lista.filter((v): v is VistaPanel => esVista(v) && v !== 'inicio').slice(0, CUANTOS);
  } catch (error) {
    console.error('[vistas] no se pudieron leer las recientes de este navegador:', error);
    return [];
  }
}

// La vista que se acaba de abrir va hasta arriba. Inicio no cuenta: es donde se ven.
export function anotarReciente(vista: VistaPanel): void {
  if (vista === 'inicio') return;
  const lista = [vista, ...leerRecientes().filter((v) => v !== vista)].slice(0, CUANTOS);
  try {
    localStorage.setItem(LLAVE, JSON.stringify(lista));
  } catch (error) {
    console.error('[vistas] no se pudo recordar la vista reciente:', error);
  }
}
