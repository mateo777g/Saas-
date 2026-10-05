import traceback

import flet as ft

from models import perfil
from views.diseno import (boton, boton_cuadro, caja_error, campo, etiqueta, sombra_vidrio,
                          texto)
from views.piezas import capa_ventana, sin_auto_update
from views.tema import D

# --- VENTANA "PERFIL" ---
# Se abre al pulsar el pie de la barra lateral: "Nombre completo" y "¿Cómo quieres que
# Fragmentless te llame?". Lo que se guarda está en models/perfil.py.
#
# Diseño manchas + vidrio (30/09), como las ventanas de agregar mesa / platillo: tarjeta sólida de
# radio 26, etiqueta mono "PERFIL", título, X arriba y un solo botón en tinta. Maqueta aprobada:
# https://claude.ai/artifact/TUMyJiwQiuQrHao64KEpKA. Los errores salen DENTRO de la ventana
# (caja_error); al guardar se cierra sin aviso, como las demás ventanas.
#
# No es de una sección, es de todo el panel: su capa va en page.overlay, encima de la ventana
# entera (la barra incluida), y no dentro de una vista. Se crea una vez y se queda ahí; al cambiar
# de vista no se pierde (al cambiar de tema, MainController la quita para que nazca con el velo
# nuevo). Escape y un clic en el velo la cierran.

ANCHO_TARJETA = 440
MAXIMO = 20                 # lo que cabe en el saludo de Inicio sin salirse


def abrir_perfil(router):
    page = router.page
    ventana = getattr(router, "ventana_perfil", None)
    if ventana is None:
        capa, abrir, cerrar = capa_ventana(page)
        ventana = router.ventana_perfil = {"capa": capa, "abrir": abrir, "cerrar": cerrar}
        # El velo cierra con el cerrar() de esta vez, que además le devuelve Escape a la vista.
        capa.on_click = sin_auto_update(lambda _: ventana["al_cerrar"]())
        page.overlay.append(capa)
        page._overlay.update()

    campo_nombre = campo(pista="Tu nombre y apellidos", valor=perfil.nombre_completo())
    # Sin pista: el dueño no quiso un "Ej: …".
    campo_llamarte = campo(valor=perfil.elegido())
    texto_error = texto("", 12.5, 500, expand=True)
    zona_error = caja_error(texto_error)
    zona_error.margin = ft.Margin.only(top=14)

    def cerrar():
        # Escape vuelve a ser de la vista (las que cierran con él sus ventanitas).
        if page.on_keyboard_event == al_teclear:
            page.on_keyboard_event = anterior
        ventana["cerrar"]()

    def mostrar_error(mensaje):
        texto_error.value = mensaje
        zona_error.visible = True
        zona_error.update()

    def guardar(_=None):
        llamarte = campo_llamarte.value.strip()
        if len(llamarte) > MAXIMO:
            mostrar_error(f"Cómo te llamo: máximo {MAXIMO} letras.")
            return
        try:
            perfil.guardar(campo_nombre.value, llamarte)
        except OSError:
            traceback.print_exc()
            mostrar_error("No se pudo guardar el perfil. Intenta de nuevo.")
            return
        cerrar()
        # El nombre nuevo, ya: en el pie de la barra que se ve y en el saludo de Inicio si está.
        for pintar in (getattr(router, "pintores_perfil", None) or {}).values():
            try:
                pintar()
            except RuntimeError:
                pass            # un pintor de una vista que ya no está en pantalla

    def al_teclear(e):
        ft.context.disable_auto_update()
        if e.key == "Escape":
            cerrar()

    def al_escribir_llamarte(_):
        # El error se va en cuanto se corrige lo que se escribe.
        if zona_error.visible:
            zona_error.visible = False
            zona_error.update()

    # Enter en cualquiera de los dos campos guarda, como "Guardar cambios".
    campo_nombre.on_submit = sin_auto_update(guardar)
    campo_llamarte.on_submit = sin_auto_update(guardar)
    campo_llamarte.on_change = sin_auto_update(al_escribir_llamarte)

    tarjeta = ft.Container(
        width=ANCHO_TARJETA, padding=28, bgcolor=D.solido, border=ft.Border.all(1, D.linea),
        border_radius=26, shadow=sombra_vidrio(),
        content=ft.Column([
            ft.Row([
                ft.Column([
                    etiqueta("PERFIL"),
                    texto("Tus datos", 24, 800, espaciado=-0.5),
                    texto("Y cómo te llama Fragmentless en el panel.", 12.5, 500, D.suave,
                          alto=1.45),
                ], spacing=6, tight=True, expand=True),
                boton_cuadro("cerrar", sin_auto_update(lambda _: cerrar()), "Cerrar"),
            ], vertical_alignment=ft.CrossAxisAlignment.START, spacing=12),
            ft.Container(height=22),
            etiqueta("NOMBRE COMPLETO"),
            ft.Container(height=8),
            campo_nombre,
            ft.Container(height=18),
            etiqueta("¿CÓMO QUIERES QUE FRAGMENTLESS TE LLAME?"),
            ft.Container(height=8),
            campo_llamarte,
            ft.Container(height=8),
            texto(f"Sale en el saludo de Inicio y del Agente IA. Máximo {MAXIMO} letras.", 12,
                  500, D.tenue),
            zona_error,
            ft.Container(height=24),
            ft.Row([boton("Guardar cambios", "check", sin_auto_update(guardar), principal=True)],
                   alignment=ft.MainAxisAlignment.END),
        ], spacing=0, tight=True, horizontal_alignment=ft.CrossAxisAlignment.STRETCH),
    )

    # Escape cierra, mientras está abierta. Se cambia el manejador sin page.update(): con uno ya
    # puesto no hace falta, y en las demás vistas se comprobó que llega igual; un
    # page.update() compararía la página entera (en Mi biblioteca llena, más de 1 s).
    anterior = page.on_keyboard_event
    page.on_keyboard_event = al_teclear
    ventana["al_cerrar"] = cerrar
    ventana["abrir"](tarjeta)
