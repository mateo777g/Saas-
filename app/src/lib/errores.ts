// Los mensajes de error que se repiten entre pantallas, escritos una sola vez, y cómo saber si
// un error fue por falta de internet. Los textos son los del panel de Flet.

export const SIN_CONEXION = 'No hay conexión con el servidor. Revisa tu internet.';
export const ALGO_SALIO = 'Algo salió mal al iniciar sesión. Intenta de nuevo.';
export const ALGO_SALIO_PANEL = 'Algo salió mal. Intenta de nuevo.';

// Un error con su texto ya en español, listo para la caja de error de la ventana.
export class Fallo extends Error {}

// ¿El error es porque no se pudo hablar con el servidor? Los navegadores lo dicen distinto:
// Chrome "Failed to fetch", Firefox "NetworkError…", Safari "Load failed". Supabase lo envuelve
// en su propio error (AuthRetryableFetchError en el login), con ese texto adentro.
export function esDeRed(error: unknown): boolean {
  if (!error) return false;
  const e = error as { name?: string; message?: string };
  if (e.name === 'AuthRetryableFetchError' || error instanceof TypeError) return true;
  return /Failed to fetch|NetworkError|Load failed|fetch failed/i.test(e.message ?? '');
}

// Lo que Postgres dice en inglés cuando una fila no cumple una regla de su tabla, traducido por
// el nombre de la regla (migraciones plataforma, mesas y menu_en_linea). Los textos son los de la
// maqueta del panel de Fragmentless (Tbt7H3G1QRXykzNKe1GXHh), los de Flet para las mesas y, para
// el menú en línea, los mismos de sus funciones (guardar_restaurante, guardar_menu_en_linea), por
// si un día una fila llega sin pasar por ellas.
const REGLAS: Record<string, string> = {
  restaurantes_nombre_check: 'Escribe el nombre del restaurante.',
  restaurantes_slug_formato:
    'El slug solo lleva minúsculas, números y guiones, sin guion al inicio ni al final ni dos seguidos.',
  restaurantes_licencia_con_fin: 'No se puede prender una licencia sin fecha de fin.',
  restaurantes_nombre_largo: 'El nombre puede tener hasta 60 letras.',
  restaurantes_telefono_formato: 'El teléfono lleva 10 dígitos, como 222 123 4567.',
  restaurantes_direccion_formato: 'La dirección puede tener hasta 200 letras.',
  restaurantes_logo_ruta_formato: 'No se pudo guardar el logo. Vuelve a subirlo.',
  restaurantes_menu_tema_lista: 'El menú se ve claro u oscuro.',
  restaurantes_menu_color_formato: 'Ese color no se entiende; escríbelo como #B3261E.',
  restaurantes_tipo_cambio_positivo: 'Escribe a cuánto tomas el dólar, como 18.50.',
  horarios_abre_distinto_de_cierra: 'Un día de tu horario abre y cierra a la misma hora.',
  carteles_imagen_ruta_formato: 'No se pudo guardar el cartel. Vuelve a subirlo.',
  miembros_nombre_check: 'Escribe su nombre completo.',
  mesas_nombre_check: 'Escribe un nombre para la mesa.',
  areas_preparacion_nombre_check: 'Escribe un nombre para el área.',
};

// Los finales de los mensajes que empiezan con un nombre: los de la migración distribuidores
// («Juanito Pérez ya tiene su cuenta ligada»), el de eliminar una categoría con productos
// (migración menu: «tacos todavía tiene 6 productos; …»), el de eliminar un área con categorías
// (migración opciones: «barra todavía tiene 2 categorías; …») y los de una mesa con la cuenta
// abierta (migración cuentas: «terraza tiene una cuenta abierta…», «barra ya tiene una cuenta
// abierta»).
const CON_NOMBRE = [
  / ya tiene su cuenta ligada$/,
  / está de baja; primero usa Reactivar$/,
  / todavía tiene \d+ clientes?; quítasel(o|os) primero$/,
  / todavía tiene \d+ productos?; muével(o|os) a otra categoría o elimínal(o|os) primero$/,
  / todavía tiene \d+ categorías?; cámbiala(s)? de área primero$/,
  / tiene una cuenta abierta\. Cóbrala o cámbiala de mesa antes de eliminarla\.$/,
  / ya tiene una cuenta abierta$/,
];

// El mensaje para la caja de error cuando falla una llamada a Postgres. Las funciones de la base
// ya lanzan sus errores en español ("Falta la fecha de inicio"), y salen tal cual. Postgres
// escribe los suyos en inglés y empezando con minúscula (es su regla de estilo): esos se
// traducen si son de una regla conocida, y si no, sale el genérico. Quien llama ya dejó el error
// completo en la consola.
export function mensajeDeError(error: unknown): string {
  if (esDeRed(error)) return SIN_CONEXION;
  const e = error as { code?: string; message?: string; details?: string };
  const mensaje = e.message ?? '';

  if (e.code === '23505' && mensaje.includes('"categorias_nombre_unico"')) {
    return 'Ya tienes una categoría con ese nombre.';
  }
  if (e.code === '23505' && mensaje.includes('"areas_preparacion_nombre_unico"')) {
    return 'Ya tienes un área con ese nombre.';
  }
  if (e.code === '23505' && mensaje.includes('"mesas_nombre_unico"')) {
    return 'Ya tienes una mesa con ese nombre.';
  }
  if (e.code === '23505' && mensaje.includes('"miembros_nombre_unico"')) {
    return 'Ya hay alguien en tu equipo con ese nombre.';
  }
  if (e.code === '23505' && mensaje.includes('"restaurantes_slug_key"')) {
    const slug = /\(slug\)=\((.*)\)/.exec(e.details ?? '')?.[1];
    if (slug !== undefined) return `Ya hay un restaurante con el slug ${slug}. Elige otro.`;
  }
  if (e.code === '23514') {
    const regla = Object.keys(REGLAS).find((nombre) => mensaje.includes(`"${nombre}"`));
    if (regla) return REGLAS[regla];
  }
  // Un código de Postgres (5 caracteres; los de PostgREST empiezan con PGRST) con un mensaje que
  // empieza con mayúscula o con comillas («Taco de pastor» está agotado…), o uno de los que
  // empiezan con un nombre (que pudo escribirse en minúscula): es de nuestras funciones.
  if (/^[0-9A-Z]{5}$/.test(e.code ?? '') && (/^[A-ZÁÉÍÓÚÑ«¿]/.test(mensaje) || CON_NOMBRE.some((r) => r.test(mensaje)))) {
    return sinCentavos(mensaje);
  }
  return ALGO_SALIO_PANEL;
}

// Postgres escribe el dinero con centavos («Ya se pagaron $200.00», privado.pesos de la migración
// cancelaciones); la app lo enseña como dinero() de formato.ts: «$200», y «$148.50» se queda.
export function sinCentavos(texto: string): string {
  return texto.replace(/\$(\d[\d,]*)\.00\b/g, '$$$1');
}
