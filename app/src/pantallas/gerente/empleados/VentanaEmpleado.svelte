<!--
  Nuevo empleado y Editar empleado (maqueta de Empleados 36iXMMqXCfVv4NuVR7vNSc). Al dar de alta:
  el nombre, los roles y un PIN de 4 números, que se ve mientras Don Chuy lo escribe. Al editar,
  solo el nombre y los roles: el PIN va por el candado. Un nombre repetido se avisa antes de
  guardar, aunque cambien las mayúsculas, como en Mesas.
-->
<script lang="ts">
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { altaEmpleado, editarEmpleado, type Persona } from '../../../lib/equipo';
  import { ROLES, type Rol } from '../../../lib/roles';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import CampoPin from './CampoPin.svelte';
  import ElegirRoles from './ElegirRoles.svelte';

  let {
    restauranteId,
    persona,
    personas,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    persona: Persona | null;
    personas: Persona[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = persona;
  const esRol = (r: string): r is Rol => ROLES.some((x) => x.valor === r);
  let nombre = $state(inicial?.nombre ?? '');
  let roles = $state<Rol[]>(inicial ? inicial.roles.filter(esRol) : []);
  let pin = $state('');
  let paso = $state<null | 'guardando' | 'listo'>(null);

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const limpio = nombre.trim();
    const repetida = personas.find((p) => p.id !== inicial?.id && p.nombre.toLowerCase() === limpio.toLowerCase());
    if (!limpio) return { error: 'Escribe el nombre.' };
    if (repetida) return { error: `Ya hay alguien en tu equipo que se llama «${repetida.nombre}».` };
    if (!roles.length) return { error: 'Elige al menos un rol.' };
    if (!inicial && !/^\d{4}$/.test(pin)) return { error: 'El PIN son 4 números.' };

    paso = 'guardando';
    try {
      if (inicial) await editarEmpleado(inicial.id, limpio, roles);
      else await altaEmpleado(restauranteId, limpio, roles, pin);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[equipo] no se pudo guardar a la persona:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'En tu equipo' };
  }
</script>

<Ventana
  etiqueta={paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR EMPLEADO' : 'NUEVO EMPLEADO'}
  titulo={inicial ? inicial.nombre : 'Agrega a tu equipo'}
  ancho={480}
  alCerrar={cerrar}
>
  <Formulario
    boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar empleado', icono: 'mas' }}
    {guardar}
    alTerminar={alCerrar}
    espacio={18}
    antesDelBoton={28}
  >
    <Campo id="empleado-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. «Pepe Martínez»" />
    <ElegirRoles bind:roles />
    {#if !inicial}
      <CampoPin
        id="empleado-pin"
        etiqueta="PIN"
        bind:valor={pin}
        pista="4 números. Díselo en persona: después nadie lo puede ver, ni tú."
      />
    {/if}
  </Formulario>
</Ventana>
