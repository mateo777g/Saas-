<!--
  «Pasar una tarjeta a otro celular» (maqueta v22, VENTANA «Confirmar código»): la abren «Confirmar un código» del panel y
  «Pasar tarjeta» de la Caja (quien cobra). Pide el código de 6 letras que le salió en su celular nuevo y el número de su
  tarjeta (si lo mandó por WhatsApp, el número desde el que escribió); Postgres revisa que el código sea de ese número
  (pasar_tarjeta). Al pasarla sale su nombre con lo que lleva y el botón en verde; si no cuadra, un solo mensaje, sin decir
  qué falló. Recibe el cliente de Supabase: el panel y el aparato la comparten.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import Boton from '../../diseno/Boton.svelte';
  import Campo from '../../diseno/Campo.svelte';
  import GrupoCampos from '../../diseno/GrupoCampos.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { cuantos, diezDigitos, limpiarCodigo, pasarTarjeta, type FormaLealtad, type TarjetaEnCuenta } from '../../lib/lealtad';

  let {
    cliente,
    restauranteId,
    regla = null,
    alPasar,
    alCerrar,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    regla?: { forma: FormaLealtad; meta: number | null } | null; // para decir «8 de 10 sellos»
    alPasar?: () => void;
    alCerrar: () => void;
  } = $props();

  const id = $props.id();
  let codigo = $state('');
  let telefono = $state('');
  let ocupado = $state(false);
  let pasada = $state<TarjetaEnCuenta | null>(null);
  let mensaje = $state<string | null>(null);

  const listo = $derived(limpiarCodigo(codigo).length === 6 && diezDigitos(telefono) !== null);
  const quieto = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Al cambiar lo escrito, el mensaje de antes se va.
  $effect(() => {
    void codigo;
    void telefono;
    mensaje = null;
  });

  async function pasar() {
    if (!listo || ocupado || pasada) return;
    ocupado = true;
    try {
      pasada = await pasarTarjeta(cliente, restauranteId, limpiarCodigo(codigo), diezDigitos(telefono)!);
      alPasar?.();
      setTimeout(alCerrar, quieto() ? 300 : 1100);
    } catch (falla) {
      mensaje = falla instanceof Error ? falla.message : 'No se pudo pasar su tarjeta. Intenta de nuevo.';
    }
    ocupado = false;
  }

  const lleva = (t: TarjetaEnCuenta) =>
    regla?.meta ? `${t.saldo.toLocaleString('en-US')} de ${cuantos(regla.forma, regla.meta)}` : t.premio_listo ? 'Premio listo' : '';
</script>

<Ventana
  etiqueta="TARJETA DE LEALTAD"
  titulo="Pasar una tarjeta a otro celular"
  nota="Escribe el código que le salió en su celular nuevo y el número de su tarjeta. Si te lo mandó por WhatsApp, que sea el número desde el que te escribió."
  ancho={600}
  centrado
  {alCerrar}
>
  <form
    class="campos"
    onsubmit={(e) => {
      e.preventDefault();
      void pasar();
    }}
  >
    <GrupoCampos>
      <div class="dos">
        <Campo id="{id}-codigo" etiqueta="CÓDIGO DE 6 LETRAS" bind:valor={codigo} placeholder="Ej. KXMPRT" largoMaximo={7} corrector={false} mono />
        <Campo id="{id}-tel" etiqueta="NÚMERO DE SU TARJETA" bind:valor={telefono} placeholder="Ej. 222 987 6543" tipo="tel" modoTeclado="tel" mono />
      </div>
    </GrupoCampos>
    {#if pasada}
      <div class="encontrada entra">
        <span class="inicial">{pasada.nombre.charAt(0).toUpperCase()}</span>
        <span class="enc-t"><b>{pasada.nombre}</b>{#if lleva(pasada)}<span>{lleva(pasada)}</span>{/if}</span>
        <span class="ok"><Icono nombre="check" tamano={15} />Ya está en su celular nuevo</span>
      </div>
    {:else if mensaje}
      <p class="resultado entra" role="alert"><Icono nombre="info" tamano={16} /><span>{mensaje}</span></p>
    {/if}
    <div class="pie">
      <Boton etiqueta="Cancelar" icono="cerrar" tono="alarga" onclick={alCerrar} />
      <span class="crece"></span>
      <Boton etiqueta="Pasar su tarjeta" tono="verde" tipo="submit" apagado={!listo || ocupado} cargando={ocupado} exito={!!pasada} />
    </div>
  </form>
</Ventana>

<style>
  .campos {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-top: 22px;
  }

  .dos {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
    align-items: start;
  }

  .encontrada {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
  }

  .inicial {
    width: 34px;
    height: 34px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--chip);
    color: var(--texto);
    font-size: 13px;
    font-weight: 700;
  }

  .enc-t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .enc-t b {
    font-size: 14px;
    font-weight: 700;
    color: var(--texto);
  }

  .enc-t > span {
    font-size: 12.5px;
    color: var(--suave);
  }

  .ok {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12.5px;
    font-weight: 600;
    color: var(--verde);
  }

  .resultado {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 0;
    padding: 0 4px;
    font: 500 13px/1.45 var(--jakarta);
    color: var(--suave);
  }

  .resultado :global(svg) {
    flex: none;
    margin-top: 1px;
    color: var(--tenue);
  }

  .pie {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: 14px;
  }

  .crece {
    flex: 1;
  }

  @keyframes entra {
    from {
      opacity: 0;
      transform: translateY(-4px);
    }
  }

  .entra {
    animation: entra 0.26s ease-out;
  }

  @media (prefers-reduced-motion: reduce) {
    .entra {
      animation: none;
    }
  }
</style>
