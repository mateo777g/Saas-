// La conexión de la sucursal con su Mercado Pago (planes/trabajo/terminal/conexion.md; Ajustes, 12 nov 2026): la cajita
// «Mercado Pago» de Ajustes y la franja ámbar de Inicio leen de aquí su estado.
//
// La conexión de verdad todavía no existe: la construye la sesión de la terminal (la Point Smart). Hasta entonces cada
// sucursal está «Sin conectar» y «Conectar Mercado Pago» todavía no lleva a ningún lado (el developer, 12 nov 2026: «que
// se vea ya»). Cuando exista, esta función lee el estado de la base con la sesión del gerente y `conectar` abre el
// permiso de Mercado Pago; nada más cambia en Ajustes ni en Inicio.
export type EstadoMercadoPago =
  | { estado: 'sin' }
  | { estado: 'conectado'; cuenta: string; desde: string }
  | { estado: 'desconectado'; cuando: string };

export async function leerMercadoPago(_restauranteId: string): Promise<EstadoMercadoPago> {
  return { estado: 'sin' };
}

// Todavía no hay a dónde llevar: lo hace la sesión de la terminal.
export const SE_PUEDE_CONECTAR = false;
