<!--
  «Accesos para tu equipo» en Inicio (maqueta Mesero y cocina, estado «Inicio»; libreta 4, decidido
  el 17 de octubre de 2026). Desde la pieza 5 van en 2 × 2 junto a Tus meseros, como en la maqueta de
  Inicio (maqueta Cortes y reportes 7J6LvYWiktRnGxNugbuaoe). Punto de venta y Cocina llevan «Abrir», que las abre dentro del panel
  con la sesión del gerente; Caja y Menú digital dicen «Llega pronto» hasta que existan. El equipo
  entra desde sus aparatos, que se ligan en Empleados.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';

  let { alAbrir }: { alAbrir: (que: 'pos' | 'caja' | 'cocina') => void } = $props();

  const ACCESOS: { icono: string; titulo: string; texto: string; abre?: 'pos' | 'caja' | 'cocina'; pronto?: string }[] = [
    { icono: 'mesas', titulo: 'Punto de venta', texto: 'Toma pedidos de las mesas y para llevar, y mándalos a cocina.', abre: 'pos' },
    { icono: 'billete', titulo: 'Caja', texto: 'Cobra las cuentas y hace el corte del día.', abre: 'caja' },
    { icono: 'cocina', titulo: 'Cocina', texto: 'Las comandas llegan en orden a la pantalla.', abre: 'cocina' },
    { icono: 'celular', titulo: 'Menú digital', texto: 'Tu menú en línea para tus clientes.', pronto: 'Llega con el menú en línea' },
  ];
</script>

<Vidrio como="section" class="tarjeta-accesos" aria-label="Accesos para tu equipo">
  <div>
    <span class="titulo-tarjeta">Accesos para tu equipo</span>
    <p class="nota-chica">Ábrelos aquí. Tu equipo entra desde sus aparatos, que ligas en Empleados.</p>
  </div>
  <div class="rejilla-accesos">
    {#each ACCESOS as a (a.titulo)}
      <div class="acceso">
        <div class="acceso-cabeza">
          <span class="cuadro-icono"><Icono nombre={a.icono} tamano={18} /></span>
          <div class="t">
            <span class="acceso-titulo">{a.titulo}</span>
            <p class="acceso-texto">{a.texto}</p>
          </div>
        </div>
        <div>
          {#if a.abre}
            {@const abre = a.abre}
            <button type="button" class="boton-chico" onclick={() => alAbrir(abre)}><Icono nombre="afuera" tamano={14} />Abrir</button>
          {:else}
            <span class="acceso-pronto">{a.pronto}</span>
          {/if}
        </div>
      </div>
    {/each}
  </div>
</Vidrio>

<style>
  :global(.tarjeta-accesos) {
    flex: 1;
    min-width: 0;
    min-height: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .titulo-tarjeta {
    font-size: 14.5px;
    font-weight: 700;
  }

  .nota-chica {
    margin: 4px 0 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    line-height: 1.45;
  }

  .rejilla-accesos {
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-columns: 1fr 1fr;
    grid-template-rows: 1fr 1fr;
    gap: 12px;
  }

  .acceso {
    min-width: 0;
    padding: 16px;
    border-radius: 18px;
    background: var(--solido);
    border: 1px solid var(--linea);
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    gap: 12px;
  }

  .acceso-cabeza {
    display: flex;
    gap: 12px;
    align-items: flex-start;
  }

  .acceso-cabeza .t {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .acceso-titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .acceso-texto {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .acceso-pronto {
    font-size: 12px;
    color: var(--tenue);
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  .boton-chico {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    padding: 0 11px;
    border-radius: 11px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton-chico:hover {
    opacity: 0.86;
  }

  @media (prefers-reduced-motion: reduce) {
    .boton-chico {
      transition: none;
    }
  }
</style>
