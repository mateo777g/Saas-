<!--
  «Tienes cambios sin guardar» del recetario (maqueta DFVTWEB3eZBEKctyxWjGjg v1; «Lo que decidí yo» 9 de las encuestas):
  la misma ventana de «Tu menú en línea» y «Tu restaurante» (restaurante/VentanaSalir.svelte), con el texto del
  recetario. Sale si Don Chuy se va de «Editar» con cambios («‹ Recetario», otra sección del dock, la barra lateral, la
  búsqueda, otra sucursal, cerrar sesión): «Salir sin guardar» en el rojo de contorno y «Guardar y salir» en verde.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';

  let {
    nombre,
    alSalir,
    alGuardar,
    alCerrar,
  }: {
    nombre: string; // «Taco al pastor»
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
    <div class="textos">
      <p>Cambiaste el recetario de {nombre} y no lo has guardado.</p>
      <p>Si sales ahora, se pierden tus cambios.</p>
      {#if error}<div class="error"><CajaError mensaje={error} /></div>{/if}
    </div>
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
  /* Como en la maqueta: el texto a 22 de la cabeza, 16 entre renglón y renglón, y los botones a 28. */
  .salir-sin-guardar {
    display: flex;
    flex-direction: column;
    text-align: center;
  }

  .textos {
    display: flex;
    flex-direction: column;
    gap: 16px;
    margin-top: 22px;
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
    text-align: left;
  }

  .pie {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    margin-top: 28px;
  }
</style>
