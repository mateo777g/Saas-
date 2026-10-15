<!--
  Nueva área y Editar área (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi): solo el nombre. Al
  editar, abajo a la izquierda, Eliminar área: con categorías no se puede y tampoco si es la última
  (lo dice la caja de error, sin abrir nada); si no, pide confirmar en su propia ventana, y Cancelar
  regresa aquí. La base revisa lo mismo.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { plural } from '../../../lib/formato';
  import { crearArea, eliminarArea, renombrarArea, type Area, type Menu } from '../../../lib/menu';

  let {
    restauranteId,
    area,
    menu,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    area: Area | null;
    menu: Menu;
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = area;
  let nombre = $state(inicial?.nombre ?? '');
  let error = $state<string | null>(null);
  let paso = $state<null | 'guardando' | 'listo'>(null);
  let confirmando = $state(false);

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const limpio = nombre.trim();
    const repetida = menu.areas.find((a) => a.id !== inicial?.id && a.nombre.toLowerCase() === limpio.toLowerCase());
    if (!limpio) return { error: 'El nombre del área es obligatorio.' };
    if (repetida) return { error: `Ya tienes un área que se llama «${repetida.nombre}».` };

    paso = 'guardando';
    try {
      if (inicial) await renombrarArea(inicial.id, limpio);
      else await crearArea(restauranteId, limpio);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo guardar el área:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'Agregada' };
  }

  // Con categorías no se puede: se cambian de área primero. La última tampoco (la base dice lo mismo).
  function pedirEliminar() {
    if (!inicial) return;
    const suyas = menu.categorias.filter((c) => c.area_preparacion_id === inicial.id).length;
    if (suyas) {
      error = `${inicial.nombre} todavía tiene ${plural(suyas, 'categoría', 'categorías')}; ${suyas === 1 ? 'cámbiala' : 'cámbialas'} de área primero.`;
      return;
    }
    if (menu.areas.length === 1) {
      error = `Necesitas al menos un área. Crea otra antes de eliminar «${inicial.nombre}».`;
      return;
    }
    error = null;
    confirmando = true;
  }

  async function eliminar(): Promise<{ listo: string } | { error: string }> {
    if (!inicial) return { error: ALGO_SALIO_PANEL };
    try {
      await eliminarArea(inicial.id);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo eliminar el área:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    alCambiar();
    return { listo: 'Eliminada' };
  }
</script>

{#if confirmando && inicial}
  <Confirmar
    icono="eliminar"
    titulo="¿Eliminar esta área?"
    texto="«{inicial.nombre}» se quita de tus áreas."
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={eliminar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else}
  <Ventana
    etiqueta={paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR ÁREA' : 'NUEVA ÁREA'}
    titulo={inicial ? inicial.nombre : 'Agrega un área'}
    ancho={460}
    alCerrar={cerrar}
  >
    <Formulario
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar área', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={16}
      antesDelBoton={28}
    >
      <Campo
        id="area-nombre"
        etiqueta="NOMBRE"
        bind:valor={nombre}
        placeholder="Ej. Barra"
        pista={inicial
          ? 'Así sale en tus categorías y en la pantalla de cocina.'
          : 'Después, en Categorías, elige qué categorías van a ella.'}
      />

      {#snippet izquierda()}
        {#if inicial}
          <Boton etiqueta="Eliminar área" icono="eliminar" apagado={paso !== null} onclick={pedirEliminar} />
        {/if}
      {/snippet}
    </Formulario>
  </Ventana>
{/if}
