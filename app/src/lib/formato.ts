// Cómo se escribe en pantalla lo que ya contó Postgres. Aquí no se cuenta nada: solo se pasa a
// palabras lo que llegó ('2026-10-08' → '8 oct 2026'; -8 días → 'Venció hace 8 días'). Las
// fechas se leen como texto, sin pasar por el reloj ni la zona del aparato.

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const MESES_LARGOS = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

function partes(iso: string) {
  const [anio, mes, dia] = iso.split('-').map(Number);
  return { anio, mes, dia };
}

// '2026-10-08' → '8 oct 2026'; sin fecha, la raya.
export function fecha(iso: string | null): string {
  if (!iso) return '—';
  const { anio, mes, dia } = partes(iso);
  return `${dia} ${MESES[mes - 1]} ${anio}`;
}

// El primer día de un mes ('2026-10-01') → 'oct' o 'octubre 2026'.
export function mesCorto(iso: string): string {
  return MESES[partes(iso).mes - 1];
}

export function mesLargo(iso: string): string {
  const { anio, mes } = partes(iso);
  return `${MESES_LARGOS[mes - 1]} ${anio}`;
}

// 1 → '1 restaurante'; 12 → '12 restaurantes'.
export function plural(n: number, uno: string, varios: string): string {
  return `${n} ${n === 1 ? uno : varios}`;
}

// Los días que le quedan a una licencia, como los dio Postgres (dias_restantes): 0 vence hoy,
// -8 venció hace 8 días; sin fecha de fin, la raya.
export function vigencia(dias: number | null): string {
  if (dias === null) return '—';
  if (dias === 0) return 'Vence hoy';
  if (dias > 0) return dias === 1 ? 'Falta 1 día' : `Faltan ${dias} días`;
  return dias === -1 ? 'Venció hace 1 día' : `Venció hace ${Math.abs(dias)} días`;
}

// Lo que se escribió en un campo de número, si es un entero de 1 o más dígitos; si no, nada
// (Postgres responde "Los meses deben ser 1 o más").
export function entero(texto: string): number | null {
  const limpio = texto.trim();
  return /^\d+$/.test(limpio) ? Number(limpio) : null;
}
