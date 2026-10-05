"""Genera el fondo de manchas animado del panel (el rediseño del 28/09):

    python panel/herramientas/generar_fondo_manchas.py

    assets/fondo-manchas-claro.webp    hueso #fafaf8 con manchas negras
    assets/fondo-manchas-oscuro.webp   carbón #161616 con manchas negras

Va detrás de TODO el panel (MainController), así que la barra lateral y las
tarjetas de vidrio lo dejan ver desenfocado. Reglas del diseño en
planes/plan panel.txt.

Es el efecto "Dithering" de @paper-design/shaders (forma "warp", trama 4x4)
pasado a numpy: unas vetas que se retuercen y se pintan con una trama de
Bayer 4x4, o sea con puntitos que se juntan donde la veta es fuerte y se
abren en los bordes.

Como el logo de "Pensando..." y las manchas del login, es UN WebP animado que
Flutter reproduce solo: python no manda un solo cuadro (ver el porqué en
agenteIA_view.py, D.logo_pensando).

Cada píxel del archivo es un puntito de la trama. Se muestra con
filter_quality=NONE (vecino más cercano), así que cada puntito sale como un
cuadrito nítido de ~3 px en pantalla y el archivo pesa poco.

La vuelta cierra sola: el tiempo t solo aparece dentro de cos(... + t) y
sin(t - ...), así que al ir de 0 a 2π el último cuadro empalma con el primero.
"""
import os

import numpy as np
from PIL import Image

ANCHO, ALTO = 540, 344      # puntitos de la trama (~3 px de pantalla cada uno)
CUADROS = 300
MS_POR_CUADRO = 70          # 300 x 70 ms = 21 s por vuelta: calmado, como speed=0.2
PISO = 0.14                 # lo que se le quita a la forma para limpiar el fondo liso
ESCALA = 0.0105             # unidades de la veta por puntito (más = vetas más finas)

# (fondo, manchas). Manchas negras en los dos temas (rediseño del 28/09, ver
# planes/plan panel.txt): sobre el hueso claro y sobre el carbón del oscuro.
COLORES = {
    "oscuro": ((22, 22, 22), (0, 0, 0)),
    "claro": ((250, 250, 248), (10, 10, 10)),
}
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BAYER4 = np.array([[0, 8, 2, 10],
                   [12, 4, 14, 6],
                   [3, 11, 1, 9],
                   [15, 7, 13, 5]], dtype=np.float32) / 16.0 + 0.5 / 16  # sin 0: el fondo liso queda limpio


def _smoothstep(a, b, x):
    k = np.clip((x - a) / (b - a), 0.0, 1.0)
    return k * k * (3 - 2 * k)


def _forma(t: float, x, y):
    # La forma "warp" del shader, tal cual: cinco pasadas que retuercen el
    # plano y luego unas franjas que se afilan donde sin(...) se acerca a 0.
    x = x.copy()
    y = y.copy()
    for i in range(1, 6):
        x += 0.6 / i * np.cos(i * 2.5 * y + t)
        y += 0.6 / i * np.cos(i * 1.5 * x + t)
    forma = 0.15 / np.maximum(0.001, np.abs(np.sin(t - y - x)))
    # Fuera de las vetas la forma nunca baja de ~0.13, y eso llenaba el fondo
    # liso de una rejilla de puntitos sueltos. Se le resta ese piso.
    return np.clip((_smoothstep(0.02, 1.0, forma) - PISO) / (1 - PISO), 0.0, 1.0)


def main():
    yy, xx = np.mgrid[0:ALTO, 0:ANCHO].astype(np.float32)
    # Centrado, para que las vetas nazcan del medio y no de una esquina.
    x = (xx - ANCHO / 2) * ESCALA
    y = (yy - ALTO / 2) * ESCALA
    umbral = np.tile(BAYER4, (ALTO // 4 + 1, ANCHO // 4 + 1))[:ALTO, :ANCHO]

    mascaras = []
    for n in range(CUADROS):
        t = 2 * np.pi * n / CUADROS
        mascaras.append(_forma(t, x, y) > umbral)

    for nombre, (fondo, mancha) in COLORES.items():
        paleta = np.array([fondo, mancha], dtype=np.uint8)
        cuadros = [Image.fromarray(paleta[m.astype(np.uint8)], "RGB") for m in mascaras]
        destino = os.path.join(RAIZ, "assets", f"fondo-manchas-{nombre}.webp")
        cuadros[0].save(destino, save_all=True, append_images=cuadros[1:],
                        duration=MS_POR_CUADRO, loop=0, lossless=True, quality=100, method=4)
        print(f"{destino}: {os.path.getsize(destino) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
