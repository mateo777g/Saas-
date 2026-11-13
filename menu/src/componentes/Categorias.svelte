<!--
  Las categorías arriba de los productos con las formas de «Tu menú en línea» (maqueta
  UDArhiEZceT7rmSKxqRA5r): las pestañas de siempre (Pestanas.svelte), rectángulos con su ícono,
  rectángulos dentro de una tarjeta, píldoras blancas con su ícono, o círculos con su ícono o con la foto
  de su primer producto que tenga foto (sin ninguna, su ícono). La elegida va en el color de tu menú.
  Al bajar se quedan pegadas arriba; quien las pone marca la de la sección que se ve, y al tocar otra
  baja hasta ella.
-->
<script lang="ts">
  import { urlImagen, type Categoria } from '../lib/datos';
  import type { Formas } from '../lib/formas';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Icono from './Icono.svelte';
  import Pestanas from './Pestanas.svelte';

  let {
    categorias,
    activa,
    forma,
    lengua,
    t,
    pegadas = true,
    nav = $bindable(),
    alElegir,
  }: {
    categorias: Categoria[];
    activa: number | null;
    forma: Formas['categorias'];
    lengua: Lengua;
    t: Textos;
    pegadas?: boolean;
    // Para medir cuánto tapa al bajar (Menu.svelte).
    nav?: HTMLElement;
    alElegir?: (id: number) => void;
  } = $props();

  // La tira que se recorre: la tarjeta, si va en tarjeta; si no, la de las categorías.
  let interior = $state<HTMLElement>();
  const tira = $derived(forma === 'tarjeta' ? interior : nav);

  // La marcada siempre se ve en la fila, aunque haya que recorrerla.
  $effect(() => {
    if (!tira) return;
    const boton = tira.querySelector<HTMLElement>(`[data-categoria="${activa}"]`);
    if (!boton) return;
    const izq = boton.offsetLeft - 16;
    const der = boton.offsetLeft + boton.offsetWidth + 16 - tira.clientWidth;
    if (tira.scrollLeft > izq) tira.scrollTo({ left: izq, behavior: 'smooth' });
    else if (tira.scrollLeft < der) tira.scrollTo({ left: der, behavior: 'smooth' });
  });

  const nombre = (c: Categoria) => enSuLengua(c.nombre, c.nombre_en, lengua);
  const fotoDe = (c: Categoria) => c.productos.find((p) => p.imagen_ruta)?.imagen_ruta ?? null;
</script>

{#snippet rectangulos(conIcono: boolean)}
  {#each categorias as c (c.id)}
    <button
      type="button"
      class="f-rect"
      class:activa={c.id === activa}
      aria-current={c.id === activa ? 'true' : undefined}
      data-categoria={c.id}
      onclick={() => alElegir?.(c.id)}>{#if conIcono}<Icono categoria={c.icono} tamano={17} />{/if}{nombre(c)}</button
    >
  {/each}
{/snippet}

{#if forma === 'pestanas'}
  <Pestanas {categorias} {activa} {lengua} {t} {pegadas} bind:nav {alElegir} />
{:else if forma === 'tarjeta'}
  <nav class="f-cats f-en-tarjeta" class:pegadas bind:this={nav} aria-label={t.categorias}>
    <div class="f-cats-tarjeta" bind:this={interior}>{@render rectangulos(false)}</div>
  </nav>
{:else}
  <nav
    class="f-cats"
    class:f-pildoras={forma === 'pildoras'}
    class:f-circulos={forma === 'circulos_icono' || forma === 'circulos_foto'}
    class:pegadas
    bind:this={nav}
    aria-label={t.categorias}
  >
    {#if forma === 'rectangulos'}
      {@render rectangulos(true)}
    {:else if forma === 'pildoras'}
      {#each categorias as c (c.id)}
        <button
          type="button"
          class="f-pil"
          class:activa={c.id === activa}
          aria-current={c.id === activa ? 'true' : undefined}
          data-categoria={c.id}
          onclick={() => alElegir?.(c.id)}><Icono categoria={c.icono} tamano={18} />{nombre(c)}</button
        >
      {/each}
    {:else}
      {#each categorias as c (c.id)}
        {@const foto = forma === 'circulos_foto' ? fotoDe(c) : null}
        <button
          type="button"
          class="f-circ"
          class:activa={c.id === activa}
          aria-current={c.id === activa ? 'true' : undefined}
          data-categoria={c.id}
          onclick={() => alElegir?.(c.id)}
        >
          <span class="f-circ-dibujo">{#if foto}<img src={urlImagen(foto)} alt="" />{:else}<Icono categoria={c.icono} tamano={27} />{/if}</span>
          <span>{nombre(c)}</span>
        </button>
      {/each}
    {/if}
  </nav>
{/if}
