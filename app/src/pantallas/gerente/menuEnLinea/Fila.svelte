<!--
  Una fila de «Tu menú en línea» (maqueta UDArhiEZceT7rmSKxqRA5r v59, «El teléfono a la derecha», v35): una tarjeta con
  su encabezado (el cuadro con su ícono, el nombre y una nota) y debajo sus formas. Las que se acomodan en el menú
  (Carteles, Búsqueda, Categorías; en el modo Producto, el Título) llevan sus flechas a la derecha del nombre; mientras
  la vista lee la primera vez, las flechas van en esqueleto. Si la nota cambia (dónde va el título), cambia con un
  desvanecido corto.
-->
<script module lang="ts">
  export type Flechas = {
    sube: string;
    baja: string;
    puedeSubir: boolean;
    puedeBajar: boolean;
    alMover: (hacia: -1 | 1) => void;
  };
</script>

<script lang="ts">
  import type { Snippet } from 'svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Tarjeta from '../../../diseno/Tarjeta.svelte';

  let {
    clave,
    icono,
    trazos,
    titulo,
    nota,
    flechas,
    cargando = false,
    children,
  }: {
    clave: string;
    icono: string;
    trazos?: string;
    titulo: string;
    nota: string;
    flechas?: Flechas;
    cargando?: boolean;
    children?: Snippet;
  } = $props();

  function aparece(_el: Element) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return { duration: 0 };
    return { duration: 220, css: (x: number) => `opacity: ${x}` };
  }
</script>

<Tarjeta como="section" class="fila-tml" data-fila={clave} aria-label={titulo}>
  <div class="encabezado">
    <span class="cuadro-icono"><Icono nombre={icono} {trazos} tamano={18} /></span>
    <span class="titulos">
      <span class="titulo">{titulo}</span>
      {#key nota}<span class="sub" in:aparece>{nota}</span>{/key}
    </span>
    {#if flechas}
      <span class="mover">
        {#if cargando}
          <Esqueleto ancho="40px" alto="40px" redondo="12px" /><Esqueleto ancho="40px" alto="40px" redondo="12px" />
        {:else}
          <BotonCuadro icono="arriba" ayuda={flechas.sube} grande apagado={!flechas.puedeSubir} onclick={() => flechas.alMover(-1)} />
          <BotonCuadro icono="abajo" ayuda={flechas.baja} grande apagado={!flechas.puedeBajar} onclick={() => flechas.alMover(1)} />
        {/if}
      </span>
    {/if}
  </div>
  {@render children?.()}
</Tarjeta>

<style>
  :global(.fila-tml) {
    flex: none;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  /* Las flechas de las filas que se mueven, a la derecha del título. */
  .mover {
    flex: none;
    display: flex;
    gap: 6px;
    margin-left: auto;
  }
</style>
