<!--
  Inicio de tu panel, portado de la maqueta aprobada el 10 de octubre de 2026
  (Tbt7H3G1QRXykzNKe1GXHh). Arriba, las 3 cifras de panel_resumen y tu insignia; en medio, Altas
  por mes; abajo, Tus distribuidores (panel_distribuidores) y Vencen pronto (las filas de
  panel_clientes que vencieron o vencen en los próximos 7 días), con Sumar meses.

  En el paso 1 (libreta 8) Tus distribuidores no lleva «Ver distribuidores →»: la vista llega
  con el paso 2, y mientras no haya ninguno dice «Darlos de alta llega con el paso 2.».
-->
<script lang="ts">
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import EstadoPunto from '../../diseno/EstadoPunto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { fecha, plural, vigencia } from '../../lib/formato';
  import type { Cliente, DatosPanel } from '../../lib/panel';
  import GraficaAltas from './GraficaAltas.svelte';
  import Insignia from './Insignia.svelte';

  let {
    datos,
    alSumar,
    alVerClientes,
  }: {
    datos: DatosPanel | null;
    alSumar: (cliente: Cliente) => void;
    alVerClientes: () => void;
  } = $props();

  const NO_SE_PUDO = 'No se pudo cargar.';

  let busqueda = $state('');

  // Las 3 cifras: el valor y su nota. Mientras se lee la primera vez, vacías.
  const cifras = $derived.by(() => {
    const r = datos?.resumen;
    if (!r) return null;
    if (!r.ok) return [{ valor: '—', nota: NO_SE_PUDO }, { valor: '—', nota: NO_SE_PUDO }, { valor: '—', nota: NO_SE_PUDO }];
    const c = r.datos;
    return [
      { valor: String(c.funcionan), nota: `de ${plural(c.total, 'restaurante', 'restaurantes')}` },
      {
        valor: String(c.vencen_pronto),
        nota: c.vencen_pronto === 0 ? 'Nada por vencer esta semana' : plural(c.vencen_hoy, 'vence hoy', 'vencen hoy'),
      },
      {
        valor: String(c.sin_funcionar),
        nota:
          c.sin_funcionar === 0
            ? 'Ninguno pausado ni vencido'
            : `${plural(c.vencidos, 'vencido', 'vencidos')} · ${plural(c.pausados, 'pausado', 'pausados')}`,
      },
    ];
  });

  const ETIQUETAS_CIFRAS = ['FUNCIONAN HOY', 'VENCEN EN 7 DÍAS', 'SIN FUNCIONAR'];

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

  // En negritas, lo que ya venció o vence hoy.
  function urgente(c: Cliente) {
    return c.estado === 'vencida' || (c.estado === 'vence_pronto' && c.dias_restantes === 0);
  }
</script>

<div class="inicio">
  {#each ETIQUETAS_CIFRAS as etiqueta, i (etiqueta)}
    <Vidrio como="section" class="tarjeta cifra">
      <span class="etiqueta">{etiqueta}</span>
      <span class="valor">{cifras?.[i].valor ?? ''}</span>
      <span class="nota">{cifras?.[i].nota ?? ''}</span>
    </Vidrio>
  {/each}

  <Vidrio como="section" class="tarjeta premio" aria-label="Insignia">
    <Insignia />
  </Vidrio>

  <Vidrio como="section" class="tarjeta grafica" aria-label="Altas por mes">
    <div class="fila-titulo">
      <div>
        <span class="titulo-tarjeta">Altas por mes</span>
        <span class="nota-chica">Restaurantes que diste de alta en los últimos 6 meses.</span>
      </div>
      {#if datos?.altas.ok && datos.altas.datos.length}
        <span class="etiqueta">{datos.altas.datos[0].total_6_meses} EN 6 MESES</span>
      {/if}
    </div>
    {#if datos?.altas.ok}
      <GraficaAltas altas={datos.altas.datos} />
    {:else if datos}
      <div class="sin-grafica">{NO_SE_PUDO}</div>
    {:else}
      <div class="sin-grafica"></div>
    {/if}
  </Vidrio>

  <Vidrio como="section" class="tarjeta dist" aria-label="Tus distribuidores">
    <div class="fila-titulo">
      <div>
        <span class="titulo-tarjeta">Tus distribuidores</span>
        <span class="nota-chica">Quienes venden Fragmentless en persona y cuántos clientes tiene cada uno.</span>
      </div>
      <label class="buscador">
        <Icono nombre="buscar" tamano={16} />
        <span class="solo-lector">Buscar distribuidor</span>
        <input type="search" placeholder="Buscar distribuidor" autocomplete="off" bind:value={busqueda} />
      </label>
    </div>
    <Tabla
      columnas="22fr 11fr 22fr 14fr 9fr"
      encabezados={[
        { texto: 'NOMBRE' },
        { texto: 'ESTADO' },
        { texto: 'CORREO' },
        { texto: 'TELÉFONO' },
        { texto: 'CLIENTES', derecha: true },
      ]}
    >
      {#if !datos}
        <!-- leyendo la primera vez -->
      {:else if !datos.distribuidores.ok}
        <NotaTabla titulo="No se pudieron leer tus distribuidores." texto={datos.distribuidores.mensaje} />
      {:else if datos.distribuidores.datos.length === 0}
        <NotaTabla titulo="Todavía no hay distribuidores." texto="Darlos de alta llega con el paso 2." />
      {:else if distribuidores.length === 0}
        <NotaTabla titulo="Ningún distribuidor se llama así." texto="Prueba con otro nombre o correo." />
      {:else}
        {#each distribuidores as d (d.id)}
          <div class="fila">
            <div class="persona">
              <span class="inicial">{d.nombre.charAt(0)}</span>
              <span class="nombre">{d.nombre}</span>
            </div>
            <EstadoPunto prendido={d.activo} texto={d.activo ? 'Activo' : 'De baja'} />
            <span class="celda" class:tenue={!d.correo}>{d.correo ?? '—'}</span>
            <span class="celda" class:tenue={!d.telefono}>{d.telefono ?? '—'}</span>
            <span class="celda numero">{d.clientes}</span>
          </div>
        {/each}
      {/if}
    </Tabla>
  </Vidrio>

  <Vidrio como="section" class="tarjeta pronto" aria-label="Vencen pronto">
    <div class="titulos">
      <span class="titulo-tarjeta">Vencen pronto</span>
      <span class="nota-chica">Vencieron o vencen en los próximos 7 días.</span>
    </div>
    <div class="lista">
      {#if !datos}
        <!-- leyendo la primera vez -->
      {:else if !datos.clientes.ok}
        <div class="vacia">{NO_SE_PUDO}</div>
      {:else if pronto.length === 0}
        <div class="vacia">Nada por revisar esta semana.</div>
      {:else}
        {#each pronto as c (c.id)}
          <div class="item">
            <div class="item-texto">
              <span class="nombre">{c.nombre}</span>
              <span class="linea">
                {#if urgente(c)}<b>{vigencia(c.dias_restantes)}</b>{:else}{vigencia(c.dias_restantes)}{/if}
                · {fecha(c.licencia_fin)}
              </span>
            </div>
            <BotonCuadro
              icono="calendario-mas"
              ayuda="Sumar meses"
              etiqueta="Sumar meses a {c.nombre}"
              onclick={() => alSumar(c)}
            />
          </div>
        {/each}
      {/if}
    </div>
    <div>
      <Boton tamano="chico" etiqueta="Ver clientes" icono="derecha" iconoAlFinal onclick={alVerClientes} />
    </div>
  </Vidrio>
</div>

<style>
  .inicio {
    height: 100%;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr)) minmax(0, 1.3fr);
    grid-template-rows: 120px 200px minmax(0, 1fr);
    gap: 16px;
  }

  .inicio > :global(.tarjeta) {
    min-width: 0;
    min-height: 0;
    padding: 20px;
  }

  .inicio > :global(.cifra) {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 18px 20px;
  }

  .inicio > :global(.premio) {
    grid-column: 4;
    grid-row: 1 / span 2;
    padding: 10px;
  }

  .inicio > :global(.grafica) {
    grid-column: 1 / span 3;
    grid-row: 2;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .inicio > :global(.dist) {
    grid-column: 1 / span 3;
    grid-row: 3;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .inicio > :global(.pronto) {
    grid-column: 4;
    grid-row: 3;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .valor {
    font-size: 26px;
    font-weight: 800;
    letter-spacing: -0.5px;
    line-height: 1.15;
    min-height: 1.15em;
  }

  .nota {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .titulo-tarjeta {
    font-size: 14.5px;
    font-weight: 700;
  }

  .nota-chica {
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .fila-titulo {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 16px;
  }

  .fila-titulo > div,
  .titulos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .sin-grafica {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .buscador {
    width: 260px;
    height: 40px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    color: var(--tenue);
  }

  .buscador:focus-within {
    border-color: var(--suave);
  }

  .buscador input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
  }

  .buscador input::placeholder {
    color: var(--tenue);
  }

  .persona {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .inicial {
    width: 34px;
    height: 34px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 17px;
    background: var(--chip);
    border: 1px solid var(--linea);
    font-size: 13px;
    font-weight: 700;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .lista {
    flex: 1;
    min-height: 0;
    overflow: auto;
    display: flex;
    flex-direction: column;
  }

  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 11px 0;
    border-bottom: 1px solid var(--linea);
  }

  .item:first-child {
    border-top: 1px solid var(--linea);
  }

  .item-texto {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .linea {
    font-size: 12px;
    font-weight: 500;
    color: var(--suave);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .linea b {
    font-weight: 600;
    color: var(--texto);
  }

  .vacia {
    padding: 24px 0;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }
</style>
