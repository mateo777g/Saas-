# Fragmentless

La página está en `index.html`, con estilos en `style.css` y sus scripts de animación:

- `escena.js`: la portada y la laptop que se encoge, gira y se cierra con el scroll.
- `barra.js`: la barra de arriba y sus submenús.
- `hoja.js`: la hoja blanca de la sección del panel, que sube encima de la escena.

La página Nosotros es `nosotros.html`, con sus estilos en `nosotros.css` y la animación de entrada de
sus bloques en `nosotros.js`. Usa la misma barra (`barra.js`, `style.css`) y el mismo footer.
Llegan a ella el botón «Conócenos» de la portada, «Acerca de → Nosotros» y el footer.

Las secciones del panel, las tarjetas y el footer son componentes React/TypeScript que se compilan
a `assets/wave-background.js` y se montan en `#panel-showcase`, `#feature-cards` y `#site-footer`.

## Desarrollo

```sh
npm install
npm run build
```

Después abre `index.html` con Live Server. Los archivos compilados en `assets/` se sirven
directamente, sin un servidor React ni dependencias de CDN. Ejecuta el build al cambiar un
componente o sus estilos; los cambios al HTML, a `style.css` o a los scripts no requieren build.

- Entrada React: `src/wave-entry.tsx` (el nombre del archivo compilado se quedó de cuando montaba
  el fondo de ondas).
- Fila curva de capturas del panel: `components/panel-showcase.tsx` y `components/ui/tilted-grid-hero.tsx`
  (usa OGL/WebGL).
- Tarjetas del producto: `components/feature-cards.tsx` y `components/ui/glass-blog-card-shadcnui.tsx`.
- Footer: `components/ui/halftone-wordmark-footer.tsx`.
- Estilos Tailwind: `styles/components.css` (sin reset global para preservar la página).
- Alias `@/`: raíz del proyecto, definido en `tsconfig.json`.
- Configuración shadcn: `components.json`; utilidad `cn`: `lib/utils.ts`.

Tailwind se limita a las utilidades de los componentes y omite
[Preflight](https://tailwindcss.com/docs/preflight#disabling-preflight).

## Imágenes y video

- El azul de la pantalla de la laptop ya no es un video: lo dibuja `pantalla.js` en vivo con WebGL
  (7 KB en vez de 0.8 MB). Sin WebGL se ve `prueba/fondo-azul.webp`, un cuadro fijo del video que había
  antes.

- Las fotos de las tarjetas son `prueba/tarjeta-*.webp` (1200 px), sacadas de los PNG originales con
  `ffmpeg -i libreta.png -vf scale=1200:-2 -c:v libwebp -quality 80 prueba/tarjeta-libreta.webp`. Los
  originales ya no están en la carpeta; siguen en el historial de git.
- `assets/og-imagen.jpg` (1200 × 630) es la imagen que se ve al compartir el enlace. Cuando la página
  tenga dominio, cambia `og:image` en `index.html` por la dirección completa.
