<!--
  La contraseña otra vez, antes de conectar o desconectar Mercado Pago (libreta 4, «La terminal en el cobro, en Ajustes y
  en Mesas»; «Lo que decidí yo» 7 de planes/trabajo/terminal/libretas.md; maqueta de la terminal v2, «La contraseña»).
  Es la ventana de «Nueva mesa» (gerente/mesas/VentanaMesa.svelte): al centro, su campo en el gris de GrupoCampos y
  «Continuar» en verde. Vuelve a entrar con el mismo correo (lib/mercadoPago.ts, confirmarContrasena) y vale 5 minutos:
  lo revisa Postgres. Conectar lleva a Mercado Pago; desconectar borra la conexión y avisa con `alListo`.
-->
<script lang="ts">
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import { confirmarContrasena, desconectarMercadoPago, irAConectar } from '../../../lib/mercadoPago';

  let {
    para,
    restauranteId,
    sucursal,
    alListo,
    alCerrar,
  }: {
    para: 'conectar' | 'desconectar';
    restauranteId: string;
    sucursal: string; // «La Fonda de Don Chuy»
    alListo: () => void; // ya se desconectó
    alCerrar: () => void;
  } = $props();

  let contrasena = $state('');
  let paso = $state<null | 'revisando' | 'listo'>(null);

  // A medio revisar no se cierra.
  function cerrar() {
    if (!paso) alCerrar();
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    if (!contrasena) return { error: 'Escribe tu contraseña.' };
    paso = 'revisando';
    try {
      await confirmarContrasena(contrasena);
      if (para === 'conectar') {
        await irAConectar(restauranteId);
        paso = 'listo';
        return { listo: 'Abriendo Mercado Pago' };
      }
      await desconectarMercadoPago(restauranteId);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[ajustes] no se pudo seguir con la contraseña:', falla);
      paso = null;
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
    paso = 'listo';
    alListo();
    return { listo: 'Desconectado' };
  }
</script>

<Ventana
  centrado
  etiqueta="MERCADO PAGO"
  titulo="Escribe tu contraseña"
  texto={para === 'conectar'
    ? `Para conectar Mercado Pago a ${sucursal}, confirma que eres tú.`
    : `Para desconectar Mercado Pago de ${sucursal}, confirma que eres tú.`}
  ancho={440}
  alCerrar={cerrar}
>
  <Formulario verde boton={{ etiqueta: 'Continuar', icono: 'derecha' }} {guardar} alTerminar={alCerrar} antesDelBoton={28}>
    <GrupoCampos>
      <Campo
        id="mp-contrasena"
        etiqueta="CONTRASEÑA"
        tipo="password"
        autocomplete="current-password"
        corrector={false}
        placeholder="Tu contraseña de Fragmentless"
        bind:valor={contrasena}
      />
    </GrupoCampos>
  </Formulario>
</Ventana>
