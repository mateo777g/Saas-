<!--
  Tu panel (libreta 8, pasos 1 y 2), portado de la maqueta aprobada el 10 de octubre de 2026
  (Tbt7H3G1QRXykzNKe1GXHh): suelo liso, la barra lateral de vidrio con Inicio, Clientes,
  Distribuidores y Cerrar sesión, la barra de arriba con el chip de cuántos restaurantes (o
  distribuidores) hay, Actualizar y Dar de alta (Nuevo distribuidor en Distribuidores), y debajo
  la vista elegida.

  Lee todo de una vez al abrir, con Actualizar y después de cada cambio (lib/panel.ts). Las
  ventanas escriben en Saas-Restaurantes de verdad.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import BarraLateral from '../diseno/BarraLateral.svelte';
  import Boton from '../diseno/Boton.svelte';
  import { plural } from '../lib/formato';
  import { leerPanel, type Cliente, type DatosPanel, type Distribuidor } from '../lib/panel';
  import AltaDistribuidor from './fragmentless/AltaDistribuidor.svelte';
  import AltaRestaurante from './fragmentless/AltaRestaurante.svelte';
  import BajaOReactivar from './fragmentless/BajaOReactivar.svelte';
  import Clientes from './fragmentless/Clientes.svelte';
  import ClientesDistribuidor from './fragmentless/ClientesDistribuidor.svelte';
  import CorregirDistribuidor from './fragmentless/CorregirDistribuidor.svelte';
  import Distribuidores, { type AccionDistribuidor } from './fragmentless/Distribuidores.svelte';
  import Inicio from './fragmentless/Inicio.svelte';
  import LigarCuenta from './fragmentless/LigarCuenta.svelte';
  import LigarGerente from './fragmentless/LigarGerente.svelte';
  import PausarCorregir from './fragmentless/PausarCorregir.svelte';
  import SumarMeses from './fragmentless/SumarMeses.svelte';

  type Vista = 'inicio' | 'clientes' | 'distribuidores';
  type VentanaAbierta =
    | { tipo: 'alta' | 'alta-distribuidor' }
    | { tipo: 'ligar' | 'sumar' | 'fijar'; cliente: Cliente }
    | { tipo: 'distribuidor'; accion: AccionDistribuidor; distribuidor: Distribuidor };

  let { correo, alSalir }: { correo: string; alSalir: () => void } = $props();

  const TITULOS: Record<Vista, string> = { inicio: 'Inicio', clientes: 'Clientes', distribuidores: 'Distribuidores' };

  let vista = $state<Vista>('inicio');
  let datos = $state<DatosPanel | null>(null);
  let leyendo = $state(false);
  let ventana = $state<VentanaAbierta | null>(null);
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
  // distribuidores), con el punto verde; si no se pudo leer, por qué.
  const estado = $derived.by(() => {
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
    if (valor === 'salir') alSalir();
    else vista = valor as Vista;
  }

  const cerrarVentana = () => (ventana = null);

  // Sus clientes no se cierra al asignar o quitar; si se cierra antes de que el panel se vuelva a
  // leer, se lee al cerrar.
  function cerrarYLeer() {
    ventana = null;
    leer();
  }

  onMount(leer);
</script>

<div class="panel">
  <BarraLateral
    subtitulo="Plataforma"
    opciones={[
      { valor: 'inicio', texto: 'Inicio', icono: 'inicio' },
      { valor: 'clientes', texto: 'Clientes', icono: 'tienda' },
      { valor: 'distribuidores', texto: 'Distribuidores', icono: 'usuarios' },
    ]}
    acciones={[{ valor: 'salir', texto: 'Cerrar sesión', icono: 'salir' }]}
    activa={vista}
    alElegir={elegir}
    pie={{ inicial: 'F', nombre: 'Fragmentless', linea: correo }}
  />

  <BarraArriba titulo={TITULOS[vista]} {estado}>
    <Boton etiqueta="Actualizar" icono="actualizar" apagado={leyendo} onclick={leer} />
    {#if vista === 'distribuidores'}
      <Boton etiqueta="Nuevo distribuidor" icono="mas" tono="tinta" onclick={() => (ventana = { tipo: 'alta-distribuidor' })} />
    {:else}
      <Boton etiqueta="Dar de alta" icono="mas" tono="tinta" onclick={() => (ventana = { tipo: 'alta' })} />
    {/if}
  </BarraArriba>

  <main class="cuerpo">
    {#if vista === 'inicio'}
      <Inicio
        {datos}
        alSumar={(cliente) => (ventana = { tipo: 'sumar', cliente })}
        alVerClientes={() => (vista = 'clientes')}
        alVerDistribuidores={() => (vista = 'distribuidores')}
      />
    {:else if vista === 'clientes'}
      <Clientes
        clientes={datos?.clientes ?? null}
        alLigar={(cliente) => (ventana = { tipo: 'ligar', cliente })}
        alSumar={(cliente) => (ventana = { tipo: 'sumar', cliente })}
        alFijar={(cliente) => (ventana = { tipo: 'fijar', cliente })}
      />
    {:else}
      <Distribuidores
        distribuidores={datos?.distribuidores ?? null}
        alElegir={(accion, distribuidor) => (ventana = { tipo: 'distribuidor', accion, distribuidor })}
      />
    {/if}
  </main>

  {#if ventana?.tipo === 'alta'}
    <AltaRestaurante alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'ligar'}
    <LigarGerente cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'sumar'}
    <SumarMeses cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
  {:else if ventana?.tipo === 'fijar'}
    <PausarCorregir cliente={ventana.cliente} alCerrar={cerrarVentana} alGuardar={leer} />
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
</div>

<style>
  .panel {
    position: relative;
    height: 100vh;
    height: 100dvh;
    overflow: hidden;
    background: var(--suelo);
  }

  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16).
     Sin desplazamiento propio, como en la maqueta: cortaría la sombra de las tarjetas. Lo que no
     cabe se desplaza dentro de cada tabla. */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
  }
</style>
