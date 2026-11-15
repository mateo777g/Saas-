// Lo que dice arriba de Pedidos: si se reciben pedidos ahora, en pausa, fuera de horario o sin lo que hace falta (parte 6b).
// En la columna de celular es la franja con su botón; a lo ancho, en el panel, es el chip de la barra de arriba y, si no se
// reciben, una línea gris junto a «POR CONFIRMAR» (encuesta 4 de planes/trabajo/adaptabilidad/pedidos-ancho.md). La
// usan caja/Pedidos.svelte y gerente/Pedidos.svelte.
import { enZona } from '../../../lib/formato';
import type { Horario, PedidosDelDia } from '../../../lib/pedidos.svelte';

export type Franja = {
  tono: 'vivo' | 'pausa' | 'apagado';
  titulo: string; // «Pedidos en pausa»
  sub: string; // «Desde las 14:05 · tus clientes ven «Por ahora no recibimos pedidos»»
  chip: string; // «En pausa desde las 14:05»
  nota: string | null; // la línea gris de a lo ancho: «Tus clientes ven «Por ahora no recibimos pedidos»»
};

// «a la 1:00», como el menú en línea.
export const alas = (h: string) => (/^1:/.test(h) ? `a la ${h}` : `a las ${h}`);
const DIAS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

function abre(e: Exclude<Horario, null | { abierto: true }>): string {
  const { dia, hora: h, en_dias } = e.abre;
  return `Abres ${en_dias === 0 ? 'hoy' : en_dias === 1 ? 'mañana' : `el ${DIAS[dia - 1]}`} ${alas(h)}`;
}

export function franjaDe(datos: PedidosDelDia, zona: string, enPanel: boolean): Franja {
  const hora = (momento: string) => enZona(momento, zona).hora;
  const ven = 'tus clientes ven «Por ahora no recibimos pedidos»';
  const Ven = 'Tus clientes ven «Por ahora no recibimos pedidos»';
  if (datos.pausado) {
    const desde = hora(datos.pausado_at ?? datos.ahora);
    return { tono: 'pausa', titulo: 'Pedidos en pausa', sub: `Desde las ${desde} · ${ven}`, chip: `En pausa desde ${alas(desde).slice(2)}`, nota: Ven };
  }
  if (datos.recibe && datos.estado?.abierto) {
    const hasta = alas(datos.estado.cierra).slice(2);
    return { tono: 'vivo', titulo: 'Recibiendo pedidos', sub: `Por WhatsApp, desde tu menú · hasta ${hasta}`, chip: `Recibiendo pedidos hasta ${hasta}`, nota: null };
  }
  if (datos.estado && !datos.estado.abierto) {
    const cuando = abre(datos.estado);
    return { tono: 'apagado', titulo: 'Fuera de horario', sub: `${cuando} · ${ven}`, chip: `Fuera de horario · ${cuando.toLowerCase()}`, nota: Ven };
  }
  const falta = datos.estado === null ? 'tu horario' : 'tu teléfono';
  const donde = enPanel ? `Falta ${falta} en Tu restaurante` : `Falta ${falta}: tu gerente lo pone en Tu restaurante`;
  return { tono: 'apagado', titulo: 'No recibes pedidos', sub: donde, chip: 'No recibes pedidos', nota: donde };
}
