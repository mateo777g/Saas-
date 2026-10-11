<!--
  La mitad derecha del login (sesion_view.py) y de la suscripción terminada: las manchas con
  grano, "Moderniza Tu Negocio" y la etiqueta de vidrio "Fragmentless · Panel web". Son de los
  no negociables: solo puede cambiar su letra. Oscuras en los dos temas; las manchas son del
  color del acento (naranjas en claro, azules en oscuro).

  Las manchas son el shader original del que salió el diseño: GrainGradient de Paper Shaders
  (forma "corners"), con los mismos valores del componente de 21st.dev que trajo el developer.
  Flet no podía correr shaders y usaba un WebP que lo imitaba; en la web corre el de verdad. Sin
  WebGL se queda el fondo negro, con la frase y la etiqueta encima.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import {
    GrainGradientShapes,
    ShaderFitOptions,
    ShaderMount,
    getShaderColorFromString,
    getShaderNoiseTexture,
    grainGradientFragmentShader,
  } from '@paper-design/shaders';
  import Integral from './Integral.svelte';

  // Los valores del componente original (auth-section-1 de 21st.dev).
  const VELOCIDAD = 1;
  const CUADRO_INICIAL = 2854.5;

  let lienzo: HTMLDivElement;

  // Blanco, acento, acento, blanco, como el original (allá el acento era naranja #FC7819).
  function colores() {
    const acento = getComputedStyle(document.documentElement).getPropertyValue('--acento').trim();
    return ['#FFFFFF', acento, acento, '#FFFFFF'].map(getShaderColorFromString);
  }

  onMount(() => {
    let shader: ShaderMount | null = null;
    let deshecho = false;
    const ruido = getShaderNoiseTexture();

    async function montar() {
      if (!ruido) throw new Error('Paper Shaders no dio la textura de ruido');
      await ruido.decode();
      // Lo mismo que hace el componente de React antes de usar una imagen.
      ruido.width = 1024;
      ruido.height = 1024;
      if (deshecho) return;
      const quieto = matchMedia('(prefers-reduced-motion: reduce)').matches;
      shader = new ShaderMount(
        lienzo,
        grainGradientFragmentShader,
        {
          u_colorBack: getShaderColorFromString('#00000000'),
          u_colors: colores(),
          u_colorsCount: 4,
          u_softness: 0.5,
          u_intensity: 0.5,
          u_noise: 0.25,
          u_shape: GrainGradientShapes.corners,
          u_noiseTexture: ruido,
          u_fit: ShaderFitOptions.contain,
          u_scale: 1,
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
        CUADRO_INICIAL,
      );
    }

    montar().catch((error) => {
      console.error('[manchas] no se pudo correr el shader; se queda el fondo negro:', error);
    });

    // Si cambia el tema con la pantalla abierta, las manchas cambian de color.
    const vigia = new MutationObserver(() => shader?.setUniforms({ u_colors: colores() }));
    vigia.observe(document.documentElement, { attributes: true, attributeFilter: ['data-tema'] });

    return () => {
      deshecho = true;
      vigia.disconnect();
      shader?.dispose();
    };
  });
</script>

<section class="manchas" aria-label="Fragmentless">
  <div class="lienzo" bind:this={lienzo}></div>
  <h2 class="frase">Moderniza<br />Tu Negocio</h2>
  <div class="marca">
    <Integral ancho={21} alto={23} />
    <span><b>Fragmentless</b> · Panel web</span>
  </div>
</section>

<style>
  .manchas {
    position: relative;
    min-width: 0;
    border-radius: 22px;
    overflow: hidden;
    border: 1px solid rgba(255, 255, 255, 0.12);
    background: #000000;
    color: #ffffff;
  }

  .lienzo {
    position: absolute;
    inset: 0;
  }

  /* A 48 del borde y 56 arriba, como el título de la tarjeta de al lado. */
  .frase {
    position: absolute;
    left: 48px;
    top: 56px;
    margin: 0;
    font-size: 56px;
    font-weight: 800;
    line-height: 1.04;
    letter-spacing: -1.68px;
  }

  .marca {
    position: absolute;
    left: 48px;
    right: 48px;
    bottom: 48px;
    height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 22px 0 18px;
    border-radius: 12px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.25);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    font-size: 15px;
    font-weight: 500;
    opacity: 0.85;
  }

  .marca b {
    font-weight: 700;
  }
</style>
