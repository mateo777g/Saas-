<!--
  boton() de diseno.py y los botones grandes del login y de la suscripción terminada.
    tono      linea: borde fino, sin relleno (los secundarios)
              tinta: el principal (negro en claro, blanco en oscuro)
              acento: azul (Conectar Mercado Pago, Renovar)
              verde: el que guarda o agrega en las ventanas del panel del gerente, como el «Arrow Fill
                Button» de Hyperiux (Mi menú, versión 8): rectángulo de 44 con un cuadrito blanco a la derecha;
                con el mouse encima, al tocarlo (450 ms) o con el teclado, el blanco crece hasta llenarlo,
                la letra se vuelve verde y el ícono sale por la derecha mientras entra otro. «Agregar…»
                lleva el +; lo demás, la flecha. Mientras guarda, el círculo gira; listo, la palomita.
              peligro: lo que borra, con contorno rojo (Eliminar producto, el anuncio abierto), como el
                «Flow Button» (versión 9): un círculo nace del centro y lo llena, el
                texto se recorre y el ícono cruza de lado. 44 de alto.
              peligro-lleno: el mismo, lleno de rojo, el «Sí, eliminar» de Confirmar. 40 de alto.
              alarga: las acciones sencillas, como el «Expanding Icon Button» (versión 13): un cuadro de
                40 con su ícono que, con el mouse encima, al tocarlo o con el teclado, se alarga justo lo
                que mide su texto (Cancelar). En tinta.
              Desde el 9 nov 2026 ninguno es píldora ni círculo: todos llevan las esquinas de 12 de los de
              la barra de arriba (regla de diseño «Los botones»); sus animaciones no cambiaron.
    tamano    normal: 40 de alto, letra 13 (la barra de arriba, las ventanas)
              grande: 48 de alto, letra 14, a todo lo ancho (el login)
              chico: 34 de alto, letra 12.5, icono 14 ("Ver clientes →")
    apagado   apagar() de diseno.py: al 40 % y sin clic (entrando, Actualizar mientras lee)
    cargando  la rueda que gira en lugar del icono, sin clic ("Guardando…" de una ventana)
    exito     la palomita verde en lugar del icono, sin clic (el éxito se ve en el botón, ~1.6 s); en el
              verde y los rojos, en blanco o en su círculo
    iconoAlFinal  el icono después del texto, como la flecha de "Ver clientes →"
    chip      el relleno de chip, sin perder el borde (Cancelar de Ocultar varios)
    ayuda     la cajita que sale con el cursor encima («Primero crea una categoría»; diseno/pista.ts)
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Icono from './Icono.svelte';
  import { ICONOS } from './iconos';
  import { pista } from './pista';
  import { enBarra, pica, vidrio } from './vidrio';

  let {
    etiqueta,
    icono,
    tono = 'linea',
    tamano = 'normal',
    apagado = false,
    cargando = false,
    exito = false,
    iconoAlFinal = false,
    chip = false,
    ayuda,
    tipo = 'button',
    onclick,
    ...resto
  }: {
    etiqueta: string;
    icono?: string;
    tono?: 'linea' | 'tinta' | 'acento' | 'verde' | 'peligro' | 'peligro-lleno' | 'alarga';
    tamano?: 'normal' | 'grande' | 'chico';
    apagado?: boolean;
    cargando?: boolean;
    exito?: boolean;
    iconoAlFinal?: boolean;
    chip?: boolean;
    ayuda?: string;
    tipo?: 'button' | 'submit';
    onclick?: (e: MouseEvent) => void;
    [dato: `aria-${string}`]: string | undefined;
  } = $props();

  // En Cristal, el de contorno de la barra de arriba («Ocultar varios») es vidrio (diseno/vidrio.ts); la acción
  // principal («Nuevo producto», en tinta) sigue sólida.
  const deBarra = enBarra();

  const lado = $derived(tamano === 'chico' ? 14 : 16);
  const FLECHA = '<path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path>';
  const MAS = '<path d="M12 5v14"></path><path d="M5 12h14"></path>';
  const PALOMITA = '<path stroke-width="2.4" d="M5 12l5 5L20 7"></path>';
  const flujo = $derived(tono === 'peligro' || tono === 'peligro-lleno');
  // El ícono del verde: + en «Agregar…», la flecha en lo demás; listo, la palomita.
  const trazoVerde = $derived(exito ? PALOMITA : /^Agregar/.test(etiqueta) ? MAS : FLECHA);
  const trazoRojo = $derived(exito ? PALOMITA : icono ? (ICONOS[icono] ?? '') : '');

  // Al tocarlo con el dedo se queda «encima» 450 ms, como con el mouse (el verde, los rojos y el que se
  // alarga).
  let encima = $state(false);
  let suelta: ReturnType<typeof setTimeout> | undefined;
  function alApretar(e: PointerEvent) {
    if (e.pointerType === 'mouse') return;
    clearTimeout(suelta);
    encima = true;
  }
  function alSoltar(e: PointerEvent) {
    if (e.pointerType === 'mouse') return;
    suelta = setTimeout(() => (encima = false), 450);
  }

  // Lo que se alarga: justo lo que mide su texto (12 + 32 + texto + 8 + 12 px).
  let texto = $state<HTMLSpanElement>();
  let ancho = $state(128);
  function medir() {
    if (texto) ancho = Math.ceil(texto.getBoundingClientRect().width - 8) + 64;
  }
  onMount(() => {
    if (tono !== 'alarga') return;
    medir();
    document.fonts?.ready.then(medir).catch((falla) => console.error('[boton] no se pudieron medir las letras', falla));
    return () => clearTimeout(suelta);
  });
</script>

{#if tono === 'alarga'}
  <button
    type={tipo}
    class="alarga"
    class:encima
    style:--ba-ancho="{ancho}px"
    use:pista={ayuda}
    disabled={apagado || cargando || exito}
    {onclick}
    onpointerdown={alApretar}
    onpointerup={alSoltar}
    onpointercancel={alSoltar}
    {...resto}
  >
    <svg class="ba-icono" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{@html icono ? (ICONOS[icono] ?? '') : ''}</svg>
    <span class="ba-texto" bind:this={texto}>{etiqueta}</span>
  </button>
{:else if tono === 'verde'}
  <button
    type={tipo}
    class="boton verde"
    class:encima
    class:cargando
    class:apagado
    use:pista={ayuda}
    disabled={apagado || cargando || exito}
    {onclick}
    onpointerdown={alApretar}
    onpointerup={alSoltar}
    onpointercancel={alSoltar}
    {...resto}
  >
    <span class="bf-texto">{etiqueta}</span>
    <span class="bf-relleno" aria-hidden="true"></span>
    <span class="bf-texto-relleno" aria-hidden="true"><span>{etiqueta}</span></span>
    <span class="bf-circulo" aria-hidden="true">
      <svg class="bf-i1" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{@html trazoVerde}</svg>
      <svg class="bf-i2" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{@html trazoVerde}</svg>
    </span>
  </button>
{:else if flujo}
  <button
    type={tipo}
    class="boton flujo"
    class:lleno={tono === 'peligro-lleno'}
    class:encima
    class:cargando
    use:pista={ayuda}
    disabled={apagado || cargando || exito}
    {onclick}
    onpointerdown={alApretar}
    onpointerup={alSoltar}
    onpointercancel={alSoltar}
    {...resto}
  >
    <svg class="bfl-izq" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{@html trazoRojo}</svg>
    <span class="bfl-texto">{etiqueta}</span>
    <span class="bfl-circulo" aria-hidden="true"></span>
    {#if cargando}
      <span class="bfl-der rueda" aria-hidden="true"></span>
    {:else}
      <svg class="bfl-der" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{@html trazoRojo}</svg>
    {/if}
  </button>
{:else}
  <button
    type={tipo}
    class="boton {tono} {tamano}"
    class:apagado
    class:chip
    use:pista={ayuda}
    use:vidrio={deBarra && tono === 'linea' ? 'control' : null}
    use:pica={deBarra && tono === 'linea' ? 1.05 : null}
    disabled={apagado || cargando || exito}
    {onclick}
    {...resto}
  >
    {#if cargando}
      <span class="rueda" aria-hidden="true"></span>
    {:else if exito}
      <span class="verde-check"><Icono nombre="check" tamano={lado} /></span>
    {:else if icono && !iconoAlFinal}
      <Icono nombre={icono} tamano={lado} />
    {/if}
    <span>{etiqueta}</span>
    {#if icono && iconoAlFinal && !cargando && !exito}
      <Icono nombre={icono} tamano={lado} />
    {/if}
  </button>
{/if}

<style>
  .boton {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 40px;
    padding: 0 14px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton:hover:not(:disabled) {
    opacity: 0.86;
  }

  .boton:disabled {
    cursor: default;
  }

  .apagado {
    opacity: 0.4;
  }

  .chip {
    background: var(--chip);
  }

  .tinta {
    padding: 0 16px;
    border: 0;
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .acento {
    padding: 0 16px;
    border: 0;
    background: var(--acento);
    color: var(--sobre-acento);
  }

  .grande {
    width: 100%;
    height: 48px;
    font-size: 14px;
  }

  .chico {
    gap: 6px;
    height: 34px;
    padding: 0 12px;
    font-size: 12.5px;
  }

  .verde-check {
    color: var(--verde);
  }

  .rueda {
    width: 14px;
    height: 14px;
    flex: none;
    border-radius: 50%;
    border: 2px solid currentColor;
    border-top-color: transparent;
    animation: girar 0.8s linear infinite;
  }

  @keyframes girar {
    to {
      transform: rotate(360deg);
    }
  }

  /* ─── El verde (Hyperiux): su misma curva y su mismo tiempo, cubic-bezier(0.785, 0.135, 0.15, 0.86), 450 ms.
     Un poco más oscuro que el punto de «en vivo», para que la letra blanca se lea. */
  .boton.verde {
    --bf-fondo: #2b8449;
    --bf-letra: #ffffff;
    --bf-blanco: #ffffff;
    --bf-circulo: 32px;
    --bf-derecha: 6px;
    --bf-y: calc((100% - var(--bf-circulo)) / 2);
    --bf-curva: cubic-bezier(0.785, 0.135, 0.15, 0.86);
    --bf-pad: 0 calc(var(--bf-circulo) + var(--bf-derecha) + 14px) 0 22px;
    position: relative;
    isolation: isolate;
    overflow: hidden;
    height: 44px;
    padding: var(--bf-pad);
    justify-content: flex-start;
    gap: 0;
    border: 1px solid var(--bf-fondo);
    border-radius: 12px;
    background: var(--bf-fondo);
    color: var(--bf-letra);
    font: 600 13.5px var(--jakarta);
    white-space: nowrap;
  }

  .bf-texto {
    position: relative;
    z-index: 1;
  }

  .bf-relleno {
    position: absolute;
    z-index: 2;
    inset: var(--bf-y) var(--bf-derecha) var(--bf-y) calc(100% - var(--bf-derecha) - var(--bf-circulo));
    border-radius: 8px;
    background: var(--bf-blanco);
    pointer-events: none;
    transition: inset 0.45s var(--bf-curva);
  }

  .bf-texto-relleno {
    position: absolute;
    z-index: 2;
    inset: 0;
    display: flex;
    align-items: center;
    padding: var(--bf-pad);
    color: var(--bf-fondo);
    clip-path: inset(var(--bf-y) var(--bf-derecha) var(--bf-y) calc(100% - var(--bf-derecha) - var(--bf-circulo)));
    pointer-events: none;
    transition: clip-path 0.45s var(--bf-curva);
  }

  .bf-circulo {
    position: absolute;
    z-index: 3;
    right: var(--bf-derecha);
    top: 50%;
    width: var(--bf-circulo);
    height: var(--bf-circulo);
    transform: translateY(-50%);
    overflow: hidden;
    border-radius: 8px;
    background: var(--bf-blanco);
    color: var(--bf-fondo);
    pointer-events: none;
  }

  .bf-circulo svg {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 16px;
    height: 16px;
    transition: transform 0.45s var(--bf-curva);
  }

  .bf-i1 {
    transform: translate(-170%, -50%) scale(0);
  }

  .bf-i2 {
    transform: translate(-50%, -50%);
  }

  .verde:not(:disabled):hover .bf-relleno,
  .verde.encima .bf-relleno,
  .verde:focus-visible .bf-relleno {
    inset: 0;
  }

  .verde:not(:disabled):hover .bf-texto-relleno,
  .verde.encima .bf-texto-relleno,
  .verde:focus-visible .bf-texto-relleno {
    clip-path: inset(0 0 0 0);
  }

  .verde:not(:disabled):hover .bf-i1,
  .verde.encima .bf-i1,
  .verde:focus-visible .bf-i1 {
    transform: translate(-50%, -50%) scale(1);
  }

  .verde:not(:disabled):hover .bf-i2,
  .verde.encima .bf-i2,
  .verde:focus-visible .bf-i2 {
    transform: translate(70%, -50%) scale(0);
  }

  .boton.verde:focus-visible {
    outline: 2px solid var(--bf-fondo);
    outline-offset: 2px;
  }

  .boton.verde.apagado {
    opacity: 0.4;
  }

  .verde.cargando .bf-circulo svg {
    display: none;
  }

  .verde.cargando .bf-circulo::after {
    content: '';
    position: absolute;
    inset: 9px;
    border-radius: 50%;
    border: 2px solid currentColor;
    border-top-color: transparent;
    animation: girar 0.8s linear infinite;
  }

  /* ─── Los rojos (Flow Button), con sus mismas curvas y tiempos, con las esquinas de 12. Con contorno el
     círculo es rojo y la letra se vuelve blanca; lleno, el círculo es un rojo más oscuro. */
  .boton.flujo {
    --bfl-c1: cubic-bezier(0.23, 1, 0.32, 1);
    --bfl-c2: cubic-bezier(0.34, 1.56, 0.64, 1);
    --bfl-c3: cubic-bezier(0.19, 1, 0.22, 1);
    --rojo-encima: #b0372f;
    position: relative;
    isolation: isolate;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 44px;
    padding: 0 32px;
    gap: 0;
    border: 1.5px solid color-mix(in srgb, var(--rojo) 45%, transparent);
    border-radius: 12px;
    background: transparent;
    color: var(--rojo);
    font: 600 13.5px var(--jakarta);
    white-space: nowrap;
    cursor: pointer;
    transition:
      border-color 0.6s var(--bfl-c1),
      color 0.6s var(--bfl-c1),
      transform 0.2s ease;
  }

  .boton.flujo.lleno {
    background: var(--rojo);
    border-color: var(--rojo);
    color: #ffffff;
    height: 40px;
  }

  .bfl-texto {
    position: relative;
    z-index: 1;
    transform: translateX(-12px);
    transition: transform 0.8s ease-out;
  }

  .bfl-circulo {
    position: absolute;
    top: 50%;
    left: 50%;
    width: 16px;
    aspect-ratio: 1;
    border-radius: 50%;
    background: var(--rojo);
    opacity: 0;
    transform: translate(-50%, -50%);
    pointer-events: none;
    transition:
      width 0.8s var(--bfl-c3),
      opacity 0.8s var(--bfl-c3);
  }

  .lleno .bfl-circulo {
    background: var(--rojo-encima);
  }

  .flujo svg,
  .flujo .bfl-der.rueda {
    position: absolute;
    z-index: 9;
    top: 50%;
    width: 16px;
    height: 16px;
    transform: translateY(-50%);
    transition:
      left 0.8s var(--bfl-c2),
      right 0.8s var(--bfl-c2);
  }

  .flujo .bfl-der.rueda {
    width: 14px;
    height: 14px;
    margin-top: -7px;
    transform: none;
    animation: girar 0.8s linear infinite;
  }

  .bfl-izq {
    left: -25%;
  }

  .bfl-der {
    right: 16px;
  }

  .boton.flujo:not(:disabled):hover,
  .boton.flujo.encima,
  .boton.flujo:focus-visible {
    border-color: transparent;
    color: #ffffff;
  }

  .boton.flujo.lleno:not(:disabled):hover,
  .boton.flujo.lleno.encima,
  .boton.flujo.lleno:focus-visible {
    border-color: var(--rojo-encima);
  }

  .flujo:not(:disabled):hover .bfl-texto,
  .flujo.encima .bfl-texto,
  .flujo:focus-visible .bfl-texto {
    transform: translateX(12px);
  }

  .flujo:not(:disabled):hover .bfl-circulo,
  .flujo.encima .bfl-circulo,
  .flujo:focus-visible .bfl-circulo {
    width: 150%;
    opacity: 1;
  }

  .flujo:not(:disabled):hover .bfl-izq,
  .flujo.encima .bfl-izq,
  .flujo:focus-visible .bfl-izq {
    left: 16px;
  }

  .flujo:not(:disabled):hover .bfl-der,
  .flujo.encima .bfl-der,
  .flujo:focus-visible .bfl-der {
    right: -25%;
  }

  .boton.flujo:not(:disabled):active {
    transform: scale(0.95);
  }

  .boton.flujo:focus-visible {
    outline: 2px solid var(--rojo);
    outline-offset: 2px;
  }

  .boton.flujo:disabled {
    opacity: 0.4;
    cursor: default;
  }

  /* Guardando: se queda quieto, sin apagarse. */
  .boton.flujo.cargando {
    opacity: 1;
  }

  /* ─── El que se alarga (Expanding Icon Button): sus mismos tiempos y curvas, 300 ms con
     cubic-bezier(0.4, 0, 0.2, 1). Como en el original, el ícono no anima «left», solo su translate. */
  .alarga {
    --ba-fondo: var(--tinta);
    --ba-letra: var(--sobre-tinta);
    --ba-curva: cubic-bezier(0.4, 0, 0.2, 1);
    position: relative;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    box-sizing: border-box;
    width: 40px;
    height: 40px;
    padding: 0 12px;
    overflow: hidden;
    border: 0;
    border-radius: 12px;
    background: var(--ba-fondo);
    color: var(--ba-letra);
    font: 600 13.5px var(--jakarta);
    white-space: nowrap;
    cursor: pointer;
    transition: width 0.3s var(--ba-curva);
  }

  .ba-icono {
    position: absolute;
    top: 50%;
    left: 50%;
    width: 16px;
    height: 16px;
    transform: translate(-50%, -50%);
    transition: transform 0.3s var(--ba-curva);
  }

  .ba-texto {
    margin-left: 32px;
    padding-right: 8px;
    white-space: nowrap;
    opacity: 0;
    transition: opacity 0.3s var(--ba-curva);
  }

  .alarga:not(:disabled):hover,
  .alarga.encima,
  .alarga:focus-visible {
    width: var(--ba-ancho);
    background: color-mix(in srgb, var(--ba-fondo) 90%, transparent);
  }

  .alarga:not(:disabled):hover .ba-icono,
  .alarga.encima .ba-icono,
  .alarga:focus-visible .ba-icono {
    left: 12px;
    transform: translate(0, -50%);
  }

  .alarga:not(:disabled):hover .ba-texto,
  .alarga.encima .ba-texto,
  .alarga:focus-visible .ba-texto {
    opacity: 1;
  }

  .alarga:focus-visible {
    outline: 2px solid var(--ba-fondo);
    outline-offset: 2px;
  }

  .alarga:disabled {
    opacity: 0.5;
    cursor: default;
  }

  /* Cristal: el verde de guardar y el rojo de eliminar se quedan, con un brillo arriba (libreta 4, «El estilo
     Cristal»; maqueta FiHkjmT1meyTu7zuU3En2n, sección 9). */
  :global(:root[data-estilo='cristal']) .boton.verde {
    background-image: linear-gradient(180deg, rgba(255, 255, 255, 0.22), rgba(255, 255, 255, 0) 55%);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .boton.verde {
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.35),
      0 8px 22px -8px rgba(63, 155, 90, 0.6);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .boton.verde {
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.35),
      0 8px 22px -8px rgba(63, 155, 90, 0.5);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .boton.flujo:not(.lleno) {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0)), rgba(212, 71, 62, 0.08);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .boton.flujo:not(.lleno) {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.5), rgba(255, 255, 255, 0.15)), rgba(212, 71, 62, 0.06);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.8);
  }

  @media (prefers-reduced-motion: reduce) {
    .boton.verde *,
    .boton.flujo,
    .boton.flujo *,
    .alarga,
    .alarga * {
      transition: none !important;
    }
  }
</style>
