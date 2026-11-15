<!--
  Pedidos a lo ancho, desde unos 900 px (adaptabilidad, encuesta 15 «A, Tablero» y «Lo que decidí yo» 7 y 9; maqueta
  planes/maquetas/adaptabilidad.html, pantalla Pedidos): a la izquierda «POR CONFIRMAR · 2» y los pedidos completos, cada uno
  en su tarjeta de Crear anuncios, uno junto a otro; a la derecha una tarjeta de 400 con «Atendidos hoy», lo más nuevo
  arriba, que se desliza por dentro con su desvanecido. Sin barra de abajo. Lo que no dibuja la maqueta salió de las
  encuestas de planes/trabajo/adaptabilidad/pedidos-ancho.md: el aviso al centro sin pedidos, la línea sin atendidos y, en
  el panel, la nota gris junto a «POR CONFIRMAR» cuando no se reciben.

  Solo acomoda: lo que pasa al confirmar, rechazar o pausar sigue en caja/Pedidos.svelte. El esqueleto sale solo en el
  panel (`esqueleto`); el aparato sigue con su texto. Al llegar, la cascada de Mi menú; lo que llega después entra igual,
  uno por uno.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { cascada } from '../../../diseno/cascada';
  import { SIN_CONEXION } from '../../../lib/errores';
  import { anchos } from '../../../lib/esqueletos';
  import { pesos } from '../../../lib/formato';
  import type { PedidosDelDia, PorConfirmar } from '../../../lib/pedidos.svelte';
  import TarjetaPedido from './TarjetaPedido.svelte';

  let {
    datos,
    falloLectura,
    esqueleto = null,
    errores = [],
    nota = null,
    llego,
    hora,
    alConfirmar,
    alRechazar,
    alReintentar,
  }: {
    datos: PedidosDelDia | null;
    falloLectura: boolean; // la primera lectura no se pudo
    // En el panel, mientras llega la primera vez: cuántas tarjetas y renglones (los de la última vez).
    esqueleto?: { pedidos: number; atendidos: number } | null;
    errores?: (string | null)[];
    nota?: string | null;
    llego: (p: PorConfirmar) => string;
    hora: (momento: string) => string;
    alConfirmar: (p: PorConfirmar) => void;
    alRechazar: (p: PorConfirmar) => void;
    alReintentar: () => void;
  } = $props();

  const pila = (nombre: string | null) => (nombre ?? '').trim().split(/\s+/)[0];

  // ─── La cascada: al llegar, lo que se ve entra uno tras otro (diseno/cascada.ts); lo que llega después, igual. ───
  let raiz = $state<HTMLElement>();
  let yaEntro = false;
  const vistos = new Set<string>();
  $effect(() => {
    if (!datos || !raiz) return;
    const claves = [...datos.por_confirmar.map((p) => `p${p.id}`), ...datos.atendidos.map((a) => `a${a.id}`)];
    const nuevas = claves.filter((c) => !vistos.has(c));
    for (const c of nuevas) vistos.add(c);
    const primera = !yaEntro;
    yaEntro = true;
    if (!nuevas.length) return;
    const r = raiz;
    tick().then(() => {
      // Dos pasadas, una por columna: cascada() se detiene en la primera que ya no se ve, y las tarjetas de abajo no
      // deben dejar sin cascada a los atendidos de arriba a la derecha.
      const de = (clase: string) =>
        primera ? `.${clase}` : nuevas.map((c) => `.${clase}[data-entra="${c}"]`).join(', ') || `.${clase}.ninguna`;
      cascada(r, de('celda'));
      cascada(r, de('atendido'));
    });
  });

  // ─── Lo de la derecha se desliza solo si no cabe, con su desvanecido (como las ventanas). ───
  let lado = $state<HTMLElement>();
  let masArriba = $state(false);
  let masAbajo = $state(false);
  function sombras() {
    if (!lado) return;
    const desborda = lado.scrollHeight > lado.clientHeight + 1;
    masArriba = desborda && lado.scrollTop > 1;
    masAbajo = desborda && lado.scrollTop + lado.clientHeight < lado.scrollHeight - 1;
  }
  $effect(() => {
    if (!lado) return;
    const l = lado;
    const ro = new ResizeObserver(sombras);
    const observar = () => {
      ro.disconnect();
      ro.observe(l);
      for (const h of l.children) ro.observe(h);
      sombras();
    };
    const mo = new MutationObserver(observar);
    mo.observe(l, { childList: true, subtree: true });
    observar();
    return () => {
      ro.disconnect();
      mo.disconnect();
    };
  });
</script>

<div class="tablero" bind:this={raiz}>
  <div class="izq">
    <div class="por-confirmar">
      <span class="etiqueta">
        POR CONFIRMAR{#if datos}&nbsp;·&nbsp;{datos.por_confirmar.length}{:else if esqueleto}&nbsp;·&nbsp;<Esqueleto ancho="14px" alto="10px" redondo="4px" />{/if}
      </span>
      {#if nota && datos}<span class="nota">{nota}</span>{/if}
    </div>
    {#each errores as e, i (i)}
      {#if e}<CajaError mensaje={e} />{/if}
    {/each}

    <div class="rejilla-scroll">
      {#if datos}
        {#if datos.por_confirmar.length}
          <div class="rejilla">
            {#each datos.por_confirmar as p (p.id)}
              <div class="celda" data-entra="p{p.id}">
                <TarjetaPedido pedido={p} llego={llego(p)} alRechazar={() => alRechazar(p)} alConfirmar={() => alConfirmar(p)} />
              </div>
            {/each}
          </div>
        {:else}
          <div class="sin-pedidos">
            <span class="cuadrito"><Icono nombre="r-bolsa" tamano={18} /></span>
            <b>Sin pedidos por confirmar</b>
            <span>Los pedidos de tu menú en línea llegan aquí, con un tono.</span>
          </div>
        {/if}
      {:else if falloLectura}
        <div class="fallo">
          <CajaError mensaje={SIN_CONEXION} />
          <Boton etiqueta="Intentar de nuevo" icono="actualizar" onclick={alReintentar} />
        </div>
      {:else if esqueleto}
        <span class="solo-lector" role="status">Cargando los pedidos…</span>
        <div class="rejilla" aria-hidden="true">
          {#each anchos([['134px', '164px'], ['116px', '150px'], ['148px', '138px']], esqueleto.pedidos) as [titulo, sub], i (i)}
            <TarjetaPedido pedido={null} forma={{ titulo, sub, renglones: i % 2 ? 2 : 3 }} />
          {/each}
        </div>
      {:else}
        <div class="sin-pedidos"><span>Abriendo los pedidos…</span></div>
      {/if}
    </div>
  </div>

  <aside class="der">
    <section class="tarjeta lado" aria-label="Atendidos hoy">
      <div class="lado-scroll" class:mas-arriba={masArriba} class:mas-abajo={masAbajo} bind:this={lado} onscroll={sombras}>
        {#if !datos && esqueleto}
          <div class="encabezado" aria-hidden="true">
            <Esqueleto ancho="36px" alto="36px" redondo="11px" />
            <div class="titulos">
              <span class="titulo"><Esqueleto ancho="132px" alto="14px" /></span>
              <span class="sub"><Esqueleto ancho="124px" alto="11px" /></span>
            </div>
          </div>
          <div class="lista" aria-hidden="true">
            {#each anchos([['32px', '152px'], ['30px', '198px'], ['40px', '150px']], esqueleto.atendidos) as [nombre, linea], i (i)}
              <div class="atendido">
                <Esqueleto ancho="42px" alto="26px" redondo="8px" />
                <span class="t">
                  <b><Esqueleto ancho={nombre} alto="12px" /></b>
                  <span><Esqueleto ancho={linea} alto="10px" /></span>
                </span>
                <span class="m"><Esqueleto ancho="54px" alto="12px" /></span>
              </div>
            {/each}
          </div>
        {:else}
          <div class="encabezado">
            <span class="cuadrito"><Icono nombre="check-delgado" tamano={18} /></span>
            <div class="titulos">
              <span class="titulo">Atendidos hoy{#if datos}&nbsp;·&nbsp;{datos.atendidos.length}{/if}</span>
              <span class="sub">Lo más nuevo, arriba.</span>
            </div>
          </div>
          {#if datos}
            {#if datos.atendidos.length}
              <div class="lista">
                {#each datos.atendidos as a (a.id)}
                  {@const rechazado = a.estado === 'rechazado'}
                  <div class="atendido" class:rechazado data-entra="a{a.id}">
                    <span class="num">#{a.numero}</span>
                    <span class="t">
                      <b>{a.cliente_nombre}</b>
                      {#if rechazado}
                        <span class="motivo" title={a.rechazo_motivo ?? undefined}>Rechazado · {a.rechazo_motivo}</span>
                      {:else}
                        <span>Confirmado{a.atendido_por ? ` · ${pila(a.atendido_por)}` : ''} · {hora(a.atendido_at)}</span>
                      {/if}
                    </span>
                    <span class="m">{pesos(a.total)}</span>
                  </div>
                {/each}
              </div>
            {:else}
              <p class="sin">Aquí salen los que confirmes o rechaces.</p>
            {/if}
          {/if}
        {/if}
      </div>
    </section>
  </aside>
</div>

<style>
  /* Dos columnas, como el paso 2 de Crear anuncios: lo de la izquierda y una tarjeta de 400 del alto de la pantalla. */
  .tablero {
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-columns: minmax(0, 1fr) 400px;
    gap: 24px;
  }

  .izq {
    min-width: 0;
    min-height: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .por-confirmar {
    min-height: 20px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 0 2px;
  }

  .etiqueta {
    display: inline-flex;
    align-items: center;
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    white-space: nowrap;
  }

  /* No se reciben (panel): lo que ven los clientes, en gris. */
  .nota {
    min-width: 0;
    font-size: 12px;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rejilla-scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    margin: 0 -6px;
    padding: 2px 6px 12px;
    scrollbar-width: none;
  }

  .rejilla-scroll::-webkit-scrollbar {
    display: none;
  }

  .rejilla {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(330px, 1fr));
    gap: 14px;
    /* Parejas por fila (el developer, 14 nov 2026): cada tarjeta mide lo que la más alta de su fila, y sus botones quedan
       abajo, alineados (TarjetaPedido, .aviso-wa). */
    align-items: stretch;
  }

  .celda {
    min-width: 0;
    display: flex;
  }

  /* Sin pedidos (encuesta 1): al centro del lado izquierdo, con la bolsa en su cuadrito. */
  .sin-pedidos {
    min-height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 40px 16px 60px;
    text-align: center;
  }

  .sin-pedidos .cuadrito {
    margin-bottom: 6px;
  }

  .sin-pedidos b {
    font-size: 14.5px;
    font-weight: 700;
  }

  .sin-pedidos > span:not(.cuadrito) {
    font-size: 12.5px;
    color: var(--suave);
    line-height: 1.45;
    max-width: 34ch;
  }

  .fallo {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }

  .der {
    min-height: 0;
    height: 100%;
  }

  /* La tarjeta de Crear anuncios, del alto de la columna; lo de adentro se desliza. */
  .tarjeta {
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
  }

  .lado {
    height: 100%;
    overflow: hidden;
    position: relative;
  }

  .lado-scroll {
    height: 100%;
    overflow-y: auto;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 18px;
    scrollbar-width: none;
  }

  .lado-scroll::-webkit-scrollbar {
    display: none;
  }

  .lado-scroll.mas-abajo {
    -webkit-mask-image: linear-gradient(to top, transparent 0, #000 32px);
    mask-image: linear-gradient(to top, transparent 0, #000 32px);
  }

  .lado-scroll.mas-arriba {
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 32px);
    mask-image: linear-gradient(to bottom, transparent 0, #000 32px);
  }

  .lado-scroll.mas-arriba.mas-abajo {
    -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 32px, #000 calc(100% - 32px), transparent 100%);
    mask-image: linear-gradient(to bottom, transparent 0, #000 32px, #000 calc(100% - 32px), transparent 100%);
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: none;
  }

  .cuadrito {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .sub {
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .sin {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
  }

  .lista {
    display: flex;
    flex-direction: column;
  }

  .atendido {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 2px;
  }

  .atendido + .atendido {
    border-top: 1px solid var(--tabla-linea, var(--linea));
  }

  /* El número en verde (confirmado) o en rojo (rechazado). */
  .num {
    min-width: 42px;
    height: 26px;
    padding: 0 8px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 8px;
    font-family: var(--mono);
    font-size: 12.5px;
    font-weight: 600;
    background: color-mix(in srgb, var(--verde) 14%, transparent);
    color: var(--verde);
  }

  .rechazado .num {
    background: color-mix(in srgb, var(--rojo) 11%, transparent);
    color: var(--rojo);
  }

  .atendido .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .atendido .t b {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .atendido .t span {
    font-size: 12px;
    color: var(--tenue);
  }

  /* El motivo es libre («Otro motivo»): a lo más dos renglones. */
  .atendido .t .motivo {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .atendido .m {
    flex: none;
    font-family: var(--mono);
    font-size: 13px;
    font-variant-numeric: tabular-nums;
  }

  .rechazado .m {
    text-decoration: line-through;
    color: var(--tenue);
  }
</style>
