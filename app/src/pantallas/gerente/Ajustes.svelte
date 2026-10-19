<!--
  Ajustes del gerente, portado de panel/views/ajustes_view.py (maqueta aprobada:
  https://claude.ai/artifact/QNMone8zhHWvzae5aVHG2f) con lo que cambió al dejar Flet: ya no hay
  carpeta de exportación (libreta 4, decidido el 9 de octubre de 2026) y por ahora solo queda el
  tema (decidido el 11 de octubre). La tarjeta Tema conserva su ancho de Flet (2 de 5, ahora a la
  izquierda). En el panel del gerente, el hueco de la derecha es la hora de corte de la sucursal
  (pieza 5, decidido el 18 de octubre de 2026; maqueta Cortes y reportes 7J6LvYWiktRnGxNugbuaoe): la
  guarda fijar_hora_corte, queda en la bitácora y también cambia a qué día pertenecen las ventas
  pasadas.

  El tema se guarda en este navegador (lib/tema.ts) y se ve al momento en todo el panel. La barra
  de arriba (con su chip) la pone el panel. Desde el 12 de octubre de 2026 la usan tal cual los
  paneles de Fragmentless y del distribuidor, sin sucursal y sin hora de corte.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import { ALGO_SALIO_PANEL, esDeRed, Fallo, SIN_CONEXION } from '../../lib/errores';
  import type { Sucursal } from '../../lib/gerente';
  import { fijarHoraCorte, leerHoraCorte } from '../../lib/reportes';
  import { cambiarTema, temaActual, type Tema } from '../../lib/tema';

  let { sucursal }: { sucursal?: Sucursal } = $props();

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

  // ─── La hora de corte (solo con sucursal) ───
  const HORAS = Array.from({ length: 24 }, (_, h) => h);
  let guardada = $state<number | null>(null);
  let hora = $state<number | null>(null);
  let paso = $state<'guardando' | 'listo' | null>(null);
  let error = $state<string | null>(null);

  onMount(async () => {
    if (!sucursal) return;
    try {
      guardada = hora = await leerHoraCorte(sucursal.id);
    } catch (falla) {
      console.error('[ajustes] no se pudo leer la hora de corte:', falla);
      error = esDeRed(falla) ? SIN_CONEXION : 'No se pudo leer la hora de corte. Intenta de nuevo en un momento.';
    }
  });

  async function guardar() {
    if (!sucursal || hora === null) return;
    paso = 'guardando';
    error = null;
    try {
      await fijarHoraCorte(sucursal.id, hora);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[ajustes] no se pudo guardar la hora de corte:', falla);
      error = falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL;
      paso = null;
      return;
    }
    guardada = hora;
    paso = 'listo';
    setTimeout(() => (paso = null), 1600);
  }

  // El ejemplo de la tarjeta, con la hora que está elegida.
  function ejemplo(h: number): { hora: string; resto: string } {
    if (h === 0) return { hora: '0:00', resto: ', cada día va de medianoche a medianoche.' };
    const cuenta = h > 1 ? '0:40' : '0:20';
    return {
      hora: `${h}:00`,
      resto: `, lo que se abre antes de las ${h}:00 cuenta en el día anterior: una cuenta del sábado a las ${cuenta} es del viernes.`,
    };
  }
</script>

<Vidrio como="section" class="ajustes" radio={26} aria-label="Tus ajustes">
  <div class="cabeza">
    <span class="etiqueta">TUS AJUSTES</span>
    <p class="nota">
      {sucursal ? 'Configura los colores del panel y cuándo empieza el día de tu negocio.' : 'Configura los colores del panel.'}
    </p>
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
      <p class="pie">
        {sucursal ? 'Se guarda en este navegador y se ve al momento en todo el panel.' : 'El cambio se ve al momento en todo el panel.'}
      </p>
    </div>

    {#if sucursal}
      <div class="tarjeta corte">
        <div class="encabezado">
          <span class="cuadro-icono"><Icono nombre="reloj" tamano={18} /></span>
          <span class="titulos">
            <span class="titulo">Hora de corte</span>
            <span class="nota">Cuándo empieza un día nuevo en tus ventas, tu caja y tus reportes.</span>
          </span>
        </div>
        <div class="raya"></div>
        <label class="etiqueta" for="hora-corte">EL DÍA EMPIEZA A LAS</label>
        <div class="hora-fila">
          <select id="hora-corte" bind:value={hora} disabled={hora === null || paso !== null}>
            {#each HORAS as h (h)}<option value={h}>{h}:00</option>{/each}
          </select>
          <Boton
            etiqueta={paso === 'guardando' ? 'Guardando…' : paso === 'listo' ? 'Guardado' : 'Guardar'}
            icono="guardar"
            tono="tinta"
            apagado={hora === null || hora === guardada}
            cargando={paso === 'guardando'}
            exito={paso === 'listo'}
            onclick={guardar}
          />
        </div>
        {#if hora !== null}
          {@const e = ejemplo(hora)}
          <p class="ejemplo"><Icono nombre="info" tamano={16} /><span>Con <b>{e.hora}</b>{e.resto}</span></p>
        {/if}
        {#if error}<div class="error"><CajaError mensaje={error} /></div>{/if}
        <p class="pie">Es de esta sucursal y vale para todo tu equipo. Si la cambias, también cambia a qué día pertenecen las ventas pasadas.</p>
      </div>
    {/if}
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
    gap: 16px;
    align-items: stretch;
  }

  /* Su ancho de Flet: 2 de las 5 partes, contando los 16 entre tarjetas. */
  .tarjeta {
    flex: none;
    min-width: 0;
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
    line-height: 1.5;
    color: var(--tenue);
  }

  .tarjeta.corte {
    flex: 1;
    width: auto;
  }

  .hora-fila {
    margin-top: 8px;
    display: flex;
    gap: 10px;
  }

  .hora-fila select {
    flex: 1;
    min-width: 0;
    height: 44px;
    padding: 0 12px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font-family: var(--mono);
    font-size: 14px;
    outline: none;
  }

  .hora-fila select:focus {
    border-color: var(--suave);
  }

  .ejemplo {
    margin: 14px 0 0;
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 11px 14px;
    border-radius: 12px;
    background: var(--chip);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--suave);
  }

  .ejemplo :global(svg) {
    flex: none;
    margin-top: 2px;
  }

  .ejemplo b {
    font-weight: 600;
    color: var(--texto);
  }

  .error {
    margin-top: 14px;
  }
</style>
