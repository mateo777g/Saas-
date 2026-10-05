"""
views/mesas_view.py
Mesas con el diseño manchas + vidrio (29/09), SIN el fondo de manchas (es exclusivo del Agente
IA): la vista pinta su propio suelo (D.suelo) y MainController lo sube detrás de la barra. Las
reglas están en planes/plan panel.txt ("DISEÑO MANCHAS + VIDRIO"); la maqueta aprobada, en
https://claude.ai/artifact/JR1YURXBzRRbR4NRiVtG4L.

Aquí el dueño agrega/renombra/borra las mesas del catálogo (tabla public.mesas), que es la lista
que mesas.html muestra para elegir. Además, cada fila dice si la mesa tiene una cuenta abierta,
desde hace cuánto y por cuánto (models/estado_mesas.py, mismo criterio que "Mesas ahora" de
Inicio).

- Barra de arriba (vidrio): "Mesas", chip con cuántas mesas hay, Actualizar y "Agregar mesa".
- Tarjeta de vidrio: "TUS MESAS" + cuántas están ocupadas y lo que hay por cobrar, y la tabla
  en sólido (MESA · ESTADO · ABIERTA · CUENTA · lápiz y bote).

Los datos no se refrescan solos: se leen al entrar y con Actualizar.
"""
import asyncio
import datetime
import traceback

import flet as ft
import httpx

from models.estado_mesas import cuenta_de, cuentas_por_mesa
from models.mesa_dao import MesaDAO
from models.venta_dao import VentaDAO
from views.components.dialogo_mesa import DialogoMesa
from views.diseno import (ALTO_BARRA_SUPERIOR, MARGEN, apagar, boton, boton_cuadro, confirmar,
                          etiqueta, icono, punto, texto, vidrio)
from views.piezas import aviso
from views.tema import D, VERDE

# Anchos relativos de las columnas (la maqueta: 2fr 1.2fr 1.2fr 1fr) y el fijo de las acciones.
COLUMNAS = [("MESA", 20), ("ESTADO", 12), ("ABIERTA", 12), ("CUENTA", 10)]
ANCHO_ACCIONES = 80
ESPACIO_COLUMNAS = 16


def _dinero(valor) -> str:
    # Mismo criterio que _formatear_precio() de menu_view.py: sin decimales si es entero.
    numero = float(valor or 0)
    return f"${int(numero):,}" if numero.is_integer() else f"${numero:,.2f}"


def _hace(desde) -> str:
    """'hace 12 min' / 'hace 1 h 10 min' desde que se abrió la cuenta."""
    if desde is None:
        return "—"
    minutos = int((datetime.datetime.now().astimezone() - desde).total_seconds() // 60)
    if minutos < 1:
        return "hace un momento"
    if minutos < 60:
        return f"hace {minutos} min"
    horas, resto = divmod(minutos, 60)
    return f"hace {horas} h {resto} min" if resto else f"hace {horas} h"


def _plural(cantidad, singular, plural):
    return f"{cantidad} {singular if cantidad == 1 else plural}"


def _estado(ocupada):
    # Como "Mesas ahora" de Inicio: punto lleno = ocupada; punto hueco = disponible.
    if ocupada:
        return ft.Row([punto(D.tinta, 8), texto("Ocupada", 12.5, 600)], spacing=8, tight=True)
    return ft.Row([ft.Container(width=8, height=8, border_radius=4,
                                border=ft.Border.all(1.5, D.tenue)),
                   texto("Disponible", 12.5, 500, D.tenue)], spacing=8, tight=True)


class MesasView(ft.Container):
    def __init__(self, router):
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        # El suelo liso del tema: MainController lo sube a toda la ventana, detrás de la barra.
        self.bgcolor = D.suelo

        self._mesas: list[dict] = []
        # clave normalizada -> {"total", "desde"}; None si no se pudieron leer las cuentas.
        self._cuentas: dict | None = {}
        self._cargando = False

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        self.texto_chip = texto("Cargando tus mesas…", 12, 500, D.suave)
        self.boton_actualizar = boton("Actualizar", "actualizar", self._on_actualizar_click)
        barra_superior = vidrio(
            radio=18, sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=12),
            contenido=ft.Row([
                texto("Mesas", 15, 700),
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE), self.texto_chip], spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
                ft.Container(expand=True),
                self.boton_actualizar,
                boton("Agregar mesa", "mas", self._on_agregar_click, principal=True),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # Tabla (sólido)
        # --------------------------------------------------------------
        self.texto_conteo = etiqueta("")
        self.cuerpo = ft.Column(spacing=0, expand=True, scroll=ft.ScrollMode.AUTO,
                                controls=[self._nota("Cargando tus mesas…")])
        cabecera = ft.Container(
            height=40, padding=ft.Padding.symmetric(horizontal=16),
            border=ft.Border(bottom=ft.BorderSide(1, D.linea)),
            content=self._celdas([etiqueta(nombre) for nombre, _ in COLUMNAS]),
        )
        tabla = ft.Container(
            expand=True, border_radius=18, border=ft.Border.all(1, D.linea), bgcolor=D.solido,
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Column([cabecera, self.cuerpo], spacing=0),
        )

        tarjeta = vidrio(
            radio=26, padding=20,
            top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN, bottom=MARGEN,
            contenido=ft.Column([
                ft.Container(
                    padding=ft.Padding.only(left=4, top=4, right=4),
                    content=ft.Row([
                        ft.Column([
                            etiqueta("TUS MESAS"),
                            texto("Estas son las mesas que aparecen para elegir en mesas.html, "
                                  "el sistema de registro de ventas.", 12.5, 500, D.suave,
                                  alto=1.45),
                        ], spacing=6, tight=True, expand=True),
                        self.texto_conteo,
                    ], vertical_alignment=ft.CrossAxisAlignment.END, spacing=16),
                ),
                tabla,
            ], spacing=16),
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
            pass    # se salió de Mesas antes de que llegaran los datos

    @staticmethod
    def _nota(titulo, detalle=None):
        # Los estados de la tabla (cargando, vacía, sin conexión): una nota centrada.
        lineas = [texto(titulo, 14.5, 700, text_align=ft.TextAlign.CENTER)]
        if detalle:
            lineas.append(texto(detalle, 12.5, 500, D.suave, text_align=ft.TextAlign.CENTER))
        return ft.Container(
            padding=ft.Padding.symmetric(vertical=48, horizontal=16),
            alignment=ft.Alignment.CENTER,
            content=ft.Column(lineas, spacing=6, tight=True,
                              horizontal_alignment=ft.CrossAxisAlignment.CENTER),
        )

    @staticmethod
    def _celdas(contenidos, acciones=None):
        """Una fila con los anchos de las columnas + el hueco de las acciones. La usan la
        cabecera y las filas, así siempre quedan alineadas."""
        controles = [ft.Container(expand=peso, content=contenido,
                                  alignment=ft.Alignment.CENTER_LEFT)
                     for (_, peso), contenido in zip(COLUMNAS, contenidos)]
        controles.append(ft.Container(width=ANCHO_ACCIONES, content=acciones,
                                      alignment=ft.Alignment.CENTER_RIGHT))
        return ft.Row(controles, spacing=ESPACIO_COLUMNAS,
                      vertical_alignment=ft.CrossAxisAlignment.CENTER)

    # ------------------------------------------------------------------
    # Carga
    # ------------------------------------------------------------------
    async def _cargar(self):
        self._cargando = True
        apagar(self.boton_actualizar, True)
        self._actualizar(self.boton_actualizar)
        try:
            await self._leer()
        finally:
            self._cargando = False
            apagar(self.boton_actualizar, False)
            self._actualizar(self.boton_actualizar)

    async def _leer(self):
        # supabase-py es síncrono: a un hilo para no congelar la ventana. Una consulta tras otra
        # (varias a la vez en el mismo cliente fallaban con WinError 10035, ver Inicio).
        try:
            self._mesas = await asyncio.to_thread(MesaDAO.obtener_todos)
        except httpx.RequestError:
            traceback.print_exc()
            self._poner_error("Sin conexión.", "No hay conexión con el servidor. Revisa tu internet.")
            return
        except Exception:
            traceback.print_exc()
            self._poner_error("No se pudieron cargar tus mesas.", "Intenta de nuevo en un momento.")
            return

        # Las cuentas abiertas son un extra: si fallan, las mesas se siguen pudiendo administrar.
        try:
            self._cuentas = cuentas_por_mesa(await asyncio.to_thread(VentaDAO.obtener_abiertas))
        except Exception:
            traceback.print_exc()
            self._cuentas = None
        self._pintar()

    def _poner_error(self, titulo, detalle):
        self._mesas = []
        self.texto_chip.value = "Sin conexión"
        self.texto_conteo.value = ""
        self.cuerpo.controls = [self._nota(titulo, detalle)]
        self._actualizar(self.texto_chip, self.texto_conteo, self.cuerpo)

    # ------------------------------------------------------------------
    # Pintado
    # ------------------------------------------------------------------
    def _pintar(self):
        n = len(self._mesas)
        self.texto_chip.value = f"{_plural(n, 'mesa', 'mesas')} para elegir en mesas.html"

        if self._cuentas is None:
            self.texto_conteo.value = "NO SE PUDIERON LEER LAS CUENTAS"
        else:
            abiertas = [c for c in (cuenta_de(m, self._cuentas) for m in self._mesas) if c]
            self.texto_conteo.value = (
                f"{len(abiertas)} DE {n} OCUPADA{'' if len(abiertas) == 1 else 'S'}"
                + (f" · {_dinero(sum(c['total'] for c in abiertas))} POR COBRAR"
                   if abiertas else ""))

        if not self._mesas:
            self.texto_conteo.value = ""
            self.cuerpo.controls = [self._nota("Todavía no hay ninguna mesa.",
                                               "Agrega la primera con el botón de arriba.")]
        else:
            self.cuerpo.controls = [self._crear_fila(m) for m in self._mesas]
        self._actualizar(self.texto_chip, self.texto_conteo, self.cuerpo)

    def _cuenta(self, mesa):
        return cuenta_de(mesa, self._cuentas) if self._cuentas is not None else None

    def _crear_fila(self, mesa: dict):
        cuenta = self._cuenta(mesa)
        if self._cuentas is None:
            # Sin cuentas no se sabe si está ocupada: guiones, nunca un "Disponible" inventado.
            estado = texto("—", 12.5, 500, D.tenue)
        else:
            estado = _estado(cuenta is not None)
        contenidos = [
            ft.Row([
                ft.Container(width=36, height=36, border_radius=11, bgcolor=D.chip,
                             alignment=ft.Alignment.CENTER, content=icono("mesas", 18)),
                texto(mesa.get("nombre") or "", 13.5, 700, expand=True, max_lines=1,
                      overflow=ft.TextOverflow.ELLIPSIS),
            ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            estado,
            texto(_hace(cuenta["desde"]) if cuenta else "—", 12.5, 500,
                  D.suave if cuenta else D.tenue),
            texto(_dinero(cuenta["total"]) if cuenta else "—", 13, 500,
                  D.texto if cuenta else D.tenue, mono=True),
        ]
        acciones = ft.Row([
            boton_cuadro("crear", lambda e, m=mesa: self._on_editar_click(m), "Renombrar mesa"),
            boton_cuadro("eliminar", lambda e, m=mesa: self._on_eliminar_click(m),
                         "Eliminar mesa"),
        ], spacing=8, tight=True)
        return ft.Container(
            padding=ft.Padding.symmetric(horizontal=16, vertical=12),
            border=ft.Border(bottom=ft.BorderSide(1, D.linea)),
            content=self._celdas(contenidos, acciones),
        )

    # ------------------------------------------------------------------
    # Acciones
    # ------------------------------------------------------------------
    def _on_actualizar_click(self, e):
        if not self._cargando:
            self.page_ref.run_task(self._cargar)

    def _on_agregar_click(self, e):
        DialogoMesa(self.router, on_guardado=self._on_guardado, mesa=None).abrir()

    def _on_editar_click(self, mesa: dict):
        DialogoMesa(self.router, on_guardado=self._on_guardado, mesa=mesa).abrir()

    def _on_eliminar_click(self, mesa: dict):
        cuenta = self._cuenta(mesa)
        confirmar(
            self.page_ref,
            titulo="¿Eliminar esta mesa?",
            mensaje=(f"\"{mesa.get('nombre', '')}\" ya no aparecerá para elegir en mesas.html. "
                     "Las ventas que ya se hicieron con ese nombre no se ven afectadas: se "
                     "quedan tal cual en el historial."),
            # mesas.html empareja las cuentas abiertas con el catálogo por nombre: sin la mesa,
            # esa cuenta ya no tiene dónde salir.
            nota=(f"Tiene una cuenta abierta de {_dinero(cuenta['total'])}. Si la eliminas "
                  "ahora, esa cuenta deja de verse en mesas.html.") if cuenta else None,
            al_confirmar=lambda: self.page_ref.run_task(self._eliminar_async, mesa),
        )

    async def _eliminar_async(self, mesa: dict):
        try:
            await asyncio.to_thread(MesaDAO.eliminar, mesa["id"])
        except httpx.RequestError:
            traceback.print_exc()
            aviso(self.page_ref, "No hay conexión con el servidor. Revisa tu internet.")
            return
        except Exception:
            traceback.print_exc()
            aviso(self.page_ref, "No se pudo eliminar la mesa. Intenta de nuevo.")
            return
        await self._cargar()

    def _on_guardado(self):
        self.page_ref.run_task(self._cargar)
