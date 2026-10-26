<!--
  El PIN (maqueta de Empleados): la inicial, «Hola, Pepe», los 4 puntos y el teclado. Con el
  cuarto número se manda al Worker, que lo mezcla con su llave; Postgres decide. Cada PIN
  equivocado dice cuántos intentos quedan; al quinto, el bloqueo, con hasta qué hora. Bloqueado,
  el teclado se apaga y la lista se vuelve a leer cada 30 segundos, para prenderlo en cuanto
  Postgres lo deje entrar (pasaron los 15 minutos, o su gerente lo desbloqueó).

  `otraVez` es el de la tableta compartida tras 2 minutos sin usarla: «¿Sigues ahí, Lupita?».
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import {
    entrar,
    FalloAparato,
    horaDe,
    nombres,
    type Ligado,
    type Lista,
    type PersonaAparato,
  } from '../../lib/aparato';
  import { ALGO_SALIO_PANEL } from '../../lib/errores';
  import Arriba from './Arriba.svelte';

  const RELEER_BLOQUEO = 30_000;
  const TECLAS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'borrar'];

  let {
    ligado,
    lista,
    persona,
    otraVez = false,
    alEntrar,
    alVolver,
    alDesligado,
  }: {
    ligado: Ligado;
    lista: Lista;
    persona: PersonaAparato;
    otraVez?: boolean;
    alEntrar: () => void;
    alVolver?: () => void;
    alDesligado: (mensaje: string) => void;
  } = $props();

  let pin = $state('');
  let aviso = $state<string | null>(null);
  let enviando = false;
  // El bloqueo que se sabe: el que trae la lista, o el que acaba de decir Postgres.
  // svelte-ignore state_referenced_locally
  let bloqueo = $state<{ hasta: string | null } | null>(persona.bloqueado ? { hasta: persona.bloqueadoHasta } : null);

  const nombre = $derived(persona.nombre.trim().split(/\s+/)[0]);
  const textoBloqueo = $derived(
    !bloqueo
      ? null
      : bloqueo.hasta
        ? `Te equivocaste 5 veces. Vuelve a intentarlo a las ${horaDe(bloqueo.hasta)}.`
        : 'Tu PIN está bloqueado. Pídele a tu gerente que lo desbloquee en Empleados.',
  );

  function tecla(k: string) {
    if (bloqueo || enviando) return;
    aviso = null;
    if (k === 'borrar') {
      pin = pin.slice(0, -1);
      return;
    }
    if (pin.length >= 4) return;
    pin += k;
    if (pin.length === 4) probar();
  }

  async function probar() {
    enviando = true;
    try {
      const r = await entrar(ligado, persona, pin);
      if (r.ok) {
        alEntrar();
        return;
      }
      pin = '';
      if (r.motivo === 'pin') {
        aviso = r.quedan === 1 ? 'PIN equivocado. Te queda 1 intento.' : `PIN equivocado. Te quedan ${r.quedan} intentos.`;
      } else {
        bloqueo = { hasta: r.hasta };
      }
    } catch (falla) {
      pin = '';
      if (falla instanceof FalloAparato && falla.desligado) {
        alDesligado(falla.message);
        return;
      }
      if (!(falla instanceof FalloAparato)) console.error('[aparato] no se pudo entrar:', falla);
      aviso = falla instanceof FalloAparato ? falla.message : ALGO_SALIO_PANEL;
    } finally {
      enviando = false;
    }
  }

  // Bloqueado: ¿ya lo deja entrar Postgres?
  $effect(() => {
    if (!bloqueo) return;
    const reloj = setInterval(async () => {
      try {
        const yo = (await nombres(ligado.token)).personas.find((p) => p.id === persona.id);
        if (yo && !yo.bloqueado) bloqueo = null;
      } catch (falla) {
        if (falla instanceof FalloAparato && falla.desligado) alDesligado(falla.message);
        else console.error('[aparato] no se pudo revisar el bloqueo:', falla);
      }
    }, RELEER_BLOQUEO);
    return () => clearInterval(reloj);
  });

  // Con teclado (una tableta con teclado, o la compu) también se escribe.
  onMount(() => {
    const alTeclear = (e: KeyboardEvent) => {
      if (/^\d$/.test(e.key)) tecla(e.key);
      else if (e.key === 'Backspace') tecla('borrar');
    };
    document.addEventListener('keydown', alTeclear);
    return () => document.removeEventListener('keydown', alTeclear);
  });
</script>

<Arriba lugar={alVolver ? null : { restaurante: lista.restaurante, aparato: lista.aparato }} {alVolver} />
<div class="cuerpo">
  <div class="centro">
    <div class="pin">
      <span class="inicial">{persona.nombre.trim().charAt(0).toUpperCase()}</span>
      <h1 class="titulo">{otraVez ? `¿Sigues ahí, ${nombre}?` : `Hola, ${nombre}`}</h1>
      <p class="texto">{otraVez ? 'Pasaron 2 minutos sin usarla. Pon tu PIN para seguir.' : 'Pon tu PIN'}</p>
      <div class="puntos" aria-label="{pin.length} de 4 números">
        {#each [0, 1, 2, 3] as i (i)}<span class:lleno={i < pin.length}></span>{/each}
      </div>
      <div class="aviso">
        {#if textoBloqueo ?? aviso}<CajaError mensaje={textoBloqueo ?? aviso ?? ''} />{/if}
      </div>
    </div>
  </div>
  <div class="teclado">
    {#each TECLAS as k, i (i)}
      {#if !k}
        <span class="tecla vacia"></span>
      {:else if k === 'borrar'}
        <button type="button" class="tecla vacia" aria-label="Borrar" disabled={!!bloqueo} onclick={() => tecla(k)}>
          <Icono nombre="borrar" tamano={24} />
        </button>
      {:else}
        <button type="button" class="tecla" disabled={!!bloqueo} onclick={() => tecla(k)}>{k}</button>
      {/if}
    {/each}
  </div>
</div>

<style>
  .pin {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    text-align: center;
  }

  .pin .inicial {
    width: 64px;
    height: 64px;
    border-radius: 32px;
    font-size: 24px;
  }

  .puntos {
    margin-top: 8px;
    display: flex;
    gap: 16px;
  }

  .puntos span {
    width: 14px;
    height: 14px;
    border-radius: 7px;
    border: 1.5px solid var(--suave);
  }

  .puntos span.lleno {
    background: var(--tinta);
    border-color: var(--tinta);
  }

  .aviso {
    min-height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: left;
  }

  .teclado {
    margin-top: 6px;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
  }

  .tecla {
    height: 64px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid var(--linea);
    border-radius: 18px;
    background: var(--solido);
    color: var(--texto);
    font-size: 24px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .tecla:active:not(:disabled) {
    background: var(--chip);
  }

  .tecla.vacia {
    border: 0;
    background: transparent;
  }

  .tecla:disabled {
    opacity: 0.35;
    cursor: default;
  }
</style>
