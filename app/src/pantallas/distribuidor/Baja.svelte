<!--
  La pantalla del distribuidor de baja (maqueta aprobada el 12 de octubre de 2026:
  YXYVVNdLRXwgWCNErFSeyK, «De baja»). Sale en lugar de su panel mientras su fila en distribuidores
  esté de baja. No se vuelve a pedir la contraseña: la sesión sigue guardada y, en cuanto
  Fragmentless lo reactiva, su panel vuelve al leer de nuevo.

  Copia la suscripción terminada del gerente (gerente/Suscripcion.svelte), que copia el login con
  sus medidas: la tarjeta a la izquierda y las manchas a la derecha. El título va sin «dado»,
  para que el texto no tenga género.
-->
<script lang="ts">
  import Boton from '../../diseno/Boton.svelte';
  import CajaError from '../../diseno/CajaError.svelte';
  import Icono from '../../diseno/Icono.svelte';
  import Manchas from '../../diseno/Manchas.svelte';
  import { WHATSAPP_FRAGMENTLESS, WHATSAPP_FRAGMENTLESS_TEXTO } from '../../lib/fragmentless';

  let { alSalir }: { alSalir: () => void } = $props();

  function escribir() {
    window.open(WHATSAPP_FRAGMENTLESS, '_blank', 'noopener');
  }
</script>

<main class="pantalla">
  <section class="tarjeta" aria-label="Tu cuenta">
    <div>
      <h1 class="titulo">Tu cuenta<br />está de baja</h1>
      <p class="sub">Fragmentless dio de baja tu cuenta de distribuidor. Escríbele para reactivarla.</p>

      <div class="acciones">
        <Boton tono="tinta" tamano="grande" icono="mensaje" etiqueta="Escribir a Fragmentless" onclick={escribir} />
      </div>

      <div class="aviso">
        <CajaError
          tipo="info"
          tamano={13}
          mensaje="Tu sesión sigue guardada. En cuanto te reactive, vuelves a tu panel."
        />
      </div>
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
