<!--
  Nuevo estilo y Corregir estilo (maqueta Estilos 7a H2yFVjosPvSV56DJD1Un71), copiada de la ventana
  de un producto de Mi menú: el nombre y el grupo; la clave, que sale sola del nombre mientras no la
  toquen y ya guardada sale con candado; lo que dice su cuadro; en De temporada, cuándo sale cada
  año (siempre, o del día y mes al día y mes, que pueden cruzar el año); sus tres muestras, cada una
  en la forma de su formato; y si su prompt ya está en el Worker. Al corregir, abajo a la izquierda,
  Eliminar estilo. El interruptor no vive aquí sino en su renglón: uno nuevo nace apagado.

  Las muestras siguen el orden de las fotos: al elegirla se revisa su forma y se ve tal cual; al
  guardar se suben las nuevas (post, historia y cartel), y si una subida o el guardado fallan, se
  borran de R2 las que se acababan de subir; ya guardado, se borran las viejas que cambiaron.
  Mientras guarda, la etiqueta de arriba dice en qué paso va (SUBIENDO MUESTRAS…, GUARDANDO…).
  Eliminar pide confirmar en su propia ventana; Cancelar regresa aquí con lo que ya se había
  escrito.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import Campo from '../../diseno/Campo.svelte';
  import CampoLista from '../../diseno/CampoLista.svelte';
  import Confirmar from '../../diseno/Confirmar.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../lib/errores';
  import {
    borrarMuestra,
    CLAVE_VALIDA,
    claveDe,
    DIAS_DEL_MES,
    eliminarEstilo,
    fechasDe,
    FORMATOS,
    GRUPOS,
    guardarEstilo,
    revisarMuestra,
    rutaMuestra,
    subirMuestra,
    type DatosEstilo,
    type Estilo,
    type Fechas,
    type Formato,
    type Grupo,
  } from '../../lib/estilos';
  import { MESES_LARGOS } from '../../lib/formato';
  import { urlFoto } from '../../lib/fotos';

  let {
    estilo,
    estilos,
    claves,
    alCambiar,
    alCerrar,
  }: {
    estilo: Estilo | null;
    estilos: Estilo[];
    claves: string[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  // Lo que llegó al abrir la ventana: no cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  const inicial = estilo ? { ...estilo } : null;
  const fechasIniciales = inicial ? fechasDe(inicial) : null;

  let nombre = $state(inicial?.nombre ?? '');
  let clave = $state(inicial?.clave ?? '');
  let claveTocada = false;
  let descripcion = $state(inicial?.descripcion ?? '');
  let grupo = $state<string>(inicial?.grupo ?? 'para_todos');
  let siempre = $state(!fechasIniciales);
  // Las que trae puestas «En unas fechas» si todavía no tenía: las de Día de Muertos.
  let fechas = $state<Fechas>(fechasIniciales ?? { desde_mes: 10, desde_dia: 15, hasta_mes: 11, hasta_dia: 2 });
  // Las muestras elegidas que todavía no se suben, y cómo se ven mientras.
  let archivos = $state<Record<Formato, File | null>>({ post: null, historia: null, cartel: null });
  let vistas = $state<Record<Formato, string | null>>({ post: null, historia: null, cartel: null });
  let rotas = $state<string[]>([]);
  let eligiendo: Formato | null = null;
  let error = $state<string | null>(null);
  let paso = $state<null | 'muestras' | 'guardando' | 'listo'>(null);
  let confirmando = $state(false);
  let elegirArchivo = $state<HTMLInputElement>();

  const etiqueta = $derived(
    paso === 'muestras'
      ? 'SUBIENDO MUESTRAS…'
      : paso === 'guardando'
        ? 'GUARDANDO…'
        : inicial
          ? 'CORREGIR ESTILO'
          : 'NUEVO ESTILO',
  );
  // Al corregir, la de su clave; en uno nuevo, la que va escrita.
  const tienePrompt = $derived(claves.includes(inicial ? inicial.clave : clave.trim()));

  onDestroy(() => {
    for (const f of FORMATOS) {
      const vista = vistas[f.valor];
      if (vista) URL.revokeObjectURL(vista);
    }
  });

  // A medio guardar no se cierra (como _cerrar() de Flet).
  function cerrar() {
    if (!paso) alCerrar();
  }

  // La clave sigue al nombre mientras no la toquen; ya guardada no cambia.
  function escribirNombre(valor: string) {
    nombre = valor;
    if (!inicial && !claveTocada) clave = claveDe(valor);
  }

  function escribirClave(valor: string) {
    clave = valor;
    claveTocada = true;
  }

  // Un mes más corto se lleva el día: del 31 de octubre a noviembre queda el 30.
  function cambiarMes(cual: 'desde' | 'hasta', mes: number) {
    if (cual === 'desde') {
      fechas.desde_mes = mes;
      fechas.desde_dia = Math.min(fechas.desde_dia, DIAS_DEL_MES[mes - 1]);
    } else {
      fechas.hasta_mes = mes;
      fechas.hasta_dia = Math.min(fechas.hasta_dia, DIAS_DEL_MES[mes - 1]);
    }
  }

  const diasDe = (mes: number) => Array.from({ length: DIAS_DEL_MES[mes - 1] }, (_, i) => i + 1);

  // Lo que se ve en el cuadro de cada muestra: la recién elegida tal cual, o la guardada.
  function verMuestra(formato: Formato): string | null {
    const vista = vistas[formato];
    if (vista) return vista;
    const ruta = inicial ? rutaMuestra(inicial, formato) : null;
    return ruta ? urlFoto(ruta) : null;
  }

  function elegirMuestra(formato: Formato) {
    if (paso) return;
    eligiendo = formato;
    elegirArchivo?.click();
  }

  async function alElegirMuestra(e: Event & { currentTarget: HTMLInputElement }) {
    const elegido = e.currentTarget.files?.[0];
    e.currentTarget.value = '';
    const formato = eligiendo;
    if (!elegido || !formato || paso) return;
    const problema = await revisarMuestra(elegido, formato);
    if (problema) {
      error = problema;
      return;
    }
    error = null;
    const vieja = vistas[formato];
    if (vieja) URL.revokeObjectURL(vieja);
    archivos[formato] = elegido;
    vistas[formato] = URL.createObjectURL(elegido);
  }

  // Lo de antes de subir nada, los textos de la maqueta: para no subir muestras de un estilo que
  // no se va a poder guardar. Postgres revisa lo mismo.
  function validar(): DatosEstilo | string {
    const limpio = nombre.trim();
    const cuadro = descripcion.trim();
    const suClave = inicial ? inicial.clave : clave.trim();
    if (!limpio) return 'Escribe el nombre del estilo.';
    if (!cuadro) return 'Escribe lo que dice su cuadro.';
    if (!CLAVE_VALIDA.test(suClave)) return 'La clave lleva solo letras sin acento, números y guiones: dia-de-muertos.';
    const otro = estilos.find(
      (e) => e.id !== inicial?.id && (e.clave === suClave || e.nombre.toLowerCase() === limpio.toLowerCase()),
    );
    if (otro) {
      return otro.clave === suClave ? `Ya hay un estilo con la clave ${suClave}.` : `Ya hay un estilo que se llama ${otro.nombre}.`;
    }
    return {
      clave: suClave,
      nombre: limpio,
      descripcion: cuadro,
      grupo: grupo as Grupo,
      fechas: grupo === 'temporada' && !siempre ? { ...fechas } : null,
      muestras: {
        post: inicial?.muestra_post_ruta ?? null,
        historia: inicial?.muestra_historia_ruta ?? null,
        cartel: inicial?.muestra_cartel_ruta ?? null,
      },
    };
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const datos = validar();
    if (typeof datos === 'string') return { error: datos };

    const subidas: string[] = [];
    let viejas: string[];
    try {
      if (FORMATOS.some((f) => archivos[f.valor])) {
        paso = 'muestras';
        for (const f of FORMATOS) {
          const archivo = archivos[f.valor];
          if (!archivo) continue;
          const ruta = await subirMuestra(datos.clave, f.valor, archivo);
          subidas.push(ruta);
          datos.muestras[f.valor] = ruta;
        }
      }
      paso = 'guardando';
      viejas = await guardarEstilo(inicial?.id ?? null, datos);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[estilos] no se pudo guardar el estilo:', falla);
      // Las muestras de un estilo que no se guardó no se quedan en R2.
      for (const ruta of subidas) await borrarMuestra(ruta);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }

    // Ya guardado: las muestras que se cambiaron ya no las usa nadie.
    for (const ruta of viejas) await borrarMuestra(ruta);
    paso = 'listo';
    alCambiar();
    return { listo: inicial ? 'Guardado' : 'Agregado' };
  }

  // Las muestras que ya tiene guardadas, para el texto de la confirmación.
  const guardadas = inicial ? FORMATOS.filter((f) => rutaMuestra(inicial, f.valor)).length : 0;

  async function eliminar(): Promise<{ listo: string } | { error: string }> {
    if (!inicial) return { error: ALGO_SALIO_PANEL };
    try {
      const rutas = await eliminarEstilo(inicial.id);
      for (const ruta of rutas) await borrarMuestra(ruta);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[estilos] no se pudo eliminar el estilo:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    alCambiar();
    return { listo: 'Eliminado' };
  }
</script>

{#if confirmando && inicial}
  <Confirmar
    icono="eliminar"
    titulo="¿Eliminar {inicial.nombre}?"
    texto="{guardadas ? `Se borra con ${guardadas === 1 ? 'su muestra' : `sus ${guardadas} muestras`} de R2. ` : ''}No se puede deshacer."
    boton={{ etiqueta: 'Sí, eliminar', icono: 'eliminar' }}
    textoCargando="Eliminando…"
    confirmar={eliminar}
    alCerrar={() => (confirmando = false)}
    alTerminar={alCerrar}
  />
{:else}
  <Ventana {etiqueta} titulo={inicial ? inicial.nombre : 'Agrega un estilo'} ancho={600} relleno="24px 28px" alCerrar={cerrar}>
    <Formulario
      boton={inicial ? { etiqueta: 'Guardar cambios', icono: 'check' } : { etiqueta: 'Agregar estilo', icono: 'mas' }}
      {guardar}
      alTerminar={alCerrar}
      bind:error
      espacio={0}
      arriba={18}
    >
      <div class="estilo">
        <div class="dos">
          <Campo
            id="estilo-nombre"
            etiqueta="NOMBRE"
            bind:valor={() => nombre, escribirNombre}
            placeholder="Ej. Día de Muertos"
            largoMaximo={30}
          />
          <div class="grupo">
            <CampoLista
              id="estilo-grupo"
              etiqueta="GRUPO"
              bind:valor={grupo}
              grupos={[{ etiqueta: '', opciones: GRUPOS.map((g) => ({ valor: g.valor, texto: g.texto })) }]}
            />
          </div>
        </div>

        {#if inicial}
          <div class="clave-fija">
            <Icono nombre="candado" tamano={14} />
            <span class="clave">{inicial.clave}</span>
            <span class="pista">No cambia: es su carpeta en R2 y la une con su prompt.</span>
          </div>
        {:else}
          <div class="bloque">
            <Campo
              id="estilo-clave"
              etiqueta="CLAVE"
              bind:valor={() => clave, escribirClave}
              placeholder="dia-de-muertos"
              corrector={false}
              largoMaximo={40}
              mono
              pista="Sale sola del nombre. Ya guardada no cambia: es su carpeta en R2 y la une con su prompt."
            />
          </div>
        {/if}

        <div class="bloque">
          <Campo
            id="estilo-cuadro"
            etiqueta="LO QUE DICE SU CUADRO"
            bind:valor={descripcion}
            placeholder="Ej. Tu producto en el altar, entre cempasúchil y velas."
            largoMaximo={80}
            contador
          />
        </div>

        {#if grupo === 'temporada'}
          <div class="bloque campo">
            <span class="etiqueta">CUÁNDO SALE · CADA AÑO</span>
            <div class="cuando">
              <Selector
                etiqueta="Cuándo sale"
                opciones={[
                  { valor: 'siempre', texto: 'Siempre' },
                  { valor: 'fechas', texto: 'En unas fechas' },
                ]}
                elegida={siempre ? 'siempre' : 'fechas'}
                alElegir={(v) => (siempre = v === 'siempre')}
              />
              {#if siempre}
                <span class="pista">Como el fútbol: todo el año.</span>
              {:else}
                <div class="fechas">
                  Del
                  <select class="dia" aria-label="Día en que empieza" bind:value={fechas.desde_dia}>
                    {#each diasDe(fechas.desde_mes) as d (d)}<option value={d}>{d}</option>{/each}
                  </select>
                  <select
                    class="mes"
                    aria-label="Mes en que empieza"
                    value={fechas.desde_mes}
                    onchange={(e) => cambiarMes('desde', Number(e.currentTarget.value))}
                  >
                    {#each MESES_LARGOS as m, i (m)}<option value={i + 1}>{m}</option>{/each}
                  </select>
                  al
                  <select class="dia" aria-label="Día en que termina" bind:value={fechas.hasta_dia}>
                    {#each diasDe(fechas.hasta_mes) as d (d)}<option value={d}>{d}</option>{/each}
                  </select>
                  <select
                    class="mes"
                    aria-label="Mes en que termina"
                    value={fechas.hasta_mes}
                    onchange={(e) => cambiarMes('hasta', Number(e.currentTarget.value))}
                  >
                    {#each MESES_LARGOS as m, i (m)}<option value={i + 1}>{m}</option>{/each}
                  </select>
                </div>
              {/if}
            </div>
          </div>
        {/if}

        <div class="bloque muestras-campo campo">
          <div class="etiqueta-fila">
            <span class="etiqueta">MUESTRAS</span>
            <span class="pista">Se hacen WebP de 1600 px · cada una en su forma</span>
          </div>
          <div class="muestras">
            {#each FORMATOS as f (f.valor)}
              {@const src = verMuestra(f.valor)}
              {@const hay = src && !rotas.includes(src)}
              <div class="muestra">
                <div class="caja {f.valor}" class:vacia={!src}>
                  {#if hay}
                    <img
                      {src}
                      alt=""
                      onerror={() => {
                        console.error('[estilos] no cargó la muestra', src);
                        if (src) rotas.push(src);
                      }}
                    />
                  {:else if !src}
                    <Icono nombre={f.valor} tamano={22} />
                  {/if}
                  {#if paso === 'muestras' && archivos[f.valor]}<span class="subiendo">SUBIENDO…</span>{/if}
                </div>
                <div class="pie-muestra">
                  <span class="nombre-muestra">{f.texto}</span>
                  <span class="forma">{f.forma}</span>
                </div>
                <Boton
                  tamano="chico"
                  etiqueta={src ? 'Cambiar' : 'Agregar'}
                  icono={src ? 'crear' : 'mas'}
                  apagado={paso !== null}
                  onclick={() => elegirMuestra(f.valor)}
                />
              </div>
            {/each}
          </div>
          <input bind:this={elegirArchivo} type="file" accept="image/*" hidden onchange={alElegirMuestra} />
        </div>

        <div class="bloque linea-prompt">
          <span class="vis" class:no={!tienePrompt}><span class="p"></span></span>
          <span>
            {tienePrompt
              ? 'Su prompt ya está en el Worker.'
              : inicial
                ? 'Su prompt todavía no está en el Worker: hasta que llegue, no les sale a los clientes.'
                : 'Su prompt todavía no está en el Worker. Nace apagado.'}
          </span>
        </div>
      </div>

      {#snippet izquierda()}
        {#if inicial}
          <Boton
            etiqueta="Eliminar estilo"
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
  .estilo {
    display: flex;
    flex-direction: column;
  }

  /* La clave va en mono de 12 (fija) o de 13 (al escribirla). */
  .estilo :global(input.mono) {
    font-size: 13px;
  }

  .bloque {
    margin-top: 14px;
  }

  .dos {
    display: flex;
    align-items: flex-start;
    gap: 16px;
  }

  .dos > :global(:first-child) {
    flex: 1;
  }

  .grupo {
    width: 190px;
    flex: none;
  }

  .clave-fija {
    margin-top: 10px;
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--tenue);
  }

  .clave {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--texto);
  }

  .clave-fija .pista {
    margin-left: 4px;
  }

  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .etiqueta-fila {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .cuando {
    display: flex;
    align-items: center;
    gap: 14px;
    flex-wrap: wrap;
  }

  .fechas {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
  }

  select {
    height: 38px;
    padding: 0 10px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
  }

  select:focus {
    border-color: var(--suave);
  }

  .dia {
    width: 64px;
  }

  .mes {
    width: 128px;
  }

  .muestras-campo {
    margin-top: 16px;
  }

  /* Las tres muestras, cada una en la forma de su formato y del mismo alto. */
  .muestras {
    display: flex;
    align-items: flex-end;
    gap: 24px;
  }

  .muestra {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }

  .caja {
    position: relative;
    height: 124px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    border-radius: 12px;
    background: #000000;
  }

  .caja.post {
    width: 99px;
  }

  .caja.historia {
    width: 70px;
  }

  .caja.cartel {
    width: 220px;
  }

  .caja img {
    width: 100%;
    height: 100%;
    display: block;
    object-fit: cover;
  }

  .caja.vacia {
    background: transparent;
    border: 1.5px dashed var(--linea-fuerte);
    color: var(--tenue);
  }

  .subiendo {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.45);
    color: #ffffff;
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.1em;
  }

  .pie-muestra {
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  .nombre-muestra {
    font-size: 13px;
    font-weight: 700;
  }

  .forma {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .linea-prompt {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 11px 14px;
    border: 1px solid var(--linea);
    border-radius: 14px;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .vis {
    flex: none;
    display: inline-flex;
    align-items: center;
  }

  .vis .p {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    background: var(--tinta);
  }

  .vis.no .p {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }
</style>
