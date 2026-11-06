<!--
  «Mi biblioteca» (parte 7b-2 de la libreta 7; maqueta SMeWoa5ypbcVQmvBGyyytt, aprobada el 31 de
  octubre de 2026; sus decisiones en planes/trabajo/7b/biblioteca-7b2.md). Como en Flet: un collage
  por día («HOY · SÁBADO 31 DE OCTUBRE», «AYER · …» y, más atrás, solo la fecha), cada anuncio en la
  columna más corta con su forma real y sin marcos; con el cursor encima, sus productos, «POST ·
  13:25», Descargar y Eliminar; un clic lo abre en grande. El que se está haciendo va hasta arriba
  de HOY con la rejilla de puntitos y, al terminar, entra solo en su lugar.

  Todos los gerentes de la sucursal ven todos sus anuncios. Lo lee todo de Postgres con
  mi_biblioteca al abrir, al volver a la pestaña, con cada cambio de sus anuncios por realtime y,
  mientras uno se hace, cada 30 segundos. Ver, descargar, borrar y ponerlo en el menú no gastan IA.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Confirmar from '../../diseno/Confirmar.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Tarjeta from '../../diseno/Tarjeta.svelte';
  import {
    anuncios as cuantosAnuncios,
    cabeceraDelDia,
    creado,
    eliminarAnuncio,
    escucharBiblioteca,
    FORMA,
    leerBiblioteca,
    listaDe,
    ponerEnMiMenu,
    seBorra,
    type AnuncioHaciendo,
    type AnuncioListo,
    type DatosBiblioteca,
  } from '../../lib/biblioteca';
  import { descargarAnuncio, type Formato } from '../../lib/crearContenido';
  import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from '../../lib/errores';
  import { urlFoto } from '../../lib/fotos';
  import type { Sucursal } from '../../lib/gerente';
  import CajaSucursales from './CajaSucursales.svelte';
  import Cargador from './crearContenido/Cargador.svelte';
  import Visor from './biblioteca/Visor.svelte';

  let {
    sucursal,
    sucursales,
    alElegir,
    alIr,
  }: {
    sucursal: Sucursal;
    sucursales: Sucursal[];
    alElegir: (sucursal: Sucursal) => void;
    // «Crear anuncio» lleva a Crear contenido.
    alIr: (vista: 'crear') => void;
  } = $props();

  // El ancho que se busca por columna, como en Flet: de ahí cuántas caben (4 en 1440).
  const ANCHO_COLUMNA = 275;
  const HUECO = 14;

  let datos = $state<DatosBiblioteca | null>(null);
  let errorLectura = $state<string | null>(null);
  let filtro = $state<'todo' | Formato>('todo');
  let ancho = $state(0);
  let cuerpo = $state<HTMLDivElement>();

  // El que se está haciendo: desde cuándo, con el reloj de este navegador (los segundos los da
  // Postgres). Los que terminaron mientras se veían entran con el efecto de «Resultado».
  let desde = $state<{ id: number; ms: number } | null>(null);
  let recienListos = $state<number[]>([]);

  // Lo que se toca: el anuncio en grande, Eliminar, Descargar y «Ponerlo en mi menú».
  let visor = $state<number | null>(null);
  let confirmar = $state<{ anuncio: AnuncioListo; desdeVisor: boolean; lugar: number } | null>(null);
  let bajando = $state<number | null>(null);
  let bajado = $state<number | null>(null);
  let poniendo = $state<number | null>(null);
  let puestos = $state<number[]>([]);
  let errorPoner = $state<{ id: number; texto: string } | null>(null);
  let errorAccion = $state<string | null>(null);

  const listos = $derived((datos?.anuncios ?? []).filter((a): a is AnuncioListo => a.estado === 'listo'));
  const haciendo = $derived((datos?.anuncios ?? []).find((a): a is AnuncioHaciendo => a.estado === 'haciendo') ?? null);
  const pasa = (formato: Formato) => filtro === 'todo' || filtro === formato;
  // Lo que deja ver el filtro, del más nuevo al más viejo: lo que recorren las flechas.
  const visibles = $derived(listos.filter((a) => pasa(a.formato)));
  const haciendoVisible = $derived(haciendo && pasa(haciendo.formato) ? haciendo : null);
  const cuenta = $derived({
    todo: listos.length,
    post: listos.filter((a) => a.formato === 'post').length,
    historia: listos.filter((a) => a.formato === 'historia').length,
    cartel: listos.filter((a) => a.formato === 'cartel').length,
  });
  const columnas = $derived(Math.max(2, Math.min(6, Math.floor((ancho + HUECO) / ANCHO_COLUMNA))));

  type Pieza = AnuncioListo | AnuncioHaciendo;
  // Un collage por día; el que se está haciendo va hasta arriba de HOY. Cada anuncio cae en la
  // columna más corta (las alturas, en anchos de columna), como en Flet.
  const dias = $derived.by(() => {
    if (!datos) return [];
    const grupos: { dia: string; piezas: Pieza[]; listos: number; haciendo: boolean }[] = [];
    if (haciendoVisible) grupos.push({ dia: datos.hoy, piezas: [haciendoVisible], listos: 0, haciendo: true });
    for (const a of visibles) {
      let g = grupos[grupos.length - 1];
      if (!g || g.dia !== a.dia) {
        g = { dia: a.dia, piezas: [], listos: 0, haciendo: false };
        grupos.push(g);
      }
      g.piezas.push(a);
      g.listos++;
    }
    return grupos.map((g) => {
      const cols: Pieza[][] = Array.from({ length: columnas }, () => []);
      const altos = Array(columnas).fill(0);
      for (const p of g.piezas) {
        const i = altos.indexOf(Math.min(...altos));
        cols[i].push(p);
        altos[i] += FORMA[p.formato].alto + 0.05;
      }
      const textos = [g.listos ? cuantosAnuncios(g.listos).toUpperCase() : '', g.haciendo ? '1 HACIÉNDOSE' : ''].filter(Boolean);
      return { dia: g.dia, cabecera: cabeceraDelDia(g.dia, datos!.hoy), cuenta: textos.join(' · '), cols };
    });
  });

  const enGrande = $derived(visor === null ? null : (visibles.find((a) => a.id === visor) ?? null));

  const mensajeDe = (e: unknown) => (e instanceof Fallo ? e.message : esDeRed(e) ? SIN_CONEXION : mensajeDeError(e));

  // ─── Leer ──────────────────────────────────────────────────────────────────────────────────

  async function leer() {
    let nuevos: DatosBiblioteca;
    try {
      nuevos = await leerBiblioteca(sucursal.id);
    } catch (e) {
      // Con algo ya en pantalla se queda; la primera vez, la caja de error.
      if (!datos) errorLectura = esDeRed(e) ? SIN_CONEXION : mensajeDeError(e);
      return;
    }
    errorLectura = null;
    const nuevo = nuevos.anuncios.find((a) => a.estado === 'haciendo');
    // Si el que se hacía ya salió, entra con su efecto.
    if (desde && !nuevo && nuevos.anuncios.some((a) => a.id === desde!.id)) {
      const id = desde.id;
      recienListos = [...recienListos, id];
      setTimeout(() => (recienListos = recienListos.filter((x) => x !== id)), 1000);
    }
    desde = nuevo ? (desde?.id === nuevo.id ? desde : { id: nuevo.id, ms: Date.now() - nuevo.segundos * 1000 }) : null;
    datos = nuevos;
    // Uno que se borró (la socia, o los 30 días) mientras estaba abierto en grande.
    if (visor !== null && !nuevos.anuncios.some((a) => a.id === visor)) visor = null;
  }

  // ─── Lo que se toca ────────────────────────────────────────────────────────────────────────

  function elegirFiltro(f: 'todo' | Formato) {
    if (f === filtro) return;
    filtro = f;
    cuerpo?.scrollTo({ top: 0 });
  }

  async function descargar(id: number) {
    if (bajando !== null) return;
    bajando = id;
    errorAccion = null;
    errorPoner = null;
    try {
      await descargarAnuncio(id);
      bajado = id;
      setTimeout(() => {
        if (bajado === id) bajado = null;
      }, 1600);
    } catch (e) {
      const texto = mensajeDe(e);
      if (visor === id) errorPoner = { id, texto };
      else errorAccion = texto;
    } finally {
      bajando = null;
    }
  }

  async function poner(id: number) {
    if (poniendo !== null || puestos.includes(id)) return;
    poniendo = id;
    errorPoner = null;
    try {
      await ponerEnMiMenu(sucursal.id, id);
      puestos = [...puestos, id];
    } catch (e) {
      if (!(e instanceof Fallo)) console.error('[biblioteca] no se pudo poner el cartel en el menú:', e);
      errorPoner = { id, texto: mensajeDe(e) };
    } finally {
      poniendo = null;
    }
  }

  function mover(paso: 1 | -1) {
    if (visor === null || visibles.length < 2) return;
    const i = visibles.findIndex((a) => a.id === visor);
    visor = visibles[(i + paso + visibles.length) % visibles.length].id;
    if (errorPoner && errorPoner.id !== visor) errorPoner = null;
  }

  function abrir(id: number) {
    errorAccion = null;
    if (errorPoner && errorPoner.id !== id) errorPoner = null;
    visor = id;
  }

  function pedirEliminar(a: AnuncioListo) {
    errorAccion = null;
    confirmar = { anuncio: a, desdeVisor: visor === a.id, lugar: visibles.findIndex((x) => x.id === a.id) };
    visor = null;
  }

  // Cancelar desde la ventana grande la vuelve a abrir, como en Flet.
  function cancelarEliminar() {
    const c = confirmar;
    confirmar = null;
    if (c?.desdeVisor && visibles.some((a) => a.id === c.anuncio.id)) visor = c.anuncio.id;
  }

  async function siEliminar(): Promise<{ listo: string } | { error: string }> {
    if (!confirmar) return { error: 'Ese anuncio ya no está.' };
    try {
      await eliminarAnuncio(confirmar.anuncio.id);
      return { listo: 'Eliminado' };
    } catch (e) {
      return { error: mensajeDe(e) };
    }
  }

  // Ya se borró: sale de la lista y, si fue desde la ventana grande, se abre el que seguía. Su
  // lugar se guardó al pedirlo: el realtime de este mismo borrado suele llegar antes y ya lo sacó.
  function alEliminado() {
    const c = confirmar;
    confirmar = null;
    if (!c || !datos) return;
    datos = { ...datos, anuncios: datos.anuncios.filter((a) => a.id !== c.anuncio.id) };
    if (c.desdeVisor && visibles.length) visor = visibles[Math.min(Math.max(c.lugar, 0), visibles.length - 1)].id;
    leer();
  }

  function alTeclearPieza(e: KeyboardEvent, id: number) {
    if (e.target !== e.currentTarget || (e.key !== 'Enter' && e.key !== ' ')) return;
    e.preventDefault();
    abrir(id);
  }

  // Mientras uno se hace, se vuelve a leer cada 30 segundos: si se perdió el aviso de realtime, o
  // si el trabajo se cayó y Postgres lo suelta a los 15 minutos, igual se entera.
  $effect(() => {
    if (!haciendo) return;
    const cada = window.setInterval(leer, 30_000);
    return () => clearInterval(cada);
  });

  onMount(() => {
    leer();
    const dejar = escucharBiblioteca(sucursal.id, leer, (id) => !!datos?.anuncios.some((a) => a.id === id));
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  });
</script>

<BarraArriba
  titulo="Mi biblioteca"
  estado={datos
    ? { texto: cuantosAnuncios(listos.length), vivo: listos.length > 0, hueco: listos.length === 0 }
    : { texto: errorLectura ? 'No se pudo leer' : 'Leyendo…', vivo: false }}
>
  {#if listos.length || haciendo}
    <div class="filtro" role="group" aria-label="Qué ver">
      {#each [['todo', 'Todo'], ['post', 'Posts'], ['historia', 'Historias'], ['cartel', 'Carteles']] as const as [valor, texto] (valor)}
        <button type="button" aria-pressed={filtro === valor} onclick={() => elegirFiltro(valor)}>
          {texto}<span class="cuenta">{cuenta[valor]}</span>
        </button>
      {/each}
    </div>
  {/if}
  <Boton etiqueta="Crear anuncio" icono="ia" tono="tinta" onclick={() => alIr('crear')} />
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

{#if errorLectura && !datos}
  <main class="cuerpo-error"><CajaError mensaje={errorLectura} /></main>
{:else}
  <Tarjeta como="main" class="tarjeta-biblio">
    <div class="cuerpo-biblio" bind:this={cuerpo} bind:clientWidth={ancho}>
      {#if errorAccion}<CajaError mensaje={errorAccion} compacta />{/if}
      {#if datos && !listos.length && !haciendo}
        <div class="vacio">
          <div class="huecos">
            <span class="hueco" style:height="90px"></span>
            <span class="hueco" style:height="128px"><Icono nombre="biblio" tamano={22} /></span>
            <span class="hueco" style:height="90px"></span>
          </div>
          <h2>Todavía no hay anuncios</h2>
          <p>Cada anuncio que hagas en Crear anuncios se guarda aquí 30 días.</p>
          <div class="boton-primero">
            <Boton etiqueta="Crear mi primer anuncio" icono="ia" tono="tinta" onclick={() => alIr('crear')} />
          </div>
        </div>
      {:else if datos && !visibles.length && !haciendoVisible && filtro !== 'todo'}
        <div class="nota-filtro">
          <b>Todavía no hay {FORMA[filtro].plural}.</b>
          <span>Cambia a Todo para ver los demás.</span>
        </div>
      {:else}
        {#each dias as d (d.dia)}
          <div class="dia">
            <span class="etq fuerte">{d.cabecera[0]}</span>
            {#if d.cabecera[1]}<span class="etq">{d.cabecera[1]}</span>{/if}
            <span class="raya"></span>
            <span class="etq">{d.cuenta}</span>
          </div>
          <div class="collage">
            {#each d.cols as col, n (n)}
              <div class="columna">
                {#each col as a (a.id)}
                  {#if a.estado === 'haciendo'}
                    <div class="pieza haciendo" style:aspect-ratio={FORMA[a.formato].razon} aria-label="Haciendo tu anuncio">
                      <Cargador desde={desde?.id === a.id ? desde.ms : Date.now() - a.segundos * 1000} orilla={12} />
                    </div>
                  {:else}
                    <div
                      class="pieza"
                      class:aparece={recienListos.includes(a.id)}
                      role="button"
                      tabindex="0"
                      style:aspect-ratio={FORMA[a.formato].razon}
                      aria-label="{listaDe(a.productos)}, {FORMA[a.formato].corto.toLowerCase()}, {creado(a, datos?.hoy ?? '')}"
                      onclick={() => abrir(a.id)}
                      onkeydown={(e) => alTeclearPieza(e, a.id)}
                    >
                      <img src={urlFoto(a.ruta)} alt="" loading="lazy" />
                      <div class="capa">
                        <div class="capa-textos">
                          <b>{listaDe(a.productos)}</b>
                          <span>{FORMA[a.formato].corto} · {a.hora}</span>
                        </div>
                        <div class="capa-botones">
                          <button
                            type="button"
                            class="blanco"
                            title="Descargar"
                            aria-label="Descargar"
                            disabled={bajando === a.id}
                            onclick={(e) => {
                              e.stopPropagation();
                              descargar(a.id);
                            }}
                          >
                            {#if bajado === a.id}<span class="verde"><Icono nombre="check" tamano={16} /></span>{:else if bajando === a.id}<span
                                class="rueda-chica"
                              ></span>{:else}<Icono nombre="exportar" tamano={16} />{/if}
                          </button>
                          <button
                            type="button"
                            class="blanco"
                            title="Eliminar"
                            aria-label="Eliminar"
                            onclick={(e) => {
                              e.stopPropagation();
                              pedirEliminar(a);
                            }}><Icono nombre="eliminar" tamano={16} /></button
                          >
                        </div>
                      </div>
                      {#if a.dias_restantes <= 7}
                        <span class="vence"><Icono nombre="reloj" tamano={13} />{seBorra(a.dias_restantes)}</span>
                      {/if}
                    </div>
                  {/if}
                {/each}
              </div>
            {/each}
          </div>
        {/each}
      {/if}
    </div>
  </Tarjeta>
{/if}

{#if enGrande && datos}
  {@const a = enGrande}
  <Visor
    anuncio={a}
    posicion={visibles.indexOf(a) + 1}
    total={visibles.length}
    hoy={datos.hoy}
    bajando={bajando === a.id}
    bajado={bajado === a.id}
    poniendo={poniendo === a.id}
    puesto={puestos.includes(a.id)}
    error={errorPoner?.id === a.id ? errorPoner.texto : null}
    alMover={mover}
    alCerrar={() => (visor = null)}
    alDescargar={() => descargar(a.id)}
    alPoner={() => poner(a.id)}
    alEliminar={() => pedirEliminar(a)}
  />
{/if}

{#if confirmar}
  <Confirmar
    miniatura={{ src: urlFoto(confirmar.anuncio.ruta), alto: Math.round(72 * FORMA[confirmar.anuncio.formato].alto) }}
    titulo="¿Eliminar este anuncio?"
    texto="Se borra de tu biblioteca y no se puede deshacer. Si ya lo descargaste o lo pusiste en tu menú, eso se queda. No te regresa a tus anuncios del mes."
    boton={{ etiqueta: 'Eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={siEliminar}
    alCerrar={cancelarEliminar}
    alTerminar={alEliminado}
  />
{/if}

<style>
  .cuerpo-error {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
  }

  /* El filtro de la barra de arriba: Todo / Posts / Historias / Carteles, con cuántos de cada uno. */
  .filtro {
    display: flex;
    gap: 2px;
    padding: 4px;
    border-radius: 12px;
    background: var(--chip);
  }

  .filtro button {
    height: 32px;
    padding: 0 12px;
    border-radius: 9px;
    border: 0;
    background: transparent;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
    white-space: nowrap;
  }

  .filtro button[aria-pressed='true'] {
    background: var(--solido);
    color: var(--texto);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 10.5px;
    font-weight: 400;
    color: var(--tenue);
  }

  :global(.tarjeta-biblio) {
    position: absolute;
    left: var(--vista-izquierda);
    top: var(--vista-arriba);
    right: var(--vista-derecha);
    bottom: var(--vista-abajo);
    padding: 20px;
    display: flex;
  }

  .cuerpo-biblio {
    flex: 1;
    min-width: 0;
    min-height: 0;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 14px;
    scrollbar-width: thin;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .dia {
    flex: none;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 4px 4px 0;
  }

  .dia .fuerte {
    color: var(--texto);
  }

  .raya {
    flex: 1;
    height: 1px;
    background: var(--linea);
  }

  .collage {
    flex: none;
    display: flex;
    gap: 14px;
    align-items: flex-start;
  }

  .columna {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* Cada anuncio, sin marco, con su forma real. */
  .pieza {
    position: relative;
    border-radius: 14px;
    overflow: hidden;
    background: var(--chip);
    cursor: pointer;
    transition: box-shadow 150ms;
  }

  .pieza > img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .pieza:hover,
  .pieza:focus-visible {
    box-shadow: 0 14px 34px var(--sombra-anuncio);
  }

  .pieza:focus-visible {
    outline-offset: 3px;
  }

  .capa {
    position: absolute;
    inset: 0;
    opacity: 0;
    background: linear-gradient(to bottom, rgba(0, 0, 0, 0) 0%, rgba(0, 0, 0, 0) 45%, rgba(0, 0, 0, 0.65) 75%, rgba(0, 0, 0, 0.9) 100%);
    transition: opacity 150ms;
  }

  .pieza:hover .capa,
  .pieza:focus-visible .capa,
  .pieza:focus-within .capa {
    opacity: 1;
  }

  .capa-textos {
    position: absolute;
    left: 14px;
    right: 14px;
    bottom: 12px;
    display: flex;
    flex-direction: column;
    gap: 3px;
    color: #ffffff;
  }

  .capa-textos b {
    font-size: 14px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .capa-textos span {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.06em;
    color: rgba(255, 255, 255, 0.85);
  }

  .capa-botones {
    position: absolute;
    top: 10px;
    right: 10px;
    display: flex;
    gap: 6px;
  }

  /* Los cuadritos blancos sobre el anuncio: blancos en los dos temas, como en Flet. */
  .blanco {
    width: 36px;
    height: 36px;
    padding: 0;
    border: 0;
    border-radius: 11px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(255, 255, 255, 0.92);
    color: #0b0b0b;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.18);
  }

  .blanco:hover {
    background: #ffffff;
  }

  .verde {
    display: flex;
    color: var(--verde);
  }

  .rueda-chica {
    width: 14px;
    height: 14px;
    flex: none;
    border-radius: 50%;
    border: 2px solid rgba(0, 0, 0, 0.18);
    border-top-color: #0b0b0b;
    animation: girar 0.9s linear infinite;
  }

  @keyframes girar {
    to {
      transform: rotate(360deg);
    }
  }

  /* «Se borra en…» en la última semana: una pastilla de vidrio con su relojito. */
  .vence {
    position: absolute;
    z-index: 1;
    top: 10px;
    left: 10px;
    height: 26px;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 0 10px;
    border-radius: 14px;
    border: 1px solid var(--linea);
    background: var(--vidrio);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    box-shadow: 0 1px 3px var(--sombra-segmento);
    font-size: 11.5px;
    font-weight: 600;
    white-space: nowrap;
    color: var(--texto);
  }

  .vence :global(svg) {
    color: var(--suave);
  }

  /* El que se está haciendo: el marco de «Resultado» en chiquito. */
  .pieza.haciendo {
    cursor: default;
    background: var(--solido);
    border: 1px solid var(--linea);
    color: var(--texto);
  }

  .pieza.haciendo:hover {
    box-shadow: none;
  }

  /* Al terminar: de borroso a nítido, como en «Resultado». */
  .pieza.aparece {
    animation: aparecer 700ms cubic-bezier(0.23, 1, 0.32, 1) both;
  }

  @keyframes aparecer {
    from {
      opacity: 0;
      transform: scale(1.06);
      filter: blur(24px);
    }
  }

  /* Vacía y filtro sin nada. */
  .vacio {
    margin: auto;
    padding: 90px 40px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
  }

  .huecos {
    display: flex;
    align-items: flex-end;
    gap: 10px;
    margin-bottom: 10px;
  }

  .hueco {
    width: 72px;
    border-radius: 12px;
    border: 1.5px dashed var(--linea-fuerte);
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--suave);
  }

  .vacio h2 {
    margin: 0;
    font-size: 18px;
    font-weight: 800;
    letter-spacing: -0.3px;
  }

  .vacio p {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .boton-primero {
    margin-top: 8px;
  }

  .boton-primero :global(.boton) {
    height: 44px;
  }

  .nota-filtro {
    margin: 0 auto;
    padding: 80px 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    text-align: center;
  }

  .nota-filtro b {
    font-size: 14.5px;
    font-weight: 700;
  }

  .nota-filtro span {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  @media (prefers-reduced-motion: reduce) {
    .pieza,
    .capa {
      transition: none;
    }

    .pieza.aparece {
      animation: none;
    }
  }
</style>
