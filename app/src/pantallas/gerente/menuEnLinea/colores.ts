// Los avisos de color de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59, avisoHtml): en la fila «Tema y colores»
// y en la ventana del color. El color de tu menú, si casi no se ve sobre el fondo (contraste menor a 1.6); la barra, si
// casi no se distingue del fondo (menor a 1.25); el fondo, si con él las letras del tema casi no se leen (menor a 4.5).
import { contraste, esClaro, FONDO_MENU, type TemaMenu } from '../../../lib/color';

export type ClaveColor = 'color' | 'colorBarra' | 'fondo';

const LETRA: Record<TemaMenu, string> = { claro: '#121212', oscuro: '#F3F3F0' };

export type Colores = { tema: TemaMenu; color: string | null; colorBarra: string | null; fondo: string | null };

export function avisoDeColor(clave: ClaveColor, s: Colores): { fuerte: string; texto: string } | null {
  const fondo = s.fondo || FONDO_MENU[s.tema];
  if (clave === 'color' && s.color && contraste(s.color, fondo) < 1.6) {
    return s.fondo
      ? { fuerte: 'Este color casi no se ve sobre tu fondo.', texto: 'Escoge otro color o cambia el fondo.' }
      : {
          fuerte: `Este color casi no se ve en tu menú ${s.tema}.`,
          texto: `Escoge uno más ${s.tema === 'claro' ? 'oscuro' : 'claro'} o cambia el tema.`,
        };
  }
  if (clave === 'colorBarra' && s.colorBarra && contraste(s.colorBarra, fondo) < 1.25) {
    return {
      fuerte: 'Este color casi no se distingue de tu fondo:',
      texto: `tu barra y tus cajas se pierden. Escoge uno más ${esClaro(fondo) ? 'oscuro' : 'claro'} o cambia el fondo.`,
    };
  }
  if (clave === 'fondo' && s.fondo && contraste(s.fondo, LETRA[s.tema]) < 4.5) {
    return {
      fuerte: `Con este fondo, las letras casi no se leen en tu menú ${s.tema}.`,
      texto: `Escoge un fondo más ${s.tema === 'claro' ? 'claro' : 'oscuro'} o cambia el tema.`,
    };
  }
  return null;
}
