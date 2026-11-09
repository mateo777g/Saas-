// Las filas de una tabla entran en cascada (9 nov 2026; maqueta Q4dffGWS7qPQxS8yTdWgPg, de la «ResizableTable» que
// mandó el developer): cada fila sube 20 px, crece de 98 % a 100 % y pasa de borrosa a nítida con el resorte de
// framer-motion 400/25, masa 0.7 (sube 2.9 %), una tras otra cada 40 ms empezando a los 0.1 s. Solo las que se ven en la
// pantalla (las de más abajo ya están cuando llegas); de la 15 en adelante entran juntas, para no tardar más de ~0.9 s.
// Quien la llama decide cuándo: en Mi menú, al llegar los datos la primera vez y al cambiar de sección; nunca al buscar,
// filtrar o releer. Con «reducir movimiento», nada.

function resorte(rigidez: number, freno: number, masa: number, segundos: number) {
  const w0 = Math.sqrt(rigidez / masa);
  const z = freno / (2 * Math.sqrt(rigidez * masa));
  const wd = w0 * Math.sqrt(1 - z * z);
  return (u: number) => {
    if (u >= 1) return 1;
    const t = u * segundos;
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + ((z * w0) / wd) * Math.sin(wd * t));
  };
}

const curva = resorte(400, 25, 0.7, 0.5);
const RESORTE_FILA = `linear(${Array.from({ length: 41 }, (_, i) => +curva(i / 40).toFixed(4)).join(', ')})`;

export function cascada(raiz: ParentNode | undefined | null) {
  if (!raiz || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const abajo = innerHeight;
  let n = 0;
  for (const fila of raiz.querySelectorAll<HTMLElement>('.cuerpo > .fila')) {
    if (fila.getBoundingClientRect().top >= abajo) break;
    fila.animate(
      [
        { opacity: 0, transform: 'translateY(20px) scale(0.98)', filter: 'blur(4px)' },
        { opacity: 1, transform: 'none', filter: 'blur(0px)' },
      ],
      { duration: 500, delay: 100 + 40 * Math.min(n, 14), easing: RESORTE_FILA, fill: 'backwards' },
    );
    n++;
  }
}
