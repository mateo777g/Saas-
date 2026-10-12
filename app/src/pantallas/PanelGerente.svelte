<!--
  El panel del gerente en el paso 1 (libreta 4), portado de la maqueta del Inicio del gerente
  aprobada el 10 de octubre de 2026 (5SVLK2avzLCq5TaW6mrqq6, estado "Paso 1"): la barra lateral
  de vidrio con Inicio, Ayuda, Ajustes y Cerrar sesión, la barra de arriba con la cajita de
  sucursales y la tarjeta del saludo. Ajustes y la ventana Perfil (el pie de la barra) vienen de
  Flet (libreta 4, decidido el 11 de octubre de 2026). La pantalla de suscripción terminada
  llega con la pieza 5.

  Vuelve a leer cada vez que Don Chuy regresa a la pestaña (decidido el 11 de octubre de 2026):
  así el saludo sigue la hora y una licencia que venció con el panel abierto se nota en cuanto
  vuelve. Si en ese momento no hay internet, se queda lo que ya se veía.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import BarraLateral from '../diseno/BarraLateral.svelte';
  import { WHATSAPP_FRAGMENTLESS } from '../lib/fragmentless';
  import {
    leerGerente,
    recordarSucursal,
    sucursalInicial,
    type DatosGerente,
    type Sucursal,
  } from '../lib/gerente';
  import { SIN_PANEL } from '../lib/sesion';
  import Ajustes from './gerente/Ajustes.svelte';
  import CajaSucursales from './gerente/CajaSucursales.svelte';
  import Inicio from './gerente/Inicio.svelte';
  import Perfil from './gerente/Perfil.svelte';

  let {
    usuarioId,
    datos: iniciales,
    alSalir,
    alSinAcceso,
  }: {
    usuarioId: string;
    datos: DatosGerente;
    alSalir: () => void;
    alSinAcceso: (mensaje: string) => void;
  } = $props();

  // Lo que llegó al entrar; después, lo de cada nueva lectura.
  // svelte-ignore state_referenced_locally
  let datos = $state(iniciales);
  // svelte-ignore state_referenced_locally
  let actualId = $state(sucursalInicial(iniciales.sucursales).id);
  let vista = $state<'inicio' | 'ajustes'>('inicio');
  let perfilAbierto = $state(false);

  // Si la que estaba ya no sale en su lista, se elige otra con la misma regla de al abrir.
  const actual = $derived(
    datos.sucursales.find((s) => s.id === actualId) ?? sucursalInicial(datos.sucursales),
  );
  // Lo llaman por su apodo; sin apodo, por su nombre en esta sucursal.
  const nombre = $derived(datos.apodo || actual.mi_nombre);
  const plan = $derived(datos.planes[actual.id] ?? '');

  async function leer() {
    let nuevos: DatosGerente;
    try {
      nuevos = await leerGerente(usuarioId);
    } catch (error) {
      console.error('[gerente] no se pudo volver a leer; se queda lo que se veía:', error);
      return;
    }
    if (nuevos.sucursales.length === 0) {
      alSinAcceso(SIN_PANEL);
      return;
    }
    datos = nuevos;
  }

  function elegir(sucursal: Sucursal) {
    actualId = sucursal.id;
    recordarSucursal(sucursal.id);
  }

  function alPulsar(valor: string) {
    if (valor === 'salir') alSalir();
    else if (valor === 'ayuda') window.open(WHATSAPP_FRAGMENTLESS, '_blank', 'noopener');
    else if (valor === 'inicio' || valor === 'ajustes') vista = valor;
  }

  onMount(() => {
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
</script>

<div class="panel">
  <BarraLateral
    subtitulo={plan ? `Plan ${plan}` : ''}
    opciones={[{ valor: 'inicio', texto: 'Inicio', icono: 'inicio' }]}
    acciones={[
      { valor: 'ayuda', texto: 'Ayuda', icono: 'ayuda' },
      { valor: 'ajustes', texto: 'Ajustes', icono: 'ajustes' },
      { valor: 'salir', texto: 'Cerrar sesión', icono: 'salir' },
    ]}
    activa={vista}
    alElegir={alPulsar}
    pie={{
      inicial: nombre.charAt(0).toUpperCase(),
      nombre,
      linea: plan,
      alPulsar: () => (perfilAbierto = true),
    }}
  />

  {#if vista === 'inicio'}
    <BarraArriba titulo="Inicio">
      <CajaSucursales sucursales={datos.sucursales} {actual} alElegir={elegir} />
    </BarraArriba>
  {:else}
    <BarraArriba titulo="Ajustes" estado={{ texto: 'Se guardan en este navegador', vivo: true }} />
  {/if}

  <main class="cuerpo">
    {#if vista === 'inicio'}
      <Inicio sucursal={actual} {nombre} />
    {:else}
      <Ajustes />
    {/if}
  </main>
</div>

{#if perfilAbierto}
  <Perfil
    nombre={actual.mi_nombre}
    apodo={datos.apodo}
    alCerrar={() => (perfilAbierto = false)}
    alGuardar={leer}
  />
{/if}

<style>
  .panel {
    position: relative;
    height: 100vh;
    height: 100dvh;
    overflow: hidden;
    background: var(--suelo);
  }

  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
  }
</style>
