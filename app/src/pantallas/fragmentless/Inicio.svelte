<!--
  Inicio de Fragmentless (rediseño del 5 de noviembre de 2026; maqueta 4Ryyf9E7u4vsDs57PdkAnz): el mismo del
  gerente, para que quepa lo que venga (barberías y lo demás). Arriba, el saludo con la fecha y «I'm CEO,
  B*tch.»; debajo, la búsqueda grande (Ctrl K), Abrir · Atajos · Recientes y, al bajar, el Resumen: las
  estadísticas, Tus distribuidores (panel_distribuidores) y Vencen pronto (las filas de panel_clientes que
  vencieron o vencen en los próximos 7 días), con Sumar meses.

  La fecha y la hora las da Postgres, nunca el reloj del aparato. Sin distribuidores, la tarjeta dice «Da de
  alta el primero en Distribuidores.» (decidido el 12 de octubre de 2026).
-->
<script lang="ts">
  import TablaDeslizable from '../../diseno/TablaDeslizable.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Buscador, { type RenglonBusqueda } from '../../diseno/Buscador.svelte';
  import Columnas, { type ItemColumna } from '../../diseno/Columnas.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { diaConNombre, fecha, saludoPorHora, vigencia } from '../../lib/formato';
  import { urgente, type Cliente, type DatosPanel } from '../../lib/panel';
  import { ACCIONES, leerRecientes, MI_NOMBRE, VISTAS, type DestinoPanel, type VistaPanel } from '../../lib/vistasFragmentless';
  import Estadisticas from './inicio/Estadisticas.svelte';

  let {
    datos,
    tomarBusqueda,
    alIr,
    alSumar,
  }: {
    datos: DatosPanel | null;
    // Si pidieron la búsqueda (Ctrl K o la búsqueda chica); se toma una vez.
    tomarBusqueda: () => boolean;
    alIr: (destino: DestinoPanel) => void;
    alSumar: (cliente: Cliente) => void;
  } = $props();

  let busqueda = $state('');
  let buscador = $state<{ enfocar: () => void } | null>(null);

  $effect(() => {
    if (buscador && tomarBusqueda()) buscador.enfocar();
  });

  const recientes = leerRecientes();

  const deVista = (v: VistaPanel): RenglonBusqueda => ({
    clave: v,
    texto: VISTAS[v].texto,
    icono: VISTAS[v].icono,
    alPicar: () => alIr({ vista: v }),
  });
  const acciones: RenglonBusqueda[] = ACCIONES.map((a) => ({
    clave: a.texto,
    texto: a.texto,
    de: a.de,
    icono: a.icono,
    alPicar: () => alIr(a.destino),
  }));
  const vistas = (Object.keys(VISTAS) as VistaPanel[]).map(deVista);

  const abrir: ItemColumna[] = (['clientes', 'distribuidores', 'estilos'] as const).map(deVista);
  const atajos: ItemColumna[] = acciones.map((a) => ({ ...a, de: undefined }));
  const deRecientes: ItemColumna[] = recientes.map((v) => ({ ...deVista(v), icono: 'r-reloj' }));

  const estadisticas = $derived(datos?.estadisticas.ok ? datos.estadisticas.datos : null);
  const hora = $derived(estadisticas?.hora ?? null);
  // Como en el Agente IA: el saludo y la fecha en una sola línea. Sin esa lectura, sin hora ni fecha.
  const linea = $derived.by(() => {
    if (!datos) return '';
    if (!estadisticas) return `Hola, ${MI_NOMBRE}`;
    const dia = diaConNombre(estadisticas.hoy);
    const saludo = saludoPorHora(Number(estadisticas.hora.slice(0, 2)));
    return `${saludo}, ${MI_NOMBRE} · ${dia.charAt(0).toLowerCase()}${dia.slice(1)}`;
  });

  // Vencen pronto: lo que Postgres marcó como vencida o vence_pronto (los pausados no).
  const pronto = $derived(
    datos?.clientes.ok
      ? datos.clientes.datos.filter((c) => c.estado === 'vencida' || c.estado === 'vence_pronto')
      : [],
  );

  const distribuidores = $derived.by(() => {
    if (!datos?.distribuidores.ok) return [];
    const q = busqueda.trim().toLowerCase();
    return datos.distribuidores.datos.filter(
      (d) => !q || d.nombre.toLowerCase().includes(q) || (d.correo ?? '').toLowerCase().includes(q),
    );
  });
</script>

<main class="vista">
  <div class="inicio">
    <div class="saludo">
      <span class="etiqueta linea">{linea}</span>
      <h1>I'm CEO, B*tch.</h1>
    </div>

    <Buscador bind:this={buscador} {vistas} {acciones} recientes={recientes.map(deVista)} />
    <Columnas {abrir} {atajos} recientes={deRecientes} />

    <div class="resumen-titulo">
      <h2>Resumen</h2>
      {#if hora}<span class="hora">Actualizado {hora}</span>{/if}
    </div>
    <Estadisticas {datos} />

    <div class="fila">
      <section class="tarjeta" aria-label="Tus distribuidores">
        <div class="cabeza">
          <div>
            <b>Tus distribuidores</b>
            <span class="nota">Quienes venden Fragmentless en persona y cuántos clientes tiene cada uno.</span>
          </div>
          <label class="buscar">
            <Icono nombre="r-buscar" tamano={18} />
            <input type="search" placeholder="Buscar distribuidor" aria-label="Buscar distribuidor" autocomplete="off" bind:value={busqueda} />
          </label>
        </div>

        {#if !datos}
          <!-- leyendo la primera vez -->
        {:else if !datos.distribuidores.ok}
          <p class="mensaje">No se pudieron leer tus distribuidores. {datos.distribuidores.mensaje}</p>
        {:else if datos.distribuidores.datos.length === 0}
          <p class="mensaje">Todavía no hay distribuidores. Da de alta el primero en Distribuidores.</p>
        {:else if distribuidores.length === 0}
          <p class="mensaje">Ningún distribuidor se llama así. Prueba con otro nombre o correo.</p>
        {:else}
          <TablaDeslizable>
            <table>
              <thead>
                <tr>
                  <th class="etiqueta">Nombre</th>
                  <th class="etiqueta">Estado</th>
                  <th class="etiqueta">Correo</th>
                  <th class="etiqueta">Teléfono</th>
                  <th class="etiqueta der">Clientes</th>
                </tr>
              </thead>
              <tbody>
                {#each distribuidores as d (d.id)}
                  <tr class:apagado={!d.activo}>
                    <td><span class="persona"><span class="inicial">{d.nombre.charAt(0)}</span><span class="nombre" title={d.nombre}>{d.nombre}</span></span></td>
                    <td><span class="estado"><i class:si={d.activo}></i>{d.activo ? 'Activo' : 'De baja'}</span></td>
                    <td class="correo" title={d.correo ?? undefined}>{d.correo ?? '—'}</td>
                    <td class="telefono">{d.telefono ?? '—'}</td>
                    <td class="der">{d.clientes}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </TablaDeslizable>
        {/if}

        <div class="pie">
          <button type="button" class="boton-chico" onclick={() => alIr({ vista: 'distribuidores' })}>Ver distribuidores <Icono nombre="r-derecha" tamano={14} /></button>
        </div>
      </section>

      <section class="tarjeta" aria-label="Vencen pronto">
        <div class="cabeza">
          <div>
            <b>Vencen pronto</b>
            <span class="nota">Vencieron o vencen en los próximos 7 días.</span>
          </div>
        </div>

        <div>
          {#if !datos}
            <!-- leyendo la primera vez -->
          {:else if !datos.clientes.ok}
            <p class="mensaje">No se pudo cargar.</p>
          {:else if pronto.length === 0}
            <p class="mensaje">Nada por revisar esta semana.</p>
          {:else}
            {#each pronto as c (c.id)}
              <div class="por-vencer">
                <div class="por-vencer-texto">
                  <b>{c.nombre}</b>
                  <span>{#if urgente(c)}<em>{vigencia(c.dias_restantes)}</em>{:else}{vigencia(c.dias_restantes)}{/if} · {fecha(c.licencia_fin)}</span>
                </div>
                <BotonCuadro icono="calendario-mas" ayuda="Sumar meses" etiqueta="Sumar meses a {c.nombre}" onclick={() => alSumar(c)} />
              </div>
            {/each}
          {/if}
        </div>

        <div class="pie">
          <button type="button" class="boton-chico" onclick={() => alIr({ vista: 'clientes' })}>Ver clientes <Icono nombre="r-derecha" tamano={14} /></button>
        </div>
      </section>
    </div>
  </div>
</main>

<style>
  .vista {
    position: absolute;
    left: 0;
    right: 0;
    top: 56px;
    bottom: 0;
    overflow-y: auto;
  }

  .inicio {
    max-width: 1060px;
    margin: 0 auto;
    padding: 52px 32px 56px;
    display: flex;
    flex-direction: column;
  }

  .saludo {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
  }

  /* En la letra de la fecha del gerente (decidido el 6 de noviembre de 2026). */
  .linea {
    min-height: 14px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  h1 {
    margin: 0;
    font-size: 40px;
    font-weight: 800;
    line-height: 1.08;
    letter-spacing: -1px;
    text-wrap: balance;
  }

  .hora {
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 400;
    color: var(--tenue);
    white-space: nowrap;
  }

  .resumen-titulo {
    display: flex;
    align-items: baseline;
    gap: 12px;
    margin: 56px 0 14px;
  }

  h2 {
    margin: 0;
    font-size: 18px;
    font-weight: 700;
  }

  .fila {
    display: grid;
    grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
    gap: 12px;
    margin-top: 12px;
  }

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

  .cabeza > div {
    min-width: 0;
    font-size: 14px;
  }

  .cabeza b {
    display: block;
    font-size: 15px;
    font-weight: 700;
  }

  .nota {
    font-size: 12.5px;
    font-weight: 400;
    color: var(--suave);
  }

  .buscar {
    flex: 0 0 190px;
    height: 36px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 12px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 10px;
    color: var(--suave);
  }

  .buscar:focus-within {
    border-color: var(--linea-fuerte);
  }

  .buscar input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 400;
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

  /* Con datos largos, las columnas no se pegan. */
  th:not(:last-child),
  td:not(:last-child) {
    padding-right: 12px;
  }

  .correo {
    max-width: 170px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .telefono {
    white-space: nowrap;
  }

  /* En un renglón y con «…», como el correo. */
  .nombre {
    max-width: 110px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  tr.apagado td {
    color: var(--suave);
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

  .estado {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    white-space: nowrap;
  }

  .estado i {
    width: 8px;
    height: 8px;
    box-sizing: border-box;
    border-radius: 50%;
    border: 1.5px solid var(--tenue);
  }

  .estado i.si {
    background: var(--verde);
    border-color: var(--verde);
  }

  .por-vencer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 11px 0;
    border-bottom: 1px solid var(--linea);
  }

  .por-vencer:first-child {
    border-top: 1px solid var(--linea);
  }

  .por-vencer-texto {
    min-width: 0;
  }

  .por-vencer b {
    display: block;
    font-size: 13.5px;
    font-weight: 700;
  }

  .por-vencer span {
    font-size: 12.5px;
    font-weight: 400;
    color: var(--suave);
  }

  .por-vencer em {
    font-style: normal;
    font-weight: 600;
    color: var(--texto);
  }

  /* Decidido el 5 de noviembre de 2026: los botones de las dos tarjetas, a la misma altura. */
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
