<!--
  «Mesas ahora» de Inicio (maqueta V64Pv4gmANPRZuJW5hTe5D): las ocupadas primero, con su puntito verde, y
  después las libres, cada grupo en el orden del catálogo; seis renglones y abajo cuántas más hay. Lo
  ocupado y el total salen de mesas_ahora (las cuentas abiertas, contadas por Postgres). Si no se pudo
  leer, lo dice: nunca un «Disponible» inventado.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { pesos, plural } from '../../../lib/formato';
  import type { MesasAhora } from '../../../lib/reportes';

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; datos: MesasAhora } | { estado: 'error'; deRed: boolean };

  let { lectura, alAdministrar }: { lectura: Lectura; alAdministrar: () => void } = $props();

  const TOPE = 6;

  const vista = $derived.by(() => {
    if (lectura.estado !== 'listo') return null;
    const { mesas, ocupadas } = lectura.datos;
    const ordenadas = [...mesas.filter((m) => m.venta_id !== null), ...mesas.filter((m) => m.venta_id === null)];
    const visibles = ordenadas.slice(0, TOPE);
    const restantes = ordenadas.length - visibles.length;
    return {
      visibles,
      etiqueta: mesas.length ? `${ocupadas} de ${mesas.length} ocupada${ocupadas === 1 ? '' : 's'}` : '',
      mas: restantes ? `y ${plural(restantes, 'mesa más', 'mesas más')}` : '',
    };
  });
</script>

<section class="tarjeta" aria-label="Mesas ahora">
  <div class="cabeza">
    <b>Mesas ahora</b>
    <span class="etiqueta resumen">{lectura.estado === 'error' ? '—' : (vista?.etiqueta ?? '')}</span>
  </div>
  <div class="lista">
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
        <div class="mesa" class:libre>
          <span class="marca"></span>
          <span class="nombre">{m.nombre}</span>
          <span class="est">{libre ? 'Disponible' : 'Ocupada'}</span>
          <span class="monto">{libre || m.total === null ? '—' : pesos(m.total)}</span>
        </div>
      {/each}
    {/if}
  </div>
  <div class="pie">
    <span class="nota">{vista?.mas ?? ''}</span>
    <button type="button" class="boton-chico" onclick={alAdministrar}>Administrar mesas <Icono nombre="r-derecha" tamano={14} /></button>
  </div>
</section>

<style>
  .tarjeta {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 18px;
    background: var(--solido);
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
  }

  .cabeza {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
  }

  b {
    font-size: 15px;
    font-weight: 700;
  }

  .resumen {
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .mensaje {
    margin: 0;
    font-size: 13px;
    font-weight: 400;
    line-height: 1.45;
    color: var(--suave);
  }

  .mesa {
    height: 36px;
    display: grid;
    grid-template-columns: 10px minmax(0, 1fr) auto 96px;
    align-items: center;
    gap: 10px;
    border-bottom: 1px solid var(--linea);
    font-size: 13.5px;
    font-weight: 400;
  }

  .mesa:last-of-type {
    border-bottom: 0;
  }

  .marca {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--verde);
  }

  .mesa.libre .marca {
    background: var(--linea-fuerte);
  }

  .nombre {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .est {
    font-size: 12px;
    color: var(--suave);
  }

  .monto {
    text-align: right;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .mesa.libre .est,
  .mesa.libre .monto {
    font-weight: 400;
    color: var(--tenue);
  }

  .pie {
    margin-top: auto;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
  }

  .nota {
    font-size: 12px;
    font-weight: 400;
    color: var(--tenue);
  }

  .boton-chico {
    height: 30px;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 0 11px;
    border: 1px solid var(--linea);
    border-radius: 8px;
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
  }

  .boton-chico:hover {
    border-color: var(--linea-fuerte);
  }
</style>
