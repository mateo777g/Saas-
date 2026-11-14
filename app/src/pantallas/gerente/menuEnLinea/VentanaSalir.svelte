<!--
  «Tienes cambios sin guardar» (maqueta UDArhiEZceT7rmSKxqRA5r v59, 11 nov 2026, versión 27): sale si Don Chuy se va de
  «Tu menú en línea» (la barra lateral, la búsqueda, otra sucursal, cerrar sesión) con cambios sin guardar. Como las de
  confirmar del panel: angosta, el título en dos renglones, el texto a todo lo ancho en dos párrafos balanceados y los
  dos botones en las orillas: «Salir sin guardar» en el rojo de contorno y «Guardar y salir» en verde.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';

  let {
    cambios,
    alSalir,
    alGuardar,
    alCerrar,
  }: {
    cambios: number;
    alSalir: () => void;
    // Guarda; si no se pudo, regresa el error y la ventana se queda.
    alGuardar: () => Promise<string | null>;
    alCerrar: () => void;
  } = $props();

  let paso = $state<null | 'guardando' | 'listo'>(null);
  let error = $state<string | null>(null);

  async function guardarYSalir() {
    if (paso) return;
    error = null;
    paso = 'guardando';
    const fallo = await alGuardar();
    if (fallo) {
      error = fallo;
      paso = null;
      return;
    }
    paso = 'listo';
    setTimeout(alSalir, 500);
  }
</script>

<Ventana centrado titulo="Tienes cambios sin guardar" ancho={460} alCerrar={() => paso === null && alCerrar()}>
  <div class="salir-sin-guardar">
    <p>Llevas {cambios} {cambios === 1 ? 'cambio' : 'cambios'} en tu menú en línea.</p>
    <p>Si sales sin guardar, tus clientes lo siguen viendo como estaba.</p>
    {#if error}<div class="error"><CajaError mensaje={error} /></div>{/if}
    <div class="pie">
      <Boton etiqueta="Salir sin guardar" icono="salir" tono="peligro" apagado={paso !== null} onclick={alSalir} />
      <Boton
        etiqueta={paso === 'guardando' ? 'Guardando…' : paso === 'listo' ? 'Guardado' : 'Guardar y salir'}
        tono="verde"
        cargando={paso === 'guardando'}
        exito={paso === 'listo'}
        onclick={guardarYSalir}
      />
    </div>
  </div>
</Ventana>

<style>
  .salir-sin-guardar {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding-top: 10px;
    text-align: center;
  }

  p {
    margin: 0;
    font-size: 13.5px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--suave);
    text-wrap: balance;
  }

  .error {
    margin-top: 14px;
    text-align: left;
  }

  .pie {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    margin-top: 24px;
  }
</style>
