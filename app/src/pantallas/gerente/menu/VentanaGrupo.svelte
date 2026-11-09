<!--
  Nuevo grupo y Editar grupo (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi), en dos columnas.
  A la izquierda: el nombre, cuántas se eligen (mínimo y máximo con − y +, nunca más que sus
  opciones, y una frase que lo dice en palabras) y las opciones, cada una con su precio extra (vacío
  es $0), su ojito de agotada, sus flechas y su X. A la derecha, los productos que lo llevan, por
  categoría, con «Todos». Todo se guarda junto con Agregar grupo o Guardar cambios (guardar_grupo):
  el ojito también. Al editar, abajo a la izquierda, Eliminar grupo pide confirmar y dice en
  cuántos productos está.

  Desde Mi menú (maqueta U9YqpsSb2PeB5pFXTPvh1C, versiones 24 a 26) va como la de producto: 984 y el
  título al centro; la izquierda se queda con lo que sobra y los productos miden 420, en tarjetas con
  foto como las de Crear anuncios, 2 por fila, que se deslizan por dentro sin estirar la ventana.
  «Agregar opción» sube junto a Mínimo y Máximo, con su etiqueta «NUEVA OPCIÓN». «Ver inglés» no se
  abre: cambia el nombre y cada opción a inglés hasta volver a picarlo («Ver español»), con su marquita
  «EN»; lo que no cambia con el idioma se apaga y no responde. Lo escrito en cada idioma se queda al ir
  y venir; un inglés vacío enseña en gris el español, y la IA lo traduce al guardar.
-->
<script lang="ts">
  import { onDestroy, tick } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import { pista } from '../../../diseno/pista';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { pesos, plural } from '../../../lib/formato';
  import { urlFoto } from '../../../lib/fotos';
  import { eliminarGrupo, guardarGrupo, type Grupo, type Menu } from '../../../lib/menu';
  import { frase } from '../../../lib/opciones';

  let {
    restauranteId,
    grupo,
    menu,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    grupo: Grupo | null;
    menu: Menu;
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // Cada fila de opción lleva su clave para que Svelte no revuelva los campos al reacomodarlas.
  type Fila = { clave: number; id: number | null; nombre: string; ingles: string; precio: string; visible: boolean };

  // El precio en el campo, como en el del producto: sin decimales de sobra; $0 es el campo vacío.
  function textoPrecio(n: number) {
    if (!n) return '';
    return Number.isInteger(n) ? String(n) : n.toFixed(2);
  }

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = grupo;
  let siguienteClave = 0;
  let nombre = $state(inicial?.nombre ?? '');
  let nombreEn = $state(inicial?.nombre_en ?? '');
  // Un grupo nuevo empieza como el más común: obligatorio, se elige una, con una opción vacía.
  let minimo = $state(inicial?.minimo ?? 1);
  let maximo = $state(inicial?.maximo ?? 1);
  let opciones = $state<Fila[]>(
    inicial
      ? inicial.opciones.map((o) => ({
          clave: siguienteClave++,
          id: o.id,
          nombre: o.nombre,
          ingles: o.nombre_en ?? '',
          precio: textoPrecio(o.precio_extra),
          visible: o.visible,
        }))
      : [{ clave: siguienteClave++, id: null, nombre: '', ingles: '', precio: '', visible: true }],
  );
  const productos = new SvelteSet<number>(inicial?.productos ?? []);
  let error = $state<string | null>(null);
  let paso = $state<null | 'guardando' | 'listo'>(null);
  let confirmando = $state(false);
  let listaOpciones = $state<HTMLElement>();
  let columnaIzquierda = $state<HTMLElement>();
  let pistaIdioma = $state<HTMLSpanElement>();
  // «Ver inglés» del grupo: los mismos campos pasan a inglés hasta volver a picarlo.
  let ingles = $state(false);
  const esperas = new Set<ReturnType<typeof setTimeout>>();
  onDestroy(() => esperas.forEach(clearTimeout));

  const cuantas = $derived(opciones.length);
  // Por categoría, en el orden del menú; las que no tienen productos no salen. Un envío no lleva
  // opciones (parte 6b).
  const porCategoria = $derived(
    menu.categorias
      .map((c) => ({ categoria: c, productos: menu.productos.filter((p) => p.categoria_id === c.id && !p.es_envio) }))
      .filter((x) => x.productos.length),
  );
  const traducido = $derived(!!nombreEn.trim() && opciones.every((o) => !!o.ingles.trim()));
  const pistaTexto = $derived(
    ingles
      ? traducido
        ? 'Lo tradujo la IA. Si corriges algo, se respeta.'
        : 'La IA lo traduce sola. Si prefieres, escríbelo tú.'
      : traducido
        ? ''
        : 'La IA lo traduce sola.',
  );

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  function cambiarMinimo(d: number) {
    minimo = Math.min(Math.max(minimo + d, 0), cuantas);
    if (maximo < minimo) maximo = minimo;
  }

  function cambiarMaximo(d: number) {
    maximo = Math.min(Math.max(maximo + d, 1), Math.max(cuantas, 1));
    if (minimo > maximo) minimo = maximo;
  }

  async function agregarOpcion() {
    opciones.push({ clave: siguienteClave++, id: null, nombre: '', ingles: '', precio: '', visible: true });
    await tick();
    const campos = listaOpciones?.querySelectorAll<HTMLInputElement>('.op-nombre');
    campos?.[campos.length - 1]?.focus();
  }

  // Nunca más de las que hay: el mínimo y el máximo se ajustan solos.
  function quitarOpcion(i: number) {
    opciones.splice(i, 1);
    minimo = Math.min(minimo, opciones.length);
    maximo = Math.min(maximo, Math.max(opciones.length, 1));
    if (maximo < minimo) maximo = minimo;
  }

  function moverOpcion(i: number, hacia: -1 | 1) {
    const j = i + hacia;
    if (j < 0 || j >= opciones.length) return;
    [opciones[i], opciones[j]] = [opciones[j], opciones[i]];
  }

  // «Todos» las elige una tras otra, 45 ms entre cada una, como la lista; «Quitar todos», igual.
  function alternarCategoria(lista: { id: number }[]) {
    const todos = lista.every((p) => productos.has(p.id));
    lista.forEach((p, i) => {
      const espera = setTimeout(() => {
        esperas.delete(espera);
        if (todos) productos.delete(p.id);
        else productos.add(p.id);
      }, i * 45);
      esperas.add(espera);
    });
  }

  function alternarProducto(id: number) {
    if (productos.has(id)) productos.delete(id);
    else productos.add(id);
  }

  const quieto = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  // El texto de cada campo entra subiendo con el rebote de la caja del agente.
  async function cambiarIdioma() {
    ingles = !ingles;
    if (quieto()) return;
    await tick();
    for (const c of columnaIzquierda?.querySelectorAll<HTMLInputElement>('#grupo-nombre, .op-nombre') ?? [])
      c.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'none' }], {
        duration: 300,
        easing: 'cubic-bezier(0.175, 0.885, 0.32, 1.275)',
      });
    if (pistaTexto)
      pistaIdioma?.animate([{ opacity: 0, transform: 'translateY(4px)' }, { opacity: 1, transform: 'none' }], { duration: 300, easing: 'ease-out' });
  }

  // Lo de antes de mandar nada: lo mismo que revisa guardar_grupo, con las palabras de la maqueta.
  function validar() {
    const limpio = nombre.trim();
    if (!limpio) return 'El nombre del grupo es obligatorio.';
    if (!opciones.length) return 'Agrega al menos una opción.';
    const vistos = new Set<string>();
    const lista = [];
    for (const o of opciones) {
      const n = o.nombre.trim();
      if (!n) return 'Cada opción necesita su nombre.';
      if (vistos.has(n.toLowerCase())) return `Ya hay una opción que se llama «${n}» en este grupo.`;
      vistos.add(n.toLowerCase());
      const texto = o.precio.trim().replace(/,/g, '');
      if (texto && !/^-?(\d+\.?\d*|\.\d+)$/.test(texto)) return `El precio extra de «${n}» debe ser un número (ej. 10 o 12.50).`;
      const precio = texto ? Number(texto) : 0;
      if (precio < 0) return 'El precio extra no puede ser negativo: una opción solo suma.';
      lista.push({
        id: o.id,
        nombre: n,
        nombre_en: o.ingles.trim(),
        precio_extra: Math.round(precio * 100) / 100,
        visible: o.visible,
      });
    }
    return { nombre: limpio, nombre_en: nombreEn.trim(), minimo, maximo, opciones: lista, productos: [...productos] };
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const datos = validar();
    if (typeof datos === 'string') return { error: datos };
    paso = 'guardando';
    try {
      await guardarGrupo(restauranteId, inicial?.id ?? null, datos);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo guardar el grupo:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'Agregado' };
  }

  async function eliminar(): Promise<{ listo: string } | { error: string }> {
    if (!inicial) return { error: ALGO_SALIO_PANEL };
    try {
      await eliminarGrupo(inicial.id);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[menu] no se pudo eliminar el grupo:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    alCambiar();
    return { listo: 'Eliminado' };
  }
</script>

{#snippet contador(etiqueta: string, valor: number, menos: () => void, mas: () => void, sinMenos: boolean, sinMas: boolean)}
  <div class="paso">
    <span class="paso-etiqueta">{etiqueta}</span>
    <div class="paso-caja">
      <button type="button" class="paso-boton" aria-label="{etiqueta}: uno menos" use:pista={'Uno menos'} disabled={sinMenos || paso !== null} onclick={menos}>
        <Icono nombre="menos" tamano={14} />
      </button>
      <span class="paso-valor">{valor}</span>
      <button type="button" class="paso-boton" aria-label="{etiqueta}: uno más" use:pista={'Uno más'} disabled={sinMas || paso !== null} onclick={mas}>
        <Icono nombre="mas" tamano={14} />
      </button>
    </div>
  </div>
{/snippet}

{#snippet marcaEn()}
  <span class="marca-en" aria-hidden="true">EN</span>
{/snippet}

{#if confirmando && inicial}
  <Confirmar
    peligro
    icono="eliminar"
    titulo="¿Eliminar este grupo?"
    texto={inicial.productos.length
      ? `«${inicial.nombre}» se quita de ${plural(inicial.productos.length, 'producto', 'productos')} y de tus opciones. Tus ventas pasadas no cambian.`
      : `«${inicial.nombre}» se quita de tus opciones.`}
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={eliminar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else}
  <Ventana
    etiqueta={paso === 'guardando' ? 'GUARDANDO…' : inicial ? 'EDITAR GRUPO' : 'NUEVO GRUPO'}
    titulo={inicial ? inicial.nombre : 'Agrega un grupo'}
    ancho={984}
    centrado
    alCerrar={cerrar}
  >
    <Formulario
      verde
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar grupo', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={0}
      antesDelBoton={28}
    >
      <div class="dos-columnas" class:en-ingles-modo={ingles}>
        <div class="columna" bind:this={columnaIzquierda}>
          <GrupoCampos>
          <div class="con-marca-en">
            <Campo
              id="grupo-nombre"
              etiqueta="NOMBRE"
              bind:valor={() => (ingles ? nombreEn : nombre), (v) => (ingles ? (nombreEn = v) : (nombre = v))}
              placeholder={ingles ? nombre.trim() || 'Ej. Salsa' : 'Ej. Salsa'}
              marca={marcaEn}
            />
          </div>

          <div class="campo cuantas-con-agregar">
            <span class="etiqueta">CUÁNTAS SE ELIGEN</span>
            <div class="pasos se-apaga" inert={ingles}>
              {@render contador('Mínimo', minimo, () => cambiarMinimo(-1), () => cambiarMinimo(1), minimo <= 0, minimo >= cuantas)}
              {@render contador('Máximo', maximo, () => cambiarMaximo(-1), () => cambiarMaximo(1), maximo <= 1, maximo >= Math.max(cuantas, 1))}
            </div>
            <p class="frase">{frase(minimo, maximo)}</p>
            <div class="nueva-opcion">
              <span class="etiqueta">NUEVA OPCIÓN</span>
              <div class="se-apaga" inert={ingles}>
                <Boton etiqueta="Agregar" aria-label="Agregar opción" icono="mas" tamano="chico" apagado={paso !== null} onclick={agregarOpcion} />
              </div>
            </div>
          </div>
          </GrupoCampos>

          <GrupoCampos>
          <div class="campo">
            <div class="etiquetas"><span class="etiqueta">OPCIONES</span><span class="etiqueta">PRECIO EXTRA</span></div>
            <div class="opciones" bind:this={listaOpciones}>
              {#each opciones as o, i (o.clave)}
                <div class="opcion" class:agotada={!o.visible}>
                  <span class="opcion-nombre con-marca-en">
                    <input
                      class="op-nombre"
                      bind:value={() => (ingles ? o.ingles : o.nombre), (v) => (ingles ? (o.ingles = v) : (o.nombre = v))}
                      placeholder={ingles ? o.nombre.trim() || 'Ej. Green' : 'Ej. Verde'}
                      aria-label={ingles ? `${o.nombre.trim() || `Opción ${i + 1}`} en inglés` : `Nombre de la opción ${i + 1}`}
                      autocomplete="off"
                      disabled={paso !== null}
                    />
                    {@render marcaEn()}
                    {#if !o.visible}<span class="marca-agotada">AGOTADA</span>{/if}
                  </span>
                  <span class="precio se-apaga" inert={ingles}>
                    <span class="prefijo">+$</span>
                    <input
                      bind:value={o.precio}
                      placeholder="0"
                      inputmode="decimal"
                      aria-label="Precio extra de la opción {i + 1}"
                      autocomplete="off"
                      disabled={paso !== null}
                    />
                  </span>
                  <span class="acciones se-apaga" inert={ingles}>
                    <BotonCuadro
                      icono={o.visible ? 'oculto' : 'ojo'}
                      ayuda={o.visible ? 'Marcar agotada' : 'Ya hay: mostrarla'}
                      apagado={paso !== null}
                      onclick={() => (o.visible = !o.visible)}
                    />
                    <BotonCuadro icono="arriba" ayuda="Subir" etiqueta="Subir opción" apagado={i === 0 || paso !== null} onclick={() => moverOpcion(i, -1)} />
                    <BotonCuadro
                      icono="abajo"
                      ayuda="Bajar"
                      etiqueta="Bajar opción"
                      apagado={i === opciones.length - 1 || paso !== null}
                      onclick={() => moverOpcion(i, 1)}
                    />
                    <BotonCuadro icono="cerrar" ayuda="Quitar opción" apagado={paso !== null} onclick={() => quitarOpcion(i)} />
                  </span>
                </div>
              {/each}
            </div>
            <p class="pista">El precio extra se suma al del producto; vacío es $0. El ojito marca una opción agotada.</p>
          </div>
          </GrupoCampos>

          <div class="ver-ingles">
            <button type="button" class="ver-ingles-fila" aria-pressed={ingles} onclick={cambiarIdioma}>
              <span class="vi-titulo">{ingles ? 'Ver español' : 'Ver inglés'}</span>
              <span class="vi-pista" bind:this={pistaIdioma}>{pistaTexto}</span>
              <svg class="vi-cambio" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
                ><path d="M17 3l4 4-4 4"></path><path d="M3 7h18"></path><path d="M7 21l-4-4 4-4"></path><path d="M21 17H3"></path></svg
              >
            </button>
          </div>
        </div>

        <div class="columna derecha">
          <div class="campo">
            <div class="etiquetas">
              <span class="etiqueta">PRODUCTOS QUE LO LLEVAN</span>
              <span class="etiqueta">{productos.size} DE {menu.productos.length}</span>
            </div>
            {#if !porCategoria.length}
              <div class="productos vacia">
                <p class="pista">Todavía no tienes productos. Cuando los tengas, aquí eliges cuáles lo llevan.</p>
              </div>
            {:else}
              <div class="productos tarjetas se-apaga" inert={ingles}>
                {#each porCategoria as { categoria, productos: suyos } (categoria.id)}
                  <div class="categoria">
                    <span class="categoria-nombre"><IconoCategoria id={categoria.icono} tamano={14} />{categoria.nombre}</span>
                    <button type="button" class="todos" disabled={paso !== null} onclick={() => alternarCategoria(suyos)}>
                      {suyos.every((p) => productos.has(p.id)) ? 'Quitar todos' : 'Todos'}
                    </button>
                  </div>
                  <div class="pt-rejilla">
                    {#each suyos as p (p.id)}
                      <button
                        type="button"
                        class="pt"
                        role="checkbox"
                        aria-checked={productos.has(p.id)}
                        disabled={paso !== null}
                        onclick={() => alternarProducto(p.id)}
                      >
                        <span class="pt-foto" style:background-image={p.imagen_ruta ? `url(${urlFoto(p.imagen_ruta)})` : undefined}></span>
                        <span class="pt-textos">
                          <span class="pt-nombre">{p.nombre}</span>
                          <span class="pt-precio">{pesos(p.precio)}{p.visible ? '' : ' · oculto'}</span>
                        </span>
                        <span class="pt-marca" aria-hidden="true"
                          ><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"
                            ><path d="M5 12.5l4.5 4.5L19 7.5"></path></svg
                          ></span
                        >
                      </button>
                    {/each}
                  </div>
                {/each}
              </div>
            {/if}
            <p class="pista">También se pone desde la ventana de cada producto.</p>
          </div>
        </div>
      </div>

      {#snippet izquierda()}
        {#if inicial}
          <Boton
            etiqueta="Eliminar grupo"
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
  /* La izquierda se queda con lo que sobra (480 px, casi lo de antes) y los productos miden 420. */
  .dos-columnas {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 420px);
    gap: 28px;
    align-items: stretch;
  }

  .columna {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  /* La columna de los productos no estira la ventana: mide lo que la izquierda (al menos 420 px) y sus
     tarjetas se deslizan por dentro. */
  .derecha {
    contain: size;
    min-height: 420px;
  }

  .derecha > .campo {
    flex: 1;
    min-height: 0;
  }

  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .etiquetas {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 12px;
  }

  /* «Cuántas se eligen» con «Nueva opción» a la derecha: las dos etiquetas en un renglón, los contadores
     y el botón en el siguiente, y la frase abajo. */
  .cuantas-con-agregar {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-rows: auto auto auto;
    column-gap: 20px;
  }

  .cuantas-con-agregar > .etiqueta {
    grid-area: 1 / 1;
  }

  .cuantas-con-agregar > .pasos {
    grid-area: 2 / 1;
  }

  .cuantas-con-agregar > .frase {
    grid-area: 3 / 1 / 4 / 3;
  }

  .nueva-opcion {
    grid-area: 1 / 2 / 3 / 3;
    display: grid;
    grid-template-rows: subgrid;
    row-gap: 8px;
    justify-items: end;
  }

  .nueva-opcion > :last-child {
    align-self: center;
  }

  .pasos {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 20px;
  }

  .paso {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .paso-etiqueta {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI), desde el 9 nov 2026. */
  .paso-caja {
    height: 40px;
    display: inline-flex;
    align-items: center;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    overflow: hidden;
  }

  .paso-boton {
    width: 37px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: 0;
    background: transparent;
    color: var(--texto);
    transition: background-color 150ms;
  }

  .paso-boton:hover:not(:disabled) {
    background: var(--chip);
  }

  .paso-boton:disabled {
    opacity: 0.3;
  }

  .paso-valor {
    min-width: 26px;
    text-align: center;
    font-family: var(--mono);
    font-size: 13.5px;
    font-variant-numeric: tabular-nums;
  }

  .frase {
    margin: 0;
    font-size: 12.5px;
    font-weight: 600;
    line-height: 1.45;
  }

  .opciones {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .opcion {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .acciones {
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI), desde el 9 nov 2026. */
  .opcion input {
    width: 100%;
    height: 40px;
    padding: 0 12px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  .opcion input:hover:not(:focus):not(:disabled) {
    background: var(--campo-encima);
  }

  .opcion input:focus {
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .opcion input::placeholder {
    color: var(--tenue);
  }

  .opcion-nombre {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
  }

  .agotada .op-nombre {
    padding-right: 78px;
    color: var(--tenue);
  }

  .marca-agotada {
    position: absolute;
    right: 8px;
    top: 50%;
    transform: translateY(-50%);
    padding: 3px 6px;
    border-radius: 6px;
    background: var(--amarillo-fondo);
    font-family: var(--mono);
    font-size: 9.5px;
    font-weight: 500;
    letter-spacing: 0.1em;
    color: var(--amarillo-texto);
    pointer-events: none;
    transition: right 0.2s ease;
  }

  .precio {
    position: relative;
    width: 96px;
    flex: none;
    display: flex;
  }

  .prefijo {
    position: absolute;
    left: 12px;
    top: 0;
    height: 40px;
    display: flex;
    align-items: center;
    font-size: 13.5px;
    color: var(--suave);
    pointer-events: none;
  }

  .precio input {
    padding-left: 32px;
    font-variant-numeric: tabular-nums;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .productos {
    max-height: 470px;
    overflow-y: auto;
    padding: 4px 6px 6px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    border: 1px solid var(--linea);
    border-radius: 14px;
  }

  .productos.tarjetas {
    flex: 1;
    min-height: 0;
    max-height: none;
    padding: 0 12px 12px;
    gap: 0;
  }

  .productos.vacia {
    padding: 18px 14px;
  }

  .categoria {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 10px 8px 4px;
  }

  .categoria-nombre {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 8px;
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--tenue);
  }

  .todos {
    padding: 2px 6px;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--suave);
    font-size: 12px;
    font-weight: 600;
  }

  .todos:hover:not(:disabled) {
    color: var(--texto);
    background: var(--chip);
  }

  /* Las tarjetas, las de Crear anuncios (.prod): foto, nombre y precio; la elegida con su orilla de tinta.
     La palomita entra con el rebote de la caja del agente y la tarjeta se aprieta un poco al picarle. */
  .pt-rejilla {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    padding: 4px 0 6px;
  }

  .pt {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 6px 6px 10px;
    border: 1px solid var(--linea);
    border-radius: 14px;
    background: var(--solido);
    color: var(--texto);
    font: inherit;
    text-align: left;
    min-width: 0;
    cursor: pointer;
    transition:
      box-shadow 0.15s ease,
      border-color 0.15s ease,
      scale 0.15s ease;
  }

  .pt:active {
    scale: 0.97;
  }

  .pt[aria-checked='true'] {
    box-shadow: 0 0 0 2px var(--tinta);
    border-color: transparent;
  }

  .pt:focus-visible {
    outline: 2px solid var(--acento);
    outline-offset: 3px;
  }

  .pt-foto {
    height: 104px;
    border-radius: 10px;
    background: #000000 center / cover no-repeat;
  }

  .pt-textos {
    padding: 0 4px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .pt-nombre {
    font-size: 12.5px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pt-precio {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .pt-marca {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 22px;
    height: 22px;
    border-radius: 11px;
    display: grid;
    place-items: center;
    background: var(--tinta);
    color: var(--sobre-tinta);
    box-shadow: 0 0 0 2px var(--solido);
    opacity: 0;
    scale: 0.4;
    transition:
      opacity 0.15s ease,
      scale 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .pt-marca svg {
    width: 12px;
    height: 12px;
  }

  .pt[aria-checked='true'] .pt-marca {
    opacity: 1;
    scale: 1;
  }

  /* El inglés del grupo: la marquita «EN» de cada campo (como «AGOTADA», en tinta), lo que no cambia con el
     idioma se apaga, y el botón gira sus flechas. */
  .con-marca-en {
    position: relative;
  }

  .marca-en {
    position: absolute;
    right: 8px;
    top: 50%;
    translate: 0 -50%;
    padding: 3px 6px;
    border-radius: 6px;
    background: var(--tinta);
    color: var(--sobre-tinta);
    font-family: var(--mono);
    font-size: 9.5px;
    line-height: 1.2;
    letter-spacing: 0.1em;
    pointer-events: none;
    opacity: 0;
    scale: 0.6;
    transition:
      opacity 0.15s ease,
      scale 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .en-ingles-modo .marca-en {
    opacity: 1;
    scale: 1;
  }

  .en-ingles-modo .con-marca-en :global(input) {
    padding-right: 44px;
  }

  .en-ingles-modo .agotada .op-nombre {
    padding-right: 112px;
  }

  .en-ingles-modo .marca-agotada {
    right: 42px;
  }

  .se-apaga {
    transition: opacity 0.2s ease;
  }

  .en-ingles-modo .se-apaga {
    opacity: 0.35;
  }

  /* «Ver inglés»: la barra (rectángulo desde el 9 nov 2026) de las ventanas de producto y de categoría, sin abrirse. */
  .ver-ingles {
    margin-top: 4px;
    height: 48px;
    overflow: hidden;
    border-radius: 12px;
    background: var(--fondo); /* el gris de los grupos de campos (GrupoCampos), desde el 9 nov 2026 */
  }

  .ver-ingles-fila {
    width: 100%;
    min-height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 16px;
    border: 0;
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font: inherit;
    text-align: left;
    cursor: pointer;
  }

  .ver-ingles-fila:hover {
    background: var(--chip);
  }

  .ver-ingles-fila:focus-visible {
    outline: 2px solid var(--acento);
    outline-offset: -2px;
  }

  .vi-titulo {
    font-size: 13px;
    font-weight: 700;
    flex: none;
  }

  .vi-pista {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    text-align: right;
  }

  .vi-cambio {
    flex: none;
    color: var(--suave);
    transition: rotate 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  [aria-pressed='true'] .vi-cambio {
    rotate: 180deg;
  }

  @media (prefers-reduced-motion: reduce) {
    .paso-boton,
    .opcion input,
    .pt,
    .pt-marca,
    .marca-en,
    .se-apaga,
    .vi-cambio,
    .marca-agotada {
      transition: none;
    }
  }
</style>
