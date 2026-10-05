"""
views/components/dialogo_color.py
Ventana "Color del anuncio" de Crear contenido (01/10, noche): elige el color que reemplaza al
rojo del flyer (fondo de arriba, precio, promoción y botón). El crema de abajo NO cambia nunca.

Maqueta aprobada: https://claude.ai/artifact/AuWieY9WJjgHoNnVpb7hiw (Color / OscuroColor). Como
el selector de Canva pero solo color sólido (sin opacidad ni gotero): un cuadro de saturación y
brillo, una barra de tono y el código del color. Flet no trae selector de color: el cuadro son
tres Container (el tono puro, un degradado blanco a lo ancho y uno negro de abajo arriba) dentro
de un GestureDetector que lee dónde se toca o arrastra.

Al lado, un anuncio en miniatura con el color puesto (y el crema abajo) y, si el color es claro
(generador_ia.es_claro, el mismo umbral que el prompt), el aviso de que las letras encima saldrán
oscuras. "Volver al rojo" devuelve None (el prompt de siempre); "Usar este color", el hex.
No se recuerda el último color (decidido por el desarrollador): la vista empieza siempre en rojo.
"""
import colorsys
import re

import flet as ft

from models.generador_ia import es_claro
from views.diseno import boton, boton_cuadro, etiqueta, icono, texto, ventana
from views.tema import D

# El rojo de siempre, SOLO para pintarlo en el panel (cuadrito, punto de partida del selector):
# si no se elige color, al prompt no se le manda ningún hex ("Solid vivid red background").
ROJO_MUESTRA = "#D7261E"
CREMA = "#F5EBDD"   # el crema de abajo, de muestra en la miniatura (en el prompt va por nombre)

_ANCHO_TARJETA = 440
_ANCHO_CUADRO = _ANCHO_TARJETA - 56     # el interior de la ventana (padding 28 por lado)
_ALTO_CUADRO = 196
_ALTO_TONO = 14
_HEX_VALIDO = re.compile(r"^#[0-9A-F]{6}$")


def hsv_a_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h / 360, s, v)
    return "#{:02X}{:02X}{:02X}".format(round(r * 255), round(g * 255), round(b * 255))


def hex_a_hsv(valor):
    numero = int(valor.lstrip("#"), 16)
    h, s, v = colorsys.rgb_to_hsv(((numero >> 16) & 255) / 255, ((numero >> 8) & 255) / 255,
                                  (numero & 255) / 255)
    return h * 360, s, v


def _limitar(x):
    return max(0.0, min(1.0, x))


def _mango(lado, borde=2.5):
    # El circulito blanco que marca dónde está el color (en el cuadro y en la barra de tono).
    return ft.Container(
        width=lado, height=lado, border_radius=lado / 2, border=ft.Border.all(borde, "#ffffff"),
        shadow=[ft.BoxShadow(spread_radius=1, blur_radius=0, color="#59000000"),
                ft.BoxShadow(blur_radius=6, color="#4D000000", offset=ft.Offset(0, 2))],
    )


class DialogoColor:
    """Uso: DialogoColor(router, color_actual, foto, precio, al_elegir).abrir()

    `color_actual`: el hex elegido o None (rojo). `foto`/`precio`: los del producto principal,
    para la miniatura (precio "" con combo o sin producto). `al_elegir(hex | None)` se llama al
    cerrar con "Usar este color" (hex) o "Volver al rojo" (None); la X no cambia nada."""

    def __init__(self, router, color_actual, foto, precio, al_elegir):
        self.page = router.page
        self.al_elegir = al_elegir
        self.h, self.s, self.v = hex_a_hsv(color_actual or ROJO_MUESTRA)

        # Cuadro de saturación (a lo ancho) y brillo (de arriba abajo).
        self.cuadro_tono = ft.Container(width=_ANCHO_CUADRO, height=_ALTO_CUADRO, border_radius=14)
        self.mango_sv = _mango(18)
        cuadro = ft.GestureDetector(
            mouse_cursor=ft.MouseCursor.PRECISE, drag_interval=16,
            on_tap_down=self._tocar_sv, on_pan_start=self._tocar_sv, on_pan_update=self._tocar_sv,
            content=ft.Stack([
                self.cuadro_tono,
                ft.Container(width=_ANCHO_CUADRO, height=_ALTO_CUADRO, border_radius=14,
                             gradient=ft.LinearGradient(begin=ft.Alignment.CENTER_LEFT,
                                                        end=ft.Alignment.CENTER_RIGHT,
                                                        colors=["#FFFFFFFF", "#00FFFFFF"])),
                ft.Container(width=_ANCHO_CUADRO, height=_ALTO_CUADRO, border_radius=14,
                             gradient=ft.LinearGradient(begin=ft.Alignment.BOTTOM_CENTER,
                                                        end=ft.Alignment.TOP_CENTER,
                                                        colors=["#FF000000", "#00000000"])),
                self.mango_sv,
            ], width=_ANCHO_CUADRO, height=_ALTO_CUADRO, clip_behavior=ft.ClipBehavior.NONE),
        )

        # Barra de tono: 20 de alto para que quepa el mango (la barra en sí mide 14).
        self.mango_tono = _mango(20)
        barra_tono = ft.GestureDetector(
            mouse_cursor=ft.MouseCursor.CLICK, drag_interval=16,
            on_tap_down=self._tocar_tono, on_pan_start=self._tocar_tono,
            on_pan_update=self._tocar_tono,
            content=ft.Stack([
                ft.Container(top=3, left=0, width=_ANCHO_CUADRO, height=_ALTO_TONO,
                             border_radius=_ALTO_TONO / 2,
                             gradient=ft.LinearGradient(
                                 begin=ft.Alignment.CENTER_LEFT, end=ft.Alignment.CENTER_RIGHT,
                                 colors=["#FF0000", "#FFFF00", "#00FF00", "#00FFFF", "#0000FF",
                                         "#FF00FF", "#FF0000"])),
                self.mango_tono,
            ], width=_ANCHO_CUADRO, height=20, clip_behavior=ft.ClipBehavior.NONE),
        )

        # Anuncio en miniatura: arriba el color, abajo el crema de siempre.
        self.mini_arriba = ft.Container(left=0, top=0, right=0, height=57)
        self.mini_raya1 = ft.Container(left=10, top=9, width=40, height=4, border_radius=2,
                                       opacity=0.85)
        self.mini_raya2 = ft.Container(left=10, top=17, width=62, height=7, border_radius=2)
        self.mini_precio = texto(precio, 13, 800, alto=1.0) if precio else None
        self.mini_pastilla = ft.Container(left=10, bottom=9, width=44, height=9, border_radius=5)
        miniatura = ft.Container(
            width=92, height=115, border_radius=10, bgcolor=CREMA, border=ft.Border.all(1, D.linea),
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Stack([
                self.mini_arriba, self.mini_raya1, self.mini_raya2,
                ft.Container(left=24, top=34, width=44, height=44, border_radius=22,
                             clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                             shadow=ft.BoxShadow(blur_radius=8, color="#40000000",
                                                 offset=ft.Offset(0, 3)),
                             content=ft.Image(src=foto, fit=ft.BoxFit.COVER, width=44, height=44)),
                *([ft.Container(left=10, top=80, content=self.mini_precio)]
                  if self.mini_precio else []),
                self.mini_pastilla,
            ]),
        )

        # El código del color: se puede escribir (con o sin "#").
        self.muestra_campo = ft.Container(width=18, height=18, border_radius=5)
        self.campo_hex = ft.TextField(
            border=ft.InputBorder.NONE, filled=False, dense=True,
            text_size=13.5, text_style=ft.TextStyle(font_family="Mono400", color=D.texto),
            content_padding=ft.Padding.symmetric(vertical=8), cursor_color=D.texto,
            capitalization=ft.TextCapitalization.CHARACTERS, expand=True,
            on_change=self._on_hex,
        )
        self.punto_color = ft.Container(width=8, height=8, border_radius=4)
        caja_hex = ft.Container(
            height=44, border_radius=12, border=ft.Border.all(1, D.linea),
            padding=ft.Padding.symmetric(horizontal=14),
            content=ft.Row([self.muestra_campo, self.campo_hex], spacing=10,
                           vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        def renglon(punto, valor):
            return ft.Row([punto, texto(valor, 12, 500, D.suave, alto=1.4)], spacing=8,
                          vertical_alignment=ft.CrossAxisAlignment.CENTER)

        self.nota_claro = ft.Container(
            padding=ft.Padding.symmetric(horizontal=14, vertical=11), border_radius=12,
            bgcolor=D.chip,
            content=ft.Row([icono("sol", 16, D.suave),
                            texto("Es un color claro: las letras que van encima saldrán oscuras "
                                  "para que se lean.", 12, 500, D.suave, alto=1.45,
                                  expand=True)],
                           spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        self.dialog = ventana(
            ft.Column(
                tight=True, spacing=0, horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                controls=[
                    ft.Row([
                        ft.Column([
                            etiqueta("COLOR DEL ANUNCIO"),
                            texto("Elige un color", 24, 800, espaciado=-0.5),
                            texto("Va en el fondo de arriba, el precio, la promoción y el botón. "
                                  "La parte de abajo siempre queda crema.", 12.5, 500, D.suave,
                                  alto=1.45),
                        ], spacing=6, tight=True, expand=True),
                        boton_cuadro("cerrar", lambda e: self._cerrar(), "Cerrar"),
                    ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.START),
                    ft.Container(height=22),
                    cuadro,
                    ft.Container(height=11),
                    barra_tono,
                    ft.Container(height=19),
                    ft.Row([
                        miniatura,
                        ft.Column([
                            etiqueta("CÓDIGO DEL COLOR"),
                            ft.Container(height=0),
                            caja_hex,
                            ft.Container(height=2),
                            renglon(self.punto_color, "Arriba, precio, promoción y botón"),
                            renglon(ft.Container(width=8, height=8, border_radius=4,
                                                 bgcolor=CREMA,
                                                 border=ft.Border.all(1, "#2E000000")),
                                    "Abajo: crema, siempre"),
                        ], spacing=6, tight=True, expand=True),
                    ], spacing=16, vertical_alignment=ft.CrossAxisAlignment.START),
                    ft.Container(height=14),
                    self.nota_claro,
                    ft.Container(height=24),
                    ft.Row([
                        boton("Volver al rojo", "volver", self._on_rojo),
                        ft.Container(expand=True),
                        boton("Usar este color", "check", self._on_usar, principal=True),
                    ], spacing=10),
                ],
            ),
            _ANCHO_TARJETA,
        )
        self._contenido = self.dialog.content
        self._pintar(actualizar=False)

    # ------------------------------------------------------------------
    def abrir(self):
        self.page.show_dialog(self.dialog)

    def _cerrar(self):
        self.page.pop_dialog()

    def _hex(self):
        return hsv_a_hex(self.h, self.s, self.v)

    def _pintar(self, actualizar=True, desde_campo=False):
        color = self._hex()
        claro = es_claro(color)
        letra = "#1A1410" if claro else "#FFFFFF"
        self.cuadro_tono.bgcolor = hsv_a_hex(self.h, 1, 1)
        self.mango_sv.left = self.s * _ANCHO_CUADRO - 9
        self.mango_sv.top = (1 - self.v) * _ALTO_CUADRO - 9
        self.mango_sv.bgcolor = color
        self.mango_tono.left = self.h / 360 * _ANCHO_CUADRO - 10
        self.mango_tono.bgcolor = hsv_a_hex(self.h, 1, 1)
        self.muestra_campo.bgcolor = color
        self.punto_color.bgcolor = color
        if not desde_campo:
            self.campo_hex.value = color
        self.mini_arriba.bgcolor = color
        self.mini_raya1.bgcolor = letra
        self.mini_raya2.bgcolor = letra
        self.mini_pastilla.bgcolor = color
        if self.mini_precio is not None:
            self.mini_precio.color = color
        self.nota_claro.visible = claro
        if actualizar:
            self._contenido.update()

    def _tocar_sv(self, e):
        self.s = _limitar(e.local_position.x / _ANCHO_CUADRO)
        self.v = 1 - _limitar(e.local_position.y / _ALTO_CUADRO)
        self._pintar()

    def _tocar_tono(self, e):
        self.h = min(359.9, _limitar(e.local_position.x / _ANCHO_CUADRO) * 360)
        self._pintar()

    def _on_hex(self, e):
        valor = (self.campo_hex.value or "").strip().upper()
        if valor and not valor.startswith("#"):
            valor = "#" + valor
        if _HEX_VALIDO.match(valor):
            self.h, self.s, self.v = hex_a_hsv(valor)
            self._pintar(desde_campo=True)

    def _on_rojo(self, e):
        self._cerrar()
        self.al_elegir(None)

    def _on_usar(self, e):
        color = self._hex()
        self._cerrar()
        # Si se quedó en el rojo de muestra, es el de siempre: el prompt probado, sin hex.
        self.al_elegir(None if color == ROJO_MUESTRA else color)
