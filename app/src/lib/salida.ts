// Irse de una vista con cambios sin guardar («Tu menú en línea», parte D, 13 nov 2026; maqueta UDArhiEZceT7rmSKxqRA5r
// v59: «si sales con cambios, "Tienes cambios sin guardar"»). La vista que junta cambios pone su guardia mientras está
// abierta; el panel, antes de cambiar de vista, de sucursal o de cerrar sesión, le pregunta con `salir`. Si la guardia
// se queda con la salida (tiene cambios), ella llama a `seguir` cuando Don Chuy elige salir; si no, se sale de una vez.

type Guardia = (seguir: () => void) => boolean;

let guardia: Guardia | null = null;

export function ponerGuardia(g: Guardia): () => void {
  guardia = g;
  return () => {
    if (guardia === g) guardia = null;
  };
}

export function salir(seguir: () => void) {
  if (guardia?.(seguir)) return;
  seguir();
}
