<!--
  Inicio del distribuidor, portado de la maqueta aprobada el 12 de octubre de 2026
  (YXYVVNdLRXwgWCNErFSeyK): la rejilla del Inicio de Fragmentless sin la insignia ni Altas por
  mes. Arriba, las 3 cifras de distribuidor_resumen; debajo, Tus clientes (distribuidor_clientes,
  con su buscador y «Ver clientes →»), y a la derecha, de arriba abajo, Vencen pronto (sus
  clientes que vencieron o vencen en los próximos 7 días), sin Sumar meses: eso solo lo hace
  Fragmentless.

  Desde el 8 de noviembre de 2026 (el developer: «todo, las animaciones, lo nuevo de los atajos, la barra de
  búsqueda, los esqueletos») arriba va lo del Inicio de Fragmentless: el saludo que sube, la búsqueda grande
  (Ctrl K) y las columnas en fila, y lo de antes queda abajo, bajo «Resumen». Por encuesta, las columnas son solo
  Abrir y Recientes, porque no tiene acciones. La primera vez que lee, las tarjetas llevan sus esqueletos.

  El mismo día, «quiero que en el panel de mi distribuidor haya gráficas, como las mías»: sus 3 cifras se volvieron
  las 5 gráficas del Inicio de Fragmentless (fragmentless/inicio/Estadisticas, con distribuidor_estadisticas), con
  el gasto de IA de sus clientes (encuesta), y Tus clientes y Vencen pronto quedaron debajo, lado a lado. Esa
  lectura trae la fecha y la hora de México: el saludo es «Buenas tardes, Josué.» con su fecha (encuesta); sale
  cuando llega y, si no se pudo leer, dice «Hola, Josué.» sin fecha.
-->
<script lang="ts">
  import Boton from '../../diseno/Boton.svelte';
  import Buscador, { type RenglonBusqueda } from '../../diseno/Buscador.svelte';
  import Columnas, { type ItemColumna } from '../../diseno/Columnas.svelte';
  import Esqueleto from '../../diseno/Esqueleto.svelte';
  import Estadisticas from '../fragmentless/inicio/Estadisticas.svelte';
  import EstadoPunto from '../../diseno/EstadoPunto.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Tarjeta from '../../diseno/Tarjeta.svelte';
  import type { DatosDistribuidor } from '../../lib/distribuidor';
  import { diaConNombre, fecha, saludoPorHora, vigencia } from '../../lib/formato';
  import { urgente } from '../../lib/panel';
  import { leerRecientes, VISTAS, type VistaDistribuidor } from '../../lib/vistasDistribuidor';

  let {
    datos,
    nombre,
    tomarBusqueda,
    alIr,
  }: {
    datos: DatosDistribuidor | null;
    // Su nombre completo, de su fila en distribuidores: el saludo usa el primero.
    nombre: string;
    // Si pidieron la búsqueda (Ctrl K o la búsqueda chica); se toma una vez.
    tomarBusqueda: () => boolean;
    alIr: (vista: VistaDistribuidor) => void;
  } = $props();

  const primerNombre = $derived(nombre.trim().split(/\s+/)[0]);

  let buscador = $state<{ enfocar: () => void } | null>(null);

  $effect(() => {
    if (buscador && tomarBusqueda()) buscador.enfocar();
  });

  const recientes = leerRecientes();

  const deVista = (v: VistaDistribuidor): RenglonBusqueda => ({
    clave: v,
    texto: VISTAS[v].texto,
    icono: VISTAS[v].icono,
    alPicar: () => alIr(v),
  });
  const vistas = (['clientes', 'ajustes'] as const).map(deVista);
  const abrir: ItemColumna[] = (['clientes', 'ajustes'] as const).map(deVista);
  const deRecientes: ItemColumna[] = recientes.map((v) => ({ ...deVista(v), icono: 'r-reloj' }));

  const NO_SE_PUDO = 'No se pudo cargar.';

  let busqueda = $state('');

  // La fecha y la hora de México, de distribuidor_estadisticas: nunca el reloj del aparato.
  const estadisticas = $derived(datos?.estadisticas.ok ? datos.estadisticas.datos : null);
  const hora = $derived(estadisticas?.hora ?? null);
  const saludo = $derived(estadisticas ? saludoPorHora(Number(estadisticas.hora.slice(0, 2))) : 'Hola');

  // Tus clientes, filtrados por nombre o slug.
  const suyos = $derived.by(() => {
    if (!datos?.clientes.ok) return [];
    const q = busqueda.trim().toLowerCase();
    return datos.clientes.datos.filter((c) => !q || c.nombre.toLowerCase().includes(q) || c.slug.includes(q));
  });

  // Vencen pronto: lo que Postgres marcó como vencida o vence_pronto (los pausados no).
  const pronto = $derived(
    datos?.clientes.ok
      ? datos.clientes.datos.filter((c) => c.estado === 'vencida' || c.estado === 'vence_pronto')
      : [],
  );
</script>

<main class="vista">
<div class="inicio">
  <!-- Guarda su lugar mientras lee, para que nada brinque; el saludo sube cuando llega. -->
  <div class="saludo">
    {#if datos}
      <div class="sube">
        <span class="etiqueta fecha">{estadisticas ? diaConNombre(estadisticas.hoy) : ''}</span>
        <h1>{saludo}, {primerNombre}.<span class="debajo">Así van tus clientes.</span></h1>
      </div>
    {/if}
  </div>

  <Buscador bind:this={buscador} {vistas} acciones={[]} recientes={recientes.map(deVista)} placeholder="Busca una vista…" />
  <Columnas {abrir} recientes={deRecientes} entra />

  <div class="resumen-titulo">
    <h2>Resumen</h2>
    {#if hora}<span class="hora">Actualizado {hora}</span>{/if}
  </div>
  <Estadisticas {datos} notaGasto="Lo que gastan tus clientes en IA; se descuenta de tu parte" quienes={['cliente', 'clientes']} />

<div class="rejilla" aria-busy={!datos}>

  <Tarjeta como="section" class="tarjeta suyos" aria-label="Tus clientes">
    <div class="fila-titulo">
      <div>
        <span class="titulo-tarjeta">Tus clientes</span>
        <span class="nota-chica">Los restaurantes que te asignó Fragmentless y cuándo termina su licencia.</span>
      </div>
      <label class="buscador">
        <Icono nombre="buscar" tamano={16} />
        <span class="solo-lector">Buscar cliente</span>
        <input type="search" placeholder="Buscar cliente" autocomplete="off" bind:value={busqueda} />
      </label>
    </div>
    <Tabla
      columnas="24fr 10fr 10fr 14fr"
      encabezados={[{ texto: 'RESTAURANTE' }, { texto: 'LICENCIA' }, { texto: 'FIN' }, { texto: 'VIGENCIA' }]}
    >
      {#if !datos}
        <!-- El esqueleto: tres renglones con la forma de un cliente (8 nov 2026). -->
        {#each ['132px', '104px', '118px'] as ancho, i (i)}
          <div class="fila" aria-hidden="true">
            <div class="restaurante">
              <Esqueleto ancho="36px" alto="36px" redondo="11px" />
              <div class="nombres"><Esqueleto {ancho} alto="11px" /><Esqueleto ancho="64px" alto="9px" /></div>
            </div>
            <span class="lineas-una"><Esqueleto ancho="8px" alto="8px" redondo="50%" /><Esqueleto ancho="56px" alto="10px" /></span>
            <Esqueleto ancho="64px" alto="10px" />
            <Esqueleto ancho="72px" alto="10px" />
          </div>
        {/each}
      {:else if !datos.clientes.ok}
        <NotaTabla titulo="No se pudieron leer tus clientes." texto={datos.clientes.mensaje} />
      {:else if datos.clientes.datos.length === 0}
        <NotaTabla
          titulo="Todavía no tienes clientes."
          texto="Cuando cierres un trato, Fragmentless te asigna el restaurante."
        />
      {:else if suyos.length === 0}
        <NotaTabla titulo="Ningún cliente se llama así." texto="Prueba con otro nombre." />
      {:else}
        {#each suyos as c (c.id)}
          <div class="fila">
            <div class="restaurante">
              <span class="cuadro-icono"><Icono nombre="tienda" tamano={18} /></span>
              <div class="nombres">
                <span class="nombre">{c.nombre}</span>
                <span class="slug">{c.slug}</span>
              </div>
            </div>
            <EstadoPunto prendido={c.licencia_activa} texto={c.licencia_activa ? 'Prendida' : 'Pausada'} />
            <span class="celda">{fecha(c.licencia_fin)}</span>
            <span class="celda" class:fuerte={urgente(c)} class:tenue={c.dias_restantes === null}>
              {vigencia(c.dias_restantes)}
            </span>
          </div>
        {/each}
      {/if}
    </Tabla>
    <div>
      <Boton tamano="chico" etiqueta="Ver clientes" icono="derecha" iconoAlFinal onclick={() => alIr('clientes')} />
    </div>
  </Tarjeta>

  <Tarjeta como="section" class="tarjeta pronto" aria-label="Vencen pronto">
    <div class="titulos">
      <span class="titulo-tarjeta">Vencen pronto</span>
      <span class="nota-chica">Vencieron o vencen en los próximos 7 días.</span>
    </div>
    <div class="lista">
      {#if !datos}
        <!-- El esqueleto: tres renglones con la forma de uno por vencer (8 nov 2026). -->
        {#each ['64%', '48%', '56%'] as ancho, i (i)}
          <div class="item" aria-hidden="true"><Esqueleto {ancho} alto="11px" /><Esqueleto ancho="44%" alto="9px" /></div>
        {/each}
      {:else if !datos.clientes.ok}
        <div class="vacia">{NO_SE_PUDO}</div>
      {:else if pronto.length === 0}
        <div class="vacia">Nada por revisar esta semana.</div>
      {:else}
        {#each pronto as c (c.id)}
          <div class="item">
            <span class="nombre">{c.nombre}</span>
            <span class="linea">
              {#if urgente(c)}<b>{vigencia(c.dias_restantes)}</b>{:else}{vigencia(c.dias_restantes)}{/if}
              · {fecha(c.licencia_fin)}
            </span>
          </div>
        {/each}
      {/if}
    </div>
  </Tarjeta>
</div>
</div>
</main>

<style>
  /* Lo de arriba, como el Inicio de Fragmentless. */
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

  /* El lugar del saludo, de su alto aunque todavía no llegue (la fecha, 12 px y las dos líneas). */
  .saludo {
    min-height: 113px;
  }

  /* Sube como en el Inicio del gerente, en cuanto llega. */
  .sube {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
    animation: saludo-sube 0.55s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  /* En la letra de la fecha del gerente. */
  .fecha {
    min-height: 14px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  @keyframes saludo-sube {
    from {
      opacity: 0;
      transform: translateY(18px);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .sube {
      animation: none;
    }
  }

  h1 {
    margin: 0;
    font-size: 40px;
    font-weight: 800;
    line-height: 1.08;
    letter-spacing: -1px;
    text-wrap: balance;
  }

  /* Del color del texto, como «Así va tu negocio hoy.» del gerente. */
  .debajo {
    display: block;
    color: var(--texto);
  }

  .resumen-titulo {
    display: flex;
    align-items: baseline;
    gap: 12px;
    margin: 56px 0 14px;
  }

  .hora {
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 400;
    color: var(--tenue);
    white-space: nowrap;
  }

  h2 {
    margin: 0;
    font-size: 18px;
    font-weight: 700;
  }

  /* Debajo de las gráficas, Tus clientes y Vencen pronto lado a lado, como Tus distribuidores y Vencen pronto en
     el Inicio de Fragmentless. Por dentro, como estaban. */
  .rejilla {
    display: grid;
    grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
    gap: 12px;
    margin-top: 12px;
  }

  .rejilla > :global(.tarjeta) {
    min-width: 0;
    min-height: 0;
    padding: 20px;
  }

  .rejilla > :global(.suyos),
  .rejilla > :global(.pronto) {
    display: flex;
    flex-direction: column;
    gap: 14px;
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

  .restaurante {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
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

  .nombres {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .slug {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
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

  /* Sin el botón de Sumar meses, cada renglón guarda el alto que tiene en el Inicio de
     Fragmentless (59), como en la maqueta. */
  .item {
    min-height: 59px;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 3px;
    padding: 11px 0;
    border-bottom: 1px solid var(--linea);
  }

  .item:first-child {
    border-top: 1px solid var(--linea);
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

  .lineas-una {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .vacia {
    padding: 24px 0;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }
</style>
