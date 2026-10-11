<!--
  boton() de diseno.py y los botones grandes del login y de la suscripción terminada.
    tono      linea: borde fino, sin relleno (los secundarios)
              tinta: el principal (negro en claro, blanco en oscuro)
              acento: naranja en claro, azul en oscuro (Conectar Mercado Pago, Renovar)
    tamano    normal: 40 de alto, letra 13 (la barra de arriba, las ventanas)
              grande: 48 de alto, letra 14, a todo lo ancho (el login)
    apagado   apagar() de diseno.py: al 40 % y sin clic (guardando, entrando)
    exito     la palomita verde en lugar del icono (el éxito se ve en el botón, ~1.6 s)
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    etiqueta,
    icono,
    tono = 'linea',
    tamano = 'normal',
    apagado = false,
    exito = false,
    tipo = 'button',
    onclick,
  }: {
    etiqueta: string;
    icono?: string;
    tono?: 'linea' | 'tinta' | 'acento';
    tamano?: 'normal' | 'grande';
    apagado?: boolean;
    exito?: boolean;
    tipo?: 'button' | 'submit';
    onclick?: (e: MouseEvent) => void;
  } = $props();
</script>

<button
  type={tipo}
  class="boton {tono} {tamano}"
  disabled={apagado}
  {onclick}
>
  {#if exito}
    <span class="verde"><Icono nombre="check" tamano={16} /></span>
  {:else if icono}
    <Icono nombre={icono} tamano={16} />
  {/if}
  <span>{etiqueta}</span>
</button>

<style>
  .boton {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 40px;
    padding: 0 14px;
    border-radius: 12px;
    border: 1px solid var(--linea);
    background: transparent;
    color: var(--texto);
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    transition: opacity 150ms;
  }

  .boton:hover:not(:disabled) {
    opacity: 0.86;
  }

  .boton:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .tinta {
    padding: 0 16px;
    border: 0;
    background: var(--tinta);
    color: var(--sobre-tinta);
  }

  .acento {
    padding: 0 16px;
    border: 0;
    background: var(--acento);
    color: var(--sobre-acento);
  }

  .grande {
    width: 100%;
    height: 48px;
    font-size: 14px;
  }

  .verde {
    color: var(--verde);
  }
</style>
