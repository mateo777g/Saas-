import os
from pathlib import Path

import flet as ft

# Todo el panel usa rutas relativas a esta carpeta (assets/..., biblioteca/),
# tanto en ft.Image como en Pillow. Así funciona igual con
# "python panel/main.py" desde la raíz que con "python main.py" desde aquí.
os.chdir(Path(__file__).resolve().parent)

from controllers.main_controller import MainController

def main(page: ft.Page):
    MainController(page)

if __name__ == "__main__":
    ft.run(main, assets_dir=".")
