<!--
  El pedido ya guardado (maqueta de la 6b, «Falta un paso» y «Enviado»). Primero «Pedido #27 · Falta
  un paso: mándalo por WhatsApp», sin X: el toque en «Enviar por WhatsApp» es el que abre WhatsApp
  (Safari en el iPhone no deja abrirlo después de esperar al Worker). Luego «Pedido #27 enviado · Te
  confirman por WhatsApp», con «Abrir WhatsApp otra vez» por si no lo mandó. Lo que se enseña es lo
  que guardó Postgres, en pesos; en inglés, los nombres que Don Chuy escribió en inglés.
-->
<script lang="ts">
  import { dinero } from '@app/lib/formato';
  import type { Producto } from '../lib/datos';
  import { enlaceWhatsApp, mensajeWhatsApp, type Guardado, type Hecho } from '../lib/pedido';
  import type { Moneda } from '../lib/preferencias';
  import { enSuLengua, type Lengua, type Textos } from '../lib/textos';
  import Hoja from './Hoja.svelte';
  import Icono from './Icono.svelte';

  let {
    pedido,
    ids,
    productos,
    enviado,
    telefono,
    lengua,
    moneda,
    t,
    alEnviar,
    alVolver,
  }: {
    pedido: Guardado;
    ids: Hecho['ids'];
    productos: Map<number, Producto>;
    enviado: boolean;
    telefono: string;
    lengua: Lengua;
    moneda: Moneda;
    t: Textos;
    alEnviar: () => void;
    alVolver: () => void;
  } = $props();

  const pesos = (n: number) => `${moneda === 'usd' ? 'MX' : ''}${dinero(n)}`;
  const enlace = $derived(enlaceWhatsApp(telefono, mensajeWhatsApp(pedido)));

  // Cada renglón como lo guardó Postgres; en inglés, con el inglés del menú si lo tiene.
  const renglones = $derived(
    pedido.renglones.map((r, i) => {
      const p = ids.length === pedido.renglones.length ? productos.get(ids[i].producto_id) : undefined;
      if (!p || lengua === 'es') return { ...r, opciones: r.opciones.map((o) => o.opcion) };
      const elegidas = p.grupos.flatMap((g) => g.opciones).filter((o) => ids[i].opciones.includes(o.id));
      return {
        ...r,
        nombre: enSuLengua(r.nombre, p.nombre_en, lengua),
        opciones: elegidas.length === r.opciones.length ? elegidas.map((o) => enSuLengua(o.nombre, o.nombre_en, lengua)) : r.opciones.map((o) => o.opcion),
      };
    }),
  );
</script>

<Hoja etiqueta={enviado ? t.enviadoN(pedido.numero) : t.falta1} alCerrar={enviado ? alVolver : null} {pie}>
  <div class="listo">
    {#if enviado}
      <span class="circulo ok"><Icono nombre="check" tamano={26} /></span>
      <h3>{t.enviadoN(pedido.numero)}</h3>
      <p>{t.enviadoTexto}</p>
    {:else}
      <span class="circulo"><Icono nombre="mensaje" tamano={28} /></span>
      <span class="chica">{t.falta1}</span>
      <h3>{t.pedidoN(pedido.numero)}</h3>
      <p>{t.faltaTexto}</p>
    {/if}
  </div>
  <div class="resumen">
    {#each renglones as r, i (i)}
      <div class="fila">
        <span>
          <b>{r.cantidad}</b>
          {r.nombre}
          {#if r.opciones.length}<small>{r.opciones.join(' · ')}</small>{/if}
        </span>
        <span>{pesos(r.importe)}</span>
      </div>
    {/each}
    <div class="fila fuerte">
      <span>{t.total}</span>
      <span>{pesos(pedido.total)}{pedido.tipo === 'domicilio' ? t.masEnvio : ''}</span>
    </div>
  </div>
</Hoja>

{#snippet pie()}
  {#if enviado}
    <div class="columna">
      <a class="m-boton contorno" href={enlace} target="_blank" rel="noopener"><Icono nombre="mensaje" tamano={18} />{t.otraVez}</a>
      <button type="button" class="m-boton" onclick={alVolver}>{t.volver}</button>
    </div>
  {:else}
    <a class="m-boton wa" href={enlace} target="_blank" rel="noopener" onclick={alEnviar}><Icono nombre="mensaje" tamano={18} />{t.enviar}</a>
  {/if}
{/snippet}

<style>
  .listo {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 12px 0 2px;
    text-align: center;
  }

  .circulo {
    width: 64px;
    height: 64px;
    border-radius: 32px;
    margin-bottom: 8px;
    background: var(--m-chip);
    color: var(--m-texto);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .circulo.ok {
    background: var(--m-wa);
    color: #ffffff;
  }

  .chica {
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--m-tenue);
  }

  h3 {
    margin: 2px 0 0;
    font-size: 25px;
    font-weight: 800;
    letter-spacing: -0.5px;
  }

  p {
    margin: 0;
    font-size: 14.5px;
    line-height: 1.5;
    color: var(--m-suave);
    max-width: 30ch;
  }

  .resumen {
    margin-top: 20px;
    padding: 2px 14px;
    border-radius: 16px;
    background: var(--m-chip);
  }

  .fila {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    padding: 11px 0;
    border-bottom: 1px solid var(--m-linea);
    font-size: 14px;
  }

  .fila > span:first-child {
    min-width: 0;
  }

  .fila > span:last-child {
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .fila small {
    display: block;
    margin-top: 2px;
    font-size: 12px;
    color: var(--m-suave);
  }

  .fila.fuerte {
    border-bottom: 0;
    font-size: 15.5px;
    font-weight: 800;
  }

  .columna {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .columna .m-boton {
    flex: none;
    width: 100%;
  }
</style>
