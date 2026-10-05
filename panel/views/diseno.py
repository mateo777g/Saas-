"""
views/diseno.py
Las piezas del diseño nuevo (28/09): el fondo de manchas, el vidrio, las letras y los iconos.
Nació en el Agente IA y es lo que van a usar las demás vistas cuando se rediseñen. Las reglas
(tamaños, pesos, radios, cuándo va vidrio y cuándo sólido) están en planes/plan panel.txt,
"DISEÑO MANCHAS + VIDRIO"; la maqueta aprobada, en panel/diseno/maquetas-agente-ia/.

Los colores salen de views/tema.py (D.texto, D.vidrio...), así que cada pieza se arma con los
del tema que esté puesto al construir la vista.
"""
import flet as ft

from views.tema import D

# Las letras de la maqueta, por peso: Plus Jakarta Sans para todo y JetBrains Mono para las
# etiquetas chicas (fechas, "IDEAS PARA TI", el plan). Flutter no elige el peso de un archivo
# variable, así que cada peso es su propio archivo estático (assets/fuentes/, sacados de los
# variables de Google Fonts con fontTools; licencia OFL al lado). MainController las registra.
FUENTES = {
    "Jakarta400": "assets/fuentes/PlusJakartaSans-Regular.ttf",
    "Jakarta500": "assets/PlusJakartaSans-Medium.ttf",
    "Jakarta600": "assets/fuentes/PlusJakartaSans-SemiBold.ttf",
    "Jakarta700": "assets/PlusJakartaSans-Bold.ttf",
    "Jakarta800": "assets/fuentes/PlusJakartaSans-ExtraBold.ttf",
    "Mono400": "assets/fuentes/JetBrainsMono-Regular.ttf",
    "Mono500": "assets/fuentes/JetBrainsMono-Medium.ttf",
}

# Medidas que se repiten entre piezas (la maqueta, en px).
MARGEN = 16            # del borde de la ventana a la barra, a la barra de arriba y entre ellas
ANCHO_BARRA = 244      # la barra lateral flotante; con sus dos márgenes ocupa 276
ALTO_BARRA_SUPERIOR = 60
DESENFOQUE = 18


def texto(valor, tamano, peso=500, color=None, mono=False, espaciado=None, alto=None, **kwargs):
    """Un texto con la letra de la maqueta. `espaciado` en px (la maqueta lo da en em: 0.14em a
    10.5 px son 1.47 px); `alto` es el interlineado (1.04 del título grande, 1.45 de las
    descripciones)."""
    familia = f"{'Mono' if mono else 'Jakarta'}{peso}"
    estilo = None
    if espaciado is not None or alto is not None:
        estilo = ft.TextStyle(letter_spacing=espaciado, height=alto)
    return ft.Text(valor, size=tamano, font_family=familia, color=color or D.texto,
                   style=estilo, **kwargs)


def etiqueta(valor, tamano=10.5, color=None):
    # Las etiquetas en mayúsculas de la maqueta ("GENERAL", "IDEAS PARA TI", la fecha): mono,
    # separadas 0.14em, en el gris tenue.
    return texto(valor, tamano, 400, color or D.tenue, mono=True, espaciado=round(tamano * 0.14, 2))


def icono(nombre, tamano=18, color=None):
    # Los iconos de trazo de la maqueta (assets/iconos/*.svg, dibujados en negro): el color se
    # les pone tiñéndolos. Nuevo en cada llamada: un icono montado no se cambia, se reemplaza
    # (ver _icono en agenteIA_view.py).
    return ft.Image(src=f"assets/iconos/{nombre}.svg", width=tamano, height=tamano,
                    color=color or D.texto)


def sombra_vidrio():
    return ft.BoxShadow(blur_radius=60, spread_radius=0, color=D.sombra, offset=ft.Offset(0, 24))


def vidrio(contenido=None, radio=22, padding=None, sombra=True, **kwargs):
    """Una superficie de vidrio: el fondo de manchas se ve detrás, desenfocado. Lo llevan la
    barra lateral, la barra de arriba y las tarjetas grandes de cada vista. Lo que se escribe
    o se lee de cerca (la caja de texto, las tarjetas de idea, las tablas) va en sólido.

    ⚠️ La sombra va en un contenedor de afuera, sin blur: flet recorta al borde redondeado
    todo lo de un Container con blur, su propia sombra incluida, y la sombra no se veía."""
    def cristal(**medidas):
        return ft.Container(
            content=contenido,
            blur=ft.Blur(DESENFOQUE, DESENFOQUE),
            bgcolor=D.vidrio,
            border=ft.Border.all(1, D.vidrio_linea),
            border_radius=radio,
            padding=padding,
            **medidas,
        )

    if not sombra:
        return cristal(**kwargs)
    # Medidas y posición (width, expand, top...) van en el de afuera; el cristal lo llena.
    return ft.Container(content=cristal(), border_radius=radio, shadow=sombra_vidrio(), **kwargs)


def fondo_manchas():
    # El fondo animado de todo el panel (herramientas/generar_fondo_manchas.py). Cada píxel del
    # archivo es un puntito: sin filtro (vecino más cercano) salen nítidos.
    return ft.Image(src=D.manchas, fit=ft.BoxFit.COVER, filter_quality=ft.FilterQuality.NONE,
                    gapless_playback=True, left=0, top=0, right=0, bottom=0)


def punto(color, lado=7):
    return ft.Container(width=lado, height=lado, border_radius=lado / 2, bgcolor=color)


def boton(etiqueta_boton, nombre_icono, al_pulsar, principal=False, alto=40):
    """Los botones de la barra de arriba: "Nueva conversación" (principal, en tinta) y los
    secundarios (borde fino, sin relleno). Radio 12, letra 13 semibold, icono 16."""
    color = D.sobre_tinta if principal else D.texto
    cuerpo = ft.Container(
        height=alto,
        padding=ft.Padding.symmetric(horizontal=16 if principal else 14),
        border_radius=12,
        bgcolor=D.tinta if principal else None,
        border=None if principal else ft.Border.all(1, D.linea),
        content=ft.Row([icono(nombre_icono, 16, color), texto(etiqueta_boton, 13, 600, color)],
                       spacing=8, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        on_click=al_pulsar,
        animate_opacity=150,
    )

    def encima(e):
        cuerpo.opacity = 0.86 if e.data in (True, "true") else 1
        cuerpo.update()

    cuerpo.on_hover = encima
    return cuerpo


def apagar(control, apagado):
    # Un botón que no se puede usar ahora (guardando, nada elegido): al 40 % y sin clic.
    control.disabled = apagado
    control.opacity = 0.4 if apagado else 1


def boton_cuadro(nombre_icono, al_pulsar, ayuda, lado=36):
    """Botón de solo icono (el ojito y el lápiz de cada fila, la X de una ventana): cuadro con
    borde fino D.linea, radio 10, icono 16."""
    cuerpo = ft.Container(
        width=lado, height=lado, border_radius=10, border=ft.Border.all(1, D.linea),
        alignment=ft.Alignment.CENTER, content=icono(nombre_icono, 16), tooltip=ayuda,
        on_click=al_pulsar, animate_opacity=150,
    )

    def encima(e):
        cuerpo.bgcolor = D.chip if e.data in (True, "true") else None
        cuerpo.update()

    cuerpo.on_hover = encima
    return cuerpo


def campo(pista="", valor="", multilinea=False, prefijo=None, al_cambiar=None, al_enviar=None,
          autofoco=False, **kwargs):
    """Una caja de texto en sólido: borde 1 px D.linea (D.suave al escribir), radio 12, letra
    13.5. Sin relleno propio: toma el sólido de la ventana o de la tarjeta en la que va."""
    return ft.TextField(
        value=valor, hint_text=pista, multiline=multilinea,
        min_lines=2 if multilinea else None, max_lines=3 if multilinea else 1,
        prefix=ft.Text(prefijo, size=13.5, font_family="Jakarta500", color=D.suave)
        if prefijo else None,
        text_size=13.5, text_style=ft.TextStyle(font_family="Jakarta500", color=D.texto),
        hint_style=ft.TextStyle(font_family="Jakarta500", color=D.tenue, size=13.5),
        border_color=D.linea, focused_border_color=D.suave, focused_border_width=1,
        border_width=1, border_radius=12, filled=False,
        content_padding=ft.Padding.symmetric(horizontal=14, vertical=12),
        cursor_color=D.texto, selection_color=D.chip,
        on_change=al_cambiar, on_submit=al_enviar, autofocus=autofoco, **kwargs,
    )


def selector(opciones, elegida, al_elegir, alto=30, tamano=12.5):
    """El selector segmentado (Hoy/Semana/Mes de Inicio, las categorías de Mi menú): caja
    D.chip radio 12, padding 3; el elegido en sólido con sombra de 1 px. Devuelve el Container;
    se repinta llamando otra vez a selector() y cambiando su .content (ver Mi menú)."""
    segmentos = []
    for opcion in opciones:
        es = opcion == elegida
        segmentos.append(ft.Container(
            height=alto, padding=ft.Padding.symmetric(horizontal=12), border_radius=9,
            alignment=ft.Alignment.CENTER, bgcolor=D.solido if es else None,
            shadow=ft.BoxShadow(blur_radius=3, color="#26000000", offset=ft.Offset(0, 1))
            if es else None,
            content=texto(opcion, tamano, 600, D.texto if es else D.suave),
            on_click=lambda e, o=opcion: al_elegir(o),
        ))
    return ft.Container(padding=3, border_radius=12, bgcolor=D.chip,
                        content=ft.Row(segmentos, spacing=2, tight=True))


def ventana(contenido, ancho):
    """Las ventanas (agregar/editar un platillo, confirmar): AlertDialog modal y transparente;
    lo que se ve es una tarjeta sólida de radio 26 con la sombra del vidrio, sobre el velo del
    tema. modal=True no cierra con Escape ni con el velo: cada ventana trae su X o su Cancelar.
    El Column de `contenido` necesita tight=True (si no, reclama todo el alto del diálogo)."""
    return ft.AlertDialog(
        modal=True, bgcolor=ft.Colors.TRANSPARENT, elevation=0, barrier_color=D.velo,
        content_padding=0,
        content=ft.Container(
            width=ancho, padding=28, bgcolor=D.solido, border=ft.Border.all(1, D.linea),
            border_radius=26, shadow=sombra_vidrio(), content=contenido,
        ),
    )


def caja_error(texto_control):
    # El error dentro de una ventana, sin rojo: chip con borde fino e icono de alerta.
    return ft.Container(
        visible=False, bgcolor=D.chip, border=ft.Border.all(1, D.linea), border_radius=12,
        padding=ft.Padding.symmetric(horizontal=14, vertical=11),
        content=ft.Row([icono("alerta", 16, D.suave), texto_control], spacing=10,
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
    )


def confirmar(page, titulo, mensaje, al_confirmar, texto_boton="Sí, eliminar",
              nombre_icono="eliminar", al_cancelar=None, nota=None, imagen=None):
    """Confirmación de algo que no se deshace (eliminar un platillo o una mesa). Sin rojo: el
    peligro lo dice el texto. Cancelar cierra (y llama a `al_cancelar`, si hay: la ventana de
    editar se vuelve a abrir); el botón principal cierra y llama a `al_confirmar`. `nota` es un
    aviso extra en un chip bajo el mensaje (Mesas: "tiene una cuenta abierta de $340...").
    `imagen` es una miniatura a la derecha del título (Mi biblioteca: el anuncio a borrar)."""
    def cerrar(e=None):
        page.pop_dialog()

    def cancelar(e):
        cerrar()
        if al_cancelar:
            al_cancelar()

    def si(e):
        cerrar()
        al_confirmar()

    cabeza = [
        ft.Container(width=44, height=44, border_radius=12, bgcolor=D.chip,
                     alignment=ft.Alignment.CENTER, content=icono("alerta", 20)),
        ft.Container(height=16),
        texto(titulo, 18, 800, espaciado=-0.3),
        ft.Container(height=6),
        texto(mensaje, 13, 500, D.suave, alto=1.45),
    ]
    if imagen is not None:
        cabeza = [ft.Row([ft.Column(cabeza, spacing=0, tight=True, expand=True), imagen],
                         spacing=16, vertical_alignment=ft.CrossAxisAlignment.START)]

    page.show_dialog(ventana(ft.Column([
        *cabeza,
        *([ft.Container(height=14),
           ft.Container(bgcolor=D.chip, border=ft.Border.all(1, D.linea), border_radius=12,
                        padding=ft.Padding.symmetric(horizontal=14, vertical=11),
                        content=texto(nota, 12.5, 500, alto=1.45))] if nota else []),
        ft.Container(height=24),
        ft.Row([boton("Cancelar", "cerrar", cancelar),
                boton(texto_boton, nombre_icono, si, principal=True)],
               spacing=10, alignment=ft.MainAxisAlignment.END),
    ], tight=True, spacing=0), 420))


def insignia(valor):
    # La pastilla naranja de "IA" en la barra.
    return ft.Container(
        bgcolor=D.acento, border_radius=6, padding=ft.Padding.symmetric(horizontal=7, vertical=3),
        content=texto(valor, 10, 400, "#ffffff", mono=True, espaciado=0.4),
    )
