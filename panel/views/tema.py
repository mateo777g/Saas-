"""
views/tema.py
Los colores del panel, en un solo sitio: el tema oscuro (el de siempre) y el claro (26/09, la
"idea loca" del dueño: elegirlo en Ajustes, en la tarjeta TEMA).

Cada color lleva el nombre de lo que ES (texto, linea, cara, pozo...), no de cómo se ve, y cada
tema le da su valor. Las vistas y las piezas nunca escriben un color a mano: lo piden aquí,
`C.texto`, `C.linea`... Así un tema nuevo es un diccionario más, y cambiar un tono es cambiar una
línea. Los valores del oscuro son los de siempre, medidos en DISENO.md ("Colores").

Los colores se leen al construir cada vista. Al cambiar de tema, Ajustes llama a `guardar()` y
rehace la vista que se ve (con la barra): las demás se construyen ya con el nuevo al abrirlas.
Se guarda en config.json (clave "tema"), junto a la carpeta de exportación y el perfil
(models/config_usuario.py: panel/config.json, en panel/.gitignore).
"""
from types import SimpleNamespace

from models.config_usuario import guardar_config, leer_config

OSCURO = {
    # Para Flet (Material 3): lo que el panel no pinta él mismo (barras de desplazamiento, el
    # cursor de un campo antes de su color...).
    "modo": "dark",
    # --- Superficies ---
    "fondo": "#0e0e0e",                  # debajo del degradado de la página
    # El degradado de la página: un brillo abajo a la derecha (regla 5). Stops 0 / 0.32 / 0.7 / 1.
    "fondo_pagina": ["#a5a5a5", "#5c5c5c", "#1a1a1a", "#000000"],
    "barra": "#0e0e0e",                  # la barra lateral
    "tarjeta": ["#222222", "#3a3a3a"],   # relleno de tarjeta, de arriba-izquierda a abajo-derecha
    # El brillo del borde de las tarjetas, atajos y píldoras (brillo(), stops 0 / 0.3 / 1), y la
    # línea que ese brillo recorta en los botones (anillo_brillo()).
    "brillo": ["#8AFFFFFF", "#2EFFFFFF", "#00FFFFFF"],
    "anillo": "#FFFFFF",
    "sombra": "#8A000000",               # la de debajo de las tarjetas (BLACK54)
    # La cara de un botón: en reposo, con el cursor encima y pulsado (5 / 14 / 20 %).
    "cara": "#0DFFFFFF",
    "cara_encendida": "#24FFFFFF",
    "cara_pulsada": "#33FFFFFF",
    "pozo": "#33000000",                 # el fondo de un campo, más hondo que la tarjeta
    "velo": "#99000000",                 # detrás de una ventanita
    "globo": "#2a2a2a",                  # avisos y globos de los botones
    # --- Texto, iconos y rayas ---
    "texto": "#FFFFFF",                  # WHITE
    "texto_suave": "#8AFFFFFF",          # WHITE54: subtítulos, etiquetas, iconos
    # La capa de icono y texto de un atajo o una opción del menú, en reposo (sube a 1 encendida):
    # vista así, igual que texto_suave.
    "reposo": 0.54,
    "tenue": "#3DFFFFFF",                # WHITE24: rayas de la barra, iconos de hueco
    "linea": "#1FFFFFFF",                # WHITE12: rayas de tablas, bordes de campos
    "globo_texto": "#FFFFFF",
    "contador": "#909090",               # los números de Inicio (el gris del reloj del iPhone)
    # --- El botón destacado ("Entrar"): cara en reposo / encendida / pulsada y su contenido ---
    "destacado": ["#F0FFFFFF", "#FFFFFFFF", "#D1FFFFFF"],
    "destacado_texto": "#000000",
    # --- Pantalla de entrar ---
    "fondo_entrar": "#000000",           # liso, sin degradado: solo brillan las manchas
    "tarjeta_entrar": ["#0a0a0a", "#1c1c1c"],
}

# El claro es el oscuro al revés: donde había blanco translúcido sobre negro, negro translúcido
# sobre blanco, con los mismos porcentajes (así un botón se enciende igual de fuerte en los dos).
# La luz sigue viniendo de abajo a la derecha (regla 5): el fondo es más blanco en esa esquina y
# las tarjetas se aclaran hacia ella. Los avisos y los globos van oscuros, como en el iPhone.
# Una excepción a "los mismos porcentajes": el gris del texto. La Light es muy fina y en negro sobre
# blanco se lee más débil que en blanco sobre negro; al 54 % se perdía. Va al 68 %.
CLARO = {
    "modo": "light",
    "fondo": "#e8e8e8",
    "fondo_pagina": ["#ffffff", "#f4f4f4", "#e8e8e8", "#dcdcdc"],
    "barra": "#f7f7f7",
    "tarjeta": ["#f3f3f3", "#ffffff"],
    "brillo": ["#40000000", "#14000000", "#00000000"],
    "anillo": "#000000",
    "sombra": "#33000000",
    "cara": "#0D000000",
    "cara_encendida": "#1F000000",
    "cara_pulsada": "#2B000000",
    "pozo": "#0A000000",
    "velo": "#59000000",
    "globo": "#2a2a2a",
    "texto": "#000000",
    "texto_suave": "#AD000000",
    "reposo": 0.68,
    "tenue": "#3D000000",
    "linea": "#1F000000",
    "globo_texto": "#FFFFFF",
    "contador": "#8a8a8a",
    "destacado": ["#F0000000", "#FF000000", "#C7000000"],
    "destacado_texto": "#FFFFFF",
    "fondo_entrar": "#ececec",
    "tarjeta_entrar": ["#f6f6f6", "#ffffff"],
}

TEMAS = {"oscuro": OSCURO, "claro": CLARO}

# --- EL DISEÑO NUEVO (28/09): fondo de manchas + vidrio -------------------------------------------
# Los colores del rediseño que nació en el Agente IA y que van a heredar las demás vistas. Viven
# aparte (D.texto, D.vidrio...) para no pisar los de arriba mientras las vistas viejas sigan
# usándolos. Salen tal cual de la maqueta (panel/diseno/maquetas-agente-ia/); las reglas de uso
# están en planes/plan panel.txt ("DISEÑO MANCHAS + VIDRIO").
D_CLARO = {
    "suelo": "#fafaf8",                  # el color del fondo de manchas (y de la ventana)
    "manchas": "assets/fondo-manchas-claro.webp",
    # Las manchas con grano del login, del color del acento (herramientas/generar_login_grano_naranja.py).
    "manchas_login": "assets/login-grano-naranja.webp",
    "logo_marca": "assets/fragmentless-naranja.svg",   # herramientas/vectorizar_logo.py
    "logo_simbolo": "assets/fragmentless-naranja-simbolo.svg",   # el del saludo del agente
    "logo_pensando": "assets/logo-pensando-naranja.webp",       # herramientas/generar_logo_pensando.py
    "acento": "#E8622A",                 # naranja del logo: botón de enviar e insignia "IA"
    "vidrio": "#CCFFFFFF",               # blanco al 80 % + desenfoque 18
    "vidrio_linea": "#14000000",         # 8 %
    "sombra": "#2E000000",               # 18 %, blur 60, caída 24
    "solido": "#ffffff",                 # caja de texto, tarjetas de idea, tablas
    "texto": "#0b0b0b",
    "suave": "#5f5f5a",                  # descripciones, botones apagados
    "tenue": "#8b8b85",                  # etiquetas mono, pistas, segunda línea del título
    "linea": "#17000000",                # 9 %
    "linea_fuerte": "#2E000000",         # 18 %: el borde punteado del resultado (Crear contenido)
    "chip": "#0B000000",                 # 4.5 %: fondo de chips, iconos y el selector
    "tinta": "#0b0b0b",                  # lo activo: opción del menú, botón principal, burbuja
    "sobre_tinta": "#ffffff",
    "velo": "#59000000",                 # detrás de una ventana (35 %)
}
D_OSCURO = {
    "suelo": "#161616",
    "manchas": "assets/fondo-manchas-oscuro.webp",
    "manchas_login": "assets/login-grano.webp",
    "logo_marca": "assets/fragmentless-azul.svg",      # herramientas/vectorizar_logo.py
    "logo_simbolo": "assets/fragmentless-azul-simbolo.svg",
    "logo_pensando": "assets/logo-pensando-azul.webp",
    "acento": "#1355E8",                 # azul del logo (fragmentless.png)
    "vidrio": "#C70E0E0E",               # #0e0e0e al 78 %
    "vidrio_linea": "#17FFFFFF",
    "sombra": "#8C000000",               # 55 %
    "solido": "#1b1b1b",
    "texto": "#f5f5f2",
    "suave": "#a6a6a0",
    "tenue": "#7c7c77",
    "linea": "#1AFFFFFF",
    "linea_fuerte": "#33FFFFFF",         # 20 %
    "chip": "#0FFFFFFF",
    "tinta": "#f5f5f2",
    "sobre_tinta": "#0b0b0b",
    "velo": "#99000000",                 # 60 %
}
D_TEMAS = {"oscuro": D_OSCURO, "claro": D_CLARO}
# Iguales en los dos temas.
VERDE = "#3f9b5a"                         # el punto de "en vivo"
D = SimpleNamespace(**D_OSCURO)
POR_DEFECTO = "oscuro"

# Los colores del tema elegido: C.texto, C.linea... Se cambian en su sitio (poner()), así que
# quien ya importó C ve siempre los del tema actual.
C = SimpleNamespace(**OSCURO)
_actual = POR_DEFECTO


def actual():
    return _actual


def poner(nombre):
    global _actual
    if nombre not in TEMAS:
        nombre = POR_DEFECTO
    _actual = nombre
    C.__dict__.update(TEMAS[nombre])
    D.__dict__.update(D_TEMAS[nombre])


def cargar():
    # El que quedó guardado en config.json (el oscuro si no hay ninguno). Al abrir el panel.
    poner(leer_config().get("tema"))


def guardar(nombre):
    guardar_config({"tema": nombre})
    poner(nombre)
