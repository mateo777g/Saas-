<!--
  «Cómo se ve» en el aparato del equipo (libreta 4, «El estilo Cristal»; maqueta «Cristal en los aparatos» v2, fuente
  planes/maquetas/aparatos-cristal.html; planes/trabajo/estilo-cristal/aparatos.md). Un botón de ícono a la derecha de la
  barra de arriba, en las pantallas de entrada del aparato (afuera, Mesas o Vender, Caja, Pedidos y Cocina), que abre una
  cajita con el tema (el sol que se vuelve luna) y el estilo (Simple · Cristal), las piezas de «Interfaz» de Ajustes. Lo
  cambia cualquiera: solo cambia cómo se ve este aparato y se guarda en él, aparte del panel (lib/tema.ts, lib/estilo.ts).

  Sale de su botón con el resorte del fondo de las listas, como la hora de corte (gerente/cortes/HoraCorte.svelte), a ras
  de su borde derecho; se cierra con un clic afuera o con Escape. En Cristal el botón es vidrio y la cajita una hoja de
  vidrio con rellenos transparentes adentro. Respeta «reducir movimiento».
-->
<script lang="ts">
  import BotonCuadro from '../../diseno/BotonCuadro.svelte';
  import BotonTema from '../../diseno/BotonTema.svelte';
  import { ponerEnBarra, vidrio } from '../../diseno/vidrio';
  import { cambiarEstilo, estiloActual, type Estilo } from '../../lib/estilo';
  import { cambiarTema, temaActual } from '../../lib/tema';

  // En Cristal el botón es vidrio, como los de la barra de arriba, también arriba en el celular y afuera.
  ponerEnBarra();

  const NOMBRE: Record<Estilo, string> = { simple: 'Simple', cristal: 'Cristal' };
  const PISTA: Record<Estilo, string> = {
    simple: 'Liso, como siempre. Solo cambia cómo se ve: todo sigue en su lugar.',
    cristal: 'De vidrio, con una luz que sigue al dedo. Solo cambia cómo se ve: todo sigue en su lugar.',
  };
  const idCaja = $props.id();

  let abierta = $state(false);
  let tema = $state(temaActual());
  let estilo = $state(estiloActual());
  let raiz: HTMLDivElement;

  function alternar() {
    if (!abierta) {
      // Lo que diga el aparato ahora (otra pestaña pudo cambiarlo).
      tema = temaActual();
      estilo = estiloActual();
    }
    abierta = !abierta;
  }

  function alternarTema() {
    tema = tema === 'claro' ? 'oscuro' : 'claro';
    cambiarTema(tema);
  }

  function elegirEstilo(e: Estilo) {
    estilo = e;
    cambiarEstilo(e);
  }

  // Un clic afuera o Escape la cierran (Escape regresa al botón).
  $effect(() => {
    if (!abierta) return;
    const afuera = (ev: PointerEvent) => {
      if (!raiz.contains(ev.target as Node)) abierta = false;
    };
    const tecla = (ev: KeyboardEvent) => {
      if (ev.key !== 'Escape') return;
      abierta = false;
      raiz.querySelector<HTMLButtonElement>('.cuadro')?.focus();
    };
    document.addEventListener('pointerdown', afuera, true);
    document.addEventListener('keydown', tecla);
    return () => {
      document.removeEventListener('pointerdown', afuera, true);
      document.removeEventListener('keydown', tecla);
    };
  });
</script>

<div class="como" class:abierta bind:this={raiz}>
  <BotonCuadro
    icono="contraste"
    ayuda="Cómo se ve"
    etiqueta="Cómo se ve este aparato"
    expandido={abierta}
    onclick={alternar}
  />
  <div class="cajita" id={idCaja} role="dialog" aria-label="Cómo se ve este aparato" inert={!abierta} use:vidrio={'hoja'}>
    <div class="cabeza"><b>Cómo se ve</b><span>Solo en este aparato</span></div>
    <div class="grupo">
      <span class="etiqueta">TEMA</span>
      <div class="control">
        <BotonTema {tema} ayuda={tema === 'claro' ? 'Cambiar este aparato a oscuro' : 'Cambiar este aparato a claro'} alCambiar={alternarTema} />
        <span class="tema-texto">Va en {tema}</span>
      </div>
    </div>
    <div class="grupo">
      <span class="etiqueta">ESTILO</span>
      <div class="formas" role="group" aria-label="Estilo">
        {#each ['simple', 'cristal'] as const as e (e)}
          <button type="button" class="forma" aria-pressed={estilo === e} onclick={() => elegirEstilo(e)}>{NOMBRE[e]}</button>
        {/each}
      </div>
      <p class="pista">{PISTA[estilo]}</p>
    </div>
  </div>
</div>

<style>
  .como {
    position: relative;
    flex: none;
    margin-left: auto;
    display: flex;
  }

  /* En Cristal, el canto de luz del botón cuelga de él. */
  :global(:root[data-estilo='cristal']) .como :global(.cuadro) {
    position: relative;
  }

  /* 8 debajo del botón y a ras de su borde derecho; sale de él con el resorte del fondo de las listas. */
  .cajita {
    position: absolute;
    right: 0;
    top: calc(100% + 8px);
    z-index: 40;
    width: 300px;
    max-width: calc(100vw - 24px);
    box-sizing: border-box;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 14px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 14px;
    background: var(--solido);
    color: var(--texto);
    text-align: left;
    box-shadow:
      0 18px 40px -12px var(--sombra-menu),
      0 2px 6px var(--sombra-menu);
    transform-origin: calc(100% - 18px) 0;
    opacity: 0;
    transform: translateY(-6px) scale(0.96);
    visibility: hidden;
    transition:
      opacity 0.15s ease,
      transform 0.2s ease,
      visibility 0s linear 0.2s;
  }

  .abierta .cajita {
    opacity: 1;
    transform: none;
    visibility: visible;
    transition:
      opacity 0.2s ease,
      transform 0.5s var(--resorte-fondo),
      visibility 0s;
  }

  .cabeza {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .cabeza b {
    font-size: 14px;
    font-weight: 700;
  }

  .cabeza span {
    font-size: 12.5px;
    color: var(--tenue);
  }

  /* Las piezas de «Interfaz» de Ajustes, tal cual. */
  .grupo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
    text-wrap: pretty;
  }

  .control {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .tema-texto {
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
  }

  .formas {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 3px;
    padding: 3px;
    border-radius: 12px;
    background: var(--chip);
  }

  .forma {
    position: relative;
    height: 40px;
    min-width: 0;
    display: flex;
    align-items: center;
    justify-content: center;
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

  .forma:hover {
    color: var(--texto);
  }

  .forma:active {
    transform: scale(0.97);
  }

  .forma:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .forma[aria-pressed='true'] {
    background: var(--solido);
    color: var(--texto);
    box-shadow: 0 1px 3px var(--sombra-segmento);
  }

  /* Cristal: dentro de la hoja de vidrio, rellenos transparentes (nunca vidrio sobre vidrio), como en Ajustes. */
  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .formas {
    background: rgba(255, 255, 255, 0.06);
  }

  :global(:root[data-estilo='cristal'][data-tema='oscuro']) .forma[aria-pressed='true'] {
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.07));
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.18),
      0 4px 12px -6px rgba(0, 0, 0, 0.6);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .formas {
    background: var(--cl-relleno);
  }

  :global(:root[data-estilo='cristal'][data-tema='claro']) .forma[aria-pressed='true'] {
    background: rgba(255, 255, 255, 0.9);
    box-shadow:
      inset 0 1px 0 #ffffff,
      0 4px 12px -6px var(--cl-sombra);
  }

  @media (prefers-reduced-motion: reduce) {
    .cajita,
    .abierta .cajita,
    .forma {
      transition: none;
    }
  }
</style>
