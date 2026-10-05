"""
views/components/dialogo_mesa.py
Ventana de alta/edición de una mesa — se abre desde "Agregar mesa" y el lápiz de cada fila en
views/mesas_view.py.

Diseño manchas + vidrio (29/09, maqueta https://claude.ai/artifact/JR1YURXBzRRbR4NRiVtG4L): la
misma ventana que la de platillos (diseno.ventana) pero con un solo campo, porque una mesa solo
tiene nombre. Arriba la etiqueta mono (que dice "GUARDANDO…" mientras guarda), el título y la X;
el campo NOMBRE; la caja de error; y el botón principal.

La X explícita + el guard `_ocupado` en `_cerrar()` existen por la MISMA razón documentada en
dialogo_platillo.py: AlertDialog(modal=True) no deja cancelar con tap-fuera ni Escape, y sin el
guard un guardado a medias se podría cortar a la mitad.
"""
import asyncio
import traceback

import flet as ft
import httpx

from models.mesa_dao import MesaDAO
from views.diseno import apagar, boton, boton_cuadro, caja_error, campo, etiqueta, texto, ventana

_ANCHO_TARJETA = 440


class DialogoMesa:
    """Uso: DialogoMesa(router, on_guardado=callback, mesa=fila_o_None).abrir()

    `mesa=None` → modo alta. `mesa=<dict>` → modo edición, precargado con esa fila.
    `on_guardado` se llama sin argumentos tras crear/actualizar con éxito, para que
    mesas_view.py recargue la tabla."""

    def __init__(self, router, on_guardado, mesa: dict | None = None):
        self.router = router
        self.page = router.page
        self.on_guardado = on_guardado
        self.editando = mesa is not None
        self.mesa = mesa or {}
        self._ocupado = False

        self.campo_nombre = campo(
            valor=self.mesa.get("nombre", ""),
            pista='Ej. "Mesa 6" o "Barra 1"',
            autofoco=True,
            al_enviar=self._on_guardar_click,
        )

        self.texto_error = texto("", 12.5, 500, expand=True)
        self.zona_error = caja_error(self.texto_error)

        self.boton_guardar = boton(
            "Guardar cambios" if self.editando else "Agregar mesa",
            "check" if self.editando else "mas",
            self._on_guardar_click,
            principal=True,
        )

        self._texto_arriba = "EDITAR MESA" if self.editando else "NUEVA MESA"
        self.texto_paso = etiqueta(self._texto_arriba)

        self.dialog = ventana(
            ft.Column(
                # Sin tight=True el Column reclama todo el alto disponible del diálogo.
                tight=True,
                spacing=0,
                horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                controls=[
                    ft.Row([
                        ft.Column([
                            self.texto_paso,
                            texto(self.mesa.get("nombre") if self.editando else "Agrega una mesa",
                                  24, 800, espaciado=-0.5, max_lines=1,
                                  overflow=ft.TextOverflow.ELLIPSIS),
                        ], spacing=6, tight=True, expand=True),
                        # modal=True bloquea el tap fuera y Escape: la X es la salida.
                        boton_cuadro("cerrar", lambda e: self._cerrar(), "Cerrar"),
                    ], vertical_alignment=ft.CrossAxisAlignment.START),
                    ft.Container(height=22),
                    ft.Column([etiqueta("NOMBRE"), self.campo_nombre], spacing=8, tight=True,
                              horizontal_alignment=ft.CrossAxisAlignment.STRETCH),
                    ft.Container(height=14),
                    self.zona_error,
                    ft.Container(height=10),
                    ft.Row([self.boton_guardar], alignment=ft.MainAxisAlignment.END),
                ],
            ),
            _ANCHO_TARJETA,
        )

    # ------------------------------------------------------------------
    def abrir(self):
        self.page.show_dialog(self.dialog)

    def _cerrar(self):
        if self._ocupado:
            return
        self.page.pop_dialog()

    def _validar(self):
        nombre = (self.campo_nombre.value or "").strip()
        if not nombre:
            return None, "Escribe un nombre para la mesa."
        return nombre, None

    def _on_guardar_click(self, e):
        if self._ocupado:
            return
        nombre, error = self._validar()
        if error:
            self._mostrar_error(error)
            return
        self.page.run_task(self._guardar, nombre)

    async def _guardar(self, nombre: str):
        self._set_cargando(True)
        try:
            if self.editando:
                await asyncio.to_thread(MesaDAO.actualizar, self.mesa["id"], nombre)
            else:
                await asyncio.to_thread(MesaDAO.crear, nombre)
        except httpx.RequestError:
            traceback.print_exc()
            self._set_cargando(False)
            self._mostrar_error("No hay conexión con el servidor. Revisa tu internet.")
            return
        except Exception:
            # Incluye el choque con la restricción UNIQUE(nombre) si ya existe una mesa con ese
            # nombre — Postgres lo rechaza con un error de la API que cae aquí.
            traceback.print_exc()
            self._set_cargando(False)
            self._mostrar_error("No se pudo guardar. ¿Ya existe una mesa con ese nombre?")
            return

        self._set_cargando(False)  # si no, _cerrar() se niega a cerrar (_ocupado sigue True)
        self._cerrar()
        self.on_guardado()

    def _mostrar_error(self, mensaje: str):
        self.texto_error.value = mensaje
        self.zona_error.visible = True
        self.zona_error.update()

    def _set_cargando(self, cargando: bool):
        # Sin rueda de carga: el botón apagado y, arriba, "GUARDANDO…".
        self._ocupado = cargando
        self.texto_paso.value = "GUARDANDO…" if cargando else self._texto_arriba
        apagar(self.boton_guardar, cargando)
        self.texto_paso.update()
        self.boton_guardar.update()
