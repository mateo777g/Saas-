<!--
  Los cuadros del recetario (maqueta DFVTWEB3eZBEKctyxWjGjg v1, «Recetario» y «Cocina · Recetario»): los platillos de Mi
  menú por categoría, en el orden del menú, y las preparaciones al final en su propio grupo (la olla), cada uno con su
  foto, su nombre y «6 pasos» o «Sin escribir». Arriba, la búsqueda en píldora y el filtro «Todos» con su lista «QUÉ
  ENSEÑAR» (Todos, cada categoría, Preparaciones y, solo en el panel, Sin escribir), como en Recetas; a la derecha, cuántos
  salen. Cada grupo lleva su título en mono con el ícono de su categoría y cuántos tiene. Tocar un cuadro abre su página.
  Los cuadros son los de Crear anuncios. Mientras lee la primera vez, esqueletos sin los títulos de grupo (sus nombres
  también vienen de la base).

  Lo usan el panel (Inventario) y el aparato (la pestaña Recetario de la cocina y la caja), que solo recibe los que
  tienen pasos.
-->
<script lang="ts">
  import './recetario.css';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import IconoCategoria from '../../diseno/IconoCategoria.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import { anchos } from '../../lib/esqueletos';
  import { plural } from '../../lib/formato';
  import { type Cuadro, type Cuadros, type De, urlDe } from '../../lib/recetario';
  import Herramientas from '../gerente/inventario/Herramientas.svelte';

  let {
    cuadros,
    cargando = false,
    error = null,
    esqueletos = 8,
    enAparato = false,
    alAbrir,
  }: {
    cuadros: Cuadros | null;
    cargando?: boolean;
    error?: { titulo: string; texto: string } | null;
    esqueletos?: number;
    // En la cocina y la caja: sin «Sin escribir» (solo les llegan los que tienen pasos).
    enAparato?: boolean;
    alAbrir: (de: De) => void;
  } = $props();

  let busqueda = $state('');
  let filtro = $state<string | null>(null);

  type Grupo = { clave: string; nombre: string; categoria: string | null; tipo: De['tipo']; cosas: Cuadro[] };
  const grupos = $derived.by<Grupo[]>(() => {
    if (!cuadros) return [];
    const g: Grupo[] = cuadros.categorias.map((c) => ({
      clave: String(c.id),
      nombre: c.nombre,
      categoria: c.icono,
      tipo: 'platillo',
      cosas: c.platillos,
    }));
    if (cuadros.preparaciones.length) {
      g.push({ clave: 'preparaciones', nombre: 'Preparaciones', categoria: null, tipo: 'preparacion', cosas: cuadros.preparaciones });
    }
    return g;
  });
  const total = $derived(grupos.reduce((n, g) => n + g.cosas.length, 0));
  const sinEscribir = $derived(grupos.reduce((n, g) => n + g.cosas.filter((c) => c.pasos === 0).length, 0));

  const texto = $derived(busqueda.trim());
  const mostrados = $derived.by(() => {
    const q = texto.toLowerCase();
    return grupos
      .filter((g) => filtro === null || filtro === 'sin' || filtro === g.clave)
      .map((g) => ({
        ...g,
        cosas: g.cosas.filter((c) => (filtro !== 'sin' || c.pasos === 0) && (!q || c.nombre.toLowerCase().includes(q))),
      }))
      .filter((g) => g.cosas.length);
  });
  const cuantos = $derived(mostrados.reduce((n, g) => n + g.cosas.length, 0));

  const filas = $derived(anchos(['110px', '84px', '120px', '96px'], esqueletos));
</script>

<Herramientas
  bind:busqueda
  placeholder="Busca un platillo o preparación…"
  cuenta={plural(cuantos, 'RECETARIO', 'RECETARIOS')}
  {cargando}
  filtro={{
    titulo: 'QUÉ ENSEÑAR',
    todas: { boton: 'Todos', nombre: 'Todos', icono: 'libro' },
    opciones: [
      ...grupos.map((g) =>
        g.categoria !== null
          ? { valor: g.clave, nombre: g.nombre, cuenta: g.cosas.length, categoria: g.categoria }
          : { valor: g.clave, nombre: g.nombre, cuenta: g.cosas.length, icono: 'olla' },
      ),
      ...(enAparato ? [] : [{ valor: 'sin', nombre: 'Sin escribir', cuenta: sinEscribir, color: 'amarillo' }]),
    ],
    total,
    elegida: filtro,
    alElegir: (v) => (filtro = v),
  }}
/>

<div class="rec-desliza">
  {#if cargando}
    <span class="solo-lector">Cargando el recetario…</span>
    <div class="rec-rejilla esqueletos" aria-hidden="true">
      {#each filas as ancho, i (i)}
        <span class="rec-cuadro quieto">
          <span class="rec-cuadro-foto"><Esqueleto alto="100%" redondo="10px" /></span>
          <span class="rec-cuadro-textos"><Esqueleto {ancho} alto="12px" /><Esqueleto ancho="52px" alto="10px" /></span>
        </span>
      {/each}
    </div>
  {:else if error}
    <NotaTabla relleno={48} angosta titulo={error.titulo} texto={error.texto} />
  {:else if !total}
    {#if enAparato}
      <NotaTabla relleno={48} angosta titulo="Todavía no hay recetarios." texto="El gerente los escribe en Inventario, desde su panel." />
    {:else}
      <NotaTabla relleno={48} angosta titulo="Todavía no hay platillos." texto="Agrégalos en Mi menú: cada uno sale aquí para escribir cómo se hace." />
    {/if}
  {:else if !cuantos}
    <NotaTabla
      relleno={48}
      angosta
      titulo={texto ? `No encontramos recetarios para "${texto}".` : filtro === 'sin' ? 'Todos tienen sus pasos.' : 'No hay recetarios aquí.'}
      texto="Prueba con otro nombre o con Todos."
    />
  {:else}
    <div class="rec-grupos">
      {#each mostrados as g (g.clave)}
        <section aria-label={g.nombre}>
          <h3 class="rec-grupo-titulo">
            {#if g.categoria !== null}<IconoCategoria id={g.categoria} tamano={14} />{:else}<Icono nombre="olla" tamano={14} />{/if}
            <span>{g.nombre.toUpperCase()}</span>
            <span class="rec-cuenta">{g.cosas.length}</span>
          </h3>
          <div class="rec-rejilla">
            {#each g.cosas as c (c.id)}
              {@const foto = urlDe(c.foto)}
              <button type="button" class="rec-cuadro" onclick={() => alAbrir({ tipo: g.tipo, id: c.id })}>
                <span class="rec-cuadro-foto" style:background-image={foto ? `url(${foto})` : undefined}></span>
                <span class="rec-cuadro-textos">
                  <span class="rec-cuadro-nombre">{c.nombre}</span>
                  {#if c.pasos}
                    <span class="rec-cuadro-pie">{plural(c.pasos, 'paso', 'pasos')}</span>
                  {:else}
                    <span class="rec-sin"><i></i>Sin escribir</span>
                  {/if}
                </span>
              </button>
            {/each}
          </div>
        </section>
      {/each}
    </div>
  {/if}
</div>

<style>
  .esqueletos {
    padding-top: 4px;
  }
</style>
