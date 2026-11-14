<!--
  El menú en línea de verdad en el celular del cartel de Crear anuncios (13 nov 2026, el developer: «para que salga el
  menú digital verdadero aquí, así como en la vista del panel para editar el menú digital»; planes/trabajo/rediseno/
  crear-anuncios.md). Es el mismo menú que el teléfono de «Tu menú en línea» (menuEnLinea/Telefono.svelte:
  ?muestra=menu, dibujado a 390 × 849 y escalado a 0.8268), con sus formas, colores y tema guardados, y en el lugar de
  sus carteles solo la muestra del estilo, quieta y con su etiqueta «Muestra» (encuesta). La primera muestra va en la
  dirección; al cambiar de estilo se le manda la nueva (menu/src/lib/muestra.ts, «cartel») y el teléfono va a ella.

  No se toca: el celular entero es el botón que elige el formato. Mientras el menú no avisa que ya pintó, la pantalla
  lleva el esqueleto que recuerda «Tu menú en línea» de este restaurante (o el general), como su teléfono; aquí solo se
  lee, porque este menú lleva la muestra en vez de sus carteles.
-->
<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { leerEsqueletoTelefono, linkDeMuestra, oirAlMenu, type EsqueletoTelefono } from '../../../lib/vistaMenu';

  let { slug, restauranteId, ruta }: { slug: string; restauranteId: string; ruta: string | null } = $props();

  const ANCHO = 390;
  const ALTO = 849;

  let marco = $state<HTMLIFrameElement>();
  let listo = $state(false);
  // svelte-ignore state_referenced_locally
  const recordado: EsqueletoTelefono | null = leerEsqueletoTelefono(restauranteId);
  // La dirección se arma una vez, con la muestra de ese momento: las siguientes van por mensaje.
  const direccion = untrack(() => {
    const link = linkDeMuestra(slug, 'menu');
    return ruta ? `${link}&cartel=${encodeURIComponent(ruta)}` : link;
  });
  const origen = new URL(direccion).origin;

  function mandarCartel() {
    marco?.contentWindow?.postMessage({ fragmentless: 'cartel', ruta }, origen);
  }

  // Otro estilo: su muestra (si el menú ya está; si no, la manda al avisar).
  $effect(() => {
    void ruta;
    if (untrack(() => listo)) mandarCartel();
  });

  onMount(() =>
    oirAlMenu(
      () => marco,
      (m) => {
        if (m.fragmentless !== 'menu-listo') return;
        // También cuando el menú vuelve a leer: que siga con la muestra de ahora.
        mandarCartel();
        listo = true;
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
  const lugar = (p: number[]) => `left:${px(p[0])};top:${px(p[1])};width:${px(p[2])};height:${px(p[3])};border-radius:${px(p[4])}`;
  const izquierda = $derived(recordado ? Math.max(0, (ANCHO - recordado.ancho) / 2) : 0);
  const ANCHOS_CATS = [84, 102, 76, 92];
</script>

<div class="pantalla" class:cargando={!listo}>
  <iframe
    bind:this={marco}
    class="menu"
    src={direccion}
    title="Tu menú en línea con la muestra del cartel"
    tabindex="-1"
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
          <!-- Uno general, como el de «Tu menú en línea»: la barra, el cartel, la búsqueda, las categorías, tres
               productos y lo de abajo. -->
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

<style>
  /* Llena la pantalla del celular (322 × 702). */
  .pantalla {
    position: absolute;
    inset: 0;
    background: #000;
  }

  /* No se toca: el clic es del celular, que elige el formato. */
  .menu {
    position: absolute;
    left: 0;
    top: 0;
    border: 0;
    transform: scale(0.8268);
    transform-origin: 0 0;
    background: #000;
    pointer-events: none;
  }

  .cargando .menu {
    visibility: hidden;
  }

  /* Lo de abajo, como el esqueleto del teléfono de «Tu menú en línea» (menuEnLinea/Telefono.svelte). */
  .esqueleto {
    position: absolute;
    inset: 0;
    z-index: 9;
    overflow: hidden;
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
