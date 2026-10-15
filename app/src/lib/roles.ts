// Los roles de quien trabaja en un restaurante, con su nombre en pantalla. El gerente da mesero,
// caja y cocina (en este orden, el que guarda alta_empleado); el de gerente lo liga Fragmentless.
// Aparte de equipo.ts porque también los usa el aparato, que no carga la conexión del panel.
export const ROLES = [
  { valor: 'mesero', texto: 'Mesero' },
  { valor: 'caja', texto: 'Caja' },
  { valor: 'cocina', texto: 'Cocina' },
] as const;
export type Rol = (typeof ROLES)[number]['valor'];

export const NOMBRE_ROL: Record<string, string> = {
  gerente: 'Gerente',
  mesero: 'Mesero',
  caja: 'Caja',
  cocina: 'Cocina',
};
