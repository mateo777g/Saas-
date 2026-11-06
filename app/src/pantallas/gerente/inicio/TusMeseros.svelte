<!--
  «Tus meseros» de Inicio (maqueta V64Pv4gmANPRZuJW5hTe5D; decidido el 18 de octubre de 2026): los meseros
  activos, aunque hoy vayan en $0, y cualquiera que hoy abrió cuentas, como Lupita o el gerente; debajo de
  cada nombre, su rol. Mesas son las cuentas que trae abiertas ahora (con los para llevar); Ventas y
  Vendido, las cerradas de hoy. Todo lo cuenta tus_meseros; aquí solo se pinta, en el orden que dio Postgres.
-->
<script lang="ts">
  import TablaDeslizable from '../../../diseno/TablaDeslizable.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { pesos, plural } from '../../../lib/formato';
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
    ].filter(Boolean).join(' · ');
  });

  const ORDEN_ROLES = ['gerente', 'mesero', 'caja', 'cocina'];
  const rol = (roles: string[]) =>
    [...roles].sort((a, b) => ORDEN_ROLES.indexOf(a) - ORDEN_ROLES.indexOf(b)).map((r) => NOMBRE_ROL[r] ?? r).join(' · ');
</script>

<section class="tarjeta" aria-label="Tus meseros">
  <div class="cabeza">
    <div>
      <b>Tus meseros</b>
      <span class="nota">Las mesas y las ventas de hoy de cada uno.</span>
    </div>
    <span class="etiqueta resumen">{equipo}</span>
  </div>

  {#if lectura.estado === 'leyendo'}
    <p class="mensaje">Cargando tu equipo…</p>
  {:else if lectura.estado === 'error'}
    <p class="mensaje">No se pudieron leer las ventas de hoy.</p>
  {:else if !lectura.datos.personas.length}
    <p class="mensaje">Todavía no tienes meseros. Dalos de alta en Empleados.</p>
  {:else}
    <TablaDeslizable>
      <table>
        <thead>
          <tr>
            <th class="etiqueta">Mesero</th>
            <th class="etiqueta der">Mesas</th>
            <th class="etiqueta der">Ventas</th>
            <th class="etiqueta der">Vendido</th>
          </tr>
        </thead>
        <tbody>
          {#each lectura.datos.personas as p (p.miembro_id)}
            <tr>
              <td>
                <span class="persona">
                  <span class="inicial">{p.nombre.charAt(0).toUpperCase()}</span>
                  <span><span class="nombre" title={p.nombre}>{p.nombre}</span><span class="rol">{rol(p.roles)}</span></span>
                </span>
              </td>
              <td class="der" class:cero={!p.abiertas}>{p.abiertas}</td>
              <td class="der" class:cero={!p.ventas}>{p.ventas}</td>
              <td class="der" class:cero={!p.vendido}>{pesos(p.vendido)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </TablaDeslizable>
  {/if}

  <div class="pie">
    <button type="button" class="boton-chico" onclick={alVerEmpleados}>Ver empleados <Icono nombre="r-derecha" tamano={14} /></button>
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
    display: block;
    font-size: 15px;
    font-weight: 700;
  }

  /* Su renglón mide lo de la letra de 16 px de la maqueta, aunque la nota sea más chica. */
  .cabeza > div {
    font-size: 16px;
  }

  .nota {
    font-size: 12.5px;
    font-weight: 400;
    color: var(--suave);
  }

  .resumen {
    letter-spacing: 0.08em;
    text-transform: uppercase;
    white-space: nowrap;
  }

  .mensaje {
    margin: 0;
    font-size: 13px;
    font-weight: 400;
    line-height: 1.45;
    color: var(--suave);
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13.5px;
    font-weight: 400;
  }

  th {
    padding: 0 0 8px;
    text-align: left;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  td {
    padding: 9px 0;
    border-top: 1px solid var(--linea);
    font-variant-numeric: tabular-nums;
  }

  th.der,
  td.der {
    text-align: right;
  }

  td.cero {
    color: var(--tenue);
  }

  .persona {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .inicial {
    width: 28px;
    height: 28px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--chip);
    font-size: 12px;
    font-weight: 700;
  }

  /* En un renglón y con «…». Aquí hay más lugar que en «Tus distribuidores». */
  .nombre {
    display: block;
    max-width: 260px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .rol {
    display: block;
    font-size: 11.5px;
    color: var(--tenue);
  }

  .pie {
    margin-top: auto;
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
