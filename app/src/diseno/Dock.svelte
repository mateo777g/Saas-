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
    --dock-escala: linear(0, 0.0319, 0.113, 0.224, 0.3497, 0.4782, 0.6009, 0.7121, 0.8084, 0.8884, 0.9519, 0.9998, 1.0339, 1.0561, 1.0684, 1.0731, 1.0719, 1.0668, 1.0591, 1.0501, 1.0407, 1.0315, 1.0231, 1.0158, 1.0096, 1.0046, 1.0008, 0.9981, 0.9962, 0.9952, 0.9947, 0.9947, 0.995, 0.9955, 0.9961, 0.9968, 0.9975, 0.9981, 0.9987, 0.9992, 0.9996, 0.9999, 1.0001, 1.0002, 1.0003, 1.0004, 1.0004, 1.0004, 1);
    --dock-sube: linear(0, 0.0408, 0.1439, 0.2835, 0.4383, 0.592, 0.733, 0.8542, 0.9518, 1.0251, 1.0754, 1.1055, 1.1187, 1.119, 1.1101, 1.0952, 1.0772, 1.0584, 1.0406, 1.0247, 1.0115, 1.0011, 0.9937, 0.9889, 0.9863, 0.9855, 0.9861, 0.9876, 0.9896, 0.9918, 0.994, 0.9961, 0.9979, 0.9993, 1.0003, 1.0011, 1.0015, 1.0017, 1.0017, 1.0016, 1.0014, 1.0011, 1.0009, 1.0006, 1.0004, 1.0002, 1, 0.9999, 1);
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
      scale 0.548s var(--dock-escala),
      translate 0.65s var(--dock-sube);
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
