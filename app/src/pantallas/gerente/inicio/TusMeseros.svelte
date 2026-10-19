<!--
  «Tus meseros» de Inicio (maqueta de Inicio 5SVLK2avzLCq5TaW6mrqq6; decidido el 18 de octubre de
  2026, maqueta Cortes y reportes 7J6LvYWiktRnGxNugbuaoe): los meseros activos, aunque hoy vayan en
  $0, y cualquiera que hoy abrió cuentas, como Lupita o el gerente; debajo de cada nombre, su rol.
  Mesas son las cuentas que trae abiertas ahora (con los para llevar); Ventas y Vendido, las
  cerradas de hoy. Todo lo cuenta tus_meseros; aquí solo se pinta, en el orden que dio Postgres.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Vidrio from '../../../diseno/Vidrio.svelte';
  import { dinero, plural } from '../../../lib/formato';
  import type { TusMeseros } from '../../../lib/reportes';
  import { NOMBRE_ROL } from '../../../lib/roles';

  type Lectura = { estado: 'leyendo' } | { estado: 'listo'; datos: TusMeseros } | { estado: 'error'; deRed: boolean };

  let { lectura, alVerEmpleados }: { lectura: Lectura; alVerEmpleados: () => void } = $props();

  // «3 meseros · 1 en caja · 1 en cocina»: lo que no hay no se dice.
  const equipo = $derived.by(() => {
    if (lectura.estado !== 'listo') return '';
    const { meseros, caja, cocina } = lectura.datos.equipo;
    return [
      meseros ? plural(meseros, 'mesero', 'meseros') : '',
      caja ? `${caja} en caja` : '',
      cocina ? `${cocina} en cocina` : '',
    ].filter(Boolean).join(' · ').toUpperCase();
  });

  const ORDEN_ROLES = ['gerente', 'mesero', 'caja', 'cocina'];
  const rol = (roles: string[]) =>
    [...roles].sort((a, b) => ORDEN_ROLES.indexOf(a) - ORDEN_ROLES.indexOf(b)).map((r) => NOMBRE_ROL[r] ?? r).join(' · ');
</script>

<Vidrio como="section" class="tarjeta-meseros" aria-label="Tus meseros">
  <div class="fila-titulo">
    <div>
      <span class="titulo-tarjeta">Tus meseros</span>
      <span class="nota">Las mesas y las ventas de hoy de cada uno.</span>
    </div>
    <span class="etiqueta resumen">{equipo}</span>
  </div>

  <div class="tabla">
    <div class="fila cabecera">
      <span class="etiqueta">MESERO</span>
      <span class="etiqueta derecha">MESAS</span>
      <span class="etiqueta derecha">VENTAS</span>
      <span class="etiqueta derecha">VENDIDO</span>
    </div>
    <div class="cuerpo">
      {#if lectura.estado === 'leyendo'}
        <p class="mensaje">Cargando tu equipo…</p>
      {:else if lectura.estado === 'error'}
        <p class="mensaje">No se pudieron leer las ventas de hoy.</p>
      {:else if !lectura.datos.personas.length}
        <p class="mensaje">Todavía no tienes meseros. Dalos de alta en Empleados.</p>
      {:else}
        {#each lectura.datos.personas as p (p.miembro_id)}
          <div class="fila">
            <span class="persona">
              <span class="inicial">{p.nombre.charAt(0).toUpperCase()}</span>
              <span class="nombres">
                <span class="nombre">{p.nombre}</span>
                <span class="rol">{rol(p.roles)}</span>
              </span>
            </span>
            <span class="celda" class:cero={!p.abiertas}>{p.abiertas}</span>
            <span class="celda" class:cero={!p.ventas}>{p.ventas}</span>
            <span class="celda numero" class:cero={!p.vendido}>{dinero(p.vendido)}</span>
          </div>
        {/each}
      {/if}
    </div>
  </div>

  <div>
    <Boton etiqueta="Ver empleados" icono="derecha" iconoAlFinal tamano="chico" onclick={alVerEmpleados} />
  </div>
</Vidrio>

<style>
  :global(.tarjeta-meseros) {
    flex: 1;
    min-width: 0;
    min-height: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .fila-titulo {
    flex: none;
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 16px;
  }

  .fila-titulo > div {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .titulo-tarjeta {
    font-size: 14.5px;
    font-weight: 700;
  }

  .nota {
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .resumen {
    white-space: nowrap;
  }

  .tabla {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
    overflow: hidden;
  }

  .cuerpo {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }

  .fila {
    display: grid;
    grid-template-columns: 2fr 1fr 1fr 1.1fr;
    gap: 16px;
    align-items: center;
    padding: 9px 16px;
    border-bottom: 1px solid var(--linea);
  }

  .cuerpo .fila:last-child {
    border-bottom: 0;
  }

  .fila.cabecera {
    flex: none;
    height: 40px;
    padding-block: 0;
  }

  .derecha {
    text-align: right;
  }

  .mensaje {
    margin: 0;
    padding: 14px;
    font-size: 13px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .persona {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .inicial {
    width: 30px;
    height: 30px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 15px;
    background: var(--chip);
    border: 1px solid var(--linea);
    font-size: 12px;
    font-weight: 700;
  }

  .nombres {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .nombre {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .rol {
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--tenue);
  }

  .celda {
    text-align: right;
    white-space: nowrap;
    font-size: 12.5px;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
    color: var(--suave);
  }

  .celda.numero {
    font-family: var(--mono);
    font-size: 13px;
    color: var(--texto);
  }

  .celda.cero {
    color: var(--tenue);
  }
</style>
