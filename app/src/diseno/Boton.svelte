<!--
  boton() de diseno.py y los botones grandes del login y de la suscripción terminada.
    tono      linea: borde fino, sin relleno (los secundarios)
              tinta: el principal (negro en claro, blanco en oscuro)
              acento: naranja en claro, azul en oscuro (Conectar Mercado Pago, Renovar)
    tamano    normal: 40 de alto, letra 13 (la barra de arriba, las ventanas)
              grande: 48 de alto, letra 14, a todo lo ancho (el login)
              chico: 34 de alto, letra 12.5, icono 14 ("Ver clientes →")
    apagado   apagar() de diseno.py: al 40 % y sin clic (entrando, Actualizar mientras lee)
    cargando  la rueda que gira en lugar del icono, sin clic ("Guardando…" de una ventana)
    exito     la palomita verde en lugar del icono, sin clic (el éxito se ve en el botón, ~1.6 s)
    iconoAlFinal  el icono después del texto, como la flecha de "Ver clientes →"
    chip      el relleno de chip, sin perder el borde (Cancelar de Ocultar varios)
    ayuda     lo que sale con el cursor encima ("Primero crea una categoría")
-->
<script lang="ts">
  import Icono from './Icono.svelte';

  let {
    etiqueta,
    icono,
    tono = 'linea',
    tamano = 'normal',
    apagado = false,
    cargando = false,
    exito = false,
    iconoAlFinal = false,
    chip = false,
    ayuda,
    tipo = 'button',
    onclick,
  }: {
    etiqueta: string;
    icono?: string;
    tono?: 'linea' | 'tinta' | 'acento';
    tamano?: 'normal' | 'grande' | 'chico';
    apagado?: boolean;
    cargando?: boolean;
    exito?: boolean;
    iconoAlFinal?: boolean;
    chip?: boolean;
    ayuda?: string;
    tipo?: 'button' | 'submit';
    onclick?: (e: MouseEvent) => void;
  } = $props();

  const lado = $derived(tamano === 'chico' ? 14 : 16);
</script>

<button
  type={tipo}
  class="boton {tono} {tamano}"
  class:apagado
  class:chip
  title={ayuda}
  disabled={apagado || cargando || exito}
  {onclick}
>
  {#if cargando}
    <span class="rueda" aria-hidden="true"></span>
  {:else if exito}
    <span class="verde"><Icono nombre="check" tamano={lado} /></span>
  {:else if icono && !iconoAlFinal}
    <Icono nombre={icono} tamano={lado} />
  {/if}
  <span>{etiqueta}</span>
  {#if icono && iconoAlFinal && !cargando && !exito}
    <Icono nombre={icono} tamano={lado} />
  {/if}
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
    cursor: default;
  }

  .apagado {
    opacity: 0.4;
  }

  .chip {
    background: var(--chip);
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

  .chico {
    gap: 6px;
    height: 34px;
    padding: 0 12px;
    font-size: 12.5px;
  }

  .verde {
    color: var(--verde);
  }

  .rueda {
    width: 14px;
    height: 14px;
    flex: none;
    border-radius: 50%;
    border: 2px solid currentColor;
    border-top-color: transparent;
    animation: girar 0.8s linear infinite;
  }

  @keyframes girar {
    to {
      transform: rotate(360deg);
    }
  }
</style>
