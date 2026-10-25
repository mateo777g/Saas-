// Los íconos del menú: los del panel (app/src/diseno/iconos.ts) más los cuatro que dibujó la maqueta
// de la 6a para el menú (ordenar, la lupa de la foto, la dirección y el menú apagado). Mismo
// viewBox 24 y puntas redondas.
import { ICONOS } from '@app/diseno/iconos';

const PROPIOS: Record<string, string> = {
  ordenar: '<path d="M7 4v16"></path><path d="M3.5 7.5 7 4l3.5 3.5"></path><path d="M17 20V4"></path><path d="M13.5 16.5 17 20l3.5-3.5"></path>',
  lupa: '<circle cx="11" cy="11" r="6"></circle><path d="M20 20l-4.2-4.2"></path><path d="M11 8.5v5"></path><path d="M8.5 11h5"></path>',
  ubicacion: '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"></path><circle cx="12" cy="9.5" r="2.5"></circle>',
  apagado: '<circle cx="12" cy="12" r="9"></circle><path d="M5.6 5.6l12.8 12.8"></path>',
};

export function trazosIcono(nombre: string): string | undefined {
  return PROPIOS[nombre] ?? ICONOS[nombre];
}
