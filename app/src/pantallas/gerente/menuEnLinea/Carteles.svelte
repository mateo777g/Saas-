<!--
  Los carteles de «Tu menú en línea» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, sección 3; libreta 6,
  decidido el 20 de octubre de 2026): hasta 5 imágenes, como «2x1 los martes», que pasan solas arriba
  del menú. Cada cambio se guarda al momento, como las flechas de Mi menú. La imagen se sube antes de
  guardar (en 1600 × 900; si no es 16:9 sale entera con los lados desenfocados) y si el guardado
  falla se borra; la anterior se borra solo después de guardar.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { borrarFoto, convertirCartel, revisarFoto, subirFoto, urlFoto } from '../../../lib/fotos';
  import {
    agregarCartel,
    cambiarCartel,
    MAXIMO_CARTELES,
    moverCartel,
    quitarCartel,
    type Cartel,
  } from '../../../lib/restaurante';

  let {
    restauranteId,
    carteles,
    alCambiar,
  }: { restauranteId: string; carteles: Cartel[]; alCambiar: () => Promise<void> } = $props();

  // Qué se está haciendo: subir uno nuevo o cambiar la imagen de uno (su id), o mover o quitar.
  let ocupado = $state<null | 'nuevo' | number | 'otro'>(null);
  let error = $state<string | null>(null);
  let elegirArchivo = $state<HTMLInputElement>();
  let paraCambiar: number | null = null;

  function elegir(id: number | null) {
    if (ocupado !== null) return;
    paraCambiar = id;
    elegirArchivo?.click();
  }

  async function alElegir(e: Event & { currentTarget: HTMLInputElement }) {
    const archivo = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    if (!archivo || ocupado !== null) return;
    const problema = await revisarFoto(archivo);
    if (problema) {
      error = problema;
      return;
    }
    const id = paraCambiar;
    error = null;
    ocupado = id ?? 'nuevo';
    let ruta: string | null = null;
    let anterior: string | null = null;
    try {
      ruta = await subirFoto(restauranteId, await convertirCartel(archivo), 'carteles');
      if (id === null) await agregarCartel(restauranteId, ruta);
      else anterior = await cambiarCartel(id, ruta);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[carteles] no se pudo guardar el cartel:', falla);
      // La imagen de un cartel que no se guardó no se queda en R2.
      if (ruta) await borrarFoto(ruta);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      ocupado = null;
      return;
    }
    if (anterior) await borrarFoto(anterior);
    await alCambiar();
    ocupado = null;
  }

  async function hacer(accion: () => Promise<string | void>) {
    if (ocupado !== null) return;
    ocupado = 'otro';
    error = null;
    try {
      const ruta = await accion();
      if (ruta) await borrarFoto(ruta);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[carteles] no se pudo cambiar:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
    }
    await alCambiar();
    ocupado = null;
  }
</script>

<div class="tarjeta carteles">
  <div class="encabezado">
    <span class="cuadro-icono"><Icono nombre="biblio" tamano={18} /></span>
    <span class="titulos">
      <span class="titulo">Carteles</span>
      <span class="nota">Tus promociones, arriba de tu menú. Pasan solos.</span>
    </span>
    <span class="etiqueta">{carteles.length} DE {MAXIMO_CARTELES}</span>
  </div>
  <div class="raya"></div>
  {#if carteles.length}
    <div class="lista">
      {#each carteles as c, i (c.id)}
        <div class="fila">
          <img class="mini" src={urlFoto(c.imagen_ruta)} alt="Cartel {i + 1}" />
          <span class="num"><b>{ocupado === c.id ? 'Subiendo…' : `Cartel ${i + 1}`}</b></span>
          <span class="botones">
            <BotonCuadro
              icono="arriba"
              ayuda="Subir"
              tamanoIcono={15}
              apagado={i === 0 || ocupado !== null}
              onclick={() => hacer(() => moverCartel(c.id, 'arriba'))}
            />
            <BotonCuadro
              icono="abajo"
              ayuda="Bajar"
              tamanoIcono={15}
              apagado={i === carteles.length - 1 || ocupado !== null}
              onclick={() => hacer(() => moverCartel(c.id, 'abajo'))}
            />
            <BotonCuadro icono="biblio" ayuda="Cambiar imagen" tamanoIcono={15} apagado={ocupado !== null} onclick={() => elegir(c.id)} />
            <BotonCuadro
              icono="eliminar"
              ayuda="Quitar cartel"
              tamanoIcono={15}
              apagado={ocupado !== null}
              onclick={() => hacer(() => quitarCartel(c.id))}
            />
          </span>
        </div>
      {/each}
    </div>
  {:else}
    <p class="nota vacia">Todavía no tienes carteles. Sin carteles, tu menú empieza directo en tus categorías.</p>
  {/if}
  {#if error}<div class="error"><CajaError mensaje={error} /></div>{/if}
  <div class="agregar">
    <Boton
      etiqueta={ocupado === 'nuevo' ? 'Subiendo cartel…' : 'Agregar cartel'}
      icono="mas"
      cargando={ocupado === 'nuevo'}
      apagado={ocupado !== null || carteles.length >= MAXIMO_CARTELES}
      ayuda={carteles.length >= MAXIMO_CARTELES ? 'Ya tienes 5 carteles. Quita uno para agregar otro.' : undefined}
      onclick={() => elegir(null)}
    />
    <span class="pista">16:9, como 1600 × 900 · JPG o PNG</span>
  </div>
  <input bind:this={elegirArchivo} type="file" accept="image/*" hidden onchange={alElegir} />
</div>

<style>
  .tarjeta {
    min-width: 0;
    padding: 20px;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
  }

  /* Abajo deja 11 y no 20, como la maqueta: así caben 3 carteles enteros en una pantalla de 900;
     con más, o en una más bajita, la lista hace scroll (decidido el 24 de octubre de 2026). */
  .carteles {
    flex: 1;
    min-height: 0;
    padding-bottom: 11px;
  }

  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
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

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .nota.vacia {
    padding: 10px 0;
  }

  .raya {
    height: 1px;
    margin: 14px 0 4px;
    background: var(--linea);
    flex: none;
  }

  .lista {
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow-y: auto;
  }

  .fila {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 0;
    border-bottom: 1px solid var(--linea);
  }

  .fila:last-child {
    border-bottom: 0;
  }

  .mini {
    width: 96px;
    height: 54px;
    border-radius: 9px;
    object-fit: cover;
    flex: none;
    display: block;
    background: var(--chip);
  }

  .num {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .num b {
    font-size: 13px;
    font-weight: 700;
  }

  .botones {
    display: flex;
    gap: 6px;
  }

  .error {
    margin-top: 10px;
  }

  .agregar {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: 10px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
