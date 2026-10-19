// El Markdown de las respuestas del Agente IA (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga). Vive
// aparte de agente.ts para que markdown-it solo se cargue con la vista del agente, no al entrar
// al panel.
import MarkdownIt from 'markdown-it';

// html: false escapa cualquier HTML que mande el modelo; sin imágenes (no se cargan cosas de
// afuera) y sin convertir direcciones sueltas en enlaces. breaks: cada renglón del modelo es un
// renglón, como en Flet.
const md = new MarkdownIt({ html: false, linkify: false, typographer: false, breaks: true }).disable('image');

export function markdown(texto: string): string {
  return md.render(texto);
}

// Un número de tabla: $1,320, −$60, 96, 13 %, 4.5 o la raya.
const NUMERO = /^[−–+-]?\s?\$?\s?\d[\d,]*(\.\d+)?\s?%?$/;
const RAYA = /^[—–-]?$/;

// Lo que el Markdown no puede decir: cada tabla va en su caja de bordes redondos, las columnas de
// números van a la derecha y en mono (como en Flet), y los enlaces abren aparte.
export function acomodar(contenedor: HTMLElement): void {
  for (const tabla of contenedor.querySelectorAll('table')) {
    if (!tabla.parentElement?.classList.contains('md-tabla')) {
      const caja = document.createElement('div');
      caja.className = 'md-tabla';
      tabla.replaceWith(caja);
      caja.append(tabla);
    }
    const filas = [...tabla.querySelectorAll('tbody tr')];
    const columnas = tabla.querySelectorAll('thead th').length;
    for (let i = 0; i < columnas; i++) {
      const celdas = filas.map((f) => f.children[i] as HTMLElement | undefined).filter((c): c is HTMLElement => !!c);
      const textos = celdas.map((c) => (c.textContent ?? '').trim());
      if (textos.some((t) => NUMERO.test(t)) && textos.every((t) => NUMERO.test(t) || RAYA.test(t))) {
        tabla.querySelectorAll('thead th')[i]?.classList.add('n');
        for (const c of celdas) c.classList.add('n');
      }
    }
  }
  for (const a of contenedor.querySelectorAll('a')) {
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
  }
}

// Renglón por renglón: cada bloque (y cada punto de una lista) sale 110 ms después del anterior.
// Regresa cuántos salieron.
export function revelar(contenedor: HTMLElement): number {
  let n = 0;
  for (const bloque of contenedor.children) {
    const piezas = bloque.matches('ul, ol') ? [...bloque.children] : [bloque];
    for (const p of piezas) {
      (p as HTMLElement).style.animationDelay = `${n++ * 110}ms`;
      p.classList.add('aparece');
    }
  }
  return n;
}
