<!--
  Lo que pide PIN (parte 4c; maqueta Cancelaciones y descuentos, estados «Cancelar 1 de 2»,
  «¿Quién autoriza?», «PIN» y «PIN equivocado»): la hoja de cancelar o descontar con su motivo, y
  su botón. Si quien pide es de la caja o gerente, el botón aplica directo y queda a su nombre. Si
  no, «Pedir autorización» enseña a la caja y a los gerentes con PIN; quien tiene un bloqueo sale en
  gris. Esa persona toca su nombre y pone su PIN aquí, con el mismo teclado de entrar: con el cuarto
  número va al Worker y Postgres revisa el PIN y aplica en el mismo paso. Un PIN equivocado dice
  cuántos intentos quedan y cuenta para el bloqueo de esa persona.

  Lo de cada hoja (cuántos, el descuento, el motivo y en cuánto queda la cuenta) va adentro;
  `pedido` es null mientras falte algo o no quepa.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import type { Snippet } from 'svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import { ALGO_SALIO_PANEL } from '../../lib/errores';
  import { enZona } from '../../lib/formato';
  import { FalloPos, pedirConPin, pedirDirecto, pila, type Autoriza, type Autorizacion, type Pedido } from '../../lib/pos';
  import { NOMBRE_ROL } from '../../lib/roles';
  import Hoja from './Hoja.svelte';

  const TECLAS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'borrar'];

  let {
    cliente,
    titulo,
    sub,
    pedido,
    resumen,
    texto,
    autorizan,
    zona,
    alCerrar,
    alListo,
    children,
  }: {
    cliente: SupabaseClient;
    titulo: string;
    sub: string;
    pedido: Pedido | null;
    resumen: string; // lo que se pide, para quien autoriza: «Cancelar 1 Taco de pastor · «Eran de suadero»»
    texto: string; // el botón cuando quien pide autoriza: «Cancelar 1»
    autorizan: Autoriza[] | null; // null: quien pide es de la caja o gerente
    zona: string;
    alCerrar: () => void;
    alListo: (autorizo: string | null, reabierta: boolean) => void; // el nombre de quien puso su PIN
    children: Snippet;
  } = $props();

  let paso = $state<{ tipo: 'forma' } | { tipo: 'quien' } | { tipo: 'pin'; persona: Autoriza }>({ tipo: 'forma' });
  let error = $state<{ texto: string; sinRed: boolean } | null>(null);
  let ocupado = $state(false);
  let pin = $state('');
  let aviso = $state<string | null>(null);
  // Los bloqueos que dijo Postgres mientras esta hoja estaba abierta.
  let bloqueos = $state<Record<number, string>>({});

  const SIN_RED_PEDIDO =
    'Sin conexión. No se sabe si llegó: cuando regrese el internet, revisa la cuenta antes de volver a pedirlo.';

  function textoError(falla: unknown): { texto: string; sinRed: boolean } {
    if (falla instanceof FalloPos) return falla.sinRed ? { texto: SIN_RED_PEDIDO, sinRed: true } : { texto: falla.message, sinRed: false };
    console.error('[pos] no se pudo pedir:', falla);
    return { texto: ALGO_SALIO_PANEL, sinRed: false };
  }

  // «Mesero y caja».
  function rolesDe(roles: string[]): string {
    const n = roles.map((r) => NOMBRE_ROL[r] ?? r).map((r, i) => (i === 0 ? r : r.toLowerCase()));
    return n.length > 1 ? `${n.slice(0, -1).join(', ')} y ${n[n.length - 1]}` : (n[0] ?? '');
  }

  function bloqueoDe(p: Autoriza): string | null {
    const hasta = bloqueos[p.id] ?? p.bloqueadoHasta;
    if (!hasta) return null;
    if (hasta === 'infinity') return 'Con bloqueo';
    return Date.parse(hasta) > Date.now() ? `Con bloqueo · hasta ${enZona(hasta, zona).hora}` : null;
  }

  // Primero quien puede autorizar ahora, la caja antes que los gerentes (está en el mostrador).
  const lista = $derived(
    [...(autorizan ?? [])].sort(
      (x, y) =>
        Number(!!bloqueoDe(x)) - Number(!!bloqueoDe(y)) ||
        Number(!x.roles.includes('caja')) - Number(!y.roles.includes('caja')) ||
        x.nombre.localeCompare(y.nombre, 'es'),
    ),
  );

  function terminar(r: Autorizacion & { ok: true }, quien: Autoriza | null) {
    alListo(quien ? pila(quien.nombre) : null, r.reabierta);
  }

  async function pedir() {
    if (!pedido || ocupado) return;
    error = null;
    if (autorizan !== null) {
      paso = { tipo: 'quien' };
      return;
    }
    ocupado = true;
    try {
      const r = await pedirDirecto(cliente, pedido);
      if (r.ok) terminar(r, null);
      else error = { texto: ALGO_SALIO_PANEL, sinRed: false };
    } catch (falla) {
      error = textoError(falla);
    } finally {
      ocupado = false;
    }
  }

  function elegir(p: Autoriza) {
    pin = '';
    aviso = null;
    paso = { tipo: 'pin', persona: p };
  }

  function tecla(k: string) {
    if (paso.tipo !== 'pin' || ocupado || bloqueoDe(paso.persona)) return;
    aviso = null;
    if (k === 'borrar') {
      pin = pin.slice(0, -1);
      return;
    }
    if (pin.length >= 4) return;
    pin += k;
    if (pin.length === 4) probar(paso.persona);
  }

  async function probar(persona: Autoriza) {
    if (!pedido) return;
    ocupado = true;
    try {
      const r = await pedirConPin(cliente, pedido, persona.id, pin);
      pin = '';
      if (r.ok) {
        terminar(r, persona);
        return;
      }
      if (r.motivo === 'pin') {
        aviso = r.quedan === 1 ? 'PIN equivocado. Te queda 1 intento.' : `PIN equivocado. Te quedan ${r.quedan} intentos.`;
      } else {
        bloqueos[persona.id] = r.hasta ?? 'infinity';
        aviso = r.hasta
          ? `Te equivocaste 5 veces. Vuelve a intentarlo a las ${enZona(r.hasta, zona).hora}.`
          : 'Tu PIN está bloqueado. Pídele a tu gerente que lo desbloquee en Empleados.';
      }
    } catch (falla) {
      pin = '';
      aviso = textoError(falla).texto;
    } finally {
      ocupado = false;
    }
  }
</script>

<!-- Con teclado (la compu o una tableta con teclado) también se escribe el PIN. -->
<svelte:window
  onkeydown={(e) => {
    if (paso.tipo !== 'pin') return;
    if (/^\d$/.test(e.key)) tecla(e.key);
    else if (e.key === 'Backspace') tecla('borrar');
  }}
/>

{#if paso.tipo === 'forma'}
  <Hoja {titulo} {sub} {alCerrar}>
    {@render children()}
    {#if error}<CajaError tipo={error.sinRed ? 'sinred' : 'alerta'} mensaje={error.texto} />{/if}
    <button type="button" class="cel-boton fijo" disabled={!pedido || ocupado} onclick={pedir}>
      {autorizan === null ? texto : 'Pedir autorización'}
    </button>
  </Hoja>
{:else if paso.tipo === 'quien'}
  <Hoja titulo="¿Quién autoriza?" sub={resumen} {alCerrar}>
    <p class="pista">La caja o un gerente pone su PIN aquí, en tu celular.</p>
    {#if !autorizan?.length}
      <CajaError tipo="info" mensaje="Nadie de la caja ni gerentes tiene PIN todavía. Tu gerente lo pone en Empleados." />
    {:else}
      <div class="grupo-op">
        {#each lista as p (p.id)}
          {@const bloqueo = bloqueoDe(p)}
          <button type="button" class="persona" disabled={!!bloqueo} onclick={() => elegir(p)}>
            <span class="inicial">{p.nombre.trim().charAt(0).toUpperCase()}</span>
            <span class="t"><b>{p.nombre}</b><span>{rolesDe(p.roles)}</span></span>
            {#if bloqueo}<span class="chip-estado">{bloqueo}</span>{/if}
          </button>
        {/each}
      </div>
    {/if}
  </Hoja>
{:else}
  {@const persona = paso.persona}
  {@const bloqueada = !!bloqueoDe(persona)}
  <Hoja titulo="PIN de {pila(persona.nombre)}" cabeza={false} {alCerrar}>
    <div class="hoja-cabeza">
      <button type="button" class="cel-volver" onclick={() => (paso = { tipo: 'quien' })}>
        <Icono nombre="anterior" tamano={16} />Elegir a otra persona
      </button>
      <span class="crece"></span>
      <button type="button" class="cuadro" aria-label="Cerrar" title="Cerrar" onclick={alCerrar}>
        <Icono nombre="cerrar" tamano={16} />
      </button>
    </div>
    <div class="pin-hoja">
      <span class="inicial">{persona.nombre.trim().charAt(0).toUpperCase()}</span>
      <h3>{pila(persona.nombre)}, pon tu PIN</h3>
      <p>{resumen}</p>
      <div class="puntos" aria-label="{pin.length} de 4 números">
        {#each [0, 1, 2, 3] as i (i)}<span class:lleno={i < pin.length}></span>{/each}
      </div>
      <div class="aviso-pin">{#if aviso}<CajaError mensaje={aviso} />{/if}</div>
    </div>
    <div class="teclado">
      {#each TECLAS as k, i (i)}
        {#if !k}
          <span class="tecla vacia"></span>
        {:else if k === 'borrar'}
          <button type="button" class="tecla vacia" aria-label="Borrar" disabled={bloqueada} onclick={() => tecla(k)}>
            <Icono nombre="borrar" tamano={22} />
          </button>
        {:else}
          <button type="button" class="tecla" disabled={bloqueada} onclick={() => tecla(k)}>{k}</button>
        {/if}
      {/each}
    </div>
  </Hoja>
{/if}

<style>
  .cel-boton.fijo {
    flex: none;
  }
</style>
