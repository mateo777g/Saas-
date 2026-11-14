<!--
  «Foto de un producto» (maqueta UDArhiEZceT7rmSKxqRA5r v59, 11 nov 2026): la ventana que sale de «Tus carteles» con los
  productos de Mi menú que tienen foto; los que ya están en sus carteles, apagados. Arriba, en el gris de los campos que
  van juntos, la búsqueda y el filtro de categorías de Mi menú: la píldora de 48 con su brillo (diseno/Haz.svelte) y el
  filtro de Productos (menu/FiltroCategorias.svelte), con su lista alineada a la derecha del botón para no salirse de la
  ventana. Al abrir, sus productos entran en cascada; al buscar o filtrar, la lista cambia quieta. Elegir uno lo pone.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { cascada } from '../../../diseno/cascada';
  import Haz from '../../../diseno/Haz.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { vidrio } from '../../../diseno/vidrio';
  import { urlFoto } from '../../../lib/fotos';
  import type { Categoria, Producto } from '../../../lib/menu';
  import FiltroCategorias from '../menu/FiltroCategorias.svelte';

  let {
    productos,
    categorias,
    yaPuestos,
    alElegir,
    alCerrar,
  }: {
    productos: Producto[];
    categorias: Categoria[];
    // Los que ya están en otro cartel.
    yaPuestos: number[];
    alElegir: (productoId: number) => void;
    alCerrar: () => void;
  } = $props();

  let busqueda = $state('');
  let filtro = $state<number | null>(null);
  let lista = $state<HTMLDivElement>();
  let caja = $state<HTMLDivElement>();

  const conFoto = $derived(productos.filter((p) => p.imagen_ruta && !p.es_envio));
  const conSusFotos = $derived(categorias.filter((c) => conFoto.some((p) => p.categoria_id === c.id)));
  const plano = (t: string) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const vistos = $derived.by(() => {
    const q = plano(busqueda.trim());
    return conFoto.filter((p) => (filtro === null || p.categoria_id === filtro) && (!q || plano(p.nombre).includes(q)));
  });
  const nombreCategoria = (id: number) => categorias.find((c) => c.id === id)?.nombre ?? '';
  const precioCorto = (n: number) => `$${Number.isInteger(n) ? n : n.toFixed(2)}`;

  onMount(() => {
    tick().then(() => cascada(lista, '.producto'));
  });
</script>

<Ventana centrado titulo="Foto de un producto" nota="Salen los de Mi menú que tienen foto." ancho={520} {alCerrar}>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="elige"
    bind:this={caja}
    onkeydown={(e) => {
      // Con la lista del filtro abierta, Escape solo la cierra (no la ventana).
      if (e.key === 'Escape' && caja?.querySelector('.filtro.abierta')) e.preventDefault();
    }}
  >
    <div class="buscar">
      <Haz>
        <label class="busca" use:vidrio={'control'}>
          <Icono nombre="buscar" tamano={18} />
          <input type="search" placeholder="Busca un producto" aria-label="Busca un producto" bind:value={busqueda} />
        </label>
      </Haz>
      <div class="filtro-caja">
        <FiltroCategorias categorias={conSusFotos} productos={conFoto} {filtro} alElegir={(id) => (filtro = id)} />
      </div>
    </div>
    <div class="productos" bind:this={lista}>
      {#each vistos as p (p.id)}
        {@const ya = yaPuestos.includes(p.id)}
        <button type="button" class="producto" disabled={ya} onclick={() => alElegir(p.id)}>
          <img src={urlFoto(p.imagen_ruta!)} alt="" />
          <span class="textos"><b>{p.nombre}</b><small>{ya ? 'Ya está en tus carteles' : nombreCategoria(p.categoria_id)}</small></span>
          <span class="precio">{precioCorto(p.precio)}</span>
        </button>
      {:else}
        <p class="vacio">
          {busqueda.trim() ? `No hay productos con «${busqueda.trim()}»` : 'No hay productos con foto'}{filtro !== null
            ? ` en ${nombreCategoria(filtro)}`
            : ''}.
        </p>
      {/each}
    </div>
  </div>
</Ventana>

<style>
  .elige {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* La búsqueda y el filtro juntos, en el gris de los campos que van juntos (el --fondo de Mi menú). */
  .buscar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 14px 16px 16px;
    border-radius: 12px;
    background: var(--fondo);
  }

  .buscar > :global(div.haz) {
    flex: 1 1 auto;
    min-width: 0;
  }

  .busca {
    width: 100%;
    height: 48px;
    box-sizing: border-box;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px 0 18px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 999px;
    background: var(--solido);
    color: var(--tenue);
  }

  .busca :global(svg) {
    flex: none;
  }

  .busca:focus-within {
    border-color: var(--linea-fuerte);
  }

  .busca input {
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--texto);
    font: 400 15px var(--jakarta);
    outline: none;
  }

  .busca input::placeholder {
    color: var(--tenue);
  }

  .filtro-caja {
    flex: none;
    display: flex;
  }

  /* El botón del filtro, de 48 como la búsqueda; su lista, alineada a la derecha. */
  .filtro-caja :global(.filtro .boton) {
    height: 48px;
  }

  .filtro-caja :global(.filtro .fondo),
  .filtro-caja :global(.filtro .lista) {
    left: auto;
    right: 0;
  }

  .productos {
    display: flex;
    flex-direction: column;
    min-height: 180px;
  }

  .producto {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 8px;
    border: 0;
    border-bottom: 1px solid var(--linea);
    background: transparent;
    text-align: left;
    color: var(--texto);
    font: inherit;
    cursor: pointer;
    border-radius: 0;
    transition: background 0.15s ease;
  }

  .producto:last-child {
    border-bottom: 0;
  }

  .producto:hover:not(:disabled) {
    background: var(--chip);
    border-radius: 10px;
  }

  .producto:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .producto img {
    width: 44px;
    height: 44px;
    border-radius: 10px;
    object-fit: cover;
    flex: none;
  }

  .textos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .textos b {
    font-size: 14px;
    font-weight: 600;
  }

  .textos small {
    font-size: 12px;
    color: var(--tenue);
  }

  .precio {
    font: 600 13px var(--mono);
    color: var(--texto);
  }

  .vacio {
    margin: 0;
    padding: 28px 8px;
    text-align: center;
    font-size: 13.5px;
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .producto {
      transition: none;
    }
  }
</style>
