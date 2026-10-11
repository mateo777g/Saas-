<!--
  Tu panel (libreta 8, paso 1), portado de la maqueta aprobada el 10 de octubre de 2026
  (Tbt7H3G1QRXykzNKe1GXHh): suelo liso, la barra lateral de vidrio con Inicio, Clientes y
  Cerrar sesión, la barra de arriba con el chip de cuántos restaurantes hay, Actualizar y Dar de
  alta, y debajo la vista elegida. La vista Distribuidores llega con el paso 2.

  Lee todo de una vez al abrir, con Actualizar y después de cada cambio (lib/panel.ts). Las
  ventanas escriben en Saas-Restaurantes de verdad.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import BarraLateral from '../diseno/BarraLateral.svelte';
  import Boton from '../diseno/Boton.svelte';
  import { plural } from '../lib/formato';
  import { leerPanel, type Cliente, type DatosPanel } from '../lib/panel';
  import AltaRestaurante from './fragmentless/AltaRestaurante.svelte';
  import Clientes from './fragmentless/Clientes.svelte';
  import Inicio from './fragmentless/Inicio.svelte';
  import LigarGerente from './fragmentless/LigarGerente.svelte';
  import PausarCorregir from './fragmentless/PausarCorregir.svelte';
  import SumarMeses from './fragmentless/SumarMeses.svelte';

  type Vista = 'inicio' | 'clientes';
  type VentanaAbierta =
    | { tipo: 'alta' }
    | { tipo: 'ligar' | 'sumar' | 'fijar'; cliente: Cliente };

  let { correo, alSalir }: { correo: string; alSalir: () => void } = $props();

  const TITULOS: Record<Vista, string> = { inicio: 'Inicio', clientes: 'Clientes' };

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

  // El chip de la barra de arriba: cuántos restaurantes hay, con el punto verde; si no se pudo
  // leer, por qué.
  const estado = $derived.by(() => {
    if (!datos) return null;
    if (datos.resumen.ok) return { texto: plural(datos.resumen.datos.total, 'restaurante', 'restaurantes'), vivo: true };
    return { texto: datos.resumen.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
  });

  function elegir(valor: string) {
    if (valor === 'salir') alSalir();
    else vista = valor as Vista;
  }

  const cerrarVentana = () => (ventana = null);

  onMount(leer);
</script>

<div class="panel">
  <BarraLateral
    subtitulo="Plataforma"
    opciones={[
      { valor: 'inicio', texto: 'Inicio', icono: 'inicio' },
      { valor: 'clientes', texto: 'Clientes', icono: 'tienda' },
    ]}
    acciones={[{ valor: 'salir', texto: 'Cerrar sesión', icono: 'salir' }]}
    activa={vista}
    alElegir={elegir}
    pie={{ inicial: 'F', nombre: 'Fragmentless', linea: correo }}
  />

  <BarraArriba titulo={TITULOS[vista]} {estado}>
    <Boton etiqueta="Actualizar" icono="actualizar" apagado={leyendo} onclick={leer} />
    <Boton etiqueta="Dar de alta" icono="mas" tono="tinta" onclick={() => (ventana = { tipo: 'alta' })} />
  </BarraArriba>

  <main class="cuerpo">
    {#if vista === 'inicio'}
      <Inicio
        {datos}
        alSumar={(cliente) => (ventana = { tipo: 'sumar', cliente })}
        alVerClientes={() => (vista = 'clientes')}
      />
    {:else}
      <Clientes
        clientes={datos?.clientes ?? null}
        alLigar={(cliente) => (ventana = { tipo: 'ligar', cliente })}
        alSumar={(cliente) => (ventana = { tipo: 'sumar', cliente })}
        alFijar={(cliente) => (ventana = { tipo: 'fijar', cliente })}
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
