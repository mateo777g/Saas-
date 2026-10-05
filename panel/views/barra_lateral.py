import flet as ft

from models import perfil
from views.diseno import ANCHO_BARRA, MARGEN, etiqueta, icono, insignia, texto, vidrio
from views.perfil_ventana import abrir_perfil
from views.piezas import sin_auto_update
from views.tema import D

# --- BARRA LATERAL ---
# Una sola para todo el panel: MainController la pone a la izquierda de cada vista con
# crear_barra_lateral(router, ruta_activa). Rediseño del 28/09 (maqueta aprobada en
# panel/diseno/maquetas-agente-ia/, reglas en planes/plan panel.txt): una tarjeta de VIDRIO que
# flota a 16 px de los bordes sobre el fondo de manchas, con la opción activa en una píldora de
# tinta (negra en el claro, blanca en el oscuro) y las demás en gris, que se encienden con el
# cursor encima.

# Las opciones: texto, icono (assets/iconos/) y ruta de MainController.cambiar_vista. Un texto
# suelto es un título de grupo.
SECCIONES = [
    ("Inicio", "inicio", "home"),
    "GENERAL",
    ("Mi menú", "menu", "menu"),
    ("Mesas", "mesas", "mesas"),
    ("Agente IA", "ia", "agente_financiero"),
    ("Crear contenido", "crear", "contenido"),
    ("Mi biblioteca", "biblio", "biblioteca"),
]
# Abajo: la ayuda por WhatsApp, Ajustes y "Cerrar sesión". La ayuda y cerrar sesión no son
# vistas, son acciones (ver _al_pulsar).
AYUDA = "ayuda"
CERRAR = "cerrar_sesion"
SECCIONES_PIE = [
    ("Ayuda", "ayuda", AYUDA),
    ("Ajustes", "ajustes", "ajustes"),
    ("Cerrar sesión", "salir", CERRAR),
]
# La línea de soporte del desarrollador.
URL_AYUDA = "https://wa.me/5212723662604"
# Una insignia junto al texto de una opción (la pastilla naranja).
INSIGNIAS = {"agente_financiero": "IA", "contenido": "IA"}

# El plan: lo enseñan la marca y el pie. Escrito una sola vez para que no queden distintos.
PLAN = "Básico"

ALTO = 42           # cada opción
RADIO = 12


def crear_barra_lateral(router, activa):
    # ⚠️ El margen va en un contenedor de afuera, sin blur: puesto en el vidrio, flet
    # desenfoca también el margen y alrededor de la barra salía un halo borroso en vez
    # de solo la sombra de la maqueta.
    return ft.Container(
        margin=ft.Margin.only(left=MARGEN, top=MARGEN, right=MARGEN, bottom=MARGEN),
        content=_cuerpo_barra(router, activa),
    )


def _cuerpo_barra(router, activa):
    return vidrio(
        width=ANCHO_BARRA,
        padding=ft.Padding.only(left=12, top=18, right=12, bottom=14),
        contenido=ft.Column([
            ft.Container(padding=ft.Padding.only(left=6, right=6, bottom=18), content=marca()),
            # El menú de arriba ocupa lo que sobra y se desplaza con la rueda en una ventana baja
            # en vez de montarse sobre el de abajo.
            ft.Column([_opcion(router, s, activa) if not isinstance(s, str) else _titulo(s)
                       for s in SECCIONES],
                      spacing=2, expand=True, scroll=ft.ScrollMode.AUTO),
            ft.Column([_opcion(router, s, activa) for s in SECCIONES_PIE], spacing=2),
            ft.Container(height=12),
            _pie_usuario(router),
        ], spacing=0),
    )


def marca():
    # El logo y el nombre. El logo ya trae su cuadro de color (naranja en el tema claro, azul
    # en el oscuro: D.logo_marca); aquí solo se le redondean las esquinas.
    return ft.Row([
        ft.Container(width=40, height=40, border_radius=12, clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                     content=ft.Image(src=D.logo_marca, width=40, height=40, fit=ft.BoxFit.COVER)),
        ft.Column([
            texto("FRAGMENTLESS", 15, 800, espaciado=0.3),
            texto(f"Plan {PLAN}", 10.5, 400, D.tenue, mono=True),
        ], spacing=2, tight=True),
    ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER)


def _titulo(valor):
    return ft.Container(padding=ft.Padding.only(left=14, top=14, right=14, bottom=6),
                        content=etiqueta(valor))


def _opcion(router, seccion, activa):
    nombre, nombre_icono, ruta = seccion
    es_activa = ruta == activa
    color = D.sobre_tinta if es_activa else D.suave
    fila = [icono(nombre_icono, 18, color),
            texto(nombre, 14, 600 if es_activa else 500, color)]
    if ruta in INSIGNIAS:
        fila += [ft.Container(expand=True), insignia(INSIGNIAS[ruta])]
    opcion = ft.Container(
        height=ALTO,
        padding=ft.Padding.symmetric(horizontal=14),
        border_radius=RADIO,
        bgcolor=D.tinta if es_activa else None,
        animate=ft.Animation(150, ft.AnimationCurve.EASE_OUT),
        content=ft.Row(fila, spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        on_click=_al_pulsar(router, ruta),
    )
    if not es_activa:
        def encima(e):
            opcion.bgcolor = D.chip if e.data in (True, "true") else None
            opcion.update()
        opcion.on_hover = sin_auto_update(encima)
    return opcion


def _al_pulsar(router, ruta):
    if ruta == CERRAR:
        async def cerrar(_):
            ft.context.disable_auto_update()
            await router.cerrar_sesion()
        return cerrar
    if ruta == AYUDA:
        return sin_auto_update(lambda _: router.page.launch_url(URL_AYUDA))
    return sin_auto_update(lambda _: router.cambiar_vista(ruta))


def _pie_usuario(router):
    # El pie: el círculo con la inicial, el nombre y el plan, sobre una raya fina. Es un botón:
    # abre la ventana Perfil.
    inicial = texto("", 13, 700)
    nombre = texto("", 13, 700, max_lines=1, no_wrap=True, overflow=ft.TextOverflow.ELLIPSIS)

    def pintar_nombre():
        llamarte = perfil.como_llamarte()
        nombre.value = llamarte
        inicial.value = llamarte[:1].upper()

    pintar_nombre()
    fila = ft.Container(
        padding=ft.Padding.only(left=8, top=8, right=8, bottom=8),
        border_radius=RADIO,
        content=ft.Row([
            ft.Container(width=34, height=34, border_radius=17, bgcolor=D.chip,
                         border=ft.Border.all(1, D.linea), alignment=ft.Alignment.CENTER,
                         content=inicial),
            ft.Column([nombre, texto(PLAN, 10.5, 400, D.tenue, mono=True)],
                      spacing=1, tight=True, expand=True),
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        on_click=sin_auto_update(lambda _: abrir_perfil(router)),
    )

    def encima(e):
        fila.bgcolor = D.chip if e.data in (True, "true") else None
        fila.update()

    def al_cambiar_perfil():
        # Lo llama la ventana Perfil al guardar: el nombre nuevo, sin rehacer la vista.
        pintar_nombre()
        fila.update()

    fila.on_hover = sin_auto_update(encima)
    # Siempre el de la barra que se ve: cada vista hace la suya y la nueva pisa a la vieja.
    router.pintores_perfil = dict(getattr(router, "pintores_perfil", None) or {}, pie=al_cambiar_perfil)
    return ft.Container(
        border=ft.Border(top=ft.BorderSide(1, D.linea)),
        padding=ft.Padding.only(top=4),
        content=fila,
    )
