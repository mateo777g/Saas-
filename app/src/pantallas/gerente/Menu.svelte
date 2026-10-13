<!--
  Mi menú, portado de la maqueta del Menú aprobada el 13 de octubre de 2026
  (CC2rrjbgxC2yykNa33a3sA), que es «Mi menú» de Flet (menu_view.py) con «producto» y las
  categorías de cada restaurante. Arriba: el título, Productos | Categorías, el chip, Ocultar
  varios (solo en Productos) y el botón negro de la sección (Nuevo producto o Nueva categoría).
  Abajo, la tarjeta de vidrio con la sección elegida, y encima las ventanas.

  Lee las categorías y los productos de la sucursal al abrir y después de cada cambio. El ojito,
  Ocultar varios y las flechas cambian la tabla en cuanto Postgres dice que sí; si falla, sale el
  aviso de abajo (aviso() de Flet).
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import AvisoFlotante from '../../diseno/AvisoFlotante.svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { plural } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import {
    cambiarVisibilidad,
    leerMenu,
    moverCategoria,
    ordenarProductos,
    type Categoria,
    type Menu,
    type Producto,
  } from '../../lib/menu';
  import Categorias from './menu/Categorias.svelte';
  import Productos from './menu/Productos.svelte';
  import VentanaCategoria from './menu/VentanaCategoria.svelte';
  import VentanaProducto from './menu/VentanaProducto.svelte';

  let { sucursal }: { sucursal: Sucursal } = $props();

  type Lectura =
    | { estado: 'leyendo' }
    | { estado: 'listo'; menu: Menu }
    | { estado: 'error'; deRed: boolean };

  let lectura = $state<Lectura>({ estado: 'leyendo' });
  let seccion = $state<'productos' | 'categorias'>('productos');
  let busqueda = $state('');
  let filtro = $state<number | null>(null);
  let eligiendo = $state(false);
  const elegidos = new SvelteSet<number>();
  let ocultando = $state(false);
  let ventana = $state<
    { tipo: 'producto'; producto: Producto | null } | { tipo: 'categoria'; categoria: Categoria | null } | null
  >(null);
  let aviso = $state<string | null>(null);
  let tarjeta = $state<HTMLElement>();

  const menu = $derived(lectura.estado === 'listo' ? lectura.menu : null);

  const estado = $derived.by(() => {
    if (lectura.estado === 'leyendo') return { texto: 'Cargando tu menú…', vivo: true };
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    const { productos, categorias } = lectura.menu;
    if (seccion === 'categorias') return { texto: plural(categorias.length, 'categoría', 'categorías'), vivo: true };
    const visibles = productos.filter((p) => p.visible).length;
    return { texto: `${visibles} de ${productos.length} a la vista en tu menú`, vivo: true };
  });

  async function leer() {
    try {
      const nuevo = await leerMenu(sucursal.id);
      lectura = { estado: 'listo', menu: nuevo };
      if (filtro !== null && !nuevo.categorias.some((c) => c.id === filtro)) filtro = null;
    } catch (error) {
      console.error('[menu] no se pudo leer el menú:', error);
      lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  onMount(leer);

  function cambiarSeccion(valor: 'productos' | 'categorias') {
    seccion = valor;
    salirDeEleccion();
  }

  function salirDeEleccion() {
    if (ocultando) return;
    eligiendo = false;
    elegidos.clear();
  }

  // El ojito: oculto deja de salir en el menú público, nunca se borra.
  async function alternarVisible(p: Producto) {
    const visible = !p.visible;
    try {
      const cambiados = await cambiarVisibilidad([p.id], visible);
      if (cambiados !== 1) {
        aviso = 'No se pudo actualizar la visibilidad. Intenta de nuevo.';
        await leer();
        return;
      }
    } catch (falla) {
      aviso = (falla as Error).message === SIN_CONEXION ? SIN_CONEXION : 'No se pudo actualizar la visibilidad. Intenta de nuevo.';
      return;
    }
    p.visible = visible;
  }

  // Ocultar varios: todos los elegidos de una vez.
  async function ocultarElegidos() {
    if (!menu || !elegidos.size || ocultando) return;
    const ids = [...elegidos];
    ocultando = true;
    try {
      const cambiados = await cambiarVisibilidad(ids, false);
      if (cambiados !== ids.length) {
        // Pudo quedar a medias (RLS): se vuelve a leer para mostrar lo que de verdad quedó.
        aviso = 'No se pudieron ocultar todos. Revisa la tabla.';
        ocultando = false;
        elegidos.clear();
        await leer();
        return;
      }
    } catch (falla) {
      ocultando = false;
      aviso = (falla as Error).message === SIN_CONEXION ? SIN_CONEXION : 'No se pudieron ocultar todos. Revisa la tabla.';
      return;
    }
    for (const p of menu.productos) if (elegidos.has(p.id)) p.visible = false;
    ocultando = false;
    salirDeEleccion();
  }

  // Las flechas: la tabla cambia en cuanto se pulsa y se guarda al instante; si Postgres no
  // pudo, sale el aviso y se vuelve a leer lo que de verdad quedó.
  async function mover(c: Categoria, hacia: 'arriba' | 'abajo') {
    if (!menu) return;
    const lista = menu.categorias;
    const aqui = lista.findIndex((x) => x.id === c.id);
    const alla = hacia === 'arriba' ? aqui - 1 : aqui + 1;
    if (aqui < 0 || alla < 0 || alla >= lista.length) return;
    [lista[aqui], lista[alla]] = [lista[alla], lista[aqui]];
    menu.productos = ordenarProductos(lista, menu.productos);
    await tick();
    const atributo = hacia === 'arriba' ? 'data-subir' : 'data-bajar';
    const boton = tarjeta?.querySelector<HTMLButtonElement>(`[${atributo}="${c.id}"]`);
    if (boton && !boton.disabled) boton.focus({ preventScroll: true });
    try {
      await moverCategoria(c.id, hacia);
    } catch (falla) {
      aviso = (falla as Error).message;
      await leer();
    }
  }
</script>

<BarraArriba titulo="Mi menú" {estado}>
  {#snippet junto()}
    <Selector
      etiqueta="Sección de Mi menú"
      opciones={[
        { valor: 'productos', texto: 'Productos' },
        { valor: 'categorias', texto: 'Categorías' },
      ]}
      elegida={seccion}
      alElegir={cambiarSeccion}
    />
  {/snippet}
  {#if seccion === 'productos'}
    {#if eligiendo}
      <Boton etiqueta="Cancelar" icono="cerrar" chip apagado={ocultando} onclick={salirDeEleccion} />
    {:else}
      <Boton
        etiqueta="Ocultar varios"
        icono="oculto"
        apagado={!menu?.productos.length}
        onclick={() => {
          eligiendo = true;
          elegidos.clear();
        }}
      />
    {/if}
    <Boton
      etiqueta="Nuevo producto"
      icono="mas"
      tono="tinta"
      apagado={!menu?.categorias.length}
      ayuda={menu && !menu.categorias.length ? 'Primero crea una categoría' : undefined}
      onclick={() => (ventana = { tipo: 'producto', producto: null })}
    />
  {:else}
    <Boton
      etiqueta="Nueva categoría"
      icono="mas"
      tono="tinta"
      apagado={!menu}
      onclick={() => (ventana = { tipo: 'categoria', categoria: null })}
    />
  {/if}
</BarraArriba>

<main class="cuerpo" bind:this={tarjeta}>
  <Vidrio como="section" class="tarjeta-menu" radio={26} aria-label="Mi menú">
    {#if menu}
      {#if seccion === 'productos'}
        <Productos
          {menu}
          bind:busqueda
          {filtro}
          alFiltrar={(id) => (filtro = id)}
          {eligiendo}
          {elegidos}
          {ocultando}
          alOjo={alternarVisible}
          alEditar={(p) => (ventana = { tipo: 'producto', producto: p })}
          alIrACategorias={() => cambiarSeccion('categorias')}
          alOcultar={ocultarElegidos}
        />
      {:else}
        <Categorias
          {menu}
          alMover={mover}
          alEditar={(c) => (ventana = { tipo: 'categoria', categoria: c })}
        />
      {/if}
    {:else}
      <!-- Mientras lee o si no pudo: la tabla vacía con su nota, como en Flet. -->
      <Tabla
        columnas={seccion === 'productos' ? '2.2fr 2.8fr 1.1fr 0.8fr 1fr 80px' : '3fr 2fr 128px'}
        encabezados={seccion === 'productos'
          ? ['PRODUCTO', 'DESCRIPCIÓN', 'CATEGORÍA', 'PRECIO', 'VISIBILIDAD', ''].map((texto) => ({ texto }))
          : ['CATEGORÍA', 'PRODUCTOS', ''].map((texto) => ({ texto }))}
      >
        {#if lectura.estado === 'leyendo'}
          <NotaTabla relleno={48} angosta titulo="Cargando tu menú…" />
        {:else if lectura.estado === 'error' && lectura.deRed}
          <NotaTabla relleno={48} angosta titulo="Sin conexión." texto={SIN_CONEXION} />
        {:else}
          <NotaTabla relleno={48} angosta titulo="No se pudo cargar tu menú." texto="Intenta de nuevo en un momento." />
        {/if}
      </Tabla>
    {/if}
  </Vidrio>
</main>

{#if menu && ventana?.tipo === 'producto'}
  <VentanaProducto
    restauranteId={sucursal.id}
    producto={ventana.producto}
    categorias={menu.categorias}
    categoriaInicial={filtro}
    alCambiar={leer}
    alCerrar={() => (ventana = null)}
  />
{:else if menu && ventana?.tipo === 'categoria'}
  <VentanaCategoria
    restauranteId={sucursal.id}
    categoria={ventana.categoria}
    {menu}
    alCambiar={leer}
    alCerrar={() => (ventana = null)}
  />
{/if}

{#if aviso}
  {#key aviso}
    <AvisoFlotante mensaje={aviso} alTerminar={() => (aviso = null)} />
  {/key}
{/if}

<style>
  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
  }

  .cuerpo > :global(.tarjeta-menu) {
    height: 100%;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
</style>
