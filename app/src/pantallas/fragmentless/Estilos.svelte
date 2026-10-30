<!--
  Estilos (parte 7a de la libreta 7), portada de la maqueta aprobada el 29 de octubre de 2026
  (H2yFVjosPvSV56DJD1Un71), que copia la tabla de Mi menú: los estilos de los anuncios de Crear
  contenido en el orden en que salen en la ventana de Don Chuy, con sus grupos como separadores.
  Cada renglón: la muestra de post chiquita (negra si no tiene), el nombre, la clave y, en los de
  temporada, sus fechas; lo que dice su cuadro; si les sale a los clientes y, si no, todo lo que le
  falta; el interruptor; las flechas (dentro de su grupo) y el lápiz, que abre su ventana. Arriba,
  cuántos les salen hoy, Actualizar y Nuevo estilo. Es la única vista del panel de Fragmentless
  con su propia barra de arriba.

  Lee dos cosas a la vez, al entrar, con Actualizar y después de guardar o eliminar: la tabla
  (panel_estilos) y las claves que ya tienen su prompt en el Worker (GET /estilos). Si una de las
  dos falla, sale «No se pudo leer» entero: sin la lista del Worker no se sabe a quién le falta su
  prompt. El interruptor cambia cuando Postgres dice que sí y las flechas mueven el renglón al
  momento; si algo falla, sale el aviso de abajo y la tabla se vuelve a leer.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import AvisoFlotante from '../../diseno/AvisoFlotante.svelte';
  import BarraArriba from '../../diseno/BarraArriba.svelte';
  import Boton from '../../diseno/Boton.svelte';
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import Interruptor from '../../diseno/Interruptor.svelte';
  import NotaTabla from '../../diseno/NotaTabla.svelte';
  import Tabla from '../../diseno/Tabla.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import {
    fechasDe,
    GRUPOS,
    leerEstilos,
    moverEstilo,
    porQueNoSale,
    prenderEstilo,
    rangoCorto,
    ultimoDia,
    type DatosEstilos,
    type Estilo,
  } from '../../lib/estilos';
  import { plural } from '../../lib/formato';
  import { urlFoto } from '../../lib/fotos';
  import type { Lectura } from '../../lib/panel';
  import VentanaEstilo from './VentanaEstilo.svelte';

  let lectura = $state<Lectura<DatosEstilos> | null>(null);
  let leyendo = $state(false);
  let ventana = $state<{ estilo: Estilo | null } | null>(null);
  let aviso = $state<string | null>(null);
  let tarjeta = $state<HTMLElement>();
  // Las muestras de post que no cargaron: se quedan en su cuadro negro, como la foto que falta.
  let rotas = $state<string[]>([]);
  // Si se pide leer otra vez antes de que termine la lectura anterior, gana la última.
  let turno = 0;

  const datos = $derived(lectura?.ok ? lectura.datos : null);

  async function leer() {
    const mio = ++turno;
    leyendo = true;
    const nueva = await leerEstilos();
    if (mio !== turno) return;
    lectura = nueva;
    leyendo = false;
  }

  onMount(leer);

  // El chip: cuántos les salen hoy a los clientes, con el punto hueco si ninguno; si no se pudo
  // leer, por qué.
  const estado = $derived.by(() => {
    if (!lectura) return null;
    if (!lectura.ok) return { texto: lectura.deRed ? 'Sin conexión' : 'No se pudo leer', vivo: false, hueco: true };
    const { estilos, claves } = lectura.datos;
    const salen = estilos.filter((e) => !porQueNoSale(e, claves).length).length;
    return { texto: `${salen} de ${estilos.length} les salen a los clientes`, vivo: salen > 0, hueco: salen === 0 };
  });

  // «futbol · siempre», «dia-de-muertos · 15 oct–2 nov»; los de Para todos, solo la clave.
  function debajo(e: Estilo) {
    if (e.grupo !== 'temporada') return e.clave;
    const fechas = fechasDe(e);
    return `${e.clave} · ${fechas ? rangoCorto(fechas) : 'siempre'}`;
  }

  // El interruptor, como el ojito de Mi menú: cambia cuando Postgres dice que sí.
  async function prender(e: Estilo, prendido: boolean) {
    try {
      await prenderEstilo(e.id, prendido);
    } catch (falla) {
      aviso = (falla as Error).message;
      await leer();
      return;
    }
    e.prendido = prendido;
  }

  // Las flechas, como las de Categorías: el renglón se mueve al momento, dentro de su grupo, y se
  // guarda; si Postgres no pudo, sale el aviso y se vuelve a leer lo que de verdad quedó.
  async function mover(e: Estilo, hacia: 'arriba' | 'abajo') {
    if (!datos) return;
    const lista = datos.estilos;
    const delGrupo = lista.filter((x) => x.grupo === e.grupo);
    const aqui = delGrupo.findIndex((x) => x.id === e.id);
    const otro = delGrupo[hacia === 'arriba' ? aqui - 1 : aqui + 1];
    if (aqui < 0 || !otro) return;
    const a = lista.findIndex((x) => x.id === e.id);
    const b = lista.findIndex((x) => x.id === otro.id);
    [lista[a], lista[b]] = [lista[b], lista[a]];
    await tick();
    const atributo = hacia === 'arriba' ? 'data-subir' : 'data-bajar';
    const boton = tarjeta?.querySelector<HTMLButtonElement>(`[${atributo}="${e.id}"]`);
    if (boton && !boton.disabled) boton.focus({ preventScroll: true });
    try {
      await moverEstilo(e.id, hacia);
    } catch (falla) {
      aviso = (falla as Error).message;
      await leer();
    }
  }
</script>

<BarraArriba titulo="Estilos" {estado}>
  <Boton etiqueta="Actualizar" icono="actualizar" apagado={leyendo} onclick={leer} />
  <Boton
    etiqueta="Nuevo estilo"
    icono="mas"
    tono="tinta"
    apagado={!datos}
    onclick={() => (ventana = { estilo: null })}
  />
</BarraArriba>

<main class="cuerpo" bind:this={tarjeta}>
  <Vidrio como="section" class="tarjeta-estilos" radio={26} aria-label="Estilos">
    <div class="herramientas">
      <p class="nota">
        Así salen en la ventana de Crear contenido de cada restaurante: por grupos y, en cada grupo, de
        arriba abajo. Muévelos con las flechas.
      </p>
      <span class="crece"></span>
      <span class="etiqueta">{datos ? plural(datos.estilos.length, 'ESTILO', 'ESTILOS') : ''}</span>
    </div>

    <Tabla
      columnas="2.2fr 2.6fr 2.2fr 84px 128px"
      relleno="0 16px"
      altoFila={72}
      encabezados={[
        { texto: 'ESTILO' },
        { texto: 'LO QUE DICE SU CUADRO' },
        { texto: 'A LOS CLIENTES' },
        { texto: 'PRENDIDO' },
        { texto: '' },
      ]}
    >
      {#if !lectura}
        <!-- leyendo la primera vez -->
      {:else if !lectura.ok}
        <NotaTabla relleno={48} angosta titulo="No pudimos leer los estilos." texto="Revisa tu conexión y toca Actualizar." />
      {:else if !lectura.datos.estilos.length}
        <NotaTabla relleno={48} angosta titulo="Todavía no hay estilos." texto="Agrega el primero con Nuevo estilo." />
      {:else}
        {@const { estilos, claves } = lectura.datos}
        {#each GRUPOS as g (g.valor)}
          {@const delGrupo = estilos.filter((e) => e.grupo === g.valor)}
          <div class="fila-grupo">
            <span class="etiqueta">{g.texto.toUpperCase()}</span>
            <span class="cuenta">{delGrupo.length}</span>
          </div>
          {#each delGrupo as e, i (e.id)}
            {@const razones = porQueNoSale(e, claves)}
            {@const fechas = fechasDe(e)}
            <div class="fila">
              <span class="estilo">
                <span class="mini" class:apagado={!e.prendido}>
                  {#if e.muestra_post_ruta && !rotas.includes(e.muestra_post_ruta)}
                    {@const ruta = e.muestra_post_ruta}
                    <img
                      src={urlFoto(ruta)}
                      alt=""
                      loading="lazy"
                      decoding="async"
                      onerror={() => {
                        console.error('[estilos] no cargó la muestra', ruta);
                        rotas.push(ruta);
                      }}
                    />
                  {/if}
                </span>
                <span class="textos">
                  <span class="nombre">{e.nombre}</span>
                  <span class="clave">{debajo(e)}</span>
                </span>
              </span>
              <span class="descripcion">{e.descripcion}</span>
              <span class="sale">
                {#if !razones.length}
                  <span class="vis"><span class="p"></span>Les sale</span>
                  {#if fechas}<span class="porque">Hasta el {ultimoDia(fechas)}</span>{/if}
                {:else}
                  <span class="vis no"><span class="p"></span>No les sale</span>
                  <span class="porque">{razones.join(' · ')}</span>
                {/if}
              </span>
              <span>
                <Interruptor prendido={e.prendido} ayuda="Prendido: {e.nombre}" alCambiar={(v) => prender(e, v)} />
              </span>
              <span class="acciones">
                <BotonCuadro
                  icono="arriba"
                  ayuda="Subir"
                  etiqueta="Subir {e.nombre}"
                  apagado={i === 0}
                  data-subir={e.id}
                  onclick={() => mover(e, 'arriba')}
                />
                <BotonCuadro
                  icono="abajo"
                  ayuda="Bajar"
                  etiqueta="Bajar {e.nombre}"
                  apagado={i === delGrupo.length - 1}
                  data-bajar={e.id}
                  onclick={() => mover(e, 'abajo')}
                />
                <BotonCuadro
                  icono="crear"
                  ayuda="Corregir"
                  etiqueta="Corregir {e.nombre}"
                  onclick={() => (ventana = { estilo: e })}
                />
              </span>
            </div>
          {/each}
        {/each}
      {/if}
    </Tabla>
  </Vidrio>
</main>

{#if datos && ventana}
  <VentanaEstilo
    estilo={ventana.estilo}
    estilos={datos.estilos}
    claves={datos.claves}
    alCambiar={leer}
    alCerrar={() => (ventana = null)}
  />
{/if}

{#if aviso}
  {#key aviso}
    <AvisoFlotante mensaje={aviso} alTerminar={() => (aviso = null)} />
  {/key}
{/if}

<style>
  /* Debajo de la barra de arriba (16 + 60 + 16) y a la derecha de la lateral (16 + 244 + 16). */
  .cuerpo {
    position: absolute;
    left: 276px;
    right: 16px;
    top: 92px;
    bottom: 16px;
  }

  .cuerpo > :global(.tarjeta-estilos) {
    height: 100%;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .herramientas {
    flex: none;
    min-height: 40px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .crece {
    flex-grow: 1;
  }

  /* El separador de cada grupo, con cuántos estilos tiene. */
  .fila-grupo {
    height: 36px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 16px;
    background: var(--chip);
    border-bottom: 1px solid var(--linea);
  }

  .fila-grupo .etiqueta {
    color: var(--suave);
  }

  .cuenta {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .estilo {
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  /* La muestra de post en 4:5, negra si no tiene (como la foto que falta), al 45 % si está apagado. */
  .mini {
    width: 40px;
    height: 50px;
    flex: none;
    overflow: hidden;
    border-radius: 8px;
    background: #000000;
  }

  .mini.apagado {
    opacity: 0.45;
  }

  .mini img {
    width: 100%;
    height: 100%;
    display: block;
    object-fit: cover;
  }

  .textos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13.5px;
    font-weight: 700;
  }

  .clave {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .descripcion {
    min-width: 0;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
  }

  .sale {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .vis {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 600;
  }

  .vis .p {
    width: 8px;
    height: 8px;
    flex: none;
    border-radius: 4px;
    background: var(--tinta);
  }

  .vis.no {
    font-weight: 500;
    color: var(--tenue);
  }

  .vis.no .p {
    background: transparent;
    border: 1.5px solid var(--tenue);
  }

  .porque {
    min-width: 0;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    padding-left: 16px;
    font-size: 11.5px;
    line-height: 1.4;
    color: var(--suave);
  }

  .acciones {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
</style>
