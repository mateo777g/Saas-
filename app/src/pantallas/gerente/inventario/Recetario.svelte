<!--
  El cuarto botón de Inventario, «Recetario» (maqueta DFVTWEB3eZBEKctyxWjGjg v1; encuestas 1 a 8 de
  planes/trabajo/recetario/encuestas.md): los platillos y las preparaciones en cuadros (recetario/Cuadros.svelte); tocar
  uno abre su página en la misma vista (recetario/Pagina.svelte), tal como la ve la cocina, con «‹ Recetario» para
  regresar; «Editar» la vuelve campos (EditarRecetario.svelte). «Editar» y «Cambiar lo que lleva» van en la barra de
  arriba de Inventario, que pregunta aquí qué enseñar (`modo`) y su chip («9 sin escribir»). «Cambiar lo que lleva» abre
  encima la ventana de la receta de Recetas (o la de la preparación), que vive en Inventario; al guardarla, Inventario sube
  `version` y aquí se lee otra vez.

  Va en el lugar de la sección entera (su propio .cuerpo), para que la barra de guardar de «Editar» vaya de lo ancho de la
  vista. Sin tiempo real: lee al entrar, después de guardar y al volver a la pestaña.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import '../../recetario/recetario.css';
  import { cascada } from '../../../diseno/cascada';
  import { esDeRed, SIN_CONEXION } from '../../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../../lib/esqueletos';
  import { contar, leerCuadros, leerPagina, type Cuadros as LosCuadros, type De, type Pagina as LaPagina } from '../../../lib/recetario';
  import { supabase } from '../../../lib/supabase';
  import Cuadros from '../../recetario/Cuadros.svelte';
  import Pagina from '../../recetario/Pagina.svelte';
  import EditarRecetario from './EditarRecetario.svelte';

  type Chip = { texto: string; vivo: boolean; pausa?: boolean };

  let {
    restauranteId,
    version = 0,
    modo = $bindable<'cuadros' | 'pagina' | 'editar'>('cuadros'),
    chip = $bindable<Chip>({ texto: 'Cargando tu recetario…', vivo: true }),
    alCambiarLoQueLleva,
  }: {
    restauranteId: string;
    version?: number;
    modo?: 'cuadros' | 'pagina' | 'editar';
    chip?: Chip;
    alCambiarLoQueLleva: (de: De) => void;
  } = $props();

  type Lectura<T> = { estado: 'leyendo' } | { estado: 'listo'; datos: T } | { estado: 'error'; deRed: boolean };
  let cuadros = $state<Lectura<LosCuadros>>({ estado: 'leyendo' });
  let abierta = $state<De | null>(null);
  let pagina = $state<Lectura<LaPagina | null>>({ estado: 'leyendo' });
  let editando = $state(false);
  let editor = $state<ReturnType<typeof EditarRecetario>>();
  let cuerpo = $state<HTMLElement>();

  // svelte-ignore state_referenced_locally
  const llave = `recetario-${restauranteId}`;
  const filas = filasDeLaUltimaVez(llave) || 8;

  const ERROR_LEER = (deRed: boolean) =>
    deRed ? { titulo: 'Sin conexión.', texto: SIN_CONEXION } : { titulo: 'No se pudo cargar tu recetario.', texto: 'Intenta de nuevo en un momento.' };

  $effect(() => {
    modo = abierta === null ? 'cuadros' : editando ? 'editar' : 'pagina';
  });

  $effect(() => {
    if (cuadros.estado === 'leyendo') chip = { texto: 'Cargando tu recetario…', vivo: true };
    else if (cuadros.estado === 'error') chip = { texto: cuadros.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    else {
      const { total, sinEscribir } = contar(cuadros.datos);
      chip = !total
        ? { texto: 'Sin platillos', vivo: false }
        : sinEscribir
          ? { texto: `${sinEscribir} sin escribir`, vivo: false, pausa: true }
          : { texto: 'Todos escritos', vivo: true };
    }
  });

  // El ícono de la categoría de un platillo (la página solo trae su nombre).
  const icono = $derived.by(() => {
    if (cuadros.estado !== 'listo' || abierta?.tipo !== 'platillo') return null;
    const id = abierta.id;
    return cuadros.datos.categorias.find((c) => c.platillos.some((p) => p.id === id))?.icono ?? null;
  });

  async function leerLosCuadros() {
    try {
      const datos = await leerCuadros(supabase, restauranteId);
      cuadros = { estado: 'listo', datos };
      recordarFilas(llave, contar(datos).total);
    } catch (error) {
      console.error('[recetario] no se pudieron leer los cuadros:', error);
      if (cuadros.estado !== 'listo') cuadros = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  async function leerLaPagina(de: De, primera: boolean) {
    if (primera) pagina = { estado: 'leyendo' };
    try {
      const datos = await leerPagina(supabase, restauranteId, de);
      if (abierta?.tipo !== de.tipo || abierta.id !== de.id) return; // ya se fue a otra
      pagina = { estado: 'listo', datos };
      if (primera) {
        await tick();
        cascada(cuerpo, '.rec-pasos > li');
      }
    } catch (error) {
      console.error('[recetario] no se pudo leer la página:', error);
      if (pagina.estado !== 'listo') pagina = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  async function abrir(de: De) {
    abierta = de;
    editando = false;
    cuerpo?.querySelector('.rec-desliza')?.scrollTo({ top: 0 });
    await leerLaPagina(de, true);
  }

  async function aLosCuadros() {
    abierta = null;
    editando = false;
    void leerLosCuadros();
    await tick();
    cascada(cuerpo, '.rec-rejilla > .rec-cuadro');
  }

  // Lo que pide la barra de arriba de Inventario.
  export function editar() {
    if (pagina.estado === 'listo' && pagina.datos) editando = true;
  }

  export function cambiarLoQueLleva() {
    if (abierta) alCambiarLoQueLleva(abierta);
  }

  // Irse de la sección (otro botón del dock): si está en «Editar» con cambios, primero la ventana.
  export function pedirSalida(seguir: () => void) {
    if (editando && editor) editor.pedirSalida(seguir);
    else seguir();
  }

  // Después de guardar en «Editar» o en «Cambiar lo que lleva»: los cuadros y la página otra vez.
  let versionVista = 0;
  $effect(() => {
    if (version === versionVista) return;
    versionVista = version;
    void leerLosCuadros();
    if (abierta) void leerLaPagina(abierta, false);
  });

  onMount(() => {
    void leerLosCuadros().then(async () => {
      await tick();
      cascada(cuerpo, '.rec-rejilla > .rec-cuadro');
    });
    const alVolver = () => {
      if (document.visibilityState !== 'visible' || editando) return;
      void leerLosCuadros();
      if (abierta) void leerLaPagina(abierta, false);
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
</script>

{#if editando && abierta && pagina.estado === 'listo' && pagina.datos}
  {#key `${abierta.tipo}-${abierta.id}`}
    <EditarRecetario
      bind:this={editor}
      {restauranteId}
      pagina={pagina.datos}
      {icono}
      alGuardado={() => {
        editando = false;
        void leerLosCuadros();
        if (abierta) void leerLaPagina(abierta, false);
      }}
      alDescartar={() => (editando = false)}
      alVolver={() => void aLosCuadros()}
    />
  {/key}
{:else}
  <main class="cuerpo inv-desliza" bind:this={cuerpo}>
    <section class="seccion" aria-label="Recetario">
      {#if abierta}
        <Pagina
          pagina={pagina.estado === 'listo' ? pagina.datos : null}
          cargando={pagina.estado === 'leyendo'}
          error={pagina.estado === 'error' ? ERROR_LEER(pagina.deRed) : null}
          {icono}
          alVolver={() => void aLosCuadros()}
          alAbrirPreparacion={(id) => void abrir({ tipo: 'preparacion', id })}
        />
      {:else}
        <Cuadros
          cuadros={cuadros.estado === 'listo' ? cuadros.datos : null}
          cargando={cuadros.estado === 'leyendo'}
          error={cuadros.estado === 'error' ? ERROR_LEER(cuadros.deRed) : null}
          esqueletos={filas}
          alAbrir={(de) => void abrir(de)}
        />
      {/if}
    </section>
  </main>
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
