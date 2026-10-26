<!--
  Nuevo grupo y Editar grupo (maqueta de Opciones y áreas GhrEVWPmevfBZtWzi4exKi), en dos columnas.
  A la izquierda: el nombre, cuántas se eligen (mínimo y máximo con − y +, nunca más que sus
  opciones, y una frase que lo dice en palabras) y las opciones, cada una con su precio extra (vacío
  es $0), su ojito de agotada, sus flechas y su X. A la derecha, los productos que lo llevan, por
  categoría, con «Todos». Todo se guarda junto con Agregar grupo o Guardar cambios (guardar_grupo):
  el ojito también. Al editar, abajo a la izquierda, Eliminar grupo pide confirmar y dice en
  cuántos productos está.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Confirmar from '../../../diseno/Confirmar.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import IconoCategoria from '../../../diseno/IconoCategoria.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { plural } from '../../../lib/formato';
  import { eliminarGrupo, guardarGrupo, type Grupo, type Menu } from '../../../lib/menu';
  import { frase } from '../../../lib/opciones';
  import EnIngles from './EnIngles.svelte';

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

  const cuantas = $derived(opciones.length);
  // Por categoría, en el orden del menú; las que no tienen productos no salen. Un envío no lleva
  // opciones (parte 6b).
  const porCategoria = $derived(
    menu.categorias
      .map((c) => ({ categoria: c, productos: menu.productos.filter((p) => p.categoria_id === c.id && !p.es_envio) }))
      .filter((x) => x.productos.length),
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

  function alternarCategoria(lista: { id: number }[]) {
    const todos = lista.every((p) => productos.has(p.id));
    for (const p of lista) {
      if (todos) productos.delete(p.id);
      else productos.add(p.id);
    }
  }

  function alternarProducto(id: number) {
    if (productos.has(id)) productos.delete(id);
    else productos.add(id);
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
      <button type="button" class="paso-boton" aria-label="{etiqueta}: uno menos" disabled={sinMenos || paso !== null} onclick={menos}>
        <Icono nombre="menos" tamano={14} />
      </button>
      <span class="paso-valor">{valor}</span>
      <button type="button" class="paso-boton" aria-label="{etiqueta}: uno más" disabled={sinMas || paso !== null} onclick={mas}>
        <Icono nombre="mas" tamano={14} />
      </button>
    </div>
  </div>
{/snippet}

{#if confirmando && inicial}
  <Confirmar
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
    ancho={880}
    alCerrar={cerrar}
  >
    <Formulario
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar grupo', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={0}
      antesDelBoton={28}
    >
      <div class="dos-columnas">
        <div class="columna">
          <Campo id="grupo-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Salsa" />

          <div class="campo">
            <span class="etiqueta">CUÁNTAS SE ELIGEN</span>
            <div class="pasos">
              {@render contador('Mínimo', minimo, () => cambiarMinimo(-1), () => cambiarMinimo(1), minimo <= 0, minimo >= cuantas)}
              {@render contador('Máximo', maximo, () => cambiarMaximo(-1), () => cambiarMaximo(1), maximo <= 1, maximo >= Math.max(cuantas, 1))}
            </div>
            <p class="frase">{frase(minimo, maximo)}</p>
          </div>

          <div class="campo">
            <div class="etiquetas"><span class="etiqueta">OPCIONES</span><span class="etiqueta">PRECIO EXTRA</span></div>
            <div class="opciones" bind:this={listaOpciones}>
              {#each opciones as o, i (o.clave)}
                <div class="opcion" class:agotada={!o.visible}>
                  <span class="opcion-nombre">
                    <input
                      class="op-nombre"
                      bind:value={o.nombre}
                      placeholder="Ej. Verde"
                      aria-label="Nombre de la opción {i + 1}"
                      autocomplete="off"
                      disabled={paso !== null}
                    />
                    {#if !o.visible}<span class="marca-agotada">AGOTADA</span>{/if}
                  </span>
                  <span class="precio">
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
                </div>
              {/each}
            </div>
            <div><Boton etiqueta="Agregar opción" icono="mas" tamano="chico" apagado={paso !== null} onclick={agregarOpcion} /></div>
            <p class="pista">El precio extra se suma al del producto; vacío es $0. El ojito marca una opción agotada.</p>
          </div>

          <EnIngles>
            <div class="en-op">
              <span>{nombre.trim() || 'Grupo'}</span>
              <input
                bind:value={nombreEn}
                placeholder={nombre.trim()}
                aria-label="{nombre.trim() || 'El grupo'} en inglés"
                autocomplete="off"
                disabled={paso !== null}
              />
            </div>
            {#each opciones as o, i (o.clave)}
              <div class="en-op">
                <span>{o.nombre.trim() || `Opción ${i + 1}`}</span>
                <input
                  bind:value={o.ingles}
                  placeholder={o.nombre.trim()}
                  aria-label="{o.nombre.trim() || `Opción ${i + 1}`} en inglés"
                  autocomplete="off"
                  disabled={paso !== null}
                />
              </div>
            {/each}
          </EnIngles>
        </div>

        <div class="columna">
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
              <div class="productos">
                {#each porCategoria as { categoria, productos: suyos } (categoria.id)}
                  <div class="categoria">
                    <span class="categoria-nombre"><IconoCategoria id={categoria.icono} tamano={14} />{categoria.nombre}</span>
                    <button type="button" class="todos" disabled={paso !== null} onclick={() => alternarCategoria(suyos)}>
                      {suyos.every((p) => productos.has(p.id)) ? 'Quitar todos' : 'Todos'}
                    </button>
                  </div>
                  {#each suyos as p (p.id)}
                    {@const elegido = productos.has(p.id)}
                    <button
                      type="button"
                      class="producto"
                      role="checkbox"
                      aria-checked={elegido}
                      disabled={paso !== null}
                      onclick={() => alternarProducto(p.id)}
                    >
                      <span class="cajita">{#if elegido}<Icono nombre="check" tamano={11} />{/if}</span>
                      <span>{p.nombre}{#if !p.visible}{' '}<span class="oculto">· oculto</span>{/if}</span>
                    </button>
                  {/each}
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
    grid-template-columns: minmax(0, 1fr) 320px;
    gap: 28px;
    align-items: start;
  }

  .columna {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 18px;
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

  .paso-caja {
    height: 40px;
    display: inline-flex;
    align-items: center;
    border: 1px solid var(--linea);
    border-radius: 12px;
    overflow: hidden;
  }

  .paso-boton {
    width: 36px;
    height: 38px;
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

  .opcion input {
    width: 100%;
    height: 40px;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: transparent;
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
  }

  .opcion input:focus {
    border-color: var(--suave);
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
    background: var(--chip);
    font-family: var(--mono);
    font-size: 9.5px;
    letter-spacing: 0.1em;
    color: var(--suave);
    pointer-events: none;
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

  .producto {
    width: 100%;
    min-height: 36px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 8px;
    border: 0;
    border-radius: 10px;
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    text-align: left;
    transition: background-color 150ms;
  }

  .producto:hover:not(:disabled) {
    background: var(--chip);
  }

  .cajita {
    width: 18px;
    height: 18px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1.5px solid var(--tenue);
    border-radius: 5px;
    background: var(--solido);
  }

  .producto[aria-checked='true'] .cajita {
    border: 0;
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .oculto {
    font-weight: 500;
    color: var(--tenue);
  }

  /* El inglés: el nombre en español a la izquierda y su campo a la derecha, uno por renglón. */
  .en-op {
    display: grid;
    grid-template-columns: 110px 1fr;
    align-items: center;
    gap: 12px;
  }

  .en-op span {
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .en-op input {
    height: 40px;
    width: 100%;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 10px;
    font-size: 13px;
    font-weight: 400;
    color: var(--texto);
    outline: none;
  }

  .en-op input:focus {
    border-color: var(--suave);
  }

  .en-op input::placeholder {
    color: var(--tenue);
  }

  @media (prefers-reduced-motion: reduce) {
    .paso-boton,
    .producto {
      transition: none;
    }
  }
</style>
