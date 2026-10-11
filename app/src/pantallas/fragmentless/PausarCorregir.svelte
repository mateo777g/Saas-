<!--
  «Pausar o corregir fechas» (fila de Clientes): llama a fijar_licencia(restaurante, activa,
  inicio, fin) con lo que quede en la ventana, tal cual. Pausada, o con su fecha de fin pasada,
  deja de funcionar al momento.
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Selector from '../../diseno/Selector.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { fijarLicencia, type Cliente } from '../../lib/panel';

  let {
    cliente,
    alCerrar,
    alGuardar,
  }: { cliente: Cliente; alCerrar: () => void; alGuardar: () => void } = $props();

  // La ventana arranca con lo que tiene hoy; lo de la lista ya no la cambia mientras está abierta.
  // svelte-ignore state_referenced_locally
  let licencia = $state<'prendida' | 'pausada'>(cliente.licencia_activa ? 'prendida' : 'pausada');
  // svelte-ignore state_referenced_locally
  let inicio = $state(cliente.licencia_inicio ?? '');
  // svelte-ignore state_referenced_locally
  let fin = $state(cliente.licencia_fin ?? '');
  let error = $state<string | null>(null);

  async function guardar() {
    const r = await fijarLicencia(cliente.id, licencia === 'prendida', inicio || null, fin || null);
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Cambios guardados' };
  }
</script>

<Ventana etiqueta="PAUSAR O CORREGIR" titulo={cliente.nombre} {alCerrar}>
  <Formulario
    boton={{ etiqueta: 'Guardar cambios', icono: 'check' }}
    {guardar}
    alTerminar={alCerrar}
    bind:error
  >
    <div class="grupo">
      <span class="etiqueta">LICENCIA</span>
      <Selector
        etiqueta="Licencia"
        opciones={[
          { valor: 'prendida', texto: 'Prendida' },
          { valor: 'pausada', texto: 'Pausada' },
        ]}
        elegida={licencia}
        alElegir={(valor) => {
          licencia = valor;
          error = null;
        }}
        alto={34}
        lleno
      />
    </div>
    <div class="par">
      <Campo id="fijar-inicio" etiqueta="INICIO" tipo="date" bind:valor={inicio} />
      <Campo id="fijar-fin" etiqueta="FIN" tipo="date" bind:valor={fin} />
    </div>
    <p class="pista">Se guarda tal cual. Pausada, o con su fecha de fin pasada, deja de funcionar al momento.</p>
  </Formulario>
</Ventana>

<style>
  .grupo {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
</style>
