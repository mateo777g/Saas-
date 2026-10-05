"""
views/ajustes_view.py
Ajustes con el diseño manchas + vidrio (30/09), SIN el fondo de manchas (es exclusivo del Agente
IA): la vista pinta su propio suelo (D.suelo) y MainController lo sube detrás de la barra. Las
reglas están en planes/plan panel.txt ("DISEÑO MANCHAS + VIDRIO"); la maqueta aprobada, en
https://claude.ai/artifact/QNMone8zhHWvzae5aVHG2f.

- Barra de arriba (vidrio): "Ajustes" y el chip "Se guardan en esta computadora" (todo va a
  panel/config.json, models/config_usuario.py).
- Tarjeta de vidrio que mide lo que su contenido: "TUS AJUSTES" y dos tarjetas en sólido, lado a
  lado y del mismo alto:
    · Exportaciones locales: la ruta (solo lectura) + el botón de carpeta, que abre el selector
      NATIVO de Windows con Tkinter (dueño: nada de FilePicker de Flet). Elegir una carpeta solo
      la muestra; se escribe en disco al pulsar "Guardar ajustes" (guardar_ruta_exportacion),
      que confirma en el propio botón (palomita verde ~1.6 s; sin banner de éxito). Si la
      carpeta ya no existe o no se pudo guardar, sale caja_error unos segundos.
    · Tema: selector Oscuro / Claro. Al elegir, el segmento se mueve y luego
      router.cambiar_tema() guarda la clave "tema" y rehace Ajustes con los colores nuevos.
Cerrar sesión vive solo en la barra lateral (views/barra_lateral.py).
"""
import asyncio
import os
import tkinter as tk
import traceback
from tkinter import filedialog

import flet as ft

from models.config_usuario import guardar_ruta_exportacion, obtener_ruta_exportacion
from views import tema
from views.diseno import (ALTO_BARRA_SUPERIOR, MARGEN, boton, boton_cuadro, caja_error, campo,
                          etiqueta, icono, punto, texto, vidrio)
from views.tema import D, VERDE

# Los temas del panel (views/tema.py), en el orden del selector: texto, icono y su nombre en
# config.json.
TEMAS = [
    ("Oscuro", "luna", "oscuro"),
    ("Claro", "sol", "claro"),
]


def _elegir_carpeta_exportacion() -> str | None:
    """Selector de carpetas NATIVO de Windows vía Tkinter (misma técnica que
    _elegir_archivo_imagen() en dialogo_platillo.py). Devuelve la ruta o None si se canceló.
    Bloqueante de verdad: siempre vía asyncio.to_thread, o congelaría la ventana de Flet."""
    raiz = tk.Tk()
    raiz.withdraw()
    raiz.attributes("-topmost", True)  # que no se abra detrás de la ventana de Flet
    try:
        ruta = filedialog.askdirectory(title="Selecciona la carpeta de exportación")
    finally:
        raiz.destroy()
    return ruta or None


def _encabezado(nombre_icono, titulo, descripcion):
    # Arriba de cada tarjeta: cuadro de icono 36 + título y descripción.
    return ft.Row([
        ft.Container(width=36, height=36, border_radius=11, bgcolor=D.chip,
                     alignment=ft.Alignment.CENTER, content=icono(nombre_icono, 18)),
        ft.Column([
            texto(titulo, 14.5, 700),
            texto(descripcion, 12.5, 500, D.suave, alto=1.45),
        ], spacing=3, tight=True, expand=True),
    ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER)


def _raya():
    return ft.Container(height=1, bgcolor=D.linea, margin=ft.Margin.symmetric(vertical=20))


def _tarjeta_solida(contenido, peso):
    return ft.Container(
        expand=peso, padding=20, bgcolor=D.solido, border=ft.Border.all(1, D.linea),
        border_radius=18, content=contenido,
    )


class AjustesView(ft.Container):
    def __init__(self, router):
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        # El suelo liso del tema: MainController lo sube a toda la ventana, detrás de la barra.
        self.bgcolor = D.suelo

        # True mientras el selector de Tkinter está abierto o se está guardando: acciones
        # exclusivas entre sí.
        self._ocupado = False
        self._aviso_token = 0
        self._tema_elegido = tema.actual()

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        barra_superior = vidrio(
            radio=18, sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=12),
            contenido=ft.Row([
                texto("Ajustes", 15, 700),
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE),
                                    texto("Se guardan en esta computadora", 12, 500, D.suave)],
                                   spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # Exportaciones locales
        # --------------------------------------------------------------
        # Arranca con la ruta YA guardada (o ~/Downloads): la misma función que usa Mi
        # biblioteca para "Exportar", así las dos pantallas muestran el mismo destino.
        self.ruta_exportacion = campo(valor=obtener_ruta_exportacion(), read_only=True,
                                      expand=True)
        self.boton_carpeta = boton_cuadro("carpeta-abrir", self._on_elegir_carpeta_click,
                                          "Elegir carpeta", lado=44)

        self.texto_error = texto("", 12.5, 500, expand=True)
        self.zona_error = caja_error(self.texto_error)
        self.zona_error.margin = ft.Margin.only(top=14)

        self.boton_guardar = boton("Guardar ajustes", "guardar", self._on_guardar_click,
                                   principal=True)
        self._contenido_guardar = self.boton_guardar.content

        exportaciones = _tarjeta_solida(ft.Column([
            _encabezado("carpeta", "Exportaciones locales",
                        "Define la carpeta donde se guardarán tus imágenes y publicaciones."),
            _raya(),
            etiqueta("RUTA PARA EXPORTAR CONTENIDO"),
            ft.Container(height=8),
            ft.Row([self.ruta_exportacion, self.boton_carpeta], spacing=10,
                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
            self.zona_error,
            ft.Container(expand=True, height=20),
            ft.Row([
                texto("Elige una carpeta accesible desde esta computadora.", 12, 500, D.tenue,
                      expand=True),
                self.boton_guardar,
            ], spacing=16, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        ], spacing=0), 3)

        # --------------------------------------------------------------
        # Tema
        # --------------------------------------------------------------
        self.selector_tema = ft.Container(padding=3, border_radius=12, bgcolor=D.chip,
                                          content=self._segmentos_tema())
        tarjeta_tema = _tarjeta_solida(ft.Column([
            _encabezado("contraste", "Tema", "Los colores del panel: oscuro o claro."),
            _raya(),
            etiqueta("COLORES DEL PANEL"),
            ft.Container(height=8),
            self.selector_tema,
            ft.Container(expand=True, height=20),
            texto("El cambio se ve al momento en todo el panel.", 12, 500, D.tenue),
        ], spacing=0), 2)

        tarjeta = vidrio(
            radio=26, padding=20,
            top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN,
            contenido=ft.Column([
                ft.Container(
                    padding=ft.Padding.only(left=4, top=4, right=4),
                    content=ft.Column([
                        etiqueta("TUS AJUSTES"),
                        texto("Configura dónde se guardará el contenido que generes y los "
                              "colores del panel.", 12.5, 500, D.suave, alto=1.45),
                    ], spacing=6, tight=True),
                ),
                # Las dos tarjetas del mismo alto (el de la más alta), como en la maqueta.
                ft.Row([exportaciones, tarjeta_tema], spacing=16, intrinsic_height=True,
                       vertical_alignment=ft.CrossAxisAlignment.STRETCH),
            ], spacing=16, tight=True),
        )

        self.content = ft.Stack([tarjeta, barra_superior], expand=True)

    # ------------------------------------------------------------------
    def _actualizar(self, *controles):
        # Si ya se salió de Ajustes mientras corría una tarea, update() falla: se ignora.
        for control in controles:
            try:
                control.update()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # Elegir carpeta (Tkinter, vía asyncio.to_thread)
    # ------------------------------------------------------------------
    def _on_elegir_carpeta_click(self, e):
        if self._ocupado:
            return
        self.page_ref.run_task(self._elegir_carpeta_async)

    async def _elegir_carpeta_async(self):
        self._ocupado = True
        self.boton_carpeta.disabled = True
        self._actualizar(self.boton_carpeta)
        try:
            ruta = await asyncio.to_thread(_elegir_carpeta_exportacion)
        finally:
            self._ocupado = False
            self.boton_carpeta.disabled = False
            self._actualizar(self.boton_carpeta)

        if not ruta:
            return  # canceló el selector
        # Se muestra ya, pero se guarda solo con "Guardar ajustes".
        self.ruta_exportacion.value = os.path.normpath(ruta)
        self._actualizar(self.ruta_exportacion)

    # ------------------------------------------------------------------
    # Guardar ajustes
    # ------------------------------------------------------------------
    def _on_guardar_click(self, e):
        if self._ocupado:
            return
        self.page_ref.run_task(self._guardar_async)

    async def _guardar_async(self):
        ruta = (self.ruta_exportacion.value or "").strip()
        if not ruta or not os.path.isdir(ruta):
            self._mostrar_error("Esa carpeta ya no existe. Elige otra antes de guardar.")
            return

        self._ocupado = True
        self._poner_boton("guardando")
        try:
            # Escritura local rápida, pero a un hilo como todo lo bloqueante del panel.
            await asyncio.to_thread(guardar_ruta_exportacion, ruta)
        except OSError:
            traceback.print_exc()
            self._mostrar_error("No se pudo guardar el ajuste. Revisa los permisos de la "
                                "carpeta e intenta de nuevo.")
            self._ocupado = False
            self._poner_boton("reposo")
            return
        except Exception:
            traceback.print_exc()
            self._mostrar_error("No se pudo guardar el ajuste. Intenta de nuevo.")
            self._ocupado = False
            self._poner_boton("reposo")
            return

        self._ocupado = False
        self._poner_boton("guardado")
        self.page_ref.run_task(self._restaurar_boton)

    def _poner_boton(self, estado):
        """reposo = "Guardar ajustes"; guardando = rueda + "Guardando..." (apagado);
        guardado = palomita verde + "Ajustes guardados" (sin banner de éxito)."""
        color = D.sobre_tinta
        if estado == "guardando":
            self.boton_guardar.content = ft.Row([
                ft.ProgressRing(width=14, height=14, stroke_width=2, color=color),
                texto("Guardando...", 13, 600, color),
            ], spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER)
        elif estado == "guardado":
            self.boton_guardar.content = ft.Row([
                icono("check", 16, VERDE), texto("Ajustes guardados", 13, 600, color),
            ], spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER)
        else:
            self.boton_guardar.content = self._contenido_guardar
        self.boton_guardar.disabled = estado == "guardando"
        self._actualizar(self.boton_guardar)

    async def _restaurar_boton(self, espera_seg: float = 1.6):
        await asyncio.sleep(espera_seg)
        self._poner_boton("reposo")

    def _mostrar_error(self, mensaje: str, duracion_seg: int = 4):
        # Temporal (se oculta sola): esta pantalla no tiene ventana donde dejarlo fijo.
        self._aviso_token += 1
        token = self._aviso_token
        self.texto_error.value = mensaje
        self.zona_error.visible = True
        self._actualizar(self.zona_error)
        self.page_ref.run_task(self._ocultar_error_luego, token, duracion_seg)

    async def _ocultar_error_luego(self, token: int, duracion_seg: int):
        await asyncio.sleep(duracion_seg)
        if token != self._aviso_token:
            return
        self.zona_error.visible = False
        self._actualizar(self.zona_error)

    # ------------------------------------------------------------------
    # Tema
    # ------------------------------------------------------------------
    def _segmentos_tema(self):
        # Como diseno.selector() pero con icono y los dos segmentos del mismo ancho.
        segmentos = []
        for etiqueta_tema, nombre_icono, nombre in TEMAS:
            es = nombre == self._tema_elegido
            color = D.texto if es else D.suave
            segmentos.append(ft.Container(
                expand=True, height=38, border_radius=9, alignment=ft.Alignment.CENTER,
                bgcolor=D.solido if es else None,
                shadow=ft.BoxShadow(blur_radius=3, color="#26000000", offset=ft.Offset(0, 1))
                if es else None,
                content=ft.Row([icono(nombre_icono, 16, color),
                                texto(etiqueta_tema, 12.5, 600, color)],
                               spacing=8, tight=True,
                               vertical_alignment=ft.CrossAxisAlignment.CENTER),
                on_click=lambda e, n=nombre: self._on_cambiar_tema(n),
            ))
        return ft.Row(segmentos, spacing=2)

    def _on_cambiar_tema(self, nombre: str):
        if nombre == self._tema_elegido:
            return
        # Primero se ve el segmento moverse; luego router.cambiar_tema() guarda la elección en
        # config.json y rehace Ajustes (con su barra) con los colores nuevos.
        self._tema_elegido = nombre
        self.selector_tema.content = self._segmentos_tema()
        self._actualizar(self.selector_tema)

        async def cambiar():
            await asyncio.sleep(0.3)
            self.router.cambiar_tema(nombre)

        self.page_ref.run_task(cambiar)
