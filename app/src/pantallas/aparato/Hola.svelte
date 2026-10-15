<!--
  Lo que ve quien entró (maqueta de Empleados) mientras no exista el punto de venta (pieza 4): su
  nombre, sus roles en el restaurante y la tarjeta de vidrio «El punto de venta llega pronto». En
  la tableta compartida lleva «Cambiar de persona».
-->
<script lang="ts">
  import Icono from '../../diseno/Icono.svelte';
  import Vidrio from '../../diseno/Vidrio.svelte';
  import type { Lista, PersonaAparato } from '../../lib/aparato';
  import { NOMBRE_ROL } from '../../lib/roles';
  import Arriba from './Arriba.svelte';

  let {
    lista,
    persona,
    alCambiar,
  }: { lista: Lista; persona: PersonaAparato; alCambiar?: () => void } = $props();

  const roles = $derived(persona.roles.map((r) => NOMBRE_ROL[r] ?? r).join(' · '));
</script>

<Arriba lugar={{ restaurante: lista.restaurante, aparato: lista.aparato }} />
<div class="cuerpo">
  <div class="centro arriba">
    <h1 class="titulo grande">Hola, {persona.nombre.trim().split(/\s+/)[0]}</h1>
    <p class="texto">{roles} en {lista.restaurante}</p>
    <Vidrio class="tarjeta-hola" radio={22}>
      <span class="cuadro-icono"><Icono nombre="mesas" tamano={18} /></span>
      <b>El punto de venta llega pronto</b>
      <p class="texto chico">Aquí vas a tomar los pedidos de tus mesas, mandarlos a cocina y anotar cómo se pagó.</p>
    </Vidrio>
  </div>
  {#if alCambiar}
    <button type="button" class="boton contorno" onclick={alCambiar}>Cambiar de persona</button>
  {/if}
</div>

<style>
  .centro.arriba {
    margin-top: 40px;
    justify-content: flex-start;
  }

  .titulo.grande {
    font-size: 32px;
  }

  .centro > :global(.tarjeta-hola) {
    margin-top: 18px;
    padding: 22px;
    display: flex;
    flex-direction: column;
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

  b {
    font-size: 16px;
    font-weight: 700;
  }

  .texto.chico {
    font-size: 13px;
  }
</style>
