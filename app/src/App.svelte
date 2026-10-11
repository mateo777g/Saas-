<!--
  El portero: decide qué pantalla se ve. Sin sesión, el login. Con sesión, le pregunta a Postgres
  qué panel le toca (lib/sesion.ts): el de Fragmentless o el del gerente. Si la sesión se cierra
  desde otro lado (otra pestaña, o Supabase ya no la acepta), regresa al login.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import Login from './pantallas/Login.svelte';
  import Pendiente from './pantallas/Pendiente.svelte';
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
    const resultado = await abrirPanel(data.session.user.id);
    vista =
      'panel' in resultado
        ? { tipo: 'panel', panel: resultado.panel }
        : { tipo: 'login', aviso: { mensaje: resultado.mensaje, tipo: 'alerta' } };
  }

  async function salir() {
    await cerrarSesion();
    vista = { tipo: 'login', aviso: { mensaje: 'Cerraste sesión.', tipo: 'info' } };
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
  <Login aviso={vista.aviso} alEntrar={(panel) => (vista = { tipo: 'panel', panel })} />
{:else if vista.tipo === 'panel'}
  <Pendiente panel={vista.panel} alSalir={salir} />
{/if}
