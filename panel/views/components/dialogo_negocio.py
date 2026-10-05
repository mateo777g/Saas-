"""
views/components/dialogo_negocio.py
Ventana "Datos del negocio" de Crear contenido (01/10): nombre, teléfono, página web y dirección,
los datos que la IA pone en los anuncios (tabla datos_negocio, models/datos_negocio_dao.py). Se
abre desde "Datos del negocio" (barra de arriba) y desde "Editar", junto a "Irá en el anuncio".

Diseño manchas + vidrio, maqueta aprobada https://claude.ai/artifact/EzzYQTCWrHhJJ2Bbmx1WPG
(estado "ventana"): la misma ventana que las de Mi menú y Mesas (diseno.ventana), con la X, los
campos en dos renglones, la nota de qué lleva cada formato y "Guardar datos" (que muestra la
rueda y "Guardando..." mientras guarda). Los errores van en la caja_error; al guardar se cierra
sola, sin aviso.

La X + el guard `_ocupado` en `_cerrar()`: por lo mismo que en dialogo_mesa.py (modal=True no
deja cerrar con Escape ni con el velo, y un guardado no se corta a la mitad).
"""
import asyncio
import traceback

import flet as ft
import httpx

from models.datos_negocio_dao import DatosNegocioDAO
from views.diseno import boton, boton_cuadro, caja_error, campo, etiqueta, texto, ventana
from views.tema import D

_ANCHO_TARJETA = 480


def _renglon_nota(formato, que_lleva):
    return ft.Text(spans=[
        ft.TextSpan(formato, ft.TextStyle(size=10.5, font_family="Mono400", color=D.texto,
                                          letter_spacing=1.05)),
        ft.TextSpan(f" · {que_lleva}", ft.TextStyle(size=12, font_family="Jakarta500",
                                                    color=D.suave, height=1.45)),
    ])


class DialogoNegocio:
    """Uso: DialogoNegocio(router, datos, on_guardado=callback).abrir()

    `datos`: el dict de DatosNegocioDAO.obtener() (o None si no se pudo leer: entonces los
    campos salen vacíos y al guardar se vuelve a leer la fila). `on_guardado(datos_nuevos)` se
    llama tras guardar con éxito."""

    def __init__(self, router, datos: dict | None, on_guardado):
        self.page = router.page
        self.datos = datos or {}
        self.on_guardado = on_guardado
        self._ocupado = False

        self.campo_nombre = campo(pista="Ej. Taku Monky", valor=self.datos.get("nombre", ""),
                                  autofoco=True, al_enviar=self._on_guardar_click)
        self.campo_telefono = campo(pista="Ej. 55 1234 5678",
                                    valor=self.datos.get("telefono", ""),
                                    al_enviar=self._on_guardar_click)
        self.campo_web = campo(pista="Ej. www.tunegocio.com",
                               valor=self.datos.get("pagina_web", ""),
                               al_enviar=self._on_guardar_click)
        self.campo_direccion = campo(pista="Ej. Av. Juárez 123, Centro",
                                     valor=self.datos.get("direccion", ""),
                                     al_enviar=self._on_guardar_click)

        self.texto_error = texto("", 12.5, 500, expand=True)
        self.zona_error = caja_error(self.texto_error)

        self.boton_guardar = boton("Guardar datos", "guardar", self._on_guardar_click,
                                   principal=True)
        self._contenido_guardar = self.boton_guardar.content

        def con_etiqueta(nombre, control, **kwargs):
            return ft.Column([etiqueta(nombre), control], spacing=8, tight=True,
                             horizontal_alignment=ft.CrossAxisAlignment.STRETCH, **kwargs)

        self.dialog = ventana(
            ft.Column(
                tight=True,
                spacing=0,
                horizontal_alignment=ft.CrossAxisAlignment.STRETCH,
                controls=[
                    ft.Row([
                        ft.Column([
                            etiqueta("DATOS DEL NEGOCIO"),
                            texto("Tu negocio", 24, 800, espaciado=-0.5),
                            texto("La IA los pone en tus anuncios, así no los escribes cada "
                                  "vez.", 12.5, 500, D.suave, alto=1.45),
                        ], spacing=6, tight=True, expand=True),
                        boton_cuadro("cerrar", lambda e: self._cerrar(), "Cerrar"),
                    ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.START),
                    ft.Container(height=22),
                    ft.Row([
                        con_etiqueta("NOMBRE DEL NEGOCIO", self.campo_nombre, expand=1),
                        con_etiqueta("TELÉFONO", self.campo_telefono, expand=1),
                    ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.START),
                    ft.Container(height=14),
                    con_etiqueta("PÁGINA WEB", self.campo_web),
                    ft.Container(height=14),
                    con_etiqueta("DIRECCIÓN", self.campo_direccion),
                    ft.Container(height=16),
                    ft.Container(
                        padding=ft.Padding.symmetric(horizontal=14, vertical=12),
                        border_radius=12, bgcolor=D.chip,
                        content=ft.Column([
                            _renglon_nota("POST", "nombre y teléfono"),
                            _renglon_nota("HISTORIA", "nombre, teléfono, página web y dirección"),
                            texto("Lo que dejes vacío no sale en el anuncio.", 12, 500, D.tenue,
                                  alto=1.45),
                        ], spacing=6, tight=True),
                    ),
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

    def _on_guardar_click(self, e):
        if self._ocupado:
            return
        self.page.run_task(self._guardar)

    async def _guardar(self):
        self._set_cargando(True)
        valores = dict(
            nombre=self.campo_nombre.value or "",
            telefono=self.campo_telefono.value or "",
            pagina_web=self.campo_web.value or "",
            direccion=self.campo_direccion.value or "",
        )
        try:
            id_fila = self.datos.get("id")
            if id_fila is None:
                # La vista no pudo leerlos al entrar: se vuelve a leer la fila para tener su id.
                id_fila = (await asyncio.to_thread(DatosNegocioDAO.obtener))["id"]
            nuevos = await asyncio.to_thread(DatosNegocioDAO.guardar, id_fila, **valores)
        except httpx.RequestError:
            traceback.print_exc()
            self._set_cargando(False)
            self._mostrar_error("No hay conexión con el servidor. Revisa tu internet.")
            return
        except Exception:
            traceback.print_exc()
            self._set_cargando(False)
            self._mostrar_error("No se pudieron guardar los datos. Intenta de nuevo.")
            return

        self._set_cargando(False)  # si no, _cerrar() se niega a cerrar (_ocupado sigue True)
        self._cerrar()
        self.on_guardado(nuevos)

    def _mostrar_error(self, mensaje: str):
        self.texto_error.value = mensaje
        self.zona_error.visible = True
        self.zona_error.update()

    def _set_cargando(self, cargando: bool):
        # Como la maqueta: la rueda y "Guardando..." en el mismo botón.
        self._ocupado = cargando
        if cargando:
            self.boton_guardar.content = ft.Row([
                ft.ProgressRing(width=16, height=16, stroke_width=2, color=D.sobre_tinta),
                texto("Guardando...", 13, 600, D.sobre_tinta),
            ], spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER)
        else:
            self.boton_guardar.content = self._contenido_guardar
        self.boton_guardar.disabled = cargando
        self.boton_guardar.update()
