// Una fila de la tabla de la Caja a lo ancho (adaptabilidad 3c; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, pantalla «Caja»): una
// cuenta por cobrar o una cobrada en este turno, ya en palabras (Cuenta · Cómo · Abrió · Total). La arma caja/Caja.svelte
// con lo que leyó; la tabla solo la pinta.
export type FiltroCaja = 'porcobrar' | 'cobradas' | 'todas';

export type FilaCaja = {
  clave: string; // «v12» por cobrar, «c12» cobrada
  id: number;
  cobrada: boolean;
  titulo: string; // «#22 · Sr. Ramírez», «Mesa 4»
  icono: string;
  como: string; // «Para llevar», «Mesa»
  abrio: string; // «Lupita · 14:05», «En línea · 14:26»
  total: number;
  falta: number | null; // solo si ya pagó una parte o se reabrió
  whatsapp: boolean;
  marca: string | null; // «Pidió la cuenta», «Reabierta»
  buscar: string; // sin acentos, para la búsqueda
};
