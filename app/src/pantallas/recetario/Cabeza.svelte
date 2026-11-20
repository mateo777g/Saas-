<!--
  Lo de arriba de la página del recetario (maqueta DFVTWEB3eZBEKctyxWjGjg v1): la foto de cómo se sirve grande a la
  izquierda (4:3; sin foto propia, la de Mi menú; sin ninguna, el cuadro negro) y a la derecha la categoría (en una
  preparación, «Preparación» con la olla), el nombre, «Para 1 · 6 pasos» (en una preparación, «Rinde 1 l · 5 pasos») y la
  tarjeta «Lo que lleva». En «Editar», la foto la pinta quien la usa (`foto`) y debajo de la tarjeta va su pista.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import './recetario.css';
  import Icono from '../../diseno/Icono.svelte';
  import IconoCategoria from '../../diseno/IconoCategoria.svelte';
  import { plural } from '../../lib/formato';
  import { cantidad } from '../../lib/inventario';
  import { urlDe, type Pagina } from '../../lib/recetario';
  import LoQueLleva from './LoQueLleva.svelte';

  let {
    pagina,
    icono = null,
    pasos,
    porciones = true,
    enAparato = false,
    alAbrirPreparacion = null,
    foto,
    debajo,
  }: {
    pagina: Pagina;
    icono?: string | null; // el de su categoría (de los cuadros)
    pasos: number;
    porciones?: boolean;
    enAparato?: boolean;
    alAbrirPreparacion?: ((id: number) => void) | null;
    foto?: Snippet;
    debajo?: Snippet;
  } = $props();

  const fotoUrl = $derived(urlDe(pagina.foto));
  const sub = $derived(
    pagina.tipo === 'preparacion' && pagina.rinde !== null && pagina.unidad
      ? `Rinde ${cantidad(pagina.rinde, pagina.unidad)} · ${plural(pasos, 'paso', 'pasos')}`
      : `Para 1 · ${plural(pasos, 'paso', 'pasos')}`,
  );
</script>

<div class="rec-cabeza">
  {#if foto}
    {@render foto()}
  {:else}
    <div class="rec-foto" style:background-image={fotoUrl ? `url(${fotoUrl})` : undefined}></div>
  {/if}
  <div class="rec-info">
    <span class="rec-chip">
      {#if pagina.tipo === 'preparacion'}
        <Icono nombre="olla" tamano={13} /><span>Preparación</span>
      {:else}
        {#if icono}<IconoCategoria id={icono} tamano={13} />{/if}<span>{pagina.categoria}</span>
      {/if}
    </span>
    <h2 class="rec-titulo">{pagina.nombre}</h2>
    <p class="rec-sub">{sub}</p>
    {#key pagina.id}
      <LoQueLleva {pagina} {porciones} {enAparato} {alAbrirPreparacion} />
    {/key}
    {@render debajo?.()}
  </div>
</div>
