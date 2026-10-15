<!--
  Nuevo producto y Editar producto: dialogo_platillo.py de Flet con «producto» y la categoría de
  una lista (maqueta del Menú CC2rrjbgxC2yykNa33a3sA). La foto, el nombre, la descripción, la
  categoría y el precio; al editar, abajo a la izquierda, Eliminar producto. Mientras guarda, la
  etiqueta de arriba dice en qué paso va (SUBIENDO FOTO…, GUARDANDO…), como en Flet.

  Las fotos siguen el orden de siempre: subir antes de guardar; si el guardado falla, se borra la
  foto que se acababa de subir; al cambiarla, la vieja se borra solo después de guardar. Eliminar
  pide confirmar en su propia ventana; Cancelar regresa aquí con lo que ya se había escrito.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import CampoLista from '../../../diseno/CampoLista.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { borrarFoto, convertirAWebp, revisarFoto, subirFoto, urlFoto } from '../../../lib/fotos';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import {
    crearProducto,
    editarProducto,
    eliminarProducto,
    type Categoria,
    type DatosProducto,
    type Producto,
  } from '../../../lib/menu';
  import Foto from './Foto.svelte';

  let {
    restauranteId,
    producto,
    categorias,
    categoriaInicial,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    producto: Producto | null;
    categorias: Categoria[];
    categoriaInicial: number | null;
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // El precio en el campo, como en Flet: sin decimales de sobra (22, 22.50).
  function textoPrecio(n: number) {
    return Number.isInteger(n) ? String(n) : n.toFixed(2);
  }

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = producto;
  // svelte-ignore state_referenced_locally
  const categoriaDeEntrada = categoriaInicial;
  let nombre = $state(inicial?.nombre ?? '');
  let descripcion = $state(inicial?.descripcion ?? '');
  let categoria = $state(String(inicial?.categoria_id ?? categoriaDeEntrada ?? ''));
  let precio = $state(inicial ? textoPrecio(inicial.precio) : '');
  let archivo = $state<File | null>(null);
  let vistaPrevia = $state<string | null>(null);
  let error = $state<string | null>(null);
  let paso = $state<null | 'foto' | 'guardando' | 'listo'>(null);
  let confirmando = $state(false);
  let elegirArchivo = $state<HTMLInputElement>();

  const etiqueta = $derived(
    paso === 'foto' ? 'SUBIENDO FOTO…' : paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR PRODUCTO' : 'NUEVO PRODUCTO',
  );
  const foto = $derived(vistaPrevia ?? (inicial?.imagen_ruta ? urlFoto(inicial.imagen_ruta) : null));

  onDestroy(() => {
    if (vistaPrevia) URL.revokeObjectURL(vistaPrevia);
  });

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  async function alElegirFoto(e: Event & { currentTarget: HTMLInputElement }) {
    const elegido = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    if (!elegido || paso) return;
    const problema = await revisarFoto(elegido);
    if (problema) {
      error = problema;
      return;
    }
    error = null;
    if (vistaPrevia) URL.revokeObjectURL(vistaPrevia);
    archivo = elegido;
    vistaPrevia = URL.createObjectURL(elegido);
  }

  // Lo de antes de mandar nada: los textos de Flet y de la maqueta. Postgres revisa lo mismo.
  function validar(): DatosProducto | string {
    const limpio = nombre.trim();
    if (!limpio) return 'El nombre del producto es obligatorio.';
    if (!categoria) return 'Elige una categoría.';
    const textoNumero = precio.trim().replace(/,/g, '');
    if (!/^-?(\d+\.?\d*|\.\d+)$/.test(textoNumero)) return 'El precio debe ser un número (ej. 145 o 145.50).';
    const numero = Number(textoNumero);
    if (numero < 0) return 'El precio no puede ser negativo.';
    return {
      categoria_id: Number(categoria),
      nombre: limpio,
      descripcion: descripcion.trim(),
      precio: Math.round(numero * 100) / 100,
    };
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const datos = validar();
    if (typeof datos === 'string') return { error: datos };

    let rutaNueva: string | null = null;
    try {
      if (archivo) {
        paso = 'foto';
        rutaNueva = await subirFoto(restauranteId, await convertirAWebp(archivo));
        datos.imagen_ruta = rutaNueva;
      }
      paso = 'guardando';
      if (inicial) await editarProducto(inicial.id, datos);
      else await crearProducto(restauranteId, datos);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo guardar el producto:', falla);
      // La foto de un producto que no se guardó no se queda en R2.
      if (rutaNueva) await borrarFoto(rutaNueva);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }

    // Ya guardado: la foto vieja ya no la usa nadie.
    if (rutaNueva && inicial?.imagen_ruta) await borrarFoto(inicial.imagen_ruta);
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'Agregado' };
  }

  async function eliminar(): Promise<{ listo: string } | { error: string }> {
    if (!inicial) return { error: ALGO_SALIO_PANEL };
    try {
      const { resultado, imagen_ruta } = await eliminarProducto(inicial.id);
      if (resultado === 'borrado' && imagen_ruta) await borrarFoto(imagen_ruta);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo eliminar el producto:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    alCambiar();
    return { listo: 'Eliminado' };
  }
</script>

{#if confirmando && inicial}
  <Confirmar
    icono="eliminar"
    titulo="¿Eliminar este producto?"
    texto="«{inicial.nombre}» se quita de tu menú. Si ya lo vendiste, tus reportes lo siguen contando. Si solo se acabó, mejor ocúltalo con el ojito."
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={eliminar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else}
  <Ventana {etiqueta} titulo={inicial ? inicial.nombre : 'Agrega un producto'} ancho={520} alCerrar={cerrar}>
    <Formulario
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar producto', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={16}
      antesDelBoton={28}
    >
      <div class="fila-foto">
        <Foto src={foto} tamano={72} radio={14} />
        <div class="foto-texto">
          <Boton
            etiqueta={foto ? 'Cambiar foto' : 'Agregar foto'}
            icono="biblio"
            apagado={paso !== null}
            onclick={() => elegirArchivo?.click()}
          />
          <span class="pista">JPG o PNG · se optimiza automáticamente</span>
        </div>
        <input bind:this={elegirArchivo} type="file" accept="image/*" hidden onchange={alElegirFoto} />
      </div>

      <Campo id="producto-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Tacos al pastor" />
      <Campo
        id="producto-descripcion"
        etiqueta="DESCRIPCIÓN"
        bind:valor={descripcion}
        placeholder="Qué lleva, cómo se sirve… (opcional)"
        multilinea
      />
      <div class="dos">
        <CampoLista
          id="producto-categoria"
          etiqueta="CATEGORÍA"
          bind:valor={categoria}
          placeholder="Elige una categoría"
          grupos={[{ etiqueta: '', opciones: categorias.map((c) => ({ valor: String(c.id), texto: c.nombre })) }]}
        />
        <div class="precio">
          <Campo
            id="producto-precio"
            etiqueta="PRECIO"
            bind:valor={precio}
            placeholder="0"
            prefijo="$"
            modoTeclado="decimal"
          />
        </div>
      </div>

      {#snippet izquierda()}
        {#if inicial}
          <Boton
            etiqueta="Eliminar producto"
            icono="eliminar"
            apagado={paso !== null}
            onclick={() => {
              error = null;
              confirmando = true;
            }}
          />
        {/if}
      {/snippet}
    </Formulario>
  </Ventana>
{/if}

<style>
  .fila-foto {
    margin-bottom: 4px;
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .foto-texto {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .dos {
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .dos > :global(:first-child) {
    flex: 1;
  }

  .precio {
    width: 160px;
    flex: none;
  }
</style>
