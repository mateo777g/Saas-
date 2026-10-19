<!--
  Inicio del gerente (maqueta de Inicio 5SVLK2avzLCq5TaW6mrqq6; pieza 5, maqueta Cortes y reportes
  7J6LvYWiktRnGxNugbuaoe). Arriba, la tarjeta de vidrio con la fecha y el saludo, lo no negociable
  de Inicio: la fecha y la hora son las del restaurante y las da Postgres (mis_sucursales), nunca el
  reloj del aparato (libreta 4, decidido el 11 de octubre de 2026). Abajo del saludo, las cuatro
  cifras (maqueta Agente IA KznKZdgQbLTZGs1EwVMvga), que hacen crecer la fila de 372 a 390 px. A su
  lado, Mesas ahora; abajo, Tus meseros y los accesos para el equipo.

  Las cifras, Mesas ahora y Tus meseros salen de cifras_de_inicio (migración agente), mesas_ahora y
  tus_meseros (migración reportes): la app no suma nada. Se leen al abrir, con «Actualizar», al
  regresar a la pestaña y cada vez que cambia una cuenta
  (el tiempo real de ventas: abrir, cobrar, cancelar). «Actualizado 18:05» es la hora del restaurante
  que dio Postgres en la última lectura. Cada tarjeta lee y falla por su cuenta.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Integral from '../../diseno/Integral.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { esDeRed } from '../../lib/errores';
  import { fechaLarga, saludoPorHora } from '../../lib/formato';
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
  import Accesos from './Accesos.svelte';
  import CajaSucursales from './CajaSucursales.svelte';
  import Cifras from './inicio/Cifras.svelte';
  import MesasAhora from './inicio/MesasAhora.svelte';
  import TusMeseros from './inicio/TusMeseros.svelte';

  let {
    sucursal,
    sucursales,
    nombre,
    alElegir,
    alAbrir,
    alIr,
  }: {
    sucursal: Sucursal;
    sucursales: Sucursal[];
    nombre: string;
    alElegir: (sucursal: Sucursal) => void;
    alAbrir: (que: 'pos' | 'caja' | 'cocina') => void;
    alIr: (vista: 'mesas' | 'equipo') => void;
  } = $props();

  type Lectura<T> = { estado: 'leyendo' } | { estado: 'listo'; datos: T } | { estado: 'error'; deRed: boolean };

  let cifras = $state<Lectura<CifrasDeInicio>>({ estado: 'leyendo' });
  let mesas = $state<Lectura<DatosMesas>>({ estado: 'leyendo' });
  let meseros = $state<Lectura<DatosMeseros>>({ estado: 'leyendo' });
  let hora = $state<string | null>(null);
  let leyendo = $state(false);

  const chip = $derived.by(() => {
    const fallas = [cifras, mesas, meseros].filter((l) => l.estado === 'error');
    if (!fallas.length) return { texto: 'Ventas y mesas en vivo', vivo: true };
    return fallas.some((l) => l.estado === 'error' && l.deRed)
      ? { texto: 'Sin conexión', vivo: false }
      : { texto: 'No se pudo leer', vivo: false };
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
  {#snippet despues()}
    {#if hora}<span class="hora">Actualizado {hora}</span>{/if}
  {/snippet}
  <BotonCuadro icono="actualizar" ayuda="Actualizar" apagado={leyendo} onclick={leer} />
  <CajaSucursales {sucursales} actual={sucursal} {alElegir} />
</BarraArriba>

<main class="cuerpo">
  <div class="fila-arriba">
    <Vidrio como="section" class="saludo" radio={30} aria-label="Saludo">
      <div>
        <div class="fecha">
          <span class="logo"><Integral ancho={20} alto={22} /></span>
          <span class="etiqueta">{fechaLarga(sucursal.hoy)}</span>
        </div>
        <p class="texto">
          {saludoPorHora(sucursal.hora)}, {nombre}.<span>Así va tu negocio hoy.</span>
        </p>
      </div>
      <Cifras lectura={cifras} />
    </Vidrio>
    <MesasAhora lectura={mesas} alAdministrar={() => alIr('mesas')} />
  </div>
  <div class="fila-abajo">
    <TusMeseros lectura={meseros} alVerEmpleados={() => alIr('equipo')} />
    <Accesos {alAbrir} />
  </div>
</main>

<style>
  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .hora {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
  }

  .fila-arriba {
    flex: none;
    height: 390px;
    display: flex;
    gap: 16px;
  }

  .fila-abajo {
    flex: 1;
    min-height: 0;
    display: flex;
    gap: 16px;
  }

  .fila-arriba > :global(.saludo) {
    flex: 1;
    min-width: 0;
    padding: 34px 36px 28px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
  }

  .fecha {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .logo {
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--acento);
  }

  .fecha .etiqueta {
    font-size: 11.5px;
  }

  .texto {
    margin: 14px 0 0;
    font-size: 50px;
    font-weight: 800;
    line-height: 1.04;
    letter-spacing: -1.25px;
  }

  .texto span {
    display: block;
    color: var(--tenue);
  }
</style>
