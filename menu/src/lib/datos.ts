// Lo que da menu_publico(slug) (migración menu_en_linea): lo único que el menú le pide a Supabase,
// como anon, con la llave publicable y un fetch, sin la librería de Supabase (libreta 6). null es
// «Este menú no está disponible»: un slug que no existe y una licencia pausada dicen lo mismo. Los
// precios en dólares ya vienen calculados por Postgres; el menú nunca hace cuentas de dinero.
import type { TemaMenu } from '@app/lib/color';

export type Opcion = {
  id: number;
  nombre: string;
  nombre_en: string | null;
  precio_extra: number;
  precio_extra_usd: number | null;
};

export type Grupo = {
  id: number;
  nombre: string;
  nombre_en: string | null;
  minimo: number;
  maximo: number;
  opciones: Opcion[];
};

export type Producto = {
  id: number;
  nombre: string;
  nombre_en: string | null;
  descripcion: string | null;
  descripcion_en: string | null;
  precio: number;
  precio_usd: number | null;
  imagen_ruta: string | null;
  // Un grupo obligatorio tiene una opción que sube el precio: «Desde $75».
  desde: boolean;
  grupos: Grupo[];
};

export type Categoria = {
  id: number;
  nombre: string;
  nombre_en: string | null;
  icono: string;
  productos: Producto[];
};

// privado.horario_ahora: null sin horario; abierto con su hora de cerrar; cerrado con la siguiente
// vez que abre (en_dias: 0 más tarde hoy, 1 mañana…).
export type Estado =
  | { abierto: true; cierra: string }
  | { abierto: false; abre: { dia: number; hora: string; en_dias: number } }
  | null;

// dia va de 1 (lunes) a 7 (domingo); las horas llegan como '9:00'.
export type Dia = { dia: number; abre: string; cierra: string };

export type MenuPublico = {
  restaurante: {
    nombre: string;
    telefono: string | null;
    direccion: string | null;
    logo_ruta: string | null;
    tema: TemaMenu;
    color: string | null;
    tipo_cambio_usd: number | null;
    hace_envios: boolean;
  };
  // La fecha y la hora del restaurante, nunca las del celular.
  ahora: { fecha: string; dia: number; hora: string };
  horario: Dia[];
  estado: Estado;
  // privado.recibe_pedidos: teléfono, dentro del horario y sin pausa (parte 6b).
  recibe_pedidos: boolean;
  pedidos_pausados: boolean;
  // Si el asistente contesta (parte 6c): su sobre tiene dinero. Sin números.
  asistente_contesta: boolean;
  carteles: string[];
  categorias: Categoria[];
};

const URL_SUPABASE = import.meta.env.VITE_SUPABASE_URL;
const LLAVE = import.meta.env.VITE_SUPABASE_LLAVE_PUBLICABLE;
const R2 = import.meta.env.VITE_R2_PUBLICO;
if (!URL_SUPABASE || !LLAVE || !R2) throw new Error('Faltan VITE_SUPABASE_URL, VITE_SUPABASE_LLAVE_PUBLICABLE o VITE_R2_PUBLICO en menu/.env');

export async function leerMenu(slug: string): Promise<MenuPublico | null> {
  const respuesta = await fetch(`${URL_SUPABASE}/rest/v1/rpc/menu_publico`, {
    method: 'POST',
    headers: { apikey: LLAVE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_slug: slug }),
  });
  if (!respuesta.ok) throw new Error(`menu_publico respondió ${respuesta.status}: ${await respuesta.text()}`);
  return (await respuesta.json()) as MenuPublico | null;
}

// El logo, las fotos y los carteles viven en R2, en la carpeta del restaurante.
export function urlImagen(ruta: string): string {
  return `${R2}/${ruta}`;
}
