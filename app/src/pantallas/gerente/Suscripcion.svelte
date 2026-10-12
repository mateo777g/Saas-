<!--
  La suscripción terminada (maqueta aprobada el 10 de octubre de 2026: X4t62jG6dDG1hKfR4ZyyXZ,
  paso 1). Sale en lugar del panel cuando la sucursal en la que está no funciona hoy, según
  Postgres (mis_sucursales: vencida o pausada). No se vuelve a pedir la contraseña: la sesión
  sigue guardada y, en cuanto Fragmentless le suma meses o la reactiva, el panel vuelve al leer
  de nuevo.

  Copia el login, con sus medidas (las de sesion_view.py, como dice la nota de la maqueta; su
  dibujo salía 50 px más ancho): la tarjeta a la izquierda y las manchas a la derecha. En el paso 1 solo hay
  «Escribir a Fragmentless» (WhatsApp); «Renovar con Mercado Pago» llega en el paso 3, y nunca
  para una pausada (pagar no quita la pausa). Abajo, las otras sucursales que sí funcionan, cada
  una con «Ir a ella» (todas, decidido el 11 de octubre de 2026; la maqueta dibujaba una).
-->
<script lang="ts">
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Manchas from '../../diseno/Manchas.svelte';
  import { fechaEnPalabras } from '../../lib/formato';
  import { WHATSAPP_FRAGMENTLESS, WHATSAPP_FRAGMENTLESS_TEXTO } from '../../lib/fragmentless';
  import type { Sucursal } from '../../lib/gerente';

  let {
    sucursal,
    otras,
    alIr,
    alSalir,
  }: {
    sucursal: Sucursal;
    otras: Sucursal[];
    alIr: (sucursal: Sucursal) => void;
    alSalir: () => void;
  } = $props();

  const pausada = $derived(sucursal.estado === 'pausada');

  function escribir() {
    window.open(WHATSAPP_FRAGMENTLESS, '_blank', 'noopener');
  }
</script>

<main class="pantalla">
  <section class="tarjeta" aria-label="Tu suscripción">
    <div>
      <h1 class="titulo">
        {#if pausada}Tu suscripción<br />está pausada{:else}Tu suscripción<br />terminó{/if}
      </h1>
      <p class="sub">
        {#if pausada}
          Fragmentless pausó {sucursal.nombre}. Escríbele para reactivarla.
        {:else}
          {sucursal.nombre} funcionó hasta el {fechaEnPalabras(sucursal.licencia_fin)}. Escribe a
          Fragmentless para renovarla.
        {/if}
      </p>

      <div class="acciones">
        <Boton tono="tinta" tamano="grande" icono="mensaje" etiqueta="Escribir a Fragmentless" onclick={escribir} />
      </div>

      <div class="aviso">
        <CajaError
          tipo="info"
          tamano={13}
          mensaje="Tus datos siguen guardados. En cuanto se {pausada
            ? 'reactive'
            : 'renueve'}, tu panel vuelve tal como lo dejaste."
        />
      </div>

      {#if otras.length}
        <div class="otras">
          <span class="etiqueta">
            {otras.length === 1 ? 'TU OTRA SUCURSAL SIGUE ACTIVA' : 'TUS OTRAS SUCURSALES SIGUEN ACTIVAS'}
          </span>
          {#each otras as s (s.id)}
            <div class="otra">
              <span class="cuadro-icono"><Icono nombre="tienda" tamano={16} /></span>
              <span class="nombres">
                <span class="nombre">{s.nombre}</span>
                <span class="slug">{s.slug}</span>
              </span>
              <Boton
                tamano="chico"
                icono="derecha"
                iconoAlFinal
                etiqueta="Ir a ella"
                onclick={() => alIr(s)}
              />
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <div class="pie">
      <span class="nota">
        <Icono nombre="mensaje" tamano={14} />
        WhatsApp de Fragmentless: {WHATSAPP_FRAGMENTLESS_TEXTO}
      </span>
      <Boton icono="salir" etiqueta="Cerrar sesión" onclick={alSalir} />
    </div>
  </section>

  <Manchas />
</main>

<style>
  /* Las dos mitades del login, 94 a 106, con 12 de aire alrededor y entre ellas. */
  .pantalla {
    height: 100vh;
    height: 100dvh;
    padding: 12px;
    display: grid;
    grid-template-columns: 94fr 106fr;
    gap: 12px;
    background: var(--suelo);
  }

  .tarjeta {
    min-width: 0;
    overflow: auto;
    padding: 55px 47px 47px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    gap: 28px;
    background: var(--solido);
    border: 1px solid var(--linea);
    border-radius: 22px;
  }

  .titulo {
    margin: 0;
    font-size: 56px;
    font-weight: 800;
    line-height: 1.04;
    letter-spacing: -1.68px;
    text-wrap: balance;
  }

  .sub {
    margin: 14px 0 0;
    max-width: 46ch;
    font-size: 16px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .acciones {
    margin-top: 40px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .aviso {
    margin-top: 14px;
  }

  .otras {
    margin-top: 28px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .otra {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 10px 10px 12px;
    border: 1px solid var(--linea);
    border-radius: 14px;
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

  .nombres {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .nombre {
    font-size: 13.5px;
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .slug {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--tenue);
  }

  .pie {
    height: 48px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }

  .nota {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 12.5px;
    font-weight: 500;
    color: var(--tenue);
  }
</style>
