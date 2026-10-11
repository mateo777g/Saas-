// Los mensajes de error que se repiten entre pantallas, escritos una sola vez, y cómo saber si
// un error fue por falta de internet. Los textos son los del panel de Flet.

export const SIN_CONEXION = 'No hay conexión con el servidor. Revisa tu internet.';
export const ALGO_SALIO = 'Algo salió mal al iniciar sesión. Intenta de nuevo.';
export const ALGO_SALIO_PANEL = 'Algo salió mal. Intenta de nuevo.';

// ¿El error es porque no se pudo hablar con el servidor? Los navegadores lo dicen distinto:
// Chrome "Failed to fetch", Firefox "NetworkError…", Safari "Load failed". Supabase lo envuelve
// en su propio error (AuthRetryableFetchError en el login), con ese texto adentro.
export function esDeRed(error: unknown): boolean {
  if (!error) return false;
  const e = error as { name?: string; message?: string };
  if (e.name === 'AuthRetryableFetchError' || error instanceof TypeError) return true;
  return /Failed to fetch|NetworkError|Load failed|fetch failed/i.test(e.message ?? '');
}

// Lo que Postgres dice en inglés cuando una fila no cumple una regla de su tabla, traducido por
// el nombre de la regla (migración plataforma). Los textos son los de la maqueta del panel de
// Fragmentless (Tbt7H3G1QRXykzNKe1GXHh).
const REGLAS: Record<string, string> = {
  restaurantes_nombre_check: 'Escribe el nombre del restaurante.',
  restaurantes_slug_formato:
    'El slug solo lleva minúsculas, números y guiones, sin guion al inicio ni al final ni dos seguidos.',
  restaurantes_licencia_con_fin: 'No se puede prender una licencia sin fecha de fin.',
  miembros_nombre_check: 'Escribe su nombre completo.',
};

// El mensaje para la caja de error cuando falla una llamada a Postgres. Las funciones de la base
// ya lanzan sus errores en español ("Falta la fecha de inicio"), y salen tal cual. Postgres
// escribe los suyos en inglés y empezando con minúscula (es su regla de estilo): esos se
// traducen si son de una regla conocida, y si no, sale el genérico. Quien llama ya dejó el error
// completo en la consola.
export function mensajeDeError(error: unknown): string {
  if (esDeRed(error)) return SIN_CONEXION;
  const e = error as { code?: string; message?: string; details?: string };
  const mensaje = e.message ?? '';

  if (e.code === '23505' && mensaje.includes('"restaurantes_slug_key"')) {
    const slug = /\(slug\)=\((.*)\)/.exec(e.details ?? '')?.[1];
    if (slug !== undefined) return `Ya hay un restaurante con el slug ${slug}. Elige otro.`;
  }
  if (e.code === '23514') {
    const regla = Object.keys(REGLAS).find((nombre) => mensaje.includes(`"${nombre}"`));
    if (regla) return REGLAS[regla];
  }
  // Un código de Postgres (5 caracteres; los de PostgREST empiezan con PGRST) con un mensaje que
  // empieza con mayúscula: es de nuestras funciones.
  if (/^[0-9A-Z]{5}$/.test(e.code ?? '') && /^[A-ZÁÉÍÓÚÑ]/.test(mensaje)) return mensaje;
  return ALGO_SALIO_PANEL;
}
