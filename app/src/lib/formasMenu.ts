// Las formas del menú en línea (migración tu_menu_en_linea, 12 de noviembre de 2026; maqueta UDArhiEZceT7rmSKxqRA5r):
// una columna por cosa en restaurantes, con sus nombres sin «menu_». El gerente las elige en «Tu menú en línea» y el
// menú las recibe en menu_publico().restaurante.formas. Viven aquí para que el panel y el menú (menu/src/lib/formas.ts,
// que las importa por @app) hablen de lo mismo; cada una nace como el menú de siempre (FORMAS_DE_SIEMPRE = los default
// de la tabla). Las reglas de verdad son las de la tabla: VALORES solo sirve para no romper nada con un valor raro.

export type Pieza = 'carteles' | 'busqueda' | 'categorias';

export type Formas = {
  // El logo a la izquierda (la de siempre) o grande al centro, con la lupa y el engrane.
  barra: 'izquierda' | 'centro';
  // Si el nombre va al lado del logo; sin logo, sale igual.
  con_nombre: boolean;
  // Con el logo a la izquierda: las letras ES/EN, el mundito con su listita o el cuadrito.
  idioma: 'letras' | 'planeta' | 'cuadro';
  moneda: 'letras' | 'monedas' | 'cuadro';
  // Con el logo al centro no cuenta: la búsqueda es la lupa de la barra.
  busqueda: 'gris' | 'blanca' | 'tarjeta';
  carteles: 'esquinas' | 'completo' | 'bajito';
  // La «i» en el cartel: la cápsula con si está abierto, o sola en su círculo; arriba o abajo.
  info: 'capsula' | 'icono';
  info_lugar: 'arriba' | 'abajo';
  // Un cartel que es un producto: con su nombre y su precio encima, o solo la foto.
  carteles_producto: 'nombre' | 'foto';
  categorias: 'pestanas' | 'rectangulos' | 'tarjeta' | 'pildoras' | 'circulos_icono' | 'circulos_foto';
  // El orden de las tres piezas de en medio, siempre abajo de la barra y arriba de los productos.
  orden: Pieza[];
  titulos: 'icono' | 'nombre' | 'raya';
  productos: 'a_lo_largo' | 'intercalado' | 'dos_en_dos' | 'clasicas';
  abajo: 'barra' | 'pildora';
  abajo_con_nombres: boolean;
  // Lo que se abre al tocar un producto.
  producto_ventana: 'completa' | 'ventana';
  producto_titulo: 'abajo' | 'arriba';
  producto_opciones: 'juntas' | 'pasos';
};

export const FORMAS_DE_SIEMPRE: Formas = {
  barra: 'izquierda',
  con_nombre: true,
  idioma: 'letras',
  moneda: 'letras',
  busqueda: 'gris',
  carteles: 'esquinas',
  info: 'capsula',
  info_lugar: 'arriba',
  carteles_producto: 'nombre',
  categorias: 'pestanas',
  orden: ['carteles', 'busqueda', 'categorias'],
  titulos: 'icono',
  productos: 'a_lo_largo',
  abajo: 'barra',
  abajo_con_nombres: true,
  producto_ventana: 'completa',
  producto_titulo: 'abajo',
  producto_opciones: 'juntas',
};

// Los valores de cada forma de texto, como las reglas `restaurantes_menu_*_lista` de la tabla.
export const VALORES: { [K in keyof Formas]?: readonly string[] } = {
  barra: ['izquierda', 'centro'],
  idioma: ['letras', 'planeta', 'cuadro'],
  moneda: ['letras', 'monedas', 'cuadro'],
  busqueda: ['gris', 'blanca', 'tarjeta'],
  carteles: ['esquinas', 'completo', 'bajito'],
  info: ['capsula', 'icono'],
  info_lugar: ['arriba', 'abajo'],
  carteles_producto: ['nombre', 'foto'],
  categorias: ['pestanas', 'rectangulos', 'tarjeta', 'pildoras', 'circulos_icono', 'circulos_foto'],
  titulos: ['icono', 'nombre', 'raya'],
  productos: ['a_lo_largo', 'intercalado', 'dos_en_dos', 'clasicas'],
  abajo: ['barra', 'pildora'],
  producto_ventana: ['completa', 'ventana'],
  producto_titulo: ['abajo', 'arriba'],
  producto_opciones: ['juntas', 'pasos'],
};

// Lo que llegue (de la base o del panel), revisado: lo que no sea una forma conocida se queda como la de siempre, así un
// valor raro nunca rompe el menú.
export function leerFormas(llegaron: unknown): Formas {
  const f = { ...FORMAS_DE_SIEMPRE } as Record<string, unknown>;
  if (!llegaron || typeof llegaron !== 'object') return f as Formas;
  const d = llegaron as Record<string, unknown>;
  for (const [k, lista] of Object.entries(VALORES)) if (typeof d[k] === 'string' && lista!.includes(d[k] as string)) f[k] = d[k];
  for (const k of ['con_nombre', 'abajo_con_nombres']) if (typeof d[k] === 'boolean') f[k] = d[k];
  const orden = d.orden;
  if (Array.isArray(orden) && orden.length === 3 && ['carteles', 'busqueda', 'categorias'].every((p) => orden.includes(p))) f.orden = [...orden];
  return f as Formas;
}

export function mismasFormas(a: Formas, b: Formas): boolean {
  return (Object.keys(FORMAS_DE_SIEMPRE) as (keyof Formas)[]).every((k) =>
    k === 'orden' ? a.orden.join() === b.orden.join() : a[k] === b[k],
  );
}
