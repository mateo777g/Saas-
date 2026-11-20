<!--
  La pestaña «Recetario» de la cocina y de la caja (maqueta DFVTWEB3eZBEKctyxWjGjg v1, «Cocina · Recetario», «Cocina ·
  Taco al pastor», «Cocina · Salsa verde» y «Caja · Recetario»; encuestas 6 a 8): los mismos cuadros del panel, pero solo
  los platillos y las preparaciones que tienen pasos (la base no le manda los demás); se toca uno y se lee su página, la
  misma de Don Chuy, sin «Editar» ni «Cambiar lo que lleva». Una preparación de lo que lleva se abre solo si su recetario
  tiene pasos. El chip de la barra dice cuántos recetarios hay. Va siempre a lo ancho, como Inventario y Menú, y no se
  cierra a los 2 minutos (Aparato.svelte). Sin tiempo real: lee al entrar y al volver a la pestaña.

  Usa la sesión del aparato que le pasan, nunca la del panel.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount, tick } from 'svelte';
  import '../recetario/recetario.css';
  import { cascada } from '../../diseno/cascada';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { plural } from '../../lib/formato';
  import { contar, leerCuadros, leerPagina, type Cuadros as LosCuadros, type De, type Pagina as LaPagina } from '../../lib/recetario';
  import '../gerente/inventario/tabla.css';
  import Barra from '../pos/ancho/Barra.svelte';
  import type { Anfitrion } from '../pos/ancho/barra';
  import '../pos/ancho/ancho.css';
  import Cuadros from '../recetario/Cuadros.svelte';
  import Pagina from '../recetario/Pagina.svelte';

  let { cliente, restauranteId, anfitrion }: { cliente: SupabaseClient; restauranteId: string; anfitrion: Anfitrion } = $props();

  type Lectura<T> = { estado: 'leyendo' } | { estado: 'listo'; datos: T } | { estado: 'error'; deRed: boolean };
  let cuadros = $state<Lectura<LosCuadros>>({ estado: 'leyendo' });
  let abierta = $state<De | null>(null);
  let pagina = $state<Lectura<LaPagina | null>>({ estado: 'leyendo' });
  let cuerpo = $state<HTMLElement>();

  // svelte-ignore state_referenced_locally
  const llave = `recetario-aparato-${restauranteId}`;
  const filas = filasDeLaUltimaVez(llave) || 8;

  const ERROR_LEER = (deRed: boolean) =>
    deRed ? { titulo: 'Sin conexión.', texto: SIN_CONEXION } : { titulo: 'No se pudo cargar el recetario.', texto: 'Intenta de nuevo en un momento.' };

  const chip = $derived.by(() => {
    if (cuadros.estado === 'leyendo') return { texto: 'Cargando el recetario…', vivo: true };
    if (cuadros.estado === 'error') return { texto: cuadros.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    const { total } = contar(cuadros.datos);
    return total ? { texto: plural(total, 'recetario', 'recetarios'), vivo: true } : { texto: 'Sin recetarios', vivo: false };
  });

  const icono = $derived.by(() => {
    if (cuadros.estado !== 'listo' || abierta?.tipo !== 'platillo') return null;
    const id = abierta.id;
    return cuadros.datos.categorias.find((c) => c.platillos.some((p) => p.id === id))?.icono ?? null;
  });

  async function leerLosCuadros() {
    try {
      const datos = await leerCuadros(cliente, restauranteId);
      cuadros = { estado: 'listo', datos };
      recordarFilas(llave, contar(datos).total);
    } catch (error) {
      console.error('[recetario] no se pudieron leer los cuadros; se queda lo que había:', error);
      if (cuadros.estado !== 'listo') cuadros = { estado: 'error', deRed: esDeRed(error) };
    }
  }

  async function leerLaPagina(de: De, primera: boolean) {
    if (primera) pagina = { estado: 'leyendo' };
    try {
      const datos = await leerPagina(cliente, restauranteId, de);
      if (abierta?.tipo !== de.tipo || abierta.id !== de.id) return;
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
    cuerpo?.scrollTo({ top: 0 });
    await leerLaPagina(de, true);
  }

  async function aLosCuadros() {
    abierta = null;
    void leerLosCuadros();
    await tick();
    cascada(cuerpo, '.rec-rejilla > .rec-cuadro');
  }

  onMount(() => {
    void leerLosCuadros().then(async () => {
      await tick();
      cascada(cuerpo, '.rec-rejilla > .rec-cuadro');
    });
    const alVolver = () => {
      if (document.visibilityState !== 'visible') return;
      void leerLosCuadros();
      if (abierta) void leerLaPagina(abierta, false);
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
</script>

<div class="recetario-aparato">
  <div class="pos-ancho barra-c">
    <Barra {anfitrion} titulo="Recetario" {chip} />
  </div>

  <main class="cuerpo inv-desliza rec-aparato" bind:this={cuerpo}>
    {#if abierta}
      <Pagina
        pagina={pagina.estado === 'listo' ? pagina.datos : null}
        cargando={pagina.estado === 'leyendo'}
        error={pagina.estado === 'error' ? ERROR_LEER(pagina.deRed) : null}
        {icono}
        enAparato
        alVolver={() => void aLosCuadros()}
        alAbrirPreparacion={(id) => void abrir({ tipo: 'preparacion', id })}
      />
    {:else}
      <Cuadros
        cuadros={cuadros.estado === 'listo' ? cuadros.datos : null}
        cargando={cuadros.estado === 'leyendo'}
        error={cuadros.estado === 'error' ? ERROR_LEER(cuadros.deRed) : null}
        esqueletos={filas}
        enAparato
        alAbrir={(de) => void abrir(de)}
      />
    {/if}
  </main>
</div>

<style>
  .recetario-aparato {
    position: absolute;
    inset: 0;
    background: var(--fondo);
    color: var(--texto);
    font-size: 13.5px;
    text-align: left;
    overflow: hidden;
  }

  /* Cristal en el aparato: lo de atrás es su degradado (aparato/cristal-aparato.css), como la Cocina. */
  :global(:root[data-puerta='equipo'][data-estilo='cristal']) .recetario-aparato {
    background: transparent;
  }

  .pos-ancho.barra-c {
    bottom: auto;
    height: 56px;
    z-index: 2;
    overflow: visible;
    background: transparent;
  }

  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: 0;
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding-bottom: 28px;
    overflow: auto;
  }

  @media (max-width: 860px) {
    .barra-c :global(.ap-lugar) {
      display: none;
    }
  }

  @media (max-width: 600px) {
    .barra-c :global(.chip) {
      display: none;
    }
  }
</style>
