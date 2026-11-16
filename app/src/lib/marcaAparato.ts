// La marca del aparato del equipo (/equipo): el logo del restaurante, el de «Tu restaurante» (el mismo del menú en
// línea), en vez de la estrella de Fragmentless, que se queda solo en los paneles. Aparato.svelte lo pone en el
// contexto en cuanto sabe de qué restaurante es (nombres_del_aparato); las barras del aparato (aparato/Arriba,
// pos/Lugar, pos/ancho/Barra) lo leen de ahí. En el panel no hay contexto: pos/Lugar sigue con la estrella.
// No importa nada del panel (lib/supabase.ts): el aparato lo usa.
import { getContext, setContext } from 'svelte';

export type MarcaAparato = { readonly logo: string | null }; // null: el restaurante no tiene logo (va solo el nombre)

const CLAVE = Symbol('marca-del-aparato');

export function ponerMarca(marca: MarcaAparato): void {
  setContext(CLAVE, marca);
}

// null fuera del aparato (el panel).
export function leerMarca(): MarcaAparato | null {
  return getContext<MarcaAparato | undefined>(CLAVE) ?? null;
}

// La dirección pública del logo en R2 (como urlFoto de lib/fotos.ts, que el aparato no puede importar).
export function urlLogo(ruta: string): string {
  return `${import.meta.env.VITE_R2_PUBLICO}/${ruta}`;
}
