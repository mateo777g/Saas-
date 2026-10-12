<!--
  Ajustes del gerente, portado de panel/views/ajustes_view.py (maqueta aprobada:
  https://claude.ai/artifact/QNMone8zhHWvzae5aVHG2f) con lo que cambió al dejar Flet: ya no hay
  carpeta de exportación (libreta 4, decidido el 9 de octubre de 2026) y por ahora solo queda el
  tema (decidido el 11 de octubre). La tarjeta Tema conserva su ancho de Flet (2 de 5, ahora a la
  izquierda); el hueco de la derecha es para la hora de corte, que llega con las ventas.

  El tema se guarda en este navegador (lib/tema.ts) y se ve al momento en todo el panel. La barra
  de arriba (con su chip) la pone el panel.
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { cambiarTema, temaActual, type Tema } from '../../lib/tema';

  // En el orden de Flet: Oscuro primero.
  const TEMAS: { valor: Tema; texto: string; icono: string }[] = [
    { valor: 'oscuro', texto: 'Oscuro', icono: 'luna' },
    { valor: 'claro', texto: 'Claro', icono: 'sol' },
  ];

  let tema = $state(temaActual());

  function elegir(nuevo: Tema) {
    if (nuevo === tema) return;
    tema = nuevo;
    cambiarTema(nuevo);
  }
</script>

<Vidrio como="section" class="ajustes" radio={26} aria-label="Tus ajustes">
  <div class="cabeza">
    <span class="etiqueta">TUS AJUSTES</span>
    <p class="nota">Configura los colores del panel.</p>
  </div>

  <div class="fila">
    <div class="tarjeta">
      <div class="encabezado">
        <span class="cuadro-icono"><Icono nombre="contraste" tamano={18} /></span>
        <span class="titulos">
          <span class="titulo">Tema</span>
          <span class="nota">Los colores del panel: oscuro o claro.</span>
        </span>
      </div>
      <div class="raya"></div>
      <span class="etiqueta">COLORES DEL PANEL</span>
      <div class="selector">
        <Selector opciones={TEMAS} elegida={tema} alElegir={elegir} etiqueta="Tema" alto={38} lleno />
      </div>
      <p class="pie">El cambio se ve al momento en todo el panel.</p>
    </div>
  </div>
</Vidrio>

<style>
  :global(.ajustes) {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .cabeza {
    padding: 4px 4px 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .nota {
    margin: 0;
    font-size: 12.5px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .fila {
    display: flex;
  }

  /* Su ancho de Flet: 2 de las 5 partes, contando los 16 entre tarjetas. */
  .tarjeta {
    width: calc((100% - 16px) * 2 / 5);
    padding: 20px;
    display: flex;
    flex-direction: column;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 18px;
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

  .raya {
    height: 1px;
    margin: 20px 0;
    background: var(--linea);
  }

  .selector {
    margin-top: 8px;
  }

  .pie {
    margin: 20px 0 0;
    font-size: 12px;
    font-weight: 500;
    color: var(--tenue);
  }
</style>
