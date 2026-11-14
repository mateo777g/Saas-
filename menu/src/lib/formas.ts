// Las formas del menú en línea (migración tu_menu_en_linea, 12 de noviembre de 2026; maqueta
// UDArhiEZceT7rmSKxqRA5r): una columna por cosa en restaurantes, que llegan juntas en
// menu_publico().restaurante.formas con sus nombres sin «menu_». El restaurante las elige en «Tu menú
// en línea»; cada una nace como el menú de siempre (FORMAS_DE_SIEMPRE = los default de la tabla).
// Desde la parte D (13 nov 2026) viven en app/src/lib/formasMenu.ts, para que el panel y el menú hablen de lo mismo.

export { FORMAS_DE_SIEMPRE, leerFormas, type Formas, type Pieza } from '@app/lib/formasMenu';

// Las pestañas de abajo: Menú, Pedido y Asistente.
export type Pestana = 'menu' | 'pedido' | 'asistente';
