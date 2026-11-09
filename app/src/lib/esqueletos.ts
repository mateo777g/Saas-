// Cuántas filas tenía una lista la última vez, en este navegador (regla «Los esqueletos», 8 nov 2026,
// planes/trabajo/rediseno/reglas-diseno.md): el esqueleto sale con esas, para que nada brinque al llegar.
// 3 la primera vez, al menos 1 y a lo más 10 (las que caben). Mi menú tiene la suya, por sección.
// `llave` dice de qué lista y de qué sucursal es: «mesas-<id de la sucursal>», «clientes».

const prefijo = 'fragmentless-filas-';
const entre = (n: unknown) => (typeof n === 'number' && Number.isFinite(n) ? Math.min(10, Math.max(1, Math.round(n))) : 3);

export function filasDeLaUltimaVez(llave: string): number {
  try {
    return entre(JSON.parse(localStorage.getItem(prefijo + llave) ?? 'null'));
  } catch (error) {
    console.error('[esqueletos] no se pudo leer cuántas filas había; sale con 3:', error);
    return 3;
  }
}

export function recordarFilas(llave: string, n: number) {
  try {
    localStorage.setItem(prefijo + llave, JSON.stringify(n));
  } catch (error) {
    console.error('[esqueletos] no se pudo recordar cuántas filas hay:', error);
  }
}

// Los anchos de las barras de cada fila del esqueleto, para que no salgan todas iguales: la fila i toma el i-ésimo.
export function anchos<T>(lista: T[], n: number): T[] {
  return Array.from({ length: n }, (_, i) => lista[i % lista.length]);
}
