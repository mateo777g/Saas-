// Los íconos del menú: los del panel (app/src/diseno/iconos.ts) más los cuatro que dibujó la maqueta
// de la 6a para el menú (ordenar, la lupa de la foto, la dirección y el menú apagado). Mismo
// viewBox 24 y puntas redondas.
import { ICONOS } from '@app/diseno/iconos';

const PROPIOS: Record<string, string> = {
  ordenar: '<path d="M7 4v16"></path><path d="M3.5 7.5 7 4l3.5 3.5"></path><path d="M17 20V4"></path><path d="M13.5 16.5 17 20l3.5-3.5"></path>',
  lupa: '<circle cx="11" cy="11" r="6"></circle><path d="M20 20l-4.2-4.2"></path><path d="M11 8.5v5"></path><path d="M8.5 11h5"></path>',
  ubicacion: '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"></path><circle cx="12" cy="9.5" r="2.5"></circle>',
  apagado: '<circle cx="12" cy="12" r="9"></circle><path d="M5.6 5.6l12.8 12.8"></path>',
  // Los de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r): el mundito y las monedas de la barra, la
  // flechita de Ajustes, los cuatro órdenes y los tres íconos de abajo (Menú, Pedido y el del Agente IA).
  mundo: '<circle cx="12" cy="12" r="9.2"></circle><path d="M12 2.8a13.5 13.5 0 0 0 0 18.4 13.5 13.5 0 0 0 0-18.4"></path><path d="M2.8 12h18.4"></path>',
  monedas:
    '<circle cx="6.6" cy="6.6" r="4.7"></circle><circle cx="17.4" cy="6.6" r="4.7"></circle><circle cx="6.6" cy="17.4" r="4.7"></circle><circle cx="17.4" cy="17.4" r="4.7"></circle>' +
    '<g fill="currentColor" stroke="none" font-family="Plus Jakarta Sans, sans-serif" font-weight="800" font-size="6.4" text-anchor="middle"><text x="6.6" y="8.9">€</text><text x="17.4" y="8.9">$</text><text x="6.6" y="19.7">£</text><text x="17.4" y="19.7">¥</text></g>',
  chevron: '<path d="m6 9 6 6 6-6"></path>',
  estrella: '<path d="M12 3.6l2.5 5.1 5.6.8-4 3.9.9 5.6-5-2.6-5 2.6.9-5.6-4-3.9 5.6-.8z"></path>',
  menor: '<path d="M6 19V5"></path><path d="M3 8l3-3 3 3"></path><path d="M19.5 8.2c-.6-.9-1.6-1.4-2.8-1.4-1.6 0-2.7.9-2.7 2.1 0 2.9 5.8 1.6 5.8 4.6 0 1.3-1.2 2.2-2.9 2.2-1.3 0-2.5-.6-3.1-1.6"></path><path d="M16.8 5v1.8"></path><path d="M16.8 15.7v1.8"></path>',
  mayor: '<path d="M6 5v14"></path><path d="M3 16l3 3 3-3"></path><path d="M19.5 8.2c-.6-.9-1.6-1.4-2.8-1.4-1.6 0-2.7.9-2.7 2.1 0 2.9 5.8 1.6 5.8 4.6 0 1.3-1.2 2.2-2.9 2.2-1.3 0-2.5-.6-3.1-1.6"></path><path d="M16.8 5v1.8"></path><path d="M16.8 15.7v1.8"></path>',
  az: '<path d="M3.5 16l3.2-9 3.2 9"></path><path d="M4.6 13h4.2"></path><path d="M13.5 7h6.5l-6.5 9.5H20"></path>',
  lista: '<path d="M8 6h12"></path><path d="M8 12h12"></path><path d="M8 18h12"></path><path d="M4 6h.01"></path><path d="M4 12h.01"></path><path d="M4 18h.01"></path>',
  'bolsa-app': '<path d="M5.5 8h13l-1 12.5h-11z"></path><path d="M9 8V6.5a3 3 0 0 1 6 0V8"></path>',
  asistente: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z"></path><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15Z"></path>',
};

// Los íconos de los cuatro órdenes, en el orden de TEXTOS.ordenes.
export const ICONOS_ORDEN = ['estrella', 'menor', 'mayor', 'az'];

export function trazosIcono(nombre: string): string | undefined {
  return PROPIOS[nombre] ?? ICONOS[nombre];
}
