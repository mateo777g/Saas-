<!--
  El candado de una fila (maqueta de Empleados): un PIN nuevo para alguien del equipo, que también
  lo desbloquea, o el propio PIN del gerente, con el que autoriza cancelaciones y descuentos. El
  Worker lo mezcla con su llave antes de que llegue a Postgres; aquí nunca se guarda.
-->
<script lang="ts">
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ponerPin, type Persona } from '../../../lib/equipo';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import CampoPin from './CampoPin.svelte';

  let {
    persona,
    alCambiar,
    alCerrar,
  }: { persona: Persona; alCambiar: () => void; alCerrar: () => void } = $props();

  // svelte-ignore state_referenced_locally
  const p = persona;
  let pin = $state('');
  let paso = $state<null | 'guardando' | 'listo'>(null);

  function cerrar() {
    if (!paso) alCerrar();
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    if (!/^\d{4}$/.test(pin)) return { error: 'El PIN son 4 números.' };
    paso = 'guardando';
    try {
      await ponerPin(p.id, pin);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[equipo] no se pudo guardar el PIN:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alCambiar();
    return { listo: 'Guardado' };
  }
</script>

<Ventana
  etiqueta={paso === 'guardando' ? 'GUARDANDO…' : p.yo ? 'TU PIN' : 'PIN NUEVO'}
  titulo={p.yo ? 'Tu PIN' : p.nombre}
  ancho={440}
  alCerrar={cerrar}
>
  <Formulario boton={{ etiqueta: 'Guardar PIN', icono: 'check' }} {guardar} alTerminar={alCerrar} antesDelBoton={28}>
    <CampoPin
      id="pin-nuevo"
      etiqueta={p.yo && p.tienePin ? 'PIN NUEVO' : 'PIN'}
      bind:valor={pin}
      pista={p.yo
        ? 'Con tu PIN autorizas cancelaciones y descuentos en los aparatos de tu equipo.'
        : 'Díselo en persona. Si su PIN estaba bloqueado, con el nuevo vuelve a entrar.'}
    />
  </Formulario>
</Ventana>
