<!--
  La pantalla de entrar, portada de panel/views/sesion_view.py (maqueta aprobada el 02/10:
  https://claude.ai/artifact/AXNeYMtPR1tSVgWdXTFjMu). Dos mitades del mismo alto: a la izquierda
  la tarjeta sólida con correo y contraseña; a la derecha las manchas (Manchas.svelte).

  Lo que cambió al dejar Flet (libreta 4): ya no lleva la nota "Por seguridad, el panel te pide
  entrar cada vez que lo abres", porque la sesión se queda guardada; el correo ya no viene
  puesto; y después de entrar no se revisa la licencia sino qué panel le toca (lib/sesion.ts).
  Los errores salen dentro de la tarjeta, debajo del botón.
-->
<script lang="ts">
  import { isAuthApiError } from '@supabase/supabase-js';
  import Boton from '../diseno/Boton.svelte';
  import CajaError from '../diseno/CajaError.svelte';
  import Icono from '../diseno/Icono.svelte';
  import Manchas from '../diseno/Manchas.svelte';
  import { ALGO_SALIO, SIN_CONEXION, esDeRed } from '../lib/errores';
  import { abrirPanel, type Panel } from '../lib/sesion';
  import { supabase } from '../lib/supabase';

  const INCORRECTOS = 'Correo o contraseña incorrectos.';

  let {
    aviso = null,
    alEntrar,
  }: {
    aviso?: { mensaje: string; tipo: 'alerta' | 'info' } | null;
    alEntrar: (panel: Panel) => void;
  } = $props();

  let correo = $state('');
  let contrasena = $state('');
  let verContrasena = $state(false);
  let entrando = $state(false);
  // El aviso con el que llega ("Cerraste sesión.") se muestra hasta que pase otra cosa.
  // svelte-ignore state_referenced_locally
  let mensaje = $state(aviso);

  function quitarMensaje() {
    // Al volver a escribir se quita el error de antes (como en Perfil).
    if (mensaje) mensaje = null;
  }

  async function entrar(e: SubmitEvent) {
    e.preventDefault();
    if (entrando) return;
    const email = correo.trim();
    if (!email || !contrasena) {
      mensaje = { mensaje: INCORRECTOS, tipo: 'alerta' };
      return;
    }

    entrando = true;
    mensaje = null;
    const { data, error } = await supabase.auth.signInWithPassword({ email, password: contrasena });
    if (error || !data.session) {
      console.error('[login] no se pudo entrar:', error);
      mensaje = {
        mensaje: esDeRed(error) ? SIN_CONEXION : isAuthApiError(error) ? INCORRECTOS : ALGO_SALIO,
        tipo: 'alerta',
      };
      entrando = false;
      return;
    }

    const resultado = await abrirPanel(data.session.user.id);
    if ('panel' in resultado) {
      alEntrar(resultado.panel);
      return; // la pantalla ya se reemplazó
    }
    mensaje = { mensaje: resultado.mensaje, tipo: 'alerta' };
    entrando = false;
  }
</script>

<main class="pantalla">
  <section class="tarjeta" aria-label="Inicia sesión">
    <h1 class="titulo">Inicia sesión</h1>
    <p class="sub">Ingresa tus datos para administrar tu menú.</p>

    <form class="formulario" onsubmit={entrar} novalidate>
      <label class="etiqueta" for="correo">CORREO</label>
      <div class="caja">
        <span class="icono"><Icono nombre="correo" tamano={16} /></span>
        <input
          id="correo"
          type="email"
          autocomplete="username"
          bind:value={correo}
          oninput={quitarMensaje}
        />
      </div>

      <label class="etiqueta separada" for="contrasena">CONTRASEÑA</label>
      <div class="caja con-ojo">
        <span class="icono"><Icono nombre="candado" tamano={16} /></span>
        <input
          id="contrasena"
          type={verContrasena ? 'text' : 'password'}
          autocomplete="current-password"
          placeholder="Tu contraseña"
          bind:value={contrasena}
          oninput={quitarMensaje}
        />
        <button
          type="button"
          class="ojo"
          title={verContrasena ? 'Ocultar contraseña' : 'Mostrar contraseña'}
          aria-label={verContrasena ? 'Ocultar contraseña' : 'Mostrar contraseña'}
          onclick={() => (verContrasena = !verContrasena)}
        >
          <Icono nombre={verContrasena ? 'oculto' : 'ojo'} tamano={16} />
        </button>
      </div>

      <div class="boton">
        <Boton
          tipo="submit"
          tono="tinta"
          tamano="grande"
          icono="entrar"
          etiqueta={entrando ? 'Entrando…' : 'Entrar al panel'}
          apagado={entrando}
        />
      </div>

      {#if mensaje}
        <div class="mensaje">
          <CajaError mensaje={mensaje.mensaje} tipo={mensaje.tipo} tamano={13} />
        </div>
      {/if}
    </form>
  </section>

  <Manchas />
</main>

<style>
  /* Las dos mitades, 94 a 106, con 12 de aire alrededor y entre ellas. */
  .pantalla {
    height: 100vh;
    height: 100dvh;
    padding: 12px;
    display: grid;
    grid-template-columns: 94fr 106fr;
    gap: 12px;
    background: var(--suelo);
  }

  /* Todo a 48 del borde de su mitad y 56 arriba, como la frase de las manchas. */
  .tarjeta {
    min-width: 0;
    overflow: auto;
    padding: 55px 47px 47px;
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
  }

  .sub {
    margin: 14px 0 0;
    font-size: 16px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--suave);
  }

  .formulario {
    margin-top: 40px;
    display: flex;
    flex-direction: column;
  }

  .formulario .etiqueta {
    margin-bottom: 8px;
  }

  .formulario .separada {
    margin-top: 14px;
  }

  /* Un campo del login: caja de 48 con borde fino (más marcado mientras se escribe), radio 12,
     el icono a la izquierda y, en la contraseña, el ojo a la derecha. */
  .caja {
    height: 48px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 14px;
    border: 1px solid var(--linea);
    border-radius: 12px;
  }

  .caja.con-ojo {
    padding-right: 6px;
  }

  .caja:focus-within {
    border-color: var(--suave);
  }

  .icono {
    color: var(--suave);
  }

  .caja input {
    flex: 1;
    min-width: 0;
    height: 100%;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--texto);
    font-size: 14px;
    font-weight: 500;
  }

  .caja input::placeholder {
    color: var(--tenue);
  }

  .ojo {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 0;
    border-radius: 10px;
    background: transparent;
    color: var(--suave);
  }

  .ojo:hover {
    background: var(--chip);
  }

  .boton {
    margin-top: 20px;
    display: flex;
  }

  .mensaje {
    margin-top: 14px;
  }
</style>
