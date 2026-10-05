"""
models/saludo_ia.py
El saludo de bienvenida del Agente IA, entero en un solo sitio (28/09,
separado de models/ia_controller.py a pedido del desarrollador): el prompt,
el modelo que lo redacta, la frase de respaldo y la reserva.

MODELO: el saludo usa su propio modelo, gpt-5.6-luna (configurable con
OPENAI_MODEL_SALUDO en el .env). Es una frase corta y decorativa que se pide
en cada visita: ahí el modelo grande no se nota pero sí se paga. La
conversación (models/ia_controller.py) usa gpt-4o y no sabe nada de esto.

RESERVA (28/09, pedido del dueño: "tarda en salir"): siempre hay, a lo
más, UN saludo ya redactado. El primero se pide al entrar al panel
(MainController.mostrar_panel); cuando la vista del agente se lo lleva
(tomar()), se pide el siguiente en segundo plano. Así sale al instante y
sigue siendo distinto en cada visita. Uno basta: una lista de varios solo
gastaría llamadas en saludos que igual se tiran, porque un saludo de
reserva se tira si ya no corresponde: si cambió el nombre (Perfil) o el
momento del día ("Buenos días" redactado a las 11:58 y mostrado a las
12:05).

redactar() y preparar() son bloqueantes (llaman a OpenAI): van siempre por
asyncio.to_thread. tomar() no bloquea (solo lee memoria).
"""
import datetime
import os
import random
import re
import threading
import traceback
from pathlib import Path

from dotenv import load_dotenv
from openai import OpenAI

from models.tiempo import momento_del_dia, saludo_por_hora

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

_MODELO = os.getenv("OPENAI_MODEL_SALUDO", "gpt-5.6-luna")
_cliente_openai = None


def _cliente() -> OpenAI:
    """El cliente de OpenAI, creado la primera vez que hace falta. Sin
    OPENAI_API_KEY lanza RuntimeError: preparar() lo atrapa y la vista cae
    al saludo de respaldo."""
    global _cliente_openai
    if _cliente_openai is None:
        llave = os.getenv("OPENAI_API_KEY")
        if not llave:
            raise RuntimeError("Falta OPENAI_API_KEY en el .env.")
        _cliente_openai = OpenAI(api_key=llave)
    return _cliente_openai


# ---------------------------------------------------------------------------
# Saludo de bienvenida de la pantalla del agente
# ---------------------------------------------------------------------------
# El saludo de agenteIA_view.py lo escribe el modelo, no está hardcodeado —
# lo pidió el desarrollador para que cambie en cada visita, como el de
# Claude. Es la única parte del panel donde el modelo redacta texto libre;
# todo lo demás que dice sale de datos reales.

# Tonos que se sortean en cada llamada. NO son un adorno: sin esto el modelo
# se acomoda en una sola fórmula y devuelve prácticamente la misma frase
# aunque la temperatura esté alta, que es justo lo contrario de lo que se
# pidió. El tono entra al prompt, no al texto.
_TONOS_SALUDO = [
    "cálido y sencillo",
    "breve y directo, casi telegráfico",
    "con energía, como quien tiene ganas de ponerse a trabajar",
    "cercano, de confianza, como un colega que ya lleva rato aquí",
    "sereno y profesional",
    "con curiosidad, invitando a revisar cómo va el negocio",
    "amable y ligero, con un guiño",
]

# Formas que se sortean junto con el tono. Los tonos solos NO alcanzaron:
# en una prueba real contra el modelo, ocho llamadas seguidas devolvieron
# ocho variantes de la MISMA frase ("Ary, es hora de revisar cómo va el
# negocio"), porque una regla del prompt que sugería aludir a revisar el
# negocio acabó siendo, de hecho, la única forma posible. El tono le cambia
# el color a la frase; la forma le cambia la estructura, que es lo que de
# verdad se nota.
_FORMAS_SALUDO = [
    "un saludo por la hora del día seguido de su nombre",
    "una pregunta corta dirigida a esa persona por su nombre",
    "una bienvenida breve, sin pregunta y sin saludo por hora",
    "una frase que muestre que estás listo para ponerte a trabajar",
    "un saludo que aluda al momento del día sin nombrarlo directamente",
    "una frase de reencuentro, como quien saluda al ver llegar a alguien",
    "una invitación a revisar cómo va el negocio, sin decir ninguna cifra",
]

# Tope de largo. Es una línea de Georgia a 40 px en una pantalla de 720:
# más largo que esto se parte en dos renglones y descuadra el bloque.
_MAX_LARGO_SALUDO = 60

# Palabras que le asignarían un género a Ary. El prompt ya pide redactar
# neutro y ayuda, pero NO alcanza: midiéndolo contra el modelo real, 1 de
# cada 8 saludos se colaba igual con un "¿listo para...?". Como no sabemos
# el género de la persona que usa el panel, el saludo que traiga una de
# estas se descarta y entra saludo_de_respaldo(), que siempre es neutro —
# perder uno de cada ocho saludos generados no le cuesta nada a nadie,
# tratar a alguien de "bienvenido" cuando no lo es, sí.
_MARCA_GENERO = re.compile(
    r"\b(bienvenid|list|prepar|cansad|content|ocupad|atent|segur)[oa]s?\b",
    re.IGNORECASE,
)


def saludo_de_respaldo(nombre: str = "Ary", hora: int | None = None) -> str:
    """El saludo cuando el modelo no está disponible (sin OPENAI_API_KEY,
    sin internet, o si devolvió algo inservible).

    No es un mensaje de error ni se ve como tal: el saludo es decorativo,
    así que si falla la llamada el dueño ve una frase normal y nunca se
    entera. Los avisos rojos se reservan para cuando algo que sí importa
    falla (ver _burbuja_error en la vista)."""
    if hora is None:
        hora = datetime.datetime.now().hour
    saludo = saludo_por_hora(hora)
    return random.choice([
        f"{saludo}, {nombre}.",
        f"{saludo}, {nombre}. ¿Qué revisamos?",
        f"Qué gusto verte, {nombre}.",
        f"Aquí andamos, {nombre}.",
        f"¿Cómo va el negocio, {nombre}?",
        f"Cuando tú digas, {nombre}.",
    ])


def _limpiar_saludo(texto: str) -> str:
    """Deja utilizable lo que devolvió el modelo, o cadena vacía si no sirve.

    Quita comillas (las mete a veces aunque se le pida que no), se queda con
    el primer renglón y descarta lo que no quepa en una línea. Vacío = el
    llamador usa saludo_de_respaldo()."""
    renglones = (texto or "").strip().splitlines()
    texto = renglones[0].strip() if renglones else ""
    texto = texto.strip('"').strip("'").strip("«").strip("»").strip()
    if not texto or len(texto) > _MAX_LARGO_SALUDO:
        return ""
    if _MARCA_GENERO.search(texto):
        return ""
    return texto


def redactar(nombre: str) -> str:
    """Una línea de bienvenida para la pantalla del agente, escrita por
    el modelo. Bloqueante: solo la llama preparar(), que va
    siempre por asyncio.to_thread().

    Nunca levanta: si la llamada falla o devuelve algo inservible,
    regresa saludo_de_respaldo(). El saludo es decorativo y el dueño no
    tiene por qué enterarse de que OpenAI no contestó; los avisos rojos
    se reservan para lo que sí importa.

    No lee NADA de la base: es un saludo, no un reporte. Meterle las
    ventas del día costaría 4 consultas y una espera larga cada vez que
    se abre la pantalla, y de paso tentaría al modelo a soltar cifras
    sin que nadie se las pidiera — o a inventarlas, que es peor.
    """
    ahora = datetime.datetime.now()
    momento = momento_del_dia(ahora.hour)
    saludo_hora = saludo_por_hora(ahora.hour)

    system_prompt = (
        "Escribes UNA sola línea de bienvenida para el panel de "
        f"administración de una taquería. Quien la lee es {nombre}, "
        "el dueño del negocio, y acaba de abrir la pantalla de su "
        "asistente de datos.\n\n"
        "REGLAS:\n"
        f"- Una sola línea, máximo {_MAX_LARGO_SALUDO} caracteres. Sin "
        "saltos de línea.\n"
        f"- Menciona a {nombre} por su nombre.\n"
        "- Español de México, natural, ni acartonado ni exagerado.\n"
        "- Sin comillas, sin emojis, sin markdown, sin firmar.\n"
        "- No inventes datos del negocio (ventas, platillos, mesas): no "
        "los tienes. Es un saludo, no un reporte.\n"
        "- No expliques nada ni ofrezcas una lista de cosas que puedes "
        "hacer. Solo el saludo.\n"
        "- NO hables de tacos, comida ni antojos, y no le desees un "
        "buen día de ventas: esto es la pantalla de trabajo donde "
        "revisa sus números, no un anuncio del restaurante.\n"
        "- Evita las fórmulas de porrista (\"¿listo para un gran "
        "día?\", \"¡a darle con todo!\").\n"
        f"- NADA de palabras que marquen género sobre {nombre}: ni "
        "\"bienvenido/bienvenida\" ni \"¿listo/lista?\". Redacta "
        "neutro (\"qué gusto verte\", \"por aquí de nuevo\", "
        "\"empezamos\").\n\n"
        "CONTEXTO DE LA HORA (úsalo solo si te sirve, no es "
        "obligatorio):\n"
        f"- Ahora mismo es de {momento}, así que el saludo por hora que "
        f'corresponde es "{saludo_hora}".\n\n'
        f"FORMA DE ESTA VEZ: {random.choice(_FORMAS_SALUDO)}.\n"
        f"TONO DE ESTA VEZ: {random.choice(_TONOS_SALUDO)}.\n"
        "Respeta esa forma y ese tono: son lo que hace que el saludo "
        "no salga igual cada vez que el dueño abre la pantalla."
    )

    # Dos intentos, no uno. Medido contra el modelo real: 4 de cada 12
    # saludos se descartaban, TODOS por colar un "¿listo para...?" pese a
    # que el prompt lo prohíbe. Un tercio de respaldos era mucho — con el
    # reintento baja a la décima parte, y el tope de dos llamadas evita
    # que un modelo terco deje al dueño esperando.
    texto = ""
    for _ in range(2):
        try:
            respuesta = _cliente().chat.completions.create(
                model=_MODELO,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": "Escribe el saludo."},
                ],
                # Sin temperature: gpt-5.6-luna solo acepta la de por
                # defecto (1). La variedad la dan el tono y la forma
                # sorteados. Y pide max_completion_tokens, no max_tokens.
                max_completion_tokens=40,
            )
            texto = _limpiar_saludo(respuesta.choices[0].message.content)
        except Exception:
            # Sin internet o sin cuota: no tiene caso reintentar.
            break
        if texto:
            break

    return texto or saludo_de_respaldo(nombre, ahora.hour)


# ---------------------------------------------------------------------------
# La reserva
# ---------------------------------------------------------------------------
_candado = threading.Lock()
# (texto, nombre, momento del día) del saludo listo, o None.
_listo = None
# Se enciende al terminar la redacción en curso; None si no hay ninguna.
_en_curso = None


def _momento_actual() -> str:
    return momento_del_dia(datetime.datetime.now().hour)


def tomar(nombre: str) -> str | None:
    """El saludo listo, si hay uno y todavía corresponde (y ya no queda
    en reserva: cada saludo se muestra una sola vez). None si no hay."""
    global _listo
    with _candado:
        listo, _listo = _listo, None
    if listo and listo[1] == nombre and listo[2] == _momento_actual():
        return listo[0]
    return None


def preparar(nombre: str) -> None:
    """Redacta un saludo y lo deja en reserva. Si ya hay uno redactándose,
    espera a que termine en vez de pedir otro; si ya hay uno listo que
    corresponde, no hace nada."""
    global _listo, _en_curso
    with _candado:
        espera = _en_curso
        if espera is None:
            if _listo and _listo[1] == nombre and _listo[2] == _momento_actual():
                return
            _en_curso = threading.Event()
    if espera is not None:
        espera.wait(timeout=30)
        return

    texto = None
    try:
        # redactar() nunca lanza por la red: si falla, devuelve el de respaldo.
        texto = redactar(nombre)
    except Exception:
        # Típicamente la OPENAI_API_KEY faltante: la vista cae al respaldo.
        traceback.print_exc()
    finally:
        with _candado:
            if texto:
                _listo = (texto, nombre, _momento_actual())
            evento, _en_curso = _en_curso, None
        evento.set()
