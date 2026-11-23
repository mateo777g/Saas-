// Los textos de la tarjeta de lealtad en el menú (maqueta v22 aprobada el 23 nov 2026, `vista_menu.py` y `armar.py`), en
// español e inglés, armados con la regla de cada sucursal: sellos o puntos, cuántos pide el premio, desde cuánto suma y el
// premio (un producto de Mi menú o un descuento). El menú no cuenta dinero: los pesos de la regla los puso Don Chuy y los
// dólares del premio los calculó Postgres.
import { dinero } from '@app/lib/formato';
import type { TextosTarjeta } from '@app/diseno/TarjetaLealtad.svelte';
import type { TarjetaDelMenu } from './datos';
import type { Moneda } from './preferencias';
import { monto } from './precio';
import type { Lengua } from './textos';
import type { Tarjeta } from './tarjeta.svelte';

export type Regla = Extract<TarjetaDelMenu, { prendida: true }>;

const MESES = {
  es: ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'],
  en: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
};

// «Hoy», «20 nov» / «Today», «Nov 20», con el día del restaurante.
export function diaCorto(dia: string, hoy: string | null, lengua: Lengua): string {
  if (dia === hoy) return lengua === 'es' ? 'Hoy' : 'Today';
  const [, m, d] = dia.split('-').map(Number);
  return lengua === 'es' ? `${d} ${MESES.es[m - 1]}` : `${MESES.en[m - 1]} ${d}`;
}

export function textosTarjeta(regla: Regla, restaurante: string, lengua: Lengua, moneda: Moneda) {
  const es = lengua === 'es';
  const sellos = regla.forma === 'sellos';
  const meta = regla.meta.toLocaleString('en-US');
  const producto = regla.premio.tipo === 'producto';
  const nombreProducto = (es ? regla.premio.nombre : (regla.premio.nombre_en ?? regla.premio.nombre)) ?? '';
  const pesosPremio = monto(regla.premio.pesos ?? 0, regla.premio.pesos_usd, moneda);
  // «10 sellos» / «100 puntos»
  const lo = (n: string | number) =>
    es ? `${n} ${sellos ? (n === 1 ? 'sello' : 'sellos') : n === 1 ? 'punto' : 'puntos'}` : `${n} ${sellos ? (n === 1 ? 'stamp' : 'stamps') : n === 1 ? 'point' : 'points'}`;
  // El premio en una frase: «tu Gringa gratis» / «$50 de descuento».
  const premio = producto ? (es ? `tu ${nombreProducto} gratis` : `a free ${nombreProducto}`) : es ? `${pesosPremio} de descuento` : `${pesosPremio} off`;
  const premioCorto = producto ? (es ? `${nombreProducto} gratis` : `Free ${nombreProducto}`) : es ? `${pesosPremio} de descuento` : `${pesosPremio} off`;
  const paraTu = producto ? (es ? `tu ${nombreProducto}` : `your ${nombreProducto}`) : es ? `descuento de ${pesosPremio}` : `${pesosPremio} off`;
  // Cómo se gana: «Cada cuenta pagada desde $50 es un sello» / «Un punto por cada $10 que pagas».
  const minimo = regla.minimo ?? 0;
  const comoSuma = sellos
    ? es
      ? minimo > 0
        ? `Cada cuenta pagada desde ${dinero(minimo)} es un sello`
        : 'Cada cuenta pagada es un sello'
      : minimo > 0
        ? `Every paid bill from ${dinero(minimo)} is a stamp`
        : 'Every paid bill is a stamp'
    : es
      ? `Un punto por cada ${dinero(regla.pesos_por_punto ?? 0)} que pagas`
      : `One point for every ${dinero(regla.pesos_por_punto ?? 0)} you pay`;

  const tarjeta: TextosTarjeta = es
    ? {
        etq: 'TARJETA DE LEALTAD',
        premioListo: 'Premio listo',
        de: 'de',
        puntos: 'puntos',
        yaJuntaste: '¡Ya lo juntaste!',
        faltan: (n) => `Te faltan ${n.toLocaleString('en-US')} para ${paraTu}`,
        teEspera: producto ? `Tu ${nombreProducto} te espera` : `Tus ${pesosPremio} de descuento te esperan`,
        voltear: 'Tu tarjeta: tócala para voltearla',
        sub: 'Tarjeta de lealtad',
        sinCamara: 'Sin cámara, diles este código',
        qr: 'Código QR de tu tarjeta',
      }
    : {
        etq: 'LOYALTY CARD',
        premioListo: 'Reward ready',
        de: 'of',
        puntos: 'points',
        yaJuntaste: 'You earned it!',
        faltan: (n) => `${n.toLocaleString('en-US')} more for ${paraTu}`,
        teEspera: producto ? `Your ${nombreProducto} is waiting` : `Your ${pesosPremio} off is waiting`,
        voltear: 'Your card: tap to flip it',
        sub: 'Loyalty card',
        sinCamara: 'No camera? Tell them this code',
        qr: 'Your card QR code',
      };

  return {
    tarjeta,
    tab: es ? 'Tarjeta' : 'Card',
    vistaT: es ? 'Tu tarjeta' : 'Your card',
    sinT: es ? 'Tarjeta de lealtad' : 'Loyalty card',
    datosT: es ? 'Saca tu tarjeta' : 'Get your card',
    existeT: es ? 'Ya hay una tarjeta' : "There's already a card",
    recuperarT: es ? 'Recupera tu tarjeta' : 'Recover your card',
    codigoT: es ? 'Tu código' : 'Your code',
    // La cabeza: «8 de 10 sellos» / «86 puntos», o «Premio listo».
    cuenta: (saldo: number) =>
      sellos ? (es ? `${Math.min(saldo, regla.meta)} de ${meta} sellos` : `${Math.min(saldo, regla.meta)} of ${meta} stamps`) : lo(saldo.toLocaleString('en-US')),
    cuentaListo: es ? 'Premio listo' : 'Reward ready',
    leadCorto: es ? `Junta ${lo(meta)} y llévate ${premio}.` : `Collect ${lo(meta)} and get ${premio}.`,
    comoQ: es ? '¿Cómo funciona?' : 'How does it work?',
    pasos: [
      [es ? 'Pagas y suma' : 'Pay and it adds up', `${comoSuma}${es ? ', aquí o en el local.' : ', here or at the restaurant.'}`],
      [es ? `Juntas ${lo(meta)}` : `Collect ${lo(meta)}`, es ? `Y te llevas ${premio}. Luego la tarjeta sigue.` : `And get ${premio}. Then the card keeps going.`],
      [
        es ? 'Enseñas tu QR' : 'Show your QR',
        es
          ? 'Quien te cobra lo escanea. En tus pedidos de este menú, tocas «Usar mi premio».'
          : 'Whoever charges you scans it. In your orders from this menu, tap «Use my reward».',
      ],
    ] as [string, string][],
    comoH: es ? 'Cómo funciona' : 'How it works',
    como: [
      ['billete', es ? 'Pagas y suma' : 'Pay and it adds up', `${comoSuma}${es ? ', en el local o en tus pedidos de este menú.' : ', at the restaurant or in your orders from this menu.'}`],
      [
        'regalo',
        es ? 'Juntas y ganas' : 'Collect and win',
        es ? `Con ${lo(meta)} te llevas ${premio}. Luego la tarjeta sigue.` : `With ${lo(meta)} you get ${premio}. Then the card keeps going.`,
      ],
      [
        'escanear',
        es ? 'Enseñas tu QR' : 'Show your QR',
        es ? 'Quien te cobra lo escanea. En un pedido de este menú, toca «Usar mi premio».' : 'Whoever charges you scans it. In an order from this menu, tap «Use my reward».',
      ],
      ['reloj', es ? 'Dura mientras compres' : 'It lasts while you buy', es ? 'Si pasas 12 meses sin comprar, se borra sola.' : 'If you go 12 months without buying, it is deleted automatically.'],
    ] as [string, string, string][],
    datosP: es ? 'Sin contraseña: solo tu nombre y tu teléfono.' : 'No password: just your name and phone number.',
    tuNombre: es ? 'Tu nombre' : 'Your name',
    telefono: es ? 'Teléfono' : 'Phone',
    privH: es ? 'Tu privacidad' : 'Your privacy',
    privB: es ? 'Aviso de privacidad' : 'Privacy notice',
    privS: es ? `Cómo usa ${restaurante} tu nombre y tu teléfono, y por cuánto tiempo.` : `How ${restaurante} uses your name and phone number, and for how long.`,
    privIr: es ? 'Ver el aviso' : 'See the notice',
    acepto: es ? ['Acepto el ', 'aviso de privacidad'] : ['I accept the ', 'privacy notice'],
    sacar: es ? 'Sacar mi tarjeta' : 'Get my card',
    yaTienes: es ? ['¿Ya tienes una? ', 'Recupérala'] : ['Already have one? ', 'Recover it'],
    atras: es ? 'Atrás' : 'Back',
    existeP: es
      ? `Este número ya tiene tarjeta: la sacaste en otro celular o borraste tus datos. La pasamos a este con un código que confirma ${restaurante}.`
      : `This number already has a card: you got it on another phone or deleted your data. We move it to this one with a code ${restaurante} confirms.`,
    pasarla: es ? 'Pasarla a este celular' : 'Move it to this phone',
    otraVez: es ? 'Ese no es mi número' : "That's not my number",
    recuperarP: es
      ? `Escribe el número de tu tarjeta. Te damos un código para que ${restaurante} la pase a este celular.`
      : `Type your card's number. We give you a code so ${restaurante} can move it to this phone.`,
    pedir: es ? 'Pedir mi código' : 'Get my code',
    codigoP: (tel: string) =>
      es
        ? [`Enséñaselo a quien te cobra en ${restaurante}, o mándalo por WhatsApp desde el `, tel, '.']
        : [`Show it to whoever charges you at ${restaurante}, or send it by WhatsApp from `, tel, '.'],
    esperando: es ? 'Esperando que lo confirmen' : 'Waiting for them to confirm it',
    vence: es ? 'vence en' : 'expires in',
    vencio: es ? 'Tu código venció. Pide otro.' : 'Your code expired. Get another one.',
    mandar: es ? 'Mandarlo por WhatsApp' : 'Send it by WhatsApp',
    mensajeCodigo: (c: string) => (es ? `Hola, quiero pasar mi tarjeta de lealtad a este celular. Mi código es ${c}` : `Hi, I want to move my loyalty card to this phone. My code is ${c}`),
    pista: es ? 'Tócala para ver tu QR' : 'Tap it to see your QR',
    nuevaB: es ? '¡Listo, ya tienes tu tarjeta!' : 'Done, you have your card!',
    nuevaS: es ? 'Suma sola cada vez que pagas, aquí o en el local.' : 'It adds up every time you pay, here or at the restaurant.',
    pasadaB: es ? '¡Tu tarjeta ya está aquí!' : 'Your card is here!',
    pasadaS: es ? 'Lo que llevas juntado sigue contigo. Tu celular anterior ya no la ve.' : "What you've earned is still yours. Your old phone no longer sees it.",
    listoB: es ? '¡Tu premio está listo!' : 'Your reward is ready!',
    listoS: es ? 'Enséñale tu QR a quien te cobra, o úsalo en tu próximo pedido.' : 'Show your QR to whoever charges you, or use it in your next order.',
    usarlo: es ? 'Usarlo en mi pedido' : 'Use it in my order',
    masH: es ? 'Más de tu tarjeta' : 'More from your card',
    premioA: es ? 'Tu premio' : 'Your reward',
    histA: es ? 'Tu historial' : 'Your history',
    premioB: premioCorto,
    premioS: es
      ? `Con ${lo(meta)}. ${producto ? 'Entra a tu cuenta en $0.' : 'Se resta de tu cuenta.'}`
      : `With ${lo(meta)}. ${producto ? 'It goes on your bill at $0.' : 'It comes off your bill.'}`,
    llevas: (saldo: number) =>
      sellos
        ? es
          ? `${Math.min(saldo, regla.meta)} de ${meta} sellos`
          : `${Math.min(saldo, regla.meta)} of ${meta} stamps`
        : es
          ? `${saldo.toLocaleString('en-US')} de ${meta} puntos`
          : `${saldo.toLocaleString('en-US')} of ${meta} points`,
    falta: (n: number) => (es ? `Te faltan ${n.toLocaleString('en-US')}` : `${n.toLocaleString('en-US')} more`),
    juntaste: (saldo: number) => (sellos ? (es ? `${meta} de ${meta}` : `${meta} of ${meta}`) : lo(saldo.toLocaleString('en-US'))),
    histH: es ? 'Tu historial' : 'Your history',
    histVacio: es ? 'Aquí verás lo que sumas y lo que canjeas.' : "Here you'll see what you earn and redeem.",
    histNoSe: es ? 'No pudimos leer tu historial. Intenta otra vez.' : "We couldn't read your history. Try again.",
    // Cada movimiento en una línea: «En el local», «Pedido por WhatsApp», «Canjeaste tu premio»…
    movimiento: (tipo: string, origen: string | null) => {
      if (tipo === 'compra') return origen === 'menu_en_linea' ? (es ? 'Pedido por WhatsApp' : 'WhatsApp order') : es ? 'En el local' : 'At the restaurant';
      if (tipo === 'canje') return es ? 'Canjeaste tu premio' : 'You redeemed your reward';
      if (tipo === 'devolucion') return es ? 'Tu premio regresó a tu tarjeta' : 'Your reward came back to your card';
      if (tipo === 'regreso') return es ? 'Se canceló un pago' : 'A payment was canceled';
      return es ? 'Tu tarjeta volvió a 0' : 'Your card went back to 0';
    },
    borraB: es ? 'Borrar mi tarjeta' : 'Delete my card',
    borraS: es ? 'Se borra para siempre, con lo que llevas juntado, aquí y en el local.' : "It's deleted for good, with everything you've earned, here and at the restaurant.",
    aLaTarjeta: (n: number) => (es ? `Ir a la tarjeta ${n}` : `Go to card ${n}`),
    borrarT: es ? '¿Borrar tu tarjeta?' : 'Delete your card?',
    borrarP: (saldo: number) =>
      es
        ? `Se borra para siempre, con ${sellos ? `tus ${lo(saldo)}` : `tus ${lo(saldo.toLocaleString('en-US'))}`}, aquí y en ${restaurante}. Un premio que ya usaste se queda en su cuenta.`
        : `It is deleted for good, with your ${lo(saldo.toLocaleString('en-US'))}, here and at ${restaurante}. A reward you already used stays on its bill.`,
    si: es ? 'Sí, borrar' : 'Yes, delete',
    cancelar: es ? 'Cancelar' : 'Cancel',
    listoT: es ? 'Listo' : 'Done',
    borradaP: es ? 'Borramos tu tarjeta. Si un día quieres otra, empiezas desde 0.' : 'We deleted your card. If you want another one someday, you start from 0.',
    cerrar: es ? 'Cerrar' : 'Close',
    noSeLeyo: es ? 'No pudimos leer tu tarjeta. Revisa tu internet e intenta otra vez.' : "We couldn't read your card. Check your internet and try again.",
    otraVezB: es ? 'Intentar otra vez' : 'Try again',
    sinRed: es ? 'No pudimos llegar al servidor. Revisa tu internet e intenta otra vez.' : "We couldn't reach the server. Check your internet and try again.",
    limite: es ? 'Ya lo intentaste varias veces. Espera una hora e intenta otra vez.' : 'You tried several times already. Wait an hour and try again.',
    sinTarjeta: es ? 'Ese número no tiene tarjeta aquí. Revisa el número o saca una.' : "That number doesn't have a card here. Check the number or get one.",
    apagada: es ? `${restaurante} pausó su tarjeta de lealtad: por ahora no suma ni se canjea. Lo que llevas juntado se queda.` : `${restaurante} paused its loyalty card: for now it doesn't add up or redeem. What you've earned stays.`,
    // Tu pedido
    invitaB: es ? 'Saca tu tarjeta de lealtad' : 'Get your loyalty card',
    invitaS: `${lo(meta)} = ${premio}`,
    vacioConB: (saldo: number) => `${es ? 'Tu tarjeta' : 'Your card'} · ${sellos ? (es ? `${Math.min(saldo, regla.meta)} de ${meta} sellos` : `${Math.min(saldo, regla.meta)} of ${meta} stamps`) : es ? `${saldo.toLocaleString('en-US')} de ${meta} puntos` : `${saldo.toLocaleString('en-US')} of ${meta} points`}`,
    vacioListoB: es ? 'Tu premio está listo' : 'Your reward is ready',
    vacioListoS: es ? 'Úsalo en tu próximo pedido' : 'Use it in your next order',
    sec: es ? 'Tu tarjeta' : 'Your card',
    suma: (n: number) => (es ? `Al pagarlo te suma ${lo(n)}` : `Paying it adds ${lo(n)}`),
    noSuma: (min: number) => (es ? `Suma un sello desde ${dinero(min)}` : `It adds a stamp from ${dinero(min)}`),
    lleva: (saldo: number) => {
      const f = Math.max(0, regla.meta - saldo).toLocaleString('en-US');
      const l = sellos ? `${Math.min(saldo, regla.meta)} ${es ? 'de' : 'of'} ${meta}` : `${saldo.toLocaleString('en-US')} ${es ? 'de' : 'of'} ${meta}`;
      return es ? `Llevas ${l}: te faltan ${f} para ${paraTu}` : `You have ${l}: ${f} more for ${paraTu}`;
    },
    listoPedidoS: premioCorto,
    usar: es ? 'Usar mi premio' : 'Use my reward',
    usarS: es ? `Entra a tu cuenta cuando ${restaurante} confirme tu pedido.` : `It goes on your bill when ${restaurante} confirms your order.`,
    premioLinea: es ? 'Premio de tu tarjeta' : 'Your card reward',
    premioChip: es ? 'Premio' : 'Reward',
    premioNoAlcanza: es
      ? `Tu premio es de ${pesosPremio}: tu pedido tiene que valer al menos eso para usarlo.`
      : `Your reward is ${pesosPremio}: your order has to be worth at least that to use it.`,
    // El premio en producto agotado o archivado (`premio.disponible` falso): se queda en la tarjeta.
    premioAgotado: es ? `Tu ${nombreProducto} se acabó por ahora: úsalo en otro pedido.` : `Your ${nombreProducto} is sold out for now: use it in another order.`,
  };
}

export type TextosDeTarjeta = ReturnType<typeof textosTarjeta>;

// Lo de la tarjeta que ve Tu pedido. `saldo` null: este celular no tiene tarjeta en esta sucursal.
export type DeLaTarjeta = { regla: Regla; tt: TextosDeTarjeta; saldo: number | null; listo: boolean };

// La tarjeta de Rosa, la del teléfono de «Tu tarjeta» en el panel (maqueta v22: 8 de 10 sellos, 86 de 100 puntos), a
// escala de la regla, con el historial de la maqueta (hoy, 20, 18 y 15 nov, y el premio canjeado el 12) contado desde el día
// del restaurante. Nunca toca la red.
export function tarjetaDeRosa(regla: Regla, hoy: string): Tarjeta {
  const sellos = regla.forma === 'sellos';
  const saldo = sellos ? Math.max(1, regla.meta - 2) : Math.round(regla.meta * 0.86);
  const antes = (dias: number) => {
    const d = new Date(`${hoy}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() - dias);
    return d.toISOString().slice(0, 10);
  };
  const puntos = [11, 9, 12, 8].map((p) => Math.max(1, Math.round((p / 100) * regla.meta)));
  const compras = [0, 3, 5, 8].map((dias, i) => ({
    tipo: 'compra',
    cantidad: sellos ? 1 : puntos[i],
    dia: antes(dias),
    origen: i === 0 ? 'menu_en_linea' : null,
  }));
  return {
    nombre: 'Rosa Ramírez',
    telefono: '2229876543',
    saldo,
    premio_listo: false,
    sacada: antes(60),
    ultima_compra: hoy,
    movimientos: [...compras, { tipo: 'canje', cantidad: -regla.meta, dia: antes(11), origen: 'menu_en_linea' }],
  };
}
