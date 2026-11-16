// La conexión de la sucursal con su Mercado Pago (libreta 5, «La terminal conectada»; libreta 4, la cajita de Ajustes;
// maqueta de la terminal v2, pantalla Ajustes). La cajita «Mercado Pago» de Ajustes y la franja ámbar de Inicio leen de
// aquí su estado; conectar, elegir la Point y desconectar pasan por aquí.
//
// Conectar y desconectar piden la contraseña otra vez: la ventanita de Ajustes vuelve a entrar con el mismo correo
// (`confirmarContrasena`) y Postgres revisa que la sesión diga «contraseña» de hace 5 minutos o menos. Conectar lleva a
// Mercado Pago (POST /mp/conectar da la dirección) y Mercado Pago regresa a la app con ?mp=conectado | cancelado | error
// (`leerRegreso`). La lista de las Point y ligar una van por el Worker, que tiene las llaves.
import { ALGO_SALIO_PANEL, Fallo, mensajeDeError } from './errores';
import { supabase } from './supabase';
import { llamarWorker } from './worker';

export type EstadoMercadoPago =
  | { estado: 'sin' }
  | { estado: 'conectado'; cuenta: string; desde: string; zona: string; terminalId: string | null; imprimirTicket: boolean }
  | { estado: 'desconectado'; cuando: string; zona: string };

// Sin fila: sin conectar. Con desconectada_at: se desconectó (el permiso se quitó o la llave venció). Si no, conectada.
// Las fechas se dicen en la zona del restaurante, nunca con el reloj del aparato.
export async function leerMercadoPago(restauranteId: string): Promise<EstadoMercadoPago> {
  const [conexion, restaurante] = await Promise.all([
    supabase
      .from('mercado_pago')
      .select('cuenta_nombre, conectada_at, desconectada_at, terminal_id, imprimir_ticket')
      .eq('restaurante_id', restauranteId)
      .maybeSingle(),
    supabase.from('restaurantes').select('zona_horaria').eq('id', restauranteId).single(),
  ]);
  if (conexion.error) throw conexion.error;
  if (restaurante.error) throw restaurante.error;
  const data = conexion.data;
  const zona = restaurante.data.zona_horaria as string;
  if (!data) return { estado: 'sin' };
  if (data.desconectada_at) return { estado: 'desconectado', cuando: data.desconectada_at, zona };
  return {
    estado: 'conectado',
    cuenta: data.cuenta_nombre,
    desde: data.conectada_at,
    zona,
    terminalId: data.terminal_id,
    imprimirTicket: data.imprimir_ticket,
  };
}

// La contraseña otra vez: entra de nuevo con el correo de la sesión. Así la sesión dice que la contraseña se puso
// ahora, y Postgres deja conectar o desconectar durante 5 minutos.
export async function confirmarContrasena(contrasena: string): Promise<void> {
  const { data, error } = await supabase.auth.getUser();
  const correo = data.user?.email;
  if (error || !correo) {
    console.error('[mercado pago] no se pudo leer el correo de la sesión:', error);
    throw new Fallo('Tu sesión venció. Vuelve a entrar.');
  }
  const entrada = await supabase.auth.signInWithPassword({ email: correo, password: contrasena });
  if (entrada.error) {
    if (entrada.error.status === 400) throw new Fallo('Esa no es tu contraseña.');
    console.error('[mercado pago] no se pudo revisar la contraseña:', entrada.error);
    throw new Fallo(mensajeDeError(entrada.error));
  }
}

// Lleva al permiso de Mercado Pago. Lo que sigue pasa en otra página: no regresa.
export async function irAConectar(restauranteId: string): Promise<void> {
  const r = await llamarWorker('mercado pago', 'POST', '/mp/conectar', { restaurante: restauranteId });
  const url = typeof r?.url === 'string' ? r.url : '';
  if (!url.startsWith('https://')) {
    console.error('[mercado pago] /mp/conectar no dio a dónde ir:', r);
    throw new Fallo(ALGO_SALIO_PANEL);
  }
  window.location.href = url;
}

export async function desconectarMercadoPago(restauranteId: string): Promise<void> {
  const { error } = await supabase.rpc('desconectar_mercado_pago', { p_restaurante_id: restauranteId });
  if (error) {
    console.error('[mercado pago] no se pudo desconectar:', error);
    throw new Fallo(mensajeDeError(error));
  }
}

export async function fijarImprimirTicket(restauranteId: string, imprimir: boolean): Promise<void> {
  const { error } = await supabase.rpc('fijar_imprimir_ticket', { p_restaurante_id: restauranteId, p_imprimir: imprimir });
  if (error) {
    console.error('[mercado pago] no se pudo cambiar el ticket:', error);
    throw new Fallo(mensajeDeError(error));
  }
}

// Las Point de la cuenta: `en` = la otra sucursal donde ya está (no se puede elegir). `desligada` = la que estaba
// ligada ya no está en la cuenta (se desligó en la app de Mercado Pago); el Worker ya la quitó.
export type Terminales = { terminales: { id: string; en: string | null }[]; ligada: string | null; desligada: string | null };

export async function leerTerminales(restauranteId: string): Promise<Terminales> {
  const r = (await llamarWorker('mercado pago', 'POST', '/mp/terminales', { restaurante: restauranteId })) ?? {};
  const lista = Array.isArray(r.terminales) ? (r.terminales as { id: string; en: string | null }[]) : [];
  return {
    terminales: lista.map((t) => ({ id: String(t.id), en: typeof t.en === 'string' ? t.en : null })),
    ligada: typeof r.ligada === 'string' ? r.ligada : null,
    desligada: typeof r.desligada === 'string' ? r.desligada : null,
  };
}

// Liga la Point y la pone en modo de punto de venta. `reinicia` = hay que reiniciarla una vez.
export async function ligarTerminal(restauranteId: string, terminalId: string): Promise<{ reinicia: boolean }> {
  const r = await llamarWorker('mercado pago', 'POST', '/mp/terminal', { restaurante: restauranteId, terminal_id: terminalId });
  return { reinicia: !!r?.reinicia };
}

// «Reinicia tu terminal una vez»: se queda en este navegador hasta que se toca «Ya la reinicié».
const LLAVE_REINICIA = (restauranteId: string) => `fragmentless-mp-reinicia-${restauranteId}`;

export function tocaReiniciar(restauranteId: string): boolean {
  try {
    return localStorage.getItem(LLAVE_REINICIA(restauranteId)) === '1';
  } catch {
    return false;
  }
}

export function marcarReiniciar(restauranteId: string, toca: boolean): void {
  try {
    if (toca) localStorage.setItem(LLAVE_REINICIA(restauranteId), '1');
    else localStorage.removeItem(LLAVE_REINICIA(restauranteId));
  } catch (error) {
    console.error('[mercado pago] no se pudo guardar «Reinicia tu terminal» en este navegador:', error);
  }
}

// Lo que dice la dirección al regresar de Mercado Pago (?mp=conectado[&reinicia=1] | cancelado | error). La quita de la
// dirección para que recargar no lo repita.
export type Regreso = { resultado: 'conectado' | 'cancelado' | 'error'; reinicia: boolean };

export function leerRegreso(): Regreso | null {
  const params = new URLSearchParams(window.location.search);
  const mp = params.get('mp');
  if (mp !== 'conectado' && mp !== 'cancelado' && mp !== 'error') return null;
  const reinicia = params.get('reinicia') === '1';
  params.delete('mp');
  params.delete('reinicia');
  const resto = params.toString();
  history.replaceState(history.state, '', `${window.location.pathname}${resto ? `?${resto}` : ''}${window.location.hash}`);
  return { resultado: mp, reinicia };
}
