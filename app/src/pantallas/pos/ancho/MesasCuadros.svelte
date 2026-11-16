<!--
  Las mesas a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, «Mesas» de Don Chuy): la búsqueda en píldora y
  el filtro «Todas las mesas» (Todas · Ocupadas · Libres) con su conteo, y las mesas en los cuadros de Crear anuncios sin
  foto: las ocupadas con su punto verde, su total y quién la abrió; lo que pasa («En cocina», «Lista», «Pidió la
  cuenta») a la derecha de su nombre, como en el celular. Una libre con algo anotado aquí lo dice. Con `encima`, un
  texto arriba (al cambiar o juntar mesas: «¿A qué mesa pasa?»). Con `cargando` (las mesas de la última vez), mientras
  se lee la primera vez, sus cuadros en bloques grises que laten (regla «Los esqueletos»; maqueta «Mesas» cargando).
-->
<script lang="ts">
  import type { VigiaTerminal } from '../../../lib/terminal.svelte';
  import { tick, type Snippet } from 'svelte';
  import { cascada } from '../../../diseno/cascada';
  import { faltaDe } from '../../../lib/caja';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import { pesos, plural } from '../../../lib/formato';
  import type { Mesa, Venta } from '../../../lib/pos';
  import { sinAcentos } from './buscar';
  import Filtro from './Filtro.svelte';
  import Herramientas from './Herramientas.svelte';

  type Estado = 'reabierta' | 'cocina' | 'lista' | 'cuenta' | 'ocupada';
  const MARCA: Partial<Record<Estado, string>> = { cocina: 'En cocina', lista: 'Lista', cuenta: 'Pidió la cuenta' };

  let {
    mesas,
    deMesa,
    anotadas,
    estadoDe,
    quien,
    hora,
    apagadas = false,
    cargando = 0,
    encima,
    alAbrir,
    terminal = null,
  }: {
    mesas: Mesa[];
    deMesa: Map<number, Venta>; // la cuenta abierta de cada mesa
    anotadas: Set<number>;
    estadoDe: (v: Venta) => Estado;
    quien: (v: Venta) => string;
    hora: (v: Venta) => string;
    apagadas?: boolean; // mientras se cambia o se junta: no se toca dos veces
    cargando?: number; // cuántas mesas había la última vez, mientras se lee la primera vez (0 = ya se leyó)
    encima?: Snippet;
    alAbrir: (m: Mesa) => void;
    terminal?: VigiaTerminal | null; // la terminal de la sucursal: la mesa cuyo cobro espera lo dice
  } = $props();

  let busqueda = $state('');
  let filtroMesas = $state<'todas' | 'ocupadas' | 'libres'>('todas');
  let rejilla = $state<HTMLDivElement>();

  const ocupadas = $derived(mesas.filter((m) => deMesa.has(m.id)).length);
  const opciones = $derived([
    { valor: 'todas' as const, nombre: 'Todas', cuenta: mesas.length, icono: 'r-mesas' },
    { valor: 'ocupadas' as const, nombre: 'Ocupadas', cuenta: ocupadas, icono: 'reloj' },
    { valor: 'libres' as const, nombre: 'Libres', cuenta: mesas.length - ocupadas, icono: 'check-delgado' },
  ]);
  const vistas = $derived.by(() => {
    const q = sinAcentos(busqueda);
    return mesas.filter(
      (m) =>
        (filtroMesas === 'todas' || deMesa.has(m.id) === (filtroMesas === 'ocupadas')) && (!q || sinAcentos(m.nombre).includes(q)),
    );
  });

  $effect(() => {
    if (!rejilla || cargando) return;
    tick().then(() => cascada(rejilla, '.prod'));
  });
</script>

<div class="uno">
  <Herramientas
    bind:busqueda
    placeholder="Busca una mesa…"
    aria="Buscar mesas"
    conteo={plural(vistas.length, 'MESA', 'MESAS')}
    cargando={cargando > 0}
  >
    {#snippet filtro()}
      <Filtro titulo="MESAS" todas="Todas las mesas" {opciones} elegida={filtroMesas} alElegir={(v) => (filtroMesas = v)} />
    {/snippet}
  </Herramientas>
  {@render encima?.()}

  <div class="rejilla-scroll">
    {#if cargando}
      <span class="solo-lector" role="status">Cargando tus mesas…</span>
      <div class="rejilla" aria-hidden="true">
        {#each Array(Math.min(cargando, 24)) as _, i (i)}
          <div class="prod mesa-t">
            <span class="mesa-nom"><Esqueleto ancho={i % 3 === 1 ? '78px' : '52px'} alto="18px" /></span>
            {#if i % 3 === 0}
              <span class="mesa-abajo"><Esqueleto ancho="30px" alto="13px" /></span>
            {:else}
              <span class="mesa-abajo"><Esqueleto ancho="88px" alto="20px" /><Esqueleto ancho="100px" alto="12px" /></span>
            {/if}
          </div>
        {/each}
      </div>
    {:else if vistas.length === 0}
      <div class="sin-coincide">
        <b>{mesas.length ? 'Ninguna mesa así' : 'No hay mesas'}</b>{mesas.length ? 'Prueba con otro nombre o con otro filtro.' : ''}
      </div>
    {:else}
      <div class="rejilla" bind:this={rejilla}>
        {#each vistas as m (m.id)}
          {@const v = deMesa.get(m.id)}
          {@const t = v ? (terminal?.marca(v.id) ?? null) : null}
          <button type="button" class="prod mesa-t" class:libre={!v} disabled={apagadas} onclick={() => alAbrir(m)}>
            <span class="mesa-nom">
              {#if v}<span class="punto-v"></span>{/if}<span class="nom">{m.nombre}</span>
              {#if t}
                <span class="marca-e t-marca {t.tipo}">{t.tipo === 'terminal' ? 'En la terminal' : t.tipo === 'revisa' ? 'Revisa la terminal' : 'No se cobró'}</span>
              {:else if v && MARCA[estadoDe(v)]}<span class="marca-e {estadoDe(v)}">{MARCA[estadoDe(v)]}</span>{/if}
            </span>
            {#if v}
              <span class="mesa-abajo">
                <b>{pesos(t && t.tipo !== 'no-cobro' ? t.monto : v.total)}</b>
                <span>{v.pagado > 0 ? `Falta ${pesos(faltaDe(v))} · ` : ''}Abrió {quien(v)} · {hora(v)}</span>
              </span>
            {:else}
              <span class="mesa-abajo"><span>Libre{anotadas.has(m.id) ? ' · anotado aquí' : ''}</span></span>
            {/if}
          </button>
        {/each}
      </div>
    {/if}
  </div>
</div>
