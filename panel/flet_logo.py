"""Fragmentless animated logo for a Flet panel.

Swaps between the eight SVG frames on a timer. SVG is used rather than
PNG so the mark stays crisp at any panel size, and the frames carry no
background of their own, so whatever is behind the panel shows through.

    from flet_logo import FragmentlessLogo
    page.add(FragmentlessLogo(size=140, color="orange"))

Put the svg/ folder in your app's assets directory and start Flet with
`ft.app(main, assets_dir="assets")`.
"""
import threading
import flet as ft

FRAMES = [f"frame{i:02d}" for i in range(36)]

PALETTE = {"orange": "#E8622A", "blue": "#1355E8"}


class FragmentlessLogo(ft.Container):
    """Animated Fragmentless mark.

    size      side length in px
    color     "orange" | "blue"
    interval  seconds per frame (36 frames -> ~2.5s per loop)
    autoplay  start animating on mount
    """

    def __init__(self, size: int = 140, color: str = "orange",
                 interval: float = 0.07, autoplay: bool = True,
                 asset_dir: str = "svg", **kwargs):
        self.frame_size = size
        self.color_name = color
        self.interval = interval
        self.asset_dir = asset_dir

        self._i = 0
        self._timer: threading.Timer | None = None
        self._running = False

        self._img = ft.Image(
            src=self._src(0),
            width=size,
            height=size,
            # ft.ImageFit no existe en el flet de este proyecto (0.8x):
            # el enum se llama ft.BoxFit. Mismo valor, mismo efecto.
            # OJO: si vuelves a reemplazar este archivo por una version
            # nueva del autor, hay que rehacer este cambio.
            fit=ft.BoxFit.CONTAIN,
        )

        super().__init__(content=self._img, width=size, height=size,
                         bgcolor=None, **kwargs)
        self._autoplay = autoplay

    # ------------------------------------------------------------ helpers

    def _src(self, i: int) -> str:
        return f"/{self.asset_dir}/fragmentless-{self.color_name}-{FRAMES[i]}.svg"

    def did_mount(self):
        if self._autoplay:
            self.start()

    def will_unmount(self):
        self.stop()

    # ------------------------------------------------------------- control

    def start(self):
        if self._running:
            return
        self._running = True
        self._tick()

    def stop(self):
        self._running = False
        if self._timer:
            self._timer.cancel()
            self._timer = None

    def set_color(self, color: str):
        """Switch palette live: logo.set_color("blue")"""
        self.color_name = color
        self._img.src = self._src(self._i)
        self.update()

    def _tick(self):
        if not self._running:
            return
        self._i = (self._i + 1) % len(FRAMES)
        self._img.src = self._src(self._i)
        try:
            self._img.update()
        except Exception:
            # control detached while a tick was in flight
            self.stop()
            return
        self._timer = threading.Timer(self.interval, self._tick)
        self._timer.daemon = True
        self._timer.start()


# ------------------------------------------------------------------ demo

def main(page: ft.Page):
    page.title = "Fragmentless"
    page.bgcolor = "#0E0E10"
    page.horizontal_alignment = ft.CrossAxisAlignment.CENTER
    page.vertical_alignment = ft.MainAxisAlignment.CENTER

    logo = FragmentlessLogo(size=200, color="orange")

    def swap(e):
        nxt = "blue" if logo.color_name == "orange" else "orange"
        logo.set_color(nxt)
        label.value = nxt
        label.color = PALETTE[nxt]
        label.update()

    label = ft.Text("orange", color=PALETTE["orange"], size=13)

    page.add(
        ft.Column(
            [logo, label, ft.TextButton("cambiar color", on_click=swap)],
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            spacing=18,
        )
    )


if __name__ == "__main__":
    ft.app(main, assets_dir=".")
