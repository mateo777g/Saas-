// Los pasos que ve Don Chuy mientras el agente piensa (planes/trabajo/estrella/worker.md). Cada paso
// es algo que pasa de verdad: el que no pasa, no sale. Las fechas en palabras son una copia de
// privado.periodo, porque el paso sale antes de llamar a Postgres; probar_pasos.mjs las compara con
// las de Postgres, letra por letra. Lo que encontró cada herramienta («Lo que leí») sí sale de allá.
import { EN_CUANTO, JUNTAR } from './porPartes';
import type { Avisar } from './porPartes';

export type Paso = { icono: string; texto: string; listo: string };

export const LEYENDO: Paso = { icono: 'globito', texto: 'Leyendo tu pregunta…', listo: 'Leí tu pregunta' };
const ESCRIBIENDO: Paso = { icono: 'crear', texto: 'Escribiendo la respuesta…', listo: 'Escribí la respuesta' };
const TABLA: Paso = { icono: 'tabla', texto: 'Haciendo la tabla…', listo: 'Hice la tabla' };

// Un nombre más largo que esto no se escribe en el paso: lo escribió el modelo y es solo un texto.
const LARGO_NOMBRE = 40;

export class Pasos {
  private siguiente = 1;
  private dichos = new Map<number, string>();

  constructor(private avisar: Avisar) {}

  // Regresa su número, o null si ese texto ya salió en esta pregunta: trabaja sin otro paso.
  abrir(paso: Paso | null): number | null {
    if (!paso || [...this.dichos.values()].includes(paso.texto)) return null;
    const id = this.siguiente++;
    this.dichos.set(id, paso.texto);
    this.avisar({ tipo: 'paso', id, ...paso });
    return id;
  }

  cerrar(id: number | null): void {
    if (id !== null) this.avisar({ tipo: 'hecho', id });
  }

  // El paso no pasó de verdad: se va de la lista y, si el modelo corrige, puede volver a salir.
  quitar(id: number | null): void {
    if (id === null) return;
    this.dichos.delete(id);
    this.avisar({ tipo: 'quita', id });
  }
}

// Lo que va escribiendo el modelo en una vuelta: la primera letra abre «Escribiendo…» y un renglón
// que empieza con «|» abre «Haciendo la tabla…». Va letra por letra y no guarda el texto, porque se
// llama con cada parte. Ya que empezó, las partes pueden juntarse: «Haciendo la tabla…» sale cuando
// mucho un segundo tarde. Ya con la tabla, no vuelve a leer.
export class Escritura {
  private abierto: number | null = null;
  private empezo = false;
  private alInicioDeRenglon = true;

  constructor(
    private pasos: Pasos,
    private alEmpezar: () => void,
  ) {}

  parte(texto: string): number | null {
    for (let i = 0; i < texto.length; i++) {
      const letra = texto[i];
      if (letra === '\n') {
        this.alInicioDeRenglon = true;
        continue;
      }
      if (this.alInicioDeRenglon && (letra === ' ' || letra === '\t' || letra === '\r')) continue;
      if (!this.empezo) {
        this.empezo = true;
        this.alEmpezar();
        if (letra !== '|') this.abierto = this.pasos.abrir(ESCRIBIENDO);
      }
      if (this.alInicioDeRenglon && letra === '|') {
        this.pasos.cerrar(this.abierto);
        this.abierto = this.pasos.abrir(TABLA);
        return null;
      }
      this.alInicioDeRenglon = false;
    }
    return this.empezo ? JUNTAR : EN_CUANTO;
  }

  // El modelo pidió una herramienta en la misma vuelta: lo que escribió no era la respuesta.
  quitar(): void {
    this.pasos.quitar(this.abierto);
    this.abierto = null;
  }
}

const buscar = (que: string): Paso => ({ icono: 'lupa', texto: `Buscando ${que}…`, listo: `Busqué ${que}` });

const GRUPOS: Record<string, string> = {
  categoria: ', por categoría',
  mesa: ', por mesa',
  mesero: ', por mesero',
  hora: ', por hora',
  dia_semana: ', por día de la semana',
  dia: ', día por día',
  semana: ', semana por semana',
  mes: ', mes por mes',
};

const LO_QUE_NO_ES_VENTA: Record<string, string> = {
  cancelaciones: 'las cancelaciones',
  descuentos: 'los descuentos',
  propinas: 'las propinas',
  pagos_cancelados: 'los pagos cancelados',
};

// El paso de una herramienta con lo que pidió el modelo; `hoy` es el día de negocio del restaurante.
// Si las fechas vienen mal, sale sin ellas: quien rechaza esa llamada es Postgres. Sin herramienta
// conocida no hay paso.
export function pasoDeHerramienta(nombre: string, a: Record<string, unknown>, hoy: string | null): Paso | null {
  const de = fechasDe(a.desde, a.hasta, hoy);
  if (nombre === 'resumen') return buscar(`las ventas${de}`);
  if (nombre === 'ranking') {
    if (a.agrupar_por !== 'producto') return buscar(`las ventas${de}${GRUPOS[String(a.agrupar_por)] ?? ''}`);
    if (a.orden === 'menor') return buscar(`lo menos vendido${de}`);
    const esTop = (a.orden === undefined || a.orden === 'mayor') && Number.isInteger(a.limite) && Number(a.limite) >= 1 && Number(a.limite) <= 10;
    return buscar(esTop ? `lo más vendido${de}` : `las ventas${de}`);
  }
  if (nombre === 'comparar') {
    const b = fechas(a.b_desde, a.b_hasta, hoy, 'solo');
    const antes = fechas(a.a_desde, a.a_hasta, hoy, 'solo');
    const que = b && antes ? ` ${loDel(b)} contra ${loDel(antes)}` : ' las ventas';
    return { icono: 'lupa', texto: `Comparando${que}…`, listo: `Comparé${que}` };
  }
  if (nombre === 'detalle') {
    if (Number.isInteger(a.folio) && Number(a.folio) >= 1) return buscar(`la cuenta con folio ${a.folio}`);
    const estado = a.estado === 'abiertas' || a.estado === 'canceladas' ? ` ${a.estado}` : '';
    return buscar(`las cuentas${estado}${de}${dondeYQuien(a.mesa, a.mesero)}`);
  }
  if (nombre === 'proyeccion_mes') {
    const mes = hoy && leerDia(hoy) !== null ? nombreMes(leerDia(hoy) as number) : 'el mes';
    return { icono: 'lupa', texto: `Calculando cómo cierra ${mes}…`, listo: `Calculé cómo cierra ${mes}` };
  }
  if (nombre === 'cancelaciones_descuentos_propinas') {
    const que = LO_QUE_NO_ES_VENTA[String(a.ver)];
    return que ? buscar(`${que}${de}`) : null;
  }
  return null;
}

function dondeYQuien(mesa: unknown, mesero: unknown): string {
  let texto = '';
  if (typeof mesa === 'string' && mesa.trim() && mesa.trim().length <= LARGO_NOMBRE) {
    const limpia = mesa.trim();
    const minusculas = limpia.toLowerCase();
    texto += minusculas === 'para llevar' || minusculas === 'a domicilio' ? `, ${minusculas}` : `, en ${limpia}`;
  }
  if (typeof mesero === 'string' && mesero.trim() && mesero.trim().length <= LARGO_NOMBRE) texto += `, de ${mesero.trim()}`;
  return texto;
}

// En «comparar», como en «Lo que leí»: «lo del 12 al 15 de octubre».
function loDel(texto: string): string {
  return texto.startsWith('del ') ? `lo ${texto}` : texto;
}

function fechasDe(desde: unknown, hasta: unknown, hoy: string | null): string {
  const texto = fechas(desde, hasta, hoy, 'de');
  return texto ? ` ${texto}` : '';
}

function fechas(desde: unknown, hasta: unknown, hoy: string | null, forma: 'solo' | 'de'): string | null {
  if (typeof desde !== 'string' || typeof hasta !== 'string' || !hoy) return null;
  const d = leerDia(desde);
  const h = leerDia(hasta);
  const dia = leerDia(hoy);
  return d === null || h === null || dia === null ? null : periodo(d, h, dia, forma);
}

// ─── La copia de privado.periodo ──────────────────────────────────────────────

const DIA = 86_400_000;
const DIAS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

// Un día es su medianoche en UTC, para que restar días nunca dependa de un horario de verano.
function leerDia(texto: string): number | null {
  const partes = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto);
  if (!partes) return null;
  const [anio, mes, dia] = [Number(partes[1]), Number(partes[2]), Number(partes[3])];
  const fecha = Date.UTC(anio, mes - 1, dia);
  const d = new Date(fecha);
  return d.getUTCFullYear() === anio && d.getUTCMonth() === mes - 1 && d.getUTCDate() === dia ? fecha : null;
}

const anioDe = (d: number) => new Date(d).getUTCFullYear();
const mesDe = (d: number) => new Date(d).getUTCMonth();
const numeroDe = (d: number) => new Date(d).getUTCDate();
const nombreMes = (d: number) => MESES[mesDe(d)];
const nombreDia = (d: number) => DIAS[(new Date(d).getUTCDay() + 6) % 7];
const primeroDelMes = (d: number) => Date.UTC(anioDe(d), mesDe(d), 1);
const finDelMes = (d: number) => Date.UTC(anioDe(d), mesDe(d) + 1, 0);

// «17 de octubre», con el año solo si no es el de hoy. `hoy` null: siempre con el año.
function diaYMes(d: number, hoy: number | null): string {
  return `${numeroDe(d)} de ${nombreMes(d)}${hoy === null || anioDe(d) !== anioDe(hoy) ? ` de ${anioDe(d)}` : ''}`;
}

export function periodo(d: number, h: number, hoy: number, forma: 'solo' | 'de'): string {
  const lunes = hoy - ((new Date(hoy).getUTCDay() + 6) % 7) * DIA;
  let texto: string;
  let tipo: 'fijo' | 'dia' | 'rango' = 'fijo';
  if (d === h && d === hoy) {
    texto = 'hoy';
  } else if (d === h && d === hoy - DIA) {
    texto = 'ayer';
  } else if (d === h) {
    texto = `el ${nombreDia(d)} ${diaYMes(d, hoy)}`;
    tipo = 'dia';
  } else if (d === lunes && h >= hoy && h <= lunes + 6 * DIA) {
    texto = 'esta semana';
  } else if (d === lunes - 7 * DIA && h === lunes - DIA) {
    texto = 'la semana pasada';
  } else if (d === primeroDelMes(hoy) && h >= hoy && h <= finDelMes(hoy)) {
    texto = 'este mes';
  } else if (d === primeroDelMes(d) && h === finDelMes(d)) {
    texto = `${nombreMes(d)}${anioDe(d) !== anioDe(hoy) ? ` de ${anioDe(d)}` : ''}`;
  } else if (
    d === Date.UTC(anioDe(d), 0, 1) &&
    (h === Date.UTC(anioDe(d), 11, 31) || (anioDe(d) === anioDe(hoy) && h >= hoy && anioDe(h) === anioDe(hoy)))
  ) {
    texto = anioDe(d) === anioDe(hoy) ? 'este año' : String(anioDe(d));
  } else if (anioDe(d) === anioDe(h) && mesDe(d) === mesDe(h)) {
    texto = `del ${numeroDe(d)} al ${diaYMes(h, hoy)}`;
    tipo = 'rango';
  } else if (anioDe(d) === anioDe(h)) {
    texto = `del ${numeroDe(d)} de ${nombreMes(d)} al ${diaYMes(h, hoy)}`;
    tipo = 'rango';
  } else {
    texto = `del ${diaYMes(d, null)} al ${diaYMes(h, null)}`;
    tipo = 'rango';
  }
  if (forma === 'solo') return texto;
  if (tipo === 'dia') return `del ${texto.slice(3)}`;
  return tipo === 'rango' ? texto : `de ${texto}`;
}
