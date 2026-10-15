<!--
  Nueva mesa y Editar mesa (maqueta de Mesas 4TKmJzMwyWMCAVU2MwEDwc), que es dialogo_mesa.py de
  Flet: un solo campo, porque una mesa solo tiene nombre. Arriba la etiqueta (GUARDANDO… mientras
  guarda), el título y la X; el nombre; la caja de error; y el botón, que se pone verde al
  terminar. Un nombre repetido se avisa antes de guardar, aunque cambien las mayúsculas.
-->
<script lang="ts">
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { crearMesa, renombrarMesa, type Mesa } from '../../../lib/mesas';

  let {
    restauranteId,
    mesa,
    mesas,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    mesa: Mesa | null;
    mesas: Mesa[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = mesa;
  let nombre = $state(inicial?.nombre ?? '');
  let paso = $state<null | 'guardando' | 'listo'>(null);

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const limpio = nombre.trim();
    const repetida = mesas.find((m) => m.id !== inicial?.id && m.nombre.toLowerCase() === limpio.toLowerCase());
    if (!limpio) return { error: 'Escribe un nombre para la mesa.' };
    if (repetida) return { error: `Ya tienes una mesa que se llama «${repetida.nombre}».` };

    paso = 'guardando';
    try {
      if (inicial) await renombrarMesa(inicial.id, limpio);
      else await crearMesa(restauranteId, limpio);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[mesas] no se pudo guardar la mesa:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'Agregada' };
  }
</script>

<Ventana
  etiqueta={paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR MESA' : 'NUEVA MESA'}
  titulo={inicial ? inicial.nombre : 'Agrega una mesa'}
  ancho={440}
  alCerrar={cerrar}
>
  <Formulario
    boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar mesa', icono: 'mas' }}
    {guardar}
    alTerminar={alCerrar}
    antesDelBoton={28}
  >
    <Campo id="mesa-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. «Mesa 6» o «Barra 1»" />
  </Formulario>
</Ventana>
