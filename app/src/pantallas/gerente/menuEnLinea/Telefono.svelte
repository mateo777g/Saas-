<!--
  El teléfono de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59: «El teléfono a la derecha», v35; «El esqueleto
  del teléfono», v36; «El marco del iPhone 16 Pro», v37): el marco del iPhone 16 Pro de 21st.dev (su SVG tal cual, a
  375 × 750) y en su pantalla el menú de verdad (?muestra=menu), dibujado a 390 × 849 como un teléfono de verdad y
  escalado a 0.8268 para caber. Se toca como lo toca un cliente (el menú no manda pedidos ni preguntas de verdad: parte
  C2). Lo que se dicen está arriba de menu/src/lib/muestra.ts y en lib/vistaMenu.ts.

  Mientras el panel lee la primera vez (o el menú todavía no avisa que ya pintó), la pantalla va en el blanco del panel
  con el esqueleto de su menú: el que el menú midió la vez pasada y el panel recuerda por restaurante, pintado con los
  colores del panel (Simple o Cristal); la primera vez, uno general. Cuando ya leyó el panel y el menú avisó, el menú
  aparece en 0.2 s.
-->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import {
    guardarEsqueletoTelefono,
    leerEsqueletoTelefono,
    limpiarEsqueleto,
    linkDeMuestra,
    mandarCerrar,
    mandarModo,
    mandarMuestra,
    oirAlMenu,
    recargarMuestra,
    type EsqueletoTelefono,
    type Muestra,
  } from '../../../lib/vistaMenu';
  import type { Formas } from '../../../lib/formasMenu';

  let {
    slug,
    restauranteId,
    muestra,
    modo,
    leido,
  }: {
    slug: string;
    restauranteId: string;
    // Lo que todavía no guarda: se le manda al menú en cuanto avisa que ya pintó.
    muestra: Muestra;
    modo: 'menu' | 'producto';
    // Si el panel ya leyó (antes de eso no hay qué mandarle).
    leido: boolean;
  } = $props();

  const ANCHO = 390;
  const ALTO = 849;

  let marco = $state<HTMLIFrameElement>();
  let menuListo = $state(false);
  // Si hay algo abierto en el teléfono (para que Escape lo cierre).
  let abierto = false;
  // svelte-ignore state_referenced_locally
  const recordado: EsqueletoTelefono | null = leerEsqueletoTelefono(restauranteId);

  const listo = $derived(leido && menuListo);

  // Lo que se le dice al menú: lo que no se ha guardado (con la forma que se acaba de elegir, para que vaya a ella).
  export function pintar(cambio: keyof Formas | null = null) {
    if (menuListo && leido) mandarMuestra(marco, muestra, cambio);
  }

  // Después de cambiar un cartel: que lo vuelva a leer.
  export function recargar() {
    recargarMuestra(marco);
  }

  // Escape en el panel: si hay algo abierto en el teléfono, lo cierra (y dice que sí lo hizo).
  export function cerrarEncima(): boolean {
    if (!abierto || !listo) return false;
    mandarCerrar(marco);
    return true;
  }

  // El dock: el producto de muestra abierto, o todo cerrado.
  let modoMandado: 'menu' | 'producto' = 'menu';
  $effect(() => {
    const m = modo;
    if (!listo || m === modoMandado) return;
    modoMandado = m;
    mandarModo(marco, m);
  });

  // Ya leyó el panel: que pinte lo suyo (si el menú avisó antes). Después, cada cambio lo manda quien lo hace (pintar),
  // con la forma que cambió.
  $effect(() => {
    if (listo) untrack(() => mandarMuestra(marco, muestra));
  });

  onMount(() =>
    oirAlMenu(
      () => marco,
      (m) => {
        if (m.fragmentless === 'menu-listo') {
          menuListo = true;
          // Si el menú se volvió a armar (otra lectura), regresa a como lo tiene el panel.
          if (leido) {
            mandarMuestra(marco, muestra);
            modoMandado = 'menu';
            if (modo === 'producto') {
              modoMandado = 'producto';
              mandarModo(marco, 'producto');
            }
          }
        } else if (m.fragmentless === 'esqueleto') {
          const e = limpiarEsqueleto(m.esqueleto);
          if (e) guardarEsqueletoTelefono(restauranteId, e);
        } else if (m.fragmentless === 'encima') {
          abierto = !!m.abierto;
        }
      },
    ),
  );

  // Al quitar el esqueleto, el menú aparece en 0.2 s.
  let yaSalio = false;
  $effect(() => {
    if (!listo || yaSalio || !marco) return;
    yaSalio = true;
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches)
      marco.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: 'ease-out' });
  });

  const px = (n: number) => `${n}px`;
  const lugar = (p: number[], dy = 0) =>
    `left:${px(p[0])};top:${px(p[1] + dy)};width:${px(p[2])};height:${px(p[3])};border-radius:${px(p[4])}`;
  // La columna del menú, al centro de la pantalla (en un teléfono mide lo mismo).
  const izquierda = $derived(recordado ? Math.max(0, (ANCHO - recordado.ancho) / 2) : 0);
  const ANCHOS_CATS = [84, 102, 76, 92];
</script>

<aside class="lado" aria-label="Tu menú, como lo ven tus clientes">
  <div class="marco">
    <!-- El cuerpo de metal con sus botones y el bisel negro (21st.dev «iphone-16-pro»). -->
    <svg class="cuerpo" viewBox="0 0 200 400" fill="none" aria-hidden="true"><path fill="#303333" d="M196.11,128.09c0-.25-.2-.45-.45-.45-.11.04-.37.03-.69,0V36.69c0-17.84-14.46-32.31-32.31-32.31H37.48C19.63,4.39,5.17,18.85,5.17,36.69v48.99c-.3.02-.55.03-.66-.02-.25,0-.45.2-.45.45,0,0,0,17.29,0,17.29-.03.41.5.49,1.11.48v13.63c-.61,0-1.14.08-1.11.48,0,0,0,28.54,0,28.54-.03.42.5.49,1.11.48v7.95c-.61,0-1.14.08-1.11.48,0,0,0,28.54,0,28.54-.03.42.5.49,1.11.48v178.86c0,17.84,14.46,32.31,32.31,32.31h125.2c17.84,0,32.31-14.46,32.31-32.31v-188.87c.32-.02.58-.03.69.04,1.26.1.03-45.94.45-46.38ZM186.07,362.63c0,13.56-10.99,24.56-24.56,24.56H38.64c-13.56,0-24.56-10.99-24.56-24.56V37.37c0-13.56,10.99-24.56,24.56-24.56h122.87c13.56,0,24.56,10.99,24.56,24.56v325.26Z"></path><path fill="#000000" d="M161.38,7.29H38.78c-16.54,0-29.95,13.41-29.95,29.95v325.52c0,16.54,13.41,29.95,29.95,29.95h122.6c16.54,0,29.95-13.41,29.95-29.95V37.24c0-16.54-13.41-29.95-29.95-29.95ZM186.07,362.57c0,13.6-11.02,24.62-24.62,24.62H38.7c-13.6,0-24.62-11.02-24.62-24.62V37.43c0-13.6,11.02-24.62,24.62-24.62h122.75c13.6,0,24.62,11.02,24.62,24.62v325.14Z"></path></svg>
    <div class="pantalla" class:cargando={!listo}>
      <iframe
        bind:this={marco}
        class="menu"
        src={linkDeMuestra(slug, 'menu')}
        title="Tu menú, como lo ven tus clientes"
        style:width={px(ANCHO)}
        style:height={px(ALTO)}
      ></iframe>
      {#if !listo}
        <div class="esqueleto" aria-hidden="true">
          <div class="escala" style:width={px(ANCHO)} style:height={px(ALTO)}>
            {#if recordado}
              <div class="columna" style:left={px(izquierda)} style:width={px(recordado.ancho)}>
                {#each recordado.piezas as p, i (i)}
                  <span class="pieza" class:tapa={p[5] === 1} style={lugar(p)}></span>
                {/each}
              </div>
              {#if recordado.abajo}
                <div class="columna abajo" style:left={px(izquierda)} style:width={px(recordado.ancho)} style:height={px(recordado.abajo.alto)}>
                  {#each recordado.abajo.piezas as p, i (i)}
                    <span class="pieza" class:tapa={p[5] === 1} style={lugar(p)}></span>
                  {/each}
                </div>
              {/if}
            {:else}
              <!-- La primera vez: uno general (la barra, el cartel, la búsqueda, las categorías, tres productos y lo de abajo). -->
              <div class="general">
                <div class="g-barra"><span class="pieza" style="width:48px;height:48px;border-radius:12px"></span><span class="pieza" style="width:170px;height:18px"></span></div>
                <div class="g-cuerpo">
                  <span class="pieza" style="width:358px;height:201px;border-radius:18px"></span>
                  <span class="pieza" style="width:358px;height:46px;border-radius:14px"></span>
                  <div class="g-cats">
                    {#each ANCHOS_CATS as w (w)}<span class="pieza" style="width:{w}px;height:36px;border-radius:18px"></span>{/each}
                  </div>
                  <span class="pieza" style="width:120px;height:20px;margin-top:8px"></span>
                  {#each [0, 1, 2] as i (i)}
                    <div class="g-fila">
                      <span class="pieza" style="width:92px;height:92px;border-radius:14px"></span>
                      <div class="g-textos"><span class="pieza" style="width:120px;height:14px"></span><span class="pieza" style="width:150px;height:11px"></span></div>
                      <div class="g-precio"><span class="pieza" style="width:34px;height:14px"></span><span class="pieza" style="width:28px;height:28px;border-radius:14px"></span></div>
                    </div>
                  {/each}
                </div>
                <div class="g-abajo">
                  {#each [0, 1, 2] as i (i)}<span class="pieza" style="width:24px;height:24px;border-radius:7px"></span>{/each}
                </div>
              </div>
            {/if}
          </div>
        </div>
      {/if}
    </div>
    <!-- La isla con su cámara, encima de la pantalla. -->
    <svg class="isla" viewBox="0 0 200 400" fill="none" aria-hidden="true"><path fill="#000000" d="M119.61,33.86h-38.93c-10.48-.18-10.5-15.78,0-15.96,0,0,38.93,0,38.93,0,4.41,0,7.98,3.57,7.98,7.98,0,4.41-3.57,7.98-7.98,7.98Z"></path><path fill="#080d4c" d="M118.78,29.21c-4.32.06-4.32-6.73,0-6.66,4.32-.06,4.32,6.73,0,6.66Z"></path></svg>
  </div>
</aside>

<style>
  /* Fijo mientras bajas por las filas. */
  .lado {
    position: sticky;
    top: 14px;
    display: flex;
    justify-content: center;
  }

  .marco {
    position: relative;
    width: 375px;
    height: 750px;
    flex: none;
  }

  .marco > svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }

  .cuerpo {
    filter: drop-shadow(0 18px 26px var(--sombra));
  }

  .isla {
    z-index: 30;
  }

  /* La pantalla es el rectángulo del SVG (322 × 702, esquinas de 46). */
  .pantalla {
    position: absolute;
    left: 26.4px;
    top: 24.02px;
    width: 322.46px;
    height: 701.94px;
    border-radius: 46.16px;
    background: #000;
    overflow: hidden;
  }

  .menu {
    position: absolute;
    left: 0;
    top: 0;
    border: 0;
    transform: scale(0.8268);
    transform-origin: 0 0;
    background: #000;
  }

  .cargando .menu {
    visibility: hidden;
  }

  /* El esqueleto de su menú, sobre el blanco del panel. */
  .esqueleto {
    position: absolute;
    inset: 0;
    z-index: 9;
    overflow: hidden;
    border-radius: 46.16px;
    background: var(--solido);
  }

  .escala {
    position: absolute;
    left: 0;
    top: 0;
    transform: scale(0.8268);
    transform-origin: 0 0;
  }

  .columna {
    position: absolute;
    top: 0;
    height: 100%;
  }

  .columna.abajo {
    top: auto;
    bottom: 0;
  }

  .columna > .pieza {
    position: absolute;
  }

  .pieza {
    display: block;
    flex: none;
    background: var(--chip);
    border-radius: 6px;
    animation: late 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }

  /* Lo que flota con su fondo (la barra de abajo, las categorías pegadas) tapa lo que pasa por debajo. */
  .pieza.tapa {
    background: var(--solido);
    animation: none;
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .pieza:not(.tapa) {
    background: var(--cristal-esqueleto);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .pieza:not(.tapa) {
    background: var(--cl-esqueleto);
  }

  @keyframes late {
    50% {
      opacity: 0.5;
    }
  }

  .general {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
  }

  .g-barra {
    flex: none;
    height: 112px;
    display: flex;
    align-items: flex-end;
    gap: 14px;
    padding: 0 16px 14px;
  }

  .g-barra > .pieza {
    align-self: center;
    margin-top: 40px;
  }

  .g-cuerpo {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 14px 16px 0;
    overflow: hidden;
  }

  .g-cats {
    display: flex;
    gap: 8px;
  }

  .g-fila {
    display: flex;
    gap: 14px;
    padding: 12px 0;
    border-top: 1px solid var(--linea);
  }

  .g-textos {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding-top: 6px;
  }

  .g-precio {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    justify-content: space-between;
    padding: 6px 0 4px;
  }

  .g-abajo {
    flex: none;
    height: 66px;
    display: flex;
    justify-content: space-around;
    align-items: center;
    padding: 0 40px 10px;
    border-top: 1px solid var(--linea);
  }

  @media (prefers-reduced-motion: reduce) {
    .pieza {
      animation: none;
    }
  }
</style>
