<!--
  Las categorías arriba de la lista, con su ícono y su nombre, como Casa Colega (libreta 6): la
  elegida en negritas con la raya del color de Don Chuy; no son píldoras. Al bajar se quedan pegadas
  arriba; quien las pone marca la de la sección que se ve, y al tocar otra baja hasta ella.
-->
<script lang="ts">
  import type { Categoria } from '../lib/datos';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Icono from './Icono.svelte';

  let {
    categorias,
    activa,
    lengua,
    t,
    pegadas = true,
    alElegir,
  }: {
    categorias: Categoria[];
    activa: number | null;
    lengua: Lengua;
    t: Textos;
    // En la tira de la ventana del color no se pegan: no hay nada que bajar.
    pegadas?: boolean;
    alElegir?: (id: number) => void;
  } = $props();

  let nav: HTMLElement;

  // La marcada siempre se ve en la fila, aunque haya que recorrerla.
  $effect(() => {
    const boton = nav.querySelector<HTMLElement>(`[data-categoria="${activa}"]`);
    if (!boton) return;
    const izq = boton.offsetLeft - 16;
    const der = boton.offsetLeft + boton.offsetWidth + 16 - nav.clientWidth;
    if (nav.scrollLeft > izq) nav.scrollTo({ left: izq, behavior: 'smooth' });
    else if (nav.scrollLeft < der) nav.scrollTo({ left: der, behavior: 'smooth' });
  });
</script>

<nav class="pestanas" class:pegadas bind:this={nav} aria-label={t.categorias}>
  {#each categorias as c (c.id)}
    <button
      type="button"
      class="pestana"
      class:activa={c.id === activa}
      aria-current={c.id === activa ? 'true' : undefined}
      data-categoria={c.id}
      onclick={() => alElegir?.(c.id)}
    >
      <Icono categoria={c.icono} tamano={17} />{enSuLengua(c.nombre, c.nombre_en, lengua)}
    </button>
  {/each}
</nav>

<style>
  .pestanas {
    z-index: 2;
    background: var(--m-fondo);
    padding: 0 16px;
    display: flex;
    gap: 22px;
    overflow-x: auto;
    scrollbar-width: none;
    border-bottom: 1px solid var(--m-linea);
  }

  .pestanas.pegadas {
    position: sticky;
    top: 0;
    margin-top: 8px;
  }

  .pestanas::-webkit-scrollbar {
    display: none;
  }

  .pestana {
    position: relative;
    height: 48px;
    padding: 0 1px;
    border: 0;
    background: transparent;
    color: var(--m-suave);
    font-size: 14px;
    font-weight: 600;
    display: flex;
    align-items: center;
    gap: 7px;
    white-space: nowrap;
    flex: none;
  }

  .pestana.activa {
    color: var(--m-texto);
    font-weight: 800;
  }

  .pestana.activa::after {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    bottom: -1px;
    height: 3px;
    border-radius: 2px;
    background: var(--m-acento);
  }
</style>
