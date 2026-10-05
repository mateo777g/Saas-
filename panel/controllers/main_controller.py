import asyncio
import os
import traceback

import flet as ft

from models import perfil, saludo_ia
from models.supabase_client import client
from views import tema
from views.agenteIA_view import AgenteIAView
from views.ajustes_view import AjustesView
from views.barra_lateral import crear_barra_lateral
from views.diseno import FUENTES, fondo_manchas
from views.biblioteca_view import BibliotecaView
from views.contenido_view import ContenidoView
from views.home_view import HomeView
from views.menu_view import MenuView
from views.mesas_view import MesasView
from views.piezas import sin_auto_update
from views.sesion_view import SesionView


class MainController:
    def __init__(self, page: ft.Page):
        self.page = page
        self.page.title = "Fragmentless - Panel"
        # El logo en la barra de título y en la de tareas (Flet solo acepta .ico y con ruta
        # absoluta). Si falta el archivo, la ventana se queda con el de Flet.
        icono = os.path.abspath("assets/icono.ico")
        if os.path.exists(icono):
            self.page.window.icon = icono
        # El tema elegido en Ajustes (config.json; el oscuro si no hay). Antes de crear ninguna
        # vista: cada una lee sus colores al construirse (views/tema.py).
        tema.cargar()
        self.page.theme_mode = tema.C.modo
        self.page.bgcolor = tema.D.suelo
        self.page.padding = 0
        # La letra del panel, registrada una sola vez: la barra lateral la usa en todas las
        # vistas. Las familias se llaman por lo que son: cambiar de fuente es cambiar dos líneas.
        fuentes = dict(getattr(self.page, "fonts", {}) or {})
        fuentes["LetraTitulo"] = "assets/PlusJakartaSans-Bold.ttf"
        fuentes["LetraTexto"] = "assets/PlusJakartaSans-Medium.ttf"
        # Coolvetica (condensada), solo para los números grandes de los contadores.
        fuentes["Coolvetica"] = "assets/Coolvetica Rg Cram.otf"
        # Las del diseño nuevo (views/diseno.py), una familia por peso.
        fuentes.update(FUENTES)
        self.page.fonts = fuentes
        # La letra por defecto de todo el panel: así ningún texto se queda en Roboto.
        # divider_color: es el color de las rayas de las tablas del markdown (Agente IA); sin él
        # salían negras. Sale del tema (views/tema.py, D.linea), así que se pone con cada tema.
        self._poner_temas_flet()

        # Eventos de la ventana que llegan aunque nadie los escuche (el tema de Windows, el foco
        # de la ventana...). Sin manejador, Flet hace igual su auto-update, que compara la página
        # entera. Con un manejador vacío sin auto-update, nada (guía, B1 regla 2).
        nada = sin_auto_update(lambda e: None)
        self.page.on_platform_brightness_change = nada
        self.page.on_app_lifecycle_state_change = nada
        self.page.on_locale_change = nada
        self.page.on_media_change = nada

        self.vista_actual = None
        self.content_container = ft.Container(expand=True)
        self.page.add(self.content_container)

        # SIEMPRE arranca en el login. La sesión NO se guarda en disco (2026-09-05): es una
        # decisión de NEGOCIO — ver "POR QUÉ EL LOGIN NO SE GUARDA" del roadmap: con la sesión
        # viva, cortarle la licencia a un local no surtía efecto hasta que venciera su
        # refresh_token; sin ella, el corte pega en el siguiente arranque.
        self.mostrar_login()
        # El saludo del Agente IA se empieza a redactar YA, en la pantalla
        # de entrar: no lee la base (solo el apodo de config.json), así que
        # no necesita la sesión, y para cuando se termina de escribir la
        # contraseña ya está listo (models/saludo_ia.py).
        self.page.run_task(self.precargar_saludo)

    def _poner_temas_flet(self):
        self.page.theme = ft.Theme(font_family="LetraTexto", divider_color=tema.D.linea)
        self.page.dark_theme = ft.Theme(font_family="LetraTexto", divider_color=tema.D.linea)

    # La ventana cambia de tamaño según la pantalla: el login va en una ventana chica y
    # centrada; al entrar al panel se maximiza, y al cerrar sesión vuelve a la chica.
    ANCHO_LOGIN = 1265
    ALTO_LOGIN = 712

    async def _ventana_login(self):
        # La espera corta es porque recién arrancada la ventana nativa ignora los cambios
        # de tamaño (por eso el maximizado de antes también esperaba).
        await asyncio.sleep(0.2)
        ventana = self.page.window
        ventana.maximized = False
        ventana.width = self.ANCHO_LOGIN
        ventana.height = self.ALTO_LOGIN
        self.page.update()
        try:
            await ventana.center()
        except Exception:
            traceback.print_exc()

    async def _ventana_panel(self):
        self.page.window.maximized = True
        self.page.update()

    def _poner_vista(self, vista):
        # Cambia la vista en DOS update(): primero entra la nueva, en un contenedor suyo junto al
        # de la vieja, que se esconde (lo que se ve cambia ya aquí); luego se quita la vieja. En
        # un solo update() Flet cruza cada control quitado con cada puesto, y con una vista
        # grande eso tardaba más de un segundo (guía, B1 regla 10).
        vieja = self.content_container
        self.content_container = ft.Container(expand=True, content=vista)
        vieja.visible = False
        self.page.controls.append(self.content_container)
        self.page.update()
        self.page.controls.remove(vieja)
        self.page.update()

    def mostrar_login(self, motivo=None):
        """La pantalla de entrar: ocupa toda la ventana (la chica del login), sin barra lateral.
        `motivo` es un aviso al llegar ("Cerraste sesión."), si lo hay: sale en la tarjeta."""
        self.vista_actual = None
        self._poner_vista(SesionView(self, motivo))
        self.page.run_task(self._ventana_login)

    def mostrar_panel(self):
        """Entra a Inicio. Solo se llama con una sesión activa en `client.auth` (desde
        SesionView tras un login exitoso y con la licencia activa)."""
        self.cambiar_vista("home")
        self.page.run_task(self._ventana_panel)
        # Por si el de la pantalla de entrar falló o ya no corresponde (otro
        # apodo, otro momento del día); si sigue sirviendo, no pide nada.
        self.page.run_task(self.precargar_saludo)

    async def precargar_saludo(self):
        """Deja un saludo del Agente IA en reserva, en segundo plano. Lo
        llaman mostrar_panel() y la vista del agente al gastar el suyo."""
        try:
            await asyncio.to_thread(saludo_ia.preparar, perfil.como_llamarte())
        except Exception:
            traceback.print_exc()

    async def cerrar_sesion(self):
        """Cierra la sesión y vuelve a la pantalla de entrar. El sign_out va en un hilo aparte
        (es red) y SOLO en esta PC (scope "local"): el valor por defecto de supabase-py es
        GLOBAL, y como los meseros entran a mesas.html con el mismo usuario, les tiraba la
        sesión también. Si el servidor no contesta da igual: la sesión solo vive en memoria."""
        try:
            await asyncio.to_thread(client.auth.sign_out, {"scope": "local"})
        except Exception:
            traceback.print_exc()
        self.mostrar_login("Cerraste sesión.")

    def cambiar_tema(self, nombre):
        # Lo llama Ajustes al elegir otro tema: se guarda y se rehace Ajustes (con su barra) ya
        # con los colores nuevos; las demás vistas se construyen con ellos al abrirlas. La capa
        # de la ventana Perfil vive en page.overlay (se crea una vez): se quita para que la
        # próxima vez nazca con el velo del tema nuevo.
        tema.guardar(nombre)
        self.page.theme_mode = tema.C.modo
        self.page.bgcolor = tema.D.suelo
        self._poner_temas_flet()
        ventana = getattr(self, "ventana_perfil", None)
        if ventana is not None:
            self.page.overlay.remove(ventana["capa"])
            self.ventana_perfil = None
        self.cambiar_vista("ajustes")

    def cambiar_vista(self, vista: str, abrir_dialogo_nuevo: bool = False,
                      ocultar_varios: bool = False):
        """abrir_dialogo_nuevo / ocultar_varios: los usan SOLO los atajos de Inicio ("Agregar un
        producto nuevo", "Marcar un platillo como agotado") para llegar a Mi menú con el diálogo
        de alta abierto o en el modo "Ocultar varios". Se pasan directo al constructor de
        MenuView (no como estado del router) para que no quede una bandera "pegada"."""
        self.vista_actual = vista

        if vista == "home":
            widget = HomeView(self)
        elif vista == "menu":
            widget = MenuView(self, abrir_dialogo_nuevo=abrir_dialogo_nuevo,
                              ocultar_varios=ocultar_varios)
        elif vista == "mesas":
            widget = MesasView(self)
        elif vista == "agente_financiero":
            widget = AgenteIAView(self)
        elif vista == "contenido":
            widget = ContenidoView(self)
        elif vista == "ajustes":
            widget = AjustesView(self)
        elif vista == "biblioteca":
            widget = BibliotecaView(self)
        else:
            self.vista_actual = "home"
            widget = HomeView(self)

        # Detrás de todo va el fondo, y encima la barra (flotante, de vidrio) y la vista, lado a
        # lado. La barra se rehace con cada vista (marca la activa). El fondo de manchas es
        # EXCLUSIVO del agente de IA; en las demás vistas su propio fondo (color + degradado) se
        # sube a toda la ventana, así la barra de vidrio toma el fondo de la vista en la que está.
        if self.vista_actual == "agente_financiero":
            fondo = fondo_manchas()
        else:
            fondo = ft.Container(left=0, top=0, right=0, bottom=0,
                                 bgcolor=widget.bgcolor, gradient=widget.gradient)
            widget.bgcolor = None
            widget.gradient = None
        self._poner_vista(ft.Stack([
            fondo,
            ft.Row(
                [crear_barra_lateral(self, self.vista_actual), widget],
                left=0, top=0, right=0, bottom=0, spacing=0,
                vertical_alignment=ft.CrossAxisAlignment.STRETCH,
            ),
        ], expand=True))
