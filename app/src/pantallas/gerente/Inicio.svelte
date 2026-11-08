<!--
  Inicio del gerente (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D): centrado como
  el inicio de Cloudflare. Arriba, la fecha y el saludo, lo no negociable de Inicio: la fecha y la hora son
  las del restaurante y las da Postgres (mis_sucursales), nunca el reloj del aparato (libreta 4, decidido
  el 11 de octubre de 2026). Debajo, la búsqueda grande (Ctrl K), las tres columnas Abrir · Atajos ·
  Recientes y, al bajar, «Resumen de hoy»: las cuatro cifras, Mesas ahora y Tus meseros.
  Desde el 7 de noviembre de 2026 el saludo sube con su fecha como la frase del Agente IA, su segunda línea va
  del color del texto y no en gris (la fecha sí, gris), y luego salen las columnas en fila. El brillo detrás de la búsqueda se probó y el
  developer lo quitó el 8 de noviembre de 2026; con él regresaron los grises de las columnas, y el saludo,
  que esperaba al brillo (1.05 s), sale desde 0.1 s.

  Las cifras, Mesas ahora y Tus meseros salen de cifras_de_inicio (migraciones agente y cifras_graficas),
  mesas_ahora y tus_meseros (migración reportes): la app no suma nada. Se leen al abrir, con «Actualizar»,
  al regresar a la pestaña y cada vez que cambia una cuenta (el tiempo real de ventas: abrir, cobrar,
  cancelar). «Actualizado 18:05» es la hora del restaurante que dio Postgres en la última lectura. Cada
  tarjeta lee y falla por su cuenta.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import { esDeRed } from '../../lib/errores';
  import { diaConNombre, saludoPorHora } from '../../lib/formato';
  import type { Sucursal } from '../../lib/gerente';
  import { escuchar } from '../../lib/pos';
  import {
    leerCifrasDeInicio,
    leerMesasAhora,
    leerTusMeseros,
    type CifrasDeInicio,
    type MesasAhora as DatosMesas,
    type TusMeseros as DatosMeseros,
  } from '../../lib/reportes';
  import { supabase } from '../../lib/supabase';
  import { leerRecientes, type Destino } from '../../lib/vistas';
  import CajaSucursales from './CajaSucursales.svelte';
  import Buscador from './inicio/Buscador.svelte';
  import Cifras from './inicio/Cifras.svelte';
  import Columnas from './inicio/Columnas.svelte';
  import MesasAhora from './inicio/MesasAhora.svelte';
  import TusMeseros from './inicio/TusMeseros.svelte';

  let {
    sucursal,
    sucursales,
    nombre,
    tomarBusqueda,
    alElegir,
    alAbrir,
    alIr,
  }: {
    sucursal: Sucursal;
    sucursales: Sucursal[];
    nombre: string;
    // Si pidieron la búsqueda (Ctrl K o la búsqueda chica de la barra); se toma una vez, para que no se
    // abra sola cada vez que se regresa a Inicio.
    tomarBusqueda: () => boolean;
    alElegir: (sucursal: Sucursal) => void;
    alAbrir: (que: 'pos' | 'caja' | 'cocina') => void;
    alIr: (destino: Destino) => void;
  } = $props();

  type Lectura<T> = { estado: 'leyendo' } | { estado: 'listo'; datos: T } | { estado: 'error'; deRed: boolean };

  let cifras = $state<Lectura<CifrasDeInicio>>({ estado: 'leyendo' });
  let mesas = $state<Lectura<DatosMesas>>({ estado: 'leyendo' });
  let meseros = $state<Lectura<DatosMeseros>>({ estado: 'leyendo' });
  let hora = $state<string | null>(null);
  let leyendo = $state(false);
  let buscador = $state<{ enfocar: () => void } | null>(null);
  // svelte-ignore state_referenced_locally
  const recientes = leerRecientes(sucursal.id);

  const chip = $derived.by(() => {
    const fallas = [cifras, mesas, meseros].filter((l) => l.estado === 'error');
    if (!fallas.length) return { texto: 'Ventas y mesas en vivo', vivo: true };
    return fallas.some((l) => l.estado === 'error' && l.deRed)
      ? { texto: 'Sin conexión', vivo: false }
      : { texto: 'No se pudo leer', vivo: false };
  });

  $effect(() => {
    if (buscador && tomarBusqueda()) buscador.enfocar();
  });

  // Solo cuenta la lectura más reciente: si dos se cruzan, la vieja no pisa a la nueva.
  let vuelta = 0;

  async function leer() {
    const esta = ++vuelta;
    leyendo = true;
    const [c, m, p] = await Promise.allSettled([
      leerCifrasDeInicio(sucursal.id),
      leerMesasAhora(sucursal.id),
      leerTusMeseros(sucursal.id),
    ]);
    if (esta !== vuelta) return;
    leyendo = false;
    if (c.status === 'fulfilled') {
      cifras = { estado: 'listo', datos: c.value };
      hora = c.value.hora;
    } else {
      console.error('[inicio] no se pudo leer cifras_de_inicio:', c.reason);
      cifras = { estado: 'error', deRed: esDeRed(c.reason) };
    }
    if (m.status === 'fulfilled') {
      mesas = { estado: 'listo', datos: m.value };
      hora = m.value.hora;
    } else {
      console.error('[inicio] no se pudo leer mesas_ahora:', m.reason);
      mesas = { estado: 'error', deRed: esDeRed(m.reason) };
    }
    if (p.status === 'fulfilled') {
      meseros = { estado: 'listo', datos: p.value };
      hora = p.value.hora;
    } else {
      console.error('[inicio] no se pudo leer tus_meseros:', p.reason);
      meseros = { estado: 'error', deRed: esDeRed(p.reason) };
    }
  }

  // Varios cambios seguidos (mandar a cocina toca varias filas) se leen una sola vez.
  let espera: ReturnType<typeof setTimeout> | undefined;
  function programar() {
    clearTimeout(espera);
    espera = setTimeout(leer, 400);
  }

  onMount(() => {
    leer();
    const dejar = escuchar(supabase, sucursal.id, ['ventas'], programar);
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      clearTimeout(espera);
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  });
</script>

<BarraArriba titulo="Inicio" estado={chip}>
  {#if hora}<span class="hora">Actualizado {hora}</span>{/if}
  <BotonCuadro icono="r-actualizar" ayuda="Actualizar" apagado={leyendo} onclick={leer} />
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="vista">
  <div class="inicio">
    <div class="saludo">
      <span class="etiqueta fecha">{diaConNombre(sucursal.hoy)}</span>
      <h1>{saludoPorHora(sucursal.hora)}, {nombre}.<span class="debajo">Así va tu negocio hoy.</span></h1>
    </div>

    <Buscador bind:this={buscador} {recientes} {alIr} />
    <Columnas {recientes} {alAbrir} {alIr} />

    <div class="resumen-titulo">
      <h2>Resumen de hoy</h2>
      {#if hora}<span class="hora">Actualizado {hora}</span>{/if}
    </div>
    <Cifras lectura={cifras} />
    <div class="fila">
      <MesasAhora lectura={mesas} alAdministrar={() => alIr({ vista: 'mesas' })} />
      <TusMeseros lectura={meseros} alVerEmpleados={() => alIr({ vista: 'equipo' })} />
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

  /* Sube como la frase del Agente IA. */
  .saludo {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
    animation: saludo-sube 0.55s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  @keyframes saludo-sube {
    from {
      opacity: 0;
      transform: translateY(18px);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .saludo {
      animation: none;
    }
  }

  .fecha {
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

  /* Del color del texto, no en gris (el developer, 7 nov 2026, «C · Negro»). La fecha regresó al gris el 8 nov. */
  .debajo {
    display: block;
    color: var(--texto);
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
    grid-template-columns: minmax(0, 5fr) minmax(0, 7fr);
    gap: 12px;
    margin-top: 12px;
  }
</style>
