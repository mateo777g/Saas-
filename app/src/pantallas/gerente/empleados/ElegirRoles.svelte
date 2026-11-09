<!--
  Los roles de una persona del equipo (maqueta de Empleados): Mesero, Caja y Cocina, uno o varios,
  como casillas que se rellenan de tinta al elegirlas. El de gerente no sale: lo liga Fragmentless.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { ROLES, type Rol } from '../../../lib/roles';

  let { roles = $bindable([]) }: { roles?: Rol[] } = $props();

  const idEtiqueta = $props.id();

  function alternar(rol: Rol) {
    roles = roles.includes(rol) ? roles.filter((r) => r !== rol) : [...roles, rol];
  }
</script>

<div class="campo">
  <span class="etiqueta" id={idEtiqueta}>ROLES</span>
  <div class="opciones" role="group" aria-labelledby={idEtiqueta}>
    {#each ROLES as r (r.valor)}
      {@const elegido = roles.includes(r.valor)}
      <button type="button" class="rol" role="checkbox" aria-checked={elegido} onclick={() => alternar(r.valor)}>
        <span class="cajita">{#if elegido}<Icono nombre="check" tamano={11} />{/if}</span>
        {r.texto}
      </button>
    {/each}
  </div>
  <p class="pista">Uno o varios. Para sumar a alguien como gerente, avísale a Fragmentless.</p>
</div>

<style>
  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .opciones {
    display: flex;
    gap: 8px;
  }

  .rol {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 40px;
    padding: 0 14px;
    border: 0;
    border-radius: 12px;
    background: var(--campo-fondo);
    box-shadow: var(--campo-sombra);
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    transition:
      background-color 0.15s ease,
      box-shadow 0.15s ease-out;
  }

  /* Como las cajas de texto (diseno/Campo.svelte, el Input de HeroUI), desde el 9 nov 2026. */
  .rol:hover {
    background: var(--campo-encima);
  }

  .rol:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .rol[aria-checked='true'] {
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  @media (prefers-reduced-motion: reduce) {
    .rol {
      transition: none;
    }
  }

  .cajita {
    width: 16px;
    height: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1.5px solid var(--tenue);
    border-radius: 5px;
  }

  .rol[aria-checked='true'] .cajita {
    border: 0;
    background: var(--sobre-tinta);
    color: var(--tinta);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }
</style>
