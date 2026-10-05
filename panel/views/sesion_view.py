"""
views/sesion_view.py
La pantalla de entrar del panel, con el diseño manchas + vidrio (02/10, maqueta aprobada:
https://claude.ai/artifact/AXNeYMtPR1tSVgWdXTFjMu). Va en una ventana chica y centrada, no a
pantalla completa (MainController._ventana_login), sin barra lateral, y siempre es lo primero al
abrir: la sesión NUNCA se guarda en disco (decisión de negocio, ver "POR QUÉ EL LOGIN NO SE
GUARDA" del roadmap).

Dos mitades del mismo alto: a la izquierda la tarjeta sólida con correo + contraseña, y a la
derecha las manchas con grano (naranjas en el tema claro, azules en el oscuro: D.manchas_login),
la frase y la etiqueta de la marca. Las manchas, la frase y la etiqueta son los tres no
negociables del desarrollador: con el rediseño solo cambió su letra (Plus Jakarta Sans).

Lo que NO cambió: sign_in_with_password, el candado de licencia justo después del login (fail
closed) y los mensajes. Los errores (y el "Cerraste sesión." al volver) salen dentro de la
tarjeta, debajo del botón, como en la ventana Perfil.
"""
import asyncio

import flet as ft
import httpx
from supabase_auth.errors import AuthApiError

from models.configuracion_negocio_dao import ConfiguracionNegocioDAO
from models.supabase_client import SUPABASE_ADMIN_EMAIL, client
from views.diseno import apagar, caja_error, etiqueta, icono, texto
from views.piezas import sin_auto_update
from views.tema import D

# Todo a 48 del borde de su mitad, 56 arriba: el título de la tarjeta y la frase de las manchas
# empiezan a la misma altura y a la misma distancia de su borde; abajo, la nota de la tarjeta y
# la etiqueta de la marca terminan juntas.
MARGEN, MARGEN_ARRIBA = 48, 56
RADIO = 22
# Los títulos grandes: Jakarta 800 a 56, interlineado 1.04 y -0.03em.
TAMANO_TITULO = 56
ESPACIADO_TITULO = -1.68


def _titulo(valor, color=None):
    return texto(valor, TAMANO_TITULO, 800, color, espaciado=ESPACIADO_TITULO, alto=1.04)


class SesionView(ft.Container):
    def __init__(self, router, motivo=None):
        """`motivo` es un aviso al llegar ("Cerraste sesión."), si lo hay: sale en la tarjeta."""
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        self.bgcolor = D.suelo
        self.padding = 12

        # El correo ya viene puesto (el del .env): el foco empieza en la contraseña.
        self.campo_correo, caja_correo = self._campo(
            "correo", valor=SUPABASE_ADMIN_EMAIL, tipo=ft.KeyboardType.EMAIL)
        self.campo_password, caja_password = self._campo(
            "candado", pista="Tu contraseña", contrasena=True, autofoco=True)

        # "Entrar al panel": el botón principal (tinta) a todo lo ancho, con la forma de los campos.
        self.texto_boton = texto("Entrar al panel", 14, 600, D.sobre_tinta)
        self.boton_entrar = ft.Container(
            height=48, border_radius=12, bgcolor=D.tinta, alignment=ft.Alignment.CENTER,
            content=ft.Row([icono("entrar", 16, D.sobre_tinta), self.texto_boton], spacing=8,
                           tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            on_click=self._on_entrar_click, animate_opacity=150,
        )
        self.boton_entrar.on_hover = self._encima_boton

        # Errores y avisos, debajo del botón (caja_error: chip sin rojo, icono de alerta o info).
        self.texto_mensaje = texto("", 13, 500, alto=1.45, expand=True)
        self.zona_mensaje = caja_error(self.texto_mensaje)
        self.zona_mensaje.margin = ft.Margin.only(top=14)
        if motivo:
            self._poner_mensaje(motivo, "info")

        formulario = ft.Column([
            ft.Container(content=etiqueta("CORREO"), margin=ft.Margin.only(bottom=8)),
            caja_correo,
            ft.Container(content=etiqueta("CONTRASEÑA"), margin=ft.Margin.only(top=14, bottom=8)),
            caja_password,
            ft.Container(height=20),
            self.boton_entrar,
            self.zona_mensaje,
        ], spacing=0, horizontal_alignment=ft.CrossAxisAlignment.STRETCH)

        # La nota de abajo: por qué pide entrar cada vez (la sesión no se guarda, ver arriba).
        pie = ft.Container(height=48, content=ft.Row([
            icono("candado", 14, D.tenue),
            texto("Por seguridad, el panel te pide entrar cada vez que lo abres.", 12.5, 500,
                  D.tenue),
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER))

        tarjeta = ft.Container(
            expand=94, bgcolor=D.solido, border=ft.Border.all(1, D.linea), border_radius=RADIO,
            padding=ft.Padding(left=MARGEN - 1, top=MARGEN_ARRIBA - 1, right=MARGEN - 1,
                               bottom=MARGEN - 1),
            content=ft.Column([
                ft.Column([
                    _titulo("Inicia sesión"),
                    ft.Container(height=14),
                    texto("Ingresa tus datos para administrar tu menú.", 16, 500, D.suave,
                          alto=1.45),
                    ft.Container(height=40),
                    formulario,
                ], spacing=0, horizontal_alignment=ft.CrossAxisAlignment.STRETCH),
                pie,
            ], spacing=0, alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        )

        # A la derecha, las manchas con grano (WebP animado: Flutter lo reproduce solo), la frase
        # y la etiqueta de la marca. Oscuras en los dos temas; el color de las manchas es el del
        # acento del tema.
        grano = ft.Container(
            expand=106, border_radius=RADIO, bgcolor="#000000", border=ft.Border.all(1, "#1FFFFFFF"),
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
            content=ft.Stack([
                ft.Image(src=D.manchas_login, fit=ft.BoxFit.COVER,
                         width=float("inf"), height=float("inf")),
                ft.Container(left=MARGEN, top=MARGEN_ARRIBA,
                             content=_titulo("Moderniza\nTu Negocio", "#FFFFFF")),
                ft.Container(left=MARGEN, right=MARGEN, bottom=MARGEN, content=etiqueta_marca()),
            ]))
        self.content = ft.Row([tarjeta, grano], spacing=12,
                              vertical_alignment=ft.CrossAxisAlignment.STRETCH)

    def _campo(self, nombre_icono, valor="", pista=None, contrasena=False, autofoco=False,
               tipo=None):
        """Un campo del login: caja de 48 con borde fino D.linea (D.suave mientras se escribe en
        ella), radio 12, el icono a la izquierda y, en la contraseña, el ojo a la derecha. Como
        el buscador de Mi menú: la caja es un Container y el TextField va sin borde."""
        campo = ft.TextField(
            value=valor, hint_text=pista, password=contrasena, autofocus=autofoco,
            keyboard_type=tipo, border=ft.InputBorder.NONE, filled=False, dense=True,
            expand=True, content_padding=ft.Padding.symmetric(vertical=12),
            text_size=14, text_style=ft.TextStyle(font_family="Jakarta500", color=D.texto),
            hint_style=ft.TextStyle(font_family="Jakarta500", color=D.tenue, size=14),
            cursor_color=D.texto, selection_color=D.chip,
            on_change=self._al_escribir,
            on_submit=sin_auto_update(self._on_entrar_click) if contrasena else None,
        )
        # La contraseña empieza encendida: lleva el autofoco.
        caja = ft.Container(
            height=48, border_radius=12, border=ft.Border.all(1, D.suave if autofoco else D.linea),
            padding=ft.Padding.only(left=14, right=6 if contrasena else 14),
        )

        def enfocar(encendida):
            caja.border = ft.Border.all(1, D.suave if encendida else D.linea)
            caja.update()

        campo.on_focus = lambda e: enfocar(True)
        campo.on_blur = lambda e: enfocar(False)
        if contrasena:
            # El ojo va DENTRO del TextField (suffix_icon): un clic fuera del campo le quita el
            # foco (Flutter, en escritorio), y devolvérselo con focus() selecciona todo lo escrito.
            campo.suffix_icon = self._ojo(campo)
            campo.suffix_icon_size_constraints = ft.BoxConstraints(
                min_width=36, max_width=36, min_height=36, max_height=36)
        caja.content = ft.Row([icono(nombre_icono, 16, D.suave), campo], spacing=10,
                              vertical_alignment=ft.CrossAxisAlignment.CENTER)
        return campo, caja

    def _ojo(self, campo):
        # Mostrar / ocultar la contraseña. El icono se reemplaza (uno montado no se cambia).
        boton = ft.Container(width=36, height=36, border_radius=10, alignment=ft.Alignment.CENTER,
                             content=icono("ojo", 16, D.suave), tooltip="Mostrar contraseña")

        def alternar(e):
            campo.password = not campo.password
            boton.content = icono("ojo" if campo.password else "oculto", 16, D.suave)
            boton.tooltip = "Mostrar contraseña" if campo.password else "Ocultar contraseña"
            campo.update()

        def encima(e):
            boton.bgcolor = D.chip if e.data in (True, "true") else None
            boton.update()

        boton.on_click = alternar
        boton.on_hover = encima
        return boton

    def _encima_boton(self, e):
        if self.boton_entrar.disabled:
            return
        self.boton_entrar.opacity = 0.86 if e.data in (True, "true") else 1
        self.boton_entrar.update()

    def _al_escribir(self, e):
        # Al volver a escribir se quita el error de antes (como en Perfil).
        if self.zona_mensaje.visible:
            self.zona_mensaje.visible = False
            self.zona_mensaje.update()

    def _on_entrar_click(self, e):
        self.page_ref.run_task(self._iniciar_sesion)

    async def _iniciar_sesion(self):
        if self.boton_entrar.disabled:
            return
        correo = (self.campo_correo.value or "").strip()
        password = self.campo_password.value or ""

        if not correo or not password:
            self._mostrar_error("Correo o contraseña incorrectos.")
            return

        self._set_cargando(True)
        try:
            # sign_in_with_password es red bloqueante (SDK sync): a un hilo aparte.
            respuesta = await asyncio.to_thread(
                client.auth.sign_in_with_password,
                {"email": correo, "password": password},
            )
            if not respuesta.session:
                self._mostrar_error("Correo o contraseña incorrectos.")
                self._set_cargando(False)
                return

            # EL CANDADO DE LICENCIA: después del login y antes de entrar.
            if not await self._licencia_ok():
                return
            self.router.mostrar_panel()
            return  # la vista ya se reemplazó; no tocar más sus controles
        except AuthApiError as e:
            print(f"[login] credenciales rechazadas: {e}")
            self._mostrar_error("Correo o contraseña incorrectos.")
        except httpx.RequestError as e:
            print(f"[login] error de red: {e}")
            self._mostrar_error("No hay conexión con el servidor. Revisa tu internet.")
        except Exception as e:
            print(f"[login] error inesperado: {e}")
            self._mostrar_error("Algo salió mal al iniciar sesión. Intenta de nuevo.")

        self._set_cargando(False)

    async def _licencia_ok(self) -> bool:
        """Revisa configuracion_negocio.activo. Si no está activo —o si no se pudo averiguar—
        cierra la sesión recién abierta y se queda aquí. Si no se pudo averiguar, NO deja pasar."""
        try:
            activa = await asyncio.to_thread(ConfiguracionNegocioDAO.licencia_activa)
        except Exception as e:
            print(f"[licencia] no se pudo verificar la licencia: {e}")
            await self._cerrar_sesion_silenciosa()
            self._mostrar_error("No se pudo verificar la licencia. Revisa tu internet e intenta de nuevo.")
            self._set_cargando(False)
            return False

        if not activa:
            print("[licencia] activo = False: se bloquea la entrada al panel.")
            await self._cerrar_sesion_silenciosa()
            self._mostrar_error("Este sistema está desactivado. Comunícate con el proveedor "
                                "del software para reactivarlo.")
            self._set_cargando(False)
            return False

        return True

    async def _cerrar_sesion_silenciosa(self):
        try:
            await asyncio.to_thread(client.auth.sign_out, {"scope": "local"})
        except Exception as e:
            print(f"[licencia] sign_out tras el rechazo falló, se ignora: {e}")

    def _poner_mensaje(self, mensaje, nombre_icono):
        # caja_error trae el icono de alerta; el aviso de llegada lleva el de info.
        self.texto_mensaje.value = mensaje
        self.zona_mensaje.content.controls[0] = icono(nombre_icono, 16, D.suave)
        self.zona_mensaje.visible = True

    def _mostrar_error(self, mensaje: str):
        self._poner_mensaje(mensaje, "alerta")
        self.zona_mensaje.update()

    def _set_cargando(self, cargando: bool):
        # Apagado mientras entra, y dice "Entrando…": no hay rueda de carga.
        if cargando and self.zona_mensaje.visible:
            self.zona_mensaje.visible = False
            self.zona_mensaje.update()
        apagar(self.boton_entrar, cargando)
        self.texto_boton.value = "Entrando…" if cargando else "Entrar al panel"
        self.boton_entrar.update()


def etiqueta_marca():
    # La etiqueta de abajo de las manchas: translúcida, borde parejo, el logo en blanco y
    # "Fragmentless · Panel de escritorio" al 85 %. No se pulsa.
    def tramo(valor, peso):
        return ft.TextSpan(valor, style=ft.TextStyle(font_family=f"Jakarta{peso}", size=15,
                                                     color=ft.Colors.WHITE))

    fila = ft.Row([
        ft.Image(src="assets/fragmentless-blanco.png", height=22, fit=ft.BoxFit.CONTAIN),
        ft.Text(spans=[tramo("Fragmentless", 700), tramo(" · Panel de escritorio", 500)]),
    ], spacing=10, tight=True, opacity=0.85)
    return ft.Container(height=48, border_radius=12, bgcolor="#0DFFFFFF", blur=ft.Blur(8, 8),
                        border=ft.Border.all(1, "#40FFFFFF"), alignment=ft.Alignment.CENTER_LEFT,
                        padding=ft.Padding(left=18, top=0, right=22, bottom=0), content=fila)
