<!--
  El portero: decide qué pantalla se ve. Sin sesión, el login. Con sesión, le pregunta a Postgres
  qué panel le toca (lib/sesion.ts): el de Fragmentless o el del gerente. Si la sesión se cierra
  desde otro lado (otra pestaña, o Supabase ya no la acepta), regresa al login.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Login from './pantallas/Login.svelte';
  import PanelFragmentless from './pantallas/PanelFragmentless.svelte';
  import PanelGerente from './pantallas/PanelGerente.svelte';
  import { abrirPanel, type Panel } from './lib/sesion';
  import { cerrarSesion, supabase } from './lib/supabase';
  import { ALGO_SALIO, SIN_CONEXION, esDeRed } from './lib/errores';

  type Aviso = { mensaje: string; tipo: 'alerta' | 'info' };
  type Vista =
    | { tipo: 'cargando' }
    | { tipo: 'login'; aviso: Aviso | null }
    | { tipo: 'panel'; panel: Panel };

  let vista = $state<Vista>({ tipo: 'cargando' });

  async function abrir() {
    const { data, error } = await supabase.auth.getSession();
    if (error) {
      console.error('[sesion] no se pudo leer la sesión guardada:', error);
      await cerrarSesion();
      vista = { tipo: 'login', aviso: { mensaje: esDeRed(error) ? SIN_CONEXION : ALGO_SALIO, tipo: 'alerta' } };
      return;
    }
    if (!data.session) {
      vista = { tipo: 'login', aviso: null };
      return;
    }
    const resultado = await abrirPanel(data.session.user);
    vista =
      'panel' in resultado
        ? { tipo: 'panel', panel: resultado.panel }
        : { tipo: 'login', aviso: { mensaje: resultado.mensaje, tipo: 'alerta' } };
  }

  async function salir() {
    await cerrarSesion();
    vista = { tipo: 'login', aviso: { mensaje: 'Cerraste sesión.', tipo: 'info' } };
  }

  // Con el panel abierto, la cuenta dejó de tener acceso (ya no es gerente de ningún
  // restaurante): se cierra la sesión y el login dice por qué, como al entrar.
  async function sinAcceso(mensaje: string) {
    await cerrarSesion();
    vista = { tipo: 'login', aviso: { mensaje, tipo: 'alerta' } };
  }

  onMount(() => {
    abrir();
    const { data } = supabase.auth.onAuthStateChange((evento) => {
      // Solo importa si se ve un panel: el login y "Cerrar sesión" ya ponen su propia pantalla.
      if (evento === 'SIGNED_OUT' && vista.tipo === 'panel') vista = { tipo: 'login', aviso: null };
    });
    return () => data.subscription.unsubscribe();
  });
</script>

{#if vista.tipo === 'login'}
  <!-- Con cada aviso nuevo el login se vuelve a montar: el de "sesión cerrada" que llega primero
       no tapa el que llega después ("Cerraste sesión.", "Esta cuenta no tiene acceso…"). -->
  {#key vista.aviso}
    <Login aviso={vista.aviso} alEntrar={(panel) => (vista = { tipo: 'panel', panel })} />
  {/key}
{:else if vista.tipo === 'panel' && vista.panel.tipo === 'fragmentless'}
  <PanelFragmentless correo={vista.panel.correo} alSalir={salir} />
{:else if vista.tipo === 'panel' && vista.panel.tipo === 'gerente'}
  <PanelGerente
    usuarioId={vista.panel.usuarioId}
    datos={vista.panel.datos}
    alSalir={salir}
    alSinAcceso={sinAcceso}
  />
{/if}
