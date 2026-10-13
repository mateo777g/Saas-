<!--
  La sección Productos de Mi menú, portada de la maqueta del Menú (CC2rrjbgxC2yykNa33a3sA) y de
  menu_view.py de Flet: el buscador (nombre, descripción o categoría), el filtro de categorías, el
  conteo y la tabla en sólido con la foto, el nombre, la descripción, la categoría con su ícono,
  el precio, la visibilidad, el ojito y el lápiz. Buscar y filtrar es en memoria: no se vuelve a
  leer por tecla.

  En «Ocultar varios» cada fila es un botón con su cajita (las ya ocultas, apagadas), y abajo sale
  la barra negra que las oculta de una vez. Ocultar nunca borra.
-->
<script lang="ts">
  import type { SvelteSet } from 'svelte/reactivity';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { urlFoto } from '../../../lib/fotos';
  import { dinero, plural } from '../../../lib/formato';
  import type { Menu, Producto } from '../../../lib/menu';
  import FiltroCategorias from './FiltroCategorias.svelte';
  import Foto from './Foto.svelte';

  let {
    menu,
    busqueda = $bindable(''),
    filtro,
    alFiltrar,
    eligiendo,
    elegidos,
    ocultando,
    alOjo,
    alEditar,
    alIrACategorias,
    alOcultar,
  }: {
    menu: Menu;
    busqueda?: string;
    filtro: number | null;
    alFiltrar: (id: number | null) => void;
    eligiendo: boolean;
    elegidos: SvelteSet<number>;
    ocultando: boolean;
    alOjo: (p: Producto) => void;
    alEditar: (p: Producto) => void;
    alIrACategorias: () => void;
    alOcultar: () => void;
  } = $props();

  const COLUMNAS = '2.2fr 2.8fr 1.1fr 0.8fr 1fr 80px';
  const COLUMNAS_ELIGIENDO = '20px 2.2fr 2.8fr 1.1fr 0.8fr 1fr';

  const categoriaDe = $derived(new Map(menu.categorias.map((c) => [c.id, c])));
  const texto = $derived(busqueda.trim());

  const mostrados = $derived.by(() => {
    const q = texto.toLowerCase();
    return menu.productos.filter((p) => {
      if (filtro !== null && p.categoria_id !== filtro) return false;
      if (!q) return true;
      return [p.nombre, p.descripcion, categoriaDe.get(p.categoria_id)?.nombre].some((t) =>
        (t ?? '').toLowerCase().includes(q),
      );
    });
  });

  // Los que se pueden elegir ahora: los que se ven en la tabla y no están ocultos ya.
  const elegibles = $derived(mostrados.filter((p) => p.visible));
  const todos = $derived(elegibles.length > 0 && elegibles.every((p) => elegidos.has(p.id)));

  function alternar(id: number) {
    if (ocultando) return;
    if (elegidos.has(id)) elegidos.delete(id);
    else elegidos.add(id);
  }

  function elegirTodos() {
    for (const p of elegibles) {
      if (todos) elegidos.delete(p.id);
      else elegidos.add(p.id);
    }
  }
</script>

{#snippet celdas(p: Producto)}
  {@const c = categoriaDe.get(p.categoria_id)}
  <span class="producto">
    <Foto src={p.imagen_ruta ? urlFoto(p.imagen_ruta) : null} oculta={!p.visible} />
    <span class="nombre">{p.nombre}</span>
  </span>
  <span class="descripcion">{p.descripcion ?? ''}</span>
  <span class="celda-categoria">
    {#if c}
      <span class="chip-categoria"><IconoCategoria id={c.icono} tamano={14} /><span>{c.nombre}</span></span>
    {/if}
  </span>
  <span class="precio">{dinero(p.precio)}</span>
  <span>
    <span class="visibilidad" class:no={!p.visible}>
      <span class="punto"></span>{p.visible ? 'Visible' : eligiendo ? 'Ya oculto' : 'Oculto'}
    </span>
  </span>
{/snippet}

<div class="herramientas">
  <label class="buscador">
    <Icono nombre="buscar" tamano={16} />
    <input
      type="search"
      aria-label="Buscar productos"
      placeholder="Busca por nombre, categoría o ingrediente..."
      bind:value={busqueda}
    />
  </label>
  <FiltroCategorias categorias={menu.categorias} productos={menu.productos} {filtro} alElegir={alFiltrar} />
  <span class="crece"></span>
  <span class="etiqueta">{plural(mostrados.length, 'PRODUCTO', 'PRODUCTOS')}</span>
</div>

<Tabla
  columnas={eligiendo ? COLUMNAS_ELIGIENDO : COLUMNAS}
  relleno="0 16px"
  altoFila={64}
  encabezados={[
    ...(eligiendo ? [{ texto: '' }] : []),
    { texto: 'PRODUCTO' },
    { texto: 'DESCRIPCIÓN' },
    { texto: 'CATEGORÍA' },
    { texto: 'PRECIO' },
    { texto: 'VISIBILIDAD' },
    ...(eligiendo ? [] : [{ texto: '' }]),
  ]}
>
  {#if !menu.productos.length}
    {#if !menu.categorias.length}
      <NotaTabla
        relleno={48} angosta
        titulo="Todavía no hay productos en el menú."
        texto="Primero crea tus categorías, como Tacos o Bebidas; después agrega tus productos con Nuevo producto."
      >
        <Boton etiqueta="Ir a Categorías" icono="derecha" iconoAlFinal tamano="chico" onclick={alIrACategorias} />
      </NotaTabla>
    {:else}
      <NotaTabla relleno={48} angosta titulo="Todavía no hay productos en el menú." texto="Agrega el primero con Nuevo producto." />
    {/if}
  {:else if !mostrados.length}
    <NotaTabla
      relleno={48} angosta
      titulo={texto ? `No encontramos productos para "${texto}".` : 'No hay productos en esta categoría.'}
      texto="Prueba con otro nombre, categoría o palabra clave."
    />
  {:else if eligiendo}
    {#each mostrados as p (p.id)}
      <button
        type="button"
        class="fila eleccion"
        aria-pressed={elegidos.has(p.id)}
        disabled={!p.visible}
        onclick={() => alternar(p.id)}
      >
        <span class="cajita" class:si={elegidos.has(p.id)} class:muerta={!p.visible}>
          {#if elegidos.has(p.id)}<Icono nombre="check" tamano={13} />{/if}
        </span>
        {@render celdas(p)}
      </button>
    {/each}
  {:else}
    {#each mostrados as p (p.id)}
      <div class="fila">
        {@render celdas(p)}
        <span class="acciones">
          <BotonCuadro
            icono={p.visible ? 'oculto' : 'ojo'}
            ayuda={p.visible ? 'Ocultar del menú público' : 'Mostrar en el menú público'}
            onclick={() => alOjo(p)}
          />
          <BotonCuadro icono="crear" ayuda="Editar producto" onclick={() => alEditar(p)} />
        </span>
      </div>
    {/each}
  {/if}
</Tabla>

{#if eligiendo}
  <div class="barra-eleccion">
    <div class="textos">
      <b>
        {elegidos.size === 0
          ? 'Toca los productos que se acabaron'
          : plural(elegidos.size, 'producto elegido', 'productos elegidos')}
      </b>
      <span>Dejan de salir en tu menú público, no se borran. Los vuelves a mostrar con el ojito.</span>
    </div>
    <button type="button" class="contorno" disabled={!elegibles.length || ocultando} onclick={elegirTodos}>
      {todos ? 'Quitar todos' : 'Elegir todos'}
    </button>
    <button type="button" class="lleno" disabled={!elegidos.size || ocultando} onclick={alOcultar}>
      <Icono nombre="oculto" tamano={16} />
      {ocultando
        ? 'Ocultando…'
        : elegidos.size <= 1
          ? 'Ocultar producto'
          : `Ocultar ${elegidos.size} productos`}
    </button>
  </div>
{/if}

<style>
  .herramientas {
    position: relative;
    flex: none;
    min-height: 40px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .buscador {
    width: 380px;
    height: 40px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--solido);
    color: var(--tenue);
  }

  .buscador input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 500;
    outline: none;
  }

  .buscador input::placeholder {
    color: var(--tenue);
  }

  .crece {
    flex-grow: 1;
  }

  .producto {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nombre,
  .descripcion {
    min-width: 0;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
  }

  .descripcion {
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
  }

  .celda-categoria {
    min-width: 0;
  }

  .chip-categoria {
    max-width: 100%;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 10px 4px 8px;
    border-radius: 8px;
    background: var(--chip);
    font-size: 12px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
  }

  .chip-categoria span {
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .precio {
    font-family: var(--mono);
    font-size: 13px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }

  .visibilidad {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 600;
  }

  .punto {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    background: var(--tinta);
  }

  .visibilidad.no {
    font-weight: 500;
    color: var(--tenue);
  }

  .visibilidad.no .punto {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  /* Ocultar varios: toda la fila es el botón. */
  .eleccion {
    width: 100%;
    border-width: 0 0 1px;
    border-style: solid;
    border-color: var(--linea);
    background: transparent;
    color: var(--texto);
    text-align: left;
  }

  .eleccion[aria-pressed='true'] {
    background: var(--chip);
  }

  .eleccion:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .cajita {
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1.5px solid var(--tenue);
    border-radius: 6px;
    background: var(--solido);
  }

  .cajita.si {
    border: 0;
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .cajita.muerta {
    border: 1.5px dashed var(--linea-fuerte);
    background: transparent;
  }

  .barra-eleccion {
    height: 64px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 12px 0 20px;
    border-radius: 18px;
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .textos {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .textos b {
    font-size: 14px;
    font-weight: 700;
  }

  .textos span {
    font-size: 12px;
    color: var(--sobre-tinta-suave);
  }

  .contorno,
  .lleno {
    height: 40px;
    border-radius: 12px;
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
  }

  .contorno {
    padding: 0 14px;
    border: 1px solid var(--sobre-tinta-linea);
    background: transparent;
    color: var(--sobre-tinta);
  }

  .lleno {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 16px;
    border: 0;
    background: var(--sobre-tinta);
    color: var(--tinta);
  }

  .contorno:disabled,
  .lleno:disabled {
    opacity: 0.4;
    cursor: default;
  }
</style>
