<!--
  Inventario (19 nov 2026; maqueta BBBNJST5w9qZfHWNdovGgb v3, copiada de Mi menú por encuesta): cuánto queda de cada
  ingrediente y qué lleva cada platillo. Arriba, el título, el chip de la sección y el dock Ingredientes · Recetas ·
  Preparaciones · Recetario; a la derecha, los botones de la sección (Contar, Merma, Llegó y «Nuevo ingrediente»; «Nueva
  preparación»; en la página de un recetario, «Cambiar lo que lleva» y «Editar»). Abajo, la búsqueda con su filtro y la
  tabla en el marco de Mi menú, y encima las ventanas. El Recetario (19 nov 2026; maqueta DFVTWEB3eZBEKctyxWjGjg v1) es
  su propia sección, en inventario/Recetario.svelte; aquí solo van su botón, su chip y sus botones de arriba.

  Los ingredientes vienen de la vigía del panel (lib/vigiaInventario.svelte.ts), que los trae en vivo: cada cuenta que se
  cierra resta su receta y la tabla cambia sola. El menú, las preparaciones y las recetas se leen al abrir y después de
  cada cambio. Las filas entran en cascada al llegar y al cambiar de sección; mientras se lee la primera vez, esqueletos.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import Dock from '../../diseno/Dock.svelte';
  import { cascada } from '../../diseno/cascada';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { plural } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { leerRecetas, type Ingrediente, type Preparacion, type Recetario } from '../../lib/inventario';
  import { leerMenu, type Grupo, type Menu, type Opcion, type Producto } from '../../lib/menu';
  import { leerZona } from '../../lib/pos';
  import { supabase } from '../../lib/supabase';
  import type { VigiaInventario } from '../../lib/vigiaInventario.svelte';
  import './inventario/tabla.css';
  import Ingredientes from './inventario/Ingredientes.svelte';
  import Preparaciones from './inventario/Preparaciones.svelte';
  import SeccionRecetario from './inventario/Recetario.svelte';
  import Recetas from './inventario/Recetas.svelte';
  import VentanaContar from './inventario/VentanaContar.svelte';
  import VentanaIngrediente from './inventario/VentanaIngrediente.svelte';
  import VentanaLlego from './inventario/VentanaLlego.svelte';
  import VentanaMerma from './inventario/VentanaMerma.svelte';
  import VentanaPreparacion from './inventario/VentanaPreparacion.svelte';
  import VentanaReceta from './inventario/VentanaReceta.svelte';

  type Seccion = 'ingredientes' | 'recetas' | 'preparaciones' | 'recetario';

  let { sucursal, vigia }: { sucursal: Sucursal; vigia: VigiaInventario } = $props();

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; menu: Menu; recetario: Recetario } | { estado: 'error'; deRed: boolean };
  let lectura = $state<Lectura>({ estado: 'leyendo' });
  let seccion = $state<Seccion>('ingredientes');
  let zona = $state('America/Mexico_City');
  let cuerpo = $state<HTMLElement>();
  let ventana = $state<
    | { tipo: 'ingrediente'; id: number | null }
    | { tipo: 'llego' }
    | { tipo: 'merma' }
    | { tipo: 'contar' }
    | { tipo: 'receta'; producto: Producto }
    | { tipo: 'preparacion'; preparacion: Preparacion | null }
    | null
  >(null);
  // La receta de una opción se abre encima de la del platillo.
  let opcion = $state<{ opcion: Opcion; grupo: Grupo } | null>(null);
  // El Recetario: qué enseña (para los botones de arriba), su chip, y `version`, que sube cuando algo se guardó.
  let libro = $state<ReturnType<typeof SeccionRecetario>>();
  let modoRecetario = $state<'cuadros' | 'pagina' | 'editar'>('cuadros');
  let chipRecetario = $state<{ texto: string; vivo: boolean; pausa?: boolean }>({ texto: 'Cargando tu recetario…', vivo: true });
  let versionRecetario = $state(0);

  const VACIO_MENU: Menu = { categorias: [], productos: [], grupos: [], areas: [] };
  const VACIO_RECETARIO: Recetario = { preparaciones: [], recetas: [] };
  const menu = $derived(lectura.estado === 'listo' ? lectura.menu : VACIO_MENU);
  const recetario = $derived(lectura.estado === 'listo' ? lectura.recetario : VACIO_RECETARIO);
  const ingredientes = $derived(vigia.ingredientes ?? []);

  // Cuántas filas tenía cada sección la última vez, para el esqueleto.
  // svelte-ignore state_referenced_locally
  const llave = (s: Seccion) => `inventario-${s}-${sucursal.id}`;
  const filas: Record<Seccion, number> = {
    ingredientes: filasDeLaUltimaVez(llave('ingredientes')),
    recetas: filasDeLaUltimaVez(llave('recetas')),
    preparaciones: filasDeLaUltimaVez(llave('preparaciones')),
    recetario: 0,
  };
  $effect(() => {
    if (vigia.ingredientes) recordarFilas(llave('ingredientes'), vigia.ingredientes.length);
  });

  const cargandoIngredientes = $derived(vigia.ingredientes === null && !vigia.error);
  const cargandoRecetas = $derived(lectura.estado === 'leyendo' || cargandoIngredientes);
  const ERROR_LEER = (deRed: boolean, que: string) =>
    deRed ? { titulo: 'Sin conexión.', texto: SIN_CONEXION } : { titulo: `No se pudo cargar ${que}.`, texto: 'Intenta de nuevo en un momento.' };
  const errorIngredientes = $derived(vigia.ingredientes === null && vigia.error ? ERROR_LEER(esDeRed(vigia.error), 'tu inventario') : null);
  const errorRecetas = $derived(lectura.estado === 'error' ? ERROR_LEER(lectura.deRed, 'tus recetas') : errorIngredientes);

  const estado = $derived.by(() => {
    if (seccion === 'recetario') return chipRecetario;
    if (seccion === 'ingredientes') {
      if (cargandoIngredientes) return { texto: 'Cargando tu inventario…', vivo: true };
      if (!vigia.ingredientes) return { texto: esDeRed(vigia.error) ? 'Sin conexión' : 'No se pudo leer', vivo: false };
      if (!vigia.ingredientes.length) return { texto: 'Sin ingredientes', vivo: false };
      return vigia.acaban
        ? { texto: `${vigia.acaban} ${vigia.acaban === 1 ? 'se está acabando' : 'se están acabando'}`, vivo: false, pausa: true }
        : { texto: 'Nada se está acabando', vivo: true };
    }
    if (lectura.estado === 'leyendo') return { texto: 'Cargando tus recetas…', vivo: true };
    if (lectura.estado === 'error') return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    if (seccion === 'recetas') {
      const platillos = menu.productos.filter((p) => !p.es_envio);
      const con = new Set(recetario.recetas.map((r) => r.producto_id));
      const sin = platillos.filter((p) => !con.has(p.id)).length;
      if (!platillos.length) return { texto: 'Sin platillos', vivo: false };
      return sin ? { texto: `${plural(sin, 'platillo', 'platillos')} sin receta`, vivo: false, pausa: true } : { texto: 'Todos con receta', vivo: true };
    }
    const n = recetario.preparaciones.length;
    return n ? { texto: plural(n, 'preparación', 'preparaciones'), vivo: true } : { texto: 'Sin preparaciones', vivo: false };
  });

  async function leer() {
    try {
      const [m, r] = await Promise.all([leerMenu(sucursal.id), leerRecetas(supabase, sucursal.id)]);
      lectura = { estado: 'listo', menu: m, recetario: r };
      recordarFilas(llave('recetas'), m.productos.filter((p) => !p.es_envio).length);
      recordarFilas(llave('preparaciones'), r.preparaciones.length);
    } catch (error) {
      console.error('[inventario] no se pudieron leer el menú y las recetas:', error);
      if (lectura.estado !== 'listo') lectura = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  // Después de guardar algo: lo que cambió se vuelve a leer (los ingredientes, también por el tiempo real).
  function alCambiar() {
    void leer();
    void vigia.leer();
    versionRecetario++;
  }

  // «Cambiar lo que lleva» del Recetario: la ventana de la receta del platillo, o la de la preparación.
  function cambiarLoQueLleva(de: { tipo: 'platillo' | 'preparacion'; id: number }) {
    if (lectura.estado !== 'listo') return;
    if (de.tipo === 'platillo') {
      const producto = menu.productos.find((p) => p.id === de.id);
      if (producto) ventana = { tipo: 'receta', producto };
      else console.error('[inventario] el platillo del recetario no está en el menú leído:', de.id);
    } else {
      const preparacion = recetario.preparaciones.find((p) => p.id === de.id);
      if (preparacion) ventana = { tipo: 'preparacion', preparacion };
      else console.error('[inventario] la preparación del recetario no está en las leídas:', de.id);
    }
  }

  onMount(async () => {
    leerZona(supabase, sucursal.id)
      .then((z) => (zona = z))
      .catch((falla) => console.error('[inventario] no se pudo leer la zona; el historial usa la de México:', falla));
    // Si los ingredientes ya estaban, entran en cascada al llegar lo demás; si no, cuando lleguen.
    await leer();
    await tick();
    cascada(cuerpo);
  });

  // La primera vez que llegan los ingredientes, si la vista ya estaba abierta, también en cascada.
  let yaEntraron = false;
  $effect(() => {
    if (!vigia.ingredientes || yaEntraron) return;
    yaEntraron = true;
    if (seccion === 'ingredientes') void tick().then(() => cascada(cuerpo));
  });

  async function cambiarSeccion(valor: Seccion) {
    if (valor === seccion) return;
    // Del Recetario en «Editar» con cambios, primero «Tienes cambios sin guardar».
    if (seccion === 'recetario' && libro) return libro.pedirSalida(() => void irASeccion(valor));
    await irASeccion(valor);
  }

  async function irASeccion(valor: Seccion) {
    seccion = valor;
    await tick();
    cascada(cuerpo);
  }

  // La ventana del ingrediente toma el de la vigía, para que su «Queda» y su historial cambien en vivo.
  const ingredienteAbierto = $derived.by<Ingrediente | null>(() => {
    const v = ventana;
    return v?.tipo === 'ingrediente' && v.id !== null ? (ingredientes.find((i) => i.id === v.id) ?? null) : null;
  });
</script>

<BarraArriba titulo="Inventario" {estado} chipAntes>
  {#snippet junto()}
    <Dock
      etiqueta="Sección de Inventario"
      opciones={[
        { valor: 'ingredientes', texto: 'Ingredientes', icono: 'inventario' },
        { valor: 'recetas', texto: 'Recetas', icono: 'receta' },
        { valor: 'preparaciones', texto: 'Preparaciones', icono: 'olla' },
        { valor: 'recetario', texto: 'Recetario', icono: 'libro' },
      ]}
      elegida={seccion}
      alElegir={cambiarSeccion}
    />
  {/snippet}
  {#if seccion === 'ingredientes'}
    <Boton etiqueta="Contar" icono="contar" apagado={!ingredientes.length} onclick={() => (ventana = { tipo: 'contar' })} />
    <Boton etiqueta="Merma" icono="eliminar" apagado={!ingredientes.length} onclick={() => (ventana = { tipo: 'merma' })} />
    <Boton etiqueta="Llegó" icono="llego" apagado={!ingredientes.length} onclick={() => (ventana = { tipo: 'llego' })} />
    <Boton
      etiqueta="Nuevo ingrediente"
      icono="mas"
      tono="tinta"
      apagado={cargandoIngredientes}
      onclick={() => (ventana = { tipo: 'ingrediente', id: null })}
    />
  {:else if seccion === 'preparaciones'}
    <Boton
      etiqueta="Nueva preparación"
      icono="mas"
      tono="tinta"
      apagado={lectura.estado !== 'listo'}
      onclick={() => (ventana = { tipo: 'preparacion', preparacion: null })}
    />
  {:else if seccion === 'recetario' && modoRecetario !== 'cuadros'}
    <Boton etiqueta="Cambiar lo que lleva" icono="receta" apagado={lectura.estado !== 'listo'} onclick={() => libro?.cambiarLoQueLleva()} />
    {#if modoRecetario === 'pagina'}
      <Boton etiqueta="Editar" icono="crear" tono="tinta" onclick={() => libro?.editar()} />
    {/if}
  {/if}
</BarraArriba>

{#if seccion === 'recetario'}
  <SeccionRecetario
    bind:this={libro}
    bind:modo={modoRecetario}
    bind:chip={chipRecetario}
    restauranteId={sucursal.id}
    version={versionRecetario}
    alCambiarLoQueLleva={cambiarLoQueLleva}
  />
{:else}
<main class="cuerpo inv-desliza" bind:this={cuerpo}>
  <section class="seccion" aria-label="Inventario">
    {#if seccion === 'ingredientes'}
      <Ingredientes
        {ingredientes}
        cargando={cargandoIngredientes}
        error={errorIngredientes}
        esqueletos={filas.ingredientes}
        gerente
        alEditar={(i) => (ventana = { tipo: 'ingrediente', id: i.id })}
      />
    {:else if seccion === 'recetas'}
      <Recetas
        {menu}
        {recetario}
        {ingredientes}
        cargando={cargandoRecetas}
        error={errorRecetas}
        esqueletos={filas.recetas}
        alEditar={(p) => (ventana = { tipo: 'receta', producto: p })}
      />
    {:else}
      <Preparaciones
        {recetario}
        {ingredientes}
        cargando={cargandoRecetas}
        error={errorRecetas}
        esqueletos={filas.preparaciones}
        alEditar={(p) => (ventana = { tipo: 'preparacion', preparacion: p })}
      />
    {/if}
  </section>
</main>
{/if}

{#if ventana?.tipo === 'ingrediente'}
  <VentanaIngrediente
    restauranteId={sucursal.id}
    ingrediente={ingredienteAbierto}
    menu={lectura.estado === 'listo' ? menu : null}
    recetario={lectura.estado === 'listo' ? recetario : null}
    {zona}
    hoy={sucursal.hoy}
    {alCambiar}
    alCerrar={() => (ventana = null)}
  />
{:else if ventana?.tipo === 'llego'}
  <VentanaLlego cliente={supabase} restauranteId={sucursal.id} {ingredientes} {alCambiar} alCerrar={() => (ventana = null)} />
{:else if ventana?.tipo === 'merma'}
  <VentanaMerma cliente={supabase} restauranteId={sucursal.id} {ingredientes} {alCambiar} alCerrar={() => (ventana = null)} />
{:else if ventana?.tipo === 'contar'}
  <VentanaContar restauranteId={sucursal.id} {ingredientes} {alCambiar} alCerrar={() => (ventana = null)} />
{:else if ventana?.tipo === 'receta' && lectura.estado === 'listo'}
  <VentanaReceta
    restauranteId={sucursal.id}
    de={{ producto: ventana.producto }}
    {menu}
    {recetario}
    {ingredientes}
    {alCambiar}
    alEditarOpcion={(o, g) => (opcion = { opcion: o, grupo: g })}
    alCerrar={() => (ventana = null)}
  />
{:else if ventana?.tipo === 'preparacion' && lectura.estado === 'listo'}
  <VentanaPreparacion
    restauranteId={sucursal.id}
    preparacion={ventana.preparacion}
    {menu}
    {recetario}
    {ingredientes}
    {alCambiar}
    alCerrar={() => (ventana = null)}
  />
{/if}

{#if opcion && lectura.estado === 'listo'}
  <VentanaReceta
    restauranteId={sucursal.id}
    de={opcion}
    {menu}
    {recetario}
    {ingredientes}
    {alCambiar}
    alCerrar={() => (opcion = null)}
  />
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
