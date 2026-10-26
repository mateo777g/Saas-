// Los pedidos del menú en línea en la caja y en el panel (parte 6b, migración pedidos; libreta 6;
// maqueta Pedidos por WhatsApp G2nxGb3xBgiPEYrDb6CgcW). La señora Ramírez pide desde el menú y el
// pedido llega «Por confirmar»; Lupita o Don Chuy lo confirman (se vuelve una cuenta y va a cocina)
// o lo rechazan, y pueden pausar los pedidos el resto del día de negocio. Como lib/pos.ts, cada
// función recibe la conexión y este archivo nunca importa lib/supabase.ts: lo usan el aparato del
// equipo y el panel del gerente. Los precios, el total y el número los pone Postgres.
import type { SupabaseClient } from '@supabase/supabase-js';
import { esDeRed, mensajeDeError, SIN_CONEXION } from './errores';
import { escuchar, FalloPos, type OpcionElegida } from './pos';
import { avisarLista, avisarPedido, prepararSonido } from './sonido';

function fallo(contexto: string, error: unknown): FalloPos {
  console.error(`[pedidos] ${contexto}:`, error);
  const sinRed = esDeRed(error);
  return new FalloPos(sinRed ? SIN_CONEXION : mensajeDeError(error), sinRed);
}

export type RenglonPedido = {
  nombre: string;
  cantidad: number;
  precio_unitario: number;
  importe: number;
  opciones: OpcionElegida[];
  nota: string | null;
};

export type PorConfirmar = {
  id: number;
  numero: number;
  tipo: 'para_llevar' | 'domicilio';
  cliente_nombre: string;
  cliente_telefono: string | null;
  cliente_direccion: string | null;
  cliente_referencias: string | null;
  paga_con: number | null;
  total: number;
  created_at: string;
  renglones: RenglonPedido[];
};

export type Atendido = {
  id: number;
  numero: number;
  tipo: 'para_llevar' | 'domicilio';
  cliente_nombre: string;
  total: number;
  estado: 'confirmado' | 'rechazado';
  venta_id: number | null;
  atendido_por: string | null; // su nombre; el cierre del día no tiene quién
  atendido_at: string;
  rechazo_motivo: string | null;
};

// El horario de ahora, como lo cuenta privado.horario_ahora: null = sin horario.
export type Horario =
  | { abierto: true; cierra: string }
  | { abierto: false; abre: { dia: number; hora: string; en_dias: number } }
  | null;

export type PedidosDelDia = {
  ahora: string; // la hora de Postgres, para «hace 3 min» sin el reloj del aparato
  pausado: boolean;
  pausado_at: string | null;
  recibe: boolean;
  estado: Horario;
  por_confirmar: PorConfirmar[];
  atendidos: Atendido[];
};

export async function leerPedidos(cliente: SupabaseClient, restauranteId: string): Promise<PedidosDelDia> {
  const { data, error } = await cliente.rpc('pedidos_del_dia', { p_restaurante_id: restauranteId });
  if (error) throw error;
  const d = data as PedidosDelDia;
  const renglon = (r: RenglonPedido): RenglonPedido => ({
    ...r,
    precio_unitario: Number(r.precio_unitario),
    importe: Number(r.importe),
    opciones: r.opciones.map((o) => ({ ...o, precio_extra: Number(o.precio_extra) })),
  });
  return {
    ...d,
    por_confirmar: d.por_confirmar.map((p) => ({
      ...p,
      total: Number(p.total),
      paga_con: p.paga_con === null ? null : Number(p.paga_con),
      renglones: p.renglones.map(renglon),
    })),
    atendidos: d.atendidos.map((a) => ({ ...a, total: Number(a.total) })),
  };
}

// Los productos de envío de Mi menú, para elegir uno al confirmar un pedido a domicilio
// («Envío $30», «Envío lejos $50»), del más barato al más caro.
export type Envio = { id: number; nombre: string; precio: number };

export async function leerEnvios(cliente: SupabaseClient, restauranteId: string): Promise<Envio[]> {
  const { data, error } = await cliente
    .from('productos')
    .select('id, nombre, precio')
    .eq('restaurante_id', restauranteId)
    .eq('es_envio', true)
    .is('archivado_at', null)
    .order('precio')
    .order('nombre');
  if (error) throw error;
  return data.map((p) => ({ id: p.id, nombre: p.nombre, precio: Number(p.precio) }));
}

// «Confirmar»: regresa la cuenta que nació. null = el pedido era de un día que ya terminó y
// Postgres lo rechazó ahí mismo («No se confirmó»).
export async function confirmarPedido(cliente: SupabaseClient, pedidoId: number, envioId: number | null): Promise<number | null> {
  const { data, error } = await cliente.rpc('confirmar_pedido', { p_pedido_id: pedidoId, p_envio_id: envioId });
  if (error) throw fallo('confirmar_pedido no se pudo', error);
  return (data as number | null) ?? null;
}

export async function rechazarPedido(cliente: SupabaseClient, pedidoId: number, motivo: string): Promise<void> {
  const { error } = await cliente.rpc('rechazar_pedido', { p_pedido_id: pedidoId, p_motivo: motivo });
  if (error) throw fallo('rechazar_pedido no se pudo', error);
}

export async function pausarPedidos(cliente: SupabaseClient, restauranteId: string, pausar: boolean): Promise<void> {
  const { error } = await cliente.rpc('pausar_pedidos', { p_restaurante_id: restauranteId, p_pausar: pausar });
  if (error) throw fallo('pausar_pedidos no se pudo', error);
}

// ─── La vigía: los pedidos de hoy, el número de la pestaña y el tono ─────────────────────────

const UN_MINUTO = 60 * 1000;

// La tienen el aparato de quien es de caja y el panel del gerente, por encima de sus pestañas y
// vistas: así el tono suena en cualquiera (decidido el 25 de octubre de 2026). Suena al llegar un
// pedido y cada minuto mientras alguno espera «Por confirmar»; en pausa se calla. La pantalla de
// Pedidos pinta lo que ya leyó la vigía, sin leer otra vez.
//
// Con `miembroId`, también le suena «Lista» a quien confirmó un pedido (la comanda va a su nombre)
// mientras no tiene abierto el punto de venta, que ya suena solo: `oirListas`.
export class VigiaPedidos {
  datos = $state<PedidosDelDia | null>(null);
  error = $state(false); // la primera lectura falló; las demás se quedan con lo que había
  oirListas = $state(false);
  pendientes = $derived(this.datos?.por_confirmar.length ?? 0);
  // Lo que dice la pestaña o la barra lateral: «2», «Pausado» o nada.
  insignia = $derived(this.datos?.pausado ? 'Pausado' : this.pendientes ? String(this.pendientes) : '');

  private conocidos: Set<number> | null = null;
  private ultimoTono = 0;
  private ultimaLectura = 0;
  private mias: Set<number> | null = null;
  private leyendo: Promise<void> | null = null;
  private otraVez = false;

  constructor(
    private readonly cliente: SupabaseClient,
    private readonly restauranteId: string,
    private readonly miembroId: number | null = null,
  ) {}

  // Empieza a vigilar; regresa con qué se deja de vigilar.
  iniciar(): () => void {
    this.leer().catch(() => {});
    const dejarPedidos = escuchar(this.cliente, this.restauranteId, ['pedidos_en_linea'], () => {
      this.leer().catch(() => {});
    });
    const dejarComandas =
      this.miembroId === null
        ? () => {}
        : escuchar(this.cliente, this.restauranteId, ['comandas'], () => {
            this.revisarListas().catch((e) => console.error('[pedidos] no se pudieron revisar las comandas listas:', e));
          });
    // La pausa y el horario son del restaurante, no de un pedido: el tiempo real de los pedidos no
    // los trae. Por eso también vuelve a leer cada minuto (la pausa que puso otra pantalla, «Fuera de
    // horario» al cerrar).
    const reloj = setInterval(() => {
      if (performance.now() - this.ultimaLectura >= UN_MINUTO) this.leer().catch(() => {});
      this.sonarSiEspera();
    }, 5000);
    const alVolver = () => {
      if (document.visibilityState === 'visible') this.leer().catch(() => {});
    };
    document.addEventListener('pointerdown', prepararSonido, true);
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      dejarPedidos();
      dejarComandas();
      clearInterval(reloj);
      document.removeEventListener('pointerdown', prepararSonido, true);
      document.removeEventListener('visibilitychange', alVolver);
    };
  }

  // Vuelve a leer (después de confirmar, rechazar o pausar, o cuando avisa el tiempo real). Si ya
  // está leyendo, lee una vez más al terminar.
  leer(): Promise<void> {
    if (this.leyendo) {
      this.otraVez = true;
      return this.leyendo;
    }
    this.leyendo = (async () => {
      do {
        this.otraVez = false;
        let nuevos: PedidosDelDia;
        try {
          nuevos = await leerPedidos(this.cliente, this.restauranteId);
        } catch (falla) {
          console.error('[pedidos] no se pudieron leer los pedidos; se queda lo que se veía:', falla);
          if (!this.datos) this.error = true;
          throw falla;
        }
        this.error = false;
        this.ultimaLectura = performance.now();
        const llego = nuevos.por_confirmar.some((p) => !this.conocidos?.has(p.id));
        this.conocidos = new Set(nuevos.por_confirmar.map((p) => p.id));
        this.datos = nuevos;
        if (llego && !nuevos.pausado) this.sonar();
      } while (this.otraVez);
    })().finally(() => (this.leyendo = null));
    return this.leyendo;
  }

  private sonar() {
    this.ultimoTono = performance.now();
    avisarPedido();
  }

  private sonarSiEspera() {
    if (!this.datos || this.datos.pausado || this.pendientes === 0) return;
    if (performance.now() - this.ultimoTono >= UN_MINUTO) this.sonar();
  }

  // Las comandas que mandó quien vigila y siguen pendientes; la que pasa a «Lista» suena.
  private async revisarListas() {
    if (this.miembroId === null) return;
    const { data, error } = await this.cliente
      .from('comandas')
      .select('id, estado')
      .eq('restaurante_id', this.restauranteId)
      .eq('enviada_por', this.miembroId)
      .or(`estado.eq.pendiente${this.mias?.size ? `,id.in.(${[...this.mias].join(',')})` : ''}`);
    if (error) throw error;
    const listas = data.filter((c) => c.estado === 'lista' && this.mias?.has(c.id));
    this.mias = new Set(data.filter((c) => c.estado === 'pendiente').map((c) => c.id));
    if (listas.length && this.oirListas) avisarLista();
  }
}
