// Cómo se escribe en pantalla lo que ya contó Postgres. Aquí no se cuenta nada: solo se pasa a
// palabras lo que llegó ('2026-10-08' → '8 oct 2026'; -8 días → 'Venció hace 8 días'). Las
// fechas se leen como texto, sin pasar por el reloj ni la zona del aparato.

// Exportados para las fechas de cada año de los estilos (estilos.ts), que no llevan año.
export const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
export const MESES_LARGOS = [
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

// La fecha de Inicio, como en Flet: '2026-10-10' → 'SÁBADO, 10 DE OCTUBRE'. El día de la
// semana sale de la misma fecha (que dio Postgres), no del reloj del aparato.
const DIAS = ['DOMINGO', 'LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO'];

export function fechaLarga(iso: string): string {
  const { anio, mes, dia } = partes(iso);
  const semana = new Date(Date.UTC(anio, mes - 1, dia)).getUTCDay();
  return `${DIAS[semana]}, ${dia} DE ${MESES_LARGOS[mes - 1].toUpperCase()}`;
}

// La fecha en palabras, como en la suscripción terminada: '2026-11-08' → '8 de noviembre de 2026';
// sin fecha, la raya.
export function fechaEnPalabras(iso: string | null): string {
  if (!iso) return '—';
  const { anio, mes, dia } = partes(iso);
  return `${dia} de ${MESES_LARGOS[mes - 1]} de ${anio}`;
}

// El día anterior a una fecha: '2026-10-01' → '2026-09-30'. Cuenta sobre el texto, sin reloj.
export function diaAnterior(iso: string): string {
  const { anio, mes, dia } = partes(iso);
  return new Date(Date.UTC(anio, mes - 1, dia - 1)).toISOString().slice(0, 10);
}

// El día siguiente: '2026-09-30' → '2026-10-01'.
export function diaSiguiente(iso: string): string {
  const { anio, mes, dia } = partes(iso);
  return new Date(Date.UTC(anio, mes - 1, dia + 1)).toISOString().slice(0, 10);
}

// El día 1 del mes que sigue: '2026-10-01' → '2026-11-01'; diciembre pasa al año que sigue.
export function mesSiguiente(iso: string): string {
  const { anio, mes } = partes(iso);
  return new Date(Date.UTC(anio, mes, 1)).toISOString().slice(0, 10);
}

// '2026-11-01' → '1 de noviembre'.
export function diaYMes(iso: string): string {
  const { mes, dia } = partes(iso);
  return `${dia} de ${MESES_LARGOS[mes - 1]}`;
}

// '2026-10-01' → 'octubre'.
export function nombreDelMes(iso: string): string {
  return MESES_LARGOS[partes(iso).mes - 1];
}

// El día de Cortes y reportes: '2026-10-17' → 'Sábado 17 de octubre'.
export function diaConNombre(iso: string): string {
  const { anio, mes, dia } = partes(iso);
  const semana = DIAS[new Date(Date.UTC(anio, mes - 1, dia)).getUTCDay()];
  return `${semana.charAt(0)}${semana.slice(1).toLowerCase()} ${dia} de ${MESES_LARGOS[mes - 1]}`;
}

// Un momento que dio Postgres ('2026-10-15T19:20:00+00:00') visto en la zona del restaurante: su
// fecha ('2026-10-15') y su hora ('14:20'). Usa la zona que se le pasa, nunca la del aparato.
export function enZona(momento: string, zona: string): { dia: string; hora: string } {
  const pedazos = new Intl.DateTimeFormat('en-CA', {
    timeZone: zona,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(momento));
  const de = (tipo: Intl.DateTimeFormatPartTypes) => pedazos.find((p) => p.type === tipo)?.value ?? '';
  return { dia: `${de('year')}-${de('month')}-${de('day')}`, hora: `${de('hour')}:${de('minute')}` };
}

// El saludo según la hora (0 a 23) que dio Postgres, con los cortes de Flet (models/tiempo.py):
// antes de las 12, días; antes de las 19, tardes; después, noches.
export function saludoPorHora(hora: number): string {
  if (hora < 12) return 'Buenos días';
  if (hora < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

// 1 → '1 restaurante'; 12 → '12 restaurantes'; 1140 → '1,140 preguntas'.
export function plural(n: number, uno: string, varios: string): string {
  return `${n.toLocaleString('en-US')} ${n === 1 ? uno : varios}`;
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

// Lo que se escribió en un campo de dinero ('2', '2.5', '1.25'); si no es un número, nada
// (Postgres dice de cuánto a cuánto va y cuántos decimales lleva).
export function decimal(texto: string): number | null {
  const limpio = texto.trim();
  return /^\d+(\.\d+)?$/.test(limpio) ? Number(limpio) : null;
}

// Un precio como lo dio Postgres: sin centavos si es entero ($1,500), con ellos si los tiene
// ($22.50). Como _formatear_precio() de Flet.
export function dinero(n: number): string {
  const entero = Math.round(n * 100) % 100 === 0;
  return `$${n.toLocaleString('en-US', { minimumFractionDigits: entero ? 0 : 2, maximumFractionDigits: 2 })}`;
}

// Pesos con centavos siempre, como en el corte: $2,400.00.
export function pesos(n: number): string {
  return `$${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

// Los dólares de la IA, con centavos siempre ($3.42, $10.00). uso_ia guarda 4 decimales: aquí
// solo se muestran 2.
export const dolares = pesos;
