<!--
  El cobro en la tarjeta de 400 a lo ancho (adaptabilidad 3b; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4, pantallas «Cobrar» y
  «Caja»; encuestas 1 a 4 de cobro-caja.md): lo mismo que la hoja del celular (pos/cobro/cobro.svelte.ts), en otra
  forma. Arriba el total grande (lo que falta); si hay descuento o pagos, debajo en el gris del ticket (Subtotal,
  Descuento con «Quitar», cada pago con «Cancelar», Falta), y el botón chico del descuento. Luego, con la cabeza de las
  tarjetas de Crear anuncios: «¿Cómo paga?» (como los roles de Empleados), «¿Con cuánto paga?» en efectivo (Exacto y los
  billetes en cuadros con el aro azul, «Otro monto» en su gris y el cambio en verde o «No alcanza» en rojo, que guarda su
  lugar mientras no hay monto) o, con tarjeta o transferencia, cuánto cobrar y la referencia; «Propina» en cuadros y
  «¿Paga todo?» con «Otra cantidad» en su gris. «Anotar pago» va en la barra de abajo (pos/cobro/Abajo.svelte). Mientras
  llega el primer resumen, lo que lo espera sale en esqueleto. El punto de venta nunca cobra: aquí se anota cómo pagó.

  Con la terminal conectada (maqueta 8aJ1RUKVd2xA5kgawVpDkQ v2, «Caja a lo ancho»): con Tarjeta, «En la terminal» dice a
  qué Point va; mientras el cobro espera, la tarjeta enseña la Point con sus ondas, el monto grande, los segundos y lo
  que lleva (la cuenta y la propina); si Mercado Pago no sabe, «Revisa la terminal». Arriba, la nota roja o ámbar de lo
  que no salió. Los botones (Mandar, La cobré a mano, Revisar, Cancelar cobro, Sí / No se pagó) van en la barra.
-->
<script lang="ts">
  import Boton from '../../../diseno/Boton.svelte';
  import CajaError from '../../../diseno/CajaError.svelte';
  import Campo from '../../../diseno/Campo.svelte';
  import Esqueleto from '../../../diseno/Esqueleto.svelte';
  import GrupoCampos from '../../../diseno/GrupoCampos.svelte';
  import Icono from '../../../diseno/Icono.svelte';
  import { NOMBRE_METODO, type Metodo, type Pago } from '../../../lib/caja';
  import { enZona, pesos } from '../../../lib/formato';
  import type { Cobro, ElegidaPropina } from './cobro.svelte';

  let { cobro, titulo }: { cobro: Cobro; titulo: string } = $props(); // titulo: «#24 · Comer aquí»

  const c = $derived(cobro);
  const r = $derived(c.resumen);
  const id = $props.id();

  const METODOS: Metodo[] = ['efectivo', 'tarjeta', 'transferencia'];
  const PROPINAS: ElegidaPropina[] = ['no', '10', '15', 'otra'];
  const PARTES = [1, 2, 3, 4];

  const quien = (p: Pago) => (p.cobrado_por === null ? 'En línea' : (c.e.nombres.get(p.cobrado_por) ?? '—'));
  const hora = (momento: string) => enZona(momento, c.e.zona).hora;
  const conPagos = $derived(c.pagos.length > 0);

  // Lo que dice la caja del cambio; sin monto todavía, guarda su lugar sin verse.
  const cajaCambio = $derived.by<{ no: boolean; monto: number } | null>(() => {
    const v = c.cambioVisto;
    return v === null ? null : { no: v < 0, monto: Math.abs(v) };
  });
  const recibidoMal = $derived(c.recibido.tipo === 'texto' && c.recibido.texto.trim() !== '' && c.recibidoPedido === null);

  // Lo que dice cada motivo de «No se cobró» («cancelada» es la de quien lo mandó y regresa a elegir, sin nota).
  const MOTIVOS: Record<string, string> = {
    rechazada: 'La tarjeta fue rechazada. Pide otra tarjeta o elige otra forma de pago.',
    vencida: 'Pasaron 5 minutos y nadie pagó en la terminal.',
    cancelada_terminal: 'Se canceló en la terminal.',
    sin_conexion: 'No se pudo mandar a la terminal. Cóbrala a mano.',
  };

  // Un error al anotar sale arriba: la tarjeta sube para que se vea.
  let arriba = $state<HTMLDivElement>();
  $effect(() => {
    if (c.error) arriba?.scrollIntoView({ block: 'nearest' });
  });
</script>

{#snippet cabeza(icono: string, texto: string, sub?: string)}
  <div class="encabezado">
    <span class="cuadro-c"><Icono nombre={icono} tamano={18} /></span>
    <div class="titulos"><span class="titulo">{texto}</span>{#if sub}<span class="t-sub">{sub}</span>{/if}</div>
  </div>
{/snippet}

{#snippet senal(ambar: boolean)}
  <div class="t-senal" class:ambar aria-hidden="true">
    <span class="t-onda"></span><span class="t-onda dos"></span>
    <span class="t-centro"><Icono nombre={ambar ? 'alerta' : 'tarjeta'} tamano={22} /></span>
  </div>
{/snippet}

{#snippet lleva(monto: number, propina: number)}
  <div class="ya">
    <div class="f"><span>{titulo}</span><b>{pesos(monto - propina)}</b></div>
    {#if propina > 0}<div class="f"><span>Propina</span><b>{pesos(propina)}</b></div>{/if}
  </div>
{/snippet}

{#if c.fase === 'esperando' && c.cobroT}
  {@const t = c.cobroT}
  <div class="t-espera-ancho t-entra">
    <div class="t-espera ancha">
      {@render senal(false)}
      <span class="t-espera-tit">Esperando en la terminal</span>
      <b class="t-espera-monto">{pesos(t.monto)}</b>
      <span class="t-espera-linea">{c.vigia?.point ?? 'Point'}</span>
      <span class="t-seg">{c.segundos} s</span>
    </div>
    {@render lleva(t.monto, t.propina)}
    {#if c.aviso5}
      <p class="t-aviso5" role="status">
        <Icono nombre="alerta" tamano={16} /><span><b>La terminal no lo ha recibido:</b> abre «Cobros vinculados» en la Point.</span>
      </p>
    {/if}
    {#if c.error}<CajaError tipo={c.error.startsWith('Sin conexión') ? 'sinred' : 'alerta'} mensaje={c.error} />{/if}
    <p class="t-pista">Puedes cobrar otra cuenta: esta se cierra sola cuando paguen.</p>
  </div>
{:else if c.fase === 'revisa' && c.cobroT}
  {@const t = c.cobroT}
  <div class="t-espera-ancho t-entra">
    <div class="t-espera ancha">
      {@render senal(true)}
      <span class="t-espera-tit">Revisa la terminal</span>
      <b class="t-espera-monto">{pesos(t.monto)}</b>
      <span class="t-espera-linea">{c.vigia?.point ?? 'Point'}</span>
    </div>
    <p class="t-nota ambar" role="alert">
      <Icono nombre="alerta" tamano={16} /><span><b>Mercado Pago no sabe si se pagó.</b> Mira la Point: ¿salió el comprobante? Lo resuelve quien lo mandó.</span>
    </p>
    {#if c.error}<CajaError mensaje={c.error} />{/if}
    {@render lleva(t.monto, t.propina)}
    <p class="t-pista">Lo que elijas queda en la bitácora, y el corte lo compara con el cierre de la terminal.</p>
  </div>
{:else}
<div class="cobro" bind:this={arriba}>
  {#if c.notaTerminal}
    {@const nota = c.notaTerminal}
    {#if nota.tipo === 'no-cobro'}
      <div class="t-nota roja t-entra" role="alert">
        <Icono nombre="alerta" tamano={16} /><span><b>No se cobró.</b> {MOTIVOS[nota.motivo] ?? ''}</span>
      </div>
    {:else if nota.tipo === 'ocupada'}
      <div class="t-nota ambar t-entra" role="alert">
        <Icono nombre="alerta" tamano={16} /><span><b>La terminal está atendiendo otro cobro.</b> Cuando termine, vuelve a mandarlo.</span>
      </div>
    {:else}
      <div class="t-nota ambar t-entra" role="alert">
        <Icono nombre="alerta" tamano={16} /><span><b>La terminal tiene algo pendiente: revisa el papel.</b> Lo pendiente sale solo cuando la Point tiene papel y está en «Cobros vinculados».</span>
      </div>
    {/if}
  {/if}
  {#if !c.turnoAbierto}
    <CajaError mensaje="La caja no está abierta. Pídele a quien está en caja que la abra para anotar pagos." />
  {/if}
  {#if c.yaNoAbierta}
    <CajaError tipo="info" mensaje="Esta cuenta ya no está abierta: se cobró o se juntó en otro aparato." />
  {/if}
  {#if c.error}<CajaError tipo={c.error.startsWith('Sin conexión') ? 'sinred' : 'alerta'} mensaje={c.error} />{/if}
  {#if c.errorResumen}
    <CajaError tipo={c.errorResumen.sinRed ? 'sinred' : 'alerta'} mensaje={c.errorResumen.texto} />
    {#if !r}<div class="otra-vez"><Boton etiqueta="Intentar de nuevo" icono="actualizar" onclick={() => c.reintentar()} /></div>{/if}
  {/if}

  <!-- El total grande: lo que falta. -->
  <div class="grande">
    {#if r}
      <span>Cobrar {titulo}</span>
      <b>{pesos(r.falta)}</b>
    {:else if !c.errorResumen}
      <span class="solo-lector" role="status">Leyendo la cuenta…</span>
      <Esqueleto ancho="150px" alto="13px" />
      <Esqueleto ancho="172px" alto="44px" redondo="8px" />
    {/if}
  </div>

  {#if r && (c.descuento || conPagos)}
    <div class="ya">
      {#if c.descuento && c.cuenta}
        <div class="f"><span>Subtotal</span><b>{pesos(c.cuenta.subtotal)}</b></div>
        <div class="f con-boton">
          <span class="desc">Descuento {c.descuento.texto}{c.descuento.motivo ? ` · «${c.descuento.motivo}»` : ''}</span>
          <b class="desc">−{pesos(c.descuento.monto)}</b>
          <Boton etiqueta="Quitar" tono="peligro" tamano="chico" apagado={c.ocupado} onclick={() => c.quitarDescuento()} />
        </div>
        <div class="f"><span>Total</span><b>{pesos(r.total)}</b></div>
      {/if}
      {#each c.pagos as p (p.id)}
        <div class="f" class:con-boton={c.seCancela(p)} class:cancelado={!!p.cancelado_at}>
          <span>
            {NOMBRE_METODO[p.metodo]} · {p.cancelado_at ? `cancelado · «${p.cancelado_motivo}»` : `${quien(p)} · ${hora(p.created_at)}`}{p.propina && !p.cancelado_at ? ` · propina ${pesos(p.propina)}` : ''}
          </span>
          <b>{pesos(p.monto)}</b>
          {#if c.seCancela(p)}<Boton etiqueta="Cancelar" tono="peligro" tamano="chico" onclick={() => c.abrirCancelarPago(p)} />{/if}
        </div>
      {/each}
      {#if conPagos}<div class="f fuerte"><span>Falta</span><b>{pesos(r.falta)}</b></div>{/if}
    </div>
  {/if}

  {#if r && r.estado === 'abierta' && c.cuenta}
    <div class="boton-desc">
      <Boton
        etiqueta={c.descuento ? 'Cambiar descuento' : 'Descuento a la cuenta'}
        icono="porcentaje"
        tamano="chico"
        apagado={c.ocupado}
        onclick={() => c.abrirDescuento()}
      />
    </div>
  {/if}

  {#if c.enCero}
    <p class="pista">Esta cuenta es de {pesos(0)}: se cierra sin anotar ningún pago.</p>
  {:else if !c.yaNoAbierta && (r || !c.errorResumen)}
    <div class="seccion">
      {@render cabeza('billete', '¿Cómo paga?')}
      <div class="elige" role="group" aria-label="Cómo paga">
        {#each METODOS as m (m)}
          <button type="button" class="elige-op" aria-pressed={c.metodo === m} onclick={() => c.elegirMetodo(m)}>{NOMBRE_METODO[m]}</button>
        {/each}
      </div>
    </div>

    {#if c.metodo === 'efectivo'}
      <div class="seccion">
        {@render cabeza('cambiar', '¿Con cuánto paga?')}
        {#if r && r.cabe && c.propinaPedida !== 'mal'}
          <div class="sugeridos" role="group" aria-label="Con cuánto paga" style:--columnas={c.sugeridos.length + 1}>
            <button type="button" class="sug" aria-pressed={c.recibido.tipo === 'exacto'} onclick={() => c.elegirRecibido({ tipo: 'exacto' })}>
              <b>{pesos(r.cobrar)}</b><span>Exacto</span>
            </button>
            {#each c.sugeridos as b (b)}
              <button
                type="button"
                class="sug"
                aria-pressed={c.recibido.tipo === 'billete' && c.recibido.n === b}
                onclick={() => c.elegirRecibido({ tipo: 'billete', n: b })}
              >
                <b>${b}</b><span>Billete</span>
              </button>
            {/each}
          </div>
        {:else if !r}
          <div class="sugeridos" aria-hidden="true" style:--columnas="4">
            {#each [0, 1, 2, 3] as i (i)}<Esqueleto alto="52px" redondo="12px" />{/each}
          </div>
        {/if}
        <GrupoCampos>
          <Campo
            id="{id}-recibido"
            etiqueta="OTRO MONTO"
            placeholder="Ej. $500.00"
            modoTeclado="decimal"
            mal={recibidoMal}
            pista={recibidoMal ? 'Escribe el billete en pesos, como «500».' : undefined}
            bind:valor={
              () => (c.recibido.tipo === 'texto' ? c.recibido.texto : ''),
              (v) => c.elegirRecibido(v.trim() ? { tipo: 'texto', texto: v } : { tipo: 'nada' })
            }
          />
        </GrupoCampos>
        {#if r}
          <div class="cambio" class:no={cajaCambio?.no} class:escondido={!cajaCambio} aria-hidden={!cajaCambio} role="status">
            <span>{cajaCambio?.no ? 'No alcanza' : 'Cambio'}</span>
            <b class="mono">{pesos(cajaCambio?.monto ?? 0)}</b>
          </div>
        {:else}
          <Esqueleto alto="52px" redondo="12px" />
        {/if}
      </div>
    {:else}
      <div class="seccion">
        {@render cabeza(
          c.metodo === 'tarjeta' ? 'tarjeta' : 'banco',
          c.metodo === 'tarjeta' ? 'En la terminal' : 'La transferencia',
          c.conTerminal ? (c.vigia?.point ?? undefined) : undefined,
        )}
        <div class="cobra-en">
          <span>{c.metodo === 'tarjeta' ? 'Cobra en la terminal' : 'Debe llegar'}</span>
          {#if r}<b class="mono">{pesos(r.cabe ? r.cobrar : 0)}</b>{:else}<Esqueleto ancho="90px" alto="20px" />{/if}
        </div>
        <GrupoCampos>
          <Campo
            id="{id}-ref"
            etiqueta="REFERENCIA · OPCIONAL"
            placeholder={c.metodo === 'tarjeta' ? 'Últimos dígitos del voucher' : 'Folio de la transferencia'}
            largoMaximo={60}
            bind:valor={() => c.referencia, (v) => c.escribirReferencia(v)}
          />
        </GrupoCampos>
      </div>
    {/if}

    <div class="seccion">
      {@render cabeza('propina', 'Propina')}
      <div class="sugeridos" role="group" aria-label="Propina" style:--columnas="4">
        {#each PROPINAS as p (p)}
          <button type="button" class="sug" aria-pressed={c.propina === p} onclick={() => c.elegirPropina(p)}>
            <b>{p === 'no' ? 'Sin' : p === 'otra' ? 'Otra' : `${p} %`}</b>
            {#if p === 'no'}
              <span>Propina</span>
            {:else if p === 'otra'}
              <span>Tú escribes</span>
            {:else if r}
              <span>{pesos(p === '10' ? r.propina_10 : r.propina_15)}</span>
            {:else}
              <Esqueleto ancho="40px" alto="10px" />
            {/if}
          </button>
        {/each}
      </div>
      {#if c.propina === 'otra'}
        <GrupoCampos>
          <Campo
            id="{id}-propina"
            etiqueta="OTRA PROPINA"
            placeholder="Ej. $20.00"
            modoTeclado="decimal"
            mal={c.propinaPedida === 'mal'}
            pista={c.propinaPedida === 'mal' ? 'Escribe la propina en pesos, como «20».' : undefined}
            bind:valor={() => c.otraTexto, (v) => c.escribirOtra(v)}
          />
        </GrupoCampos>
      {/if}
    </div>

    <div class="seccion">
      {@render cabeza('usuarios', '¿Paga todo?')}
      <div class="elige" role="group" aria-label="Paga todo">
        {#each PARTES as n (n)}
          <button type="button" class="elige-op" aria-pressed={c.montoAuto && c.partes === n} onclick={() => c.elegirPartes(n)}>
            {n === 1 ? 'Todo' : `Entre ${n}`}
          </button>
        {/each}
      </div>
      <GrupoCampos>
        <Campo
          id="{id}-monto"
          etiqueta="OTRA CANTIDAD"
          placeholder="Ej. $50.00"
          modoTeclado="decimal"
          mal={c.montoMal}
          pista={c.montoMal && r
            ? c.montoPedido === null
              ? 'Escribe el monto en pesos, como «150» o «148.50».'
              : `No puede pasar de lo que falta (${pesos(r.falta)}).`
            : c.montoAuto && c.partes > 1 && r
              ? `Pago ${c.hechas + 1} de ${c.partes}.${r.partes.length > 1 ? ` Los demás: ${r.partes.slice(1).map(pesos).join(', ')}.` : ''}`
              : undefined}
          bind:valor={() => (c.montoAuto ? '' : c.montoTexto), (v) => c.escribirMonto(v)}
        />
      </GrupoCampos>
    </div>
  {/if}
</div>
{/if}

<style>
  /* Medidas de la maqueta (planes/trabajo/adaptabilidad/maqueta/estilos.css: .cobro, .grande, .seccion-c, .sugeridos,
     .sug, .cambio). */
  .cobro {
    display: flex;
    flex-direction: column;
    gap: 22px;
  }

  .grande {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 6px 0 2px;
  }

  .grande span:not(.solo-lector) {
    font-size: 12.5px;
    color: var(--suave);
    font-weight: 600;
  }

  .grande b {
    font-family: var(--mono);
    font-size: 40px;
    font-weight: 600;
    letter-spacing: -1.5px;
  }

  .otra-vez {
    display: flex;
    justify-content: center;
  }

  .boton-desc {
    display: flex;
    justify-content: center;
    margin-top: -8px;
  }

  /* Lo que ya tiene la cuenta, en el gris del ticket */
  .ya {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 14px 16px;
    border-radius: 12px;
    background: var(--fondo);
  }

  .f {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
    gap: 12px;
    min-height: 20px;
    font-size: 13px;
  }

  .f.con-boton {
    grid-template-columns: minmax(0, 1fr) auto auto;
  }

  .f span {
    color: var(--suave);
    font-weight: 600;
    line-height: 1.4;
  }

  .f b {
    font-family: var(--mono);
    font-weight: 500;
    white-space: nowrap;
  }

  .f .desc {
    color: var(--verde);
  }

  .f.fuerte span {
    color: var(--texto);
  }

  .f.fuerte b {
    font-weight: 700;
  }

  .f.cancelado span,
  .f.cancelado b {
    color: var(--tenue);
    text-decoration: line-through;
  }

  .seccion {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding-top: 20px;
    border-top: 1px solid var(--linea);
  }

  /* Los montos, como los cuadros que se eligen: con el aro azul */
  .sugeridos {
    display: grid;
    grid-template-columns: repeat(var(--columnas, 4), minmax(0, 1fr));
    gap: 8px;
  }

  .sug {
    height: 52px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    border: 1px solid var(--borde-tarjeta);
    border-radius: 12px;
    background: var(--solido);
    color: var(--texto);
    font: inherit;
    cursor: pointer;
    transition:
      transform 0.15s ease,
      box-shadow 0.2s ease,
      border-color 0.2s ease;
  }

  .sug:hover {
    background: var(--chip);
  }

  .sug:active {
    transform: scale(0.97);
  }

  .sug:focus-visible {
    outline: none;
    box-shadow: 0 0 0 2px var(--campo-aro);
  }

  .sug b {
    font-family: var(--mono);
    font-size: 14px;
    font-weight: 600;
  }

  .sug span {
    font-size: 10.5px;
    color: var(--tenue);
    font-weight: 600;
  }

  .sug[aria-pressed='true'] {
    box-shadow: 0 0 0 2px var(--campo-aro);
    border-color: transparent;
  }

  .cambio,
  .cobra-en {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    padding: 12px 16px;
    border-radius: 12px;
    background: color-mix(in srgb, var(--verde) 13%, transparent);
  }

  .cambio span {
    font-size: 13px;
    font-weight: 700;
    color: var(--verde);
  }

  .cambio b {
    font-size: 22px;
    font-weight: 600;
    color: var(--verde);
  }

  .cambio.no {
    background: color-mix(in srgb, var(--rojo) 11%, transparent);
  }

  .cambio.no span,
  .cambio.no b {
    color: var(--rojo);
  }

  .cambio.escondido {
    visibility: hidden;
  }

  /* Con tarjeta o transferencia: cuánto cobrar, en el gris de lo que se lee */
  .cobra-en {
    align-items: center;
    background: var(--fondo);
  }

  .cobra-en span {
    font-size: 13px;
    font-weight: 600;
    color: var(--suave);
  }

  .cobra-en b {
    font-size: 20px;
    font-weight: 600;
  }

  .pista {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.45;
    color: var(--suave);
    text-align: center;
  }
</style>
