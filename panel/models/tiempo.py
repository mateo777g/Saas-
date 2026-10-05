"""
models/tiempo.py
Lo que el panel sabe de la hora local, en un solo lugar.

Vive aquí y no dentro de una vista porque lo usan dos pantallas que no se
conocen entre sí: home_view.py lo tenía adentro desde que el saludo de
Inicio dejó de ser el texto fijo "Buenos días", y agenteIA_view.py lo
necesita (vía models/ia_controller.py) para que el saludo que escribe el
modelo pueda decir "Buenas tardes" cuando de verdad es tarde.

Los cortes viven en UNA sola función a propósito. Duplicados en dos
archivos, tarde o temprano alguien mueve uno y no el otro, y el panel
acabaría dando los buenos días en una pantalla y las buenas tardes en la
otra a la misma hora.
"""

# Cortes de uso común en México: mañana hasta las 12, tarde hasta las 19,
# noche de ahí en adelante.
_CORTE_MANANA = 12
_CORTE_TARDE = 19


def momento_del_dia(hora: int) -> str:
    """'mañana' / 'tarde' / 'noche'. En minúsculas y sin saludo, para
    meterlo en una frase ("es de tarde") o en un prompt."""
    if hora < _CORTE_MANANA:
        return "mañana"
    if hora < _CORTE_TARDE:
        return "tarde"
    return "noche"


def saludo_por_hora(hora: int) -> str:
    """'Buenos días' / 'Buenas tardes' / 'Buenas noches' según la hora.

    Recibe la hora como parámetro (en vez de llamar a datetime.now() aquí
    adentro) para que se pueda probar sin depender del reloj real."""
    return {
        "mañana": "Buenos días",
        "tarde": "Buenas tardes",
        "noche": "Buenas noches",
    }[momento_del_dia(hora)]
