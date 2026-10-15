<!--
  «¿Quién eres?» en la tableta compartida (maqueta de Empleados): el equipo con PIN, sin los
  gerentes, como lo da Postgres. Cada quien toca su nombre y pone su PIN. Quien está bloqueado sale
  en gris, con hasta qué hora.
-->
<script lang="ts">
  import { horaDe, type Lista, type PersonaAparato } from '../../lib/aparato';
  import { NOMBRE_ROL } from '../../lib/roles';
  import Arriba from './Arriba.svelte';

  let { lista, alElegir }: { lista: Lista; alElegir: (persona: PersonaAparato) => void } = $props();

  function debajo(p: PersonaAparato): string {
    if (p.bloqueado && !p.bloqueadoHasta) return 'PIN bloqueado: tu gerente lo desbloquea';
    if (p.bloqueado && p.bloqueadoHasta) return `PIN bloqueado hasta las ${horaDe(p.bloqueadoHasta)}`;
    return p.roles.map((r) => NOMBRE_ROL[r] ?? r).join(' · ');
  }
</script>

<Arriba lugar={{ restaurante: lista.restaurante, aparato: lista.aparato }} />
<div class="cuerpo">
  <h1 class="titulo arriba">¿Quién eres?</h1>
  {#if lista.personas.length}
    <div class="lista">
      {#each lista.personas as p (p.id)}
        <button type="button" class="persona" class:bloqueada={p.bloqueado} onclick={() => alElegir(p)}>
          <span class="inicial">{p.nombre.trim().charAt(0).toUpperCase()}</span>
          <span class="t">
            <b>{p.nombre}</b>
            <span>{debajo(p)}</span>
          </span>
        </button>
      {/each}
    </div>
  {:else}
    <p class="texto vacia">Todavía no hay nadie del equipo con PIN. Pídele a tu gerente que te agregue en Empleados.</p>
  {/if}
</div>

<style>
  .titulo.arriba {
    margin-top: 28px;
  }

  .lista {
    margin-top: 18px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    overflow-y: auto;
  }

  .persona {
    min-height: 64px;
    flex: none;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 0 16px;
    border: 1px solid var(--linea);
    border-radius: 16px;
    background: var(--solido);
    color: var(--texto);
    text-align: left;
  }

  .persona .inicial {
    width: 40px;
    height: 40px;
    border-radius: 20px;
    font-size: 15px;
  }

  .t {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .t b {
    font-size: 15px;
    font-weight: 700;
  }

  .t > span {
    font-size: 12.5px;
    color: var(--tenue);
  }

  .bloqueada b {
    color: var(--tenue);
  }

  .texto.vacia {
    margin-top: 18px;
  }
</style>
