// Los mensajes de error que se repiten entre pantallas, escritos una sola vez, y cómo saber si
// un error fue por falta de internet. Los textos son los del panel de Flet.

export const SIN_CONEXION = 'No hay conexión con el servidor. Revisa tu internet.';
export const ALGO_SALIO = 'Algo salió mal al iniciar sesión. Intenta de nuevo.';

// ¿El error es porque no se pudo hablar con el servidor? Los navegadores lo dicen distinto:
// Chrome "Failed to fetch", Firefox "NetworkError…", Safari "Load failed". Supabase lo envuelve
// en su propio error (AuthRetryableFetchError en el login), con ese texto adentro.
export function esDeRed(error: unknown): boolean {
  if (!error) return false;
  const e = error as { name?: string; message?: string };
  if (e.name === 'AuthRetryableFetchError' || error instanceof TypeError) return true;
  return /Failed to fetch|NetworkError|Load failed|fetch failed/i.test(e.message ?? '');
}
