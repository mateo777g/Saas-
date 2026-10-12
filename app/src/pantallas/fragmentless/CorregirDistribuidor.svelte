<!--
  «Corregir datos» (fila de Distribuidores): llama a editar_distribuidor(distribuidor, nombre,
  telefono, correo). Trae puestos sus datos de hoy; un teléfono o un correo en blanco se guarda
  vacío. El correo es de contacto: no cambia la cuenta con la que entra a su panel.
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { editarDistribuidor, type Distribuidor } from '../../lib/panel';

  let {
    distribuidor,
    alCerrar,
    alGuardar,
  }: { distribuidor: Distribuidor; alCerrar: () => void; alGuardar: () => void } = $props();

  // Lo que trae al abrir; después es lo que se escriba.
  // svelte-ignore state_referenced_locally
  let nombre = $state(distribuidor.nombre);
  // svelte-ignore state_referenced_locally
  let telefono = $state(distribuidor.telefono ?? '');
  // svelte-ignore state_referenced_locally
  let correo = $state(distribuidor.correo ?? '');

  async function guardar() {
    const r = await editarDistribuidor(distribuidor.id, nombre.trim(), telefono.trim(), correo.trim());
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Cambios guardados' };
  }
</script>

<Ventana etiqueta="CORREGIR DATOS" titulo={distribuidor.nombre} {alCerrar}>
  <Formulario boton={{ etiqueta: 'Guardar cambios', icono: 'check' }} {guardar} alTerminar={alCerrar}>
    <Campo id="corregir-nombre" etiqueta="NOMBRE" bind:valor={nombre} />
    <Campo id="corregir-telefono" etiqueta="TELÉFONO" tipo="tel" bind:valor={telefono} placeholder="Sin teléfono" />
    <Campo
      id="corregir-correo"
      etiqueta="CORREO"
      tipo="email"
      bind:valor={correo}
      placeholder="Sin correo"
      corrector={false}
      pista="Este correo es para contacto: cambiarlo no cambia la cuenta con la que entra a su panel."
    />
  </Formulario>
</Ventana>
