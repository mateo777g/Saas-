"""
views/components/dialogo_combinar.py
Ventana "Combinar productos" de Crear contenido (01/10, noche): hasta 2 productos más que salen
en el anuncio acompañando al principal (p. ej. Taco arabe + Agua de Jamaica). Máximo 3 en total.

Maqueta aprobada: https://claude.ai/artifact/AuWieY9WJjgHoNnVpb7hiw (Combinar / OscuroCombinar).
Arriba los tres lugares (PRINCIPAL, el elegido en la rejilla de la vista, y EXTRA 1/2, que se
quitan con su X; los libres con borde punteado), abajo el menú con buscador sin acentos (sin el
principal; con 3 ya elegidos, los demás se apagan) y la nota: el TITULAR es solo el principal
(decidido por el desarrollador: los extra solo acompañan, sin su nombre), mientras más
productos más chicos salen, y el precio del combo va en el mensaje (no sale el del menú).

"Listo"/"Usar N productos" devuelve la lista de extra; la X cierra sin cambiar nada.
"""
import unicodedata

import flet as ft
import flet.canvas as cv

from models.generador_ia import formatear_precio
from views.diseno import boton, boton_cuadro, etiqueta, icono, texto, ventana
from views.tema import D

MAX_EXTRA = 2
_ANCHO_TARJETA = 600
_INTERIOR = _ANCHO_TARJETA - 56
_ANCHO_LUGAR = (_INTERIOR - 20) / 3
_ALTO_LUGAR = 60
_COLUMNAS = 4
_ALTO_TARJETA = 136     # 6 + foto 72 + 7 + nombre + precio + 9, más el respiro del anillo
_ALTO_MAX_MENU = 262


def _sin_acentos(valor):
    descompuesto = unicodedata.normalize("NFD", valor or "")
    return "".join(c for c in descompuesto if unicodedata.category(c) != "Mn").lower()


def _foto(platillo):
    return platillo.get("image_url") or "assets/sin-foto.png"


class DialogoCombinar:
    """Uso: DialogoCombinar(router, principal, platillos, extras, al_listo).abrir()

    `principal`: el platillo elegido en la rejilla. `platillos`: todo el menú. `extras`: los
    extra que ya había. `al_listo(lista_de_extras)` al cerrar con el botón principal."""

    def __init__(self, router, principal, platillos, extras, al_listo):
        self.page = router.page
        self.principal = principal
        self.platillos = [p for p in platillos if p.get("id") != principal.get("id")]
        self.extras = [p for p in extras if p.get("id") != principal.get("id")][:MAX_EXTRA]
        self.al_listo = al_listo
        self._busqueda = ""

        self.texto_cuenta = etiqueta("")
        self.fila_lugares = ft.Row(spacing=10)
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
        self.rejilla = ft.Column(spacing=10, scroll=ft.ScrollMode.AUTO)
        self.zona_menu = ft.Container(content=self.rejilla)

        titular = ft.Text(spans=[
            ft.TextSpan("TITULAR", ft.TextStyle(size=10.5, font_family="Mono400", color=D.texto,
                                                letter_spacing=1.05)),
            ft.TextSpan(" · ", ft.TextStyle(size=12, font_family="Jakarta500", color=D.suave)),
            ft.TextSpan((principal.get("nombre") or "").upper(),
                        ft.TextStyle(size=12, font_family="Jakarta700", color=D.texto)),
        ], max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)

        self.boton_quitar = boton("Quitar los extra", "cerrar", self._on_vaciar)
        self.boton_usar = ft.Container(content=None)

        self.dialog = ventana(
            ft.Column(
                tight=True, spacing=0, horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                controls=[
                    ft.Row([
                        ft.Column([
                            etiqueta("COMBINAR PRODUCTOS"),
                            texto("Arma un combo", 24, 800, espaciado=-0.5),
                            texto("Elige hasta 2 productos más para que salgan junto a "
                                  f"{principal.get('nombre') or 'tu producto'}.", 12.5, 500,
                                  D.suave, alto=1.45),
                        ], spacing=6, tight=True, expand=True),
                        boton_cuadro("cerrar", lambda e: self._cerrar(), "Cerrar"),
                    ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.START),
                    ft.Container(height=22),
                    ft.Row([etiqueta("EN EL ANUNCIO"), ft.Container(expand=True),
                            self.texto_cuenta]),
                    ft.Container(height=10),
                    self.fila_lugares,
                    ft.Container(height=18),
                    ft.Row([etiqueta("TU MENÚ"), ft.Container(expand=True), buscador],
                           vertical_alignment=ft.CrossAxisAlignment.CENTER),
                    ft.Container(height=10),
                    self.zona_menu,
                    ft.Container(height=16),
                    ft.Container(
                        padding=ft.Padding.symmetric(horizontal=14, vertical=12),
                        border_radius=12, bgcolor=D.chip,
                        content=ft.Column([
                            titular,
                            texto("Los extra salen acompañando al principal, sin su nombre. "
                                  "Mientras más productos, más chicos salen para que quepan "
                                  "todos.", 12, 500, D.suave, alto=1.45),
                            texto("No sale el precio del menú: escribe el precio del combo en "
                                  "tu mensaje.", 12, 500, D.tenue, alto=1.45),
                        ], spacing=6, tight=True),
                    ),
                    ft.Container(height=24),
                    ft.Row([self.boton_quitar, ft.Container(expand=True), self.boton_usar],
                           spacing=10),
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

    # ------------------------------------------------------------------
    def _lugar_lleno(self, platillo, rol, quitar=None):
        return ft.Container(
            width=_ANCHO_LUGAR, height=_ALTO_LUGAR, padding=8, border_radius=14,
            border=ft.Border.all(1, D.linea),
            content=ft.Row([
                ft.Container(width=42, height=42, border_radius=9,
                             clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                             content=ft.Image(src=_foto(platillo), fit=ft.BoxFit.COVER,
                                              width=42, height=42)),
                ft.Column([
                    texto(platillo.get("nombre") or "", 12.5, 600, max_lines=1,
                          overflow=ft.TextOverflow.ELLIPSIS),
                    etiqueta(rol, 10),
                ], spacing=3, tight=True, expand=True),
                *([boton_cuadro("cerrar", quitar, "Quitar", lado=28)] if quitar else []),
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

    @staticmethod
    def _lugar_libre():
        # Borde punteado (flet no lo tiene: se dibuja en un Canvas), como el marco del resultado.
        return ft.Stack([
            cv.Canvas([cv.Rect(0.75, 0.75, _ANCHO_LUGAR - 1.5, _ALTO_LUGAR - 1.5, border_radius=14,
                               paint=ft.Paint(color=D.linea_fuerte, stroke_width=1.5,
                                              style=ft.PaintingStyle.STROKE,
                                              stroke_dash_pattern=[5, 4]))],
                      width=_ANCHO_LUGAR, height=_ALTO_LUGAR),
            ft.Container(width=_ANCHO_LUGAR, height=_ALTO_LUGAR, alignment=ft.Alignment.CENTER,
                         content=ft.Row([icono("mas", 14, D.tenue),
                                         texto("Lugar libre", 12, 500, D.tenue)],
                                        spacing=8, tight=True)),
        ], width=_ANCHO_LUGAR, height=_ALTO_LUGAR)

    def _tarjeta(self, platillo):
        elegido = any(p.get("id") == platillo.get("id") for p in self.extras)
        apagado = not elegido and len(self.extras) >= MAX_EXTRA
        capas = [ft.Column([
            ft.Container(height=72, border_radius=10, clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                         content=ft.Image(src=_foto(platillo), fit=ft.BoxFit.COVER, height=72)),
            ft.Container(padding=ft.Padding.symmetric(horizontal=4), content=ft.Column([
                texto(platillo.get("nombre") or "", 12, 600, max_lines=1,
                      overflow=ft.TextOverflow.ELLIPSIS),
                texto(formatear_precio(platillo.get("precio")), 10.5, 400, D.tenue, mono=True),
            ], spacing=2, tight=True)),
        ], spacing=7, tight=True, horizontal_alignment=ft.CrossAxisAlignment.STRETCH)]
        if elegido:
            capas.append(ft.Container(
                top=5, right=5, width=22, height=22, border_radius=11, bgcolor=D.tinta,
                alignment=ft.Alignment.CENTER, content=icono("check", 12, D.sobre_tinta)))
        return ft.Container(
            expand=1, padding=ft.Padding.only(left=6, top=6, right=6, bottom=9),
            border_radius=14, border=ft.Border.all(1, D.linea), bgcolor=D.solido,
            shadow=ft.BoxShadow(spread_radius=2, blur_radius=0, color=D.tinta) if elegido
            else None,
            opacity=0.4 if apagado else 1, disabled=apagado,
            content=ft.Stack(capas),
            on_click=lambda e, p=platillo: self._alternar(p),
        )

    def _pintar(self, actualizar=True):
        lugares = [self._lugar_lleno(self.principal, "PRINCIPAL")]
        for i, p in enumerate(self.extras, start=1):
            lugares.append(self._lugar_lleno(p, f"EXTRA {i}",
                                             quitar=lambda e, x=p: self._alternar(x)))
        while len(lugares) < MAX_EXTRA + 1:
            lugares.append(self._lugar_libre())
        self.fila_lugares.controls = lugares
        self.texto_cuenta.value = f"{1 + len(self.extras)} DE 3"

        q = _sin_acentos(self._busqueda.strip())
        lista = [p for p in self.platillos if not q or q in _sin_acentos(p.get("nombre", ""))]
        if not lista:
            self.rejilla.controls = [ft.Container(
                padding=ft.Padding.symmetric(vertical=18), alignment=ft.Alignment.CENTER,
                content=texto("No hay productos con ese nombre en tu menú." if q else
                              "No hay más productos en tu menú.", 12.5, 500, D.suave))]
            self.zona_menu.height = None
        else:
            tarjetas = [self._tarjeta(p) for p in lista]
            tarjetas += [ft.Container(expand=1) for _ in range(-len(tarjetas) % _COLUMNAS)]
            filas = [ft.Row(tarjetas[i:i + _COLUMNAS], spacing=10)
                     for i in range(0, len(tarjetas), _COLUMNAS)]
            # Respiro de 2 px para que no se corte el anillo de las elegidas.
            self.rejilla.controls = [ft.Container(padding=2, content=ft.Column(filas,
                                                                               spacing=10))]
            n = len(filas)
            self.zona_menu.height = min(_ALTO_MAX_MENU, n * _ALTO_TARJETA + (n - 1) * 10 + 4)

        self.boton_quitar.visible = bool(self.extras)
        self.boton_usar.content = boton(
            f"Usar {1 + len(self.extras)} productos" if self.extras else "Listo", "check",
            self._on_usar, principal=True)
        if actualizar:
            self._contenido.update()

    # ------------------------------------------------------------------
    def _alternar(self, platillo):
        if any(p.get("id") == platillo.get("id") for p in self.extras):
            self.extras = [p for p in self.extras if p.get("id") != platillo.get("id")]
        elif len(self.extras) < MAX_EXTRA:
            self.extras = self.extras + [platillo]
        else:
            return
        self._pintar()

    def _on_buscar(self, e):
        self._busqueda = self.campo_buscar.value or ""
        self._pintar()

    def _on_vaciar(self, e):
        self.extras = []
        self._pintar()

    def _on_usar(self, e):
        self._cerrar()
        self.al_listo(list(self.extras))
