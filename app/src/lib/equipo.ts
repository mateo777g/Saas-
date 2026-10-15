// Lo que lee y escribe Empleados (migración empleados): el equipo de la sucursal y sus aparatos.
// El gerente corrige nombre y roles y da de baja directo en miembros, solo esas columnas y solo a
// quien no es gerente (lo cuida RLS). El alta y los PIN pasan por el Worker, que mezcla el PIN con
// su llave antes de que llegue a Postgres; desbloquear, el código de 6 letras y desligar son
// funciones de la base. Nada de eso cuenta aquí: Postgres decide quién puede qué.
import { esDeRed, Fallo, mensajeDeError, SIN_CONEXION } from './errores';
import { diaAnterior, enZona, fecha } from './formato';
import type { Sucursal } from './gerente';
import { ROLES, type Rol } from './roles';
import { supabase } from './supabase';
import { llamarWorker } from './worker';

export type Persona = {
  id: number;
  nombre: string;
  roles: string[];
  gerente: boolean;
  yo: boolean;
  tienePin: boolean;
  // Sin bloquear, null. Bloqueada, hasta qué hora ('14:20', en la zona del restaurante), o null
  // si es hasta que su gerente la desbloquee (la segunda vez en el mismo día).
  bloqueo: { hasta: string | null } | null;
};

export type Aparato = {
  id: string;
  nombre: string;
  miembroId: number | null; // null: compartido
  ultimoUso: string | null; // ya en palabras: 'Hoy, 13:42'; null si nadie ha entrado
};

export type Equipo = { personas: Persona[]; aparatos: Aparato[] };

type FilaMiembro = {
  id: number;
  usuario_id: string;
  nombre: string;
  roles: string[];
  tiene_pin: boolean;
  bloqueado_hasta: string | null;
};

type FilaAparato = { id: string; nombre: string; miembro_id: number | null; ultimo_uso_at: string | null };

// Todo de una vez, al abrir y después de cada cambio: quienes están activos (los gerentes
// primero, quien entró antes que nadie, y después por nombre), quiénes siguen bloqueados y los
// aparatos ligados, en el orden en que se ligaron.
export async function leerEquipo(sucursal: Sucursal, usuarioId: string): Promise<Equipo> {
  const [miembros, bloqueados, aparatos, restaurante] = await Promise.all([
    supabase
      .from('miembros')
      .select('id, usuario_id, nombre, roles, tiene_pin, bloqueado_hasta')
      .eq('restaurante_id', sucursal.id)
      .eq('activo', true),
    // Si un bloqueo de 15 minutos ya pasó lo dice el reloj de Postgres, no el de la compu: el
    // 'now' de este filtro se lee allá.
    supabase
      .from('miembros')
      .select('id')
      .eq('restaurante_id', sucursal.id)
      .eq('activo', true)
      .gt('bloqueado_hasta', 'now'),
    supabase
      .from('dispositivos')
      .select('id, nombre, miembro_id, ultimo_uso_at')
      .eq('restaurante_id', sucursal.id)
      .is('revocado_at', null)
      .order('created_at')
      .order('id'),
    supabase.from('restaurantes').select('zona_horaria').eq('id', sucursal.id),
  ]);
  for (const r of [miembros, bloqueados, aparatos, restaurante]) if (r.error) throw r.error;
  const zona: string | undefined = restaurante.data?.[0]?.zona_horaria;
  if (!zona) throw new Error(`No se pudo leer la zona horaria de ${sucursal.id}`);

  const siguen = new Set((bloqueados.data ?? []).map((m: { id: number }) => m.id));
  const personas = (miembros.data as FilaMiembro[]).map((m): Persona => ({
    id: m.id,
    nombre: m.nombre,
    roles: m.roles,
    gerente: m.roles.includes('gerente'),
    yo: m.usuario_id === usuarioId,
    tienePin: m.tiene_pin,
    bloqueo:
      siguen.has(m.id) && m.bloqueado_hasta
        ? { hasta: m.bloqueado_hasta === 'infinity' ? null : enZona(m.bloqueado_hasta, zona).hora }
        : null,
  }));
  personas.sort(
    (a, b) =>
      Number(b.gerente) - Number(a.gerente) ||
      Number(b.yo) - Number(a.yo) ||
      a.nombre.localeCompare(b.nombre, 'es'),
  );

  return {
    personas,
    aparatos: (aparatos.data as FilaAparato[]).map((a) => ({
      id: a.id,
      nombre: a.nombre,
      miembroId: a.miembro_id,
      ultimoUso: a.ultimo_uso_at ? ultimoUso(a.ultimo_uso_at, zona, sucursal.hoy) : null,
    })),
  };
}

// 'Hoy, 13:42', 'Ayer, 22:10' o '8 oct 2026, 22:10', con el hoy de la sucursal que dio Postgres.
function ultimoUso(momento: string, zona: string, hoy: string): string {
  const { dia, hora } = enZona(momento, zona);
  if (dia === hoy) return `Hoy, ${hora}`;
  if (dia === diaAnterior(hoy)) return `Ayer, ${hora}`;
  return `${fecha(dia)}, ${hora}`;
}

// El error de una escritura, ya en español para la caja; el error completo queda en la consola.
function fallo(contexto: string, error: unknown): Fallo {
  console.error(`[equipo] ${contexto}:`, error);
  return new Fallo(esDeRed(error) ? SIN_CONEXION : mensajeDeError(error));
}

// Un UPDATE que RLS no deja pasar no da error: regresa 0 filas (la regla de siempre). Se revisa.
function revisarFilas(contexto: string, filas: unknown[] | null) {
  if ((filas?.length ?? 0) !== 1) {
    console.error(`[equipo] ${contexto}: se esperaba 1 fila y cambiaron ${filas?.length ?? 0}`);
    throw new Fallo('No se pudo guardar. Intenta de nuevo.');
  }
}

// Los roles elegidos, en el orden de siempre.
function enOrden(roles: Rol[]): Rol[] {
  return ROLES.map((r) => r.valor).filter((r) => roles.includes(r));
}

// «Agregar empleado»: el Worker le crea su cuenta y lo anota con su PIN.
export async function altaEmpleado(restauranteId: string, nombre: string, roles: Rol[], pin: string): Promise<void> {
  await llamarWorker('equipo', 'POST', '/equipo/empleado', {
    restaurante: restauranteId,
    nombre,
    roles: enOrden(roles),
    pin,
  });
}

// «Guardar PIN»: el de alguien del equipo, o el propio.
export async function ponerPin(miembroId: number, pin: string): Promise<void> {
  await llamarWorker('equipo', 'POST', '/equipo/pin', { miembro: miembroId, pin });
}

export async function editarEmpleado(id: number, nombre: string, roles: Rol[]): Promise<void> {
  const { data, error } = await supabase
    .from('miembros')
    .update({ nombre, roles: enOrden(roles) })
    .eq('id', id)
    .select('id');
  if (error) throw fallo('no se pudo editar a la persona', error);
  revisarFilas('editar persona', data);
}

// «Dar de baja»: ya no entra, y Postgres desliga su celular.
export async function darDeBaja(id: number): Promise<void> {
  const { data, error } = await supabase.from('miembros').update({ activo: false }).eq('id', id).select('id');
  if (error) throw fallo('no se pudo dar de baja', error);
  revisarFilas('dar de baja', data);
}

export async function desbloquear(id: number): Promise<void> {
  const { error } = await supabase.rpc('desbloquear_miembro', { p_miembro_id: id });
  if (error) throw fallo('desbloquear_miembro no se pudo', error);
}

// «Crear código»: el de 6 letras y cuándo vence. Sin persona, el aparato es compartido.
export async function crearCodigo(
  restauranteId: string,
  nombre: string,
  miembroId: number | null,
): Promise<{ codigo: string; expira: string }> {
  const { data, error } = await supabase.rpc('crear_codigo_vinculo', {
    p_restaurante_id: restauranteId,
    p_nombre: nombre,
    p_miembro_id: miembroId,
  });
  if (error) throw fallo('crear_codigo_vinculo no se pudo', error);
  const fila = (data as { codigo: string; expira_at: string }[] | null)?.[0];
  if (!fila) {
    console.error('[equipo] crear_codigo_vinculo no regresó el código:', data);
    throw new Fallo('No se pudo crear el código. Intenta de nuevo.');
  }
  return { codigo: fila.codigo, expira: fila.expira_at };
}

export async function desligar(id: string): Promise<void> {
  const { error } = await supabase.rpc('desligar_aparato', { p_dispositivo_id: id });
  if (error) throw fallo('desligar_aparato no se pudo', error);
}
