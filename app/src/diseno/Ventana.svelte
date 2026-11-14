<!--
  ventana() de diseno.py: una tarjeta sólida de radio 26 con la sombra del vidrio, sobre el velo
  del tema. Arriba, la cabeza de la maqueta: la etiqueta ("NUEVO CLIENTE"), el título de 24 y la
  X; debajo, si hay, un texto (13, o 12.5 en Perfil, como en Flet). Lo demás lo pone quien la abre (casi siempre un Formulario).
  `relleno` es 28 por lado, o el de su maqueta (24px 28px en la de un estilo).

  Es un <dialog> del navegador: mientras está abierta, lo de atrás no se puede tocar ni recibe
  el foco. Se cierra con la X, con Escape o con un clic en el velo, como en la maqueta
  (Tbt7H3G1QRXykzNKe1GXHh); el panel decide qué pasa al cerrar (alCerrar).

  `centrado` pone la etiqueta, el título y su texto al centro, con la X en su esquina (las ventanas de producto,
  categoría y grupo de Mi menú, maqueta U9YqpsSb2PeB5pFXTPvh1C; desde el 9 nov 2026, todas las del panel del gerente).
  Los campos de adentro siguen a la izquierda.

  En el panel del gerente se mueven (diseno/ventanaSeMueve.ts; maqueta 4NPDnXrWetC6yFYF7B1EXd v2): salen del centro y al
  cerrar regresan, y el panel espera a que termine antes de quitarla (`|global`, porque la quita el `{#if}` de quien la
  abre); junto a la X va «Agrandar» (1.15 veces); la ventana no pasa del alto de la pantalla y lo de adentro se desliza
  bajo la cabeza fija, desvanecido arriba y abajo mientras hay más. Solo se desliza cuando no cabe: así las listas que se
  abren (Categoría, Área, «Agregar grupo») no se cortan.
-->
<script lang="ts">
  import { flushSync, onMount, type Snippet } from 'svelte';
  import BotonCuadro from './BotonCuadro.svelte';
  import { quitarDeBarra, vidrio } from './vidrio';
  import { ABRE, CRECE, quieto, RESORTE_CSS, seMueven, ventanaSale, veloSale } from './ventanaSeMueve';

  // En Cristal la ventana es vidrio casi sólido (tipo «ventana», diseno/vidrio.ts); lo de adentro nunca es vidrio.
  quitarDeBarra();

  let {
    etiqueta,
    titulo,
    nota,
    texto,
    ancho = 460,
    alto,
    relleno = '28px',
    tamanoTexto = 13,
    centrado = false,
    alCerrar,
    children,
  }: {
    // Sin etiqueta, el título va solo (el color del menú en línea).
    etiqueta?: string;
    titulo: string;
    // Una nota chica debajo del título, junto a la X (la ventana del color del menú en línea).
    nota?: string;
    texto?: string;
    ancho?: number;
    // Un alto fijo, para la que lleva una lista que se recorre dentro (Elige un estilo).
    alto?: number;
    relleno?: string;
    tamanoTexto?: number;
    centrado?: boolean;
    alCerrar: () => void;
    children: Snippet;
  } = $props();

  let dialogo: HTMLDialogElement;
  let caja: HTMLDivElement;
  let desliza: HTMLDivElement;
  const idTitulo = $props.id();
  const mueve = seMueven();

  // El relleno se reparte: arriba y a los lados en la ventana, abajo dentro de lo que se desliza (que llega a las orillas).
  const lados = $derived.by(() => {
    const p = relleno.trim().split(/\s+/);
    return { arriba: p[0], derecha: p[1] ?? p[0], abajo: p[2] ?? p[0], izquierda: p[3] ?? p[1] ?? p[0] };
  });

  // Agrandada: 1.15 veces su ancho y su alto (la pantalla la detiene con max-width y max-height).
  let grande = $state<{ ancho: number; alto: number } | null>(null);
  let desborda = $state(false);
  let masArriba = $state(false);
  let masAbajo = $state(false);

  onMount(() => {
    dialogo.showModal();
    // Como en la maqueta: el foco va al primer campo, no a la X.
    dialogo
      .querySelector<HTMLElement>('input:not([type="file"]), select, textarea')
      ?.focus({ preventScroll: true });
    if (!mueve) return;
    // Lo de adentro se desliza solo si no cabe. Se mide con el fin de cada hijo, no con scrollHeight, que también
    // cuenta las listas abiertas (van con position: absolute) y la haría deslizarse justo al abrir una.
    const ro = new ResizeObserver(medir);
    const observar = () => {
      ro.disconnect();
      ro.observe(desliza);
      for (const h of desliza.children) ro.observe(h);
      medir();
    };
    const mo = new MutationObserver(observar);
    mo.observe(desliza, { childList: true });
    observar();
    return () => {
      ro.disconnect();
      mo.disconnect();
    };
  });

  function medir() {
    let fin = 0;
    for (const h of desliza.children as HTMLCollectionOf<HTMLElement>) {
      fin = Math.max(fin, h.offsetTop + h.offsetHeight + (parseFloat(getComputedStyle(h).marginBottom) || 0));
    }
    desborda = fin + (parseFloat(getComputedStyle(desliza).paddingBottom) || 0) > desliza.clientHeight + 1;
    sombras();
  }

  function sombras() {
    masArriba = desborda && desliza.scrollTop > 1;
    masAbajo = desborda && desliza.scrollTop + desliza.clientHeight < desliza.scrollHeight - 1;
  }

  function agrandar() {
    const antes = { ancho: caja.offsetWidth, alto: caja.offsetHeight };
    grande = grande ? null : { ancho: Math.round(ancho * CRECE), alto: Math.round(antes.alto * CRECE) };
    flushSync();
    const despues = { ancho: caja.offsetWidth, alto: caja.offsetHeight };
    if (quieto()) return;
    caja.animate(
      [
        { width: `${antes.ancho}px`, height: `${antes.alto}px` },
        { width: `${despues.ancho}px`, height: `${despues.alto}px` },
      ],
      { duration: ABRE, easing: RESORTE_CSS },
    );
  }

  function alCancelar(e: Event) {
    // Escape: no la cierra el navegador por su cuenta, la cierra el panel.
    e.preventDefault();
    alCerrar();
  }
</script>

<!-- El clic en el velo es un atajo del ratón; con el teclado se cierra con Escape (oncancel). -->
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogo}
  class="velo"
  aria-labelledby={idTitulo}
  in:veloSale|global={mueve}
  out:veloSale|global={mueve}
  oncancel={alCancelar}
  onclick={(e) => {
    if (e.target === dialogo) alCerrar();
  }}
>
  <div
    bind:this={caja}
    class="ventana"
    use:vidrio={'ventana'}
    class:mueve
    class:fijo={!!alto}
    style:width="{grande ? grande.ancho : ancho}px"
    style:height={grande ? `${grande.alto}px` : alto ? `${alto}px` : undefined}
    style:padding={mueve ? `${lados.arriba} ${lados.derecha} 0 ${lados.izquierda}` : relleno}
    style:--derecha={lados.derecha}
    style:--abajo={lados.abajo}
    style:--izquierda={lados.izquierda}
    in:ventanaSale|global={mueve}
    out:ventanaSale|global={mueve}
  >
    <div class="cabeza" class:centrado class:dos={mueve}>
      <div class="titulos">
        {#if etiqueta}<span class="etiqueta">{etiqueta}</span>{/if}
        <h2 class="titulo" id={idTitulo}>{titulo}</h2>
        {#if nota}<p class="nota">{nota}</p>{/if}
      </div>
      <div class="acciones">
        {#if mueve}
          <BotonCuadro icono={grande ? 'achicar' : 'agrandar'} ayuda={grande ? 'Achicar' : 'Agrandar'} onclick={agrandar} />
        {/if}
        <BotonCuadro icono="cerrar" ayuda="Cerrar" onclick={alCerrar} />
      </div>
    </div>
    <div
      bind:this={desliza}
      class="desliza"
      class:desborda
      class:mas-arriba={masArriba}
      class:mas-abajo={masAbajo}
      onscroll={sombras}
    >
      {#if texto}
        <p class="texto" class:centrado style:font-size="{tamanoTexto}px">{texto}</p>
      {/if}
      {@render children()}
    </div>
  </div>
</dialog>

<style>
  .velo[open] {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    max-width: none;
    max-height: none;
    margin: 0;
    padding: 16px;
    border: 0;
    background: var(--velo);
    color: var(--texto);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: auto;
  }

  .velo::backdrop {
    background: transparent;
  }

  .ventana {
    max-width: 100%;
    margin: auto;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 26px;
    box-shadow: 0 24px 60px var(--sombra);
  }

  /* Cristal: la hoja de vidrio grueso (su receta en cristal.css) lleva su canto. */
  :global(:root[data-estilo='cristal']) .ventana {
    position: relative;
  }

  /* En el gerente, nunca más alta que la pantalla. */
  .ventana.mueve {
    max-height: 100%;
  }

  .cabeza {
    flex: none;
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .acciones {
    flex: none;
    display: flex;
    gap: 8px;
  }

  /* Lo de adentro. En el gerente llega a las orillas de la ventana (su relleno va dentro) y, si no cabe, se desliza
     bajo la cabeza, desvanecido arriba y abajo mientras hay más (el gradientScrollFade del prompt). */
  .desliza {
    position: relative;
    flex: 1 1 auto;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }

  .mueve > .desliza {
    margin: 0 calc(-1 * var(--derecha)) 0 calc(-1 * var(--izquierda));
    padding: 0 var(--derecha) var(--abajo) var(--izquierda);
    border-radius: 0 0 25px 25px;
  }

  /* Lo de adentro no se aplasta: si no cabe, se desliza (la de alto fijo reparte su alto ella misma). */
  .mueve:not(.fijo) > .desliza > :global(*) {
    flex-shrink: 0;
  }

  .desliza.desborda {
    overflow-y: auto;
    scrollbar-width: thin;
  }

  .desliza.mas-arriba {
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 32px);
    mask-image: linear-gradient(to bottom, transparent 0, #000 32px);
  }

  .desliza.mas-abajo {
    -webkit-mask-image: linear-gradient(to top, transparent 0, #000 32px);
    mask-image: linear-gradient(to top, transparent 0, #000 32px);
  }

  .desliza.mas-arriba.mas-abajo {
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 32px, #000 calc(100% - 32px), transparent 100%);
    mask-image: linear-gradient(to bottom, transparent 0, #000 32px, #000 calc(100% - 32px), transparent 100%);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .cabeza.centrado {
    position: relative;
  }

  .centrado .titulos {
    align-items: center;
    text-align: center;
    padding: 0 52px;
  }

  /* Con «Agrandar» junto a la X, el título deja lugar a los dos botones. */
  .centrado.dos .titulos {
    padding: 0 96px;
  }

  .texto.centrado {
    text-align: center;
  }

  .centrado > .acciones {
    position: absolute;
    top: 0;
    right: 0;
  }

  .titulo {
    margin: 0;
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.5px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Al centro, el título que no cabe entre los botones baja a un segundo renglón, parejo (el developer, 13 nov 2026:
     «La banderita de Torta de pastor» se metía debajo de «Agrandar» y la X). */
  .centrado .titulo {
    max-width: 100%;
    white-space: normal;
    text-wrap: balance;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .texto {
    margin: 6px 0 0;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }
</style>
