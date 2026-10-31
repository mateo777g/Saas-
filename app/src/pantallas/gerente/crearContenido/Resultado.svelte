<!--
  «Resultado», la tarjeta de la derecha de Crear contenido (maqueta JQBw2yGFSiky1x9twUyYbe): vacía
  hasta que hay un anuncio; mientras se hace, la rejilla de puntitos con sus segundos; cuando sale,
  el anuncio en su forma, de borroso a nítido, con «Otra vez» y «Descargar»; si no salió, por qué y
  que no contó. Cada marco tiene la forma del formato.
-->
<script module lang="ts">
  import type { Formato } from '../../../lib/crearContenido';

  export type LoQueSeVe =
    | { fase: 'vacio' }
    | { fase: 'haciendo'; formato: Formato; nombres: string; desde: number }
    | { fase: 'listo'; formato: Formato; id: number; ruta: string }
    | { fase: 'fallo'; formato: Formato; motivo: 'rechazado' | 'no_salio' | 'cerrada' };
</script>

<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import Vidrio from '../../../diseno/Vidrio.svelte';
  import { formatoDe } from '../../../lib/crearContenido';
  import { Fallo, mensajeDeError } from '../../../lib/errores';
  import { urlFoto } from '../../../lib/fotos';
  import Cargador from './Cargador.svelte';

  let {
    se,
    formatoElegido,
    otraVez,
    alOtraVez,
    alDescargar,
  }: {
    se: LoQueSeVe;
    // El formato que eligió: el del marco vacío.
    formatoElegido: Formato | null;
    // «Otra vez» se apaga si no le quedan o la IA no puede.
    otraVez: boolean;
    alOtraVez: () => void;
    alDescargar: (id: number) => Promise<void>;
  } = $props();

  const formato = $derived(se.fase === 'vacio' ? (formatoElegido ?? 'post') : se.formato);
  const f = $derived(formatoDe(formato));
  const etiqueta = $derived(se.fase === 'vacio' && !formatoElegido ? '' : `${f.corto} · ${f.medida}`);

  let bajando = $state(false);
  let descargado = $state(false);
  let errorDescarga = $state<string | null>(null);

  async function descargar(id: number) {
    bajando = true;
    errorDescarga = null;
    try {
      await alDescargar(id);
      descargado = true;
      setTimeout(() => (descargado = false), 1600);
    } catch (error) {
      errorDescarga = error instanceof Fallo ? error.message : mensajeDeError(error);
    } finally {
      bajando = false;
    }
  }

  function textoDelFallo(motivo: 'rechazado' | 'no_salio' | 'cerrada'): string {
    if (motivo === 'rechazado') return 'OpenAI no aceptó este anuncio. Cambia el mensaje e inténtalo otra vez.';
    if (motivo === 'cerrada') return 'Tu último anuncio no se pudo hacer. No contó.';
    return 'No se pudo hacer tu anuncio. Inténtalo otra vez.';
  }
</script>

<Vidrio como="section" class="tarjeta-resultado" radio={26} aria-label="Resultado">
  <div class="cabeza">
    <span class="etq">Resultado</span>
    <span class="crece"></span>
    <span class="etq">{etiqueta}</span>
  </div>

  <div class="zona">
    {#if se.fase === 'haciendo'}
      <div class="marco haciendo" style:width="{f.ancho}px" style:height="{f.alto}px">
        <Cargador desde={se.desde} />
      </div>
    {:else if se.fase === 'listo'}
      {#key se.id}
        <div class="marco listo" style:width="{f.ancho}px" style:height="{f.alto}px">
          <img src={urlFoto(se.ruta)} alt="Tu anuncio" />
        </div>
      {/key}
    {:else if se.fase === 'fallo'}
      <div class="marco vacio" style:width="{f.ancho}px" style:height="{f.alto}px">
        <div class="centro">
          <CajaError mensaje={textoDelFallo(se.motivo)} compacta />
          {#if se.motivo !== 'cerrada'}<span class="chico">No contó.</span>{/if}
        </div>
      </div>
    {:else}
      <div class="marco vacio" style:width="{f.ancho}px" style:height="{f.alto}px">
        <div class="centro">
          <span class="chip-icono"><Icono nombre="biblio" tamano={20} /></span>
          <b>Aquí aparecerá tu anuncio</b>
          <span>Pica tus productos, elige el formato y toca Generar anuncio.</span>
        </div>
      </div>
    {/if}
  </div>

  {#if se.fase === 'haciendo'}
    <div class="haciendo-pie">
      <b>{se.nombres} · {f.texto}</b>
      <span>Puede tardar un par de minutos. Puedes cerrar esta ventana: aparecerá en Mi biblioteca.</span>
    </div>
  {:else if se.fase === 'listo'}
    {@const id = se.id}
    <div class="acciones">
      {#if errorDescarga}
        <CajaError mensaje={errorDescarga} compacta />
      {:else}
        <div class="guardado"><Icono nombre="check-fino" tamano={16} />Guardado en Mi biblioteca</div>
      {/if}
      <div class="dos-botones">
        <Boton etiqueta="Otra vez" icono="actualizar" apagado={!otraVez} onclick={alOtraVez} />
        <Boton
          etiqueta={descargado ? 'Descargado' : 'Descargar'}
          icono="exportar"
          tono="tinta"
          cargando={bajando}
          exito={descargado}
          onclick={() => descargar(id)}
        />
      </div>
    </div>
  {/if}
</Vidrio>

<style>
  :global(.tarjeta-resultado) {
    position: absolute;
    right: 16px;
    top: 92px;
    bottom: 16px;
    width: 440px;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .etq {
    font-family: var(--mono);
    font-size: 10.5px;
    letter-spacing: 0.14em;
    color: var(--tenue);
    text-transform: uppercase;
  }

  .crece {
    flex-grow: 1;
  }

  .cabeza {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 4px 4px 0;
  }

  .zona {
    flex: 1;
    min-height: 0;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .marco {
    position: relative;
    flex: none;
    border-radius: 18px;
    overflow: hidden;
  }

  .marco.vacio {
    border: 1.5px dashed var(--linea-fuerte);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
  }

  .marco.haciendo {
    background: var(--solido);
    border: 1px solid var(--linea);
    color: var(--texto);
  }

  /* Cuando sale: de borroso a nítido y de un poco grande a su tamaño. */
  .marco.listo {
    background: #111111;
    box-shadow: 0 12px 32px var(--sombra-anuncio);
    animation: aparecer 700ms cubic-bezier(0.23, 1, 0.32, 1) both;
  }

  @keyframes aparecer {
    from {
      opacity: 0;
      transform: scale(1.06);
      filter: blur(24px);
    }
  }

  .marco.listo img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .centro {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    text-align: center;
  }

  .centro b {
    font-size: 14.5px;
    font-weight: 700;
  }

  .centro span {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
    line-height: 1.45;
    max-width: 30ch;
  }

  .centro .chico {
    font-size: 12px;
    color: var(--tenue);
  }

  .centro :global(.caja) {
    text-align: left;
  }

  .chip-icono {
    width: 44px;
    height: 44px;
    border-radius: 13px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--chip);
    color: var(--suave);
  }

  .haciendo-pie {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 0 4px;
  }

  .haciendo-pie b {
    font-size: 12.5px;
    font-weight: 600;
  }

  .haciendo-pie span {
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
    line-height: 1.45;
  }

  .acciones {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .guardado {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 4px;
    font-size: 12.5px;
    font-weight: 600;
  }

  .guardado :global(svg) {
    color: var(--verde);
  }

  .dos-botones {
    display: flex;
    gap: 10px;
  }

  .dos-botones :global(.boton) {
    flex: 1;
  }

  @media (prefers-reduced-motion: reduce) {
    .marco.listo {
      animation: none;
    }
  }
</style>
