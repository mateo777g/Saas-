// El color del menú en línea (libreta 6, decidido el 20 de octubre de 2026; maqueta de la 6a
// Qx4C5CbKJYpeAsJCfw4ghn). La letra encima del color se pone sola oscura o blanca con la regla de los
// flyers (generador_ia.es_claro: luminancia WCAG > 0.45), y la vista avisa cuando el color casi no
// se ve sobre el fondo del menú. El selector trabaja en HSV, como el de Flet. El menú en línea (menu/)
// usa este mismo archivo.

export type TemaMenu = 'claro' | 'oscuro';

// El fondo del menú en cada tema.
export const FONDO_MENU: Record<TemaMenu, string> = { claro: '#FFFFFF', oscuro: '#0F0F0F' };

export function luminancia(hex: string): number {
  const v = parseInt(hex.slice(1), 16);
  return [16, 8, 0]
    .map((s) => {
      const c = ((v >> s) & 255) / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    })
    .reduce((suma, c, i) => suma + c * [0.2126, 0.7152, 0.0722][i], 0);
}

export function esClaro(hex: string): boolean {
  return luminancia(hex) > 0.45;
}

export function contraste(a: string, b: string): number {
  const x = luminancia(a);
  const y = luminancia(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

// Un color tan parecido al fondo que la barra casi no se distingue de él.
export function casiNoSeVe(hex: string | null, tema: TemaMenu): boolean {
  return !!hex && contraste(hex, FONDO_MENU[tema]) < 1.6;
}

// Las variables CSS del menú para un color: la barra, la raya de la categoría y los botones, con su
// letra encima. Sin color, el menú usa sus neutros (negro en claro, gris oscuro en oscuro).
export function estiloColor(hex: string | null): string {
  if (!hex) return '';
  const claro = esClaro(hex);
  const sobre = claro ? '#121212' : '#ffffff';
  return (
    `--m-acento:${hex};--m-sobre-acento:${sobre};--m-barra:${hex};--m-sobre-barra:${sobre};` +
    `--m-barra-chip:${claro ? 'rgba(0,0,0,0.10)' : 'rgba(255,255,255,0.18)'};` +
    `--m-barra-suave:${claro ? 'rgba(18,18,18,0.72)' : 'rgba(255,255,255,0.78)'};`
  );
}

// Tono de 0 a 360, saturación y brillo de 0 a 1.
export function hsvAHex(h: number, s: number, v: number): string {
  const f = (n: number) => {
    const k = (n + h / 60) % 6;
    return v - v * s * Math.max(0, Math.min(k, 4 - k, 1));
  };
  return (
    '#' +
    [f(5), f(3), f(1)]
      .map((x) => Math.round(x * 255).toString(16).padStart(2, '0'))
      .join('')
      .toUpperCase()
  );
}

export function hexAHsv(hex: string): [number, number, number] {
  const v = parseInt(hex.slice(1), 16);
  const r = ((v >> 16) & 255) / 255;
  const g = ((v >> 8) & 255) / 255;
  const b = (v & 255) / 255;
  const mx = Math.max(r, g, b);
  const mn = Math.min(r, g, b);
  const d = mx - mn;
  let h = 0;
  if (d) h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [(h * 60 + 360) % 360, mx ? d / mx : 0, mx];
}

// Lo que escribe en el campo del código: con o sin #, en minúsculas. null si todavía no es un color.
export function leerCodigo(texto: string): string | null {
  let v = texto.trim().toUpperCase();
  if (v[0] !== '#') v = '#' + v;
  return /^#[0-9A-F]{6}$/.test(v) ? v : null;
}
