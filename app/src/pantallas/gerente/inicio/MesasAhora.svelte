<!--
  «Mesas ahora» de Inicio, tal cual Flet (home_view._pintar_mesas; maqueta Cortes y reportes
  7J6LvYWiktRnGxNugbuaoe): las ocupadas primero y después las libres, cada grupo en el orden del
  catálogo; cinco renglones y abajo cuántas más hay. Lo ocupado y el total salen de mesas_ahora
  (las cuentas abiertas, contadas por Postgres). Si no se pudo leer, lo dice: nunca un «Disponible»
  inventado.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Vidrio from '../../../diseno/Vidrio.svelte';
  import { dinero, plural } from '../../../lib/formato';
  import type { MesasAhora } from '../../../lib/reportes';

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; datos: MesasAhora } | { estado: 'error'; deRed: boolean };

  let { lectura, alAdministrar }: { lectura: Lectura; alAdministrar: () => void } = $props();

  // Como TOPE_MESAS de Flet: cinco renglones; el resto se cuenta abajo.
  const TOPE = 5;

  const vista = $derived.by(() => {
    if (lectura.estado !== 'listo') return null;
    const { mesas, ocupadas } = lectura.datos;
    const ordenadas = [...mesas.filter((m) => m.venta_id !== null), ...mesas.filter((m) => m.venta_id === null)];
    const visibles = ordenadas.slice(0, TOPE);
    const restantes = ordenadas.length - visibles.length;
    return {
      visibles,
      etiqueta: mesas.length ? `${ocupadas} DE ${mesas.length} OCUPADA${ocupadas === 1 ? '' : 'S'}` : '',
      mas: restantes ? `y ${plural(restantes, 'mesa más', 'mesas más')}` : '',
    };
  });
</script>

<Vidrio como="section" class="tarjeta-mesas-ahora" aria-label="Mesas ahora">
  <div class="fila-titulo">
    <span class="titulo-tarjeta">Mesas ahora</span>
    <span class="etiqueta">{lectura.estado === 'error' ? '—' : (vista?.etiqueta ?? '')}</span>
  </div>
  <div class="caja-solida">
    {#if lectura.estado === 'leyendo'}
      <p class="mensaje">Cargando tus mesas…</p>
    {:else if lectura.estado === 'error'}
      <p class="mensaje">
        {lectura.deRed ? 'No se pudieron leer tus mesas. Se vuelven a leer cuando regrese el internet.' : 'No se pudieron leer tus mesas.'}
      </p>
    {:else if vista && !vista.visibles.length}
      <p class="mensaje">Todavía no tienes mesas. Agrégalas en Mesas.</p>
    {:else if vista}
      {#each vista.visibles as m (m.id)}
        {@const libre = m.venta_id === null}
        <div class="mesa">
          <span class="marca" class:libre></span>
          <span class="nombre">{m.nombre}</span>
          <span class="estado" class:libre>{libre ? 'Disponible' : 'Ocupada'}</span>
          <span class="monto" class:libre>{libre || m.total === null ? '—' : dinero(m.total)}</span>
        </div>
      {/each}
    {/if}
  </div>
  <div class="pie">
    <span class="nota">{vista?.mas ?? ''}</span>
    <Boton etiqueta="Administrar mesas" icono="derecha" iconoAlFinal tamano="chico" onclick={alAdministrar} />
  </div>
</Vidrio>

<style>
  :global(.tarjeta-mesas-ahora) {
    width: 360px;
    flex: none;
    min-height: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .fila-titulo {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }

  .titulo-tarjeta {
    font-size: 14.5px;
    font-weight: 700;
  }

  .caja-solida {
    border-radius: 16px;
    border: 1px solid var(--linea);
    background: var(--solido);
    overflow: hidden;
  }

  .mensaje {
    margin: 0;
    padding: 14px;
    font-size: 13px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .mesa {
    height: 44px;
    padding: 0 14px;
    display: flex;
    align-items: center;
    gap: 10px;
    border-bottom: 1px solid var(--linea);
  }

  .mesa:last-child {
    border-bottom: 0;
  }

  .marca {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    background: var(--tinta);
  }

  .marca.libre {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }

  .nombre {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 600;
  }

  .estado {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .monto {
    width: 64px;
    text-align: right;
    font-family: var(--mono);
    font-size: 12.5px;
    font-variant-numeric: tabular-nums;
  }

  .estado.libre,
  .monto.libre {
    color: var(--tenue);
  }

  .pie {
    margin-top: auto;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .nota {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }
</style>
