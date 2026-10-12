<!--
  El panel del distribuidor (libreta 8, paso 2), portado de la maqueta aprobada el 12 de octubre
  de 2026 (YXYVVNdLRXwgWCNErFSeyK): las piezas del panel de Fragmentless con la barra lateral de
  Juanito («Distribuidor» bajo el logo; Inicio, Clientes, Ajustes y Cerrar sesión, sin Ayuda; al
  pie su nombre y el correo de su sesión) y arriba solo Actualizar, con el chip de cuántos
  clientes tiene. Ajustes es el mismo del gerente, solo con el tema (decidido el 12 de octubre).
  Solo lee: no ve ventas ni gerentes, y no cambia nada.

  Si Fragmentless lo da de baja, en lugar de todo eso sale la pantalla de baja. Vuelve a leer su
  fila y sus clientes con Actualizar y cada vez que regresa a la pestaña, como el panel del
  gerente: así, en cuanto Fragmentless lo reactiva, vuelve solo a su panel.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import BarraArriba from '../diseno/BarraArriba.svelte';
  import BarraLateral from '../diseno/BarraLateral.svelte';
  import Boton from '../diseno/Boton.svelte';
  import { leerCuenta, leerPanelDistribuidor, type Cuenta, type DatosDistribuidor } from '../lib/distribuidor';
  import { plural } from '../lib/formato';
  import { SIN_PANEL } from '../lib/sesion';
  import Baja from './distribuidor/Baja.svelte';
  import Clientes from './distribuidor/Clientes.svelte';
  import Inicio from './distribuidor/Inicio.svelte';
  import Ajustes from './gerente/Ajustes.svelte';

  type Vista = 'inicio' | 'clientes' | 'ajustes';

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
    if (valor === 'salir') alSalir();
    else vista = valor as Vista;
  }

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

{#if !cuenta.activo}
  <Baja {alSalir} />
{:else}
  <div class="panel">
    <BarraLateral
      subtitulo="Distribuidor"
      opciones={[
        { valor: 'inicio', texto: 'Inicio', icono: 'inicio' },
        { valor: 'clientes', texto: 'Clientes', icono: 'tienda' },
      ]}
      acciones={[
        { valor: 'ajustes', texto: 'Ajustes', icono: 'ajustes' },
        { valor: 'salir', texto: 'Cerrar sesión', icono: 'salir' },
      ]}
      activa={vista}
      alElegir={elegir}
      pie={{ inicial: cuenta.nombre.charAt(0).toUpperCase(), nombre: cuenta.nombre, linea: correo }}
    />

    <BarraArriba titulo={TITULOS[vista]} {estado}>
      {#if vista !== 'ajustes'}
        <Boton etiqueta="Actualizar" icono="actualizar" apagado={leyendo} onclick={leer} />
      {/if}
    </BarraArriba>

    <main class="cuerpo">
      {#if vista === 'inicio'}
        <Inicio {datos} alVerClientes={() => (vista = 'clientes')} />
      {:else if vista === 'clientes'}
        <Clientes clientes={datos?.clientes ?? null} />
      {:else}
        <Ajustes />
      {/if}
    </main>
  </div>
{/if}

<style>
  .panel {
    position: relative;
    height: 100vh;
    height: 100dvh;
    overflow: hidden;
    background: var(--suelo);
  }

  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16),
     como en el panel de Fragmentless. */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
  }
</style>
