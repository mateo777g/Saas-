// La flecha de las listas que se doblan en ✕ al abrir (diseno/Lista.svelte y el filtro de Productos): cada punta va
// de la V a la ✕ con el resorte de framer-motion (rigidez 260, freno 22, masa 1), resuelto por tiempo, como la
// transición CSS de 0.662 s de la maqueta de Mi menú: rebasa 5 % y regresa. No va con el `Spring` de Svelte porque
// ese suma su empuje en cada cuadro: en una pantalla de 120 Hz o más corre más rápido y ya no rebota (medido el
// 7 de noviembre de 2026).
const W0 = Math.sqrt(260);
const Z = 22 / (2 * W0);
const WD = W0 * Math.sqrt(1 - Z * Z);

export const DURA_FLECHA = 662;

export function resorteFlecha(p: number): number {
  if (p >= 1) return 1;
  const t = (p * DURA_FLECHA) / 1000;
  return 1 - Math.exp(-Z * W0 * t) * (Math.cos(WD * t) + ((Z * W0) / WD) * Math.sin(WD * t));
}

// Los dos trazos de la flecha según cuánto se ha doblado (0 = V, 1 = ✕), en un viewBox de 24.
export function trazosFlecha(doblez: number): [string, string] {
  const ir = (a: number, b: number) => (a + (b - a) * doblez).toFixed(2);
  return [`M ${ir(6, 6)} ${ir(10, 6)} L ${ir(12, 18)} ${ir(16, 18)}`, `M ${ir(12, 6)} ${ir(16, 18)} L ${ir(18, 18)} ${ir(10, 6)}`];
}
