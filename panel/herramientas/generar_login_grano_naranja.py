"""Pinta de naranja las manchas del login (02/10):

    python panel/herramientas/generar_login_grano_naranja.py

    assets/login-grano.webp           el original: manchas azules #1355E8 (no se toca)
    assets/login-grano-naranja.webp   el mismo, con las manchas en el naranja del logo

Solo cambia el color de las manchas. El negro, el grano crema, los 240 cuadros, sus 50 ms y la
vuelta quedan idénticos: el archivo original no tiene script propio, así que en vez de rehacerlo
se recolorea cuadro por cuadro.

El original usa 14 colores en total: negro, el azul, el azul oscurecido (4 tonos = azul x k),
5 cremas del grano y 3 grises apenas azulados. Cada azul x k pasa a naranja x k; los grises
azulados se espejan a grises apenas cálidos (se cambian R y B), para que el grano no meta un
reflejo azul junto al naranja. Lo demás no se toca.
"""
import os

import numpy as np
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGEN = os.path.join(RAIZ, "assets", "login-grano.webp")
DESTINO = os.path.join(RAIZ, "assets", "login-grano-naranja.webp")

AZUL = (19, 85, 232)        # #1355E8, el azul del logo (D_OSCURO["acento"])
NARANJA = (232, 98, 42)     # #E8622A, el naranja del logo (D_CLARO["acento"])
MS_POR_CUADRO = 50          # el del original (240 x 50 ms = 12 s por vuelta)


def _nuevo_color(color):
    r, g, b = color
    # Un azul del original: el azul del logo multiplicado por k (1, 0.95, 0.8, 0.65, 0.5).
    k = b / AZUL[2]
    if b > 100 and all(abs(c - a * k) <= 2 for c, a in zip(color, AZUL)):
        return tuple(round(n * k) for n in NARANJA)
    # Un gris apenas azulado (B un poco más alto que R y G): se espeja a cálido.
    if b > r and r == g and b - r <= 4:
        return (b, g, r)
    return color


def main():
    im = Image.open(ORIGEN)
    cuadros = []
    cambios = {}
    for n in range(im.n_frames):
        im.seek(n)
        rgb = np.array(im.convert("RGB"))
        planos = rgb.reshape(-1, 3)
        colores, indices = np.unique(planos, axis=0, return_inverse=True)
        nuevos = np.array([_nuevo_color(tuple(int(c) for c in color)) for color in colores],
                          dtype=np.uint8)
        for viejo, nuevo in zip(colores, nuevos):
            if tuple(viejo) != tuple(nuevo):
                cambios[tuple(int(c) for c in viejo)] = tuple(int(c) for c in nuevo)
        cuadros.append(Image.fromarray(nuevos[indices.reshape(-1)].reshape(rgb.shape), "RGB"))

    for viejo, nuevo in sorted(cambios.items()):
        print(f"  {viejo} -> {nuevo}")
    cuadros[0].save(DESTINO, save_all=True, append_images=cuadros[1:], duration=MS_POR_CUADRO,
                    loop=0, lossless=True, quality=100, method=4)
    print(f"{DESTINO}: {len(cuadros)} cuadros, {os.path.getsize(DESTINO) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
