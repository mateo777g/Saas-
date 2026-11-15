<!--
  La Cocina a lo ancho (rediseño, 14 nov 2026; planes/trabajo/rediseno/cocina.md): la estructura del Tablero de Pedidos
  (caja/pedidos/Tablero.svelte; maqueta planes/maquetas/adaptabilidad.html, pantalla Pedidos). A la izquierda «POR
  PREPARAR · 3» y las comandas de esta área, de la más vieja a la más nueva, cada una en su tarjeta (TarjetaComanda), una
  junto a otra; a la derecha una tarjeta con «Últimas listas», lo más nuevo arriba, que se desliza por dentro con su
  desvanecido. Más angosto, la tarjeta de la derecha se angosta y, en un celular, baja debajo de las comandas.

  Solo acomoda: marcar «Lista», regresarla, el tono y lo que se lee siguen en Cocina.svelte. Al llegar, la cascada de Mi
  menú; lo que llega después entra igual, solo eso; al cambiar de área, otra vez todo. Lo que se marca «Lista» se va
  más rápido de lo que llega, y las demás se recorren a su lugar.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { flip } from 'svelte/animate';
  import { scale } from 'svelte/transition';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { cascada } from '../../diseno/cascada';
  import { SIN_CONEXION } from '../../lib/errores';
  import { anchos } from '../../lib/esqueletos';
  import type { Tarjeta } from '../../lib/pos';
  import TarjetaComanda from './TarjetaComanda.svelte';

  let {
    clave,
    comandas,
    listas,
    falloLectura = false,
    esqueleto = null,
    error = null,
    subDe,
    minutos,
    hora,
    lineaLista,
    alMarcar,
    alRegresar,
    alReintentar,
  }: {
    clave: string | number; // el área: al cambiarla, la cascada vuelve a entrar toda
    comandas: Tarjeta[] | null; // las pendientes de esta área; null mientras llega la primera vez
    listas: Tarjeta[] | null;
    falloLectura?: boolean; // la primera lectura no se pudo
    esqueleto?: { comandas: number; listas: number } | null;
    error?: string | null;
    subDe: (t: Tarjeta) => string;
    minutos: (t: Tarjeta) => number;
    hora: (momento: string) => string;
    lineaLista: (t: Tarjeta) => string; // «Domicilio · Pepe»: la de la tarjeta, sin la hora (la hora va en verde)
    alMarcar: (t: Tarjeta) => void;
    alRegresar: (t: Tarjeta) => void;
    alReintentar: () => void;
  } = $props();

  const quieto = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
  const tiempo = (ms: number) => (quieto?.matches ? 0 : ms);

  // «Últimas listas»: lo cancelado del mismo producto va junto («2 Taco de pastor»), cada uno con su motivo (4c).
  function textoCancelados(t: Tarjeta): string {
    const cuantos = new Map<string, number>();
    for (const r of t.renglones) {
      if (r.estado === 'cancelado') cuantos.set(r.nombre, (cuantos.get(r.nombre) ?? 0) + r.cantidad);
    }
    return [...cuantos].map(([nombre, n]) => `${n} ${nombre}`).join(', ');
  }

  // ─── La cascada: al llegar, lo que se ve entra uno tras otro (diseno/cascada.ts); lo que llega después, igual. ───
  let raiz = $state<HTMLElement>();
  let yaEntro = false;
  let vistos = new Set<string>();
  let claveVista: string | number | null = null;
  $effect(() => {
    if (!comandas || !listas || !raiz) return;
    if (clave !== claveVista) {
      claveVista = clave;
      yaEntro = false;
      vistos = new Set();
    }
    const claves = [...comandas.map((c) => `c${c.id}`), ...listas.map((l) => `l${l.id}`)];
    const nuevas = claves.filter((c) => !vistos.has(c));
    for (const c of nuevas) vistos.add(c);
    const primera = !yaEntro;
    yaEntro = true;
    if (!nuevas.length) return;
    const r = raiz;
    tick().then(() => {
      // Dos pasadas, una por columna, como en Pedidos: las tarjetas de abajo no dejan sin cascada a las listas.
      const de = (clase: string) =>
        primera ? `.${clase}` : nuevas.map((c) => `.${clase}[data-entra="${c}"]`).join(', ') || `.${clase}.ninguna`;
      cascada(r, de('celda'));
      cascada(r, de('lista-fila'));
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
    <div class="por-preparar">
      <span class="etiqueta">
        POR PREPARAR{#if comandas}&nbsp;·&nbsp;{comandas.length}{:else if esqueleto}&nbsp;·&nbsp;<Esqueleto ancho="14px" alto="10px" redondo="4px" />{/if}
      </span>
    </div>
    {#if error}<CajaError mensaje={error} />{/if}

    <div class="rejilla-scroll">
      {#if comandas}
        {#if comandas.length}
          <div class="rejilla">
            {#each comandas as t (t.id)}
              <div class="celda" data-entra="c{t.id}" animate:flip={{ duration: tiempo(300) }} out:scale={{ duration: tiempo(180), start: 0.94 }}>
                <TarjetaComanda comanda={t} sub={subDe(t)} minutos={minutos(t)} alTocar={() => alMarcar(t)} />
              </div>
            {/each}
          </div>
        {:else}
          <div class="sin-comandas">
            <span class="cuadrito"><Icono nombre="r-cocina" tamano={18} /></span>
            <b>Sin comandas pendientes</b>
            <span>Las nuevas llegan solas, al momento.</span>
          </div>
        {/if}
      {:else if falloLectura}
        <div class="fallo">
          <CajaError mensaje={SIN_CONEXION} />
          <Boton etiqueta="Intentar de nuevo" icono="actualizar" onclick={alReintentar} />
        </div>
      {:else if esqueleto}
        <span class="solo-lector" role="status">Cargando las comandas…</span>
        <div class="rejilla" aria-hidden="true">
          {#each anchos([['96px', '120px'], ['128px', '150px'], ['84px', '104px']], esqueleto.comandas) as [titulo, sub], i (i)}
            <TarjetaComanda comanda={null} forma={{ titulo, sub, renglones: i % 2 ? 2 : 3 }} />
          {/each}
        </div>
      {/if}
    </div>
  </div>

  <aside class="der">
    <section class="tarjeta lado" aria-label="Últimas listas">
      <div class="lado-scroll" class:mas-arriba={masArriba} class:mas-abajo={masAbajo} bind:this={lado} onscroll={sombras}>
        {#if !listas && esqueleto}
          <div class="encabezado" aria-hidden="true">
            <Esqueleto ancho="36px" alto="36px" redondo="11px" />
            <div class="titulos">
              <span class="titulo"><Esqueleto ancho="124px" alto="14px" /></span>
              <span class="sub"><Esqueleto ancho="200px" alto="11px" /></span>
            </div>
          </div>
          <div class="lista" aria-hidden="true">
            {#each anchos([['70px', '48px'], ['92px', '64px'], ['58px', '40px']], esqueleto.listas) as [nombre, linea], i (i)}
              <div class="lista-fila">
                <Esqueleto ancho="54px" alto="26px" redondo="8px" />
                <span class="t">
                  <b><Esqueleto ancho={nombre} alto="12px" /></b>
                  <span><Esqueleto ancho={linea} alto="10px" /></span>
                </span>
                <Esqueleto ancho="104px" alto="34px" redondo="12px" />
              </div>
            {/each}
          </div>
        {:else}
          <div class="encabezado">
            <span class="cuadrito"><Icono nombre="check-delgado" tamano={18} /></span>
            <div class="titulos">
              <span class="titulo">Últimas listas{#if listas}&nbsp;·&nbsp;{listas.length}{/if}</span>
              <span class="sub">Las 10 más recientes de hoy. Regresar la devuelve a la pantalla.</span>
            </div>
          </div>
          {#if listas}
            {#if listas.length}
              <div class="lista">
                {#each listas as t (t.id)}
                  {@const cancelados = t.renglones.filter((r) => r.estado === 'cancelado')}
                  {@const toda = cancelados.length > 0 && cancelados.length === t.renglones.length}
                  <div class="lista-fila" class:toda data-entra="l{t.id}">
                    <span class="hora">{hora(t.lista_at ?? t.created_at)}</span>
                    <span class="t">
                      <b>{t.titulo}</b>
                      <span>{lineaLista(t)}</span>
                      {#if cancelados.length}<span class="cancel-l">Cancelado: {textoCancelados(t)}</span>{/if}
                    </span>
                    <Boton etiqueta="Regresar" icono="regresar" tamano="chico" onclick={() => alRegresar(t)} />
                  </div>
                {/each}
              </div>
            {:else}
              <p class="sin">Nada marcado todavía.</p>
            {/if}
          {/if}
        {/if}
      </div>
    </section>
  </aside>
</div>

<style>
  /* Dos columnas, como Pedidos a lo ancho: lo de la izquierda y una tarjeta de 400 del alto de la pantalla. */
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

  .por-preparar {
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

  /* Un poco más angostas que las de Pedidos: en la cocina caben más a la vista. */
  .rejilla {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 14px;
    /* Parejas por fila (el developer, 14 nov 2026): cada comanda mide lo que la más alta de su fila, y «Toca cuando salga
       todo» queda abajo, alineado (TarjetaComanda, .pista). */
    align-items: stretch;
  }

  .celda {
    min-width: 0;
    display: flex;
  }

  /* Sin comandas: al centro del lado izquierdo, con su ícono en su cuadrito, como «Sin pedidos por confirmar». */
  .sin-comandas {
    min-height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 40px 16px 60px;
    text-align: center;
  }

  .sin-comandas .cuadrito {
    margin-bottom: 6px;
  }

  .sin-comandas b {
    font-size: 14.5px;
    font-weight: 700;
  }

  .sin-comandas > span:not(.cuadrito) {
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

  .solo-lector {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
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

  .lista-fila {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 2px;
  }

  .lista-fila + .lista-fila {
    border-top: 1px solid var(--tabla-linea, var(--linea));
  }

  /* La hora en que quedó lista, en verde, como el número de los atendidos de Pedidos; en rojo si se canceló toda. */
  .hora {
    min-width: 54px;
    height: 26px;
    padding: 0 8px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 8px;
    font-family: var(--mono);
    font-size: 12.5px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    background: color-mix(in srgb, var(--verde) 14%, transparent);
    color: var(--verde);
  }

  .toda .hora {
    background: color-mix(in srgb, var(--rojo) 11%, transparent);
    color: var(--rojo);
  }

  .lista-fila .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .lista-fila .t b {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .toda .t b {
    text-decoration: line-through;
    color: var(--tenue);
  }

  .lista-fila .t span {
    font-size: 12px;
    color: var(--tenue);
  }

  .lista-fila .t .cancel-l {
    font-weight: 600;
    color: var(--rojo);
  }

  /* Más angosto (una tableta parada): la tarjeta de la derecha se angosta. */
  @container cocina (max-width: 1000px) {
    .tablero {
      grid-template-columns: minmax(0, 1fr) 320px;
    }
  }

  /* En un celular: una sola columna que se desliza entera, y «Últimas listas» debajo de las comandas. */
  @container cocina (max-width: 680px) {
    .tablero {
      display: flex;
      flex-direction: column;
      overflow-y: auto;
      scrollbar-width: none;
    }

    .izq,
    .rejilla-scroll {
      flex: none;
      overflow: visible;
    }

    .der,
    .lado,
    .lado-scroll {
      height: auto;
    }

    .rejilla {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
