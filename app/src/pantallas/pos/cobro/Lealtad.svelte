<!--
  La fila «Tarjeta de lealtad» del cobro a lo ancho (maqueta v22, pantalla «Cobro»): «Escanear» (la cámara, Camara.svelte;
  «Escribir su código» si no hay cámara) y «Escribir número». Ligada, su nombre con lo que lleva y lo que esta cuenta le
  suma, con «Quitar»; con el premio listo y su QR (o su código), «Canjear premio»; con solo su número, «Para canjearlo,
  escanea su QR». Ya canjeado, lo que pasó (el producto entró en $0 y va a la cocina, o se restó de la cuenta). Solo sale
  con la tarjeta prendida y en una cuenta abierta. Postgres hace todo (ligar_tarjeta, canjear_premio, quitar_tarjeta):
  aquí solo se cuenta lo que le suma, como lo cuenta Postgres al cerrar la cuenta.
-->
<script lang="ts">
  import type { SupabaseClient } from '@supabase/supabase-js';
  import { onMount } from 'svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { dinero } from '../../../lib/formato';
  import {
    canjearPremio,
    conRegla,
    cuantos,
    diezDigitos,
    leerLealtad,
    nombreDelPremio,
    ligarTarjeta,
    limpiarCodigo,
    quitarTarjeta,
    tarjetaDeLaCuenta,
    type ConQue,
    type Lealtad,
    type TarjetaDeLaCuenta,
    juntado,
  } from '../../../lib/lealtad';
  import Camara from './Camara.svelte';

  let {
    cliente,
    restauranteId,
    ventaId,
    total,
  }: {
    cliente: SupabaseClient;
    restauranteId: string;
    ventaId: number;
    total: number | null; // lo que vale la cuenta (sin propina), para decir lo que le suma
  } = $props();

  type Modo = 'nada' | 'camara' | 'codigo' | 'numero';
  let regla = $state<Lealtad | null>(null);
  let premioNombre = $state('su producto');
  let modo = $state<Modo>('nada');
  let tarjeta = $state<TarjetaDeLaCuenta | null>(null);
  // Con qué llegó: el QR o su código dejan canjear; su número no.
  let credencial = $state<{ llave: string } | { codigo: string } | null>(null);
  let codigo = $state('');
  let telefono = $state('');
  let ocupado = $state(false);
  let error = $state<string | null>(null);
  let aviso = $state<string | null>(null);
  let entra = $state(false);
  const id = $props.id();

  onMount(async () => {
    try {
      const [l, t] = await Promise.all([leerLealtad(cliente, restauranteId), tarjetaDeLaCuenta(cliente, ventaId)]);
      regla = l;
      tarjeta = t;
      if (l.premio_tipo === 'producto' && l.premio_producto_id !== null)
        premioNombre = (await nombreDelPremio(cliente, restauranteId, l.premio_producto_id)) ?? premioNombre;
    } catch (falla) {
      error = falla instanceof Error ? falla.message : 'No se pudo leer la tarjeta de lealtad.';
    }
  });

  const prendida = $derived(!!regla && regla.prendida && conRegla(regla));
  const premioCorto = $derived(regla?.premio_tipo === 'producto' ? `${premioNombre} gratis` : `${dinero(regla?.premio_pesos ?? 0)} de descuento`);
  // Lo que le suma esta cuenta (como privado de Postgres al cerrarla): con sellos, uno si llega al mínimo; con puntos,
  // los pesos entre lo que vale un punto. Una cuenta de $0 no suma.
  const suma = $derived.by(() => {
    if (!regla || total === null || total <= 0) return 0;
    if (regla.forma === 'sellos') return total >= (regla.minimo ?? 0) ? 1 : 0;
    return Math.floor(total / (regla.pesos_por_punto ?? Infinity));
  });
  const estadoPremio = $derived.by((): 'listo' | 'numero' | 'canjeado' | null => {
    if (!tarjeta) return null;
    if (tarjeta.premio_en_cuenta) return 'canjeado';
    if (!tarjeta.premio_listo) return null;
    return credencial ? 'listo' : 'numero';
  });

  function ir(m: Modo) {
    modo = m;
    error = null;
    aviso = null;
  }

  async function ligar(con: ConQue) {
    if (ocupado) return;
    ocupado = true;
    error = null;
    try {
      const r = await ligarTarjeta(cliente, ventaId, con);
      tarjeta = { id: r.id, nombre: r.nombre, saldo: r.saldo, premio_listo: r.premio_listo, premio_en_cuenta: tarjeta?.id === r.id && tarjeta.premio_en_cuenta };
      credencial = r.con_qr ? ('llave' in con ? { llave: con.llave } : 'codigo' in con ? { codigo: con.codigo } : null) : null;
      modo = 'nada';
      codigo = '';
      telefono = '';
      entra = true;
    } catch (falla) {
      error = falla instanceof Error ? falla.message : 'No se pudo poner la tarjeta.';
      // Lo que leyó la cámara no era de aquí: que escriba su código.
      if (modo === 'camara') modo = 'codigo';
    }
    ocupado = false;
  }

  async function quitar() {
    if (ocupado) return;
    ocupado = true;
    error = null;
    try {
      await quitarTarjeta(cliente, ventaId);
      tarjeta = null;
      credencial = null;
    } catch (falla) {
      error = falla instanceof Error ? falla.message : 'No se pudo quitar la tarjeta.';
    }
    ocupado = false;
  }

  // La clave del canje se queda mientras no salga: pulsar dos veces canjea una vez.
  let clave = crypto.randomUUID();
  async function canjear() {
    if (ocupado || !credencial || !tarjeta) return;
    ocupado = true;
    error = null;
    try {
      const r = await canjearPremio(cliente, ventaId, clave, credencial);
      tarjeta = { ...r, premio_en_cuenta: true };
      clave = crypto.randomUUID();
    } catch (falla) {
      error = falla instanceof Error ? falla.message : 'No se pudo canjear el premio.';
    }
    ocupado = false;
  }

  // El código de abajo del QR (8 letras y números): se pone solo al completarlo.
  $effect(() => {
    const c = limpiarCodigo(codigo);
    if (modo === 'codigo' && c.length === 8) void ligar({ codigo: c });
  });
  // Su número: se pone solo al tener 10 dígitos.
  $effect(() => {
    const t = diezDigitos(telefono);
    if (modo === 'numero' && t) void ligar({ telefono: t });
  });
</script>

{#if prendida}
<div class="seccion">
  <div class="encabezado">
    <span class="cuadro-c"><Icono nombre="r-lealtad" tamano={18} /></span>
    <div class="titulos"><span class="titulo">Tarjeta de lealtad</span></div>
  </div>

  {#if error}<CajaError mensaje={error} compacta />{/if}

  {#if tarjeta && modo === 'nada'}
    <div class="ligada" class:entra>
      <span class="inicial">{tarjeta.nombre.charAt(0).toUpperCase()}</span>
      <span class="enc-t">
        <b>{tarjeta.nombre}</b>
        <span
          >{juntado(regla!.forma, tarjeta.saldo, regla!.meta ?? 0).toLocaleString('en-US')} de {cuantos(regla!.forma, regla!.meta ?? 0)}{#if !tarjeta.premio_en_cuenta && suma > 0}&nbsp;· esta cuenta
            le suma {suma.toLocaleString('en-US')}{/if}</span
        >
      </span>
      {#if !tarjeta.premio_en_cuenta}<button type="button" class="liga" disabled={ocupado} onclick={quitar}>Quitar</button>{/if}
    </div>
    {#if estadoPremio === 'listo'}
      <div class="premio entra">
        <span class="premio-i"><Icono nombre="regalo" tamano={18} /></span>
        <span class="enc-t"><b>Premio listo</b><span>{premioCorto}</span></span>
        <button type="button" class="canjear" disabled={ocupado} onclick={canjear}>Canjear premio</button>
      </div>
    {:else if estadoPremio === 'numero'}
      <div class="premio entra">
        <span class="premio-i"><Icono nombre="regalo" tamano={18} /></span>
        <span class="enc-t"><b>Tiene su premio listo</b><span>Para canjearlo, escanea su QR.</span></span>
        <button type="button" class="liga fuerte" onclick={() => ir('camara')}>Escanear</button>
      </div>
    {:else if estadoPremio === 'canjeado'}
      <div class="premio entra">
        <span class="premio-i"><Icono nombre="check" tamano={18} /></span>
        <span class="enc-t"
          ><b>Premio canjeado</b><span
            >{regla?.premio_tipo === 'producto'
              ? `${premioNombre} entró a la cuenta en $0 y va a la cocina.`
              : `Se restaron ${dinero(regla?.premio_pesos ?? 0)} de la cuenta.`}</span
          ></span
        >
      </div>
    {/if}
  {:else if modo === 'nada'}
    <div class="dos">
      <button type="button" class="c-boton" onclick={() => ir('camara')}><Icono nombre="escanear" tamano={18} />Escanear</button>
      <button type="button" class="c-boton" onclick={() => ir('numero')}><Icono nombre="teclado" tamano={18} />Escribir número</button>
    </div>
  {:else if modo === 'camara'}
    <Camara
      alLeer={(t) => void ligar({ llave: t })}
      alFallar={(m) => {
        aviso = m;
        modo = 'codigo';
      }}
    />
    <div class="c-pie">
      <button type="button" class="liga" onclick={() => ir('codigo')}>Escribir su código</button>
      <button type="button" class="liga" onclick={() => ir('nada')}>Cancelar</button>
    </div>
  {:else if modo === 'codigo'}
    {#if aviso}<p class="c-nota">{aviso}</p>{/if}
    <GrupoCampos>
      <Campo id="{id}-codigo" etiqueta="CÓDIGO DE SU TARJETA" bind:valor={codigo} placeholder="8 letras y números, abajo de su QR" largoMaximo={10} corrector={false} mono />
    </GrupoCampos>
    <div class="c-pie">
      <button type="button" class="liga" onclick={() => ir('camara')}>Escanear</button>
      <button type="button" class="liga" onclick={() => ir('nada')}>Cancelar</button>
    </div>
  {:else}
    <GrupoCampos>
      <Campo id="{id}-tel" etiqueta="NÚMERO DE SU TARJETA" bind:valor={telefono} placeholder="Ej. 222 987 6543" tipo="tel" modoTeclado="tel" mono />
    </GrupoCampos>
    <p class="c-nota">Con su número suma; para canjear su premio, escanea su QR.</p>
    <div class="c-pie">
      <button type="button" class="liga" onclick={() => ir('camara')}>Escanear</button>
      <button type="button" class="liga" onclick={() => ir('nada')}>Cancelar</button>
    </div>
  {/if}
</div>
{/if}

<style>
  /* Como las secciones del cobro (Tarjeta.svelte): con su línea arriba. */
  .seccion {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding-top: 20px;
    border-top: 1px solid var(--linea);
  }

  /* La cabeza, como las secciones del cobro a lo ancho (pos/ancho/ancho.css), aquí también para la hoja del celular. */
  .encabezado {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cuadro-c {
    width: 36px;
    height: 36px;
    flex: none;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 11px;
    background: var(--chip);
    color: var(--texto);
  }

  .titulos {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .titulo {
    font-size: 14.5px;
    font-weight: 700;
    overflow-wrap: anywhere;
  }

  .dos {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .c-boton {
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font: 600 13.5px var(--jakarta);
    cursor: pointer;
    transition:
      background-color 0.15s,
      transform 0.15s;
  }

  .c-boton:hover {
    background: var(--chip);
  }

  .c-boton:active {
    transform: scale(0.98);
  }

  .c-pie {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    margin-top: -4px;
  }

  .liga {
    padding: 0;
    border: 0;
    background: none;
    color: var(--suave);
    font: 600 13px var(--jakarta);
    text-decoration: underline;
    text-underline-offset: 2px;
    cursor: pointer;
  }

  .liga.fuerte {
    color: var(--texto);
  }

  .c-nota {
    margin: -6px 2px 0;
    font-size: 12.5px;
    color: var(--suave);
  }

  .ligada {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
  }

  .inicial {
    width: 34px;
    height: 34px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--chip);
    color: var(--texto);
    font-size: 13px;
    font-weight: 700;
  }

  .enc-t {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .enc-t b {
    font-size: 14px;
    font-weight: 700;
    color: var(--texto);
  }

  .enc-t > span {
    font-size: 12.5px;
    color: var(--suave);
  }

  .premio {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: -6px;
    padding: 10px 12px;
    border-radius: 12px;
    background: color-mix(in srgb, var(--verde) 12%, transparent);
  }

  .premio-i {
    width: 32px;
    height: 32px;
    flex: none;
    display: grid;
    place-items: center;
    border-radius: 50%;
    background: var(--verde);
    color: #fff;
  }

  .canjear {
    height: 36px;
    flex: none;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--verde);
    color: #fff;
    font: 700 13px var(--jakarta);
    cursor: pointer;
    transition:
      transform 0.15s,
      filter 0.15s;
  }

  .canjear:hover {
    filter: brightness(1.06);
  }

  .canjear:active {
    transform: scale(0.97);
  }

  @keyframes entra {
    from {
      opacity: 0;
      transform: translateY(-4px);
    }
  }

  .entra {
    animation: entra 0.26s ease-out;
  }

  @media (prefers-reduced-motion: reduce) {
    .entra {
      animation: none;
    }
  }
</style>
