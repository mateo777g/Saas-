"""Calca assets/fragmentless.png (el logo de trazo grueso) a SVG y saca, por color:

    assets/fragmentless-azul.svg      cuadro azul, logo blanco (barra lateral, tema oscuro)
    assets/fragmentless-naranja.svg   cuadro naranja (D.acento claro), logo blanco (barra, tema claro)
    assets/fragmentless-{azul,naranja}-simbolo.svg   solo el logo, sin cuadro, en su color, con
                                      las caras transparentes y un tinte suave (saludo del agente)

    python panel/herramientas/vectorizar_logo.py

El PNG de 2048 px se veía pixeleado reducido a 40 px en la barra lateral; el SVG sale nítido
a cualquier tamaño. Se calca así: cada píxel es el azul de fondo mezclado con blanco en alguna
medida; con esa medida se sacan los contornos (skimage) del hexágono blanco y de cada cara
(los huecos entre trazos), se simplifican a polígonos y se escriben: fondo, hexágono blanco y
encima las caras en el color de fondo con el degradado aclarado de arriba a la izquierda.
"""
import os

import numpy as np
from PIL import Image
from skimage import measure

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGEN = os.path.join(RAIZ, "assets", "fragmentless.png")
AZUL = (19, 85, 232)
COLORES = {"azul": "#1355E8", "naranja": "#E8622A"}   # = D.acento de views/tema.py (claro / oscuro)
# Tolerancia (en px del PNG) al simplificar: las caras son polígonos de lados rectos; el contorno
# del hexágono tiene las esquinas redondeadas y se deja más fino para que sigan curvas.
TOL_CARA = 1.5
TOL_HEXAGONO = 0.8


def medir_blanco(pixeles):
    rojo = (pixeles[..., 0] - AZUL[0]) / (255 - AZUL[0])
    verde = (pixeles[..., 1] - AZUL[1]) / (255 - AZUL[1])
    return np.clip((rojo + verde) / 2, 0, 1)


def ruta(contorno):
    # skimage da (fila, columna); SVG quiere x, y.
    puntos = " L ".join(f"{c:.1f},{f:.1f}" for f, c in contorno[:-1])
    return f"M {puntos} Z"


def contornos(pixeles):
    blanco = medir_blanco(pixeles)
    # El trazo es blanco puro; las caras llegan a ~20 % de blanco en su esquina más clara.
    trazo = blanco > 0.6
    etiquetas = measure.label(~trazo, connectivity=1)
    lado = trazo.shape[0]
    fondo = etiquetas[0, 0]

    # Hexágono: todo lo que no es el fondo de afuera.
    hexagono = (etiquetas != fondo).astype(float)
    borde_hex = max(measure.find_contours(np.pad(hexagono, 1), 0.5), key=len) - 1
    hexa = measure.approximate_polygon(borde_hex, TOL_HEXAGONO)

    caras = []
    for region in measure.regionprops(etiquetas):
        if region.label == fondo or region.area < 200:
            continue
        mascara = np.pad((etiquetas == region.label).astype(float), 1)
        borde = max(measure.find_contours(mascara, 0.5), key=len) - 1
        caras.append(measure.approximate_polygon(borde, TOL_CARA))
    return lado, hexa, caras


def escribir(nombre, color, lado, hexa, caras):
    lineas = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{lado}" height="{lado}" '
        f'viewBox="0 0 {lado} {lado}">',
        "<defs>",
        # El aclarado de cada cara: blanco ~20 % arriba a la izquierda que se apaga hacia abajo.
        '<linearGradient id="brillo" x1="0" y1="0" x2="0.55" y2="1">',
        '<stop offset="0" stop-color="#ffffff" stop-opacity="0.2"/>',
        '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>',
        "</linearGradient>",
        "</defs>",
        f'<rect width="{lado}" height="{lado}" fill="{color}"/>',
        f'<path d="{ruta(hexa)}" fill="#ffffff"/>',
    ]
    for cara in caras:
        d = ruta(cara)
        lineas.append(f'<path d="{d}" fill="{color}"/>')
        lineas.append(f'<path d="{d}" fill="url(#brillo)"/>')
    lineas.append("</svg>")
    destino = os.path.join(RAIZ, "assets", f"fragmentless-{nombre}.svg")
    with open(destino, "w", encoding="utf-8") as archivo:
        archivo.write("\n".join(lineas) + "\n")
    print(f"Listo: {destino} ({len(caras)} caras, hexágono de {len(hexa) - 1} puntos)")


def escribir_simbolo(nombre, color, hexa, caras):
    # Recortado al hexágono (cuadrado, centrado) para que llene la caja donde se ponga.
    filas, columnas = hexa[:, 0], hexa[:, 1]
    lado = max(filas.max() - filas.min(), columnas.max() - columnas.min())
    x0 = (columnas.max() + columnas.min() - lado) / 2
    y0 = (filas.max() + filas.min() - lado) / 2
    # Un solo trazo: el hexágono con las caras como huecos (evenodd). Debajo, las caras con el
    # tinte del color, como el logo viejo (22 % arriba a la izquierda -> 4 %).
    trazo = " ".join([ruta(hexa)] + [ruta(cara) for cara in caras])
    lineas = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{lado:.0f}" height="{lado:.0f}" '
        f'viewBox="{x0:.1f} {y0:.1f} {lado:.1f} {lado:.1f}">',
        "<defs>",
        '<linearGradient id="tinte" x1="0" y1="0" x2="0.55" y2="1">',
        f'<stop offset="0" stop-color="{color}" stop-opacity="0.22"/>',
        f'<stop offset="1" stop-color="{color}" stop-opacity="0.04"/>',
        "</linearGradient>",
        "</defs>",
    ]
    lineas += [f'<path d="{ruta(cara)}" fill="url(#tinte)"/>' for cara in caras]
    lineas.append(f'<path d="{trazo}" fill="{color}" fill-rule="evenodd"/>')
    lineas.append("</svg>")
    destino = os.path.join(RAIZ, "assets", f"fragmentless-{nombre}-simbolo.svg")
    with open(destino, "w", encoding="utf-8") as archivo:
        archivo.write("\n".join(lineas) + "\n")
    print(f"Listo: {destino}")


def main():
    pixeles = np.asarray(Image.open(ORIGEN).convert("RGB"), dtype=np.float32)
    lado, hexa, caras = contornos(pixeles)
    for nombre, color in COLORES.items():
        escribir(nombre, color, lado, hexa, caras)
        escribir_simbolo(nombre, color, hexa, caras)


if __name__ == "__main__":
    main()
