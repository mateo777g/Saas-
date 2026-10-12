<!--
  La ventana Perfil, portada de panel/views/perfil_ventana.py (maqueta aprobada:
  https://claude.ai/artifact/TUMyJiwQiuQrHao64KEpKA). Se abre con el pie de la barra lateral.
  El nombre completo y "¿Cómo quieres que te llamemos?" (la etiqueta de la libreta 4; en Flet
  decía "…que Fragmentless te llame"). Lo guarda guardar_perfil: el nombre cambia en todas sus
  sucursales y el apodo vale en todas (libreta 4, decidido el 11 de octubre de 2026).

  Como en Flet: los errores salen dentro de la ventana y al guardar se cierra sin aviso. El
  panel vuelve a leer para que el saludo y el pie digan ya el nombre nuevo.
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { guardarPerfil } from '../../lib/gerente';

  let {
    nombre: nombreActual,
    apodo: apodoActual,
    alCerrar,
    alGuardar,
  }: {
    nombre: string;
    apodo: string | null;
    alCerrar: () => void;
    alGuardar: () => Promise<void>;
  } = $props();

  // Arranca con lo que tiene: su nombre en esta sucursal y su apodo (vacío si no tiene).
  // svelte-ignore state_referenced_locally
  let nombre = $state(nombreActual);
  // svelte-ignore state_referenced_locally
  let apodo = $state(apodoActual ?? '');

  async function guardar() {
    const r = await guardarPerfil(nombre, apodo);
    if (!r.ok) return { error: r.mensaje };
    await alGuardar();
    return { listo: '' };
  }
</script>

<Ventana
  etiqueta="PERFIL"
  titulo="Tus datos"
  texto="Y cómo te llama Fragmentless en el panel."
  ancho={440}
  tamanoTexto={12.5}
  {alCerrar}
>
  <Formulario
    boton={{ etiqueta: 'Guardar cambios', icono: 'check' }}
    {guardar}
    alTerminar={alCerrar}
    sinAviso
    espacio={18}
    antesDelBoton={24}
  >
    <Campo
      id="perfil-nombre"
      etiqueta="NOMBRE COMPLETO"
      bind:valor={nombre}
      placeholder="Tu nombre y apellidos"
      autocomplete="name"
    />
    <!-- Sin placeholder, como en Flet: ahí se quitó el "Ej: …" a propósito. -->
    <Campo
      id="perfil-apodo"
      etiqueta="¿CÓMO QUIERES QUE TE LLAMEMOS?"
      bind:valor={apodo}
      pista="Sale en el saludo de Inicio y del Agente IA. Máximo 20 letras."
    />
  </Formulario>
</Ventana>
