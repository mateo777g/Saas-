<!--
  La página entera cuando no hay menú que enseñar (maqueta de la 6a, estado «No disponible»): un slug
  que no existe y una licencia pausada dicen lo mismo, «Este menú no está disponible». También sale
  cuando no se pudo leer (sin internet), con «Intentar otra vez».
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let { titulo, texto, boton, alBoton }: { titulo: string; texto: string; boton?: string; alBoton?: () => void } = $props();
</script>

<div class="aviso">
  <span class="circulo"><Icono nombre="apagado" tamano={28} /></span>
  <b>{titulo}</b>
  <span class="texto">{texto}</span>
  {#if boton}<button type="button" onclick={alBoton}>{boton}</button>{/if}
</div>

<style>
  .aviso {
    position: fixed;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    padding: 0 36px;
    text-align: center;
  }

  .circulo {
    width: 64px;
    height: 64px;
    border-radius: 32px;
    background: var(--m-chip);
    color: var(--m-suave);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 6px;
  }

  b {
    font-size: 19px;
    font-weight: 800;
    letter-spacing: -0.3px;
  }

  .texto {
    font-size: 14px;
    color: var(--m-suave);
    line-height: 1.5;
  }

  button {
    margin-top: 8px;
    height: 40px;
    padding: 0 18px;
    border-radius: 20px;
    border: 1px solid var(--m-linea);
    background: transparent;
    color: var(--m-texto);
    font-size: 14px;
    font-weight: 600;
  }
</style>
