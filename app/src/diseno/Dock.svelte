<!--
  Las secciones de Mi menú (Productos, Categorías, Opciones, Áreas) como el «Dock» de 21st.dev (React +
  framer-motion + lucide-react), hecho en CSS (maqueta de Mi menú U9YqpsSb2PeB5pFXTPvh1C, versiones 15, 16
  y 27). Una píldora con borde y sombra (más grande al pasar el mouse, 300 ms) con solo íconos de 18 en
  botones de 32. Cada uno crece a 1.1 y sube 2 px con los resortes de framer-motion (escala 550/30,
  0.55 s; altura 500/25, 0.65 s) y se aprieta a 0.95 al picarle. El nombre sale abajo al instante
  (150 ms), también con el teclado. Lo elegido lleva el gris de pasar el mouse (--chip). Va al centro de
  la barra de arriba, para que no se recorra al cambiar de sección, y quieto: solo se mueve con el mouse.
  Sin el desenfoque del original: en la barra lisa no se ve.
-->
<script lang="ts" generics="T extends string">
  import Icono from './Icono.svelte';

  let {
    opciones,
    elegida,
    alElegir,
    etiqueta,
  }: {
    opciones: { valor: T; texto: string; icono: string; trazos?: string }[];
    elegida: T;
    alElegir: (valor: T) => void;
    etiqueta: string;
  } = $props();
</script>

<div class="dock" role="group" aria-label={etiqueta}>
  {#each opciones as o (o.valor)}
    <button type="button" class="dock-boton" aria-pressed={o.valor === elegida} aria-label={o.texto} onclick={() => alElegir(o.valor)}>
      <span class="dock-icono"><Icono nombre={o.icono} trazos={o.trazos} tamano={18} /></span>
      <span class="dock-nombre" aria-hidden="true">{o.texto}</span>
    </button>
  {/each}
</div>

<style>
  .dock {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    flex: none;
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
    background: color-mix(in srgb, var(--solido) 90%, transparent);
    box-shadow:
      0 10px 15px -3px rgba(0, 0, 0, 0.1),
      0 4px 6px -4px rgba(0, 0, 0, 0.1);
    transition: box-shadow 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .dock:hover {
    box-shadow:
      0 20px 25px -5px rgba(0, 0, 0, 0.1),
      0 8px 10px -6px rgba(0, 0, 0, 0.1);
  }

  .dock-boton {
    position: relative;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 0;
    border-radius: 8px;
    background: transparent;
    color: var(--texto);
    cursor: pointer;
    transition:
      background-color 0.15s cubic-bezier(0.4, 0, 0.2, 1),
      color 0.15s cubic-bezier(0.4, 0, 0.2, 1),
      scale 0.548s var(--resorte-escala),
      translate 0.65s var(--resorte-sube);
  }

  .dock-boton:hover,
  .dock-boton:focus-visible {
    background: var(--chip);
    scale: 1.1;
    translate: 0 -2px;
  }

  .dock-boton:active {
    scale: 0.95;
  }

  .dock-boton[aria-pressed='true'] {
    background: var(--chip);
  }

  .dock-boton:focus-visible {
    outline: 2px solid var(--acento);
    outline-offset: 2px;
  }

  .dock-icono {
    width: 18px;
    height: 18px;
    flex: none;
    display: flex;
  }

  .dock-nombre {
    position: absolute;
    z-index: 5;
    top: calc(100% + 8px);
    left: 50%;
    translate: -50% 0;
    padding: 4px 8px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 4px;
    background: var(--solido);
    color: var(--texto);
    font: 500 12px/16px var(--jakarta);
    white-space: nowrap;
    opacity: 0;
    pointer-events: none;
    box-shadow: 0 4px 12px var(--sombra-menu, rgba(0, 0, 0, 0.12));
    transition: opacity 0.15s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .dock-boton:hover .dock-nombre,
  .dock-boton:focus-visible .dock-nombre {
    opacity: 1;
  }

  @media (prefers-reduced-motion: reduce) {
    .dock,
    .dock * {
      transition: none !important;
      animation: none !important;
    }
  }
</style>
