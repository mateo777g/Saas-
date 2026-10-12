<!--
  «Nuevo distribuidor» (el botón de arriba en Distribuidores): llama a
  alta_distribuidor(nombre, telefono, correo). Nace activo, sin cuenta y sin clientes; el teléfono
  y el correo son solo para contacto.
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { altaDistribuidor } from '../../lib/panel';

  let { alCerrar, alGuardar }: { alCerrar: () => void; alGuardar: () => void } = $props();

  let nombre = $state('');
  let telefono = $state('');
  let correo = $state('');

  async function guardar() {
    const r = await altaDistribuidor(nombre.trim(), telefono.trim(), correo.trim());
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Alta guardada' };
  }
</script>

<Ventana etiqueta="NUEVO DISTRIBUIDOR" titulo="Dar de alta un distribuidor" {alCerrar}>
  <Formulario boton={{ etiqueta: 'Dar de alta', icono: 'mas' }} {guardar} alTerminar={alCerrar}>
    <Campo id="dist-nombre" etiqueta="NOMBRE" bind:valor={nombre} placeholder="Ej. Juanito Pérez" />
    <div class="par">
      <Campo id="dist-telefono" etiqueta="TELÉFONO" tipo="tel" bind:valor={telefono} placeholder="Ej. 55 1234 5678" />
      <Campo
        id="dist-correo"
        etiqueta="CORREO"
        tipo="email"
        bind:valor={correo}
        placeholder="Ej. juanito@ejemplo.com"
        corrector={false}
      />
    </div>
    <p class="pista">
      Nace con estado Activo y sin clientes. El teléfono y el correo son para contacto; para que
      entre a su panel, después ligas su cuenta.
    </p>
  </Formulario>
</Ventana>
