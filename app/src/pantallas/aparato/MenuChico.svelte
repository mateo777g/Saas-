<!--
  La pestaña «Menú» de la cocina y de la caja (maqueta BBBNJST5w9qZfHWNdovGgb v3, «Cocina · Menú» y «Caja · Menú»;
  encuestas 18 y 19): la tabla de Mi menú, chiquita, con la foto, el nombre, la categoría, «Hoy» (Hay o Agotado) y el
  ojito, que solo oculta y muestra (marcar_agotado). Con la búsqueda y el filtro por categoría, más «Agotados». Sin
  envíos ni archivados. Lo agotado les sale en gris a los meseros y el menú en línea deja de ofrecerlo; las opciones y lo
  demás del menú se cambian en Mi menú. El chip de la barra cuenta los agotados. Llega en vivo: si el gerente o alguien
  más marca uno, cambia aquí también.

  Usa la sesión del aparato que le pasan, nunca la del panel.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount } from 'svelte';
  import AvisoFlotante from '../../diseno/AvisoFlotante.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import IconoCategoria from '../../diseno/IconoCategoria.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import { esDeRed, SIN_CONEXION } from '../../lib/errores';
  import { anchos, filasDeLaUltimaVez, recordarFilas } from '../../lib/esqueletos';
  import { plural } from '../../lib/formato';
  import { leerPlatillos, marcarAgotado, type CategoriaChica, type Platillo } from '../../lib/inventario';
  import { escuchar } from '../../lib/pos';
  import Foto from '../gerente/menu/Foto.svelte';
  import Herramientas from '../gerente/inventario/Herramientas.svelte';
  import '../gerente/inventario/tabla.css';
  import Barra from '../pos/ancho/Barra.svelte';
  import type { Anfitrion } from '../pos/ancho/barra';
  import '../pos/ancho/ancho.css';

  let { cliente, restauranteId, anfitrion }: { cliente: SupabaseClient; restauranteId: string; anfitrion: Anfitrion } = $props();

  let datos = $state<{ categorias: CategoriaChica[]; platillos: Platillo[] } | null>(null);
  let falla = $state<unknown>(null);
  let busqueda = $state('');
  let filtro = $state<string | null>(null);
  let aviso = $state<string | null>(null);
  let cambiando = $state<number | null>(null);

  // svelte-ignore state_referenced_locally
  const llave = `menu-chico-${restauranteId}`;
  const filas = anchos(['96px', '120px', '70px', '104px', '84px'], filasDeLaUltimaVez(llave));

  async function leer() {
    try {
      datos = await leerPlatillos(cliente, restauranteId);
      falla = null;
      recordarFilas(llave, datos.platillos.length);
    } catch (error) {
      console.error('[menu chico] no se pudo leer el menú; se queda lo que había:', error);
      falla = error;
    }
  }

  // Al entrar, con cada cambio de productos (el tiempo real) y al volver a la pestaña. Varios avisos juntos, una lectura.
  let reloj: ReturnType<typeof setTimeout> | undefined;
  const programar = () => {
    clearTimeout(reloj);
    reloj = setTimeout(() => void leer(), 250);
  };
  onMount(() => {
    void leer();
    const dejar = escuchar(cliente, restauranteId, ['productos'], programar);
    const alVolver = () => {
      if (document.visibilityState === 'visible') programar();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      clearTimeout(reloj);
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  });

  const platillos = $derived(datos?.platillos ?? []);
  const categorias = $derived(datos?.categorias ?? []);
  const categoriaDe = $derived(new Map(categorias.map((c) => [c.id, c])));
  const agotados = $derived(platillos.filter((p) => !p.visible).length);
  const cargando = $derived(datos === null && !falla);

  const texto = $derived(busqueda.trim());
  const mostrados = $derived.by(() => {
    const q = texto.toLowerCase();
    return platillos.filter((p) => {
      if (filtro === 'agotados' && p.visible) return false;
      if (filtro !== null && filtro !== 'agotados' && String(p.categoria_id) !== filtro) return false;
      return !q || p.nombre.toLowerCase().includes(q);
    });
  });

  const chip = $derived.by(() => {
    if (cargando) return { texto: 'Cargando el menú…', vivo: true };
    if (!datos) return { texto: esDeRed(falla) ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    return agotados ? { texto: plural(agotados, 'agotado', 'agotados'), vivo: false, pausa: true } : { texto: 'Nada agotado', vivo: true };
  });

  // El ojito: tapado si hay («Marcar agotado»), abierto si se agotó («Ya hay»). Cambia en cuanto Postgres dice que sí.
  async function alternar(p: Platillo) {
    if (cambiando !== null) return;
    cambiando = p.id;
    try {
      p.visible = await marcarAgotado(cliente, restauranteId, p.id, p.visible);
    } catch (error) {
      aviso = (error as Error).message;
    } finally {
      cambiando = null;
    }
  }
</script>

<div class="menu-chico">
  <div class="pos-ancho barra-c">
    <Barra {anfitrion} titulo="Menú" {chip} />
  </div>

  <main class="cuerpo inv-desliza">
    <Herramientas
      bind:busqueda
      placeholder="Busca un platillo…"
      cuenta={plural(mostrados.length, 'PLATILLO', 'PLATILLOS')}
      {cargando}
      filtro={{
        titulo: 'CATEGORÍAS',
        todas: { boton: 'Todas las categorías', nombre: 'Todas', icono: 'menu' },
        opciones: [
          ...categorias.map((c) => ({
            valor: String(c.id),
            nombre: c.nombre,
            cuenta: platillos.filter((p) => p.categoria_id === c.id).length,
            categoria: c.icono,
          })),
          { valor: 'agotados', nombre: 'Agotados', cuenta: agotados, color: 'amarillo' },
        ],
        total: platillos.length,
        elegida: filtro,
        alElegir: (v) => (filtro = v),
      }}
    />

    <Tabla
      columnas="2.4fr 1.2fr 1fr 80px"
      relleno="0 16px"
      altoFila={64}
      marco
      encabezados={[{ texto: 'Platillo' }, { texto: 'Categoría' }, { texto: 'Hoy' }, { texto: '' }]}
    >
      {#if cargando}
        <span class="solo-lector">Cargando el menú…</span>
        {#each filas as ancho, i (i)}
          <div class="fila quieta" aria-hidden="true">
            <span class="inv-producto"><Esqueleto ancho="44px" alto="44px" redondo="11px" /><Esqueleto {ancho} alto="11px" /></span>
            <span><Esqueleto ancho="72px" alto="24px" redondo="8px" /></span>
            <span><Esqueleto ancho="60px" alto="11px" /></span>
            <span></span>
          </div>
        {/each}
      {:else if !datos}
        {#if esDeRed(falla)}
          <NotaTabla relleno={48} angosta titulo="Sin conexión." texto={SIN_CONEXION} />
        {:else}
          <NotaTabla relleno={48} angosta titulo="No se pudo cargar el menú." texto="Intenta de nuevo en un momento." />
        {/if}
      {:else if !platillos.length}
        <NotaTabla relleno={48} angosta titulo="Todavía no hay platillos." texto="El gerente los agrega en Mi menú, desde su panel." />
      {:else if !mostrados.length}
        <NotaTabla
          relleno={48}
          angosta
          titulo={texto ? `No encontramos platillos para "${texto}".` : filtro === 'agotados' ? 'Nada está agotado.' : 'No hay platillos en esta categoría.'}
          texto="Prueba con otro nombre o con Todas las categorías."
        />
      {:else}
        {#each mostrados as p (p.id)}
          {@const c = categoriaDe.get(p.categoria_id)}
          <div class="fila">
            <span class="inv-producto">
              <Foto src={p.foto} oculta={!p.visible} />
              <span class="inv-nombre">{p.nombre}</span>
            </span>
            <span>{#if c}<span class="inv-chip"><IconoCategoria id={c.icono} tamano={13} /><span>{c.nombre}</span></span>{/if}</span>
            <span><span class="hoy" class:no={!p.visible}><span class="punto"></span>{p.visible ? 'Hay' : 'Agotado'}</span></span>
            <span class="inv-acciones">
              <BotonCuadro
                icono={p.visible ? 'oculto' : 'ojo'}
                ayuda={p.visible ? 'Marcar agotado' : 'Ya hay'}
                apagado={cambiando === p.id}
                onclick={() => alternar(p)}
              />
            </span>
          </div>
        {/each}
      {/if}
    </Tabla>

    <p class="inv-nota">
      Lo agotado les sale en gris a los meseros y el menú en línea deja de ofrecerlo, hasta que lo regreses. Las opciones agotadas y
      lo demás del menú se cambian en Mi menú, desde el panel del gerente.
    </p>
  </main>
</div>

{#if aviso}
  {#key aviso}
    <AvisoFlotante mensaje={aviso} alTerminar={() => (aviso = null)} />
  {/key}
{/if}

<style>
  .menu-chico {
    position: absolute;
    inset: 0;
    background: var(--fondo);
    color: var(--texto);
    font-size: 13.5px;
    text-align: left;
    overflow: hidden;
  }

  :global(:root[data-estilo='cristal'] .lugar-vista) .menu-chico {
    background: transparent;
    overflow: visible;
  }

  /* Cristal en el aparato: lo de atrás es su degradado (aparato/cristal-aparato.css), como la Cocina. */
  :global(:root[data-puerta='equipo'][data-estilo='cristal']) .menu-chico {
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

  .cuerpo > :global(.tabla) {
    flex: none;
  }

  /* «Hoy», como «Visible» y «Oculto» de Mi menú. */
  .hoy {
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
    background: var(--verde);
  }

  .hoy.no {
    font-weight: 500;
    color: var(--tenue);
  }

  .hoy.no .punto {
    background: transparent;
    border: 1.5px solid var(--tenue);
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
