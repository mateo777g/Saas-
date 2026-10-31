<!--
  El panel del gerente en el paso 1 (libreta 4), portado de la maqueta del Inicio del gerente
  aprobada el 10 de octubre de 2026 (5SVLK2avzLCq5TaW6mrqq6, estado "Paso 1"): la barra lateral
  de vidrio con Inicio, Ayuda, Ajustes y Cerrar sesión, la barra de arriba con la cajita de
  sucursales y la tarjeta del saludo. Ajustes y la ventana Perfil (el pie de la barra) vienen de
  Flet (libreta 4, decidido el 11 de octubre de 2026). Mi menú y Mesas, bajo GENERAL como en
  Flet, vienen de sus maquetas (CC2rrjbgxC2yykNa33a3sA y 4TKmJzMwyWMCAVU2MwEDwc), y Empleados de
  la suya (36iXMMqXCfVv4NuVR7vNSc); las tres traen su propia barra de arriba. Cortes y reportes,
  Mesas ahora y Tus meseros en Inicio, y la hora de corte en Ajustes vienen de la pieza 5 (maqueta
  7J6LvYWiktRnGxNugbuaoe); Inicio y Cortes también traen su barra. «Agente IA», al final de
  GENERAL con su insignia IA como en Flet, viene de su maqueta (KznKZdgQbLTZGs1EwVMvga); al entrar
  al panel se prepara su saludo, para que salga al instante. «Crear contenido», después del agente
  con su insignia IA, viene de su maqueta (JQBw2yGFSiky1x9twUyYbe). «Abrir» en los
  accesos de Inicio abre ahí mismo el punto de venta o la cocina, con su sesión (maqueta Mesero y
  cocina TYq97pKacRCYBqcvRp1bZ2). «Tu restaurante», primero en GENERAL, y «Tu menú en línea», que abre
  el «Abrir» de Menú digital con su flecha para volver, vienen de la maqueta de la 6a
  (Qx4C5CbKJYpeAsJCfw4ghn). Si la
  sucursal en la que está no funciona hoy (vencida o pausada, lo dice Postgres), en lugar de todo
  eso sale la suscripción terminada.

  Vuelve a leer cada vez que Don Chuy regresa a la pestaña (decidido el 11 de octubre de 2026):
  así el saludo sigue la hora y una licencia que venció con el panel abierto se nota en cuanto
  vuelve, y una que Fragmentless renovó regresa sola al panel. Si en ese momento no hay
  internet, se queda lo que ya se veía.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import BarraLateral from '../diseno/BarraLateral.svelte';
  import { haySaludo, prepararSaludo } from '../lib/agente';
  import { saludoPorHora } from '../lib/formato';
  import { WHATSAPP_FRAGMENTLESS } from '../lib/fragmentless';
  import {
    leerGerente,
    recordarSucursal,
    sucursalInicial,
    type DatosGerente,
    type Sucursal,
  } from '../lib/gerente';
  import { VigiaPedidos } from '../lib/pedidos.svelte';
  import { SIN_PANEL } from '../lib/sesion';
  import { supabase } from '../lib/supabase';
  import CajaError from '../diseno/CajaError.svelte';
  import { esDeRed, SIN_CONEXION } from '../lib/errores';
  import AccesoAbierto from './gerente/AccesoAbierto.svelte';
  import Ajustes from './gerente/Ajustes.svelte';
  import Cortes from './gerente/Cortes.svelte';
  import CrearContenido from './gerente/CrearContenido.svelte';
  import Empleados from './gerente/Empleados.svelte';
  import Inicio from './gerente/Inicio.svelte';
  import Menu from './gerente/Menu.svelte';
  import MenuEnLinea from './gerente/MenuEnLinea.svelte';
  import Mesas from './gerente/Mesas.svelte';
  import Pedidos from './gerente/Pedidos.svelte';
  import Perfil from './gerente/Perfil.svelte';
  import Suscripcion from './gerente/Suscripcion.svelte';
  import TuRestaurante from './gerente/TuRestaurante.svelte';

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
  let vista = $state<
    | 'inicio'
    | 'pedidos'
    | 'restaurante'
    | 'menu'
    | 'mesas'
    | 'equipo'
    | 'cortes'
    | 'agente'
    | 'crear'
    | 'ajustes'
    | 'pos'
    | 'caja'
    | 'cocina'
    | 'menu-en-linea'
  >('inicio');
  let perfilAbierto = $state(false);

  // Si la que estaba ya no sale en su lista, se elige otra con la misma regla de al abrir.
  const actual = $derived(
    datos.sucursales.find((s) => s.id === actualId) ?? sucursalInicial(datos.sucursales),
  );
  // Lo llaman por su apodo; sin apodo, por su nombre en esta sucursal.
  const nombre = $derived(datos.apodo || actual.mi_nombre);
  const plan = $derived(datos.planes[actual.id] ?? '');
  // Las otras sucursales que sí funcionan, para el «Ir a ella» de la suscripción terminada.
  const otrasQueFuncionan = $derived(
    datos.sucursales.filter((s) => s.estado === 'funciona' && s.id !== actual.id),
  );

  // Los pedidos del menú en línea de la sucursal (parte 6b): su vigía vive aquí, encima de las
  // vistas, para que el tono suene en cualquiera. Con su fila de miembros, también le suena «Lista»
  // a lo que confirmó, menos en el punto de venta, que ya suena solo.
  let vigia = $state<VigiaPedidos | null>(null);
  // Solo el id: releer las sucursales al volver a la pestaña no la vuelve a crear.
  const vigilada = $derived(actual.estado === 'funciona' ? actual.id : null);
  $effect(() => {
    if (vigilada === null) return;
    const restauranteId = vigilada;
    let dejar: (() => void) | null = null;
    let fuera = false;
    supabase
      .from('miembros')
      .select('id')
      .eq('restaurante_id', restauranteId)
      .eq('usuario_id', usuarioId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (error) console.error('[gerente] no se pudo leer su fila de miembros; «Lista» no le sonará:', error);
        if (fuera) return;
        const v = new VigiaPedidos(supabase, restauranteId, data?.id ?? null);
        vigia = v;
        dejar = v.iniciar();
      });
    return () => {
      fuera = true;
      dejar?.();
      vigia = null;
    };
  });
  $effect(() => {
    if (vigia) vigia.oirListas = vista !== 'pos';
  });

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

  // La vista del agente (con markdown-it) se baja la primera vez que se abre, no al entrar.
  let vistaAgente: Promise<typeof import('./gerente/Agente.svelte')> | null = null;
  function cargarAgente() {
    vistaAgente ??= import('./gerente/Agente.svelte').catch((error) => {
      console.error('[gerente] no se pudo bajar la vista del agente:', error);
      vistaAgente = null;
      throw error;
    });
    return vistaAgente;
  }

  function elegir(sucursal: Sucursal) {
    actualId = sucursal.id;
    recordarSucursal(sucursal.id);
  }

  function alPulsar(valor: string) {
    if (valor === 'salir') alSalir();
    else if (valor === 'ayuda') window.open(WHATSAPP_FRAGMENTLESS, '_blank', 'noopener');
    else if (
      valor === 'inicio' ||
      valor === 'pedidos' ||
      valor === 'restaurante' ||
      valor === 'menu' ||
      valor === 'mesas' ||
      valor === 'equipo' ||
      valor === 'cortes' ||
      valor === 'agente' ||
      valor === 'crear' ||
      valor === 'ajustes'
    ) {
      vista = valor;
    }
  }

  onMount(() => {
    // El saludo del agente para esta sucursal, si no hay uno que sirva (sin tope, el Worker regresa
    // nada sin llamar a OpenAI).
    if (actual.estado === 'funciona' && !haySaludo(actual.id, actual.hoy, saludoPorHora(actual.hora))) {
      prepararSaludo(actual.id, actual.hoy, saludoPorHora(actual.hora));
    }
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
</script>

{#if actual.estado !== 'funciona'}
  <Suscripcion sucursal={actual} otras={otrasQueFuncionan} alIr={elegir} {alSalir} />
{:else}
  <div class="panel">
    <BarraLateral
      subtitulo={plan ? `Plan ${plan}` : ''}
      opciones={[
        { valor: 'inicio', texto: 'Inicio', icono: 'inicio' },
        { valor: 'pedidos', texto: 'Pedidos', icono: 'bolsa', insignia: vigia?.insignia || undefined },
        { grupo: 'GENERAL' },
        { valor: 'restaurante', texto: 'Tu restaurante', icono: 'tienda' },
        { valor: 'menu', texto: 'Mi menú', icono: 'menu' },
        { valor: 'mesas', texto: 'Mesas', icono: 'mesas' },
        { valor: 'equipo', texto: 'Empleados', icono: 'usuarios' },
        { valor: 'cortes', texto: 'Cortes y reportes', icono: 'corte' },
        { valor: 'agente', texto: 'Agente IA', icono: 'ia', insignia: 'IA' },
        { valor: 'crear', texto: 'Crear contenido', icono: 'crear', insignia: 'IA' },
      ]}
      acciones={[
        { valor: 'ayuda', texto: 'Ayuda', icono: 'ayuda' },
        { valor: 'ajustes', texto: 'Ajustes', icono: 'ajustes' },
        { valor: 'salir', texto: 'Cerrar sesión', icono: 'salir' },
      ]}
      activa={vista === 'pos' || vista === 'caja' || vista === 'cocina' || vista === 'menu-en-linea' ? 'inicio' : vista}
      alElegir={alPulsar}
      pie={{
        inicial: nombre.charAt(0).toUpperCase(),
        nombre,
        linea: plan,
        alPulsar: () => (perfilAbierto = true),
      }}
    />

    {#if vista === 'pedidos'}
      {#if vigia}
        <Pedidos sucursal={actual} sucursales={datos.sucursales} {vigia} alElegir={elegir} />
      {:else}
        <BarraArriba titulo="Pedidos" estado={{ texto: 'Leyendo…', vivo: false }} />
      {/if}
    {:else if vista === 'restaurante'}
      <!-- Cada sucursal tiene sus datos y su horario: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <TuRestaurante sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} />
      {/key}
    {:else if vista === 'menu-en-linea'}
      <!-- Cada sucursal tiene su menú en línea: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <MenuEnLinea sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} alVolver={() => (vista = 'inicio')} />
      {/key}
    {:else if vista === 'menu'}
      <!-- Otra sucursal es otro menú: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Menu sucursal={actual} />
      {/key}
    {:else if vista === 'mesas'}
      <!-- Otra sucursal son otras mesas: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Mesas sucursal={actual} />
      {/key}
    {:else if vista === 'pos' || vista === 'caja' || vista === 'cocina'}
      <!-- Otra sucursal es otro punto de venta: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <AccesoAbierto que={vista} sucursal={actual} {usuarioId} alVolver={() => (vista = 'inicio')} />
      {/key}
    {:else if vista === 'equipo'}
      <!-- Otra sucursal es otro equipo: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Empleados sucursal={actual} {usuarioId} />
      {/key}
    {:else if vista === 'inicio'}
      <!-- Otra sucursal son otras mesas y otro equipo: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Inicio
          sucursal={actual}
          sucursales={datos.sucursales}
          {nombre}
          alElegir={elegir}
          alAbrir={(que) => (vista = que)}
          alIr={(a) => (vista = a)}
        />
      {/key}
    {:else if vista === 'cortes'}
      {#key actual.id}
        <Cortes sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} />
      {/key}
    {:else if vista === 'agente'}
      <!-- El Historial y las ventas son de cada sucursal: cambiar de sucursal abre su bienvenida. -->
      {#key actual.id}
        {#await cargarAgente() then { default: Agente }}
          <Agente sucursal={actual} sucursales={datos.sucursales} {nombre} alElegir={elegir} />
        {:catch error}
          <BarraArriba titulo="Agente IA" estado={{ texto: 'No se pudo abrir', vivo: false }} />
          <main class="cuerpo">
            <CajaError mensaje={esDeRed(error) ? SIN_CONEXION : 'No se pudo abrir el Agente IA. Vuelve a intentarlo.'} />
          </main>
        {/await}
      {/key}
    {:else if vista === 'crear'}
      <!-- Cada sucursal tiene sus propios 20 anuncios y su menú: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <CrearContenido sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} alIr={(a) => (vista = a)} />
      {/key}
    {:else}
      <!-- La hora de corte es de la sucursal; el chip dice de cuál. -->
      <BarraArriba titulo="Ajustes" estado={{ texto: actual.nombre, vivo: true }} />
      <main class="cuerpo">
        {#key actual.id}
          <Ajustes sucursal={actual} />
        {/key}
      </main>
    {/if}
  </div>

  {#if perfilAbierto}
    <Perfil
      nombre={actual.mi_nombre}
      apodo={datos.apodo}
      alCerrar={() => (perfilAbierto = false)}
      alGuardar={leer}
    />
  {/if}
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
