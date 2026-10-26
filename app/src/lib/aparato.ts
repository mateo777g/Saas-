// El aparato del equipo (libreta 3, «El personal: aparato y PIN»): la tableta de la caja o el
// celular de Pepe, que abre /equipo. No usa la sesión del panel ni pasa por su portero
// (App.svelte y sesion.ts, que le cierran la sesión a quien no tiene panel): guarda su propio
// secreto y la sesión de quien entró con otros nombres en el navegador, así que en la compu del
// gerente pueden vivir los dos. Todo lo pide al Worker: el aparato no tiene sesión hasta que
// alguien pone su PIN, y el PIN nunca llega a Postgres sin la llave del Worker.
import { createClient } from '@supabase/supabase-js';
import { ALGO_SALIO_PANEL, SIN_CONEXION } from './errores';

const API = import.meta.env.VITE_API_URL;
const URL_PROYECTO = import.meta.env.VITE_SUPABASE_URL;
const LLAVE_PUBLICABLE = import.meta.env.VITE_SUPABASE_LLAVE_PUBLICABLE;
if (!API || !URL_PROYECTO || !LLAVE_PUBLICABLE) {
  throw new Error('Faltan VITE_API_URL, VITE_SUPABASE_URL o VITE_SUPABASE_LLAVE_PUBLICABLE en app/.env');
}

// La sesión de quien entró con su PIN: la que el Worker registró como la única de este aparato.
// La usará el punto de venta (pieza 4); se renueva sola, con el mismo session_id.
export const supabaseAparato = createClient(URL_PROYECTO, LLAVE_PUBLICABLE, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
    storageKey: 'fragmentless-sesion-aparato',
  },
});

// Lo que el aparato recuerda: su secreto (43 caracteres que solo él guarda; la base tiene su
// huella), cómo se llama, si es compartido y quién está adentro. `ultimoDeCaja`: la última persona
// que entró era de caja; así la tableta de la caja suena con los pedidos también en «¿Quién eres?»,
// y la de la cocina no (parte 6b).
export type Ligado = { token: string; aparato: string; compartido: boolean; adentro: number | null; ultimoDeCaja?: boolean };

const LLAVE_LIGADO = 'fragmentless-aparato';

export function leerLigado(): Ligado | null {
  try {
    const guardado = localStorage.getItem(LLAVE_LIGADO);
    if (!guardado) return null;
    const l = JSON.parse(guardado) as Partial<Ligado>;
    if (typeof l.token !== 'string' || typeof l.aparato !== 'string' || typeof l.compartido !== 'boolean') {
      console.error('[aparato] lo guardado no se entiende; se olvida:', Object.keys(l));
      olvidarLigado();
      return null;
    }
    return { token: l.token, aparato: l.aparato, compartido: l.compartido, adentro: l.adentro ?? null, ultimoDeCaja: l.ultimoDeCaja === true };
  } catch (error) {
    console.error('[aparato] no se pudo leer lo guardado:', error);
    return null;
  }
}

export function guardarLigado(ligado: Ligado): void {
  try {
    localStorage.setItem(LLAVE_LIGADO, JSON.stringify(ligado));
  } catch (error) {
    console.error('[aparato] no se pudo guardar el aparato:', error);
  }
}

// Al olvidarse, el aparato también olvida lo del punto de venta (los borradores de cada quien,
// lib/pos.ts) y el área que mostraba la cocina (Cocina.svelte): ligado otra vez, empieza limpio
// (decidido el 17 de octubre de 2026). En una compu que también es el panel del gerente, eso
// incluye su borrador sin mandar.
const PREFIJOS_DEL_POS = ['fragmentless-pos-', 'fragmentless-cocina-'];

export function olvidarLigado(): void {
  try {
    localStorage.removeItem(LLAVE_LIGADO);
    for (const llave of Object.keys(localStorage)) {
      if (PREFIJOS_DEL_POS.some((p) => llave.startsWith(p))) localStorage.removeItem(llave);
    }
  } catch (error) {
    console.error('[aparato] no se pudo olvidar el aparato:', error);
  }
}

// Un «no» del Worker con su texto en español. `desligado`: el aparato ya no está ligado (se
// desligó, o su persona se dio de baja) y hay que pedir un código nuevo.
export class FalloAparato extends Error {
  constructor(
    mensaje: string,
    readonly desligado = false,
  ) {
    super(mensaje);
  }
}

async function pedir<T>(camino: string, cuerpo: Record<string, unknown>): Promise<T> {
  let respuesta: Response;
  try {
    respuesta = await fetch(`${API}${camino}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
    });
  } catch (falla) {
    console.error(`[aparato] ${camino}: no se pudo hablar con el Worker:`, falla);
    throw new FalloAparato(SIN_CONEXION);
  }
  const datos = await respuesta.json().catch(() => null);
  if (!respuesta.ok) {
    console.error(`[aparato] ${camino}: el Worker dijo ${respuesta.status}:`, datos);
    const mensaje = typeof datos?.error === 'string' ? datos.error : ALGO_SALIO_PANEL;
    // 404 con el secreto: Postgres ya no encuentra el aparato ligado (aparato_vigente).
    throw new FalloAparato(mensaje, respuesta.status === 404 && camino !== '/equipo/vincular');
  }
  return datos as T;
}

// «Vincular»: el código de 6 letras de Empleados. El Worker genera el secreto del aparato.
export async function vincular(codigo: string): Promise<Ligado> {
  const r = await pedir<{ token: string; aparato: string; compartido: boolean }>('/equipo/vincular', { codigo });
  const ligado = { token: r.token, aparato: r.aparato, compartido: r.compartido, adentro: null };
  guardarLigado(ligado);
  return ligado;
}

export type PersonaAparato = {
  id: number;
  nombre: string;
  roles: string[];
  bloqueado: boolean;
  bloqueadoHasta: string | null; // el momento en que termina; null: hasta que su gerente la desbloquee
};

export type Lista = {
  restaurante: string;
  aparato: string;
  compartido: boolean;
  personas: PersonaAparato[];
  pedidosPorConfirmar: number | null; // null donde no entra nadie de caja (parte 6b)
};

// «¿Quién eres?»: el restaurante, el aparato y quiénes pueden entrar ahí (en uno de una
// persona, solo ella), y cuántos pedidos del menú esperan. Si un bloqueo sigue lo decide Postgres.
export async function nombres(token: string): Promise<Lista> {
  const r = await pedir<{
    restaurante: string;
    aparato: string;
    compartido: boolean;
    personas: { id: number; nombre: string; roles: string[]; bloqueado: boolean; bloqueado_hasta: string | null }[];
    pedidos_por_confirmar: number | null;
  }>('/equipo/nombres', { token });
  return {
    restaurante: r.restaurante,
    aparato: r.aparato,
    compartido: r.compartido,
    personas: r.personas.map((p) => ({
      id: p.id,
      nombre: p.nombre,
      roles: p.roles,
      bloqueado: p.bloqueado,
      bloqueadoHasta: p.bloqueado_hasta,
    })),
    pedidosPorConfirmar: r.pedidos_por_confirmar ?? null,
  };
}

export type Entrada =
  | { ok: true }
  | { ok: false; motivo: 'pin'; quedan: number }
  | { ok: false; motivo: 'bloqueado'; hasta: string | null };

// Pepe pone su PIN. Si Postgres dice que sí, el Worker le da su sesión y aquí se guarda.
export async function entrar(ligado: Ligado, miembro: PersonaAparato, pin: string): Promise<Entrada> {
  const r = await pedir<
    | { ok: true; sesion: { access_token: string; refresh_token: string } }
    | { ok: false; motivo: 'pin'; quedan: number }
    | { ok: false; motivo: 'bloqueado'; hasta: string | null }
  >('/equipo/entrar', { token: ligado.token, miembro: miembro.id, pin });
  if (!r.ok) return r;

  const { error } = await supabaseAparato.auth.setSession(r.sesion);
  if (error) {
    console.error('[aparato] no se pudo guardar la sesión que dio el Worker:', error);
    throw new FalloAparato(ALGO_SALIO_PANEL);
  }
  guardarLigado({ ...ligado, adentro: miembro.id, ultimoDeCaja: miembro.roles.includes('caja') });
  return { ok: true };
}

// Sale quien estaba adentro: su sesión se cierra (también en Supabase) y el aparato lo olvida.
export async function salir(ligado: Ligado | null): Promise<void> {
  const { error } = await supabaseAparato.auth.signOut({ scope: 'local' });
  if (error) console.error('[aparato] el servidor no se enteró del cierre; se borró solo aquí:', error);
  if (ligado) guardarLigado({ ...ligado, adentro: null });
}

// ¿Hay una sesión guardada en este aparato?
export async function haySesion(): Promise<boolean> {
  const { data, error } = await supabaseAparato.auth.getSession();
  if (error) console.error('[aparato] no se pudo leer la sesión guardada:', error);
  return !!data.session;
}

// La hora en que termina un bloqueo ('14:35'). El aparato no tiene la zona del restaurante antes
// de que alguien entre: usa la suya, porque está en el restaurante.
export function horaDe(momento: string): string {
  return new Intl.DateTimeFormat('es-MX', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(
    new Date(momento),
  );
}
