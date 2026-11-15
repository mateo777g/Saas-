<!--
  La izquierda de Cortes y reportes (14 nov 2026), copia de la de la Caja a lo ancho (caja/caja/TablaCuentas.svelte):
  la búsqueda en píldora de Mi menú con el filtro Todo el día · Turnos · Descuentos · Cancelaciones · Otros cambios y su
  conteo, y la tabla en el marco de Mi menú (Qué · Tipo · Quién · Monto, filas de 64). Primero los turnos del día con su
  sello (Cuadra en verde, Faltan en rojo, Abierta) y luego lo que pasó en sus cuentas, por hora. El renglón que se ve a
  la derecha queda en gris (aria-pressed). Mientras se lee, las filas de la última vez en esqueleto; al llegar (la
  primera vez y al cambiar de día), entran en cascada (diseno/cascada.ts). Al buscar, filtrar o releer, quietas.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { cascada } from '../../../diseno/cascada';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import NotaTabla from '../../../diseno/NotaTabla.svelte';
  import Tabla from '../../../diseno/Tabla.svelte';
  import { anchos } from '../../../lib/esqueletos';
  import { pesos, plural } from '../../../lib/formato';
  import Filtro from '../../pos/ancho/Filtro.svelte';
  import Herramientas from '../../pos/ancho/Herramientas.svelte';
  import type { FilaCortes, FiltroCortes } from './filas';

  let {
    filas,
    busqueda = $bindable(''),
    filtroElegido,
    cuantos,
    cargando,
    filasEsqueleto,
    elegida,
    vacio,
    alFiltro,
    alElegir,
  }: {
    filas: FilaCortes[]; // ya filtradas y buscadas
    busqueda?: string;
    filtroElegido: FiltroCortes;
    cuantos: Record<FiltroCortes, number>; // para el filtro
    cargando: boolean;
    filasEsqueleto: number;
    elegida: string | null; // la clave del renglón que se ve a la derecha
    vacio: { titulo: string; texto: string };
    alFiltro: (f: FiltroCortes) => void;
    alElegir: (f: FilaCortes) => void;
  } = $props();

  // La cascada, cada vez que llega un día (la primera vez y al cambiar de día); al releer el mismo, quietas.
  let lugar = $state<HTMLDivElement>();
  let antes = true;
  $effect(() => {
    const ahora = cargando;
    if (antes && !ahora) tick().then(() => cascada(lugar, '.cuerpo > .fila'));
    antes = ahora;
  });

  const ANCHOS = ['150px', '118px', '176px', '132px', '104px', '140px'];
</script>

<div class="izq">
  <Herramientas
    bind:busqueda
    placeholder="Busca por mesa, folio, producto o persona…"
    aria="Buscar en este día"
    conteo={plural(filas.length, 'REGISTRO', 'REGISTROS')}
    {cargando}
  >
    {#snippet filtro()}
      <Filtro
        titulo="EN ESTE DÍA"
        todas="Todo el día"
        opciones={[
          { valor: 'todo', nombre: 'Todo el día', cuenta: cuantos.todo, icono: 'tabla' },
          { valor: 'turnos', nombre: 'Turnos', cuenta: cuantos.turnos, icono: 'corte' },
          { valor: 'descuentos', nombre: 'Descuentos', cuenta: cuantos.descuentos, icono: 'porcentaje' },
          { valor: 'cancelaciones', nombre: 'Cancelaciones', cuenta: cuantos.cancelaciones, icono: 'eliminar' },
          { valor: 'otros', nombre: 'Otros cambios', cuenta: cuantos.otros, icono: 'cambiar' },
        ]}
        elegida={filtroElegido}
        alElegir={alFiltro}
      />
    {/snippet}
  </Herramientas>

  <div class="tabla-lugar" bind:this={lugar}>
    <Tabla
      marco
      columnas="1.6fr 1fr 1fr 0.8fr"
      relleno="0 16px"
      altoFila={64}
      encabezados={[{ texto: 'Qué' }, { texto: 'Tipo' }, { texto: 'Quién' }, { texto: 'Monto', derecha: true }]}
    >
      {#if cargando}
        <!-- El esqueleto: con su forma y sin sus botones. -->
        <span class="solo-lector">Cargando este día…</span>
        {#each anchos(ANCHOS, filasEsqueleto) as ancho, i (i)}
          <div class="fila quieta" aria-hidden="true">
            <span class="cel-que"><Esqueleto ancho="36px" alto="36px" redondo="11px" /><Esqueleto {ancho} alto="12px" /></span>
            <span><Esqueleto ancho="84px" alto="10px" /></span>
            <span><Esqueleto ancho="92px" alto="10px" /></span>
            <span class="derecha"><Esqueleto ancho="64px" alto="11px" /></span>
          </div>
        {/each}
      {:else if !filas.length}
        <NotaTabla relleno={48} angosta titulo={vacio.titulo} texto={vacio.texto} />
      {:else}
        {#each filas as f (f.clave)}
          <button type="button" class="fila fila-dia" aria-pressed={elegida === f.clave} onclick={() => alElegir(f)}>
            <span class="cel-que">
              <span class="ico-c"><Icono nombre={f.icono} tamano={16} /></span>
              <span class="textos">
                <span class="celda fuerte">{f.titulo}</span>
                {#if f.sub}<small>{f.sub}</small>{/if}
              </span>
            </span>
            <span class="celda">{f.tipo}</span>
            <span class="textos">
              <span class="celda tenue">{f.quien || '—'}</span>
              {#if f.autorizo}<small>{f.autorizo}</small>{/if}
            </span>
            <span class="celda numero">
              {#if f.que === 'turno'}
                {#if f.sello.clase === 'abierta'}
                  <span class="sello abierta"><span class="punto-v"></span>{f.sello.texto}</span>
                {:else}
                  <span class="sello {f.sello.clase}">{f.sello.texto}{#if f.sello.clase === 'cuadra'} ✓{/if}</span>
                {/if}
              {:else if f.que === 'descuento'}
                <span class="descontado">−{pesos(f.descuento.descuento)}</span>
              {:else if f.que === 'cancelacion'}
                <span class="tachado">{pesos(f.cancelacion.importe)}</span>
              {:else}
                <span class="nada">—</span>
              {/if}
            </span>
          </button>
        {/each}
      {/if}
    </Tabla>
  </div>
</div>

<style>
  .tabla-lugar {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }

  .fila-dia {
    width: 100%;
    border-top: 0;
    border-left: 0;
    border-right: 0;
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  .fila-dia:focus-visible {
    outline: none;
    box-shadow: inset 0 0 0 2px var(--campo-aro);
  }

  .cel-que {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .textos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .textos small {
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .derecha {
    display: flex;
    justify-content: flex-end;
  }

  /* El sello del turno, con el color que dice algo: verde si cuadra, rojo si falta. */
  .sello {
    font-family: var(--jakarta);
    font-size: 12.5px;
    font-weight: 600;
  }

  .sello.cuadra {
    color: var(--verde);
  }

  .sello.falta {
    color: var(--rojo);
  }

  .sello.sobra {
    color: var(--texto);
  }

  .sello.abierta {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    color: var(--texto);
  }

  .descontado {
    color: var(--verde);
  }

  .tachado {
    color: var(--tenue);
    text-decoration: line-through;
  }

  .nada {
    color: var(--tenue);
  }
</style>
