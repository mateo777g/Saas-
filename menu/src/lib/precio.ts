// Cómo se escribe un precio en el menú: en pesos, como en todo el producto (dinero() de
// app/src/lib/formato.ts: «$22», «$22.50»), o en los dólares que calculó Postgres, siempre con
// centavos: «US$4.05». El menú nunca convierte; si un precio no trae dólares, sale en pesos.
import { dinero } from '@app/lib/formato';
import type { Moneda } from './preferencias';

export function dolares(n: number): string {
  return `US$${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function monto(pesos: number, enDolares: number | null, moneda: Moneda): string {
  return moneda === 'usd' && enDolares !== null ? dolares(enDolares) : dinero(pesos);
}
