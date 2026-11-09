<!--
  Mi menú, portado de la maqueta del Menú aprobada el 13 de octubre de 2026
  (CC2rrjbgxC2yykNa33a3sA), que es «Mi menú» de Flet (menu_view.py) con «producto» y las
  categorías de cada restaurante, más Opciones y Áreas (maqueta de Opciones y áreas
  GhrEVWPmevfBZtWzi4exKi, aprobada el 15 de octubre de 2026). Arriba: el título, Productos |
  Categorías | Opciones | Áreas, el chip, Ocultar varios (solo en Productos) y el botón negro de la
  sección (Nuevo producto, Nueva categoría, Nuevo grupo o Nueva área). Abajo, la tarjeta de vidrio
  con la sección elegida, y encima las ventanas.

  Lee el menú de la sucursal al abrir y después de cada cambio. El ojito, Ocultar varios y las
  flechas cambian la tabla en cuanto Postgres dice que sí; si falla, sale el aviso de abajo
  (aviso() de Flet).

  Desde Mi menú (maqueta U9YqpsSb2PeB5pFXTPvh1C): las secciones van en el dock, al centro de la barra, y la
  pastilla pegada al título. El inglés lo traduce la IA sola (lib/traduccion.ts): al abrir la vista y
  después de guardar un producto, una categoría o un grupo, sin esperarlo; si escribió algo, se vuelve a
  leer el menú. Se para al salir de la vista.

  Desde la tabla nueva (8 nov 2026, maqueta Ltm74p3fb7tiAqYcj5nqbX): sin la tarjeta blanca. Lo de arriba de
  cada sección (la búsqueda, la nota) va suelto sobre el fondo y su tabla, en su marco, 16 abajo. Mientras
  lee por primera vez, la sección sale con un menú vacío y `cargando`, que pinta sus esqueletos, tantos
  como filas tenía la última vez en este navegador (encuesta del 8 nov 2026); si no pudo leer, la tabla
  vacía de la sección con su nota.
-->
<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import AvisoFlotante from '../../diseno/AvisoFlotante.svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import Dock from '../../diseno/Dock.svelte';
  import { cascada } from '../../diseno/cascada';
  import { trazosCategoria } from '../../diseno/iconosCategorias';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { plural } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { traductor } from '../../lib/traduccion';
  import {
    cambiarVisibilidad,
    leerMenu,
    moverCategoria,
    moverGrupo,
    ordenarProductos,
    type Area,
    type Categoria,
    type Grupo,
    type Menu,
    type Producto,
  } from '../../lib/menu';
  import Areas from './menu/Areas.svelte';
  import Categorias from './menu/Categorias.svelte';
  import Opciones from './menu/Opciones.svelte';
  import Productos from './menu/Productos.svelte';
  import VentanaArea from './menu/VentanaArea.svelte';
  import VentanaCategoria from './menu/VentanaCategoria.svelte';
  import VentanaGrupo from './menu/VentanaGrupo.svelte';
  import VentanaProducto from './menu/VentanaProducto.svelte';

  type Seccion = 'productos' | 'categorias' | 'opciones' | 'areas';

  let { sucursal, abrirNuevo }: { sucursal: Sucursal; abrirNuevo?: () => boolean } = $props();

  type Lectura =
    | { estado: 'leyendo' }
    | { estado: 'listo'; menu: Menu }
    | { estado: 'error'; deRed: boolean };

  let lectura = $state<Lectura>({ estado: 'leyendo' });
  let seccion = $state<Seccion>('productos');
  let busqueda = $state('');
  let filtro = $state<number | null>(null);
  let eligiendo = $state(false);
  const elegidos = new SvelteSet<number>();
  let ocultando = $state(false);
  let ventana = $state<
    | { tipo: 'producto'; producto: Producto | null }
    | { tipo: 'categoria'; categoria: Categoria | null }
    | { tipo: 'grupo'; grupo: Grupo | null }
    | { tipo: 'area'; area: Area | null }
    | null
  >(null);
  let aviso = $state<string | null>(null);
  let tarjeta = $state<HTMLElement>();

  const menu = $derived(lectura.estado === 'listo' ? lectura.menu : null);
  const cargando = $derived(lectura.estado === 'leyendo');
  // Lo que ven las secciones mientras leen: nada, con sus esqueletos encima.
  const VACIO: Menu = { categorias: [], productos: [], grupos: [], areas: [] };
  const visto = $derived(menu ?? VACIO);

  // Cuántas filas tenía cada sección la última vez, en este navegador y en esta sucursal, para que el
  // esqueleto salga con esas: 3 la primera vez, al menos 1 y a lo más 10 (las que caben).
  type Filas = Record<Seccion, number>;
  const llaveFilas = () => `fragmentless-menu-filas-${sucursal.id}`;
  const entre = (n: unknown) => (typeof n === 'number' && Number.isFinite(n) ? Math.min(10, Math.max(1, Math.round(n))) : 3);

  function leerFilas(): Filas {
    try {
      const g = JSON.parse(localStorage.getItem(llaveFilas()) ?? 'null') as Partial<Filas> | null;
      return { productos: entre(g?.productos), categorias: entre(g?.categorias), opciones: entre(g?.opciones), areas: entre(g?.areas) };
    } catch (error) {
      console.error('[menu] no se pudo leer cuántas filas había; el esqueleto sale con 3:', error);
      return { productos: 3, categorias: 3, opciones: 3, areas: 3 };
    }
  }

  function guardarFilas(m: Menu) {
    const filas: Filas = { productos: m.productos.length, categorias: m.categorias.length, opciones: m.grupos.length, areas: m.areas.length };
    try {
      localStorage.setItem(llaveFilas(), JSON.stringify(filas));
    } catch (error) {
      console.error('[menu] no se pudo recordar cuántas filas hay:', error);
    }
  }

  const filas = leerFilas();

  const estado = $derived.by(() => {
    if (lectura.estado === 'leyendo') return { texto: 'Cargando tu menú…', vivo: true };
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    const { productos, categorias, grupos, areas } = lectura.menu;
    if (seccion === 'categorias') return { texto: plural(categorias.length, 'categoría', 'categorías'), vivo: true };
    if (seccion === 'areas') return { texto: plural(areas.length, 'área', 'áreas'), vivo: true };
    if (seccion === 'opciones') {
      const agotadas = grupos.reduce((n, g) => n + g.opciones.filter((o) => !o.visible).length, 0);
      const texto = plural(grupos.length, 'grupo', 'grupos');
      return { texto: agotadas ? `${texto} · ${plural(agotadas, 'opción agotada', 'opciones agotadas')}` : texto, vivo: true };
    }
    const visibles = productos.filter((p) => p.visible).length;
    return { texto: `${visibles} de ${productos.length} a la vista en tu menú`, vivo: true };
  });

  async function leer() {
    try {
      const nuevo = await leerMenu(sucursal.id);
      lectura = { estado: 'listo', menu: nuevo };
      guardarFilas(nuevo);
      if (filtro !== null && !nuevo.categorias.some((c) => c.id === filtro)) filtro = null;
    } catch (error) {
      console.error('[menu] no se pudo leer el menú:', error);
      lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  // svelte-ignore state_referenced_locally
  const traduce = traductor(sucursal.id, () => void leer());
  onDestroy(() => traduce.parar());

  // Después de guardar en una ventana: se vuelve a leer y lo nuevo se traduce, sin esperarlo.
  function alGuardar() {
    void leer();
    traduce.correr();
  }

  // «Agregar producto» de la búsqueda de Inicio: al terminar de leer, su ventana.
  onMount(async () => {
    const abrir = abrirNuevo?.() ?? false;
    await leer();
    if (lectura.estado === 'listo') {
      traduce.correr();
      // Las filas entran en cascada al llegar la primera vez (diseno/cascada.ts); al releer se quedan quietas.
      await tick();
      cascada(tarjeta);
    }
    if (!abrir || lectura.estado !== 'listo') return;
    if (lectura.menu.categorias.length) ventana = { tipo: 'producto', producto: null };
    else aviso = 'Primero crea una categoría.';
  });

  // La tabla vacía de cada sección, si no pudo leer.
  const VACIA: Record<Seccion, { columnas: string; encabezados: string[] }> = {
    productos: {
      columnas: '2.2fr 2.8fr 1.1fr 0.8fr 1fr 80px',
      encabezados: ['Producto', 'Descripción', 'Categoría', 'Precio', 'Visibilidad', ''],
    },
    categorias: { columnas: '3fr 1.6fr 1.5fr 128px', encabezados: ['Categoría', 'Productos', 'Área', ''] },
    opciones: { columnas: '3fr 1.3fr 1.1fr 128px', encabezados: ['Grupo', 'Cómo se elige', 'Productos', ''] },
    areas: { columnas: '1.4fr 3fr 88px', encabezados: ['Área', 'Le llegan', ''] },
  };

  async function cambiarSeccion(valor: Seccion) {
    const otra = valor !== seccion;
    seccion = valor;
    salirDeEleccion();
    // Las de la sección nueva entran en cascada (si ya llegaron; mientras lee, sus esqueletos).
    if (!otra || !menu) return;
    await tick();
    cascada(tarjeta);
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

  // Las flechas de Categorías y de Opciones: la tabla cambia en cuanto se pulsa y se guarda al
  // instante; si Postgres no pudo, sale el aviso y se vuelve a leer lo que de verdad quedó.
  async function mover<T extends { id: number }>(
    lista: T[],
    fila: T,
    hacia: 'arriba' | 'abajo',
    guardar: (id: number, hacia: 'arriba' | 'abajo') => Promise<void>,
    despues?: () => void,
  ) {
    const aqui = lista.findIndex((x) => x.id === fila.id);
    const alla = hacia === 'arriba' ? aqui - 1 : aqui + 1;
    if (aqui < 0 || alla < 0 || alla >= lista.length) return;
    [lista[aqui], lista[alla]] = [lista[alla], lista[aqui]];
    despues?.();
    await tick();
    const atributo = hacia === 'arriba' ? 'data-subir' : 'data-bajar';
    const boton = tarjeta?.querySelector<HTMLButtonElement>(`[${atributo}="${fila.id}"]`);
    if (boton && !boton.disabled) boton.focus({ preventScroll: true });
    try {
      await guardar(fila.id, hacia);
    } catch (falla) {
      aviso = (falla as Error).message;
      await leer();
    }
  }
</script>

<BarraArriba titulo="Mi menú" {estado} chipAntes>
  {#snippet junto()}
    <Dock
      etiqueta="Sección de Mi menú"
      opciones={[
        { valor: 'productos', texto: 'Productos', icono: 'comida', trazos: trazosCategoria('comida') },
        { valor: 'categorias', texto: 'Categorías', icono: 'carpeta' },
        { valor: 'opciones', texto: 'Opciones', icono: 'menu' },
        { valor: 'areas', texto: 'Áreas', icono: 'cocina' },
      ]}
      elegida={seccion}
      alElegir={cambiarSeccion}
    />
  {/snippet}
  {#if seccion === 'productos'}
    {#if eligiendo}
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" apagado={ocultando} onclick={salirDeEleccion} />
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
  {:else if seccion === 'categorias'}
    <Boton
      etiqueta="Nueva categoría"
      icono="mas"
      tono="tinta"
      apagado={!menu}
      onclick={() => (ventana = { tipo: 'categoria', categoria: null })}
    />
  {:else if seccion === 'opciones'}
    <Boton
      etiqueta="Nuevo grupo"
      icono="mas"
      tono="tinta"
      apagado={!menu}
      onclick={() => (ventana = { tipo: 'grupo', grupo: null })}
    />
  {:else}
    <Boton
      etiqueta="Nueva área"
      icono="mas"
      tono="tinta"
      apagado={!menu}
      onclick={() => (ventana = { tipo: 'area', area: null })}
    />
  {/if}
</BarraArriba>

<main class="cuerpo" bind:this={tarjeta}>
  <section class="seccion" aria-label="Mi menú">
    {#if lectura.estado !== 'error'}
      {#if seccion === 'productos'}
        <Productos
          menu={visto}
          {cargando}
          esqueletos={filas.productos}
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
      {:else if seccion === 'categorias'}
        <Categorias
          menu={visto}
          {cargando}
          esqueletos={filas.categorias}
          alMover={(c, hacia) => {
            if (menu) mover(menu.categorias, c, hacia, moverCategoria, () => (menu.productos = ordenarProductos(menu.categorias, menu.productos)));
          }}
          alEditar={(c) => (ventana = { tipo: 'categoria', categoria: c })}
        />
      {:else if seccion === 'opciones'}
        <Opciones
          menu={visto}
          {cargando}
          esqueletos={filas.opciones}
          alMover={(g, hacia) => {
            if (menu) mover(menu.grupos, g, hacia, moverGrupo);
          }}
          alEditar={(g) => (ventana = { tipo: 'grupo', grupo: g })}
        />
      {:else}
        <Areas menu={visto} {cargando} esqueletos={filas.areas} alEditar={(a) => (ventana = { tipo: 'area', area: a })} />
      {/if}
    {:else}
      <!-- Si no pudo leer: la tabla vacía con su nota, como en Flet. -->
      <Tabla columnas={VACIA[seccion].columnas} encabezados={VACIA[seccion].encabezados.map((texto) => ({ texto }))} marco>
        {#if lectura.deRed}
          <NotaTabla relleno={48} angosta titulo="Sin conexión." texto={SIN_CONEXION} />
        {:else}
          <NotaTabla relleno={48} angosta titulo="No se pudo cargar tu menú." texto="Intenta de nuevo en un momento." />
        {/if}
      </Tabla>
    {/if}
  </section>
</main>

{#if menu && ventana?.tipo === 'producto'}
  <VentanaProducto
    restauranteId={sucursal.id}
    producto={ventana.producto}
    categorias={menu.categorias}
    grupos={menu.grupos}
    categoriaInicial={filtro}
    alCambiar={alGuardar}
    alCerrar={() => (ventana = null)}
  />
{:else if menu && ventana?.tipo === 'categoria'}
  <VentanaCategoria
    restauranteId={sucursal.id}
    categoria={ventana.categoria}
    {menu}
    alCambiar={alGuardar}
    alCerrar={() => (ventana = null)}
  />
{:else if menu && ventana?.tipo === 'grupo'}
  <VentanaGrupo
    restauranteId={sucursal.id}
    grupo={ventana.grupo}
    {menu}
    alCambiar={alGuardar}
    alCerrar={() => (ventana = null)}
  />
{:else if menu && ventana?.tipo === 'area'}
  <VentanaArea
    restauranteId={sucursal.id}
    area={ventana.area}
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
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
  }

  .seccion {
    height: 100%;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }
</style>
