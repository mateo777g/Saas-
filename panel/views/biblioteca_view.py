"""
views/biblioteca_view.py
Mi biblioteca con el diseño manchas + vidrio (01/10), SIN el fondo de manchas (es exclusivo del
Agente IA): la vista pinta su propio suelo (D.suelo) y MainController lo sube detrás de la barra.
Las reglas están en planes/plan panel.txt ("DISEÑO MANCHAS + VIDRIO"); la maqueta aprobada, en
https://claude.ai/artifact/3Yz1CqyvCrUn5fCKvmaaze.

La galería de lo que hay en la carpeta biblioteca/ (lo que generan Crear contenido y las
plantillas). Todo sale de los archivos: fecha, formato y producto los lee models/biblioteca.py
del nombre de cada uno; el nombre bonito del producto se busca en el menú (si no se puede leer,
queda el del archivo).

- Barra de arriba (vidrio): "Mi biblioteca", chip con cuántos hay, el filtro Todo / Posts /
  Historias (con cuántos de cada uno), Abrir carpeta y Crear anuncio (-> Crear contenido).
- Tarjeta de vidrio: un collage por día ("HOY · JUEVES 1 DE OCTUBRE"). Sin marcos: cada anuncio
  cae en la columna más corta, con su proporción real (post 4:5, historia 9:16). Con el cursor
  encima sale el nombre, el formato y la hora, más Exportar y Eliminar; un clic lo abre en grande.
- Ver en grande (ventana): el anuncio, flechas (y ← → del teclado) para recorrer lo que deja ver
  el filtro, sus datos y Exportar / En carpeta / Eliminar. Escape la cierra.

Exportar copia el archivo a la carpeta de Ajustes (~/Downloads si no hay); se confirma con la
palomita verde en el botón (~1.6 s), sin aviso. Eliminar borra el archivo de disco tras
diseno.confirmar. La carpeta se lee al entrar: nada se refresca solo.
"""
import asyncio
import datetime
import itertools
import traceback

import flet as ft
import flet.canvas as cv

from models import biblioteca
from models.config_usuario import obtener_ruta_exportacion
from models.platillo_dao import PlatilloDAO
from views.diseno import (ALTO_BARRA_SUPERIOR, MARGEN, boton, boton_cuadro, confirmar, etiqueta,
                          icono, punto, texto, ventana, vidrio)
from views.piezas import DIAS, MESES, aviso
from views.tema import D, VERDE

FILTROS = [("todo", "Todo"), ("post", "Posts"), ("historia", "Historias")]
NOMBRE_FORMATO = {"post": "Post", "historia": "Historia"}
MESES_MIN = [m.lower() for m in MESES]

HUECO = 14              # entre los anuncios del collage
ANCHO_COLUMNA = 275     # el ancho que se busca por columna: de ahí cuántas caben (4 en 1440)
OCUPA_FUERA = 276 + MARGEN + 40   # la barra lateral, el margen derecho y el relleno del vidrio
RADIO_PIEZA = 14
BLANCO = "#EBFFFFFF"    # los botones sobre el anuncio (blancos en los dos temas, como la maqueta)
NEGRO = "#0b0b0b"


def _plural(cantidad):
    return "1 anuncio" if cantidad == 1 else f"{cantidad} anuncios"


def _dia(fecha):
    """La cabecera de cada grupo: ("HOY", "JUEVES 1 DE OCTUBRE"), ("AYER", ...) o, más atrás,
    solo la fecha."""
    fecha_larga = f"{DIAS[fecha.weekday()]} {fecha.day} DE {MESES[fecha.month - 1]}"
    if fecha.year != datetime.date.today().year:
        fecha_larga += f" DE {fecha.year}"
    dias = (datetime.date.today() - fecha).days
    if dias == 0:
        return "HOY", fecha_larga
    if dias == 1:
        return "AYER", fecha_larga
    return fecha_larga, ""


def _cuando(fecha):
    # "Hoy, 15:26" / "Ayer, 15:26" / "24 de septiembre, 15:26".
    hora = fecha.strftime("%H:%M")
    dias = (datetime.date.today() - fecha.date()).days
    if dias == 0:
        return f"Hoy, {hora}"
    if dias == 1:
        return f"Ayer, {hora}"
    año = f" de {fecha.year}" if fecha.year != datetime.date.today().year else ""
    return f"{fecha.day} de {MESES_MIN[fecha.month - 1]}{año}, {hora}"


def _hueco_punteado(alto, contenido=None):
    # Los tres anuncios vacíos del estado "sin anuncios" (flet no tiene borde punteado: Canvas).
    return ft.Stack([
        cv.Canvas([cv.Rect(0.75, 0.75, 72 - 1.5, alto - 1.5, border_radius=12,
                           paint=ft.Paint(color=D.linea_fuerte, stroke_width=1.5,
                                          style=ft.PaintingStyle.STROKE,
                                          stroke_dash_pattern=[5, 4]))],
                  width=72, height=alto),
        ft.Container(width=72, height=alto, alignment=ft.Alignment.CENTER, content=contenido),
    ], width=72, height=alto)


def _boton_blanco(nombre_icono, ayuda, al_pulsar):
    # Exportar / Eliminar sobre el anuncio: cuadro blanco de 36, radio 11, con sombra.
    return ft.Container(
        width=36, height=36, border_radius=11, bgcolor=BLANCO, alignment=ft.Alignment.CENTER,
        tooltip=ayuda, on_click=al_pulsar, content=icono(nombre_icono, 16, NEGRO),
        shadow=ft.BoxShadow(blur_radius=14, color="#2E000000", offset=ft.Offset(0, 4)),
    )


def _flecha(nombre_icono, ayuda, al_pulsar, **posicion):
    # Anterior / siguiente en la ventana grande: círculo sólido de 44.
    return ft.Container(
        width=44, height=44, border_radius=22, bgcolor=D.solido,
        border=ft.Border.all(1, D.linea), alignment=ft.Alignment.CENTER, tooltip=ayuda,
        on_click=al_pulsar, content=icono(nombre_icono, 18),
        shadow=ft.BoxShadow(blur_radius=18, color="#1F000000", offset=ft.Offset(0, 6)),
        **posicion,
    )


class BibliotecaView(ft.Container):
    def __init__(self, router):
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        # El suelo liso del tema: MainController lo sube a toda la ventana, detrás de la barra.
        self.bgcolor = D.suelo

        self._anuncios: list[dict] = []
        self._filtro = "todo"
        self._visor = None              # los controles de la ventana grande, mientras está abierta
        self._ancho = None              # lo que mide el collage por dentro (on_size_change)
        self._columnas = None
        self._teclado_anterior = None

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        self.texto_chip = texto("Leyendo tu biblioteca…", 12, 500, D.suave)
        self.caja_filtros = ft.Container(visible=False)
        barra_superior = vidrio(
            radio=18, sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=10),
            contenido=ft.Row([
                texto("Mi biblioteca", 15, 700),
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE), self.texto_chip], spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
                ft.Container(expand=True),
                self.caja_filtros,
                boton("Abrir carpeta", "carpeta", lambda e: self._mostrar_en_carpeta(None)),
                boton("Crear anuncio", "ia", lambda e: self.router.cambiar_vista("contenido"),
                      principal=True),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # El collage
        # --------------------------------------------------------------
        self.cuerpo = ft.Column(spacing=HUECO, expand=True, scroll=ft.ScrollMode.AUTO,
                                horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                                controls=[self._nota("Leyendo tu biblioteca…")])
        # ⚠️ on_size_change en un Container de adentro (en el que lleva top/left, el Stack ya no
        # lo reconoce como posicionado: ver Inicio). Con él se sabe cuántas columnas caben.
        tarjeta = vidrio(
            radio=26, padding=20,
            top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN, bottom=MARGEN,
            contenido=ft.Container(expand=True, content=self.cuerpo,
                                   on_size_change=self._al_cambiar_tamano),
        )

        self.content = ft.Stack([tarjeta, barra_superior], expand=True)

        # Se agenda aquí pero no corre hasta que cambiar_vista() termine de montar la vista.
        self.page_ref.run_task(self._cargar)

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------
    def _actualizar(self, *controles):
        try:
            for c in controles:
                c.update()
        except RuntimeError:
            pass    # se salió de Mi biblioteca antes de que terminara (exportar, leer...)

    @staticmethod
    def _nota(titulo, detalle=None):
        # Los estados de la tarjeta (leyendo, sin conexión a la carpeta, filtro vacío).
        lineas = [texto(titulo, 14.5, 700, text_align=ft.TextAlign.CENTER)]
        if detalle:
            lineas.append(texto(detalle, 12.5, 500, D.suave, text_align=ft.TextAlign.CENTER))
        return ft.Container(
            padding=ft.Padding.symmetric(vertical=80, horizontal=16),
            alignment=ft.Alignment.CENTER,
            content=ft.Column(lineas, spacing=8, tight=True,
                              horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        )

    def _visibles(self):
        return [a for a in self._anuncios if self._filtro in ("todo", a["formato"])]

    # ------------------------------------------------------------------
    # Carga
    # ------------------------------------------------------------------
    async def _cargar(self):
        try:
            anuncios = await asyncio.to_thread(biblioteca.listar)
        except Exception:
            traceback.print_exc()
            self.texto_chip.value = "No se pudo leer"
            self.cuerpo.controls = [self._nota(
                "No se pudo leer tu biblioteca.",
                "Revisa los permisos de la carpeta \"biblioteca\" e intenta de nuevo.")]
            self._actualizar(self.texto_chip, self.cuerpo)
            return

        # Los nombres bonitos salen del menú; si no se puede leer, se quedan los del archivo.
        platillos = []
        if anuncios:
            try:
                platillos = await asyncio.to_thread(PlatilloDAO.obtener_todos)
            except Exception:
                traceback.print_exc()
        self._anuncios = biblioteca.poner_nombres(anuncios, platillos)
        self._pintar()

    # ------------------------------------------------------------------
    # Pintado
    # ------------------------------------------------------------------
    def _pintar(self):
        visibles = self._visibles()
        self.texto_chip.value = f"{_plural(len(self._anuncios))} en esta computadora"
        self.caja_filtros.visible = bool(self._anuncios)
        self.caja_filtros.content = self._selector_filtros()

        if not self._anuncios:
            self.cuerpo.controls = [self._vacio()]
        elif not visibles:
            self.cuerpo.controls = [self._nota(
                "Todavía no hay posts." if self._filtro == "post"
                else "Todavía no hay historias.",
                "Cambia a Todo para ver los demás.")]
        else:
            columnas = self._columnas = self._cuantas_columnas()
            controles = []
            for fecha, del_dia in itertools.groupby(visibles, key=lambda a: a["fecha"].date()):
                del_dia = list(del_dia)
                controles.append(self._cabecera_dia(fecha, len(del_dia)))
                controles.append(self._collage(del_dia, columnas))
            self.cuerpo.controls = controles
        self._actualizar(self.texto_chip, self.caja_filtros, self.cuerpo)

    def _cuantas_columnas(self):
        # Las que caben a ~275 px (4 en una ventana de 1440, 5 maximizada en 1920).
        ancho = self._ancho or (self.page_ref.width or 1440) - OCUPA_FUERA
        return max(2, min(6, int((ancho + HUECO) // ANCHO_COLUMNA)))

    def _al_cambiar_tamano(self, e):
        self._ancho = e.width
        if self._anuncios and self._columnas and self._cuantas_columnas() != self._columnas:
            self._pintar()

    def _selector_filtros(self):
        """Todo / Posts / Historias con cuántos hay de cada uno. Como diseno.selector (caja
        D.chip radio 12; el elegido en sólido con sombra de 1 px), más la cuenta en mono."""
        cuentas = {"todo": len(self._anuncios),
                   "post": sum(a["formato"] == "post" for a in self._anuncios)}
        cuentas["historia"] = cuentas["todo"] - cuentas["post"]
        segmentos = []
        for clave, nombre in FILTROS:
            es = clave == self._filtro
            segmentos.append(ft.Container(
                height=32, padding=ft.Padding.symmetric(horizontal=12), border_radius=9,
                alignment=ft.Alignment.CENTER, bgcolor=D.solido if es else None,
                shadow=ft.BoxShadow(blur_radius=3, color="#26000000", offset=ft.Offset(0, 1))
                if es else None,
                content=ft.Row([texto(nombre, 12.5, 600, D.texto if es else D.suave),
                                texto(str(cuentas[clave]), 10.5, 400, D.tenue, mono=True)],
                               spacing=7, tight=True,
                               vertical_alignment=ft.CrossAxisAlignment.CENTER),
                on_click=lambda e, c=clave: self._elegir_filtro(c),
            ))
        return ft.Container(padding=4, border_radius=12, bgcolor=D.chip,
                            content=ft.Row(segmentos, spacing=2, tight=True))

    @staticmethod
    def _cabecera_dia(fecha, cuantos):
        principal, secundario = _dia(fecha)
        partes = [etiqueta(principal, color=D.texto)]
        if secundario:
            partes.append(etiqueta(secundario))
        partes += [ft.Container(expand=True, height=1, bgcolor=D.linea),
                   etiqueta(_plural(cuantos).upper())]
        return ft.Container(
            padding=ft.Padding.only(left=4, top=4, right=4),
            content=ft.Row(partes, spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

    def _collage(self, anuncios, columnas):
        # Cada anuncio cae en la columna más corta (las alturas, en anchos de columna).
        piezas = [[] for _ in range(columnas)]
        altos = [0.0] * columnas
        for anuncio in anuncios:
            i = altos.index(min(altos))
            piezas[i].append(self._pieza(anuncio))
            altos[i] += anuncio["alto"] / anuncio["ancho"] + 0.05
        return ft.Row(
            [ft.Column(p, spacing=HUECO, expand=1,
                       horizontal_alignment=ft.CrossAxisAlignment.STRETCH) for p in piezas],
            spacing=HUECO, vertical_alignment=ft.CrossAxisAlignment.START,
        )

    def _pieza(self, anuncio):
        """Un anuncio del collage, sin marco. Con el cursor encima: degradado abajo con el
        nombre y "HISTORIA · 15:26", y Exportar / Eliminar arriba a la derecha."""
        boton_exportar = _boton_blanco("exportar", "Exportar",
                                       lambda e: self._exportar(anuncio, en_pieza))
        en_pieza = {"boton": boton_exportar}
        capa = ft.Container(
            left=0, top=0, right=0, bottom=0, visible=False,
            gradient=ft.LinearGradient(begin=ft.Alignment.TOP_CENTER,
                                       end=ft.Alignment.BOTTOM_CENTER,
                                       colors=["#00000000", "#00000000", "#A6000000",
                                               "#E6000000"],
                                       stops=[0, 0.45, 0.75, 1]),
            content=ft.Stack([
                ft.Container(
                    left=14, right=14, bottom=12,
                    content=ft.Column([
                        texto(anuncio["nombre"], 14, 700, "#ffffff", max_lines=1,
                              overflow=ft.TextOverflow.ELLIPSIS),
                        texto(f"{NOMBRE_FORMATO[anuncio['formato']].upper()} · "
                              f"{anuncio['fecha'].strftime('%H:%M')}", 10.5, 400, "#D9FFFFFF",
                              mono=True, espaciado=0.6),
                    ], spacing=3, tight=True),
                ),
                ft.Container(
                    top=10, right=10,
                    content=ft.Row([
                        boton_exportar,
                        _boton_blanco("eliminar", "Eliminar",
                                      lambda e: self._pedir_eliminar(anuncio)),
                    ], spacing=6, tight=True),
                ),
            ]),
        )
        pieza = ft.Container(
            aspect_ratio=anuncio["ancho"] / anuncio["alto"],
            border_radius=RADIO_PIEZA, bgcolor=D.chip, clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            on_click=lambda e: self._abrir_visor(anuncio),
            content=ft.Stack([
                # cache_width: se decodifica a 600 px, no a 1080 (con muchos anuncios, memoria).
                ft.Image(src=anuncio["ruta"], fit=ft.BoxFit.COVER, cache_width=600,
                         gapless_playback=True, left=0, top=0, right=0, bottom=0,
                         error_content=ft.Container(alignment=ft.Alignment.CENTER,
                                                    content=icono("biblio", 22, D.tenue))),
                capa,
            ]),
        )

        def encima(e):
            si = e.data in (True, "true")
            capa.visible = si
            pieza.shadow = (ft.BoxShadow(blur_radius=34, color="#38000000",
                                         offset=ft.Offset(0, 14)) if si else None)
            self._actualizar(pieza)

        pieza.on_hover = encima
        return pieza

    def _vacio(self):
        return ft.Container(
            padding=ft.Padding.symmetric(vertical=90, horizontal=40),
            alignment=ft.Alignment.CENTER,
            content=ft.Column([
                ft.Row([_hueco_punteado(90),
                        _hueco_punteado(128, icono("biblio", 22, D.suave)),
                        _hueco_punteado(90)],
                       spacing=10, tight=True, vertical_alignment=ft.CrossAxisAlignment.END),
                ft.Container(height=10),
                texto("Todavía no hay anuncios", 18, 800, espaciado=-0.3),
                texto("Cada anuncio que generes en Crear contenido se guarda aquí solito.", 13,
                      500, D.suave, alto=1.45, text_align=ft.TextAlign.CENTER),
                ft.Container(height=8),
                boton("Crear mi primer anuncio", "ia",
                      lambda e: self.router.cambiar_vista("contenido"), principal=True, alto=44),
            ], spacing=12, tight=True, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        )

    # ------------------------------------------------------------------
    # Ver en grande
    # ------------------------------------------------------------------
    def _abrir_visor(self, anuncio):
        """La ventana grande. Se arma una vez; las flechas solo cambian la imagen y los textos
        (_mostrar_en_visor), sin cerrarla."""
        alto = max(420, min(720, (self.page_ref.height or 900) - 180))
        ancho = max(860, min(1020, (self.page_ref.width or 1440) - 80))
        v = {
            "anuncio": anuncio,
            "imagen": ft.Image(src=anuncio["ruta"], height=alto - 56, fit=ft.BoxFit.CONTAIN,
                               border_radius=12, gapless_playback=True),
            "posicion": etiqueta(""),
            "nombre": texto("", 24, 800, espaciado=-0.5, alto=1.15),
            "formato": texto("", 13, 500, D.suave),
            "medida": texto("", 12, 400, mono=True),
            "creado": texto("", 12.5, 600),
            "archivo": texto("", 11, 400, D.suave, mono=True, alto=1.5),
            "flechas": [],
        }
        v["exportar"] = boton("Exportar", "exportar",
                              lambda e: self._exportar(v["anuncio"], v), principal=True, alto=46)
        v["exportar"].alignment = ft.Alignment.CENTER
        v["flechas"] = [
            _flecha("anterior", "Anterior", lambda e: self._mover_visor(-1),
                    left=14, top=(alto - 44) / 2),
            _flecha("siguiente", "Siguiente", lambda e: self._mover_visor(1),
                    right=14, top=(alto - 44) / 2),
        ]
        self._visor = v

        def dato(nombre, valor):
            return ft.Container(
                padding=ft.Padding.symmetric(vertical=12),
                border=ft.Border(bottom=ft.BorderSide(1, D.linea)),
                content=ft.Row([texto(nombre, 12.5, 500, D.tenue), ft.Container(expand=True),
                                valor], vertical_alignment=ft.CrossAxisAlignment.CENTER),
            )

        def ancho_completo(control):
            control.alignment = ft.Alignment.CENTER
            control.expand = 1
            return control

        zona = ft.Container(
            expand=True, height=alto, border_radius=18, bgcolor=D.chip,
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Stack([
                ft.Container(left=0, top=0, right=0, bottom=0, alignment=ft.Alignment.CENTER,
                             content=ft.Container(
                                 border_radius=12, content=v["imagen"],
                                 shadow=ft.BoxShadow(blur_radius=40, color="#40000000",
                                                     offset=ft.Offset(0, 16)))),
                *v["flechas"],
            ]),
        )
        lado = ft.Container(width=300, height=alto, content=ft.Column([
            ft.Row([ft.Container(expand=True, content=v["posicion"]),
                    boton_cuadro("cerrar", lambda e: self._cerrar_visor(), "Cerrar")],
                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
            ft.Container(height=18),
            v["nombre"],
            ft.Container(height=8),
            v["formato"],
            ft.Container(height=24),
            ft.Container(
                border=ft.Border(top=ft.BorderSide(1, D.linea)),
                content=ft.Column([
                    dato("Tamaño", v["medida"]),
                    dato("Creado", v["creado"]),
                    ft.Container(
                        padding=ft.Padding.symmetric(vertical=12),
                        border=ft.Border(bottom=ft.BorderSide(1, D.linea)),
                        content=ft.Column([texto("Archivo", 12.5, 500, D.tenue), v["archivo"]],
                                          spacing=6, tight=True),
                    ),
                ], spacing=0, tight=True),
            ),
            ft.Container(expand=True),
            v["exportar"],
            ft.Row([texto("Se copia a", 11.5, 500, D.tenue),
                    texto(obtener_ruta_exportacion(), 11.5, 400, D.suave, mono=True,
                          max_lines=1, overflow=ft.TextOverflow.ELLIPSIS, expand=True)],
                   spacing=6),
            ft.Container(height=4),
            ft.Row([
                ancho_completo(boton("En carpeta", "carpeta",
                                     lambda e: self._mostrar_en_carpeta(v["anuncio"]))),
                ancho_completo(boton("Eliminar", "eliminar",
                                     lambda e: self._pedir_eliminar(v["anuncio"],
                                                                    desde_visor=True))),
            ], spacing=10),
        ], spacing=0, horizontal_alignment=ft.CrossAxisAlignment.STRETCH))

        self._mostrar_en_visor(anuncio, actualizar=False)
        self.page_ref.show_dialog(ventana(ft.Row([zona, lado], spacing=24, height=alto), ancho))

        # ← → recorren y Escape cierra, mientras está abierta (como la ventana Perfil: se
        # cambia el manejador sin page.update()).
        self._teclado_anterior = self.page_ref.on_keyboard_event
        self.page_ref.on_keyboard_event = self._al_teclear

    def _mostrar_en_visor(self, anuncio, actualizar=True):
        v = self._visor
        visibles = self._visibles()
        v["anuncio"] = anuncio
        v["imagen"].src = anuncio["ruta"]
        v["posicion"].value = f"{visibles.index(anuncio) + 1} DE {len(visibles)}"
        v["nombre"].value = anuncio["nombre"]
        v["formato"].value = f"{NOMBRE_FORMATO[anuncio['formato']]} de Instagram"
        v["medida"].value = f"{anuncio['ancho']} × {anuncio['alto']}"
        v["creado"].value = _cuando(anuncio["fecha"])
        v["archivo"].value = anuncio["archivo"]
        for flecha in v["flechas"]:
            flecha.visible = len(visibles) > 1
        if actualizar:
            self._actualizar(v["imagen"], v["posicion"], v["nombre"], v["formato"], v["medida"],
                             v["creado"], v["archivo"])

    def _mover_visor(self, paso):
        if not self._visor:
            return
        visibles = self._visibles()
        if len(visibles) < 2:
            return
        i = visibles.index(self._visor["anuncio"])
        self._mostrar_en_visor(visibles[(i + paso) % len(visibles)])

    def _al_teclear(self, e):
        ft.context.disable_auto_update()
        if e.key == "Escape":
            self._cerrar_visor()
        elif e.key == "Arrow Left":
            self._mover_visor(-1)
        elif e.key == "Arrow Right":
            self._mover_visor(1)

    def _cerrar_visor(self):
        if not self._visor:
            return
        self._visor = None
        if self.page_ref.on_keyboard_event == self._al_teclear:
            self.page_ref.on_keyboard_event = self._teclado_anterior
        self.page_ref.pop_dialog()

    # ------------------------------------------------------------------
    # Acciones
    # ------------------------------------------------------------------
    def _elegir_filtro(self, clave):
        if clave != self._filtro:
            self._filtro = clave
            self._pintar()

    def _mostrar_en_carpeta(self, anuncio):
        try:
            biblioteca.mostrar_en_carpeta(anuncio)
        except Exception:
            traceback.print_exc()
            aviso(self.page_ref, "No se pudo abrir la carpeta.")

    def _exportar(self, anuncio, donde):
        self.page_ref.run_task(self._exportar_async, anuncio, donde)

    async def _exportar_async(self, anuncio, donde):
        """`donde` es la pieza del collage o la ventana grande: su botón Exportar se vuelve
        palomita verde un momento (sin aviso: así confirma todo el panel)."""
        try:
            await asyncio.to_thread(biblioteca.exportar, anuncio)
        except OSError:
            traceback.print_exc()
            aviso(self.page_ref, "No se pudo copiar. Revisa la carpeta de exportación en Ajustes.")
            return
        except Exception:
            traceback.print_exc()
            aviso(self.page_ref, "No se pudo exportar el anuncio. Intenta de nuevo.")
            return
        en_visor = donde is self._visor
        boton_exportar = donde["exportar"] if en_visor else donde["boton"]
        antes = boton_exportar.content
        if en_visor:
            boton_exportar.content = ft.Row(
                [icono("check", 16, VERDE), texto("Exportado", 13, 600, D.sobre_tinta)],
                spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER)
        else:
            boton_exportar.content = icono("check", 16, VERDE)
        self._actualizar(boton_exportar)
        await asyncio.sleep(1.6)
        boton_exportar.content = antes
        self._actualizar(boton_exportar)

    def _pedir_eliminar(self, anuncio, desde_visor=False):
        # Desde la ventana grande: confirmar la reemplaza; Cancelar la vuelve a abrir.
        if desde_visor:
            self._cerrar_visor()
        confirmar(
            self.page_ref,
            titulo="¿Eliminar este anuncio?",
            mensaje="Se borra de esta computadora y no se puede deshacer. Si ya lo exportaste, "
                    "esa copia se queda.",
            imagen=ft.Image(src=anuncio["ruta"], width=72,
                            height=round(72 * anuncio["alto"] / anuncio["ancho"]),
                            fit=ft.BoxFit.COVER, border_radius=10, cache_width=200),
            al_cancelar=(lambda: self._abrir_visor(anuncio)) if desde_visor else None,
            al_confirmar=lambda: self.page_ref.run_task(self._eliminar_async, anuncio,
                                                        desde_visor),
        )

    async def _eliminar_async(self, anuncio, desde_visor):
        visibles = self._visibles()
        try:
            await asyncio.to_thread(biblioteca.eliminar, anuncio)
        except Exception:
            traceback.print_exc()
            aviso(self.page_ref, "No se pudo eliminar el anuncio. Intenta de nuevo.")
            return
        self._anuncios = [a for a in self._anuncios if a is not anuncio]
        self._pintar()
        # Borrado desde la ventana grande: se vuelve a abrir en el que seguía.
        quedan = [a for a in visibles if a is not anuncio]
        if desde_visor and quedan:
            self._abrir_visor(quedan[min(visibles.index(anuncio), len(quedan) - 1)])
