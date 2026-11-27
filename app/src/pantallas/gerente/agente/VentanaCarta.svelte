<!--
  «Tu carta» (el menú con IA; maqueta 1Y6NCBNSZwWCVatj17iCDA, «Lo que elegí yo» 3 a 5 de la v1): se abre desde
  «Armar mi menú con tu carta» del «+» (también con tope 0) y desde Mi menú vacío. Vacía, la caja de la foto de Mi menú
  (con Riffle) para elegir o arrastrar hasta 6 fotos o un PDF de hasta 6 páginas. Con hojas, 4 por renglón en 3:4, cada
  una con su ✕ y «HOJA 1» abajo, y «Agregar otra hoja» punteada hasta 6; las hojas entran con el resorte de las listas.
  Un PDF va como una sola hoja con sus páginas. Abajo, fijo, cuántas cartas quedan este mes (puedo_leer_carta: su
  esqueleto mientras llega) y «Leer mi carta» en verde; sin cartas, la nota ámbar y todo apagado.
  Las fotos no se guardan: se las lleva el Agente IA a la plática y de ahí al Worker.
-->
<script lang="ts">
  import { onMount, tick } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import BotonCuadro from '../../../diseno/BotonCuadro.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { elegirHojas, leerCartasDelMes, MAXIMO_HOJAS, soltarHojas, type CartasDelMes, type Hoja } from '../../../lib/carta';
  import { esDeRed, SIN_CONEXION } from '../../../lib/errores';
  import { diaYMes } from '../../../lib/formato';
  import CajaFoto from '../menu/CajaFoto.svelte';

  let {
    restauranteId,
    iniciales = [],
    alLeer,
    alCerrar,
  }: {
    restauranteId: string;
    // Lo que se soltó en el Agente IA y no entra en su caja (un PDF): entra aquí al abrir.
    iniciales?: File[];
    alLeer: (hojas: Hoja[]) => void;
    alCerrar: () => void;
  } = $props();

  let hojas = $state<Hoja[]>([]);
  let cartas = $state<CartasDelMes | null>(null);
  let error = $state<string | null>(null);
  let otra = $state<HTMLInputElement | null>(null);
  let leyendo = false;
  // Las hojas entran con su resorte solo la primera vez que salen (como la maqueta).
  let primera = true;

  const sinCartas = $derived(!!cartas && !cartas.puede);
  const hayPdf = $derived(hojas.some((h) => h.tipo === 'pdf'));
  const quieto = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  onMount(() => {
    if (iniciales.length) agregar(iniciales);
    leerCartasDelMes(restauranteId)
      .then((c) => (cartas = c))
      .catch((falla) => {
        console.error('[carta] no se pudo leer cuántas cartas quedan:', falla);
        error = esDeRed(falla) ? SIN_CONEXION : 'No pudimos ver cuántas cartas te quedan este mes. Cierra y vuelve a intentarlo.';
      });
    // Si se cierra sin leer, las miniaturas se sueltan; si se leyó, se las lleva la plática.
    return () => {
      if (!leyendo) soltarHojas(hojas);
    };
  });

  async function agregar(archivos: File[]) {
    if (sinCartas) return;
    if (hojas.length >= MAXIMO_HOJAS) return;
    error = null;
    const r = await elegirHojas(archivos, hojas);
    hojas = [...hojas, ...r.hojas];
    error = r.problema;
    if (!r.problema && archivos.filter((a) => a.type.startsWith('image/')).length > r.hojas.length && r.hojas.length) {
      error = `Caben ${MAXIMO_HOJAS} hojas: no agregué las demás.`;
    }
    await tick();
    primera = false;
  }

  function quitar(i: number) {
    soltarHojas([hojas[i]]);
    hojas = hojas.filter((_, j) => j !== i);
    error = null;
  }

  function entra(nodo: HTMLElement, i: number) {
    if (quieto || !primera) return;
    nodo.animate(
      [
        { opacity: 0, transform: 'translateY(14px) scale(0.96)' },
        { opacity: 1, transform: 'none' },
      ],
      { duration: 420, delay: i * 60, easing: 'cubic-bezier(0.34, 1.4, 0.64, 1)', fill: 'backwards' },
    );
  }

  function leer() {
    if (!hojas.length || !cartas?.puede) return;
    leyendo = true;
    alLeer(hojas);
  }

  function alElegirOtra(e: Event & { currentTarget: HTMLInputElement }) {
    const archivos = [...(e.currentTarget.files ?? [])];
    e.currentTarget.value = '';
    if (archivos.length) agregar(archivos);
  }
</script>

<Ventana
  etiqueta="ARMAR MI MENÚ"
  titulo="Tu carta"
  ancho={640}
  centrado
  textoArriba
  texto="Sube una foto de cada hoja de tu carta, o un PDF. La IA arma tu menú y tú lo revisas antes de subirlo."
  {alCerrar}
>
  <div class="carta">
    {#if !hojas.length}
      <div class="caja" class:apagada={sinCartas} inert={sinCartas}>
        <CajaFoto
          src={null}
          apagado={sinCartas}
          alElegir={() => {}}
          varias={{
            titulo: 'Fotos de tu carta',
            texto: 'Arrástralas aquí o haz clic para elegirlas.',
            soltar: 'Suéltalas aquí.',
            pista: 'Hasta 6 fotos o un PDF de hasta 6 páginas',
            alElegir: agregar,
          }}
        />
      </div>
    {:else}
      <div class="rejilla">
        {#each hojas as h, i (h.tipo === 'foto' ? h.url : 'pdf')}
          <figure class="hoja" use:entra={i}>
            {#if h.tipo === 'foto'}
              <img src={h.url} alt="Hoja {i + 1} de tu carta" />
            {:else}
              <span class="pdf"><span class="doc">PDF</span>{h.paginas} {h.paginas === 1 ? 'página' : 'páginas'}</span>
            {/if}
            <span class="quitar">
              <BotonCuadro icono="cerrar" ayuda={h.tipo === 'pdf' ? 'Quitar el PDF' : `Quitar la hoja ${i + 1}`} tamanoIcono={14} onclick={() => quitar(i)} />
            </span>
            <figcaption>{h.tipo === 'pdf' ? 'Tu carta en PDF' : `Hoja ${i + 1}`}</figcaption>
          </figure>
        {/each}
        {#if !hayPdf && hojas.length < MAXIMO_HOJAS}
          <button type="button" class="otra" onclick={() => otra?.click()}>
            <Icono nombre="mas" tamano={20} /><span>Agregar otra hoja</span>
          </button>
        {/if}
      </div>
      <input bind:this={otra} type="file" accept="image/*" multiple hidden onchange={alElegirOtra} />
      <p class="pista">Las fotos no se guardan: solo las lee la IA. Hasta 6 hojas, o un PDF de hasta 6 páginas.</p>
    {/if}
    {#if error}<CajaError mensaje={error} compacta />{/if}
  </div>

  {#snippet pie()}
    {#if sinCartas && cartas}
      <p class="quedan nota-ambar">
        <Icono nombre="alerta" tamano={15} /><span>Ya leíste {cartas.de} cartas este mes. Vuelve el {diaYMes(cartas.vuelve)}.</span>
      </p>
    {:else}
      <p class="quedan">
        {#if cartas}Te quedan {cartas.quedan} de {cartas.de} este mes{:else}<span class="solo-lector">Viendo cuántas cartas te quedan…</span
          ><Esqueleto ancho="150px" alto="10px" />{/if}
      </p>
    {/if}
    <span class="crece"></span>
    <Boton tono="verde" etiqueta="Leer mi carta" apagado={!cartas?.puede || !hojas.length} onclick={leer} />
  {/snippet}
</Ventana>

<style>
  .carta {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding-top: 18px;
  }

  .caja.apagada {
    opacity: 0.45;
    pointer-events: none;
  }

  .rejilla {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
  }

  .hoja {
    position: relative;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .hoja img,
  .pdf {
    display: block;
    width: 100%;
    aspect-ratio: 3 / 4;
    object-fit: cover;
    border-radius: 12px;
    border: 1px solid var(--borde-tarjeta);
    background: var(--chip);
  }

  .pdf {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
  }

  .doc {
    width: 36px;
    height: 44px;
    display: grid;
    place-items: center;
    border-radius: 6px;
    background: var(--solido);
    font-family: var(--mono);
    font-size: 9.5px;
    font-weight: 500;
    color: var(--rojo);
  }

  figcaption {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--tenue);
    text-align: center;
  }

  .quitar {
    position: absolute;
    top: 6px;
    right: 6px;
  }

  .quitar :global(button) {
    width: 28px;
    height: 28px;
    background: var(--solido);
    box-shadow: var(--sombra-menu, 0 4px 14px rgba(0, 0, 0, 0.14));
  }

  .otra {
    aspect-ratio: 3 / 4;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border: 1.5px dashed var(--linea-fuerte);
    border-radius: 12px;
    background: transparent;
    color: var(--suave);
    font: inherit;
    font-size: 12.5px;
    font-weight: 600;
    transition:
      background 0.15s,
      color 0.15s;
  }

  .otra:hover {
    background: var(--chip);
    color: var(--texto);
  }

  .pista {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--tenue);
    text-align: center;
  }

  .quedan {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    color: var(--suave);
  }

  .nota-ambar {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 10px 12px;
    border-radius: 10px;
    background: var(--amarillo-fondo);
    color: var(--amarillo-texto);
    line-height: 1.45;
  }

  .nota-ambar :global(svg) {
    flex: none;
    margin-top: 1px;
  }

  .crece {
    flex: 1;
  }
</style>
