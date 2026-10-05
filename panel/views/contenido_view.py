"""
views/contenido_view.py
Crear contenido CON IA (01/10), diseño manchas + vidrio SIN el fondo de manchas (es exclusivo del
Agente IA): la vista pinta su suelo (D.suelo) y MainController lo sube detrás de la barra.
Maqueta aprobada, pasada tal cual: https://claude.ai/artifact/EzzYQTCWrHhJJ2Bbmx1WPG. Lo único
que allí era de muestra (la imagen con la etiqueta MUESTRA) aquí es el anuncio real.

UNA sola pantalla con todo a la vista (lo pidió el desarrollador: nada de pasos que cambian de
pantalla):
- Barra de arriba (vidrio): "Crear contenido", chip "Tus anuncios se guardan en Mi biblioteca" y
  "Datos del negocio" (abre components/dialogo_negocio.py).
- Tarjeta "NUEVO ANUNCIO" (vidrio) con tres secciones en sólido, cada una con su número que se
  vuelve palomita verde al llenarse: 1 Producto (TODOS los platillos del menú, con foto o
  sin-foto.png, buscador sin acentos en memoria), 2 Formato (post 1080×1350 / historia
  1080×1920) y 3 ¿Qué quieres decir? (texto libre). Abajo "Irá en el anuncio: ..." (los datos
  del negocio que lleva ese formato) con "Editar", y "Generar anuncio", que se enciende con las
  tres.
- Fila OPCIONAL (01/10, noche; maqueta https://claude.ai/artifact/AuWieY9WJjgHoNnVpb7hiw), sin
  número ni palomita: "Color" (cuadrito + código; abre components/dialogo_color.py), el botón de
  volver al rojo (apagado mientras esté el rojo) y "Combinar" (abre components/dialogo_combinar.py;
  apagado sin producto; con combo, fotitos + nombres y la X para quitarlo). El color NO se
  recuerda: cada visita empieza en rojo. Para hacerle sitio, la sección 3 ya no ocupa tanto.
- Tarjeta "RESULTADO" (vidrio, 440 de ancho): vacío (marco punteado) / generando (rueda) /
  listo (la imagen + "Guardado en Mi biblioteca", Generar otra, Abrir carpeta) / error.

La imagen la hace models/generador_ia.py (gpt-image-2.5-sunburst, bloqueante: va con
asyncio.to_thread) y la guarda en biblioteca/, donde Mi biblioteca ya la ve. Las PLANTILLAS de
antes no se borraron: su vista está en views/contenido_plantillas_view.py, sin ruta ni botón,
para reintegrarla después.
"""
import asyncio
import os
import subprocess
import traceback
import unicodedata

import flet as ft
import flet.canvas as cv
import httpx
import openai

from models import generador_ia
from models.datos_negocio_dao import DatosNegocioDAO
from models.platillo_dao import PlatilloDAO
from views.components.dialogo_color import ROJO_MUESTRA, DialogoColor
from views.components.dialogo_combinar import DialogoCombinar
from views.components.dialogo_negocio import DialogoNegocio
from views.diseno import (ALTO_BARRA_SUPERIOR, MARGEN, apagar, boton, boton_cuadro, etiqueta,
                          icono, punto, texto, vidrio)
from views.tema import D, VERDE

ANCHO_RESULTADO = 440
COLUMNAS_PRODUCTOS = 5
# Alto de una tarjeta de producto (6 + foto 96 + 8 + nombre + precio + 10) más el anillo de 2 px
# de la elegida (con su respiro): se ve un renglón y los demás se alcanzan con la rueda del ratón.
ALTO_PRODUCTOS = 164

# formato -> (título, medidas, qué lleva, nombre corto, etiqueta del resultado, marco ancho×alto)
FORMATOS = {
    "post": ("Post de Instagram", "1080 × 1350", "Lleva el nombre y el teléfono.", "post",
             "POST · 1080 × 1350", (360, 450)),
    "historia": ("Historia de Instagram", "1080 × 1920",
                 "Nombre, teléfono, página web y dirección.", "historia",
                 "HISTORIA · 1080 × 1920", (288, 512)),
}


def _sin_acentos(valor: str) -> str:
    descompuesto = unicodedata.normalize("NFD", valor or "")
    return "".join(c for c in descompuesto if unicodedata.category(c) != "Mn").lower()


def _anillo(elegido):
    # El anillo de 2 px en tinta de lo elegido (box-shadow 0 0 0 2px de la maqueta).
    return ft.BoxShadow(spread_radius=2, blur_radius=0, color=D.tinta) if elegido else None


def _marca(numero, listo):
    """El número de cada sección (1, 2, 3) que se vuelve palomita verde al llenarse."""
    if listo:
        return ft.Container(width=24, height=24, border_radius=12, bgcolor=VERDE,
                            alignment=ft.Alignment.CENTER, content=icono("check", 13, "#ffffff"))
    return ft.Container(width=24, height=24, border_radius=12, bgcolor=D.chip,
                        border=ft.Border.all(1, D.linea), alignment=ft.Alignment.CENTER,
                        content=texto(str(numero), 11, 400, D.suave, mono=True))


def _seccion(contenido, expand=None, espacio=14):
    # Las tres secciones de la tarjeta: sólido, borde fino, radio 18, padding 16.
    return ft.Container(padding=16, bgcolor=D.solido, border=ft.Border.all(1, D.linea),
                        border_radius=18, expand=expand,
                        content=ft.Column(contenido, spacing=espacio, tight=expand is None))


def _marco_punteado(ancho, alto, contenido):
    # El marco de los estados vacío y error: borde punteado de 1.5 px en D.linea_fuerte (flet no
    # tiene borde punteado: se dibuja en un Canvas detrás).
    return ft.Stack([
        cv.Canvas([cv.Rect(0.75, 0.75, ancho - 1.5, alto - 1.5, border_radius=18,
                           paint=ft.Paint(color=D.linea_fuerte, stroke_width=1.5,
                                          style=ft.PaintingStyle.STROKE,
                                          stroke_dash_pattern=[5, 4]))],
                  width=ancho, height=alto),
        ft.Container(width=ancho, height=alto, padding=24, alignment=ft.Alignment.CENTER,
                     content=contenido),
    ], width=ancho, height=alto)


def _boton_ancho(etiqueta_boton, nombre_icono, al_pulsar, principal=False):
    # Los dos botones bajo el anuncio listo, a lo ancho y centrados (alto 40, radio 12).
    color = D.sobre_tinta if principal else D.texto
    cuerpo = ft.Container(
        expand=1, height=40, border_radius=12, alignment=ft.Alignment.CENTER,
        bgcolor=D.tinta if principal else None,
        border=None if principal else ft.Border.all(1, D.linea),
        content=ft.Row([icono(nombre_icono, 16, color), texto(etiqueta_boton, 13, 600, color)],
                       spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        on_click=al_pulsar, animate_opacity=150,
    )

    def encima(e):
        cuerpo.opacity = 0.86 if e.data in (True, "true") else 1
        cuerpo.update()

    cuerpo.on_hover = encima
    return cuerpo


def _boton_opcion(contenido, al_pulsar):
    # Los botones de la fila OPCIONAL (Color, Combinar): alto 36, radio 11, borde fino.
    cuerpo = ft.Container(height=36, border_radius=11, border=ft.Border.all(1, D.linea),
                          padding=ft.Padding.symmetric(horizontal=12), content=contenido,
                          on_click=al_pulsar, animate_opacity=150)

    def encima(e):
        if not cuerpo.disabled:
            cuerpo.bgcolor = D.chip if e.data in (True, "true") else None
            cuerpo.update()

    cuerpo.on_hover = encima
    return cuerpo


def _mensaje_de_error(error: Exception) -> str:
    """Los errores de la generación en palabras del dueño (sin llave, sin saldo, sin red...)."""
    if isinstance(error, generador_ia.SinLlave):
        return "Falta la llave de OpenAI en este panel. Pide ayuda a soporte."
    if isinstance(error, openai.AuthenticationError):
        return "La llave de OpenAI no es válida. Pide ayuda a soporte."
    if isinstance(error, openai.PermissionDeniedError):
        return "Tu cuenta de OpenAI no tiene acceso al modelo de imágenes. Pide ayuda a soporte."
    if isinstance(error, openai.RateLimitError):
        if "insufficient_quota" in str(error) or getattr(error, "code", "") == "insufficient_quota":
            return "Se acabó el saldo de OpenAI. Recárgalo para seguir generando anuncios."
        return "Se pidieron muchas imágenes seguidas. Espera un minuto e inténtalo otra vez."
    if isinstance(error, openai.BadRequestError):
        return "OpenAI no aceptó este anuncio. Cambia el mensaje e inténtalo otra vez."
    if isinstance(error, (openai.APIConnectionError, httpx.RequestError)):
        return "No se pudo generar el anuncio. Revisa tu conexión e inténtalo otra vez."
    return "No se pudo generar el anuncio. Inténtalo otra vez."


class ContenidoView(ft.Container):
    def __init__(self, router):
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        # El suelo liso del tema: MainController lo sube a toda la ventana, detrás de la barra.
        self.bgcolor = D.suelo

        self._platillos: list[dict] | None = None     # None = cargando o no se pudo
        self._error_menu = None
        self._datos: dict | None = None                # None = sin leer (o falló)
        self._datos_error = False
        self._busqueda = ""
        self._producto: dict | None = None
        self._formato: str | None = None
        # Opcionales: el color (None = el rojo de siempre; no se recuerda entre visitas) y los
        # productos que acompañan al principal (combo, máximo 2 extra).
        self._color: str | None = None
        self._extras: list[dict] = []
        # Estado del resultado: "vacio" / "generando" / "listo" / "error", y lo que se pidió.
        self._fase = "vacio"
        self._pedido: dict | None = None
        self._ruta: str | None = None
        self._error = ""

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        barra_superior = vidrio(
            radio=18, sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=12),
            contenido=ft.Row([
                texto("Crear contenido", 15, 700),
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE),
                                    texto("Tus anuncios se guardan en Mi biblioteca", 12, 500,
                                          D.suave)],
                                   spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
                ft.Container(expand=True),
                boton("Datos del negocio", "tienda", self._abrir_datos),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # 1 Producto
        # --------------------------------------------------------------
        self.marca1 = ft.Container(content=_marca(1, False))
        self.campo_buscar = ft.TextField(
            hint_text="Buscar en tu menú", border=ft.InputBorder.NONE, filled=False, dense=True,
            text_size=12.5, text_style=ft.TextStyle(font_family="Jakarta500", color=D.texto),
            hint_style=ft.TextStyle(font_family="Jakarta500", color=D.tenue, size=12.5),
            content_padding=ft.Padding.symmetric(vertical=8), cursor_color=D.texto,
            expand=True, on_change=self._on_buscar,
        )
        buscador = ft.Container(
            width=220, height=36, border_radius=11, border=ft.Border.all(1, D.linea),
            padding=ft.Padding.symmetric(horizontal=12),
            content=ft.Row([icono("buscar", 15, D.tenue), self.campo_buscar], spacing=8,
                           vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )
        self.rejilla = ft.Column(spacing=10, scroll=ft.ScrollMode.AUTO,
                                 controls=[self._nota("Cargando tu menú…")])
        seccion_producto = _seccion([
            ft.Row([
                self.marca1,
                ft.Column([
                    texto("Producto", 14.5, 700),
                    texto("De tu menú. La IA usa su foto para que salga tu producto real.", 12,
                          500, D.tenue),
                ], spacing=2, tight=True, expand=True),
                buscador,
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            ft.Container(height=ALTO_PRODUCTOS, content=self.rejilla),
        ])

        # --------------------------------------------------------------
        # 2 Formato
        # --------------------------------------------------------------
        self.marca2 = ft.Container(content=_marca(2, False))
        self.tarjetas_formato = {clave: self._tarjeta_formato(clave) for clave in FORMATOS}
        seccion_formato = _seccion([
            ft.Row([self.marca2, texto("Formato", 14.5, 700)], spacing=10,
                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
            # Las dos del mismo alto aunque una descripción ocupe dos renglones.
            ft.Row(list(self.tarjetas_formato.values()), spacing=10, intrinsic_height=True,
                   vertical_alignment=ft.CrossAxisAlignment.STRETCH),
        ])

        # --------------------------------------------------------------
        # 3 ¿Qué quieres decir?
        # --------------------------------------------------------------
        self.marca3 = ft.Container(content=_marca(3, False))
        self.campo_mensaje = ft.TextField(
            hint_text="Ej. 2x1 en frappés todos los viernes de octubre.",
            multiline=True, min_lines=2, max_lines=None, border=ft.InputBorder.NONE,
            filled=False, dense=True, content_padding=0,
            text_size=13.5,
            text_style=ft.TextStyle(font_family="Jakarta400", color=D.texto, height=1.5),
            hint_style=ft.TextStyle(font_family="Jakarta400", color=D.tenue, size=13.5,
                                    height=1.5),
            cursor_color=D.texto, on_change=self._on_escribir,
        )
        caja_mensaje = ft.Container(
            expand=True, padding=ft.Padding.symmetric(horizontal=14, vertical=10),
            border_radius=12, border=ft.Border.all(1, D.linea),
            content=ft.Column([self.campo_mensaje], spacing=0,
                              horizontal_alignment=ft.CrossAxisAlignment.STRETCH),
            # El área vacía de la caja también lleva al campo (como un textarea).
            on_click=lambda e: self.campo_mensaje.focus(),
        )
        # Con combo no sale el precio del menú: se avisa bajo la caja.
        self.nota_combo = ft.Container(
            visible=False, margin=ft.Margin.only(top=-4),
            content=ft.Row([icono("info", 14, D.tenue),
                            texto("Con combo no sale el precio del menú: escribe el precio del "
                                  "combo en tu mensaje.", 12, 500, D.tenue, expand=True)],
                           spacing=8, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )
        # Ya no se estira tanto como antes (lo que se escribe es poco): unos 3 renglones; el
        # espacio que soltó es para la fila OPCIONAL de abajo.
        seccion_mensaje = _seccion([
            ft.Row([self.marca3, texto("¿Qué quieres decir?", 14.5, 700)], spacing=10,
                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
            caja_mensaje,
            self.nota_combo,
        ], expand=True, espacio=12)

        # --------------------------------------------------------------
        # OPCIONAL: color del anuncio y combinar productos (sin número ni palomita)
        # --------------------------------------------------------------
        self.muestra_color = ft.Container(width=18, height=18, border_radius=5,
                                          border=ft.Border.all(1, "#1F000000"))
        self.valor_color = texto("", 11, 400, D.tenue, mono=True)
        self.boton_color = _boton_opcion(
            ft.Row([self.muestra_color, texto("Color", 13, 600), self.valor_color], spacing=9,
                   tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            self._abrir_color)
        self.boton_color.padding = ft.Padding.only(left=9, right=12)
        self.boton_color.tooltip = "Elegir el color del anuncio"
        self.boton_rojo = boton_cuadro("volver", self._volver_rojo, "Volver al rojo de siempre")
        self.cuenta_combo = texto("", 11, 400, D.tenue, mono=True)
        self.boton_combinar = _boton_opcion(
            ft.Row([icono("combinar", 16), texto("Combinar", 13, 600), self.cuenta_combo],
                   spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            self._abrir_combinar)
        self.boton_combinar.tooltip = "Poner hasta 3 productos en el mismo anuncio"
        self.fotos_combo = ft.Stack(height=24)
        self.resumen_combo = ft.Text(size=12, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)
        # Con combo los nombres casi nunca caben enteros: completos en la ayuda del ratón.
        self.zona_resumen = ft.Container(content=self.resumen_combo, expand=1)
        self.boton_quitar_combo = boton_cuadro("cerrar", self._quitar_combo, "Quitar el combo")
        fila_opciones = ft.Container(
            padding=ft.Padding.only(left=16, top=12, right=14, bottom=12),
            bgcolor=D.solido, border=ft.Border.all(1, D.linea), border_radius=18,
            content=ft.Row([
                etiqueta("OPCIONAL"),
                ft.Container(width=4),
                self.boton_color,
                self.boton_rojo,
                ft.Container(width=1, height=24, bgcolor=D.linea,
                             margin=ft.Margin.symmetric(horizontal=4)),
                self.boton_combinar,
                ft.Row([self.fotos_combo, self.zona_resumen], spacing=8, expand=True,
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
                self.boton_quitar_combo,
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # Pie: lo que irá en el anuncio + Generar
        # --------------------------------------------------------------
        self.texto_van = ft.Text(max_lines=1, overflow=ft.TextOverflow.ELLIPSIS, expand=1,
                                 expand_loose=True)
        editar = ft.Container(
            content=ft.Text("Editar", size=12, font_family="Jakarta600", color=D.texto,
                            style=ft.TextStyle(decoration=ft.TextDecoration.UNDERLINE)),
            on_click=self._abrir_datos,
        )
        self.boton_generar = ft.Container(height=44, border_radius=12,
                                          padding=ft.Padding.symmetric(horizontal=20),
                                          on_click=self._on_generar)
        pie = ft.Container(
            padding=ft.Padding.symmetric(horizontal=4),
            content=ft.Row([
                ft.Row([self.texto_van, editar], spacing=8, expand=True,
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
                self.boton_generar,
            ], spacing=16, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        tarjeta_nuevo = vidrio(
            radio=26, padding=20, expand=True,
            contenido=ft.Column([
                ft.Container(
                    padding=ft.Padding.only(left=4, top=4, right=4),
                    content=ft.Column([
                        etiqueta("NUEVO ANUNCIO"),
                        texto("Elige un producto, el formato y lo que quieres decir. La IA "
                              "arma el anuncio con los datos de tu negocio.", 12.5, 500,
                              D.suave, alto=1.45),
                    ], spacing=6, tight=True),
                ),
                seccion_producto,
                seccion_formato,
                seccion_mensaje,
                fila_opciones,
                pie,
            ], spacing=14),
        )

        # --------------------------------------------------------------
        # Resultado
        # --------------------------------------------------------------
        self.texto_formato_resultado = etiqueta("")
        self.zona_marco = ft.Container(expand=True, alignment=ft.Alignment.CENTER)
        self.zona_acciones = ft.Column([
            ft.Container(
                padding=ft.Padding.symmetric(horizontal=4),
                content=ft.Row([icono("check-fino", 16, VERDE),
                                texto("Guardado en Mi biblioteca", 12.5, 600)], spacing=8),
            ),
            ft.Row([
                _boton_ancho("Generar otra", "actualizar", self._on_generar),
                _boton_ancho("Abrir carpeta", "carpeta", self._on_abrir_carpeta,
                             principal=True),
            ], spacing=10),
        ], spacing=12, visible=False)
        tarjeta_resultado = vidrio(
            radio=26, padding=20, width=ANCHO_RESULTADO,
            contenido=ft.Column([
                ft.Container(
                    padding=ft.Padding.only(left=4, top=4, right=4),
                    content=ft.Row([etiqueta("RESULTADO"), ft.Container(expand=True),
                                    self.texto_formato_resultado], spacing=12),
                ),
                self.zona_marco,
                self.zona_acciones,
            ], spacing=16),
        )

        cuerpo = ft.Row([tarjeta_nuevo, tarjeta_resultado], spacing=MARGEN,
                        vertical_alignment=ft.CrossAxisAlignment.STRETCH,
                        top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN,
                        bottom=MARGEN)

        self.content = ft.Stack([cuerpo, barra_superior], expand=True)
        self._pintar_estado(actualizar=False)

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
            pass    # se salió de Crear contenido antes de que llegaran los datos

    @staticmethod
    def _nota(mensaje):
        return ft.Container(padding=ft.Padding.symmetric(vertical=18),
                            alignment=ft.Alignment.CENTER,
                            content=texto(mensaje, 12.5, 500, D.suave,
                                          text_align=ft.TextAlign.CENTER))

    def _listo(self):
        mensaje = (self.campo_mensaje.value or "").strip()
        return self._producto is not None and self._formato is not None and bool(mensaje)

    # ------------------------------------------------------------------
    # Carga: el menú y los datos del negocio, uno tras otro (varias consultas a la vez en el
    # mismo cliente fallaban con WinError 10035, ver Inicio).
    # ------------------------------------------------------------------
    async def _cargar(self):
        try:
            self._platillos = await asyncio.to_thread(PlatilloDAO.obtener_todos)
        except httpx.RequestError:
            traceback.print_exc()
            self._error_menu = "No hay conexión con el servidor. Revisa tu internet."
        except Exception:
            traceback.print_exc()
            self._error_menu = "No se pudo cargar tu menú. Intenta de nuevo en un momento."
        self._pintar_productos()

        await self._leer_datos()

    async def _leer_datos(self):
        try:
            self._datos = await asyncio.to_thread(DatosNegocioDAO.obtener)
            self._datos_error = False
        except Exception:
            traceback.print_exc()
            self._datos = None
            self._datos_error = True
        self._pintar_van()

    # ------------------------------------------------------------------
    # Pintado
    # ------------------------------------------------------------------
    def _pintar_productos(self, actualizar=True):
        if self._platillos is None:
            controles = [self._nota(self._error_menu or "Cargando tu menú…")]
        elif not self._platillos:
            controles = [self._nota("Todavía no hay productos en tu menú.")]
        else:
            q = _sin_acentos(self._busqueda.strip())
            lista = [p for p in self._platillos
                     if not q or q in _sin_acentos(p.get("nombre", ""))]
            if not lista:
                controles = [self._nota("No hay productos con ese nombre en tu menú.")]
            else:
                tarjetas = [self._tarjeta_producto(p) for p in lista]
                # Huecos al final para que el último renglón no estire sus tarjetas.
                tarjetas += [ft.Container(expand=1)
                             for _ in range(-len(tarjetas) % COLUMNAS_PRODUCTOS)]
                controles = [ft.Row(tarjetas[i:i + COLUMNAS_PRODUCTOS], spacing=10)
                             for i in range(0, len(tarjetas), COLUMNAS_PRODUCTOS)]
        # Un respiro de 2 px para que el anillo de la elegida no se corte en el borde.
        self.rejilla.controls = [ft.Container(padding=2, content=ft.Column(controles,
                                                                           spacing=10))]
        if actualizar:
            self._actualizar(self.rejilla)

    def _tarjeta_producto(self, platillo):
        elegido = self._producto is not None and self._producto.get("id") == platillo.get("id")
        foto = platillo.get("image_url") or "assets/sin-foto.png"
        capas = [ft.Column([
            ft.Container(height=96, border_radius=10, clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                         content=ft.Image(src=foto, fit=ft.BoxFit.COVER, height=96)),
            ft.Container(padding=ft.Padding.symmetric(horizontal=4), content=ft.Column([
                texto(platillo.get("nombre") or "", 12.5, 600, max_lines=1,
                      overflow=ft.TextOverflow.ELLIPSIS),
                texto(generador_ia.formatear_precio(platillo.get("precio")), 11, 400, D.tenue,
                      mono=True),
            ], spacing=2, tight=True)),
        ], spacing=8, tight=True, horizontal_alignment=ft.CrossAxisAlignment.STRETCH)]
        if elegido:
            capas.append(ft.Container(
                top=6, right=6, width=22, height=22, border_radius=11, bgcolor=D.tinta,
                alignment=ft.Alignment.CENTER, content=icono("check", 12, D.sobre_tinta)))
        return ft.Container(
            expand=1, padding=ft.Padding.only(left=6, top=6, right=6, bottom=10),
            border_radius=14, border=ft.Border.all(1, D.linea), shadow=_anillo(elegido),
            # Con fondo: el anillo es una sombra y, sin él, se ve a través de la tarjeta.
            bgcolor=D.solido, content=ft.Stack(capas),
            on_click=lambda e, p=platillo: self._elegir_producto(p),
        )

    def _tarjeta_formato(self, clave):
        titulo, medidas, lleva, _, _, _ = FORMATOS[clave]
        tarjeta = ft.Container(
            expand=1, padding=14, border_radius=14, border=ft.Border.all(1, D.linea),
            bgcolor=D.solido,
            content=ft.Row([
                ft.Container(width=36, height=36, border_radius=11, bgcolor=D.chip,
                             alignment=ft.Alignment.CENTER, content=icono(clave, 18)),
                ft.Column([
                    ft.Row([texto(titulo, 13.5, 700), texto(medidas, 10.5, 400, D.tenue,
                                                            mono=True)],
                           spacing=8, vertical_alignment=ft.CrossAxisAlignment.END),
                    texto(lleva, 12, 500, D.suave, alto=1.4),
                ], spacing=3, tight=True, expand=True),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            on_click=lambda e, c=clave: self._elegir_formato(c),
        )
        return tarjeta

    def _pintar_van(self, actualizar=True):
        if self._datos is None:
            valor = ("No se pudieron leer los datos del negocio" if self._datos_error
                     else "Cargando…")
        else:
            valor = " · ".join(generador_ia.datos_que_van(self._formato or "post", self._datos)) \
                or "ningún dato del negocio"
        self.texto_van.spans = [
            ft.TextSpan("Irá en el anuncio: ",
                        ft.TextStyle(size=12, font_family="Jakarta500", color=D.tenue)),
            ft.TextSpan(valor, ft.TextStyle(size=12, font_family="Jakarta600", color=D.suave)),
        ]
        if actualizar:
            self._actualizar(self.texto_van)

    def _pintar_marcas(self):
        self.marca1.content = _marca(1, self._producto is not None)
        self.marca2.content = _marca(2, self._formato is not None)
        self.marca3.content = _marca(3, bool((self.campo_mensaje.value or "").strip()))

    def _pintar_generar(self):
        encendido = self._listo() and self._fase != "generando"
        color = D.sobre_tinta if encendido else D.tenue
        self.boton_generar.bgcolor = D.tinta if encendido else D.chip
        self.boton_generar.content = ft.Row([
            icono("ia", 16, color),
            texto("Generando..." if self._fase == "generando" else "Generar anuncio", 13, 600,
                  color),
        ], spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER)
        self.boton_generar.mouse_cursor = (ft.MouseCursor.CLICK if encendido
                                           else ft.MouseCursor.FORBIDDEN)

    def _pintar_resultado(self):
        # El marco toma el formato de lo pedido (generando/listo) o el elegido ahora (vacío).
        clave = (self._pedido or {}).get("formato") if self._fase in ("generando", "listo") \
            else self._formato
        ancho, alto = FORMATOS[clave or "post"][5]
        self.texto_formato_resultado.value = FORMATOS[clave][4] if clave else ""

        if self._fase == "generando":
            marco = ft.Container(
                width=ancho, height=alto, padding=24, border_radius=18, bgcolor=D.solido,
                border=ft.Border.all(1, D.linea), alignment=ft.Alignment.CENTER,
                content=ft.Column([
                    ft.ProgressRing(width=28, height=28, stroke_width=2.4, color=D.texto),
                    texto("Generando tu anuncio...", 14.5, 700),
                    texto(" + ".join(p.get("nombre", "") for p in
                                     [self._pedido["producto"]] + self._pedido["extras"])
                          + f" · {FORMATOS[clave][0]}", 12.5, 500, D.suave, alto=1.45,
                          text_align=ft.TextAlign.CENTER),
                    texto("Puede tardar un poco.", 12, 500, D.tenue, alto=1.45),
                ], spacing=12, tight=True, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            )
        elif self._fase == "listo":
            marco = ft.Container(
                width=ancho, height=alto, border_radius=18, bgcolor="#111111",
                clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                shadow=ft.BoxShadow(blur_radius=32, color="#38000000", offset=ft.Offset(0, 12)),
                content=ft.Image(src=self._ruta, fit=ft.BoxFit.COVER, width=ancho, height=alto),
            )
        elif self._fase == "error":
            marco = _marco_punteado(ancho, alto, ft.Container(
                padding=ft.Padding.symmetric(horizontal=14, vertical=11), border_radius=12,
                border=ft.Border.all(1, D.linea), bgcolor=D.chip,
                content=ft.Row([icono("alerta", 16, D.suave),
                                texto(self._error, 12.5, 500, expand=True)],
                               spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            ))
        else:
            marco = _marco_punteado(ancho, alto, ft.Column([
                ft.Container(width=44, height=44, border_radius=13, bgcolor=D.chip,
                             alignment=ft.Alignment.CENTER,
                             content=icono("biblio", 20, D.suave)),
                texto("Aquí aparecerá tu anuncio", 14.5, 700),
                texto("Llena los tres pasos y toca Generar.", 12.5, 500, D.suave, alto=1.45),
            ], spacing=10, tight=True, horizontal_alignment=ft.CrossAxisAlignment.CENTER))
        self.zona_marco.content = marco
        self.zona_acciones.visible = self._fase == "listo"

    def _combo(self):
        """El principal y sus extra, en orden (vacío si no hay producto)."""
        return [self._producto] + self._extras if self._producto is not None else []

    def _pintar_opciones(self):
        # Color: el cuadrito con el color elegido (o el rojo de siempre) y su código.
        self.muestra_color.bgcolor = self._color or ROJO_MUESTRA
        self.valor_color.value = self._color or "ROJO"
        apagar(self.boton_rojo, self._color is None)

        # Combinar: apagado hasta que haya principal; con combo, fotitos + nombres y la X.
        combo = self._combo()
        hay_combo = bool(self._extras) and self._producto is not None
        apagar(self.boton_combinar, self._producto is None)
        self.cuenta_combo.value = f"{len(combo)}/3"
        self.cuenta_combo.visible = hay_combo
        self.fotos_combo.controls = [
            ft.Container(left=i * 18, width=24, height=24, border_radius=7,
                         border=ft.Border.all(2, D.solido),
                         clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                         content=ft.Image(src=p.get("image_url") or "assets/sin-foto.png",
                                          fit=ft.BoxFit.COVER, width=24, height=24))
            for i, p in enumerate(combo)] if hay_combo else []
        self.fotos_combo.width = 24 + 18 * (len(combo) - 1) if hay_combo else 0
        self.fotos_combo.visible = hay_combo
        if hay_combo:
            resumen, color, peso = " + ".join(p.get("nombre", "") for p in combo), D.texto, 600
        elif self._producto is not None:
            resumen, color, peso = "Hasta 3 productos en un mismo anuncio.", D.tenue, 500
        else:
            resumen, color, peso = "Elige primero el producto.", D.tenue, 500
        self.resumen_combo.value = resumen
        self.zona_resumen.tooltip = resumen if hay_combo else None
        self.resumen_combo.color = color
        self.resumen_combo.font_family = f"Jakarta{peso}"
        self.boton_quitar_combo.visible = hay_combo
        self.nota_combo.visible = hay_combo
        self.campo_mensaje.hint_text = ("Ej. Taco + agua por $99 todo octubre." if hay_combo
                                        else "Ej. 2x1 en frappés todos los viernes de octubre.")

    def _pintar_estado(self, actualizar=True):
        """Todo lo que cambia al elegir/escribir/generar (sin la rejilla de productos)."""
        self._pintar_marcas()
        self._pintar_generar()
        self._pintar_resultado()
        self._pintar_opciones()
        self._pintar_van(actualizar=False)
        for clave, tarjeta in self.tarjetas_formato.items():
            tarjeta.shadow = _anillo(clave == self._formato)
        if actualizar:
            self._actualizar(self.marca1, self.marca2, self.marca3, self.boton_generar,
                             self.texto_formato_resultado, self.zona_marco, self.zona_acciones,
                             self.texto_van, *self.tarjetas_formato.values(),
                             self.boton_color, self.boton_rojo, self.boton_combinar,
                             self.fotos_combo, self.zona_resumen, self.boton_quitar_combo,
                             self.nota_combo, self.campo_mensaje)

    # ------------------------------------------------------------------
    # Acciones
    # ------------------------------------------------------------------
    def _on_buscar(self, e):
        self._busqueda = self.campo_buscar.value or ""
        self._pintar_productos()

    def _elegir_producto(self, platillo):
        self._producto = platillo
        # Si el nuevo principal era uno de los extra, deja de ser extra.
        self._extras = [p for p in self._extras if p.get("id") != platillo.get("id")]
        self._pintar_productos()
        self._pintar_estado()

    def _abrir_color(self, e=None):
        combo = bool(self._extras)
        producto = self._producto or {}
        DialogoColor(
            self.router, self._color,
            foto=producto.get("image_url") or "assets/sin-foto.png",
            precio="" if combo else generador_ia.formatear_precio(producto.get("precio")),
            al_elegir=self._on_color,
        ).abrir()

    def _on_color(self, color):
        self._color = color
        self._pintar_estado()

    def _volver_rojo(self, e=None):
        self._color = None
        self._pintar_estado()

    def _abrir_combinar(self, e=None):
        if self._producto is None:
            return
        DialogoCombinar(self.router, self._producto, self._platillos or [], self._extras,
                        al_listo=self._on_combo).abrir()

    def _on_combo(self, extras):
        self._extras = extras
        self._pintar_estado()

    def _quitar_combo(self, e=None):
        self._extras = []
        self._pintar_estado()

    def _elegir_formato(self, clave):
        self._formato = clave
        self._pintar_estado()

    def _on_escribir(self, e):
        self._pintar_estado()

    def _abrir_datos(self, e=None):
        DialogoNegocio(self.router, self._datos, on_guardado=self._on_datos_guardados).abrir()

    def _on_datos_guardados(self, datos):
        self._datos = datos
        self._datos_error = False
        self._pintar_van()

    def _on_generar(self, e):
        if not self._listo() or self._fase == "generando":
            return
        self._pedido = {
            "producto": self._producto,
            "formato": self._formato,
            "mensaje": (self.campo_mensaje.value or "").strip(),
            "color": self._color,
            "extras": list(self._extras),
        }
        self._fase = "generando"
        self._pintar_estado()
        self.page_ref.run_task(self._generar)

    async def _generar(self):
        pedido = self._pedido
        try:
            if self._datos is None:
                # No se pudieron leer al entrar: otro intento antes de gastar una imagen.
                self._datos = await asyncio.to_thread(DatosNegocioDAO.obtener)
                self._datos_error = False
            self._ruta = await asyncio.to_thread(
                generador_ia.generar, pedido["producto"], pedido["formato"],
                pedido["mensaje"], self._datos, pedido["color"], pedido["extras"])
            self._fase = "listo"
        except Exception as error:
            traceback.print_exc()
            self._error = _mensaje_de_error(error)
            self._fase = "error"
        self._pintar_estado()

    def _on_abrir_carpeta(self, e):
        # El Explorador con el anuncio ya marcado dentro de biblioteca/.
        try:
            if self._ruta and os.path.exists(self._ruta):
                subprocess.Popen(["explorer", "/select,",
                                  os.path.normpath(os.path.abspath(self._ruta))])
            else:
                os.startfile(os.path.abspath(generador_ia.RUTA_BIBLIOTECA))
        except Exception:
            traceback.print_exc()
