"""
views/menu_view.py
Mi menú con el diseño manchas + vidrio (29/09), SIN el fondo de manchas (es exclusivo del Agente
IA): la vista pinta su propio suelo (D.suelo) y MainController lo sube detrás de la barra. Las
reglas están en planes/plan panel.txt ("DISEÑO MANCHAS + VIDRIO"); la maqueta aprobada, en
https://claude.ai/artifact/34WRAVdMDwSU8NpLctykoe.

- Barra de arriba (vidrio): "Mi menú", chip con cuántos se ven en el menú público, el botón
  blanco "Ocultar varios" (en ese modo, "Cancelar") y el negro "Nuevo platillo".
- Tarjeta de vidrio: buscador, selector de categoría y la tabla en sólido (foto, nombre,
  descripción, categoría, precio, visibilidad, ojito y lápiz).
- "Ocultar varios": cada fila muestra una cajita; se tocan las que se acabaron y la barra de
  abajo las oculta en una sola consulta (PlatilloDAO.ocultar_varios). Ocultar nunca borra. Al
  modo se llega también desde el atajo "Marcar un platillo como agotado" de Inicio.

El buscador y las categorías filtran en memoria: no se vuelve a consultar Supabase por tecla.
"""
import asyncio
import traceback

import flet as ft
import httpx

from models.platillo_dao import PlatilloDAO
from views.components.dialogo_platillo import DialogoPlatillo
from views.diseno import (ALTO_BARRA_SUPERIOR, MARGEN, apagar, boton, boton_cuadro, etiqueta,
                          icono, punto, selector, texto, vidrio)
from views.piezas import aviso
from views.tema import D, VERDE

CATEGORIAS = ["Todos", "Platillos", "Bebidas", "Postres"]

# Anchos relativos de las columnas (la maqueta: 2.2fr 2.8fr 1fr 0.8fr 1fr) y los fijos.
COLUMNAS = [("PLATILLO", 22), ("DESCRIPCIÓN", 28), ("CATEGORÍA", 10), ("PRECIO", 8),
            ("VISIBILIDAD", 10)]
ANCHO_ACCIONES = 80
ANCHO_CAJITA = 20
ESPACIO_COLUMNAS = 16


def _formatear_precio(valor) -> str:
    """precio llega como numeric(10,2) de Supabase (float en Python): sin decimales si es
    entero ($300), con centavos si los tiene."""
    try:
        numero = float(valor)
    except (TypeError, ValueError):
        return "$0"
    if numero.is_integer():
        return f"${int(numero):,}"
    return f"${numero:,.2f}"


def _coincide(platillo: dict, query: str) -> bool:
    """El buscador: nombre, descripción y categoría, sin distinguir mayúsculas."""
    campos = (
        platillo.get("nombre") or "",
        platillo.get("descripcion") or "",
        platillo.get("categoria") or "",
    )
    return any(query in campo.lower() for campo in campos)


def _plural(cantidad, singular, plural):
    return f"{cantidad} {singular if cantidad == 1 else plural}"


def _con_alfa(color, alfa):
    # "#ffffff" + "A3" -> "#A3ffffff": el sobre_tinta a medias para la barra de abajo.
    return f"#{alfa}{color.lstrip('#')}"


def _cajita(elegido, oculto):
    """La cajita de "Ocultar varios": vacía, palomeada (tinta) o, si ya está oculto, sin borde
    firme (no se puede elegir)."""
    if elegido:
        return ft.Container(width=ANCHO_CAJITA, height=ANCHO_CAJITA, border_radius=6,
                            bgcolor=D.tinta, alignment=ft.Alignment.CENTER,
                            content=icono("check", 13, D.sobre_tinta))
    return ft.Container(width=ANCHO_CAJITA, height=ANCHO_CAJITA, border_radius=6,
                        bgcolor=None if oculto else D.solido,
                        border=ft.Border.all(1.5, D.linea if oculto else D.tenue))


def _estado_visibilidad(visible, texto_oculto="Oculto"):
    # Como "Mesas ahora" de Inicio: punto lleno = se ve; punto hueco = oculto. Sin rojo ni verde.
    if visible:
        return ft.Row([punto(D.tinta, 8), texto("Visible", 12.5, 600)], spacing=8, tight=True)
    return ft.Row([ft.Container(width=8, height=8, border_radius=4,
                                border=ft.Border.all(1.5, D.tenue)),
                   texto(texto_oculto, 12.5, 500, D.tenue)], spacing=8, tight=True)


class MenuView(ft.Container):
    def __init__(self, router, abrir_dialogo_nuevo: bool = False, ocultar_varios: bool = False):
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        # El suelo liso del tema: MainController lo sube a toda la ventana, detrás de la barra.
        self.bgcolor = D.suelo

        # Lista maestra tal cual vino de Supabase y la que se ve (tras buscador y categoría).
        self._platillos: list[dict] = []
        self._mostrados: list[dict] = []
        self._cargado = False
        self._categoria = "Todos"
        self._seleccionando = ocultar_varios
        self._elegidos: set = set()
        self._ocultando = False
        # Filas pintadas en modo "Ocultar varios", por id: (fila, hueco de la cajita).
        self._filas_eleccion: dict = {}

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        self.texto_chip = texto("Cargando tu menú…", 12, 500, D.suave)
        self.hueco_boton_modo = ft.Container()
        barra_superior = vidrio(
            radio=18, sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=12),
            contenido=ft.Row([
                texto("Mi menú", 15, 700),
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE), self.texto_chip], spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
                ft.Container(expand=True),
                self.hueco_boton_modo,
                boton("Nuevo platillo", "mas", self._on_agregar_click, principal=True),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # Herramientas: buscador, categoría y conteo
        # --------------------------------------------------------------
        self.campo_busqueda = ft.TextField(
            hint_text="Busca por nombre, categoría o ingrediente...",
            border=ft.InputBorder.NONE, dense=True, expand=True,
            content_padding=ft.Padding.symmetric(vertical=10),
            text_size=13, text_style=ft.TextStyle(font_family="Jakarta500", color=D.texto),
            hint_style=ft.TextStyle(font_family="Jakarta500", color=D.tenue, size=13),
            cursor_color=D.texto, selection_color=D.chip,
            on_change=lambda e: self._pintar_tabla(),
        )
        buscador = ft.Container(
            width=380, height=40, border_radius=12, border=ft.Border.all(1, D.linea),
            bgcolor=D.solido, padding=ft.Padding.symmetric(horizontal=14),
            content=ft.Row([icono("buscar", 16, D.tenue), self.campo_busqueda], spacing=10,
                           vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )
        self.hueco_selector = ft.Container(
            content=selector(CATEGORIAS, self._categoria, self._elegir_categoria))
        self.texto_conteo = etiqueta("")

        # --------------------------------------------------------------
        # Tabla (sólido)
        # --------------------------------------------------------------
        self.cabecera = ft.Container(
            height=40, padding=ft.Padding.symmetric(horizontal=16),
            border=ft.Border(bottom=ft.BorderSide(1, D.linea)),
        )
        self.cuerpo = ft.Column(spacing=0, expand=True, scroll=ft.ScrollMode.AUTO,
                                controls=[self._nota("Cargando tu menú…")])
        tabla = ft.Container(
            expand=True, border_radius=18, border=ft.Border.all(1, D.linea), bgcolor=D.solido,
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Column([self.cabecera, self.cuerpo], spacing=0),
        )

        # --------------------------------------------------------------
        # Barra de "Ocultar varios" (tinta, abajo de la tabla)
        # --------------------------------------------------------------
        self.texto_barra = texto("", 14, 700, D.sobre_tinta)
        self.texto_todos = texto("Elegir todos", 13, 600, D.sobre_tinta)
        self.boton_todos = ft.Container(
            height=40, padding=ft.Padding.symmetric(horizontal=14), border_radius=12,
            border=ft.Border.all(1, _con_alfa(D.sobre_tinta, "3D")),
            alignment=ft.Alignment.CENTER, content=self.texto_todos,
            on_click=self._elegir_todos,
        )
        self.texto_ocultar = texto("Ocultar platillo", 13, 600, D.tinta)
        self.boton_ocultar = ft.Container(
            height=40, padding=ft.Padding.symmetric(horizontal=16), border_radius=12,
            bgcolor=D.sobre_tinta, on_click=self._on_ocultar_click,
            content=ft.Row([icono("oculto", 16, D.tinta), self.texto_ocultar], spacing=8,
                           tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )
        self.barra_eleccion = ft.Container(
            height=64, border_radius=18, bgcolor=D.tinta,
            padding=ft.Padding.only(left=20, right=12),
            content=ft.Row([
                ft.Column([
                    self.texto_barra,
                    texto("Dejan de salir en tu menú público, no se borran. Los vuelves a "
                          "mostrar con el ojito.", 12, 500, _con_alfa(D.sobre_tinta, "A3")),
                ], spacing=2, tight=True, expand=True,
                    alignment=ft.MainAxisAlignment.CENTER),
                self.boton_todos,
                self.boton_ocultar,
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        tarjeta = vidrio(
            radio=26, padding=20,
            top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN, bottom=MARGEN,
            contenido=ft.Column([
                ft.Row([buscador, self.hueco_selector, ft.Container(expand=True),
                        self.texto_conteo],
                       spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER),
                tabla,
                self.barra_eleccion,
            ], spacing=14),
        )

        self._pintar_modo()
        self.cabecera.content = self._celdas([etiqueta(nombre) for nombre, _ in COLUMNAS])
        self._pintar_barra_eleccion()
        self.content = ft.Stack([tarjeta, barra_superior], expand=True)

        # Se agenda aquí pero no corre hasta que cambiar_vista() termine de montar la vista.
        self.page_ref.run_task(self._cargar_platillos)
        # Desde el atajo "Agregar un producto nuevo" de Inicio: el diálogo de alta, ya montada.
        if abrir_dialogo_nuevo:
            self.page_ref.run_task(self._abrir_dialogo_nuevo_al_montar)

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------
    def _actualizar(self, *controles):
        try:
            for c in controles:
                c.update()
        except RuntimeError:
            pass    # se salió de Mi menú antes de que llegaran los datos

    @staticmethod
    def _nota(titulo, detalle=None):
        # Los estados de la tabla (cargando, vacía, sin resultados, sin conexión): una nota
        # centrada dentro del sólido.
        lineas = [texto(titulo, 14.5, 700, text_align=ft.TextAlign.CENTER)]
        if detalle:
            lineas.append(texto(detalle, 12.5, 500, D.suave, text_align=ft.TextAlign.CENTER))
        return ft.Container(
            padding=ft.Padding.symmetric(vertical=48, horizontal=16),
            alignment=ft.Alignment.CENTER,
            content=ft.Column(lineas, spacing=6, tight=True,
                              horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        )

    def _celdas(self, contenidos, cajita=None, acciones=None):
        """Una fila de la tabla con los anchos de las columnas: [cajita] + las 5 columnas +
        [acciones]. La usan la cabecera y las filas, así siempre quedan alineadas."""
        controles = []
        if self._seleccionando:
            controles.append(ft.Container(width=ANCHO_CAJITA, content=cajita))
        for (_, peso), contenido in zip(COLUMNAS, contenidos):
            controles.append(ft.Container(expand=peso, content=contenido,
                                          alignment=ft.Alignment.CENTER_LEFT))
        if not self._seleccionando:
            controles.append(ft.Container(width=ANCHO_ACCIONES, content=acciones,
                                          alignment=ft.Alignment.CENTER_RIGHT))
        return ft.Row(controles, spacing=ESPACIO_COLUMNAS,
                      vertical_alignment=ft.CrossAxisAlignment.CENTER)

    # ------------------------------------------------------------------
    # Carga
    # ------------------------------------------------------------------
    async def _cargar_platillos(self):
        try:
            # supabase-py es síncrono: a un hilo para no congelar la ventana.
            self._platillos = await asyncio.to_thread(PlatilloDAO.obtener_todos)
            self._cargado = True
        except httpx.RequestError:
            traceback.print_exc()
            self._platillos = []
            self._cargado = False
            self._poner_error("Sin conexión.", "No hay conexión con el servidor. Revisa tu internet.")
            return
        except Exception:
            traceback.print_exc()
            self._platillos = []
            self._cargado = False
            self._poner_error("No se pudo cargar tu menú.", "Intenta de nuevo en un momento.")
            return
        self._pintar_tabla()

    def _poner_error(self, titulo, detalle):
        self.texto_chip.value = "Sin conexión"
        self.texto_conteo.value = ""
        self.cuerpo.controls = [self._nota(titulo, detalle)]
        self._actualizar(self.texto_chip, self.texto_conteo, self.cuerpo)

    # ------------------------------------------------------------------
    # Pintado
    # ------------------------------------------------------------------
    def _elegir_categoria(self, categoria):
        if categoria == self._categoria:
            return
        self._categoria = categoria
        self.hueco_selector.content = selector(CATEGORIAS, categoria, self._elegir_categoria)
        self._actualizar(self.hueco_selector)
        self._pintar_tabla()

    def _filtrar(self):
        query = (self.campo_busqueda.value or "").strip().lower()
        return [p for p in self._platillos
                if (self._categoria == "Todos" or p.get("categoria") == self._categoria)
                and (not query or _coincide(p, query))]

    def _pintar_tabla(self):
        """Repinta cabecera, filas, chip y conteo desde lo que hay en memoria."""
        self.cabecera.content = self._celdas(
            [etiqueta(nombre) for nombre, _ in COLUMNAS])
        if not self._cargado:
            self._pintar_barra_eleccion()
            self._actualizar(self.cabecera, self.barra_eleccion)
            return

        total = len(self._platillos)
        visibles = sum(1 for p in self._platillos if p.get("visible", True))
        self.texto_chip.value = f"{visibles} de {total} a la vista en tu menú"

        self._mostrados = self._filtrar()
        self.texto_conteo.value = _plural(len(self._mostrados), "PLATILLO", "PLATILLOS")
        self._filas_eleccion = {}
        query = (self.campo_busqueda.value or "").strip()
        if not self._platillos:
            self.cuerpo.controls = [self._nota("Todavía no hay platillos en el menú.",
                                               "Agrega el primero con Nuevo platillo.")]
        elif not self._mostrados:
            self.cuerpo.controls = [self._nota(
                f'No encontramos platillos para "{query}".' if query
                else "No hay platillos en esta categoría.",
                "Prueba con otro nombre, categoría o palabra clave.")]
        else:
            self.cuerpo.controls = [self._crear_fila(p) for p in self._mostrados]
        self._pintar_barra_eleccion()
        self._actualizar(self.cabecera, self.cuerpo, self.texto_chip, self.texto_conteo,
                         self.barra_eleccion)

    def _crear_fila(self, platillo: dict):
        visible = bool(platillo.get("visible", True))
        foto = ft.Container(
            width=44, height=44, border_radius=11, bgcolor="#000000",
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS, opacity=1 if visible else 0.4,
            content=ft.Image(
                # Sin foto: la imagen negra de siempre (assets/sin-foto.png).
                src=platillo.get("image_url") or "assets/sin-foto.png",
                width=44, height=44, fit=ft.BoxFit.COVER, cache_width=132,
                error_content=ft.Image(src="assets/sin-foto.png", width=44, height=44,
                                       fit=ft.BoxFit.COVER),
            ),
        )
        contenidos = [
            ft.Row([foto, texto(platillo.get("nombre") or "", 13.5, 700, expand=True,
                                max_lines=2, overflow=ft.TextOverflow.ELLIPSIS)],
                   spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            texto(platillo.get("descripcion") or "", 12.5, 500, D.suave, alto=1.45,
                  max_lines=2, overflow=ft.TextOverflow.ELLIPSIS),
            ft.Container(padding=ft.Padding.symmetric(horizontal=10, vertical=4),
                         border_radius=8, bgcolor=D.chip,
                         content=texto(platillo.get("categoria") or "", 12, 600, D.suave)),
            texto(_formatear_precio(platillo.get("precio")), 13, 500, mono=True),
            _estado_visibilidad(visible, "Oculto" if not self._seleccionando else "Ya oculto"),
        ]
        raya = ft.Border(bottom=ft.BorderSide(1, D.linea))
        relleno = ft.Padding.symmetric(horizontal=16, vertical=10)

        if not self._seleccionando:
            acciones = ft.Row([
                boton_cuadro("oculto" if visible else "ojo",
                             lambda e, p=platillo: self._on_toggle_visibilidad(p),
                             "Ocultar del menú público" if visible
                             else "Mostrar en el menú público"),
                boton_cuadro("crear", lambda e, p=platillo: self._on_editar_click(p),
                             "Editar platillo"),
            ], spacing=8, tight=True)
            return ft.Container(padding=relleno, border=raya,
                                content=self._celdas(contenidos, acciones=acciones))

        # Modo "Ocultar varios": toda la fila es el botón. Las ya ocultas, apagadas.
        elegido = platillo.get("id") in self._elegidos
        hueco = ft.Container(content=_cajita(elegido, not visible))
        fila = ft.Container(
            padding=relleno, border=raya, bgcolor=D.chip if elegido else None,
            opacity=1 if visible else 0.5,
            on_click=(lambda e, p=platillo: self._alternar_eleccion(p)) if visible else None,
            content=self._celdas(contenidos, cajita=hueco),
        )
        self._filas_eleccion[platillo.get("id")] = (fila, hueco)
        return fila

    # ------------------------------------------------------------------
    # Modo "Ocultar varios"
    # ------------------------------------------------------------------
    def _pintar_modo(self):
        if self._seleccionando:
            self.hueco_boton_modo.content = boton("Cancelar", "cerrar", self._salir_de_eleccion)
        else:
            self.hueco_boton_modo.content = boton("Ocultar varios", "oculto",
                                                  self._entrar_a_eleccion)
        self.barra_eleccion.visible = self._seleccionando

    def _entrar_a_eleccion(self, _=None):
        self._seleccionando = True
        self._elegidos = set()
        self._pintar_modo()
        self._pintar_tabla()
        self._actualizar(self.hueco_boton_modo)

    def _salir_de_eleccion(self, _=None):
        if self._ocultando:
            return
        self._seleccionando = False
        self._elegidos = set()
        self._pintar_modo()
        self._pintar_tabla()
        self._actualizar(self.hueco_boton_modo)

    def _elegibles(self):
        # Los que se pueden elegir ahora: los que se ven en la tabla y no están ocultos ya.
        return [p for p in self._mostrados if p.get("visible", True)]

    def _pintar_barra_eleccion(self):
        n = len(self._elegidos)
        self.texto_barra.value = ("Toca los platillos que se acabaron" if n == 0
                                  else _plural(n, "platillo elegido", "platillos elegidos"))
        if self._ocultando:
            self.texto_ocultar.value = "Ocultando…"
        else:
            self.texto_ocultar.value = ("Ocultar platillo" if n <= 1
                                        else f"Ocultar {n} platillos")
        elegibles = self._elegibles()
        todos = bool(elegibles) and all(p.get("id") in self._elegidos for p in elegibles)
        self.texto_todos.value = "Quitar todos" if todos else "Elegir todos"
        apagar(self.boton_ocultar, n == 0 or self._ocultando)
        apagar(self.boton_todos, not elegibles or self._ocultando)

    def _pintar_eleccion_de(self, id_platillo):
        fila, hueco = self._filas_eleccion.get(id_platillo, (None, None))
        if fila is None:
            return
        elegido = id_platillo in self._elegidos
        fila.bgcolor = D.chip if elegido else None
        hueco.content = _cajita(elegido, False)
        self._actualizar(fila)

    def _alternar_eleccion(self, platillo):
        if self._ocultando:
            return
        id_platillo = platillo.get("id")
        if id_platillo in self._elegidos:
            self._elegidos.discard(id_platillo)
        else:
            self._elegidos.add(id_platillo)
        self._pintar_eleccion_de(id_platillo)
        self._pintar_barra_eleccion()
        self._actualizar(self.barra_eleccion)

    def _elegir_todos(self, _):
        elegibles = self._elegibles()
        ids = {p.get("id") for p in elegibles}
        if ids and ids <= self._elegidos:
            self._elegidos -= ids
        else:
            self._elegidos |= ids
        for id_platillo in ids:
            self._pintar_eleccion_de(id_platillo)
        self._pintar_barra_eleccion()
        self._actualizar(self.barra_eleccion)

    def _on_ocultar_click(self, _):
        if self._elegidos and not self._ocultando:
            self.page_ref.run_task(self._ocultar_elegidos)

    async def _ocultar_elegidos(self):
        ids = sorted(self._elegidos)
        self._ocultando = True
        apagar(self.hueco_boton_modo, True)
        self._pintar_barra_eleccion()
        self._actualizar(self.barra_eleccion, self.hueco_boton_modo)
        try:
            await asyncio.to_thread(PlatilloDAO.ocultar_varios, ids)
        except Exception as e:
            traceback.print_exc()
            self._ocultando = False
            apagar(self.hueco_boton_modo, False)
            self._pintar_barra_eleccion()
            self._actualizar(self.barra_eleccion, self.hueco_boton_modo)
            if isinstance(e, httpx.RequestError):
                aviso(self.page_ref, "No hay conexión con el servidor. Revisa tu internet.")
                return
            # Pudo quedar a medias (RLS): se recarga para mostrar lo que de verdad quedó.
            aviso(self.page_ref, "No se pudieron ocultar todos. Revisa la tabla.")
            self._elegidos = set()
            await self._cargar_platillos()
            return

        for p in self._platillos:
            if p.get("id") in self._elegidos:
                p["visible"] = False
        self._ocultando = False
        apagar(self.hueco_boton_modo, False)
        self._seleccionando = False
        self._elegidos = set()
        self._pintar_modo()
        self._pintar_tabla()
        self._actualizar(self.hueco_boton_modo)

    # ------------------------------------------------------------------
    # Ojito: cambiar la visibilidad de una fila sin recargar toda la tabla
    # ------------------------------------------------------------------
    def _on_toggle_visibilidad(self, platillo: dict):
        self.page_ref.run_task(self._alternar_visibilidad, platillo)

    async def _alternar_visibilidad(self, platillo: dict):
        nuevo_valor = not bool(platillo.get("visible", True))
        try:
            actualizado = await asyncio.to_thread(
                PlatilloDAO.cambiar_visibilidad, platillo["id"], nuevo_valor
            )
        except httpx.RequestError:
            traceback.print_exc()
            aviso(self.page_ref, "No hay conexión con el servidor. Revisa tu internet.")
            return
        except Exception:
            traceback.print_exc()
            aviso(self.page_ref, "No se pudo actualizar la visibilidad. Intenta de nuevo.")
            return

        # Ocultar NO borra: solo deja de salir en el menú público. Se repinta ÚNICAMENTE esa
        # fila (y el chip), sin volver a consultar Supabase.
        valor_final = bool(actualizado.get("visible", nuevo_valor))
        for p in self._platillos:
            if p.get("id") == platillo.get("id"):
                p["visible"] = valor_final
        visibles = sum(1 for p in self._platillos if p.get("visible", True))
        self.texto_chip.value = f"{visibles} de {len(self._platillos)} a la vista en tu menú"
        for indice, p in enumerate(self._mostrados):
            if p.get("id") == platillo.get("id") and indice < len(self.cuerpo.controls):
                self.cuerpo.controls[indice] = self._crear_fila(p)
                break
        self._actualizar(self.cuerpo, self.texto_chip)

    # ------------------------------------------------------------------
    # Agregar / editar: abren el mismo diálogo
    # ------------------------------------------------------------------
    def _on_agregar_click(self, e):
        DialogoPlatillo(self.router, on_guardado=self._on_guardado, platillo=None).abrir()

    async def _abrir_dialogo_nuevo_al_montar(self):
        self._on_agregar_click(None)

    def _on_editar_click(self, platillo: dict):
        DialogoPlatillo(self.router, on_guardado=self._on_guardado, platillo=platillo).abrir()

    def _on_guardado(self, aviso_limpieza: str | None = None):
        """Tras crear/actualizar/eliminar con éxito: aquí SÍ se recarga contra Supabase (un
        alta cambia el total y el orden; un borrado quita la fila). `aviso_limpieza` llega si de
        pasada falló borrar una foto vieja en R2 (el guardado ya salió bien)."""
        if aviso_limpieza:
            aviso(self.page_ref, aviso_limpieza)
        self.page_ref.run_task(self._cargar_platillos)
