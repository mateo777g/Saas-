<!--
  Tu panel (libreta 8, pasos 1 y 2), portado de la maqueta aprobada el 10 de octubre de 2026
  (Tbt7H3G1QRXykzNKe1GXHh): suelo liso, la barra lateral de vidrio con Inicio, Clientes,
  Distribuidores, Ajustes y Cerrar sesión, la barra de arriba con el chip de cuántos restaurantes
  (o distribuidores) hay, Actualizar y Dar de alta (Nuevo distribuidor en Distribuidores), y
  debajo la vista elegida. Ajustes es el mismo del gerente, solo con el tema, y arriba solo lleva
  su chip (decidido el 12 de octubre de 2026). Estilos (parte 7a, maqueta H2yFVjosPvSV56DJD1Un71)
  va después de Distribuidores y trae su propia barra de arriba, sus lecturas y sus ventanas.

  Lee todo de una vez al abrir, con Actualizar y después de cada cambio (lib/panel.ts). Las
  ventanas escriben en Saas-Restaurantes de verdad.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import Boton from '../diseno/Boton.svelte';
  import Marco from '../diseno/Marco.svelte';
  import { plural } from '../lib/formato';
  import { leerPanel, type Cliente, type DatosPanel, type Distribuidor } from '../lib/panel';
  import { anotarReciente, MI_NOMBRE, type DestinoPanel, type VistaPanel } from '../lib/vistasFragmentless';
  import AltaDistribuidor from './fragmentless/AltaDistribuidor.svelte';
  import AltaRestaurante from './fragmentless/AltaRestaurante.svelte';
  import BajaOReactivar from './fragmentless/BajaOReactivar.svelte';
  import Clientes from './fragmentless/Clientes.svelte';
  import ClientesDistribuidor from './fragmentless/ClientesDistribuidor.svelte';
  import CorregirDistribuidor from './fragmentless/CorregirDistribuidor.svelte';
  import Distribuidores, { type AccionDistribuidor } from './fragmentless/Distribuidores.svelte';
  import Estilos from './fragmentless/Estilos.svelte';
  import Inicio from './fragmentless/Inicio.svelte';
  import LigarCuenta from './fragmentless/LigarCuenta.svelte';
  import LigarGerente from './fragmentless/LigarGerente.svelte';
  import PausarCorregir from './fragmentless/PausarCorregir.svelte';
  import SumarMeses from './fragmentless/SumarMeses.svelte';
  import TopeIa from './fragmentless/TopeIa.svelte';
  import Ajustes from './gerente/Ajustes.svelte';

  type Vista = VistaPanel;
  type VentanaAbierta =
    | { tipo: 'alta' | 'alta-distribuidor' }
    | { tipo: 'ligar' | 'sumar' | 'fijar' | 'tope'; cliente: Cliente }
    | { tipo: 'distribuidor'; accion: AccionDistribuidor; distribuidor: Distribuidor };

  let { correo, alSalir }: { correo: string; alSalir: () => void } = $props();

  const TITULOS: Record<Exclude<Vista, 'estilos'>, string> = {
    inicio: 'Inicio',
    clientes: 'Clientes',
    distribuidores: 'Distribuidores',
    ajustes: 'Ajustes',
  };

  let vista = $state<Vista>('inicio');
  let datos = $state<DatosPanel | null>(null);
  let leyendo = $state(false);
  let ventana = $state<VentanaAbierta | null>(null);
  // Ctrl K o la búsqueda chica de la barra: Inicio abre la grande y lo toma una vez.
  let busquedaPedida = $state(false);
  // «Nuevo estilo» en la búsqueda o en Atajos: Estilos abre su ventana al llegar y lo toma una vez.
  let estiloPedido = false;
  // Si se pide leer otra vez antes de que termine la lectura anterior, gana la última.
  let turno = 0;

  async function leer() {
    const mio = ++turno;
    leyendo = true;
    const nuevos = await leerPanel();
    if (mio !== turno) return;
    datos = nuevos;
    leyendo = false;
  }

  // El chip de la barra de arriba: cuántos restaurantes hay (en Distribuidores, cuántos
  // distribuidores), con el punto verde; si no se pudo leer, por qué. En Ajustes, el del gerente.
  const estado = $derived.by(() => {
    if (vista === 'ajustes') return { texto: 'Se guardan en este navegador', vivo: true };
    if (!datos) return null;
    if (vista === 'distribuidores') {
      const d = datos.distribuidores;
      if (d.ok) return { texto: plural(d.datos.length, 'distribuidor', 'distribuidores'), vivo: true };
      return { texto: d.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
    }
    if (datos.resumen.ok) return { texto: plural(datos.resumen.datos.total, 'restaurante', 'restaurantes'), vivo: true };
    return { texto: datos.resumen.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
  });

  function elegir(valor: string) {
    vista = valor as Vista;
  }

  function ir(destino: DestinoPanel) {
    vista = destino.vista;
    if (destino.nuevo === 'estilo') estiloPedido = true;
    else if (destino.nuevo) ventana = { tipo: destino.nuevo };
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

  function tomarEstilo() {
    const es = estiloPedido;
    estiloPedido = false;
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
    anotarReciente(vista);
  });

  const cerrarVentana = () => (ventana = null);

  // Sus clientes no se cierra al asignar o quitar; si se cierra antes de que el panel se vuelva a
  // leer, se lee al cerrar.
  function cerrarYLeer() {
    ventana = null;
    leer();
  }

  onMount(leer);
</script>

<svelte:window onkeydown={alTeclear} />

<Marco
  opciones={[
    { valor: 'inicio', texto: 'Inicio', icono: 'r-inicio' },
    { valor: 'clientes', texto: 'Clientes', icono: 'r-tienda' },
    { valor: 'distribuidores', texto: 'Distribuidores', icono: 'r-usuarios' },
    { valor: 'estilos', texto: 'Estilos', icono: 'r-biblio' },
  ]}
  acciones={[{ valor: 'ajustes', texto: 'Ajustes', icono: 'r-ajustes' }]}
  activa={vista}
  alElegir={elegir}
  {alSalir}
  alBuscar={abrirBusqueda}
  pie={{ inicial: MI_NOMBRE.charAt(0), nombre: MI_NOMBRE, linea: correo }}
>

  {#if vista === 'estilos'}
    <Estilos {tomarEstilo} />
  {:else}
    <BarraArriba titulo={TITULOS[vista]} {estado}>
      {#if vista !== 'ajustes'}
        <Boton etiqueta="Actualizar" icono="actualizar" apagado={leyendo} onclick={leer} />
      {/if}
      {#if vista === 'distribuidores'}
        <Boton etiqueta="Nuevo distribuidor" icono="mas" tono="tinta" onclick={() => (ventana = { tipo: 'alta-distribuidor' })} />
      {:else if vista !== 'ajustes'}
        <Boton etiqueta="Dar de alta" icono="mas" tono="tinta" onclick={() => (ventana = { tipo: 'alta' })} />
      {/if}
    </BarraArriba>

    {#if vista === 'inicio'}
      <Inicio {datos} {tomarBusqueda} alIr={ir} alSumar={(cliente) => (ventana = { tipo: 'sumar', cliente })} />
    {:else}
    <main class="cuerpo">
      {#if vista === 'clientes'}
        <Clientes
          clientes={datos?.clientes ?? null}
          alLigar={(cliente) => (ventana = { tipo: 'ligar', cliente })}
          alSumar={(cliente) => (ventana = { tipo: 'sumar', cliente })}
          alFijar={(cliente) => (ventana = { tipo: 'fijar', cliente })}
          alTope={(cliente) => (ventana = { tipo: 'tope', cliente })}
        />
      {:else if vista === 'distribuidores'}
        <Distribuidores
          distribuidores={datos?.distribuidores ?? null}
          alElegir={(accion, distribuidor) => (ventana = { tipo: 'distribuidor', accion, distribuidor })}
        />
      {:else}
        <Ajustes />
      {/if}
    </main>
    {/if}
  {/if}

  {#if ventana?.tipo === 'alta'}
    <AltaRestaurante alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'ligar'}
    <LigarGerente cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'sumar'}
    <SumarMeses cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'fijar'}
    <PausarCorregir cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'tope'}
    <TopeIa cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'alta-distribuidor'}
    <AltaDistribuidor alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'distribuidor'}
    {#if ventana.accion === 'ligar'}
      <LigarCuenta distribuidor={ventana.distribuidor} alCerrar={cerrarVentana} alGuardar={leer} />
    {:else if ventana.accion === 'clientes'}
      <ClientesDistribuidor distribuidor={ventana.distribuidor} {datos} alCerrar={cerrarYLeer} alCambiar={leer} />
    {:else if ventana.accion === 'corregir'}
      <CorregirDistribuidor distribuidor={ventana.distribuidor} alCerrar={cerrarVentana} alGuardar={leer} />
    {:else}
      <BajaOReactivar
        distribuidor={ventana.distribuidor}
        baja={ventana.accion === 'baja'}
        alCerrar={cerrarVentana}
        alGuardar={leer}
      />
    {/if}
  {/if}
</Marco>

<style>
  /* Sin desplazamiento propio, como en la maqueta: lo que no cabe se desplaza dentro de cada tabla. */
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
  }
</style>
