<!--
  Un botón con su listita debajo («Tu menú en línea», maqueta UDArhiEZceT7rmSKxqRA5r): el mundito del
  idioma, las monedas, «Ordenar por» de la búsqueda y los renglones de Ajustes. La listita se abre como
  las del panel (el fondo crece con su resorte y cada opción llega con el suyo, una tras otra) y se
  cierra al elegir, al tocar afuera o con Escape; solo hay una abierta a la vez. Al elegir, primero se
  cierra y luego cambia el menú, como en la maqueta (260 ms; sin espera con «reducir movimiento»).
  El botón lo pone quien la usa (`boton`), para que lleve su forma.
-->
<script lang="ts" module>
  // La que está abierta, para cerrarla cuando se abre otra.
  let cerrarLaAbierta: (() => void) | null = null;
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';
  import Bandera from './Bandera.svelte';
  import Icono from './Icono.svelte';

  type Opcion = { valor: string; texto: string; bandera?: 'mx' | 'us'; icono?: string };

  let {
    opciones,
    elegida,
    etiqueta,
    clase = '',
    boton,
    alElegir,
  }: {
    opciones: Opcion[];
    elegida: string;
    etiqueta: string;
    // f-ordenar para la de la búsqueda (es un poco más angosta).
    clase?: string;
    boton: Snippet<[{ abierta: boolean; alternar: () => void }]>;
    alElegir: (valor: string) => void;
  } = $props();

  let abierta = $state(false);
  let caja: HTMLSpanElement;

  function cerrar() {
    abierta = false;
    if (cerrarLaAbierta === cerrar) cerrarLaAbierta = null;
  }

  function alternar() {
    if (abierta) return cerrar();
    cerrarLaAbierta?.();
    abierta = true;
    cerrarLaAbierta = cerrar;
  }

  function elegir(valor: string) {
    cerrar();
    const quieto = matchMedia('(prefers-reduced-motion: reduce)').matches;
    setTimeout(() => alElegir(valor), quieto ? 0 : 260);
  }

  $effect(() => {
    if (!abierta) return;
    const afuera = (e: PointerEvent) => {
      if (!caja.contains(e.target as Node)) cerrar();
    };
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        cerrar();
      }
    };
    document.addEventListener('pointerdown', afuera, true);
    document.addEventListener('keydown', tecla, true);
    return () => {
      document.removeEventListener('pointerdown', afuera, true);
      document.removeEventListener('keydown', tecla, true);
    };
  });
</script>

<span class="f-boton-lista {clase}" class:abierta bind:this={caja}>
  {@render boton({ abierta, alternar })}
  <div class="f-lista" style:--alto="{opciones.length * 48 + 8}px">
    <div class="f-lista-fondo"></div>
    <div class="f-lista-ops" role="listbox" aria-label={etiqueta}>
      {#each opciones as o, i (o.valor)}
        <button
          type="button"
          role="option"
          class="f-op"
          class:elegida={o.valor === elegida}
          aria-selected={o.valor === elegida}
          tabindex={abierta ? 0 : -1}
          style:--i={i}
          style:--y="{i * 48 + 42}px"
          style:--dc="{(opciones.length - 1 - i) * 20}ms"
          onclick={() => elegir(o.valor)}
        >
          {#if o.bandera}<Bandera pais={o.bandera} />{:else if o.icono}<span class="f-op-icono"><Icono nombre={o.icono} tamano={18} /></span>{/if}
          <span class="f-op-texto">{o.texto}</span>
          <span class="f-op-marca"><Icono nombre="check" tamano={16} grosor={2.2} /></span>
        </button>
      {/each}
    </div>
  </div>
</span>
