<!--
  «Editar» de la página del recetario (maqueta DFVTWEB3eZBEKctyxWjGjg v1, «Taco al pastor · Editar»; «Lo que decidí yo» 9
  y 11 de las encuestas): la misma página vuelta campos. La foto de cómo se sirve con «Cambiar foto» y el bote encima, y
  un aviso cuando la que se ve es la de Mi menú; lo que lleva se ve igual, sin «Para más porciones», con su pista (se
  cambia con «Cambiar lo que lleva», arriba). Cada paso en su tarjeta: su número, ↑ ↓ y el bote arriba a la derecha; el
  texto en el gris de los campos con su contador («77/300») y su foto a la derecha (o un cuadro punteado «Foto»). Al
  final, «Agregar paso · 6 de 20». Abajo, la barra de guardar de Tu menú en línea; todo se guarda junto.

  Las fotos nuevas se suben al guardar, en WebP como las de Mi menú, a la carpeta recetario/ (el Worker), y luego
  guardar_recetario guarda todo. Si algo falla, las que se subieron se borran al momento; las que se quitaron o se
  cambiaron las borra el Worker una vez al día (fotos_por_borrar). Si Don Chuy se va con cambios, «Tienes cambios sin
  guardar» (y el navegador pregunta si cierra la pestaña).
-->
<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte';
  import '../../recetario/recetario.css';
  import BarraGuardar from '../../../diseno/BarraGuardar.svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { borrarFoto, convertirAWebp, revisarFoto, subirFoto } from '../../../lib/fotos';
  import { guardarRecetario, MAXIMO_LETRAS, MAXIMO_PASOS, urlDe, type De, type Pagina } from '../../../lib/recetario';
  import { ponerGuardia } from '../../../lib/salida';
  import { supabase } from '../../../lib/supabase';
  import Cabeza from '../../recetario/Cabeza.svelte';
  import VentanaSalirRecetario from './VentanaSalirRecetario.svelte';

  let {
    restauranteId,
    pagina,
    icono = null,
    cambios = $bindable(0),
    alGuardado,
    alDescartar,
    alVolver,
  }: {
    restauranteId: string;
    pagina: Pagina; // la que se leyó al entrar; si cambia lo que lleva, llega otra y los pasos escritos se quedan
    icono?: string | null;
    cambios?: number;
    alGuardado: () => void; // ya se guardó: regresa a la página
    alDescartar: () => void; // regresa a la página sin guardar
    alVolver: () => void; // «‹ Recetario»: a los cuadros
  } = $props();

  type Borrador = { clave: number; texto: string; ruta: string | null; archivo: File | null; vista: string | null };

  // Lo de cuando entró (svelte-ignore: el borrador nace una vez; lo que lleva sí se sigue de `pagina`).
  // svelte-ignore state_referenced_locally
  const de: De = { tipo: pagina.tipo, id: pagina.id };
  // svelte-ignore state_referenced_locally
  const antes = { imagen: pagina.imagen_ruta, pasos: pagina.pasos.map((p) => ({ texto: p.texto, ruta: p.imagen_ruta })) };

  let fotoRuta = $state<string | null>(antes.imagen);
  let fotoArchivo = $state<File | null>(null);
  let fotoVista = $state<string | null>(null);
  let siguiente = antes.pasos.length + 1;
  let pasos = $state<Borrador[]>(antes.pasos.map((p, i) => ({ clave: i + 1, texto: p.texto, ruta: p.ruta, archivo: null, vista: null })));

  let paso = $state<null | 'guardando' | 'listo'>(null);
  let error = $state<string | null>(null);
  let salida = $state<(() => void) | null>(null);
  let entrada = $state<HTMLInputElement>();
  let paraQuien = $state<'cabeza' | number | null>(null); // a qué foto va el archivo que se elige
  let lista = $state<HTMLOListElement>();

  // Cuántas cosas cambió: la foto, cada paso que se agregó, se quitó o cambió su texto o su foto, y el orden.
  const cuenta = $derived.by(() => {
    let n = 0;
    if (fotoArchivo || fotoRuta !== antes.imagen) n++;
    const viejos = pasos.filter((p) => p.clave <= antes.pasos.length);
    n += antes.pasos.length - viejos.length;
    n += pasos.length - viejos.length;
    for (const p of viejos) {
      const o = antes.pasos[p.clave - 1];
      if (p.texto.trim() !== o.texto) n++;
      if (p.archivo || p.ruta !== o.ruta) n++;
    }
    if (viejos.some((p, i) => i > 0 && p.clave < viejos[i - 1].clave)) n++;
    return n;
  });
  $effect(() => {
    cambios = cuenta;
  });

  // La foto de arriba: la nueva, la propia o, sin propia, la de Mi menú (con su aviso).
  const fotoPropia = $derived(fotoVista ?? urlDe(fotoRuta));
  const fotoDeMiMenu = $derived(!fotoArchivo && !fotoRuta ? urlDe(pagina.foto_de_mi_menu) : null);
  const fotoQueSeVe = $derived(fotoPropia ?? fotoDeMiMenu);

  // ─── Las fotos ──────────────────────────────────────────────────────────────────────────────

  function elegir(para: 'cabeza' | number) {
    if (paso) return;
    paraQuien = para;
    if (entrada) {
      entrada.value = '';
      entrada.click();
    }
  }

  async function alElegir() {
    const archivo = entrada?.files?.[0];
    const para = paraQuien;
    paraQuien = null;
    if (!archivo || para === null) return;
    const problema = await revisarFoto(archivo);
    if (problema) {
      error = problema;
      return;
    }
    error = null;
    const vista = URL.createObjectURL(archivo);
    if (para === 'cabeza') {
      if (fotoVista) URL.revokeObjectURL(fotoVista);
      fotoArchivo = archivo;
      fotoVista = vista;
      return;
    }
    const p = pasos.find((x) => x.clave === para);
    if (!p) return URL.revokeObjectURL(vista);
    if (p.vista) URL.revokeObjectURL(p.vista);
    p.archivo = archivo;
    p.vista = vista;
  }

  function quitarFotoCabeza() {
    if (fotoVista) URL.revokeObjectURL(fotoVista);
    fotoArchivo = null;
    fotoVista = null;
    fotoRuta = null;
  }

  function quitarFotoPaso(p: Borrador) {
    if (p.vista) URL.revokeObjectURL(p.vista);
    p.archivo = null;
    p.vista = null;
    p.ruta = null;
  }

  // ─── Los pasos ──────────────────────────────────────────────────────────────────────────────

  async function agregar() {
    if (pasos.length >= MAXIMO_PASOS) return;
    const clave = siguiente++;
    pasos.push({ clave, texto: '', ruta: null, archivo: null, vista: null });
    await tick();
    const campo = lista?.querySelector<HTMLTextAreaElement>(`[data-paso="${clave}"]`);
    campo?.focus();
    campo?.closest('li')?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  function mover(i: number, hacia: -1 | 1) {
    const j = i + hacia;
    if (j < 0 || j >= pasos.length) return;
    [pasos[i], pasos[j]] = [pasos[j], pasos[i]];
  }

  function quitar(i: number) {
    const [p] = pasos.splice(i, 1);
    if (p?.vista) URL.revokeObjectURL(p.vista);
  }

  // ─── Guardar ────────────────────────────────────────────────────────────────────────────────

  // Guarda todo; regresa el error si no se pudo (para «Guardar y salir»), o null.
  async function guardar(): Promise<string | null> {
    if (paso) return null;
    const vacio = pasos.findIndex((p) => !p.texto.trim());
    if (vacio >= 0) {
      error = `Escribe el paso ${vacio + 1}`;
      return error;
    }
    error = null;
    paso = 'guardando';
    const subidas: string[] = [];
    const subir = async (archivo: File) => {
      const ruta = await subirFoto(restauranteId, await convertirAWebp(archivo), 'recetario');
      subidas.push(ruta);
      return ruta;
    };
    try {
      const imagen = fotoArchivo ? await subir(fotoArchivo) : fotoRuta;
      const nuevos = [];
      for (const p of pasos) nuevos.push({ texto: p.texto.trim(), imagen_ruta: p.archivo ? await subir(p.archivo) : p.ruta });
      await guardarRecetario(supabase, restauranteId, de, imagen, nuevos);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[recetario] no se pudo guardar:', falla);
      // Las fotos de un recetario que no se guardó no se quedan en R2.
      for (const ruta of subidas) await borrarFoto(ruta);
      paso = null;
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      return error;
    }
    paso = 'listo';
    return null;
  }

  async function alGuardar() {
    if ((await guardar()) === null) setTimeout(alGuardado, 600);
  }

  // Irse de «Editar»: con cambios, primero la ventana; sin cambios, de una vez.
  export function pedirSalida(seguir: () => void) {
    if (cuenta && paso !== 'listo') salida = seguir;
    else seguir();
  }

  onMount(() => {
    // Si se va con cambios (la barra lateral, la búsqueda, otra sucursal, cerrar sesión), primero lo pregunta.
    const quitarGuardia = ponerGuardia((seguir) => {
      if (!cuenta || paso) return false;
      salida = seguir;
      return true;
    });
    // Y si cierra o recarga la pestaña, el navegador también pregunta.
    const alIrse = (e: BeforeUnloadEvent) => {
      if (cuenta && paso !== 'listo') e.preventDefault();
    };
    window.addEventListener('beforeunload', alIrse);
    return () => {
      quitarGuardia();
      window.removeEventListener('beforeunload', alIrse);
    };
  });

  onDestroy(() => {
    if (fotoVista) URL.revokeObjectURL(fotoVista);
    for (const p of pasos) if (p.vista) URL.revokeObjectURL(p.vista);
  });
</script>

<main class="rec-cuerpo inv-desliza">
  <div class="rec-desliza">
    <div class="rec-pagina editar">
      <span class="rec-volver"><Boton etiqueta="Recetario" icono="anterior" onclick={() => pedirSalida(alVolver)} /></span>
      <Cabeza {pagina} {icono} pasos={pasos.length} porciones={false}>
        {#snippet foto()}
          <div class="rec-foto" style:background-image={fotoQueSeVe ? `url(${fotoQueSeVe})` : undefined}>
            {#if fotoDeMiMenu}<span class="nota-foto">Sin foto de cómo se sirve, sale la de Mi menú.</span>{/if}
            <div class="botones-foto">
              <Boton etiqueta={fotoQueSeVe ? 'Cambiar foto' : 'Subir foto'} icono="foto" apagado={paso !== null} onclick={() => elegir('cabeza')} />
              {#if fotoPropia}<BotonCuadro icono="eliminar" ayuda="Quitar foto" apagado={paso !== null} onclick={quitarFotoCabeza} />{/if}
            </div>
          </div>
        {/snippet}
        {#snippet debajo()}
          <p class="rec-pista nota-lleva">Sale de la receta: lo mismo que se resta del inventario. Para cambiarlo, «Cambiar lo que lleva».</p>
        {/snippet}
      </Cabeza>

      <h3 class="rec-pasos-titulo"><span class="rec-etq">CÓMO SE HACE</span><span class="rec-cuenta">{pasos.length}</span></h3>
      <p class="rec-pista pista-pasos">
        Escribe cada paso sin cantidades: esas salen de lo que lleva y cambian con «Para más porciones». Hasta {MAXIMO_PASOS} pasos, de hasta
        {MAXIMO_LETRAS} letras cada uno.
      </p>
      <ol class="rec-pasos editando" bind:this={lista}>
        {#each pasos as p, i (p.clave)}
          {@const fotoPaso = p.vista ?? urlDe(p.ruta)}
          <li class="tarjeta rec-tarjeta paso-editar">
            <div class="arriba">
              <span class="rec-num">{i + 1}</span>
              <span class="crece"></span>
              <BotonCuadro icono="arriba" ayuda="Subir" apagado={i === 0 || paso !== null} onclick={() => mover(i, -1)} />
              <BotonCuadro icono="abajo" ayuda="Bajar" apagado={i === pasos.length - 1 || paso !== null} onclick={() => mover(i, 1)} />
              <BotonCuadro icono="eliminar" ayuda="Quitar paso" apagado={paso !== null} onclick={() => quitar(i)} />
            </div>
            <div class="campos">
              <GrupoCampos>
                <div class="campo">
                  <textarea
                    data-paso={p.clave}
                    rows="3"
                    maxlength={MAXIMO_LETRAS}
                    aria-label="Paso {i + 1}"
                    placeholder="Marina el pastor una noche con su adobo."
                    bind:value={p.texto}
                  ></textarea>
                  <span class="letras">{p.texto.length}/{MAXIMO_LETRAS}</span>
                </div>
              </GrupoCampos>
              {#if fotoPaso}
                <span class="rec-paso-foto" style:background-image="url({fotoPaso})">
                  <span class="foto-mini">
                    <BotonCuadro icono="foto" ayuda="Cambiar foto" apagado={paso !== null} onclick={() => elegir(p.clave)} />
                    <BotonCuadro icono="eliminar" ayuda="Quitar foto" apagado={paso !== null} onclick={() => quitarFotoPaso(p)} />
                  </span>
                </span>
              {:else}
                <button type="button" class="rec-paso-foto foto-vacia" disabled={paso !== null} onclick={() => elegir(p.clave)}>
                  <Icono nombre="foto" tamano={18} /><span>Foto</span>
                </button>
              {/if}
            </div>
          </li>
        {/each}
      </ol>
      <button type="button" class="agregar" disabled={pasos.length >= MAXIMO_PASOS || paso !== null} onclick={agregar}>
        <Icono nombre="mas" tamano={16} /> Agregar paso <span>{pasos.length} de {MAXIMO_PASOS}</span>
      </button>
    </div>
  </div>
</main>

<input bind:this={entrada} type="file" accept="image/*" hidden onchange={alElegir} />

<BarraGuardar cambios={cuenta} {paso} {error} alGuardar={() => void alGuardar()} alDescartar={alDescartar} />

{#if salida}
  <VentanaSalirRecetario
    nombre={pagina.nombre}
    alSalir={() => {
      const ir = salida;
      salida = null;
      ir?.();
    }}
    alGuardar={guardar}
    alCerrar={() => (salida = null)}
  />
{/if}

<style>
  /* Entre la barra de arriba y la de guardar (64), como Tu restaurante. */
  .rec-cuerpo {
    position: absolute;
    left: var(--vista-izquierda);
    right: var(--vista-derecha);
    top: var(--vista-arriba);
    bottom: 64px;
    display: flex;
    flex-direction: column;
  }

  /* Cristal: la página pasa por debajo de la barra de guardar, que es transparente (diseno/BarraGuardar), y ahí se borra
     poco a poco; lo último sigue quedando arriba de la barra: 40 + 64. */
  :global(:root[data-estilo='cristal']) .rec-cuerpo {
    bottom: 0;
  }

  :global(:root[data-estilo='cristal']) .editar {
    padding-bottom: 104px;
  }

  /* La foto de cómo se sirve: sus botones abajo a la izquierda y el aviso arriba. */
  .botones-foto {
    position: absolute;
    left: 12px;
    bottom: 12px;
    display: flex;
    gap: 8px;
  }

  .botones-foto :global(button),
  .foto-mini :global(button) {
    background: var(--solido);
  }

  .nota-foto {
    position: absolute;
    left: 12px;
    top: 12px;
    padding: 5px 9px;
    border-radius: 8px;
    background: rgba(0, 0, 0, 0.55);
    color: #ffffff;
    font-size: 11.5px;
    font-weight: 500;
  }

  .nota-lleva {
    margin: 2px 4px 0;
  }

  .pista-pasos {
    margin: -6px 4px 0;
  }

  .editando {
    gap: 12px;
  }

  .paso-editar {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 14px 16px 16px;
  }

  /* Cristal: el gris de los campos, el de las tarjetas de material (como en Crear anuncios). */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .paso-editar {
    --fondo: var(--cristal-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .paso-editar {
    --fondo: var(--cl-relleno);
  }

  .arriba {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .crece {
    flex-grow: 1;
  }

  .campos {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 176px;
    gap: 14px;
    align-items: start;
  }

  .campo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  /* La caja de texto de Campo.svelte, de tres renglones. */
  textarea {
    display: block;
    width: 100%;
    height: 104px;
    padding: 12px 14px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-size: 14px;
    font-weight: 500;
    line-height: 1.5;
    resize: none;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  textarea:hover:not(:focus) {
    background: var(--campo-encima);
  }

  /* Al escribir, el aro azul de las cajas de texto. */
  textarea:focus {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  textarea::placeholder {
    color: var(--tenue);
  }

  .letras {
    align-self: flex-end;
    margin-top: 6px;
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 500;
    color: var(--tenue);
    font-variant-numeric: tabular-nums;
  }

  .foto-mini {
    position: absolute;
    right: 6px;
    bottom: 6px;
    display: flex;
    gap: 4px;
  }

  .foto-vacia {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6px;
    border: 1.5px dashed var(--borde-tarjeta);
    background: transparent;
    color: var(--tenue);
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    transition:
      background 0.15s,
      color 0.15s;
  }

  .foto-vacia:hover:not(:disabled) {
    background: var(--chip);
    color: var(--texto);
  }

  /* «Agregar paso», punteado como «Otro ingrediente» de las recetas. */
  .agregar {
    align-self: stretch;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 44px;
    padding: 0 12px;
    border: 1px dashed var(--borde-tarjeta);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s;
  }

  .agregar:hover:not(:disabled) {
    background: var(--chip);
  }

  .agregar:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .agregar span {
    margin-left: 6px;
    font-family: var(--mono);
    font-size: 11px;
    font-weight: 500;
    color: var(--tenue);
  }

  @media (max-width: 860px) {
    .campos {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .foto-vacia,
    .agregar {
      transition: none;
    }
  }
</style>
