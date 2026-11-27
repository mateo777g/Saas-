<!--
  La tarjeta de una carta leída en la plática (el menú con IA; maqueta 1Y6NCBNSZwWCVatj17iCDA, «Lo que elegí yo» 7 y 13
  de la v1): la del «Reporte en PDF» con el libro de Mi menú, «Leí tu carta», cuántas categorías, productos y dudas
  (las dudas en ámbar) y «Revisar y subir». Ya subida, la palomita verde, «Subí 18 productos a tu menú», qué entró
  dónde y «Ver Mi menú», con un rebote. No se sube dos veces.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { dudaAhora, textoSubida, type CartaGuardada } from '../../../lib/carta';
  import { plural } from '../../../lib/formato';

  let {
    carta,
    alRevisar,
    alVerMenu,
  }: { carta: CartaGuardada; alRevisar: () => void; alVerMenu: () => void } = $props();

  const productos = $derived(carta.categorias.reduce((n, c) => n + c.productos.length, 0));
  const dudas = $derived(carta.categorias.reduce((n, c) => n + c.productos.filter((p) => dudaAhora(p)).length, 0));
  const quieto = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Al subirse, la tarjeta rebota (solo si cambió aquí, no al abrirla del Historial ya subida).
  // svelte-ignore state_referenced_locally
  let yaSubida = !!carta.subida;
  let tarjeta = $state<HTMLDivElement | null>(null);
  $effect(() => {
    if (!carta.subida || yaSubida) return;
    yaSubida = true;
    if (!quieto)
      tarjeta?.animate(
        [
          { transform: 'scale(0.98)', opacity: 0.6 },
          { transform: 'none', opacity: 1 },
        ],
        { duration: 400, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' },
      );
  });
</script>

<div class="archivo" bind:this={tarjeta}>
  {#if carta.subida}
    <span class="doc listo"><Icono nombre="check" tamano={18} /></span>
    <span class="arch-textos">
      <span class="nombre-arch">Subí {plural(carta.subida.productos, 'producto', 'productos')} a tu menú</span>
      <span class="det">{textoSubida(carta.subida)}</span>
    </span>
    <button type="button" class="boton-chico" onclick={alVerMenu}>Ver Mi menú</button>
  {:else}
    <span class="doc"><Icono nombre="r-menu" tamano={18} /></span>
    <span class="arch-textos">
      <span class="nombre-arch">Leí tu carta</span>
      <span class="det"
        >{plural(carta.categorias.length, 'categoría', 'categorías')} · {plural(productos, 'producto', 'productos')}{#if dudas}{' · '}<span class="ambar">{plural(dudas, 'duda', 'dudas')}</span>{/if}</span
      >
    </span>
    <button type="button" class="boton-chico" onclick={alRevisar}>Revisar y subir</button>
  {/if}
</div>

<style>
  /* La del «Reporte en PDF» (ArchivoReporte.svelte), con su ícono en lugar de «PDF». */
  .archivo {
    display: flex;
    align-items: center;
    gap: 12px;
    max-width: 480px;
    padding: 12px 14px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
  }

  .doc {
    width: 36px;
    height: 44px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 6px;
    background: var(--chip);
    color: var(--texto);
  }

  .doc.listo {
    color: var(--verde);
  }

  .arch-textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .nombre-arch {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 600;
    line-height: 1.6;
  }

  .det {
    font-size: 12px;
    line-height: 1.6;
    color: var(--suave);
  }

  .ambar {
    color: var(--amarillo-texto);
    font-weight: 600;
  }

  .boton-chico {
    height: 30px;
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 11px;
    border: 1px solid var(--linea);
    border-radius: 8px;
    background: none;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
  }

  .boton-chico:hover {
    border-color: var(--linea-fuerte);
  }
</style>
