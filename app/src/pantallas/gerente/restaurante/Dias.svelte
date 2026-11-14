<!--
  El horario de los 7 días en «Tu restaurante» (maqueta de la 6a Qx4C5CbKJYpeAsJCfw4ghn, sección 2;
  libreta 6, decidido el 20 de octubre de 2026): cada día dice «Abre» con sus dos horas, o
  «Cerrado». Si cierra antes de la hora en que abre, cierra al día siguiente y lo dice («del
  sábado»). Las horas van de media en media; una que ya estaba guardada fuera de esa lista también
  sale.

  Desde el 14 nov 2026 (el developer: «interruptores como en la vista de mi menú digital… de color verde o rojo»),
  «Abre · Cerrado» es el selector de dos de Tu menú en línea (menuEnLinea/Formas.svelte: la canaleta gris y la elegida en
  su pastilla), con «Abre» en el verde de los botones del panel y «Cerrado» en rojo.
-->
<script module lang="ts">
  export type Dia = { abre: string; cierra: string } | null;
</script>

<script lang="ts">
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import Lista from '../../../diseno/Lista.svelte';
  import { quieto } from '../../../diseno/ventanaSeMueve';
  import { cubicOut } from 'svelte/easing';

  let {
    dias = $bindable(),
    hoy,
    apagado = false,
    cargando = false,
  }: { dias: Dia[]; hoy: number; apagado?: boolean; cargando?: boolean } = $props();

  const NOMBRES = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const HORAS = Array.from({ length: 48 }, (_, i) => `${Math.floor(i / 2)}:${i % 2 ? '30' : '00'}`);

  function minutos(t: string) {
    const [h, m] = t.split(':');
    return Number(h) * 60 + Number(m);
  }

  // La lista con la hora guardada en su lugar, si no es de media en media.
  function horasCon(valor: string) {
    if (HORAS.includes(valor)) return HORAS;
    return [...HORAS, valor].sort((a, b) => minutos(a) - minutos(b));
  }

  // Al prender un día, sus horas salen del interruptor (se deslizan desde la izquierda y se aclaran, con la curva de
  // salida de las listas); al apagarlo se desvanecen rápido. Quietas con «reducir movimiento».
  function entra(_n: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 260, easing: cubicOut, css: (t: number) => `opacity: ${t}; transform: translateX(${(1 - t) * -10}px)` };
  }

  function sale(_n: Element) {
    if (quieto()) return { duration: 0 };
    return { duration: 120, css: (t: number) => `opacity: ${t}` };
  }

  function abrir(i: number) {
    if (!dias[i]) dias[i] = { abre: '9:00', cierra: '18:00' };
  }

  function cerrar(i: number) {
    if (dias[i]) dias[i] = null;
  }
</script>

<div class="dias">
  {#each NOMBRES as nombre, i (nombre)}
    {@const d = dias[i]}
    {#if cargando}
      <!-- El esqueleto de la primera lectura (regla «Los esqueletos»): el nombre del día no espera a la red. -->
      <div class="dia" class:hoy={i === hoy} aria-hidden="true">
        <span class="dia-nombre">{nombre}</span>
        <span class="abre-cerrado-esqueleto"><Esqueleto ancho="168px" alto="42px" redondo="12px" /></span>
        <span class="horas"><Esqueleto ancho="{i % 3 === 2 ? 120 : 176}px" alto="10px" /></span>
      </div>
    {:else}
    <div class="dia" class:hoy={i === hoy}>
      <span class="dia-nombre">{nombre}</span>
      <div class="abre-cerrado" role="group" aria-label={nombre}>
        <button type="button" class="opcion abre" aria-pressed={!!d} disabled={apagado} onclick={() => abrir(i)}>Abre</button>
        <button type="button" class="opcion cerrado" aria-pressed={!d} disabled={apagado} onclick={() => cerrar(i)}>Cerrado</button>
      </div>
      <span class="horas">
        {#if d}
          <span class="horas-dentro" in:entra out:sale>
            <Lista aria-label="Abre el {nombre}" bind:valor={d.abre} {apagado} opciones={horasCon(d.abre).map((h) => ({ valor: h, texto: h }))} />
            <span class="a">a</span>
            <Lista aria-label="Cierra el {nombre}" bind:valor={d.cierra} {apagado} opciones={horasCon(d.cierra).map((h) => ({ valor: h, texto: h }))} />
            {#if minutos(d.cierra) < minutos(d.abre)}
              <span class="siguiente" in:entra>del {NOMBRES[(i + 1) % 7].toLowerCase()}</span>
            {/if}
          </span>
        {/if}
      </span>
    </div>
    {/if}
  {/each}
</div>

<style>
  .dias {
    display: flex;
    flex-direction: column;
  }

  .dia {
    display: grid;
    grid-template-columns: 96px 168px 1fr;
    align-items: center;
    gap: 14px;
    min-height: 52px;
    border-bottom: 1px solid var(--linea);
  }

  .dia:last-child {
    border-bottom: 0;
  }

  .dia-nombre {
    font-size: 13.5px;
    font-weight: 700;
  }

  .dia.hoy .dia-nombre::after {
    content: 'Hoy';
    margin-left: 8px;
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.1em;
    color: var(--tenue);
    font-weight: 500;
    text-transform: uppercase;
  }

  /* El selector de dos de Tu menú en línea (Formas): la canaleta en --chip y la elegida en su pastilla. «Abre» va en el
     verde de los botones del panel (el de Hyperiux, Boton tono="verde") y «Cerrado» en el rojo del panel. */
  .abre-cerrado {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 3px;
    padding: 3px;
    border-radius: 12px;
    background: var(--chip);
  }

  .opcion {
    height: 36px;
    min-width: 0;
    padding: 0 8px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    color: var(--suave);
    font: 600 12.5px var(--jakarta);
    white-space: nowrap;
    cursor: pointer;
    transition:
      background-color 0.18s ease,
      color 0.18s ease,
      box-shadow 0.18s ease,
      transform 0.15s ease;
  }

  .opcion:not(:disabled):hover {
    color: var(--texto);
  }

  .opcion:not(:disabled):active {
    transform: scale(0.97);
  }

  .opcion:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .opcion:disabled {
    cursor: default;
  }

  .opcion.abre[aria-pressed='true'] {
    background: #2b8449;
    color: #ffffff;
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  .opcion.cerrado[aria-pressed='true'] {
    background: var(--rojo);
    color: var(--sobre-rojo);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  /* Cristal: la canaleta, un relleno transparente como en Formas; el verde y el rojo se quedan, con la orilla de luz. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .abre-cerrado {
    background: rgba(255, 255, 255, 0.06);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .abre-cerrado {
    background: var(--cl-relleno);
  }

  :global(:root[data-estilo='cristal']) .opcion[aria-pressed='true'] {
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.22),
      0 4px 12px -6px rgba(0, 0, 0, 0.5);
  }

  .horas {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  .horas-dentro {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }

  .a {
    font-size: 12.5px;
    color: var(--tenue);
  }

  .siguiente {
    font-size: 11.5px;
    font-weight: 600;
    color: var(--suave);
    background: var(--chip);
    border-radius: 7px;
    padding: 3px 8px;
    white-space: nowrap;
  }

  @media (prefers-reduced-motion: reduce) {
    .opcion {
      transition: none;
    }
  }
</style>
