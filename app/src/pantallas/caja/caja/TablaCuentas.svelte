<!--
  La izquierda de la Caja a lo ancho (adaptabilidad 3c; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, pantalla «Caja»; encuesta 16):
  la búsqueda en píldora de Mi menú con el filtro Por cobrar · Cobradas · Todas y su conteo, y la tabla en el marco de Mi
  menú (Cuenta · Cómo · Abrió · Total, filas de 64). La cuenta que se cobra queda en gris (aria-pressed). Mientras se lee
  la primera vez, las filas de la última vez en esqueleto; al llegar, entran en cascada (diseno/cascada.ts). Al buscar o
  filtrar, quietas.
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
  import type { VigiaTerminal } from '../../../lib/terminal.svelte';
  import type { FilaCaja, FiltroCaja } from './filas';

  let {
    filas,
    busqueda = $bindable(''),
    filtroElegido,
    cuentas,
    cargando,
    filasEsqueleto,
    elegida,
    vacio,
    alFiltro,
    alElegir,
    terminal = null,
  }: {
    filas: FilaCaja[]; // ya filtradas y buscadas
    busqueda?: string;
    filtroElegido: FiltroCaja;
    cuentas: { porcobrar: number; cobradas: number }; // para el filtro
    cargando: boolean;
    filasEsqueleto: number;
    elegida: string | null; // la clave de la fila que se cobra o se ve
    vacio: { titulo: string; texto: string };
    alFiltro: (f: FiltroCaja) => void;
    alElegir: (f: FilaCaja) => void;
    terminal?: VigiaTerminal | null; // «En la terminal · $489.50» en la cuenta cuyo cobro espera
  } = $props();

  // La cascada, solo la primera vez que llegan las cuentas.
  let lugar = $state<HTMLDivElement>();
  let yaEntraron = false;
  $effect(() => {
    if (cargando || yaEntraron) return;
    yaEntraron = true;
    tick().then(() => cascada(lugar, '.cuerpo > .fila'));
  });

  const ANCHOS = ['132px', '96px', '150px', '110px', '124px', '88px'];
</script>

<div class="izq">
  <Herramientas
    bind:busqueda
    placeholder="Busca una cuenta por número o nombre…"
    aria="Buscar cuentas"
    conteo={plural(filas.length, 'CUENTA', 'CUENTAS')}
    {cargando}
  >
    {#snippet filtro()}
      <Filtro
        titulo="CUENTAS"
        todas="Por cobrar"
        opciones={[
          { valor: 'porcobrar', nombre: 'Por cobrar', cuenta: cuentas.porcobrar, icono: 'reloj' },
          { valor: 'cobradas', nombre: 'Cobradas', cuenta: cuentas.cobradas, icono: 'check-delgado' },
          { valor: 'todas', nombre: 'Todas', cuenta: cuentas.porcobrar + cuentas.cobradas, icono: 'cuenta' },
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
      encabezados={[{ texto: 'Cuenta' }, { texto: 'Cómo' }, { texto: 'Abrió' }, { texto: 'Total', derecha: true }]}
    >
      {#if cargando}
        <!-- El esqueleto: con su forma y sin sus botones. -->
        <span class="solo-lector">Cargando las cuentas…</span>
        {#each anchos(ANCHOS, filasEsqueleto) as ancho, i (i)}
          <div class="fila quieta" aria-hidden="true">
            <span class="cel-cuenta"><Esqueleto ancho="36px" alto="36px" redondo="11px" /><Esqueleto {ancho} alto="12px" /></span>
            <span><Esqueleto ancho="70px" alto="10px" /></span>
            <span><Esqueleto ancho="84px" alto="10px" /></span>
            <span class="derecha"><Esqueleto ancho="56px" alto="11px" /></span>
          </div>
        {/each}
      {:else if !filas.length}
        <NotaTabla relleno={48} angosta titulo={vacio.titulo} texto={vacio.texto} />
      {:else}
        {#each filas as f (f.clave)}
          {@const t = f.cobrada ? null : (terminal?.marca(f.id) ?? null)}
          <button type="button" class="fila fila-cuenta" class:cobrada={f.cobrada} aria-pressed={elegida === f.clave} onclick={() => alElegir(f)}>
            <span class="cel-cuenta">
              <span class="ico-c"><Icono nombre={f.icono} tamano={16} /></span>
              <span class="celda fuerte">{f.titulo}</span>
              {#if f.whatsapp}<span class="wa">WhatsApp</span>{/if}
              {#if t}
                <span class="marca-e t-marca {t.tipo}">{t.tipo === 'terminal' ? 'En la terminal' : t.tipo === 'revisa' ? 'Revisa la terminal' : 'No se cobró'}</span>
              {:else if f.marca}<span class="marca-e" class:cuenta={f.marca === 'Pidió la cuenta'} class:reabierta={f.marca === 'Reabierta'}>{f.marca}</span>{/if}
            </span>
            <span class="celda">{f.como}</span>
            <span class="celda tenue">{f.abrio}</span>
            <span class="celda numero">
              {pesos(t && t.tipo !== 'no-cobro' ? t.monto : f.total)}{#if f.cobrada}<span class="hecha" aria-label="cobrada"> ✓</span>{/if}
              {#if f.falta !== null}<small>Falta {pesos(f.falta)}</small>{/if}
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

  .fila-cuenta {
    width: 100%;
    border-top: 0;
    border-left: 0;
    border-right: 0;
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  .fila-cuenta:focus-visible {
    outline: none;
    box-shadow: inset 0 0 0 2px var(--campo-aro);
  }

  .cel-cuenta {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cel-cuenta .celda {
    flex: 0 1 auto;
  }

  .cel-cuenta .wa,
  .cel-cuenta .marca-e {
    align-self: center;
  }

  .celda.numero small {
    display: block;
    margin-top: 2px;
    font-size: 11px;
    color: var(--tenue);
  }

  .hecha {
    color: var(--verde);
  }

  .derecha {
    display: flex;
    justify-content: flex-end;
  }
</style>
