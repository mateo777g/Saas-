<!--
  «Tus datos» (los datos de los clientes, 21 nov 2026; maqueta Qvn42kQsyRX3m9vscikYfB, «Menú · Tus datos»; encuestas 3, 8
  y 8b de planes/trabajo/datos-de-clientes/encuestas.md). Crece desde el ícono de persona de la barra de la vista Pedido,
  como la ventana de la «i». Solo enseña lo que este celular recuerda para este menú (los datos se cambian en Tu pedido,
  como siempre), la liga al aviso y «Borrar mis datos», que pregunta en la misma ventana: el bote en rojo, qué se borra y
  qué se queda, «Cancelar» y «Sí, borrar». Al borrar, la palomita que se dibuja (la de «Pedido enviado») y Tu pedido se
  queda sin los datos. Sin nada recordado, lo dice y deja solo la liga al aviso.
-->
<script lang="ts">
  import { tick } from 'svelte';
  import { quieto } from '../lib/movimiento';
  import { sinDatos, type Cliente } from '../lib/pedido';
  import type { Textos } from '../lib/textos';
  import Icono from './Icono.svelte';
  import VentanaCrece from './VentanaCrece.svelte';

  let {
    nombre,
    recordado,
    t,
    desde,
    alAviso,
    alBorrar,
    alCerrar,
  }: {
    // El nombre del restaurante: «Lo que este celular recuerda para pedir en La Fonda de Don Chuy».
    nombre: string;
    recordado: Cliente;
    t: Textos;
    desde: HTMLElement | null;
    alAviso: (desde: HTMLElement) => void;
    // Borra lo de este celular; regresa si pudo.
    alBorrar: () => boolean;
    alCerrar: () => void;
  } = $props();

  type Paso = 'ver' | 'pregunta' | 'listo' | 'vacio';
  // svelte-ignore state_referenced_locally
  let paso = $state<Paso>(sinDatos(recordado) ? 'vacio' : 'ver');
  let caja = $state<HTMLDivElement>();
  let pasos = $state<HTMLDivElement>();

  const telefono = $derived.by(() => {
    const d = recordado.telefono.replace(/\D/g, '');
    return d.length === 10 ? d.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3') : recordado.telefono.trim();
  });

  // Otro paso en la misma ventana: lo de adentro sube un poco, uno tras otro, y la caja se acomoda con un rebote corto.
  async function irA(nuevo: Paso) {
    paso = nuevo;
    await tick();
    if (quieto() || !pasos) return;
    [...pasos.children].forEach((x, i) =>
      x.animate([{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], {
        duration: 380,
        delay: i * 50,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
        fill: 'backwards',
      }),
    );
    caja?.animate([{ transform: 'scale(0.985)' }, { transform: 'none' }], { duration: 300, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' });
  }

  function borrar() {
    if (alBorrar()) irA('listo');
  }
</script>

{#snippet ligaAviso()}
  <button type="button" class="dc-renglon" onclick={(e) => alAviso(e.currentTarget)}>
    <span>{t.avisoPrivacidad}</span><Icono nombre="flechita" tamano={18} grosor={2} />
  </button>
{/snippet}

<VentanaCrece etiqueta={t.tusDatos} {t} {desde} esconder bind:caja {alCerrar}>
  <div class="dc-paso" bind:this={pasos}>
    {#if paso === 'ver'}
      <div class="dc-cabeza" data-sube>
        <span class="dc-icono"><Icono nombre="persona" tamano={20} grosor={1.9} /></span>
        <h2>{t.tusDatos}</h2>
        <p>{t.datosTexto(nombre)}</p>
      </div>
      <div class="dc-cuerpo" data-sube>
        <div class="f-info-tarjeta dc-tarjeta">
          {#if recordado.nombre.trim()}
            <div class="dc-dato"><span>{t.datoNombre}</span><b>{recordado.nombre.trim()}</b></div>
          {/if}
          {#if telefono}
            <div class="dc-dato"><span>{t.telefono}</span><b>{telefono}</b></div>
          {/if}
          {#if recordado.direccion.trim() || recordado.referencias.trim()}
            <div class="dc-dato">
              <span>{t.direccion}</span>
              <b>{recordado.direccion.trim()}{#if recordado.referencias.trim()}<small>{recordado.referencias.trim()}</small>{/if}</b>
            </div>
          {/if}
        </div>
        {@render ligaAviso()}
        <button type="button" class="f-info-ir dc-rojo" onclick={() => irA('pregunta')}>{t.borrarMisDatos}</button>
      </div>
    {:else if paso === 'pregunta'}
      <div class="dc-cabeza">
        <span class="dc-icono rojo"><Icono nombre="bote" tamano={22} grosor={1.9} /></span>
        <h2>{t.borrarPregunta}</h2>
        <p>{t.borrarPreguntaTexto}</p>
      </div>
      <div class="dc-cuerpo dc-dos">
        <button type="button" class="f-info-ir" onclick={() => irA('ver')}>{t.cancelar}</button>
        <button type="button" class="dc-si" onclick={borrar}>{t.siBorrar}</button>
      </div>
    {:else if paso === 'listo'}
      <div class="dc-cabeza listo" role="status">
        <svg class="dc-palomita" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle class="aro" cx="24" cy="24" r="19"></circle><path class="pal" d="M16 24.5l5.5 5.5L32.5 19"></path>
        </svg>
        <h2>{t.listo}</h2>
        <p>{t.borradoTexto}</p>
      </div>
    {:else}
      <div class="dc-cabeza" data-sube>
        <span class="dc-icono"><Icono nombre="persona" tamano={20} grosor={1.9} /></span>
        <h2>{t.tusDatos}</h2>
        <p>{t.sinDatos}</p>
      </div>
      <div class="dc-cuerpo" data-sube>{@render ligaAviso()}</div>
    {/if}
  </div>
</VentanaCrece>
