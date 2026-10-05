"""
views/agenteIA_view.py
El Agente IA con el diseño nuevo (28/09): la maqueta aprobada está en
panel/diseno/maquetas-agente-ia/ y sus reglas en planes/plan panel.txt
("DISEÑO MANCHAS + VIDRIO"). Las piezas compartidas (vidrio, letras, iconos)
viven en views/diseno.py y los colores en views/tema.py (D.*).

La vista no pinta fondo: detrás está el fondo de manchas de MainController.
Encima van la barra de arriba (vidrio) y el cuerpo, que tiene dos estados:

- BIENVENIDA: una tarjeta de vidrio centrada con la fecha, el saludo en dos
  renglones, la caja de texto y las tres ideas.
- CONVERSACIÓN: un panel de vidrio con los mensajes y la caja anclada abajo,
  y a su derecha la tarjeta "LO QUE LEÍ PARA RESPONDER".
"""
import asyncio
import datetime
import math
import re
import traceback

import flet as ft

from models import perfil, saludo_ia
from models.ia_controller import IAController
from views.diseno import (ALTO_BARRA_SUPERIOR, MARGEN, boton, etiqueta, icono, punto, texto,
                          vidrio)
from views.piezas import DIAS, MESES
from views.tema import D, VERDE

# Lo que miden las piezas de la maqueta.
ANCHO_BIENVENIDA = 780      # la tarjeta de vidrio de la bienvenida (padding 40: 700 útiles)
ANCHO_CHAT = 732            # la columna de mensajes dentro del panel de conversación
ANCHO_CAJA_CHAT = 764       # la caja de texto anclada abajo del panel
ANCHO_LEIDO = 320           # la tarjeta "LO QUE LEÍ PARA RESPONDER"
TAMANO_SALUDO = 50

# El tope de ancho de la burbuja del dueño (460 en la maqueta) y el hueco que
# se le deja a la derecha a la respuesta.
HUECO_USUARIO = ANCHO_CHAT - 460
HUECO_IA = 0

# Renglones que muestra la caja de texto antes de necesitar el botón de
# desplegar, y los que muestra ya desplegada.
LINEAS_COLAPSADA = 4
LINEAS_EXPANDIDA = 14
ANCHO_BOTON_EXPANDIR = 30

# El logo animado que se ve mientras la IA piensa. Es UN archivo WebP
# animado (36 cuadros, 70 ms cada uno, ~2.5 s por vuelta, con transparencia
# real), no los 36 SVG sueltos, y ese cambio arregló un fallo de verdad.
#
# ⚠️ NO lo regreses a "un SVG por cuadro con un temporizador de python".
# Así estaba, y en la máquina del desarrollador la animación se veía
# CONGELADA. Medido en un video suyo de la app real: el logo estuvo 3.87 s
# en pantalla y solo cambió de dibujo 3 veces —con un hueco de 1.70 s— donde
# tocaban ~55. La causa no es el diseño ni el tamaño: con un cuadro por
# archivo, python tiene que empujar 14 actualizaciones por segundo al
# cliente, y eso es lo primero que se muere cuando la máquina está ocupada,
# que es SIEMPRE en esta pantalla — mientras el logo gira, el mismo proceso
# está leyendo 4 tablas de Supabase, armando el prompt y esperando a OpenAI.
# Reproducido y medido: en reposo repintaba a 12.6 cuadros/s, con la CPU
# ocupada bajaba a 7.4, y en la máquina del desarrollador (más cargada, con
# la ventana maximizada y grabando video) a ~1.
#
# Con el WebP animado el cliente reproduce la animación SOLO y python no
# manda un solo cuadro: medido igual, 13.6 cuadros/s en reposo y 13.2 con la
# CPU al tope, o sea que ya no le afecta. De paso desaparecieron el
# threading.Timer, el .start()/.stop() y la trampa de autoplay.
#
# El archivo sale de herramientas/generar_logo_pensando.py, uno por tema
# (D.logo_pensando): es el MISMO logo de cada respuesta (_logo_saludo), del
# mismo color y en el mismo hueco, partiéndose en sus piezas. Su primer cuadro
# es el logo entero, así que al llegar la respuesta el cambio no brinca.

# El logo fijo del saludo y de cada respuesta: el de trazo grueso, sin cuadro,
# naranja en el tema claro y azul en el oscuro (D.logo_simbolo, sale de
# herramientas/vectorizar_logo.py). El SVG llena su caja de borde a borde; el
# viejo (frame35) traía aire alrededor, por eso se pinta a 3/4 del hueco.
def _logo_saludo(hueco: int) -> ft.Container:
    lado = round(hueco * 0.75)
    return ft.Container(width=hueco, height=hueco, alignment=ft.Alignment.CENTER,
                        content=ft.Image(src=D.logo_simbolo, width=lado, height=lado))

# El hueco del logo de cada respuesta y del de "Pensando...", que va en el
# mismo lugar: los dos a 42, el tamaño que ya tenía "Pensando..." (el
# desarrollador lo quería así, no al revés). Y el texto de "Pensando...".
HUECO_LOGO_RESPUESTA = 42
# Renglón de la respuesta: Jakarta 16 con interlineado 1.6. El texto se baja
# lo necesario para que su primer renglón quede centrado con el logo.
_ALTO_RENGLON_RESPUESTA = 16 * 1.6
TAMANO_TEXTO_PENSANDO = 14

# Texto de reposo de la caja, en cada estado. Es constante porque también lo
# restaura _hover_idea() al salirse el cursor de una idea.
HINT_ENTRADA = "Pregunta lo que quieras de tu negocio…"
HINT_CHAT = "Sigue preguntando… por ejemplo, ¿y ayer?"

# El selector de periodo de la caja. Lo elegido se le dice al modelo SOLO
# cuando la pregunta no trae su propio periodo (ver _enviar_mensaje): "Hoy"
# no convierte "¿qué se vende más los viernes?" en una pregunta de hoy.
PERIODOS = (
    ("Hoy", "HOY"),
    ("Semana", "ESTA SEMANA"),
    ("Mes", "ESTE MES"),
)

# Los tres atajos. La estructura es la de cualquier chat de IA grande: un
# rótulo corto que se lee de un vistazo, y detrás un prompt largo y preciso
# que el dueño nunca tendría que escribir.
#
# ⚠️ LOS TRES PIDEN EL DESGLOSE POR PRODUCTO Y PROHÍBEN EL DE MESA, a
# propósito. El agente sabe contestar las dos cosas —_resumen_calculado()
# le manda los dos desgloses ya sumados—, pero estos atajos son para la
# pregunta que el dueño se hace de verdad: qué se vendió y cuánto dejó cada
# producto. Por mesa es un dato de operación, no de negocio, y aquí sobra.
#
# ⚠️ LA PRIMERA FRASE DE CADA PROMPT SE BASTA SOLA, y eso no es estilo: el
# prompt se asoma en la caja de texto mientras el cursor está encima de la
# idea (ver _hover_idea), y ahí se corta a UN renglón —unos 74 caracteres—
# porque hint_max_lines=1. Si la parte que dice de qué es el reporte cayera
# en la segunda frase, el dueño vería un adelanto que no dice nada. Si
# alguna vez se reescriben, que lo importante siga cabiendo al principio.
#
# ⚠️ "EL TOTAL NO VA DENTRO DE LA TABLA" TAMPOCO ES UNA MANÍA DE FORMATO, y
# se ganó a pulso. Sin esa frase el modelo cierra la tabla con una fila
# **Total** y, para llenarla, suma la columna de unidades ÉL MISMO: probado
# contra la base real, contestó "21 unidades" donde eran 25 — y 21 resultó
# ser el total de AYER, o sea que ni siquiera se equivocó al sumar, se
# equivocó de periodo y el número se veía perfectamente creíble. El dinero
# de esa misma respuesta sí venía bien, que es lo peor del caso: falla solo
# en la columna que nadie revisa. Sacando el total de la tabla, el modelo ya
# no tiene ninguna columna que sumar y solo copia el total del periodo, que
# le llega precalculado. Del lado de Python el respaldo también está puesto
# (ver el renglón TOTAL POR PRODUCTO en _bloque_desglose de
# models/ia_controller.py), pero esta frase es la que evita que lo necesite.
# Y de paso es lo que pidió el dueño: la tabla y, debajo, cuánto se hizo.
#
# El periodo va en MAYÚSCULAS dentro del prompt porque es lo único que
# cambia entre los tres y es lo que el modelo no debe confundir; el resto
# del texto es idéntico a propósito, para que las tres respuestas salgan
# con la misma forma y se puedan comparar entre sí.
#
# "descripcion" es el renglón gris de la tarjeta y "seguimiento" los dos
# botones que salen bajo la respuesta de esa idea (cada uno manda su texto
# como pregunta nueva).
_FORMA_REPORTE = (
    "en tabla y con el total al final. Ponme el producto, cuántas unidades se "
    "vendieron y cuánto dinero representa cada uno, de mayor a menor. El total "
    "no va dentro de la tabla: va debajo, en un renglón de texto. No lo "
    "desgloses por mesa."
)
IDEAS = (
    {
        "icono": "hoy",
        "titulo": "Qué se vendió hoy",
        "descripcion": "Por producto, con el total al final.",
        "prompt": f"Ventas de HOY por producto, {_FORMA_REPORTE}",
        "seguimiento": (("Compárala con ayer", "Compara lo de hoy con lo de ayer, por producto."),
                        ("Ver la semana", f"Ventas de ESTA SEMANA por producto, {_FORMA_REPORTE}")),
    },
    {
        "icono": "semana",
        "titulo": "Reporte de la semana",
        "descripcion": "Lunes a hoy, producto por producto.",
        "prompt": f"Ventas de ESTA SEMANA por producto, {_FORMA_REPORTE}",
        "seguimiento": (("Compárala con la pasada", "Compara esta semana con la semana pasada, por producto."),
                        ("Ver el mes", f"Ventas de ESTE MES por producto, {_FORMA_REPORTE}")),
    },
    {
        "icono": "mes",
        "titulo": "Reporte del mes",
        "descripcion": "Lo que más dejó este mes.",
        "prompt": f"Ventas de ESTE MES por producto, {_FORMA_REPORTE}",
        "seguimiento": (("Compáralo con el pasado", "Compara este mes con el mes pasado, por producto."),
                        ("Ver hoy", f"Ventas de HOY por producto, {_FORMA_REPORTE}")),
    },
)

def _icono(nombre, tamano: int, color: str) -> ft.Icon:
    """Un ft.Icon nuevo, para ASIGNARLO a .content del botón que lo usa.

    ⚠️ No cambies un icono ya montado con `mi_icono.name = ft.Icons.OTRO`:
    en esta versión de flet esa mutación NO se propaga al cliente — el
    icono se queda dibujado como estaba, para siempre y sin ningún error.
    Se comprobó con dos iconos lado a lado en la ventana real: al que se
    le mutó `.name` no se movió, y el que se reemplazó entero sí cambió.
    (Las propiedades del Container que lo envuelve —bgcolor, border_radius—
    sí se propagan, lo que hace el fallo todavía más confuso: medio botón
    cambia y el otro medio no.) Por eso los dos botones de la caja de
    texto reemplazan su `.content` en vez de mutar el icono; el de
    desplegar arrastraba justo ese bug y nunca llegaba a mostrar
    UNFOLD_LESS al expandirse.
    """
    return ft.Icon(nombre, size=tamano, color=color)


# Hueco entre bloques de markdown (parrafo -> tabla -> lista...). Es el
# block_spacing de _estilo_markdown() sacado a constante porque desde que
# la respuesta se pinta renglon por renglon hay un SEGUNDO sitio que lo
# necesita: _partir_en_renglones() se lo pone a mano a cada renglon que
# empieza un bloque nuevo, que es justo lo que hace que la respuesta
# partida quede pintada igual que la entera. Si cambia aqui, cambia en los
# dos lados a la vez; escrito a mano en cada sitio, no.
ESPACIO_BLOQUE = 12

# Como aparece una respuesta: RENGLON POR RENGLON, de arriba hacia abajo,
# cada uno con un fundido corto, en vez de que el mensaje entero se plante
# de golpe. Lo pidio el desarrollador el 2026-09-06 con un video de Claude
# al lado, y preciso dos veces el detalle que define todo lo demas: la
# animacion va por renglones -"sale un renglon con la animacion, se baja al
# otro y asi"-, no es el bloque completo apareciendo de una. (Primero dijo
# "difuminado"; luego aclaro que se referia a la APARICION de las letras,
# no a un desenfoque. Un desenfoque de verdad si se puede en este flet -un
# Container con blur encima difumina lo que queda debajo, se probo y
# funciona- pero cuesta un BackdropFilter por renglon y no es lo que se
# pidio.)
#
# Los tres numeros estan amarrados entre si y no se tocan por separado:
#
# - PASO_APARICION es cada cuanto ARRANCA el siguiente renglon.
# - DURACION_APARICION es lo que tarda UNO en aparecer, y es a proposito
#   como seis veces el paso: asi siempre hay varios renglones fundiendose
#   al mismo tiempo y la respuesta se lee "de corrido", que es como la
#   pidio el desarrollador. Igualarlos la convertiria en una fila de
#   parpadeos sueltos.
# - PASOS_MAXIMOS es el tope de avisos que python le manda al cliente por
#   respuesta. Con el paso fijo son ~18 por segundo pase lo que pase, pero
#   una respuesta larga tardaria eternidades en acabar de salir; pasado el
#   tope los renglones se revelan de dos en dos o de tres en tres, asi que
#   ninguna respuesta tarda mas de ~1.8 s en terminar de aparecer.
#
# La leccion del logo de "Pensando..." (ver D.logo_pensando) NO aplica
# aqui, aunque el ritmo se parezca: ahi python empujaba 14 CUADROS por
# segundo y la animacion se congelaba con la maquina ocupada. Aqui python
# solo manda el disparo de cada renglon y quien interpola el fundido es el
# cliente, con animate_opacity. Si un aviso llega tarde, ese renglon
# arranca tarde pero aparece igual de suave, nunca se queda a medias. Y
# llega cuando la respuesta YA esta en la mano, o sea con el proceso
# desocupado, no mientras se leen 4 tablas y se espera a OpenAI.
PASO_APARICION = 0.055
DURACION_APARICION = 340
PASOS_MAXIMOS = 32

# Lo que sube cada renglon mientras aparece, en fraccion de su propia
# altura (asi mide el offset de flet). Los renglones de texto suben un
# pelin; las tablas, las citas y el codigo NO se mueven, solo se funden:
# al ser mucho mas altos esa misma fraccion los haria dar un brinco de mas
# de 30 px en vez del empujoncito de 6 que se ve en una linea suelta.
SUBIDA_APARICION = 0.25


_RE_TABLA = re.compile(r"^\s*\|")
_RE_TITULO = re.compile(r"^\s{0,3}#{1,6}\s")
_RE_CERCA = re.compile(r"^\s*(```|~~~)")
_RE_CITA = re.compile(r"^\s*>")
_RE_LISTA = re.compile(r"^\s*([-*+]|\d+[.)])\s")
# La fila de guiones que va debajo del encabezado de una tabla. Existe
# porque en GFM los pipes de los extremos son OPCIONALES: el modelo puede
# contestar "Producto | Importe" y debajo "--- | ---", sin un solo pipe al
# principio de renglon. Reconocer la tabla solo por _RE_TABLA dejaria esa
# variante partida renglon por renglon, o sea pintada como basura.
_RE_SEP_TABLA = re.compile(r"^\s*\|?[\s:|-]*-[\s:|-]*\|[\s:|-]*$")
# Un renglon sangrado, que en markdown NO empieza algo nuevo sino que
# continua lo de arriba: una vineta anidada, o un bloque de codigo con
# sangria. Se pega al trozo anterior en vez de volverse uno propio —
# suelto perderia la sangria, y con 4 espacios flutter lo pintaria como
# un bloque de codigo en medio de una lista.
_RE_SANGRIA = re.compile(r"^ {2,}\S")


def _partir_en_renglones(texto: str) -> list:
    """Parte la respuesta en los trozos que van a aparecer uno por uno.

    Devuelve (markdown, hueco_arriba, es_bloque) por trozo. Cada trozo se
    pinta con su PROPIA ft.Markdown, y de ahi salen las dos reglas que
    tiene esta funcion:

    1. UN RENGLON DEL TEXTO = UN TROZO... salvo lo que no se puede partir.
       Una tabla a la que le quites el encabezado deja de ser una tabla y
       se pinta como un monton de pipes; un bloque de codigo sin su cerca
       de cierre, igual. Tablas, codigo y citas se juntan enteros y
       aparecen de un solo fundido - que ademas es lo que se ve bien: una
       tabla saliendo fila por fila se lee como un error de pintado, no
       como una animacion.

    2. EL HUECO SE REPARTE A MANO. Una sola ft.Markdown mete su
       block_spacing entre bloques y NADA entre los renglones de un mismo
       parrafo (los saltos suaves, ver soft_line_break en _burbuja_ia).
       Partida en trozos ese reparto se pierde, asi que aqui se devuelve
       renglon por renglon: ESPACIO_BLOQUE cuando el trozo abre bloque
       nuevo -hubo linea en blanco, o es titulo/lista/tabla/codigo/cita- y
       0 cuando solo continua el parrafo de arriba.

       Los renglones de LISTA cuentan como bloque, y eso NO es un detalle
       de estilo: flutter le mete su block_spacing a cada vineta, asi que
       sin esta regla las listas salian 12 px mas juntas que hoy. Se cacho
       midiendo, no leyendo.

    Que el reparto sea exacto es lo unico que sostiene el cambio: la
    respuesta partida y la entera se renderizaron a 650 px (el ancho real
    de la conversacion) y salieron IDENTICAS pixel por pixel -
    ImageChops.difference dio bbox None, no "casi"-, con una muestra que
    traia titulo, parrafo, tabla (con pipes y sin ellos), negritas,
    vinetas, vinetas anidadas, lista numerada, saltos suaves, cita, regla
    horizontal y codigo. Si algun dia tocas esta funcion, esa es la prueba
    que hay que repetir.
    """
    lineas = texto.replace("\r\n", "\n").split("\n")
    unidades = []
    i = 0
    hubo_blanco = False
    anterior_bloque = False

    while i < len(lineas):
        linea = lineas[i]
        if not linea.strip():
            hubo_blanco = True
            i += 1
            continue

        if unidades and not hubo_blanco and _RE_SANGRIA.match(linea):
            # Continuacion sangrada: se pega al trozo de arriba.
            trozo_previo, hueco_previo, bloque_previo = unidades[-1]
            unidades[-1] = (trozo_previo + "\n" + linea, hueco_previo, bloque_previo)
            i += 1
            continue

        if _RE_CERCA.match(linea):
            # Codigo: de la cerca de apertura a la de cierre. Si el modelo
            # se comio la de cierre, se lleva lo que queda y no se cuelga.
            juntas = [linea]
            i += 1
            while i < len(lineas):
                juntas.append(lineas[i])
                cerro = bool(_RE_CERCA.match(lineas[i]))
                i += 1
                if cerro:
                    break
            trozo, bloque = "\n".join(juntas), True
        elif _RE_TABLA.match(linea) or (
            "|" in linea
            and i + 1 < len(lineas)
            and _RE_SEP_TABLA.match(lineas[i + 1])
        ):
            # Tabla: se junta mientras los renglones lleven pipe, no
            # mientras EMPIECEN con pipe (ver _RE_SEP_TABLA).
            juntas = []
            while i < len(lineas) and lineas[i].strip() and "|" in lineas[i]:
                juntas.append(lineas[i])
                i += 1
            trozo, bloque = "\n".join(juntas), True
        elif _RE_CITA.match(linea):
            juntas = []
            while i < len(lineas) and _RE_CITA.match(lineas[i]):
                juntas.append(lineas[i])
                i += 1
            trozo, bloque = "\n".join(juntas), True
        else:
            trozo = linea
            bloque = bool(_RE_TITULO.match(linea)) or bool(_RE_LISTA.match(linea))
            i += 1

        hueco = ESPACIO_BLOQUE if (hubo_blanco or bloque or anterior_bloque) else 0
        if not unidades:
            # El primer trozo pega con el padding de la burbuja; un hueco
            # aqui lo despegaria del "Pensando..." al que reemplaza.
            hueco = 0
        unidades.append((trozo, hueco, bloque))
        hubo_blanco = False
        anterior_bloque = bloque

    return unidades



# La letra de las respuestas: la misma Plus Jakarta Sans del diseño, 16 con
# interlineado 1.6 (la maqueta).
TAMANO_RESPUESTA = 16
INTERLINEADO_RESPUESTA = 1.6


def _estilo_markdown() -> ft.MarkdownStyleSheet:
    """Estilos con los que se pinta el markdown de las respuestas: prosa en
    Jakarta 400, negritas y títulos en 700, tablas con encabezado en mono
    (como las etiquetas del diseño) sobre celdas sólidas, y código en mono.

    Devuelve una instancia nueva en cada llamada, en vez de ser una
    constante compartida por todas las burbujas: cuesta nada y evita
    preguntarse si flet puede reutilizar el mismo objeto en varios
    controles a la vez.
    """

    def prosa(**extra) -> ft.TextStyle:
        extra.setdefault("size", TAMANO_RESPUESTA)
        extra.setdefault("color", D.texto)
        # setdefault y no font_family= fijo: la negrita pasa su propia letra
        # y un argumento repetido rompe el TextStyle.
        extra.setdefault("font_family", "Jakarta400")
        return ft.TextStyle(height=INTERLINEADO_RESPUESTA, **extra)

    def titulo(tam: int, color: str) -> ft.TextStyle:
        return ft.TextStyle(size=tam, font_family="Jakarta700", color=color, height=1.3)

    return ft.MarkdownStyleSheet(
        p_text_style=prosa(),
        strong_text_style=prosa(font_family="Jakarta700"),
        em_text_style=prosa(),
        h1_text_style=titulo(21, D.texto),
        h2_text_style=titulo(19, D.texto),
        h3_text_style=titulo(17, D.texto),
        h4_text_style=titulo(16, D.suave),
        list_bullet_text_style=prosa(color=D.suave),
        blockquote_text_style=prosa(size=15, color=D.suave),
        blockquote_decoration=ft.BoxDecoration(bgcolor=D.chip, border_radius=10),
        blockquote_padding=ft.Padding.symmetric(horizontal=14, vertical=10),
        code_text_style=ft.TextStyle(size=14, font_family="Mono400", color=D.texto),
        codeblock_decoration=ft.BoxDecoration(bgcolor=D.chip, border_radius=10),
        codeblock_padding=ft.Padding.symmetric(horizontal=12, vertical=10),
        table_head_text_style=ft.TextStyle(size=11, font_family="Mono500", color=D.tenue,
                                           letter_spacing=1.1),
        table_body_text_style=ft.TextStyle(size=14, font_family="Jakarta500", color=D.texto),
        table_cells_padding=ft.Padding.symmetric(horizontal=14, vertical=11),
        table_cells_decoration=ft.BoxDecoration(bgcolor=D.solido),
        # Vive en una constante porque _partir_en_renglones() tiene que
        # reproducir este mismo hueco a mano al pintar renglón por renglón.
        block_spacing=ESPACIO_BLOQUE,
        list_indent=20,
    )


def _partir_saludo(saludo: str, nombre: str) -> tuple[str, str]:
    """Parte el saludo en los dos renglones de la maqueta: el primero en
    tinta y el segundo en gris ("Buenas tardes, Wilson." / "¿Qué revisamos
    hoy?"). El corte va justo después del nombre y su signo: el saludo lo
    redacta el modelo en muchas formas, pero casi todas nombran al dueño a
    media frase. Si el nombre no está o cierra la frase, va todo en un
    renglón negro."""
    i = saludo.find(nombre) if nombre else -1
    if i < 0:
        return saludo, ""
    fin = i + len(nombre)
    while fin < len(saludo) and saludo[fin] in ".,;:!?":
        fin += 1
    resto = saludo[fin:].strip()
    if not resto:
        return saludo, ""
    primero = saludo[:fin].rstrip()
    # "Buenas tardes, Wilson," se lee cortado: la coma se vuelve punto.
    if primero.endswith(","):
        primero = primero[:-1] + "."
        resto = resto[:1].upper() + resto[1:]
    return primero, resto


def _para_pintar(respuesta: str) -> str:
    """La respuesta tal como se pinta: el renglón de encabezado de cada tabla
    va en MAYÚSCULAS, como las etiquetas del diseño (el estilo del markdown
    no puede cambiar mayúsculas). Lo que se copia y lo que se guarda en el
    historial es la respuesta original."""
    lineas = respuesta.replace("\r\n", "\n").split("\n")
    for i in range(len(lineas) - 1):
        if "|" in lineas[i] and _RE_SEP_TABLA.match(lineas[i + 1]):
            lineas[i] = lineas[i].upper()
    return "\n".join(lineas)


def _fecha_hoy() -> str:
    hoy = datetime.datetime.now()
    return f"{DIAS[hoy.weekday()]}, {hoy.day} DE {MESES[hoy.month - 1]}"


class AgenteIAView(ft.Container):
    """Pantalla del agente de IA (ver el docstring del módulo).

    Cambia de BIENVENIDA a CONVERSACIÓN una sola vez, con el primer mensaje.
    Las conversaciones de esta sesión del panel se guardan en el router
    (router.conversaciones) para el botón "Historial"; como la sesión nunca
    se guarda en disco, tampoco ellas: se pierden al cerrar el panel.
    """

    def __init__(self, router):
        super().__init__()
        self.router = router
        self.expand = True
        # Sin bgcolor: detrás está el fondo de manchas (MainController).

        # El controlador se crea en la primera pregunta (_responder) en vez de
        # aquí, para que un OPENAI_API_KEY faltante no reviente la vista: se
        # muestra como un aviso de error normal.
        self._ia: IAController | None = None
        # Conversación de esta pantalla, como lista de {"role", "content"}:
        # le da al agente memoria de lo que ya se preguntó.
        self._historial: list[dict] = []
        self._procesando = False
        self._modo_chat = False
        self._entrada_expandida = False
        self._entrada_enfocada = False
        self._periodo = 0
        # Numera las preguntas para desplazarse hasta la última (_ir_a).
        self._contador_preguntas = 0
        # La entrada de esta conversación en router.conversaciones (Historial).
        self._conversacion = None
        abrir = getattr(router, "conversacion_a_abrir", None)
        router.conversacion_a_abrir = None

        # --------------------------------------------------------------
        # Caja de texto
        # --------------------------------------------------------------
        self.entrada = ft.TextField(
            hint_text=HINT_ENTRADA,
            # El hint se cambia por el prompt de una idea mientras el cursor
            # está encima (_hover_idea): con 1 renglón la caja no brinca, el
            # adelanto se corta con puntos suspensivos. Por eso la primera
            # frase de cada prompt tiene que bastarse sola.
            hint_max_lines=1,
            expand=True,
            # Enter manda y Shift+Enter hace salto de línea.
            multiline=True,
            min_lines=2,
            max_lines=LINEAS_COLAPSADA,
            shift_enter=True,
            border=ft.InputBorder.NONE,
            # ⚠️ Sin relleno: un TextField relleno se pinta encima del borde
            # del Container que lo envuelve. El fondo lo pone la caja.
            filled=False,
            dense=True,
            color=D.texto,
            cursor_color=D.texto,
            text_style=ft.TextStyle(size=16, font_family="Jakarta400", height=1.5),
            hint_style=ft.TextStyle(size=16, font_family="Jakarta400", color=D.tenue, height=1.5),
            content_padding=ft.Padding.all(0),
            on_submit=self._enviar_mensaje,
            on_change=self._on_cambio_entrada,
            on_focus=self._on_foco_entrada,
            on_blur=self._on_foco_entrada,
        )

        # Desplegar: solo aparece cuando el texto ya no cabe en la caja.
        self.boton_expandir = ft.Container(
            content=_icono(ft.Icons.UNFOLD_MORE, 16, D.suave),
            width=ANCHO_BOTON_EXPANDIR,
            height=ANCHO_BOTON_EXPANDIR,
            alignment=ft.Alignment(0, 0),
            border_radius=ANCHO_BOTON_EXPANDIR / 2,
            ink=True,
            visible=False,
            tooltip="Ver todo el mensaje",
            on_click=self._alternar_expansion,
        )

        # Enviar: el cuadro naranja de la maqueta. Solo aparece cuando hay
        # algo escrito (_on_cambio_entrada); con la caja vacía no hay qué mandar.
        self.boton_enviar = ft.Container(
            content=icono("flecha", 20, "#ffffff"),
            width=44,
            height=44,
            border_radius=14,
            bgcolor=D.acento,
            alignment=ft.Alignment(0, 0),
            visible=False,
            tooltip="Enviar (Enter)",
            on_click=self._enviar_mensaje,
        )

        self.selector_periodo = ft.Container(
            padding=3, border_radius=12, bgcolor=D.chip,
        )
        self._pintar_selector()

        self.columna_caja = ft.Column([
            ft.Row([self.entrada]),
            ft.Row([
                self.selector_periodo,
                texto("Enter envía · Shift+Enter salto", 11, 400, D.tenue, mono=True),
                ft.Container(expand=True),
                self.boton_expandir,
                # Hueco fijo de 44×44: el botón aparece y desaparece sin que
                # el renglón (ni la caja) cambie de alto.
                ft.Container(self.boton_enviar, width=44, height=44),
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        ], spacing=18)
        self.caja_entrada = ft.Container(
            bgcolor=D.solido,
            border_radius=22,
            padding=ft.Padding.only(left=20, top=16, right=16, bottom=12),
            shadow=ft.BoxShadow(blur_radius=30, color="#1A000000", offset=ft.Offset(0, 10)),
            content=self.columna_caja,
        )
        self._aplicar_realce_caja()

        # --------------------------------------------------------------
        # Conversación
        # --------------------------------------------------------------
        self.lista_mensajes = ft.Column(
            spacing=26,
            expand=True,
            scroll=ft.ScrollMode.AUTO,
            # auto_scroll NO: se usa scroll_to() con la clave de la pregunta
            # para dejarla hasta arriba, y flet exige auto_scroll apagado.
            auto_scroll=False,
        )

        # "LO QUE LEÍ PARA RESPONDER": lo que el agente leyó de la base para
        # la última respuesta (IAController.ultima_lectura).
        self.leido_platillos = texto("Tu menú · —", 13)
        self.leido_mesas = texto("Tus mesas · —", 13)
        self.leido_ventas = texto("Ventas · —", 13)

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        self.titulo_barra = texto("Agente IA", 15, 700, max_lines=1, no_wrap=True,
                                  overflow=ft.TextOverflow.ELLIPSIS)
        barra_superior = vidrio(
            radio=18,
            sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=12),
            contenido=ft.Row([
                self.titulo_barra,
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE), texto("Leyendo tus ventas en vivo", 12, 500, D.suave)],
                                   spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
                ft.Container(expand=True),
                self._boton_historial(),
                boton("Nueva conversación", "mas", self._nueva_conversacion, principal=True),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        self.cuerpo = ft.Container(top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN,
                                   bottom=MARGEN)
        self.content = ft.Stack([barra_superior, self.cuerpo], expand=True)

        if abrir:
            self._abrir_conversacion(abrir)
        else:
            self._montar_bienvenida()
            # El saludo de la próxima visita, en segundo plano.
            self.router.page.run_task(self.router.precargar_saludo)

    # ------------------------------------------------------------------
    # Los dos estados de la pantalla
    # ------------------------------------------------------------------
    def _montar_bienvenida(self):
        """La tarjeta de vidrio centrada: fecha, saludo, caja, ideas y la
        nota de abajo."""
        # El saludo ya viene redactado de antes (models/saludo_ia.py). Si no
        # llega, entra al instante la frase local; nunca se cambia uno ya
        # puesto por otro (se leería como un parpadeo).
        nombre = perfil.como_llamarte()
        saludo = saludo_ia.tomar(nombre) or saludo_ia.saludo_de_respaldo(nombre)
        primero, segundo = _partir_saludo(saludo, nombre)
        renglones = [ft.TextSpan(primero)]
        if segundo:
            renglones.append(ft.TextSpan("\n" + segundo, ft.TextStyle(color=D.tenue)))
        titulo = ft.Text(
            spans=renglones, size=TAMANO_SALUDO, font_family="Jakarta800", color=D.texto,
            style=ft.TextStyle(height=1.04, letter_spacing=-1.25),
        )

        ideas = ft.Row([self._tarjeta_idea(idea) for idea in IDEAS], spacing=12)

        tarjeta = vidrio(
            radio=30,
            width=ANCHO_BIENVENIDA,
            padding=ft.Padding.only(left=40, top=40, right=40, bottom=28),
            contenido=ft.Column([
                ft.Column([
                    ft.Row([_logo_saludo(30),
                            etiqueta(_fecha_hoy(), 11.5)],
                           spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
                    titulo,
                ], spacing=14),
                self.caja_entrada,
                ft.Column([etiqueta("IDEAS PARA TI"), ideas], spacing=12),
                ft.Row([icono("candado", 14, D.tenue),
                        texto("Solo responde sobre tu negocio. Las cifras salen de tus ventas "
                              "cerradas.", 12, 500, D.tenue)],
                       spacing=8, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            ], spacing=28, tight=True),
        )
        self.cuerpo.content = ft.Column(
            [ft.Row([tarjeta], alignment=ft.MainAxisAlignment.CENTER)],
            alignment=ft.MainAxisAlignment.CENTER,
            scroll=ft.ScrollMode.AUTO,
            expand=True,
        )

    def _montar_chat(self):
        """El panel de vidrio con los mensajes y la caja abajo, y la tarjeta
        de lo leído a su derecha. Se llama una sola vez: al mandar el primer
        mensaje (o al abrir una del Historial)."""
        self._modo_chat = True
        self.entrada.min_lines = 1
        self.entrada.hint_text = HINT_CHAT
        self.columna_caja.spacing = 10
        self.caja_entrada.width = ANCHO_CAJA_CHAT

        panel = vidrio(
            radio=26,
            expand=True,
            contenido=ft.Column([
                ft.Container(
                    expand=True,
                    padding=ft.Padding.only(top=32, bottom=16),
                    alignment=ft.Alignment.TOP_CENTER,
                    content=ft.Container(width=ANCHO_CHAT, content=self.lista_mensajes),
                ),
                ft.Container(padding=ft.Padding.only(left=24, right=24, bottom=24),
                             alignment=ft.Alignment.BOTTOM_CENTER, content=self.caja_entrada),
            ], spacing=0),
        )

        def fuente(nombre_icono, control):
            return ft.Row([icono(nombre_icono, 16, D.tenue), control], spacing=10,
                          vertical_alignment=ft.CrossAxisAlignment.CENTER)

        leido = vidrio(
            radio=22,
            width=ANCHO_LEIDO,
            padding=20,
            contenido=ft.Column([
                etiqueta("LO QUE LEÍ PARA RESPONDER"),
                fuente("menu", self.leido_platillos),
                fuente("mesas", self.leido_mesas),
                fuente("datos", self.leido_ventas),
                ft.Container(height=1, bgcolor=D.linea),
                texto("El día se cuenta de 6:00 a 6:00. Las sumas las hace el panel, no la IA.",
                      12.5, 500, D.suave, alto=1.5),
            ], spacing=14, tight=True),
        )
        self.cuerpo.content = ft.Row(
            [panel, ft.Column([leido], spacing=0)],
            spacing=MARGEN,
            vertical_alignment=ft.CrossAxisAlignment.STRETCH,
        )

    def _pintar_leido(self, lectura=None):
        if lectura is None and self._ia is not None:
            lectura = getattr(self._ia, "ultima_lectura", None)
        if not lectura:
            return
        n = lectura["platillos"]
        self.leido_platillos.value = f"Tu menú · {n} platillo{'' if n == 1 else 's'}"
        self.leido_mesas.value = f"Tus mesas · {lectura['mesas']}"
        self.leido_ventas.value = f"Ventas · últimas {lectura['ventas']}"

    # ------------------------------------------------------------------
    # Barra de arriba: Historial y Nueva conversación
    # ------------------------------------------------------------------
    def _boton_historial(self):
        """Las conversaciones de esta sesión del panel (router.conversaciones),
        la más nueva arriba. Elegir una la vuelve a abrir tal cual."""
        conversaciones = list(reversed(getattr(self.router, "conversaciones", None) or []))
        if conversaciones:
            opciones = [
                ft.PopupMenuItem(
                    content=texto(c["titulo"], 13, 500, max_lines=1,
                                  overflow=ft.TextOverflow.ELLIPSIS, width=280),
                    on_click=lambda e, c=c: self._abrir_desde_historial(c),
                )
                for c in conversaciones
            ]
        else:
            opciones = [ft.PopupMenuItem(
                content=texto("Aún no hay conversaciones en esta sesión.", 13, 500, D.tenue),
                disabled=True,
            )]
        cara = ft.Container(
            height=40,
            padding=ft.Padding.symmetric(horizontal=14),
            border_radius=12,
            border=ft.Border.all(1, D.linea),
            content=ft.Row([icono("historial", 16), texto("Historial", 13, 600)],
                           spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )
        return ft.PopupMenuButton(
            content=cara,
            items=opciones,
            bgcolor=D.solido,
            menu_position=ft.PopupMenuPosition.UNDER,
            shape=ft.RoundedRectangleBorder(radius=14),
            tooltip="",
        )

    def _abrir_desde_historial(self, conversacion):
        self.router.conversacion_a_abrir = conversacion
        self.router.cambiar_vista("agente_financiero")

    def _nueva_conversacion(self, _):
        self.router.cambiar_vista("agente_financiero")

    def _guardar_conversacion(self, titulo: str):
        """Deja esta conversación en router.conversaciones (Historial). Se
        llama tras cada respuesta buena; la entrada es la misma, se actualiza."""
        if self._conversacion is None:
            self._conversacion = {"titulo": titulo, "historial": [], "mensajes": []}
            conversaciones = getattr(self.router, "conversaciones", None) or []
            conversaciones.append(self._conversacion)
            self.router.conversaciones = conversaciones
        self._conversacion["historial"] = list(self._historial)

    def _abrir_conversacion(self, conversacion):
        """Vuelve a pintar una conversación del Historial, sin animación."""
        self._conversacion = conversacion
        self._historial = list(conversacion["historial"])
        self.titulo_barra.value = conversacion["titulo"]
        self._montar_chat()
        self._pintar_leido(conversacion.get("leido"))
        for visible, respuesta in conversacion["mensajes"]:
            self._contador_preguntas += 1
            fila = self._fila(self._burbuja_usuario(visible), derecha=True)
            fila.key = ft.ScrollKey(f"pregunta-{self._contador_preguntas}")
            self.lista_mensajes.controls.append(fila)
            self.lista_mensajes.controls.append(
                self._fila_respuesta(self._markdown_respuesta(_para_pintar(respuesta)), respuesta,
                                     None, visible=True)
            )

    # ------------------------------------------------------------------
    # Selector de periodo
    # ------------------------------------------------------------------
    def _pintar_selector(self):
        segmentos = []
        for i, (nombre, _) in enumerate(PERIODOS):
            elegido = i == self._periodo
            segmentos.append(ft.Container(
                height=30,
                padding=ft.Padding.symmetric(horizontal=12),
                border_radius=9,
                alignment=ft.Alignment.CENTER,
                bgcolor=D.solido if elegido else None,
                shadow=ft.BoxShadow(blur_radius=3, color="#26000000", offset=ft.Offset(0, 1))
                if elegido else None,
                content=texto(nombre, 12.5, 600, D.texto if elegido else D.suave),
                on_click=lambda e, i=i: self._elegir_periodo(i),
            ))
        self.selector_periodo.content = ft.Row(segmentos, spacing=2, tight=True)

    def _elegir_periodo(self, i: int):
        if i == self._periodo:
            return
        self._periodo = i
        self._pintar_selector()
        self._refrescar()

    # ------------------------------------------------------------------
    # Ideas para ti
    # ------------------------------------------------------------------
    def _tarjeta_idea(self, idea: dict) -> ft.Container:
        """Una idea: icono y flechita arriba, título y descripción abajo. Toda
        la tarjeta es el área sensible. Alto fijo para que las tres queden
        parejas aunque una descripción ocupe un renglón y otra dos. La
        flechita solo aparece con el cursor encima, junto con el borde
        oscuro (_hover_idea)."""
        flecha = ft.Container(
            content=icono("derecha", 16, D.tenue),
            opacity=0,
            animate_opacity=ft.Animation(150, ft.AnimationCurve.EASE_OUT),
        )
        return ft.Container(
            data=flecha,
            expand=1,
            height=136,
            padding=16,
            border_radius=18,
            bgcolor=D.solido,
            border=ft.Border.all(1, D.linea),
            animate=ft.Animation(150, ft.AnimationCurve.EASE_OUT),
            content=ft.Column([
                ft.Row([
                    ft.Container(width=36, height=36, border_radius=11, bgcolor=D.chip,
                                 alignment=ft.Alignment.CENTER, content=icono(idea["icono"], 18)),
                    ft.Container(expand=True),
                    flecha,
                ], vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ft.Column([
                    texto(idea["titulo"], 14.5, 700),
                    texto(idea["descripcion"], 12.5, 500, D.suave, alto=1.45),
                ], spacing=4, tight=True),
            ], spacing=14, tight=True),
            on_hover=lambda e, prompt=idea["prompt"]: self._hover_idea(e, prompt),
            on_click=lambda e, idea=idea: self._usar_idea(e, idea),
        )

    def _hover_idea(self, evento, prompt: str):
        """Con el cursor encima de una idea su borde se oscurece y la caja de
        texto adelanta el prompt en su texto de reposo (hint, no value: se ve
        en gris como adelanto, y si el dueño ya escribió algo ni se ve). Al
        salirse, las dos se deshacen."""
        # evento.data es un bool de verdad: True al entrar, False al salir.
        dentro = bool(evento.data)
        evento.control.border = ft.Border.all(1, D.suave if dentro else D.linea)
        evento.control.data.opacity = 1 if dentro else 0
        self.entrada.hint_text = prompt if dentro else HINT_ENTRADA
        self._refrescar()

    def _usar_idea(self, evento, idea: dict):
        """Un clic en una idea la manda de una vez: la idea ES la pregunta."""
        self.entrada.hint_text = HINT_ENTRADA
        self._enviar_mensaje(evento, texto_idea=idea)

    # ------------------------------------------------------------------
    # Piezas de la conversación
    # ------------------------------------------------------------------
    def _fila(self, contenido: ft.Control, derecha: bool) -> ft.Container:
        """Coloca un mensaje de un lado o del otro. El padding del lado
        contrario es el tope de ancho de la burbuja."""
        return ft.Container(
            content=contenido,
            alignment=ft.Alignment(1, 0) if derecha else ft.Alignment(-1, 0),
            padding=(
                ft.Padding.only(left=HUECO_USUARIO)
                if derecha
                else ft.Padding.only(right=HUECO_IA)
            ),
        )

    def _burbuja_usuario(self, valor: str) -> ft.Container:
        # En tinta, con la esquina de abajo a la derecha casi recta: la cola
        # de quien habla.
        return ft.Container(
            content=texto(valor, 14.5, 500, D.sobre_tinta, alto=1.5, selectable=True),
            bgcolor=D.tinta,
            padding=ft.Padding.symmetric(horizontal=18, vertical=12),
            border_radius=ft.BorderRadius.only(top_left=18, top_right=18, bottom_left=18,
                                               bottom_right=6),
        )

    def _markdown_respuesta(self, valor: str) -> ft.Markdown:
        """Un trozo de respuesta pintado como markdown: el modelo contesta en
        markdown (**negritas**, viñetas, tablas con pipes).

        selectable=True porque las respuestas traen cifras que el dueño va a
        querer copiar.
        """
        return ft.Markdown(
            valor,
            selectable=True,
            # GITHUB_FLAVORED habilita las tablas.
            extension_set=ft.MarkdownExtensionSet.GITHUB_FLAVORED,
            # OBLIGATORIO: sin esto un solo salto de línea no parte el
            # renglón y "Mesa 1 — $2,150\nMesa 2 — $1,480" se pegaría.
            soft_line_break=True,
            md_style_sheet=_estilo_markdown(),
        )

    def _renglon_respuesta(self, trozo: str, hueco: int, bloque: bool) -> ft.Container:
        """Un renglón de la respuesta, apagado y listo para encenderse.

        Nace en opacity=0 y lo enciende _revelar(). Quien interpola el
        fundido es el CLIENTE (animate_opacity), no python. Nacer apagado
        hace que la respuesta ocupe su alto desde el principio, así que el
        scroll no brinca. Solo los renglones de texto suben: un bloque
        (tabla, código, cita) solo se funde, porque el offset se mide en
        fracciones de su propia altura y daría un brinco.
        """
        animacion = ft.Animation(DURACION_APARICION, ft.AnimationCurve.EASE_OUT)
        return ft.Container(
            content=self._markdown_respuesta(trozo),
            margin=ft.Margin.only(top=hueco),
            opacity=0,
            animate_opacity=animacion,
            offset=None if bloque else ft.Offset(0, SUBIDA_APARICION),
            animate_offset=None if bloque else animacion,
        )

    def _acciones(self, respuesta: str, idea: dict | None, visible: bool) -> ft.Row:
        """Los botones bajo una respuesta: Copiar, y si vino de una idea, sus
        dos preguntas de seguimiento. Aparecen al terminar de salir el texto."""
        def chico(etiqueta_boton, al_pulsar, nombre_icono=None, color=None):
            fila = [texto(etiqueta_boton, 12.5, 600, color or D.texto)]
            if nombre_icono:
                fila.insert(0, icono(nombre_icono, 14, color or D.texto))
            return ft.Container(
                height=32, padding=ft.Padding.symmetric(horizontal=12), border_radius=10,
                bgcolor=D.solido, border=ft.Border.all(1, D.linea),
                content=ft.Row(fila, spacing=6, tight=True,
                               vertical_alignment=ft.CrossAxisAlignment.CENTER),
                on_click=al_pulsar,
            )

        async def copiar(_):
            try:
                await self.router.page.clipboard.set(respuesta)
            except Exception:
                traceback.print_exc()

        botones = [chico("Copiar", copiar, "copiar", D.suave)]
        for etiqueta_boton, pregunta in (idea or {}).get("seguimiento", ()):
            botones.append(chico(
                etiqueta_boton,
                lambda e, p=pregunta, t=etiqueta_boton: self._enviar_mensaje(e, texto_libre=(t, p)),
            ))
        return ft.Row(botones, spacing=8, wrap=True, opacity=1 if visible else 0,
                      animate_opacity=ft.Animation(DURACION_APARICION, ft.AnimationCurve.EASE_OUT))

    def _fila_respuesta(self, contenido: ft.Control, respuesta: str, idea, visible=False):
        """La respuesta con el logo a la izquierda y sus botones debajo."""
        acciones = self._acciones(respuesta, idea, visible)
        fila = ft.Row([
            _logo_saludo(HUECO_LOGO_RESPUESTA),
            ft.Container(
                ft.Column([contenido, acciones], spacing=14),
                expand=True,
                padding=ft.Padding.only(top=(HUECO_LOGO_RESPUESTA - _ALTO_RENGLON_RESPUESTA) / 2),
            ),
        ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.START)
        fila.data = acciones
        return fila

    def _burbuja_ia(self, valor: str):
        """La respuesta del agente, partida en renglones que aparecen uno por
        uno (ver _partir_en_renglones y _revelar). Devuelve (contenedor,
        renglones)."""
        renglones = [
            self._renglon_respuesta(trozo, hueco, bloque)
            for trozo, hueco, bloque in _partir_en_renglones(_para_pintar(valor))
        ]
        contenedor = ft.Container(content=ft.Column(renglones, spacing=0))
        return contenedor, renglones

    async def _revelar(self, contenedor: ft.Container, renglones: list, valor: str,
                       acciones: ft.Row):
        """Va encendiendo los renglones de arriba hacia abajo, en su propia
        tarea. De dos en dos o de tres en tres cuando la respuesta es larga
        (PASOS_MAXIMOS).

        AL FINAL se cambia la columna de renglones por UNA sola ft.Markdown
        con la respuesta completa: es lo que devuelve la selección de texto
        de punta a punta (pintan igual píxel por píxel). Y se encienden los
        botones de debajo.
        """
        por_paso = max(1, math.ceil(len(renglones) / PASOS_MAXIMOS))
        for i in range(0, len(renglones), por_paso):
            for renglon in renglones[i:i + por_paso]:
                renglon.opacity = 1
                if renglon.offset is not None:
                    renglon.offset = ft.Offset(0, 0)
            self._refrescar()
            await asyncio.sleep(PASO_APARICION)

        await asyncio.sleep(DURACION_APARICION / 1000)
        contenedor.content = self._markdown_respuesta(_para_pintar(valor))
        acciones.opacity = 1
        self._refrescar()

    def _burbuja_pensando(self) -> ft.Row:
        """"Pensando..." con el logo animado: un WebP que el cliente reproduce
        solo (D.logo_pensando). Mismo hueco y separación del texto que el
        logo de _fila_respuesta, para que la respuesta lo tome sin brincar."""
        return ft.Row(
            controls=[
                ft.Image(src=D.logo_pensando, width=HUECO_LOGO_RESPUESTA,
                         height=HUECO_LOGO_RESPUESTA, fit=ft.BoxFit.CONTAIN),
                texto("Pensando...", TAMANO_TEXTO_PENSANDO, 500, D.suave),
            ],
            spacing=14,
            tight=True,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        )

    def _burbuja_error(self, mensaje: str) -> ft.Container:
        return ft.Container(
            bgcolor=D.solido,
            border=ft.Border.all(1, D.linea),
            border_radius=14,
            padding=ft.Padding.symmetric(horizontal=16, vertical=12),
            content=ft.Row(
                controls=[
                    ft.Icon(ft.Icons.ERROR_OUTLINE, size=16, color=D.suave),
                    texto(mensaje, 13, 500, D.suave, expand=True),
                ],
                spacing=8,
            ),
        )

    # ------------------------------------------------------------------
    # Caja de texto: enviar, crecer, desplegar, plegar
    # ------------------------------------------------------------------
    def _on_foco_entrada(self, e):
        self._entrada_enfocada = e.name == "focus"
        self._aplicar_realce_caja()
        self._refrescar()

    def _aplicar_realce_caja(self):
        """El borde de la caja: fino en reposo, más marcado con el cursor
        dentro. No repinta — quien llama decide cuándo."""
        self.caja_entrada.border = ft.Border.all(
            1, D.suave if self._entrada_enfocada else D.linea
        )

    def _lineas_estimadas(self, valor: str) -> int:
        """Cuántos renglones ocupa el texto en la caja. Es una estimación
        (flet no da la altura real del TextField) que solo decide si aparece
        el botón de desplegar. ~8.4 px por carácter de Jakarta a 16 px, en
        los 664 px útiles de la caja de la bienvenida (la más angosta)."""
        por_renglon = max(20, int((ANCHO_BIENVENIDA - 80 - 36) / 8.4))
        renglones = 0
        for parrafo in valor.split("\n"):
            renglones += max(1, math.ceil(len(parrafo) / por_renglon))
        return renglones

    def _plegar_entrada(self):
        self._entrada_expandida = False
        self.entrada.max_lines = LINEAS_COLAPSADA
        self.boton_expandir.content = _icono(ft.Icons.UNFOLD_MORE, 16, D.suave)
        self.boton_expandir.tooltip = "Ver todo el mensaje"

    def _on_cambio_entrada(self, evento):
        """Enciende o apaga el botón de enviar (hay texto o no) y el de
        desplegar (el texto cabe o no)."""
        valor = self.entrada.value or ""
        hay_texto = bool(valor.strip())
        desborda = self._lineas_estimadas(valor) > LINEAS_COLAPSADA
        if hay_texto == self.boton_enviar.visible and desborda == self.boton_expandir.visible:
            return
        self.boton_enviar.visible = hay_texto
        self.boton_expandir.visible = desborda
        if not desborda:
            self._plegar_entrada()
        self._refrescar()

    def _alternar_expansion(self, evento):
        if self._entrada_expandida:
            self._plegar_entrada()
        else:
            self._entrada_expandida = True
            self.entrada.max_lines = LINEAS_EXPANDIDA
            self.boton_expandir.content = _icono(ft.Icons.UNFOLD_LESS, 16, D.suave)
            self.boton_expandir.tooltip = "Contraer"
        self._refrescar()

    # ------------------------------------------------------------------
    # Enviar / responder
    # ------------------------------------------------------------------
    def _enviar_mensaje(self, evento, texto_idea: dict | None = None,
                        texto_libre: tuple[str, str] | None = None):
        """Manda lo escrito en la caja, una idea (texto_idea) o un botón de
        seguimiento (texto_libre = (lo que se ve, lo que se pregunta))."""
        if self._procesando:
            return
        idea = texto_idea
        if idea:
            visible, pregunta = idea["titulo"], idea["prompt"]
        elif texto_libre:
            visible, pregunta = texto_libre
        else:
            visible = (self.entrada.value or "").strip()
            if not visible:
                return
            # El periodo del selector va como aclaración, solo para cuando la
            # pregunta no dice de qué periodo habla.
            pregunta = (f"{visible}\n\n(Si mi pregunta no dice de qué periodo hablo, "
                        f"toma {PERIODOS[self._periodo][1]}.)")

        if not self._modo_chat:
            self._montar_chat()
            self.titulo_barra.value = visible if len(visible) <= 48 else visible[:47] + "…"

        self._contador_preguntas += 1
        clave = f"pregunta-{self._contador_preguntas}"
        fila = self._fila(self._burbuja_usuario(visible), derecha=True)
        fila.key = ft.ScrollKey(clave)
        self.lista_mensajes.controls.append(fila)

        self.entrada.value = ""
        self.boton_enviar.visible = False
        self.boton_expandir.visible = False
        self._plegar_entrada()
        self._refrescar()
        self.router.page.run_task(self._responder, visible, pregunta, clave, idea)

    def _quitar_indicador(self, indicador: ft.Control):
        """Quita la fila de "Pensando..." SI todavía está puesta. No es
        defensivo de más: un .remove() pelón en el except, después de que
        algo tronara con el indicador ya quitado, levantaba ValueError y el
        aviso de error nunca salía (la pregunta se quedaba sola, 06/09)."""
        if indicador in self.lista_mensajes.controls:
            self.lista_mensajes.controls.remove(indicador)

    async def _responder(self, visible: str, pregunta: str, clave: str, idea: dict | None):
        self._procesando = True
        self.entrada.disabled = True
        indicador = self._fila(self._burbuja_pensando(), derecha=False)
        self.lista_mensajes.controls.append(indicador)
        self._refrescar()
        await self._ir_a(clave)

        # Lo que _revelar() necesita; lo lanza el finally.
        animacion = None

        try:
            if self._ia is None:
                self._ia = IAController()
            respuesta = await asyncio.to_thread(
                self._ia.preguntar, pregunta, self._historial
            )
            self._quitar_indicador(indicador)
            burbuja, renglones = self._burbuja_ia(respuesta)
            fila = self._fila_respuesta(burbuja, respuesta, idea)
            self.lista_mensajes.controls.append(fila)
            animacion = (burbuja, renglones, respuesta, fila.data)
            # Al historial solo tras una respuesta buena: una pregunta sin
            # respuesta no debe colarse en lo que se le manda al modelo.
            self._historial.append({"role": "user", "content": pregunta})
            self._historial.append({"role": "assistant", "content": respuesta})
            self._guardar_conversacion(self.titulo_barra.value)
            self._conversacion["mensajes"].append((visible, respuesta))
            self._pintar_leido()
            self._conversacion["leido"] = getattr(self._ia, "ultima_lectura", None)
        except RuntimeError as error:
            # Típicamente el OPENAI_API_KEY faltante (IAController.__init__).
            self._quitar_indicador(indicador)
            self.lista_mensajes.controls.append(
                self._fila(self._burbuja_error(str(error)), derecha=False)
            )
        except Exception:
            # traceback a consola a propósito: aquí caen los fallos de red y
            # también los errores de programación, que no deben perderse.
            traceback.print_exc()
            self._quitar_indicador(indicador)
            self.lista_mensajes.controls.append(
                self._fila(
                    self._burbuja_error(
                        "No se pudo conectar con el agente de IA. Intenta de nuevo."
                    ),
                    derecha=False,
                )
            )
        finally:
            self._procesando = False
            self.entrada.disabled = False
            self._refrescar()
            # Antes del scroll y del foco, para que el texto empiece a salir
            # de inmediato donde estaba el "Pensando...".
            if animacion is not None:
                self.router.page.run_task(self._revelar, *animacion)
            # El scroll va a la pregunta: la respuesta se lee desde arriba.
            await self._ir_a(clave)
            # Y el cursor regresa a la caja (deshabilitarla le quitó el foco).
            try:
                await self.entrada.focus()
                # focus() programático NO dispara on_focus: el realce a mano.
                self._entrada_enfocada = True
                self._aplicar_realce_caja()
                self._refrescar()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------
    def _refrescar(self):
        """self.update() a prueba de que el dueño haya navegado a otra
        pantalla mientras la IA respondía (la vista ya no está montada)."""
        try:
            self.update()
        except (RuntimeError, AssertionError):
            pass

    async def _ir_a(self, clave: str):
        """Desplaza la conversación hasta dejar esa pregunta hasta arriba."""
        # Un respiro para que flet alcance a pintar el control nuevo.
        await asyncio.sleep(0.08)
        try:
            await self.lista_mensajes.scroll_to(scroll_key=clave, duration=260)
        except Exception:
            pass
