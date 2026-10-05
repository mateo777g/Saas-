"""Genera el logo animado de "Pensando..." del agente de IA, uno por tema:

    assets/logo-pensando-naranja.webp   (tema claro)
    assets/logo-pensando-azul.webp      (tema oscuro)

    python panel/herramientas/generar_logo_pensando.py

Por qué es un WebP animado y no una animación desde python: el agente mueve cuadros desde python
y se congelaba en cuanto la máquina trabajaba (que es siempre mientras piensa: lee Supabase y
espera a OpenAI). El WebP lo reproduce el cliente solo. Nunca volver a un timer de python.

Qué dibuja: el MISMO logo del saludo y de cada respuesta (D.logo_simbolo, el de trazo grueso
de assets/fragmentless.png), del mismo color, al mismo tamaño y en el mismo hueco (_logo_saludo
de agenteIA_view.py: el logo a 3/4 de un cuadro). En reposo es idéntico al logo fijo, así que al
llegar la respuesta el cambio no brinca. La animación: el logo se parte en sus 7 piezas (cada
cara con su pedazo de trazo), que se separan un poco hacia afuera girando y vuelven a juntarse.

Cómo: del PNG se mide cuánto blanco lleva cada píxel (el trazo) y se etiquetan las caras; cada
píxel de trazo se reparte a la cara más cercana (así cada pieza lleva su pedazo). Cada pieza es
una capa RGBA: trazo en el color, cara con el tinte en degradado (22 % -> 4 %, igual que el SVG
del símbolo). Se mueven las capas cuadro por cuadro, se componen a 4x y se reducen.
"""
import math
import os

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGEN = os.path.join(RAIZ, "assets", "fragmentless.png")
AZUL_PNG = (19, 85, 232)                                  # el fondo de fragmentless.png
COLORES = {"naranja": (0xE8, 0x62, 0x2A), "azul": (0x13, 0x55, 0xE8)}   # = D.acento por tema

LADO = 112          # px por cuadro en el archivo (se muestra a 42: nítido en pantallas 2.5x)
SUPER = 4           # se compone a LADO*SUPER y se reduce: bordes suaves
PROPORCION = 0.75   # el logo ocupa 3/4 del cuadro, como en _logo_saludo()
CUADROS = 36
MS_POR_CUADRO = 70  # 36 x 70 ms = ~2.5 s por vuelta
SEPARACION = 0.06   # cuánto se aleja cada pieza, en fracción del lado del logo
GIRO = 9.0          # grados que gira cada pieza en lo más separado


def piezas(lado_logo):
    """Las 7 capas RGBA (una por cara) del logo a `lado_logo` px, en blanco y negro de alfa:
    devuelve (alfa_trazo, alfa_tinte, centro) por pieza, ya recortadas al cuadrado del logo."""
    px = np.asarray(Image.open(ORIGEN).convert("RGB"), dtype=np.float32)
    rojo = (px[..., 0] - AZUL_PNG[0]) / (255 - AZUL_PNG[0])
    verde = (px[..., 1] - AZUL_PNG[1]) / (255 - AZUL_PNG[1])
    blanco = np.clip((rojo + verde) / 2, 0, 1)

    etiquetas = measure.label(blanco <= 0.6, connectivity=1)
    fondo = etiquetas[0, 0]
    dentro = etiquetas != fondo                       # el hexágono (trazo + caras)
    caras = [r for r in measure.regionprops(etiquetas) if r.label != fondo and r.area >= 200]

    # Cada píxel del hexágono va a la cara más cercana.
    semillas = np.zeros_like(etiquetas)
    for i, cara in enumerate(caras, start=1):
        semillas[etiquetas == cara.label] = i
    _, (fi, ci) = ndimage.distance_transform_edt(semillas == 0, return_indices=True)
    duena = semillas[fi, ci] * dentro

    # Recorte cuadrado al hexágono, igual que el viewBox del SVG del símbolo.
    filas, columnas = np.nonzero(dentro)
    lado = max(filas.max() - filas.min(), columnas.max() - columnas.min()) + 1
    y0 = (filas.max() + filas.min() + 1 - lado) // 2
    x0 = (columnas.max() + columnas.min() + 1 - lado) // 2

    def recortar(m):
        img = Image.fromarray((m[y0:y0 + lado, x0:x0 + lado] * 255).astype(np.uint8), "L")
        return np.asarray(img.resize((lado_logo, lado_logo), Image.LANCZOS), np.float32) / 255

    resultado = []
    for i, cara in enumerate(caras, start=1):
        es_cara = etiquetas == cara.label
        # Tinte en degradado sobre la caja de la cara (objectBoundingBox 0,0 -> 0.55,1 del SVG).
        f0, c0, f1, c1 = cara.bbox
        yy, xx = np.mgrid[f0:f1, c0:c1]
        u = (xx - c0) / max(1, c1 - c0 - 1)
        v = (yy - f0) / max(1, f1 - f0 - 1)
        t = np.clip((u * 0.55 + v) / (0.55 ** 2 + 1), 0, 1)
        tinte = np.zeros_like(blanco)
        tinte[f0:f1, c0:c1] = 0.22 + (0.04 - 0.22) * t
        tinte *= es_cara
        trazo = blanco * (duena == i)
        cy, cx = cara.centroid
        centro = ((cx - x0) / lado, (cy - y0) / lado)       # en fracción del logo
        resultado.append((recortar(trazo), recortar(tinte), centro))
    return resultado


def capa(alfa_trazo, alfa_tinte, color, lienzo, desfase):
    """Una pieza como imagen RGBA del tamaño del lienzo, con el logo centrado."""
    alfa = alfa_trazo + (1 - alfa_trazo) * alfa_tinte
    lado_logo = alfa.shape[0]
    rgba = np.zeros((lado_logo, lado_logo, 4), np.uint8)
    rgba[..., :3] = color
    rgba[..., 3] = np.round(np.clip(alfa, 0, 1) * 255)
    img = Image.new("RGBA", (lienzo, lienzo))
    img.paste(Image.fromarray(rgba, "RGBA"), (desfase, desfase))
    return img


REPOSO = 0.25       # la primera cuarta parte de la vuelta el logo está entero y quieto
RETRASO = 0.04      # cada pieza arranca un poco después que la anterior: una onda, no un bloque


def curva(fase, j, total):
    """Cuánto está separada la pieza j (0 = en su lugar, 1 = lo más lejos) en esta fase de la
    vuelta. Todas terminan en 0 antes de acabar la vuelta: el primer y el último cuadro son el
    logo entero, así que al llegar la respuesta nunca queda a medio partir por culpa del ciclo."""
    if fase < REPOSO:
        return 0.0
    x = (fase - REPOSO) / (1 - REPOSO)
    ventana = 1 - RETRASO * (total - 1)
    local = (x - RETRASO * j) / ventana
    if not 0 <= local <= 1:
        return 0.0
    return math.sin(math.pi * local) ** 2


def main():
    lienzo = LADO * SUPER
    lado_logo = round(lienzo * PROPORCION)
    desfase = (lienzo - lado_logo) // 2
    partes = piezas(lado_logo)

    for nombre, color in COLORES.items():
        capas = [capa(t, n, color, lienzo, desfase) for t, n, _ in partes]
        cuadros = []
        for k in range(CUADROS):
            cuadro = Image.new("RGBA", (lienzo, lienzo))
            for j, (img, (_, _, (cx, cy))) in enumerate(zip(capas, partes)):
                a = curva(k / CUADROS, j, len(partes))
                dx, dy = cx - 0.5, cy - 0.5
                norma = math.hypot(dx, dy) or 1.0
                mover = SEPARACION * lado_logo * a
                centro = (desfase + cx * lado_logo, desfase + cy * lado_logo)
                giro = GIRO * a * (1 if j % 2 else -1)
                pieza = img.rotate(giro, resample=Image.BICUBIC, center=centro,
                                   translate=(dx / norma * mover, dy / norma * mover))
                cuadro.alpha_composite(pieza)
            cuadros.append(cuadro.resize((LADO, LADO), Image.LANCZOS))
        destino = os.path.join(RAIZ, "assets", f"logo-pensando-{nombre}.webp")
        cuadros[0].save(destino, save_all=True, append_images=cuadros[1:],
                        duration=MS_POR_CUADRO, loop=0, lossless=True, method=6)
        print(f"Listo: {destino} ({os.path.getsize(destino) // 1024} KB)")


if __name__ == "__main__":
    main()
