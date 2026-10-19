<!--
  El fondo de manchas del Agente IA, solo de esa vista («DISEÑO MANCHAS + VIDRIO» en plan
  panel.txt; maqueta Agente IA KznKZdgQbLTZGs1EwVMvga): unas vetas negras que se retuercen,
  pintadas con una trama de Bayer 4 × 4, sobre el hueso del tema claro o el carbón del oscuro. La
  barra lateral y las tarjetas de vidrio lo dejan ver desenfocado.

  Es el shader del que salió el diseño: Dithering de Paper Shaders, forma "warp", trama 4 × 4.
  Flet no podía correr shaders y usaba un WebP animado que lo imitaba (dither-claro.webp de la
  maqueta, hecho con panel/herramientas/generar_fondo_manchas.py); en la web corre el de verdad,
  como las manchas del login, con los valores de ese WebP: una vuelta cada 21 s, puntitos de 3 px
  y vetas del mismo grueso. Sin WebGL se queda el color del suelo.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import {
    DitheringShapes,
    DitheringTypes,
    ShaderFitOptions,
    ShaderMount,
    ditheringFragmentShader,
    getShaderColorFromString,
  } from '@paper-design/shaders';
  import { temaActual } from '../lib/tema';

  // El tiempo del shader corre a la mitad (t = u_time / 2) y la veta da su vuelta en 2π: con
  // 4π / 21 da una vuelta cada 21 s, como el WebP.
  const VELOCIDAD = (4 * Math.PI) / 21;
  // El WebP pinta 0.0105 de veta por puntito y la maqueta lo estira a 2.67 px por puntito; el
  // shader pinta 0.003 por px dividido entre la escala.
  const ESCALA = 0.003 / (0.0105 / (1440 / 540));
  const PUNTITO = 3;

  // Fuera de las vetas la forma nunca baja a 0, y eso llena el fondo liso de una rejilla de
  // puntitos sueltos: Flet le restaba un piso (PISO = 0.14 en generar_fondo_manchas.py) y así se
  // ve la maqueta. Aquí se le resta lo mismo, en la línea de la veta "warp" del shader.
  const VETA = 'shape = smoothstep(0.02, 1., shape);';
  const CON_PISO = ditheringFragmentShader.includes(VETA)
    ? ditheringFragmentShader.replace(VETA, `${VETA}\n    shape = clamp((shape - .14) / .86, 0., 1.);`)
    : null;
  if (!CON_PISO) console.error('[fondo] el shader de Paper cambió: sin el piso, el fondo liso lleva puntitos sueltos');
  const SHADER = CON_PISO ?? ditheringFragmentShader;

  // Los colores del WebP: manchas negras en los dos temas.
  function colores() {
    const oscuro = temaActual() === 'oscuro';
    return {
      u_colorBack: getShaderColorFromString(oscuro ? '#161616' : '#fafaf8'),
      u_colorFront: getShaderColorFromString(oscuro ? '#000000' : '#0a0a0a'),
    };
  }

  let lienzo: HTMLDivElement;

  onMount(() => {
    let shader: ShaderMount | null = null;
    try {
      const quieto = matchMedia('(prefers-reduced-motion: reduce)').matches;
      shader = new ShaderMount(
        lienzo,
        SHADER,
        {
          ...colores(),
          u_shape: DitheringShapes.warp,
          u_type: DitheringTypes['4x4'],
          u_pxSize: PUNTITO,
          u_fit: ShaderFitOptions.none,
          u_scale: ESCALA,
          u_rotation: 0,
          u_offsetX: 0,
          u_offsetY: 0,
          u_originX: 0.5,
          u_originY: 0.5,
          u_worldWidth: 0,
          u_worldHeight: 0,
        },
        undefined,
        quieto ? 0 : VELOCIDAD,
      );
    } catch (error) {
      console.error('[fondo] no se pudo correr el shader del agente; se queda el suelo liso:', error);
    }

    // Si cambia el tema con la vista abierta, cambian los colores.
    const vigia = new MutationObserver(() => shader?.setUniforms(colores()));
    vigia.observe(document.documentElement, { attributes: true, attributeFilter: ['data-tema'] });

    return () => {
      vigia.disconnect();
      shader?.dispose();
    };
  });
</script>

<div class="fondo" bind:this={lienzo} aria-hidden="true"></div>

<style>
  .fondo {
    position: absolute;
    inset: 0;
    z-index: 0;
    background: var(--suelo);
  }
</style>
