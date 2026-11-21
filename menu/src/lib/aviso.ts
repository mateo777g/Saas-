// El aviso de privacidad del menú (los datos de los clientes, 21 nov 2026): el borrador aprobado de
// planes/trabajo/datos-de-clientes/aviso.md, palabra por palabra, en español e inglés. Es el mismo texto para todos los
// menús (encuestas.md, «Lo que decidí yo» 3): vive aquí, no en Postgres, para que una corrección del abogado sea publicar el
// menú. Lo de entre llaves lo llena el menú con lo que manda menu_publico (Tu restaurante); **así** va en negritas y
// [así] es un hueco del borrador, por definir (la maqueta lo marca en amarillo). ANTES DEL PRIMER CLIENTE LO REVISA UN
// ABOGADO.
import type { Lengua } from './textos';

export type Bloque = { p: string } | { lista: string[] };

// El día en que cambió este texto, el mismo para todos.
export const FECHA = { es: '20 de noviembre de 2026', en: 'November 20, 2026' };

export const AVISO: Record<Lengua, Bloque[]> = {
  es: [
    { p: "**Quién cuida tus datos.** {responsable}, con domicilio en {domicilio}, es responsable de los datos que nos das al pedir en este menú. El menú funciona con el sistema de Fragmentless ([razón social de Fragmentless, por definir]), que guarda y procesa tus datos por nosotros, solo para lo que dice este aviso." },
    { p: "**Qué datos usamos.**" },
    {
      lista: [
        "Al pedir: tu nombre y tu teléfono; si es a domicilio, tu dirección, las referencias que quieras darnos y con cuánto pagas; y las notas que escribas en tu pedido.",
        "Si le preguntas algo al asistente del menú: tu pregunta.",
        "Para evitar pedidos falsos, una huella cifrada de tu celular y de tu conexión (no tu número ni tu dirección de internet), y la revisión de un servicio que comprueba que no eres un robot.",
      ],
    },
    { p: "No te pedimos datos sensibles (salud, religión, origen, etc.)." },
    { p: "**Para qué.** Solo para:" },
    {
      lista: [
        "recibir, preparar y entregarte tu pedido;",
        "avisarte si algo cambia (si se agotó algo, la hora de entrega);",
        "cobrarlo y llevar nuestras cuentas;",
        "contestar tus preguntas sobre el menú;",
        "evitar pedidos falsos y abusos.",
      ],
    },
    { p: "No usamos tus datos para publicidad ni para nada más. Si algún día queremos usarlos para otra cosa, te pediremos permiso antes." },
    { p: "**Cuánto tiempo.**" },
    {
      lista: [
        "Tu teléfono, tu dirección y tus referencias se borran solos 90 días después de tu pedido (7 días si no se confirmó).",
        "Tu nombre, lo que pediste y el total se quedan en nuestras cuentas, porque así lo pide la ley.",
        "Tus preguntas al asistente no se guardan.",
      ],
    },
    { p: "**En tu celular.** Para que no escribas tus datos cada vez, este menú los recuerda en tu navegador, solo en tu celular y solo para este restaurante; también tu pedido sin mandar, tu idioma y tu moneda. No usamos cookies de publicidad ni de rastreo. Los borras cuando quieras con «Borrar mis datos», en «Tus datos» de la vista Pedido." },
    { p: "**Con quién.** No vendemos ni prestamos tus datos. Los procesan por nosotros Fragmentless y sus proveedores de nube y de inteligencia artificial, con servidores en Estados Unidos, que solo pueden usarlos para darnos su servicio. Solo los entregaríamos a una autoridad que los pida conforme a la ley. Al pedir, tú nos mandas el mensaje desde tu WhatsApp: WhatsApp los trata con su propio aviso de privacidad." },
    { p: "**Servicios de inteligencia artificial.**" },
    {
      lista: [
        "Lo que le escribes al asistente del menú lo lee un servicio de inteligencia artificial para contestarte; no se guarda ni se usa para entrenarlo. No le escribas datos personales.",
        "Un asistente de inteligencia artificial que nos ayuda a revisar nuestras ventas puede leer el nombre de tu pedido, nunca tu teléfono ni tu dirección; tampoco se usa para entrenarlo.",
      ],
    },
    { p: "**Tus derechos.** Puedes pedirnos ver tus datos, corregirlos, borrarlos u oponerte a que los usemos, y retirar tu permiso. Escríbenos por WhatsApp al {whatsapp} desde el número con el que pediste (así sabemos que eres tú) y dinos qué quieres. Es gratis. Te contestamos en un máximo de 20 días hábiles y, si procede, lo hacemos en los 15 días hábiles siguientes. Si escribes desde otro número, te pediremos confirmar que eres tú." },
    { p: "**Si algo cambia.** Cualquier cambio a este aviso sale en esta misma página con su fecha. Si cambia para qué usamos tus datos, te pediremos permiso otra vez." },
    { p: "**Si crees que no respetamos tus derechos,** puedes acudir a la Secretaría Anticorrupción y Buen Gobierno." },
    { p: "Última actualización: {fecha}." },
  ],
  en: [
    { p: "**Who looks after your data.** {responsable}, located at {domicilio}, is responsible for the data you give us when you order from this menu. The menu runs on Fragmentless's system ([Fragmentless legal name, to be defined]), which stores and processes your data on our behalf, only for what this notice says." },
    { p: "**What data we use.**" },
    {
      lista: [
        "When you order: your name and phone number; for delivery, your address, any directions you choose to give us and what you will pay with; and any notes you write in your order.",
        "If you ask the menu's assistant something: your question.",
        "To prevent fake orders, an encrypted fingerprint of your phone and your connection (not your number or your internet address), and a check by a service that makes sure you are not a robot.",
      ],
    },
    { p: "We do not ask for sensitive data (health, religion, origin, etc.)." },
    { p: "**What for.** Only to:" },
    {
      lista: [
        "receive, prepare and deliver your order;",
        "let you know if something changes (an item sold out, the delivery time);",
        "charge for it and keep our books;",
        "answer your questions about the menu;",
        "prevent fake orders and abuse.",
      ],
    },
    { p: "We do not use your data for advertising or anything else. If we ever want to use it for something new, we will ask for your permission first." },
    { p: "**How long.**" },
    {
      lista: [
        "Your phone number, address and directions are deleted automatically 90 days after your order (7 days if it was not confirmed).",
        "Your name, what you ordered and the total stay in our books, as the law requires.",
        "Your questions to the assistant are not stored.",
      ],
    },
    { p: "**On your phone.** So you don't have to type your data every time, this menu remembers it in your browser, only on your phone and only for this restaurant; also your unsent order, your language and your currency. We do not use advertising or tracking cookies. You can delete them anytime with «Delete my data», in «Your data» in the Order view." },
    { p: "**Who else.** We do not sell or lend your data. It is processed on our behalf by Fragmentless and its cloud and artificial intelligence providers, with servers in the United States, who may only use it to provide their service to us. We would only hand it to an authority that requests it as the law provides. When you order, you send us the message from your own WhatsApp: WhatsApp handles it under its own privacy notice." },
    { p: "**Artificial intelligence services.**" },
    {
      lista: [
        "What you write to the menu's assistant is read by an artificial intelligence service to answer you; it is not stored or used to train it. Do not write personal data there.",
        "An artificial intelligence assistant that helps us review our sales may read the name on your order, never your phone number or address; it is not used to train it either.",
      ],
    },
    { p: "**Your rights.** You can ask us to see your data, correct it, delete it or object to our using it, and withdraw your consent. Message us on WhatsApp at {whatsapp} from the number you ordered with (so we know it is you) and tell us what you want. It is free. We will answer within 20 business days and, if it applies, carry it out within the following 15 business days. If you write from another number, we will ask you to confirm it is you." },
    { p: "**If something changes.** Any change to this notice will appear on this same page with its date. If what we use your data for changes, we will ask for your permission again." },
    { p: "**If you believe we are not respecting your rights,** you can turn to Mexico's Secretaría Anticorrupción y Buen Gobierno." },
    { p: "Last updated: {fecha}." },
  ],
};

export type DatosDelAviso = { nombre: string; nombreLegal: string | null; direccion: string | null; whatsapp: string | null };

// Un pedazo de texto: normal, en negritas o el hueco del borrador.
export type Pedazo = { texto: string; como: 'texto' | 'negritas' | 'falta' };

// «55 1234 5678» del aviso se escribe como el resto del menú escribe un teléfono: «551 234 5678».
const telefono = (t: string) => t.replace(/(\d{3})(\d{3})(\d{4})/, '$1 $2 $3');

// Sin dirección en Tu restaurante, la frase «con domicilio en…» no sale («Lo que decidí yo» 7 del aviso).
const SIN_DOMICILIO: Record<Lengua, string> = { es: ', con domicilio en {domicilio},', en: ', located at {domicilio},' };

function llenar(x: string, d: DatosDelAviso, lengua: Lengua): string {
  const responsable = d.nombreLegal
    ? `${d.nombreLegal}${lengua === 'en' ? ', doing business as ' : ', con el nombre comercial '}${d.nombre}`
    : d.nombre;
  return x
    .replaceAll('{responsable}', responsable)
    .replaceAll('{domicilio}', d.direccion ?? '')
    .replaceAll('{whatsapp}', d.whatsapp ? telefono(d.whatsapp) : '')
    .replaceAll('{fecha}', FECHA[lengua]);
}

// Las marcas se leen antes de llenar: un nombre con «**» o «[» se queda como texto.
export function pedazos(plantilla: string, d: DatosDelAviso, lengua: Lengua): Pedazo[] {
  const base = d.direccion ? plantilla : plantilla.replace(SIN_DOMICILIO[lengua], '');
  const out: Pedazo[] = [];
  for (const m of base.matchAll(/\*\*(.+?)\*\*|\[([^\]]+)\]|([^*[]+|[*[])/g)) {
    if (m[1] !== undefined) out.push({ texto: llenar(m[1], d, lengua), como: 'negritas' });
    else if (m[2] !== undefined) out.push({ texto: llenar(m[2], d, lengua), como: 'falta' });
    else out.push({ texto: llenar(m[3], d, lengua), como: 'texto' });
  }
  return out;
}
