<!--
  Nuevo producto y Editar producto: dialogo_platillo.py de Flet con «producto» y la categoría de
  una lista (maqueta del Menú CC2rrjbgxC2yykNa33a3sA). La foto, el nombre, la descripción, la
  categoría y el precio, y debajo sus grupos de opciones (maqueta de Opciones y áreas
  GhrEVWPmevfBZtWzi4exKi), que se guardan junto con el producto (guardar_producto), y al final su
  inglés para el menú en línea (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn); al editar, abajo
  a la izquierda, Eliminar producto. Con la 6b (maqueta Pedidos por WhatsApp G2nxGb3xBgiPEYrDb6CgcW),
  «Es un costo de envío»: un envío no lleva foto, opciones ni inglés, porque sus clientes no lo ven,
  así que esas partes se esconden; si tenía foto, se borra de R2 después de guardar. Mientras guarda, la etiqueta de arriba dice en qué paso va
  (SUBIENDO FOTO…, GUARDANDO…), como en Flet.

  Desde Mi menú (maqueta U9YqpsSb2PeB5pFXTPvh1C, versiones 2, 3 y 13) va en dos columnas, de 984 y con el
  título al centro: los campos a la izquierda y a la derecha el cuadro «Foto de tu menú» (CajaFoto), para
  arrastrar la foto o picarle. El inglés va plegado en «Ver inglés», a todo lo ancho, con sus dos campos
  lado a lado: la IA lo traduce sola al guardar (lib/traduccion.ts).

  Las fotos siguen el orden de siempre: subir antes de guardar; si el guardado falla, se borra la
  foto que se acababa de subir; al cambiarla, la vieja se borra solo después de guardar. Eliminar
  pide confirmar en su propia ventana; Cancelar regresa aquí con lo que ya se había escrito.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Interruptor from '../../../diseno/Interruptor.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { borrarFoto, convertirAWebp, revisarFoto, subirFoto, urlFoto } from '../../../lib/fotos';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import {
    eliminarProducto,
    guardarProducto,
    type Categoria,
    type DatosProducto,
    type Grupo,
    type Producto,
  } from '../../../lib/menu';
  import CajaFoto from './CajaFoto.svelte';
  import EnIngles from './EnIngles.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import GruposProducto from './GruposProducto.svelte';

  let {
    restauranteId,
    producto,
    categorias,
    grupos,
    categoriaInicial,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    producto: Producto | null;
    categorias: Categoria[];
    grupos: Grupo[];
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
  let nombreEn = $state(inicial?.nombre_en ?? '');
  let descripcionEn = $state(inicial?.descripcion_en ?? '');
  let categoria = $state(String(inicial?.categoria_id ?? categoriaDeEntrada ?? ''));
  let precio = $state(inicial ? textoPrecio(inicial.precio) : '');
  let elegidos = $state<number[]>(inicial?.grupos ?? []);
  let envio = $state(inicial?.es_envio ?? false);
  let archivo = $state<File | null>(null);
  let vistaPrevia = $state<string | null>(null);
  let error = $state<string | null>(null);
  let paso = $state<null | 'foto' | 'guardando' | 'listo'>(null);
  let confirmando = $state(false);

  const etiqueta = $derived(
    paso === 'foto' ? 'SUBIENDO FOTO…' : paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR PRODUCTO' : 'NUEVO PRODUCTO',
  );
  const foto = $derived(vistaPrevia ?? (inicial?.imagen_ruta ? urlFoto(inicial.imagen_ruta) : null));
  // Traducido: con su nombre en inglés y, si tiene descripción, también la suya (sin descripción no hay inglés).
  const traducido = $derived(!!nombreEn.trim() && (!descripcion.trim() || !!descripcionEn.trim()));

  onDestroy(() => {
    if (vistaPrevia) URL.revokeObjectURL(vistaPrevia);
  });

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  // Del cuadro de la foto: elegida con el botón o arrastrada encima.
  async function alElegirFoto(elegido: File) {
    if (paso) return;
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
      nombre_en: envio ? '' : nombreEn.trim(),
      descripcion_en: envio ? '' : descripcionEn.trim(),
      precio: Math.round(numero * 100) / 100,
      grupos: envio ? [] : [...elegidos],
      es_envio: envio,
    };
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const datos = validar();
    if (typeof datos === 'string') return { error: datos };

    let rutaNueva: string | null = null;
    try {
      if (archivo && !envio) {
        paso = 'foto';
        rutaNueva = await subirFoto(restauranteId, await convertirAWebp(archivo));
        datos.imagen_ruta = rutaNueva;
      }
      paso = 'guardando';
      await guardarProducto(restauranteId, inicial?.id ?? null, datos);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo guardar el producto:', falla);
      // La foto de un producto que no se guardó no se queda en R2.
      if (rutaNueva) await borrarFoto(rutaNueva);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }

    // Ya guardado: la foto vieja ya no la usa nadie (al volverse envío, Postgres ya se la quitó).
    if ((rutaNueva || envio) && inicial?.imagen_ruta) await borrarFoto(inicial.imagen_ruta);
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
    peligro
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
  <Ventana {etiqueta} titulo={inicial ? inicial.nombre : 'Agrega un producto'} ancho={984} centrado alCerrar={cerrar}>
    <Formulario
    verde
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar producto', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={16}
      antesDelBoton={28}
    >
      <div class="dos-columnas">
        <div class="col-campos">
          <GrupoCampos>
            <Campo id="producto-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Tacos al pastor" />
            <Campo
              id="producto-descripcion"
              etiqueta="DESCRIPCIÓN"
              bind:valor={descripcion}
              placeholder="Qué lleva, cómo se sirve… (opcional)"
              multilinea
            />
          </GrupoCampos>
          <GrupoCampos>
          <div class="dos">
            <Lista
              id="producto-categoria"
              etiqueta="CATEGORÍA"
              bind:valor={categoria}
              placeholder="Elige una categoría"
              opciones={categorias.map((c) => ({ valor: String(c.id), texto: c.nombre, icono: c.icono }))}
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
          </GrupoCampos>

          <div class="fila-switch">
            <Interruptor prendido={envio} ayuda="Es un costo de envío" apagado={paso !== null} alCambiar={(v) => (envio = v)} />
            <span class="t">
              <b>Es un costo de envío</b>
              <span class="pista">
                {envio
                  ? 'No sale en tu menú en línea ni llega a la cocina. Sale como botón al confirmar un pedido a domicilio, y en el punto de venta como cualquier producto.'
                  : 'Prende esto solo para lo que cobras por llevar un pedido a domicilio.'}
              </span>
            </span>
          </div>

          {#if envio}
            <p class="pista">Un envío no lleva opciones ni foto, ni su parte en inglés, porque tus clientes no lo ven.</p>
          {:else}
            <GrupoCampos><GruposProducto {grupos} bind:elegidos apagado={paso !== null} /></GrupoCampos>
          {/if}
        </div>
        <CajaFoto src={foto} {envio} apagado={paso !== null} alElegir={alElegirFoto} />
      </div>

      {#if !envio}
        <EnIngles {traducido} columnas="1fr 1fr">
          <Campo
            id="producto-nombre-en"
            etiqueta="NOMBRE EN INGLÉS"
            bind:valor={nombreEn}
            placeholder={nombre.trim() || 'Ej. Pastor taco'}
          />
          <Campo
            id="producto-descripcion-en"
            etiqueta="DESCRIPCIÓN EN INGLÉS"
            bind:valor={descripcionEn}
            placeholder={descripcion.trim()}
            multilinea
          />
        </EnIngles>
      {/if}

      {#snippet izquierda()}
        {#if inicial}
          <Boton
            etiqueta="Eliminar producto"
            icono="eliminar"
            tono="peligro"
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
  .dos-columnas {
    display: grid;
    grid-template-columns: minmax(0, 420px) minmax(0, 1fr);
    gap: 28px;
  }

  .col-campos {
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .fila-switch {
    display: flex;
    align-items: flex-start;
    gap: 14px;
    padding: 14px 16px;
    border-radius: 16px;
    background: var(--fondo); /* el gris de los grupos de campos (GrupoCampos), desde el 9 nov 2026 */
  }

  .fila-switch :global(.interruptor) {
    margin-top: 1px;
  }

  .fila-switch .t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .fila-switch b {
    font-size: 13.5px;
    font-weight: 700;
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
