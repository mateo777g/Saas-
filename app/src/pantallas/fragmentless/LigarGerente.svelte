<!--
  «Ligar gerente» (fila de Clientes): llama a ligar_gerente(restaurante, correo, nombre). La
  cuenta se crea antes a mano en el dashboard de Supabase; aquí solo se anota como gerente de
  este restaurante. Una persona puede ser gerente de varios, pero no se liga dos veces al mismo.
-->
<script lang="ts">
  import Campo from '../../diseno/Campo.svelte';
  import Formulario from '../../diseno/Formulario.svelte';
  import Ventana from '../../diseno/Ventana.svelte';
  import { ligarGerente, type Cliente } from '../../lib/panel';

  let {
    cliente,
    alCerrar,
    alGuardar,
  }: { cliente: Cliente; alCerrar: () => void; alGuardar: () => void } = $props();

  let correo = $state('');
  let nombre = $state('');

  async function guardar() {
    const r = await ligarGerente(cliente.id, correo.trim(), nombre.trim());
    if (!r.ok) return { error: r.mensaje };
    alGuardar();
    return { listo: 'Gerente ligado' };
  }
</script>

<Ventana
  etiqueta="LIGAR GERENTE"
  titulo={cliente.nombre}
  texto="La cuenta se crea antes a mano en Supabase, en Authentication → Add user. Aquí solo se anota como gerente de este restaurante."
  {alCerrar}
>
  <Formulario boton={{ etiqueta: 'Ligar gerente', icono: 'usuario-mas' }} {guardar} alTerminar={alCerrar}>
    <Campo
      id="ligar-correo"
      etiqueta="CORREO DE SU CUENTA"
      tipo="email"
      bind:valor={correo}
      placeholder="Ej. chuy.perez@ejemplo.com"
      corrector={false}
    />
    <Campo
      id="ligar-nombre"
      etiqueta="NOMBRE COMPLETO"
      bind:valor={nombre}
      placeholder="Ej. Jesús Pérez"
      pista="Así sale en su panel. Después lo puede corregir en su perfil."
    />
  </Formulario>
</Ventana>
