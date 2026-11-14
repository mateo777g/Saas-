<!--
  La barra de guardar («Tu menú en línea», maqueta UDArhiEZceT7rmSKxqRA5r v59; encuesta 33 de
  planes/trabajo/rediseno/tu-menu-en-linea.md): pegada abajo, de lo ancho de la vista, para una vista que junta muchos
  cambios y los guarda de un jalón. A la izquierda dice si todo está guardado (la palomita verde) o «Tienes cambios sin
  guardar · 3 cambios» (el punto ámbar); se cambian con un desvanecido que sube. A la derecha, «Descartar» en el rojo de
  contorno (se esconde sin cambios) y «Guardar» en verde (apagado sin cambios; mientras guarda su círculo gira y al
  terminar, la palomita). Mientras la vista lee la primera vez, el estado va en esqueleto. Si no se pudo guardar, el
  error va en su lugar, en su caja.
-->
<script lang="ts">
  import Boton from './Boton.svelte';
  import CajaError from './CajaError.svelte';
  import Esqueleto from './Esqueleto.svelte';
  import Icono from './Icono.svelte';

  let {
    cambios,
    paso = null,
    cargando = false,
    error = null,
    alGuardar,
    alDescartar,
  }: {
    // Cuántas cosas cambió (0 = todo guardado).
    cambios: number;
    paso?: null | 'guardando' | 'listo';
    cargando?: boolean;
    error?: string | null;
    alGuardar: () => void;
    alDescartar: () => void;
  } = $props();

  const con = $derived(cambios > 0 && paso !== 'listo');
</script>

<div class="barra-guardar" class:con-cambios={con}>
  <div class="estado" role="status">
    {#if cargando}
      <span class="esqueleto" aria-hidden="true"><Esqueleto ancho="120px" alto="12px" /></span>
    {:else if error}
      <span class="error"><CajaError mensaje={error} compacta /></span>
    {:else}
      <span class="todo" aria-hidden={con}><Icono nombre="check" tamano={16} />Todo guardado</span>
      <span class="cambios" aria-hidden={!con}
        ><i></i>Tienes cambios sin guardar<small>{cambios > 0 ? ` · ${cambios} ${cambios === 1 ? 'cambio' : 'cambios'}` : ''}</small></span
      >
    {/if}
  </div>
  <span class="descartar" inert={!con || paso !== null}>
    <Boton etiqueta="Descartar" icono="regresar" tono="peligro" onclick={alDescartar} />
  </span>
  <Boton
    etiqueta={paso === 'guardando' ? 'Guardando…' : paso === 'listo' ? 'Guardado' : 'Guardar'}
    tono="verde"
    apagado={(!con && paso === null) || cargando}
    cargando={paso === 'guardando'}
    exito={paso === 'listo'}
    onclick={alGuardar}
  />
</div>

<style>
  .barra-guardar {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 64px;
    z-index: 6;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 20px 0 24px;
    background: var(--solido);
    border-top: 1px solid var(--linea);
  }

  .estado {
    flex: 1;
    min-width: 0;
    position: relative;
    height: 22px;
  }

  .estado > span {
    position: absolute;
    left: 0;
    top: 0;
    height: 22px;
    display: flex;
    align-items: center;
    gap: 9px;
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition:
      opacity 0.25s ease,
      transform 0.25s ease;
  }

  .estado > .esqueleto {
    align-items: center;
  }

  .estado > .error {
    top: 50%;
    height: auto;
    max-width: 100%;
    transform: translateY(-50%);
    white-space: normal;
  }

  .todo {
    color: var(--suave);
  }

  .todo :global(svg) {
    color: var(--verde);
  }

  .cambios {
    color: var(--texto);
  }

  .cambios i {
    width: 9px;
    height: 9px;
    border-radius: 5px;
    background: var(--amarillo);
    box-shadow: 0 0 0 4px var(--amarillo-fondo);
  }

  .cambios small {
    font-size: 12.5px;
    font-weight: 500;
    color: var(--suave);
  }

  .barra-guardar:not(.con-cambios) .cambios,
  .barra-guardar.con-cambios .todo {
    opacity: 0;
    transform: translateY(6px);
    pointer-events: none;
  }

  /* «Descartar» se esconde sin cambios y conserva el movimiento de su contorno y su letra. */
  .descartar {
    display: flex;
    transition:
      opacity 0.25s ease,
      transform 0.25s ease;
  }

  .barra-guardar:not(.con-cambios) .descartar {
    opacity: 0;
    transform: translateX(8px);
    pointer-events: none;
  }

  @media (prefers-reduced-motion: reduce) {
    .estado > span,
    .descartar {
      transition: none;
    }
  }
</style>
