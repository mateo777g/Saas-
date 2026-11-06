<!--
  El panel del gerente (rediseño del 5 de noviembre de 2026; maqueta V64Pv4gmANPRZuJW5hTe5D): el marco
  liso con la barra lateral por grupos (Inicio; OPERACIÓN; TU NEGOCIO; IA Y CONTENIDO; abajo, Ayuda, Ajustes
  y la persona, que abre su Perfil) y cada vista con su propia barra de arriba. Al entrar al panel se
  prepara el saludo del agente, para que salga al instante. «Abrir» en Inicio abre ahí mismo el punto de
  venta, la caja o la cocina, con su sesión (maqueta Mesero y cocina TYq97pKacRCYBqcvRp1bZ2). Ctrl K, desde
  cualquier vista, lleva a Inicio y abre su búsqueda. Si la sucursal en la que está no funciona hoy
  (vencida o pausada, lo dice Postgres), en lugar de todo eso sale la suscripción terminada.

  Vuelve a leer cada vez que Don Chuy regresa a la pestaña (decidido el 11 de octubre de 2026):
  así el saludo sigue la hora y una licencia que venció con el panel abierto se nota en cuanto
  vuelve, y una que Fragmentless renovó regresa sola al panel. Si en ese momento no hay
  internet, se queda lo que ya se veía.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import Marco from '../diseno/Marco.svelte';
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
  import { anotarReciente, type Destino, type NuevoAlEntrar } from '../lib/vistas';
  import CajaError from '../diseno/CajaError.svelte';
  import { esDeRed, SIN_CONEXION } from '../lib/errores';
  import AccesoAbierto from './gerente/AccesoAbierto.svelte';
  import Ajustes from './gerente/Ajustes.svelte';
  import Biblioteca from './gerente/Biblioteca.svelte';
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
    | 'biblioteca'
    | 'ajustes'
    | 'pos'
    | 'caja'
    | 'cocina'
    | 'menu-en-linea'
  >('inicio');
  let perfilAbierto = $state(false);
  // Ctrl K o la búsqueda chica de la barra: Inicio abre la grande y lo toma una vez.
  let busquedaPedida = $state(false);
  // La ventana que se abre al llegar a una vista (Agregar producto en la búsqueda); la vista la toma una vez.
  let nuevoAlEntrar: NuevoAlEntrar | null = null;

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
    if (valor === 'ayuda') window.open(WHATSAPP_FRAGMENTLESS, '_blank', 'noopener');
    else if (
      valor === 'inicio' ||
      valor === 'pedidos' ||
      valor === 'restaurante' ||
      valor === 'menu-en-linea' ||
      valor === 'menu' ||
      valor === 'mesas' ||
      valor === 'equipo' ||
      valor === 'cortes' ||
      valor === 'agente' ||
      valor === 'crear' ||
      valor === 'biblioteca' ||
      valor === 'ajustes'
    ) {
      vista = valor;
    }
  }

  function irA(destino: Destino) {
    if (destino.vista === 'ayuda') {
      alPulsar('ayuda');
      return;
    }
    nuevoAlEntrar = destino.nuevo ?? null;
    vista = destino.vista;
  }

  function tomarNuevo(cual: NuevoAlEntrar) {
    const es = nuevoAlEntrar === cual;
    if (es) nuevoAlEntrar = null;
    return es;
  }

  function abrirBusqueda() {
    vista = 'inicio';
    busquedaPedida = true;
  }

  function tomarBusqueda() {
    const es = busquedaPedida;
    if (es) busquedaPedida = false;
    return es;
  }

  // Desde cualquier vista, menos con una ventana abierta: se perdería lo que lleva escrito.
  function alTeclear(e: KeyboardEvent) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k' && !document.querySelector('dialog[open]')) {
      e.preventDefault();
      abrirBusqueda();
    }
  }

  $effect(() => {
    anotarReciente(actual.id, vista);
  });

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

<svelte:window onkeydown={actual.estado === 'funciona' ? alTeclear : undefined} />

{#if actual.estado !== 'funciona'}
  <Suscripcion sucursal={actual} otras={otrasQueFuncionan} alIr={elegir} {alSalir} />
{:else}
  <Marco
    opciones={[
      { valor: 'inicio', texto: 'Inicio', icono: 'r-inicio' },
      { grupo: 'OPERACIÓN' },
      { valor: 'pedidos', texto: 'Pedidos', icono: 'r-bolsa', insignia: vigia?.insignia || undefined },
      { valor: 'mesas', texto: 'Mesas', icono: 'r-mesas' },
      { valor: 'cortes', texto: 'Cortes y reportes', icono: 'r-corte' },
      { grupo: 'TU NEGOCIO' },
      { valor: 'restaurante', texto: 'Tu restaurante', icono: 'r-tienda' },
      { valor: 'menu-en-linea', texto: 'Tu menú en línea', icono: 'r-celular' },
      { valor: 'menu', texto: 'Mi menú', icono: 'r-menu' },
      { valor: 'equipo', texto: 'Empleados', icono: 'r-usuarios' },
      { grupo: 'IA Y CONTENIDO' },
      { valor: 'agente', texto: 'Agente IA', icono: 'r-ia', insignia: 'IA' },
      { valor: 'crear', texto: 'Crear anuncios', icono: 'r-crear', insignia: 'IA' },
      { valor: 'biblioteca', texto: 'Mi biblioteca', icono: 'r-biblio' },
    ]}
    acciones={[
      { valor: 'ayuda', texto: 'Ayuda', icono: 'r-ayuda' },
      { valor: 'ajustes', texto: 'Ajustes', icono: 'r-ajustes' },
    ]}
    activa={vista === 'pos' || vista === 'caja' || vista === 'cocina' ? 'inicio' : vista}
    alElegir={alPulsar}
    alBuscar={abrirBusqueda}
    {alSalir}
    pie={{
      inicial: nombre.charAt(0).toUpperCase(),
      nombre,
      linea: plan ? `Plan ${plan}` : '',
      alPulsar: () => (perfilAbierto = true),
    }}
  >

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
        <MenuEnLinea sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} />
      {/key}
    {:else if vista === 'menu'}
      <!-- Otra sucursal es otro menú: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Menu sucursal={actual} abrirNuevo={() => tomarNuevo('producto')} />
      {/key}
    {:else if vista === 'mesas'}
      <!-- Otra sucursal son otras mesas: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Mesas sucursal={actual} abrirNueva={() => tomarNuevo('mesa')} />
      {/key}
    {:else if vista === 'pos' || vista === 'caja' || vista === 'cocina'}
      <!-- Otra sucursal es otro punto de venta: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <AccesoAbierto que={vista} sucursal={actual} {usuarioId} alVolver={() => (vista = 'inicio')} />
      {/key}
    {:else if vista === 'equipo'}
      <!-- Otra sucursal es otro equipo: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Empleados sucursal={actual} {usuarioId} abrirNuevo={() => tomarNuevo('empleado')} />
      {/key}
    {:else if vista === 'inicio'}
      <!-- Otra sucursal son otras mesas y otro equipo: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Inicio
          sucursal={actual}
          sucursales={datos.sucursales}
          {nombre}
          {tomarBusqueda}
          alElegir={elegir}
          alAbrir={(que) => (vista = que)}
          alIr={irA}
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
          <Agente sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} />
        {:catch error}
          <BarraArriba titulo="Agente IA" estado={{ texto: 'No se pudo abrir', vivo: false }} />
          <main class="cuerpo">
            <CajaError mensaje={esDeRed(error) ? SIN_CONEXION : 'No se pudo abrir el Agente IA. Vuelve a intentarlo.'} />
          </main>
        {/await}
      {/key}
    {:else if vista === 'crear'}
      <!-- Cada sucursal tiene sus propios anuncios y su menú: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <CrearContenido sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} alIr={(a) => (vista = a)} />
      {/key}
    {:else if vista === 'biblioteca'}
      <!-- Cada sucursal tiene su biblioteca: se vuelve a abrir desde cero. -->
      {#key actual.id}
        <Biblioteca sucursal={actual} sucursales={datos.sucursales} alElegir={elegir} alIr={(a) => (vista = a)} />
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
  </Marco>

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
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
  }
</style>
