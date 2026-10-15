<!--
  Nueva categoría y Editar categoría (maqueta del Menú CC2rrjbgxC2yykNa33a3sA): el nombre, uno de
  los 28 íconos, debajo cómo sale en el menú y su área (maqueta de Opciones y áreas
  GhrEVWPmevfBZtWzi4exKi): una nueva sale con la primera. Al editar, abajo a la izquierda, Eliminar
  categoría: con productos no se puede (lo dice la caja de error, sin abrir nada); sin productos,
  pide confirmar en su propia ventana, y Cancelar regresa aquí.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import CampoLista from '../../../diseno/CampoLista.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import { ICONOS_CATEGORIAS } from '../../../diseno/iconosCategorias';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { plural } from '../../../lib/formato';
  import {
    crearCategoria,
    editarCategoria,
    eliminarCategoria,
    type Categoria,
    type Menu,
  } from '../../../lib/menu';

  let {
    restauranteId,
    categoria,
    menu,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    categoria: Categoria | null;
    menu: Menu;
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = categoria;
  let nombre = $state(inicial?.nombre ?? '');
  let icono = $state(inicial?.icono ?? '');
  // En la lista, «mesero» es «Lo sirve el mesero» (la columna vacía). Una nueva sale con la primera.
  // svelte-ignore state_referenced_locally
  let area = $state(
    inicial ? (inicial.area_preparacion_id === null ? 'mesero' : String(inicial.area_preparacion_id)) : String(menu.areas[0]?.id ?? 'mesero'),
  );
  let error = $state<string | null>(null);
  let paso = $state<null | 'guardando' | 'listo'>(null);
  let confirmando = $state(false);

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  function elegirIcono(id: string, boton: HTMLButtonElement) {
    if (paso) return;
    icono = id;
    error = null;
    boton.focus({ preventScroll: true });
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const limpio = nombre.trim();
    const repetida = menu.categorias.find(
      (c) => c.id !== inicial?.id && c.nombre.toLowerCase() === limpio.toLowerCase(),
    );
    if (!limpio) return { error: 'El nombre de la categoría es obligatorio.' };
    if (repetida) return { error: `Ya tienes una categoría que se llama «${repetida.nombre}».` };
    if (!icono) return { error: 'Elige un ícono para la categoría.' };
    if (!area) return { error: 'Elige a qué área van sus productos.' };

    const datos = { nombre: limpio, icono, area_preparacion_id: area === 'mesero' ? null : Number(area) };
    paso = 'guardando';
    try {
      if (inicial) await editarCategoria(inicial.id, datos);
      else await crearCategoria(restauranteId, datos);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo guardar la categoría:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'Agregada' };
  }

  // Con productos no se puede: se mueven o se eliminan primero (la base dice lo mismo).
  function pedirEliminar() {
    if (!inicial) return;
    const suyos = menu.productos.filter((p) => p.categoria_id === inicial.id).length;
    if (suyos) {
      error =
        suyos === 1
          ? `${inicial.nombre} todavía tiene 1 producto; muévelo a otra categoría o elimínalo primero.`
          : `${inicial.nombre} todavía tiene ${plural(suyos, 'producto', 'productos')}; muévelos a otra categoría o elimínalos primero.`;
      return;
    }
    error = null;
    confirmando = true;
  }

  async function eliminar(): Promise<{ listo: string } | { error: string }> {
    if (!inicial) return { error: ALGO_SALIO_PANEL };
    try {
      await eliminarCategoria(inicial.id);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo eliminar la categoría:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    alCambiar();
    return { listo: 'Eliminada' };
  }
</script>

{#if confirmando && inicial}
  <Confirmar
    icono="eliminar"
    titulo="¿Eliminar esta categoría?"
    texto="«{inicial.nombre}» deja de salir en tu menú y en tus categorías."
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={eliminar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else}
  <Ventana
    etiqueta={paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR CATEGORÍA' : 'NUEVA CATEGORÍA'}
    titulo={inicial ? inicial.nombre : 'Agrega una categoría'}
    ancho={520}
    alCerrar={cerrar}
  >
    <Formulario
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar categoría', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={16}
      antesDelBoton={28}
    >
      <Campo id="categoria-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Tacos" />

      <div class="campo">
        <span class="etiqueta" id="categoria-icono">ÍCONO</span>
        <div class="iconos" role="radiogroup" aria-labelledby="categoria-icono">
          {#each ICONOS_CATEGORIAS as opcion (opcion.id)}
            <button
              type="button"
              class="icono"
              role="radio"
              aria-checked={icono === opcion.id}
              aria-label={opcion.nombre}
              title={opcion.nombre}
              onclick={(e) => elegirIcono(opcion.id, e.currentTarget)}
            >
              <IconoCategoria id={opcion.id} tamano={22} />
            </button>
          {/each}
        </div>
      </div>

      <div class="muestra">
        <span class="cuadro-icono">{#if icono}<IconoCategoria id={icono} tamano={18} />{/if}</span>
        <span class="nombre" class:vacia={!nombre.trim()}>{nombre.trim() || 'Así sale en tu menú'}</span>
      </div>

      <CampoLista
        id="categoria-area"
        etiqueta="ÁREA"
        bind:valor={area}
        placeholder="Elige un área"
        grupos={[
          {
            etiqueta: '',
            opciones: [
              ...menu.areas.map((a) => ({ valor: String(a.id), texto: a.nombre })),
              { valor: 'mesero', texto: 'Lo sirve el mesero' },
            ],
          },
        ]}
        pista="Ahí llegan sus productos al mandar a cocina. Lo que sirve el mesero no llega a ninguna pantalla."
      />

      {#snippet izquierda()}
        {#if inicial}
          <Boton etiqueta="Eliminar categoría" icono="eliminar" apagado={paso !== null} onclick={pedirEliminar} />
        {/if}
      {/snippet}
    </Formulario>
  </Ventana>
{/if}

<style>
  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .iconos {
    display: grid;
    grid-template-columns: repeat(7, minmax(0, 1fr));
    gap: 8px;
  }

  .icono {
    aspect-ratio: 1;
    max-width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    transition: background-color 150ms;
  }

  .icono:hover {
    background: var(--chip);
  }

  .icono[aria-checked='true'] {
    border-color: var(--tinta);
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .muestra {
    margin-top: -4px;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    border: 1px solid var(--linea);
    border-radius: 14px;
  }

  .cuadro-icono {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
  }

  .nombre {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .nombre.vacia {
    color: var(--tenue);
    font-weight: 500;
  }
</style>
