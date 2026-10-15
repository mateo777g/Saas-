<!--
  Vincular aparato (maqueta de Empleados 36iXMMqXCfVv4NuVR7vNSc). Primero el nombre del aparato y
  de quién es: compartido (la tableta de la caja o de la cocina) o de una persona del equipo.
  Después, en la misma ventana, el QR y el código de 6 letras que dio Postgres, con lo que le
  queda: dura 10 minutos y sirve una sola vez. Vencido, se apaga y sale «Crear otro código».
  Listo (o la X) cierra la ventana y Empleados vuelve a leer sus aparatos.
-->
<script lang="ts">
  import { onDestroy } from 'svelte';
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Formulario from '../../../diseno/Formulario.svelte';
  import Ventana from '../../../diseno/Ventana.svelte';
  import { crearCodigo, type Aparato, type Persona } from '../../../lib/equipo';
  import { ALGO_SALIO_PANEL, Fallo } from '../../../lib/errores';
  import Qr from './Qr.svelte';

  let {
    restauranteId,
    equipo,
    aparatos,
    alCambiar,
    alCerrar,
  }: {
    restauranteId: string;
    equipo: Persona[]; // quienes pueden tener su propio aparato: el equipo activo, sin los gerentes
    aparatos: Aparato[];
    alCambiar: () => void;
    alCerrar: () => void;
  } = $props();

  let nombre = $state('');
  let de = $state(''); // '' = compartido; si no, el id de la persona
  let paso = $state<null | 'guardando'>(null);
  let codigo = $state<{ codigo: string; expira: string } | null>(null);
  let restan = $state(0);
  let otroCodigo = $state<{ creando: boolean; error: string | null }>({ creando: false, error: null });
  let reloj: ReturnType<typeof setInterval> | undefined;

  const persona = $derived(de ? equipo.find((p) => String(p.id) === de) : undefined);
  const vencido = $derived(codigo !== null && restan <= 0);
  // La dirección que abre el aparato: la de esta misma app (app.fragmentless.com, o el localhost
  // mientras se desarrolla).
  const direccion = `${location.host}/equipo`;

  // Lo que le queda al código, contra la hora en que vence que dio Postgres.
  function contar() {
    if (!codigo) return;
    restan = Math.max(0, Math.ceil((Date.parse(codigo.expira) - Date.now()) / 1000));
    if (restan <= 0) clearInterval(reloj);
  }

  function mostrar(nuevo: { codigo: string; expira: string }) {
    codigo = nuevo;
    clearInterval(reloj);
    contar();
    reloj = setInterval(contar, 1000);
  }

  onDestroy(() => clearInterval(reloj));

  // Con el código a la vista ya se puede cerrar, y la lista se vuelve a leer (el aparato pudo
  // haberse ligado); a medio crear, no.
  function cerrar() {
    if (codigo) {
      alCambiar();
      alCerrar();
    } else if (!paso) {
      alCerrar();
    }
  }

  async function pedir(): Promise<{ codigo: string; expira: string } | { error: string }> {
    try {
      return await crearCodigo(restauranteId, nombre.trim(), persona ? persona.id : null);
    } catch (falla) {
      if (!(falla instanceof Fallo)) console.error('[equipo] no se pudo crear el código:', falla);
      return { error: falla instanceof Fallo ? falla.message : ALGO_SALIO_PANEL };
    }
  }

  async function guardar(): Promise<{ listo: string } | { error: string }> {
    const limpio = nombre.trim();
    const repetido = aparatos.find((a) => a.nombre.toLowerCase() === limpio.toLowerCase());
    if (!limpio) return { error: 'Escribe el nombre del aparato.' };
    if (repetido) return { error: `Ya tienes un aparato que se llama «${repetido.nombre}».` };

    paso = 'guardando';
    const resultado = await pedir();
    paso = null;
    if ('error' in resultado) return resultado;
    mostrar(resultado);
    return { listo: '' };
  }

  async function crearOtro() {
    otroCodigo = { creando: true, error: null };
    const resultado = await pedir();
    if ('error' in resultado) {
      otroCodigo = { creando: false, error: resultado.error };
      return;
    }
    otroCodigo = { creando: false, error: null };
    mostrar(resultado);
  }
</script>

<Ventana
  etiqueta={!codigo && paso === 'guardando' ? 'CREANDO CÓDIGO…' : 'VINCULAR APARATO'}
  titulo={codigo ? nombre.trim() : 'Liga un aparato'}
  ancho={codigo ? 560 : 480}
  alCerrar={cerrar}
>
  {#if !codigo}
    <Formulario
      boton={{ etiqueta: 'Crear código', icono: 'derecha' }}
      {guardar}
      alTerminar={() => {}}
      sinAviso
      espacio={18}
      antesDelBoton={28}
      textoCargando="Creando…"
    >
      <Campo
        id="aparato-nombre"
        etiqueta="NOMBRE DEL APARATO"
        bind:valor={nombre}
        placeholder="Ej. «Tableta caja» o «Celular de Pepe»"
      />
      <div class="campo">
        <label class="etiqueta" for="aparato-de">¿DE QUIÉN ES?</label>
        <select id="aparato-de" bind:value={de}>
          <option value="">Compartido: sale todo el equipo</option>
          {#each equipo as p (p.id)}
            <option value={String(p.id)}>{p.nombre}</option>
          {/each}
        </select>
        <p class="pista">
          Compartido es para la tableta de la caja o de la cocina: cada quien toca su nombre y pone su PIN. Si es el
          celular de alguien, solo esa persona puede entrar.
        </p>
      </div>
    </Formulario>
  {:else}
    <div class="caja-codigo" class:vencido>
      <Qr texto="{location.origin}/equipo?codigo={codigo.codigo}" />
      <div class="textos">
        <span class="etiqueta">CÓDIGO</span>
        <span class="codigo">{codigo.codigo.slice(0, 3)} {codigo.codigo.slice(3)}</span>
        <span class="vence">
          {vencido ? 'Ya venció' : `Vence en ${Math.floor(restan / 60)}:${String(restan % 60).padStart(2, '0')}`}
        </span>
      </div>
    </div>

    <ol class="pasos">
      <li>
        En {#if persona}el celular de <b>{persona.nombre}</b>{:else}la tableta{/if}, abre <b>{direccion}</b>.
      </li>
      <li>Escribe el código, o escanea el QR con la cámara.</li>
      <li>
        Listo: {persona ? `ahí solo podrá entrar ${persona.nombre.split(' ')[0]}.` : 'ahí sale todo tu equipo.'}
      </li>
    </ol>

    {#if otroCodigo.error}
      <div class="error"><CajaError mensaje={otroCodigo.error} /></div>
    {/if}

    <div class="pie">
      {#if vencido}
        <Boton
          etiqueta={otroCodigo.creando ? 'Creando…' : 'Crear otro código'}
          cargando={otroCodigo.creando}
          onclick={crearOtro}
        />
      {/if}
      <span class="crece"></span>
      <Boton tono="tinta" icono="check" etiqueta="Listo" apagado={otroCodigo.creando} onclick={cerrar} />
    </div>
  {/if}
</Ventana>

<style>
  .campo {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  select {
    width: 100%;
    height: 44px;
    padding: 0 10px;
    border: 1px solid var(--linea);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font-size: 13.5px;
    font-weight: 500;
    outline: none;
  }

  select:focus {
    border-color: var(--suave);
  }

  .pista {
    margin: 0;
    font-size: 12px;
    font-weight: 500;
    line-height: 1.45;
    color: var(--tenue);
  }

  .caja-codigo {
    margin-top: 22px;
    padding: 18px;
    display: flex;
    align-items: center;
    gap: 22px;
    border: 1px solid var(--linea);
    border-radius: 18px;
  }

  .vencido {
    opacity: 0.4;
  }

  .textos {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .codigo {
    font-family: var(--mono);
    font-size: 34px;
    font-weight: 500;
    letter-spacing: 0.16em;
    line-height: 1;
  }

  .vence {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--suave);
    font-variant-numeric: tabular-nums;
  }

  .pasos {
    margin: 16px 0 0;
    padding-left: 20px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .pasos li {
    font-size: 13px;
    line-height: 1.5;
    color: var(--suave);
  }

  .pasos b {
    color: var(--texto);
    font-weight: 600;
  }

  .error {
    margin-top: 14px;
  }

  .pie {
    margin-top: 24px;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .crece {
    flex-grow: 1;
  }
</style>
