// Los textos fijos del menú en sus dos idiomas (libreta 6: los traduce Fragmentless una vez; lo que
// escribe Don Chuy lleva su propio inglés, y lo que no lo tiene sale en español). Los de la maqueta
// de la 6a (Qx4C5CbKJYpeAsJCfw4ghn), sección 1.
import type { Estado } from './datos';

export type Lengua = 'es' | 'en';

export const TEXTOS = {
  es: {
    buscar: 'Buscar en el menú',
    limpiar: 'Borrar la búsqueda',
    ordenar: 'Ordenar por',
    ordenes: ['Recomendado', 'Precio: menor a mayor', 'Precio: mayor a menor', 'Nombre: A a Z'],
    desde: 'Desde',
    aprox: 'aprox.',
    incluido: 'Incluido',
    resultado: 'resultado',
    resultados: 'resultados',
    nada: (q: string) => `No encontramos «${q}»`,
    nadaTexto: 'Prueba con otra palabra, como el nombre de un platillo o de una bebida.',
    info: 'Información del restaurante',
    direccion: 'Dirección',
    whatsapp: 'WhatsApp',
    escribir: 'Escribir por WhatsApp',
    horario: 'Horario',
    hoy: 'hoy',
    cerrado: 'Cerrado',
    a: 'a',
    dias: ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'],
    cerrar: 'Cerrar',
    verFoto: 'Ver la foto',
    idioma: 'Idioma',
    moneda: 'Moneda',
    categorias: 'Categorías',
    cartel: (n: number, de: number) => `Cartel ${n} de ${de}`,
    apagado: 'Este menú no está disponible',
    apagadoTexto: 'Revisa el link o pregúntale al restaurante.',
    sinRed: 'No se pudo abrir el menú',
    sinRedTexto: 'Revisa tu internet e inténtalo otra vez.',
    reintentar: 'Intentar otra vez',
    // El pedido (parte 6b)
    agregarA: (n: string) => `Agregar ${n}`,
    elegirA: (n: string) => `Elegir ${n}`,
    agregar: 'Agregar al pedido',
    guardarCambios: 'Guardar cambios',
    nota: 'Nota · opcional',
    notaEjemplo: 'Ej. sin cebolla',
    falta: 'falta',
    elige: 'Elige',
    cantidad: 'Cantidad',
    unoMenos: 'Uno menos',
    unoMas: 'Uno más',
    quitar: 'Quitar',
    enTuPedido: ' · en tu pedido',
    ver: 'Ver tu pedido',
    tuPedido: 'Tu pedido',
    comoLoRecibes: 'Cómo lo recibes',
    llevar: 'Para llevar',
    domicilio: 'A domicilio',
    tuNombre: 'Tu nombre',
    nombreEjemplo: 'Nombre y apellido',
    telefono: 'Teléfono',
    telefonoEjemplo: '10 dígitos',
    tuDireccion: 'Dirección',
    direccionEjemplo: 'Calle, número y colonia',
    referencias: 'Referencias · opcional',
    referenciasEjemplo: 'Ej. portón verde',
    pagaCon: 'Si pagas en efectivo, ¿con cuánto? · opcional',
    pagaConEjemplo: 'Ej. 500',
    total: 'Total',
    masEnvio: ' + envío',
    envioPista: 'El envío te lo dice el restaurante por WhatsApp.',
    hacer: 'Hacer pedido',
    hacerPista: 'En el siguiente paso lo mandas por WhatsApp. Aquí no se paga.',
    notaRenglon: 'Nota: ',
    falta1: 'Falta un paso',
    pedidoN: (n: number) => `Pedido #${n}`,
    faltaTexto: 'Mándalo por WhatsApp para que lo reciban.',
    enviar: 'Enviar por WhatsApp',
    enviadoN: (n: number) => `Pedido #${n} enviado`,
    enviadoTexto: 'Te confirman por WhatsApp.',
    otraVez: 'Abrir WhatsApp otra vez',
    volver: 'Volver al menú',
    cambio: 'Cambió algo en el menú',
    cambioTexto: 'Revisa tu pedido y vuelve a tocar «Hacer pedido».',
    yaNoHay: (n: string) => `Ya no hay ${n}`,
    ahoraCuesta: (n: string, precio: string) => `${n} ahora cuesta ${precio}`,
    cambiaronOpciones: (n: string) => `Cambiaron las opciones de ${n}`,
    recibimos: (abre: string, cierra: string) => `Recibimos pedidos de ${abre} a ${cierra}`,
    noRecibimos: 'Por ahora no recibimos pedidos',
    noSeMando: 'No pudimos mandar tu pedido. Intenta otra vez.',
    // El asistente (parte 6c; maqueta 2UPwZw31WrcYRZkH8jaT1Y)
    asistente: (n: string) => `Asistente de ${n}`,
    saludo: (n: string) => `Hola, soy el asistente de ${n}. Pregúntame del menú, del horario o de los envíos.`,
    sugeridas: ['¿Qué me recomiendas?', '¿A qué hora cierran?', '¿Hacen envíos?'],
    escribe: 'Escribe tu pregunta',
    marcaIa: 'IA de Fragmentless · puede equivocarse',
    pensando: 'Pensando…',
    preguntale: 'Pregúntale al asistente',
    enviarPregunta: 'Enviar',
    sinIa: 'Por ahora no puedo contestar.',
    sinIaWa: ' Escríbele al restaurante por WhatsApp.',
    limiteCelular: 'Ya hiciste 20 preguntas en la última hora.',
    limiteConexion: 'Desde esta conexión ya se hicieron 60 preguntas en la última hora.',
    limiteWa: ' Si quieres saber algo más, escríbele al restaurante por WhatsApp.',
    limiteTarde: ' Inténtalo más tarde.',
    noContesto: 'No pude contestar. Vuelve a intentarlo.',
  },
  en: {
    buscar: 'Search the menu',
    limpiar: 'Clear the search',
    ordenar: 'Sort by',
    ordenes: ['Recommended', 'Price: low to high', 'Price: high to low', 'Name: A to Z'],
    desde: 'From',
    aprox: 'approx.',
    incluido: 'Included',
    resultado: 'result',
    resultados: 'results',
    nada: (q: string) => `No results for «${q}»`,
    nadaTexto: 'Try another word, like the name of a dish or a drink.',
    info: 'About the restaurant',
    direccion: 'Address',
    whatsapp: 'WhatsApp',
    escribir: 'Message on WhatsApp',
    horario: 'Hours',
    hoy: 'today',
    cerrado: 'Closed',
    a: 'to',
    dias: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    cerrar: 'Close',
    verFoto: 'See the photo',
    idioma: 'Language',
    moneda: 'Currency',
    categorias: 'Categories',
    cartel: (n: number, de: number) => `Banner ${n} of ${de}`,
    apagado: 'This menu is not available',
    apagadoTexto: 'Check the link or ask the restaurant.',
    sinRed: "We couldn't open the menu",
    sinRedTexto: 'Check your internet connection and try again.',
    reintentar: 'Try again',
    agregarA: (n: string) => `Add ${n}`,
    elegirA: (n: string) => `Choose ${n}`,
    agregar: 'Add to order',
    guardarCambios: 'Save changes',
    nota: 'Note · optional',
    notaEjemplo: 'E.g. no onions',
    falta: 'required',
    elige: 'Choose',
    cantidad: 'Quantity',
    unoMenos: 'One less',
    unoMas: 'One more',
    quitar: 'Remove',
    enTuPedido: ' · added',
    ver: 'View your order',
    tuPedido: 'Your order',
    comoLoRecibes: 'How you get it',
    llevar: 'Pickup',
    domicilio: 'Delivery',
    tuNombre: 'Your name',
    nombreEjemplo: 'First and last name',
    telefono: 'Phone',
    telefonoEjemplo: '10 digits',
    tuDireccion: 'Address',
    direccionEjemplo: 'Street, number and neighborhood',
    referencias: 'Directions · optional',
    referenciasEjemplo: 'E.g. green gate',
    pagaCon: 'Paying cash? How much? · optional',
    pagaConEjemplo: 'E.g. 500',
    total: 'Total',
    masEnvio: ' + delivery',
    envioPista: 'The restaurant tells you the delivery fee on WhatsApp.',
    hacer: 'Place order',
    hacerPista: "Next, you send it on WhatsApp. You don't pay here.",
    notaRenglon: 'Note: ',
    falta1: 'One more step',
    pedidoN: (n: number) => `Order #${n}`,
    faltaTexto: 'Send it on WhatsApp so they get it.',
    enviar: 'Send on WhatsApp',
    enviadoN: (n: number) => `Order #${n} sent`,
    enviadoTexto: "They'll confirm on WhatsApp.",
    otraVez: 'Open WhatsApp again',
    volver: 'Back to the menu',
    cambio: 'Something changed on the menu',
    cambioTexto: 'Check your order and tap «Place order» again.',
    yaNoHay: (n: string) => `No more ${n}`,
    ahoraCuesta: (n: string, precio: string) => `${n} now costs ${precio}`,
    cambiaronOpciones: (n: string) => `The options for ${n} changed`,
    recibimos: (abre: string, cierra: string) => `We take orders from ${abre} to ${cierra}`,
    noRecibimos: "We're not taking orders right now",
    noSeMando: "We couldn't send your order. Try again.",
    asistente: (n: string) => `Assistant for ${n}`,
    saludo: (n: string) => `Hi, I'm the assistant for ${n}. Ask me about the menu, our hours or delivery.`,
    sugeridas: ['What do you recommend?', 'What time do you close?', 'Do you deliver?'],
    escribe: 'Type your question',
    marcaIa: 'AI by Fragmentless · it can make mistakes',
    pensando: 'Thinking…',
    preguntale: 'Ask the assistant',
    enviarPregunta: 'Send',
    sinIa: "I can't answer right now.",
    sinIaWa: ' Message the restaurant on WhatsApp.',
    limiteCelular: "You've asked 20 questions in the last hour.",
    limiteConexion: '60 questions have been asked from this connection in the last hour.',
    limiteWa: " If you'd like to know more, message the restaurant on WhatsApp.",
    limiteTarde: ' Please try again later.',
    noContesto: "I couldn't answer. Please try again.",
  },
} as const;

export type Textos = (typeof TEXTOS)[Lengua];

// «Abierto · cierra a las 18:00», «Cerrado · abre mañana a las 9:00». Sin horario, nada. En
// español es «a la 1:00», no «a las 1:00».
export function textoEstado(estado: Estado, lengua: Lengua): string | null {
  if (!estado) return null;
  const alas = (hora: string) => (/^1:/.test(hora) ? `a la ${hora}` : `a las ${hora}`);
  if (lengua === 'en') {
    if (estado.abierto) return `Open · closes at ${estado.cierra}`;
    const { dia, hora, en_dias } = estado.abre;
    const cuando = en_dias === 0 ? 'today' : en_dias === 1 ? 'tomorrow' : TEXTOS.en.dias[dia - 1];
    return `Closed · opens ${cuando} at ${hora}`;
  }
  if (estado.abierto) return `Abierto · cierra ${alas(estado.cierra)}`;
  const { dia, hora, en_dias } = estado.abre;
  const cuando = en_dias === 0 ? 'hoy' : en_dias === 1 ? 'mañana' : `el ${TEXTOS.es.dias[dia - 1].toLowerCase()}`;
  return `Cerrado · abre ${cuando} ${alas(hora)}`;
}

// Cuántas opciones se eligen de un grupo, del mínimo y el máximo que guardó Postgres: «Elige 1»,
// «Hasta 3 · opcional». La misma regla que reglaCorta de app/src/lib/opciones.ts, dicha para la
// clienta y en sus dos idiomas.
export function textoRegla(minimo: number, maximo: number, lengua: Lengua): string {
  if (lengua === 'en') {
    if (minimo === 0) return maximo === 1 ? 'Optional' : `Up to ${maximo} · optional`;
    if (minimo === maximo) return `Choose ${minimo}`;
    return `Choose ${minimo} to ${maximo}`;
  }
  if (minimo === 0) return maximo === 1 ? 'Opcional' : `Hasta ${maximo} · opcional`;
  if (minimo === maximo) return `Elige ${minimo}`;
  return `Elige de ${minimo} a ${maximo}`;
}

// Lo que Don Chuy escribió en inglés, o su español si lo dejó vacío.
export function enSuLengua(es: string, en: string | null, lengua: Lengua): string;
export function enSuLengua(es: string | null, en: string | null, lengua: Lengua): string | null;
export function enSuLengua(es: string | null, en: string | null, lengua: Lengua): string | null {
  return lengua === 'en' && en ? en : es;
}

// Los «no» del Worker y de Postgres llegan en español (los lee también el restaurante). En inglés, los
// que la clienta puede ver seguido; uno que no esté aquí sale en español.
const EN: Record<string, string> = {
  'Ya mandaste 3 pedidos en la última hora. Si quieres algo más, escríbele al restaurante por WhatsApp.':
    "You've sent 3 orders in the last hour. If you need anything else, message the restaurant on WhatsApp.",
  'Desde esta conexión ya se mandaron 10 pedidos en la última hora. Si quieres algo más, escríbele al restaurante por WhatsApp.':
    'This connection already sent 10 orders in the last hour. If you need anything else, message the restaurant on WhatsApp.',
  'No pudimos revisar que eres tú. Intenta otra vez.': "We couldn't check it's you. Try again.",
  'No pudimos mandar tu pedido. Intenta otra vez.': "We couldn't send your order. Try again.",
  'Por ahora no hacemos envíos. Puedes pedir para llevar.': "We're not delivering right now. You can order for pickup.",
};

export function enSuLenguaElNo(mensaje: string, lengua: Lengua): string {
  return lengua === 'en' ? (EN[mensaje] ?? mensaje) : mensaje;
}

// El límite por hora: «Tu pedido» enseña el botón de WhatsApp y apaga «Hacer pedido».
export function esLimite(mensaje: string): boolean {
  return mensaje.startsWith('Ya mandaste 3 pedidos') || mensaje.startsWith('Desde esta conexión ya se mandaron');
}
