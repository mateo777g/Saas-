<!--
  El menú de Vender a lo ancho (adaptabilidad, encuestas 13 y 14; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4): arriba la búsqueda
  en píldora de Mi menú y el filtro «Todas las categorías» con su conteo; abajo todos los productos en los cuadros de
  Crear anuncios (foto a 4:3 o el cuadro negro, nombre y precio), cada categoría con su título. Lo anotado lleva el aro
  azul y su número, que salta al sumar otro; lo agotado sale apagado y no se toca. Al escribir, solo quedan los que
  coinciden. Mientras se lee la primera vez, esqueletos del mismo tamaño; al llegar, los cuadros entran en cascada.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { cascada } from '../../../diseno/cascada';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { pesos, plural } from '../../../lib/formato';
  import { agotado, type CategoriaPos, type ProductoPos } from '../../../lib/pos';
  import { sinAcentos } from './buscar';
  import Filtro from './Filtro.svelte';
  import Herramientas from './Herramientas.svelte';

  let {
    categorias,
    cuantos,
    cargando = false,
    alProducto,
  }: {
    categorias: CategoriaPos[];
    cuantos: Map<number, number>; // lo anotado de cada producto
    cargando?: boolean;
    alProducto: (p: ProductoPos) => void;
  } = $props();

  let busqueda = $state('');
  let filtroElegido = $state(0); // 0 = todas
  let rejilla = $state<HTMLDivElement>();

  const total = $derived(categorias.reduce((s, c) => s + c.productos.length, 0));
  const opciones = $derived([
    { valor: 0, nombre: 'Todas', cuenta: total, icono: 'menu' },
    ...categorias.map((c) => ({ valor: c.id, nombre: c.nombre, cuenta: c.productos.length, categoria: c.icono })),
  ]);
  const vistas = $derived.by(() => {
    const q = sinAcentos(busqueda);
    return categorias
      .filter((c) => filtroElegido === 0 || c.id === filtroElegido)
      .map((c) => ({ ...c, productos: q ? c.productos.filter((p) => sinAcentos(p.nombre).includes(q)) : c.productos }))
      .filter((c) => c.productos.length > 0);
  });
  const mostrados = $derived(vistas.reduce((s, c) => s + c.productos.length, 0));

  // La cascada, solo la primera vez que llegan los productos.
  let entraron = false;
  $effect(() => {
    if (cargando || entraron || !rejilla) return;
    entraron = true;
    tick().then(() => cascada(rejilla, '.prod'));
  });

  // Al sumar otro del mismo, su número salta con el rebote con que salió (la primera vez sale con su CSS).
  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  function salta(nodo: HTMLElement, _n: number) {
    return {
      update() {
        if (quieto?.matches) return;
        nodo.animate([{ transform: 'scale(0.6)' }, { transform: 'scale(1)' }], {
          duration: 400,
          easing: 'cubic-bezier(0.175, 0.885, 0.32, 1.275)',
        });
      },
    };
  }
</script>

<div class="izq">
  <Herramientas
    bind:busqueda
    placeholder="Busca un producto…"
    aria="Buscar en el menú"
    conteo={plural(mostrados, 'PRODUCTO', 'PRODUCTOS')}
    {cargando}
  >
    {#snippet filtro()}
      <Filtro titulo="CATEGORÍAS" todas="Todas las categorías" {opciones} elegida={filtroElegido} alElegir={(v) => (filtroElegido = v)} />
    {/snippet}
  </Herramientas>

  <div class="rejilla-scroll" bind:this={rejilla}>
    {#if cargando}
      <span class="solo-lector" role="status">Cargando el menú…</span>
      {#each [4, 3] as n, b (b)}
        <section class="bloque-cat" aria-hidden="true">
          <div class="cat-titulo"><Esqueleto ancho="90px" alto="15px" /></div>
          <div class="rejilla">
            {#each Array(n) as _, i (i)}
              <div class="prod">
                <Esqueleto alto="auto" proporcion="4 / 3" redondo="10px" />
                <span class="prod-textos"><Esqueleto ancho="70%" alto="14px" /><Esqueleto ancho="40%" alto="11px" /></span>
              </div>
            {/each}
          </div>
        </section>
      {/each}
    {:else if categorias.length === 0}
      <div class="sin-coincide"><b>Tu menú está vacío</b>Los productos se agregan en Mi menú, desde el panel.</div>
    {:else if vistas.length === 0}
      <div class="sin-coincide"><b>Nada con ese nombre</b>Prueba con otra palabra o con otra categoría.</div>
    {:else}
      {#each vistas as c (c.id)}
        <section class="bloque-cat">
          <div class="cat-titulo"><h2>{c.nombre}</h2><span>{plural(c.productos.length, 'PRODUCTO', 'PRODUCTOS')}</span></div>
          <div class="rejilla">
            {#each c.productos as p (p.id)}
              {@const n = cuantos.get(p.id) ?? 0}
              {@const sinHay = agotado(p)}
              <button
                type="button"
                class="prod"
                class:elegido={n > 0}
                class:agotado={sinHay}
                aria-pressed={n > 0}
                disabled={sinHay}
                onclick={() => alProducto(p)}
              >
                <span class="prod-foto" style:background-image={p.foto ? `url("${p.foto}")` : null}></span>
                <span class="prod-textos">
                  <span class="prod-nombre">{p.nombre}</span>
                  <span class="prod-precio">{pesos(p.precio)}</span>
                </span>
                {#if n > 0}<span class="numero" use:salta={n}>{n}</span>{/if}
              </button>
            {/each}
          </div>
        </section>
      {/each}
    {/if}
  </div>
</div>
