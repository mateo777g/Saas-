<!--
  El panel del distribuidor (libreta 8, paso 2), portado de la maqueta aprobada el 12 de octubre
  de 2026 (YXYVVNdLRXwgWCNErFSeyK): las piezas del panel de Fragmentless con la barra lateral de
  Juanito (Inicio, Clientes, Ajustes y Cerrar sesión, sin Ayuda; al pie su nombre y el correo de su
  sesión) y arriba solo Actualizar, con el chip de cuántos
  clientes tiene. Ajustes es el mismo del gerente, solo con el tema (decidido el 12 de octubre).
  Solo lee: no ve ventas ni gerentes, y no cambia nada.

  Desde el 8 de noviembre de 2026 su Inicio es como el de Fragmentless (saludo, búsqueda grande con Ctrl K,
  Abrir y Recientes, y debajo lo de antes) y anota sus vistas recientes en este navegador.

  Si Fragmentless lo da de baja, en lugar de todo eso sale la pantalla de baja. Vuelve a leer su
  fila y sus clientes con Actualizar y cada vez que regresa a la pestaña, como el panel del
  gerente: así, en cuanto Fragmentless lo reactiva, vuelve solo a su panel.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import Boton from '../diseno/Boton.svelte';
  import Marco from '../diseno/Marco.svelte';
  import { leerCuenta, leerPanelDistribuidor, type Cuenta, type DatosDistribuidor } from '../lib/distribuidor';
  import { plural } from '../lib/formato';
  import { SIN_PANEL } from '../lib/sesion';
  import { anotarReciente, type VistaDistribuidor } from '../lib/vistasDistribuidor';
  import Baja from './distribuidor/Baja.svelte';
  import Clientes from './distribuidor/Clientes.svelte';
  import Inicio from './distribuidor/Inicio.svelte';
  import Ajustes from './gerente/Ajustes.svelte';

  type Vista = VistaDistribuidor;

  let {
    usuarioId,
    correo,
    cuenta: inicial,
    alSalir,
    alSinAcceso,
  }: {
    usuarioId: string;
    correo: string;
    cuenta: Cuenta;
    alSalir: () => void;
    alSinAcceso: (mensaje: string) => void;
  } = $props();

  const TITULOS: Record<Vista, string> = { inicio: 'Inicio', clientes: 'Clientes', ajustes: 'Ajustes' };

  // La que llegó al entrar; después, la de cada nueva lectura.
  // svelte-ignore state_referenced_locally
  let cuenta = $state(inicial);
  let vista = $state<Vista>('inicio');
  let datos = $state<DatosDistribuidor | null>(null);
  let leyendo = $state(false);
  // Si se pide leer otra vez antes de que termine la lectura anterior, gana la última.
  let turno = 0;

  // Primero su fila: si ya no está ligada a ningún distribuidor, se le cierra la sesión; de baja,
  // sale la pantalla de baja y no se pide nada más (las funciones no le responderían). Si su fila
  // no se pudo leer, se queda la que había y se intentan leer sus clientes: sin internet, cada
  // parte dice que no se pudo.
  async function leer() {
    const mio = ++turno;
    leyendo = true;
    try {
      const nueva = await leerCuenta(usuarioId);
      if (mio !== turno) return;
      if (!nueva) {
        alSinAcceso(SIN_PANEL);
        return;
      }
      cuenta = nueva;
    } catch (error) {
      console.error('[distribuidor] no se pudo volver a leer su fila; se queda la que había:', error);
      if (mio !== turno) return;
    }
    if (cuenta.activo) {
      const nuevos = await leerPanelDistribuidor();
      if (mio !== turno) return;
      datos = nuevos;
    }
    leyendo = false;
  }

  // El chip de la barra de arriba: cuántos clientes tiene, con el punto verde; si no se pudo
  // leer, por qué.
  const estado = $derived.by(() => {
    if (vista === 'ajustes') return { texto: 'Se guardan en este navegador', vivo: true };
    if (!datos) return null;
    if (datos.resumen.ok) return { texto: plural(datos.resumen.datos.total, 'cliente', 'clientes'), vivo: true };
    return { texto: datos.resumen.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false };
  });

  function elegir(valor: string) {
    vista = valor as Vista;
  }

  // Ctrl K o la búsqueda chica de la barra: a Inicio, con la búsqueda grande abierta (como el panel de Fragmentless).
  let busquedaPedida = $state(false);

  function abrirBusqueda() {
    vista = 'inicio';
    busquedaPedida = true;
  }

  function tomarBusqueda() {
    const es = busquedaPedida;
    if (es) busquedaPedida = false;
    return es;
  }

  // Desde cualquier vista, menos con una ventana abierta.
  function alTeclear(e: KeyboardEvent) {
    if (!cuenta.activo) return;
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k' && !document.querySelector('dialog[open]')) {
      e.preventDefault();
      abrirBusqueda();
    }
  }

  $effect(() => {
    anotarReciente(vista);
  });

  onMount(() => {
    // Su fila ya se leyó al entrar; solo faltan sus clientes.
    if (cuenta.activo) leer();
    const alVolver = () => {
      if (document.visibilityState === 'visible') leer();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => document.removeEventListener('visibilitychange', alVolver);
  });
</script>

<svelte:window onkeydown={alTeclear} />

{#if !cuenta.activo}
  <Baja {alSalir} />
{:else}
  <Marco
    opciones={[
      { valor: 'inicio', texto: 'Inicio', icono: 'r-inicio' },
      { valor: 'clientes', texto: 'Clientes', icono: 'r-tienda' },
    ]}
    acciones={[{ valor: 'ajustes', texto: 'Ajustes', icono: 'r-ajustes' }]}
    activa={vista}
    alElegir={elegir}
    {alSalir}
    alBuscar={abrirBusqueda}
    pie={{ inicial: cuenta.nombre.charAt(0).toUpperCase(), nombre: cuenta.nombre, linea: correo }}
  >

    <BarraArriba titulo={TITULOS[vista]} {estado}>
      {#if vista !== 'ajustes'}
        <Boton etiqueta="Actualizar" icono="actualizar" apagado={leyendo} onclick={leer} />
      {/if}
    </BarraArriba>

    {#if vista === 'inicio'}
      <Inicio {datos} nombre={cuenta.nombre} {tomarBusqueda} alIr={(v) => (vista = v)} />
    {:else}
      <main class="cuerpo">
        {#if vista === 'clientes'}
          <Clientes clientes={datos?.clientes ?? null} />
        {:else}
          <Ajustes />
        {/if}
      </main>
    {/if}
  </Marco>
{/if}

<style>
  /* Como en el panel de Fragmentless. */
  .cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: var(--vista-abajo);
  }
</style>
