<!--
  «Ligar cuenta» (fila de Distribuidores, solo en quien todavía no la tiene): llama a
  ligar_distribuidor(distribuidor, correo). Como Ligar gerente, la cuenta se crea antes a mano en
  el dashboard de Supabase, y no puede ser de Fragmentless ni de nadie en un restaurante (una
  cuenta, un panel).
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { ligarDistribuidor, type Distribuidor } from '../../lib/panel';

  let {
    distribuidor,
    alCerrar,
    alGuardar,
  }: { distribuidor: Distribuidor; alCerrar: () => void; alGuardar: () => void } = $props();

  let correo = $state('');

  async function guardar() {
    const r = await ligarDistribuidor(distribuidor.id, correo.trim());
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Cuenta ligada' };
  }
</script>

<Ventana
  etiqueta="LIGAR CUENTA"
  titulo={distribuidor.nombre}
  texto="La cuenta se crea antes a mano en Supabase, en Authentication → Add user. Aquí solo se anota como suya, para que entre a su panel de distribuidor."
  {alCerrar}
>
  <Formulario boton={{ etiqueta: 'Ligar cuenta', icono: 'usuario-mas' }} {guardar} alTerminar={alCerrar}>
    <Campo
      id="cuenta-correo"
      etiqueta="CORREO DE SU CUENTA"
      tipo="email"
      bind:valor={correo}
      placeholder="Ej. memo@ejemplo.com"
      corrector={false}
      pista="Cada distribuidor tiene una sola cuenta, y cada cuenta es de un solo distribuidor."
    />
  </Formulario>
</Ventana>
