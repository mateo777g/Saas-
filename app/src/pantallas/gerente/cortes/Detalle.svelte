<!--
  Lo que pasó en una cuenta, en la tarjeta de la derecha de Cortes y reportes (14 nov 2026): un descuento, una cancelación
  u otro cambio (de mesa, juntar mesas, quitar un descuento, la hora de corte), con la forma de la tarjeta de la Caja a lo
  ancho: la cabeza con su cuadrito, el monto en grande al centro (como el cobro) y los datos en su gris con un ícono cada
  uno: la cuenta y su folio, el motivo, quién lo pidió y quién lo autorizó, y la hora. Lo mismo que decía cada renglón de
  la pieza 5, más a la vista. Los montos vienen de Postgres; aquí no se suma nada.
-->
<script lang="ts">
  import Icono from '../../../diseno/Icono.svelte';
  import { enZona, pesos } from '../../../lib/formato';
  import { ICONO_DE_TIPO } from '../../../lib/pos';
  import { cuentaDe, type FilaCortes } from './filas';
  import { quienLoHizo } from './quien';

  let { fila, zona }: { fila: Exclude<FilaCortes, { que: 'turno' }>; zona: string } = $props();

  const hora = (momento: string | null) => (momento ? enZona(momento, zona).hora : '');

  // Lo de abajo del monto y los datos, ya en palabras.
  const datos = $derived.by(() => {
    if (fila.que === 'descuento') {
      const d = fila.descuento;
      return {
        etiqueta: 'Se descontó',
        monto: `−${pesos(d.descuento)}`,
        clase: 'descuento',
        cuenta: { icono: ICONO_DE_TIPO[d.tipo] ?? 'cuenta', texto: [cuentaDe(d), d.folio ? `Folio ${d.folio}` : 'cerrada'].join(' · ') },
        motivo: d.motivo,
        quien: quienLoHizo(d.pidio_id, d.pidio, d.autorizo_id, d.autorizo),
        hora: hora(d.created_at),
      };
    }
    if (fila.que === 'cancelacion') {
      const c = fila.cancelacion;
      const estado = c.que === 'cuenta' || c.estado === 'cancelada' ? 'la cuenta se canceló' : c.estado === 'abierta' ? 'la cuenta sigue abierta' : '';
      return {
        etiqueta: 'Se canceló',
        monto: pesos(c.importe),
        clase: 'cancelacion',
        cuenta: {
          icono: ICONO_DE_TIPO[c.tipo] ?? 'cuenta',
          texto: [cuentaDe(c), c.folio ? `Folio ${c.folio}` : '', estado].filter(Boolean).join(' · '),
        },
        motivo: c.motivo,
        quien: quienLoHizo(c.pidio_id, c.pidio, c.autorizo_id, c.autorizo),
        hora: hora(c.created_at),
      };
    }
    const o = fila.otro;
    return {
      etiqueta: '',
      monto: '',
      clase: '',
      cuenta: o.cuenta ? { icono: 'cuenta', texto: o.cuenta } : null,
      motivo: '',
      quien: o.quien ?? '',
      hora: hora(o.created_at),
    };
  });

  // La frase de cada otro cambio, la misma de la pieza 5.
  function frase(): string {
    if (fila.que !== 'otro') return fila.titulo;
    const o = fila.otro;
    const d = o.detalle as Record<string, string | number | null | undefined>;
    if (o.accion === 'cambiar_mesa') return `Cambió de mesa: de ${d.de} a ${d.a}`;
    if (o.accion === 'juntar_mesas') return `Juntó ${d.de} con ${d.a}`;
    if (o.accion === 'cambiar_hora_corte') return `Cambió la hora de corte de ${d.de}:00 a ${d.a}:00`;
    if (o.accion === 'devuelto_mercado_pago') {
      return `Devuelto desde Mercado Pago · ${pesos(Number(d.monto))}${o.cuenta ? ` de ${o.cuenta}` : ''}${d.folio != null ? ` (folio ${d.folio})` : ''}`;
    }
    const de = d.nombre ? `${d.nombre}${o.cuenta ? ` en ${o.cuenta}` : ''}` : (o.cuenta ?? 'la cuenta');
    return `Quitó el descuento de ${de}`;
  }
</script>

<div class="encabezado">
  <span class="cuadro-c"><Icono nombre={fila.icono} tamano={18} /></span>
  <div class="titulos">
    <span class="titulo">{fila.que === 'otro' ? fila.tipo : fila.titulo}</span>
    <span class="sub">{fila.que === 'otro' ? frase() : fila.tipo}</span>
  </div>
</div>

{#if datos.monto}
  <div class="grande">
    <span class="arriba">{datos.etiqueta}</span>
    <b class={datos.clase}>{datos.monto}</b>
  </div>
{/if}

<div class="datos-c">
  {#if datos.cuenta}
    <span><Icono nombre={datos.cuenta.icono} tamano={14} /><span>{datos.cuenta.texto}</span></span>
  {/if}
  {#if datos.motivo}
    <span><Icono nombre="mensaje" tamano={14} /><span>«{datos.motivo}»</span></span>
  {/if}
  {#if datos.quien}
    <span><Icono nombre="usuarios" tamano={14} /><span>{datos.quien}</span></span>
  {/if}
  {#if datos.hora}
    <span><Icono nombre="reloj" tamano={14} /><span>A las {datos.hora}</span></span>
  {/if}
</div>

<style>
  /* El monto en grande, como el total del cobro de la Caja. */
  .grande {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 6px 0 18px;
    border-bottom: 1px solid var(--linea);
  }

  .arriba {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--suave);
  }

  .grande b {
    font-family: var(--mono);
    font-size: 40px;
    font-weight: 600;
    letter-spacing: -1.5px;
  }

  .grande b.descuento {
    color: var(--verde);
  }
</style>
