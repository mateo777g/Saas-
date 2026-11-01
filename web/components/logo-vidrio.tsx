"use client";

import * as React from "react";

// El logo de Fragmentless dentro del vidrio líquido del «Glass Reveal» de 21st.dev (components/ui/
// liquid-glass-logo-reveal.tsx): la entrada de Nosotros. Lleva los mismos números que el logo de 21st.dev en el
// componente; solo cambia el logo, que va con sus propios colores, y que sale una sola vez. Al terminar, el logo
// se queda un momento, sube a su lugar arriba del texto de la portada mientras el fondo pasa del gris de la
// referencia a blanco, y luego salen la barra y el texto (nosotros.css, con data-intro en <html>).
import { GlassIconReveal } from "@/components/ui/liquid-glass-logo-reveal";

// La estrella oficial, la del lienzo «Logo Fragmentless» (un poco más redondeada que assets/fragmentless-logo.svg),
// con su degradado de azul profundo a celeste. Va como texto y no como archivo porque así el componente la dibuja
// al tamaño de su textura; un .svg de 24 px saldría borroso.
const LOGO = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="179 33 180 180">
<defs><linearGradient id="dg-g" gradientUnits="userSpaceOnUse" x1="192" y1="200" x2="350" y2="46">
<stop offset="0" stop-color="#0A2470"/><stop offset="0.45" stop-color="#1355E8"/>
<stop offset="0.8" stop-color="#4FA3FF"/><stop offset="1" stop-color="#9FE6FF"/>
</linearGradient></defs>
<g fill="url(#dg-g)" stroke="url(#dg-g)" stroke-width="8" stroke-linejoin="round">
<path d="M214 92 Q282.3 83.6 346.4 49.7 Q309.6 112.2 298 180 Z"/>
<path d="M196 108 Q204 157 192 196 Q232 186 280 196 Z"/>
</g></svg>`;

// El fondo de la referencia, sobre el que se ve la orilla blanca del vidrio, y el blanco de la página
const GRIS = [0xe9, 0xe9, 0xeb];
const BLANCO = [0xff, 0xff, 0xff];
// Lo que el logo terminado se queda quieto antes de subir, y lo que tarda en subir (igual que en nosotros.css)
const PAUSA = 500;
const SUBIDA = 900;
// El último cuadro del vidrio, en segundos: lo que lo sostiene (2.4) más lo que tarda en soltarlo (1.1). Con
// «reducir movimiento» no hay entrada y se queda en ese cuadro: el logo solo, sobre blanco.
const FIN = 3.5;

const hex = (c: number[]) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
// La misma curva de la subida (cubic-bezier(.65, 0, .35, 1) en nosotros.css, casi igual a esta)
const suave = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);

export default function LogoVidrio({ className }: { className?: string }) {
  const [quieto] = React.useState(() => matchMedia("(prefers-reduced-motion: reduce)").matches);
  const [fondo, setFondo] = React.useState(() => hex(quieto ? BLANCO : GRIS));

  const alTerminar = React.useCallback(() => {
    if (quieto) return;
    setTimeout(() => {
      document.documentElement.dataset.intro = "sube";
      const inicio = performance.now();
      const paso = (ahora: number) => {
        const t = Math.min(1, (ahora - inicio) / SUBIDA);
        setFondo(hex(GRIS.map((g, i) => g + (BLANCO[i] - g) * suave(t))));
        if (t < 1) requestAnimationFrame(paso);
      };
      requestAnimationFrame(paso);
    }, PAUSA);
  }, [quieto]);

  // El lienzo sube con el logo y deja ver la portada debajo (nosotros.css), que va del mismo color que él. Se le
  // pone aquí y no en paso() para que cambie en el mismo cuadro en que el lienzo se vuelve a pintar; si no, la
  // portada iba un cuadro adelante y en la orilla de abajo del lienzo se veía una línea.
  React.useEffect(() => {
    document.documentElement.style.setProperty("--fondo-logo", fondo);
  }, [fondo]);

  return (
    <GlassIconReveal
      logo={LOGO}
      label="Fragmentless"
      look="light"
      originalColors
      // Sin WebGL se ve el logo plano, en el azul de la marca
      logoColor="#1355E8"
      logoScale={0.6}
      finalScale={0.8}
      tuning={{ startZoom: 2.3 }}
      background={fondo}
      loop={false}
      time={quieto ? FIN : undefined}
      onEnd={alTerminar}
      className={className}
    />
  );
}
