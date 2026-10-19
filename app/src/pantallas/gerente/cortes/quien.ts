// Quién pidió y quién autorizó algo que pidió PIN, como lo dice Cortes y reportes: si fue la misma
// persona (la caja o un gerente, que se autorizan solos), «Lo hizo Lupita Hernández».
export function quienLoHizo(
  pidioId: number | null,
  pidio: string | null,
  autorizoId: number | null,
  autorizo: string | null,
): string {
  if (!pidio) return autorizo ? `Autorizó ${autorizo}` : '';
  if (!autorizo || pidioId === autorizoId) return `Lo hizo ${pidio}`;
  return `Pidió ${pidio} · Autorizó ${autorizo}`;
}
