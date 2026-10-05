"""
views/home_view.py
Inicio con el diseño manchas + vidrio (29/09), SIN el fondo de manchas (es exclusivo del Agente
IA): la vista pinta su propio suelo (D.suelo) y MainController lo sube detrás de la barra. Las
reglas están en planes/plan panel.txt ("DISEÑO MANCHAS + VIDRIO"); la maqueta aprobada, en
https://claude.ai/artifact/1FWmGuBQ5hqeKU8ddtqgqg.

Encima del suelo:
- Barra de arriba (vidrio): "Inicio", chip "en vivo", hora de la última lectura, Actualizar,
  Crear contenido y Nuevo platillo.
- Tarjeta grande (vidrio): la fecha y el saludo (los no negociables de esta vista) y cuatro
  cifras: vendido hoy, mesas abiertas, platillos en venta y contenido del mes.
- "Mesas ahora": las mesas del catálogo, ocupadas primero, con lo que llevan.
- Abajo: los atajos de "¿Qué hacemos hoy?", "Lo más vendido" (Hoy/Semana/Mes) y "Lo último de
  tu menú".

Todas las cifras son reales: las de ventas y mesas salen de models/resumen_inicio.py (mismas
reglas que el agente: solo ventas cerradas, día de 6:00 a 6:00), "en venta" de
PlatilloDAO.obtener_estadisticas() (solo visibles) y el contenido de la carpeta biblioteca/.
Cada tarjeta carga y falla por su cuenta.
"""
import asyncio
import datetime
import traceback

import flet as ft

from models import perfil, resumen_inicio
from models.platillo_dao import PlatilloDAO
from models.tiempo import saludo_por_hora
from views.diseno import ALTO_BARRA_SUPERIOR, MARGEN, boton, etiqueta, icono, punto, texto, vidrio
from views.piezas import DIAS, MESES
from views.tema import D, VERDE

MESES_MIN = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
             "septiembre", "octubre", "noviembre", "diciembre"]

# Medidas de la maqueta.
TAMANO_SALUDO = 50
ALTO_FILA_ARRIBA = 372          # tarjeta del saludo y "Mesas ahora"
ALTO_MIN_FILA_ABAJO = 340       # por debajo de esto el cuerpo se desplaza en vez de apretarse
ANCHO_MESAS = 360
TOPE_MESAS = 5                  # renglones de "Mesas ahora"; el resto se cuenta abajo
TOPE_RECIENTES = 3

# El selector de "Lo más vendido": (nombre, clave en resumen_inicio, nota de abajo).
PERIODOS = [
    ("Hoy", "hoy", "Piezas vendidas y total, hoy desde las 6:00."),
    ("Semana", "semana", "Piezas vendidas y total, de lunes a hoy."),
    ("Mes", "mes", "Piezas vendidas y total, en lo que va del mes."),
]

# Los atajos de "¿Qué hacemos hoy?": (icono, título, descripción, vista, cómo llega). "nuevo"
# abre Mi menú con el diálogo de alta; "ocultar", en el modo "Ocultar varios".
ATAJOS = [
    ("crear", "Crear post para Instagram", "Imágenes promocionales automáticas.",
     "contenido", None),
    ("oculto", "Marcar un platillo como agotado", "Se oculta de tu menú.", "menu", "ocultar"),
    ("agregar", "Agregar un producto nuevo", "Con foto, precio y descripción.", "menu", "nuevo"),
    ("ia", "Administrar finanzas con IA", "Analiza y optimiza tu negocio.",
     "agente_financiero", None),
]


def _plural(cantidad, singular, plural):
    return f"{cantidad} {singular if cantidad == 1 else plural}"


def _dinero(valor):
    # Mismo criterio que _formatear_precio() de menu_view.py: sin decimales si es entero.
    numero = float(valor or 0)
    return f"${int(numero):,}" if numero.is_integer() else f"${numero:,.2f}"


def _analizar_fecha(valor):
    if not valor:
        return None
    try:
        return datetime.datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def _tiempo_relativo(valor):
    """'hace 2 horas' / 'ayer' / 'hace 3 días' / 'el 12 de agosto', en hora local."""
    fecha = _analizar_fecha(valor)
    if fecha is None:
        return ""
    fecha_local = fecha.astimezone()
    ahora = datetime.datetime.now().astimezone()
    segundos = (ahora - fecha_local).total_seconds()
    if segundos < 60:
        return "hace un momento"
    if segundos < 3600:
        minutos = int(segundos // 60)
        return "hace 1 minuto" if minutos == 1 else f"hace {minutos} minutos"
    dias = (ahora.date() - fecha_local.date()).days
    if dias <= 0:
        horas = int(segundos // 3600)
        return "hace 1 hora" if horas == 1 else f"hace {horas} horas"
    if dias == 1:
        return "ayer"
    if dias < 7:
        return f"hace {dias} días"
    return f"el {fecha_local.day} de {MESES_MIN[fecha_local.month - 1]}"


def _fecha_hoy():
    hoy = datetime.datetime.now()
    return f"{DIAS[hoy.weekday()]}, {hoy.day} DE {MESES[hoy.month - 1]}"


def _logo_fecha():
    # El logo de trazo grueso junto a la fecha, igual que en el saludo del agente
    # (_logo_saludo de agenteIA_view.py): el SVG llena su caja, se pinta a 3/4 del hueco.
    return ft.Container(width=30, height=30, alignment=ft.Alignment.CENTER,
                        content=ft.Image(src=D.logo_simbolo, width=22, height=22))


def _con_hover(control, al_entrar):
    # Hover sin repintar la vista entera: solo el control que cambió.
    def encima(e):
        al_entrar(e.data in (True, "true"))
        control.update()
    control.on_hover = encima
    return control


def _boton_chico(etiqueta_boton, al_pulsar):
    """El botón chico de las tarjetas ("Administrar mesas", "Ver menú"): secundario, alto 34,
    12.5/600 y flechita."""
    cuerpo = ft.Container(
        height=34, padding=ft.Padding.symmetric(horizontal=12), border_radius=12,
        border=ft.Border.all(1, D.linea), animate_opacity=150, on_click=al_pulsar,
        content=ft.Row([texto(etiqueta_boton, 12.5, 600), icono("derecha", 14)],
                       spacing=6, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER),
    )
    return _con_hover(cuerpo, lambda dentro: setattr(cuerpo, "opacity", 0.86 if dentro else 1))


def _raya_abajo():
    return ft.Border(bottom=ft.BorderSide(1, D.linea))


class HomeView(ft.Container):
    def __init__(self, router):
        super().__init__()
        self.router = router
        self.page_ref = router.page
        self.expand = True
        # El suelo liso del tema: MainController lo sube a toda la ventana, detrás de la barra.
        self.bgcolor = D.suelo

        self._resumen = None        # lo de models/resumen_inicio.leer_ventas()
        self._periodo = 1           # "Semana"
        self._cargando = False

        # El saludo se repinta aquí si se cambia el nombre en Perfil (pie de la barra).
        self.router.pintores_perfil = dict(getattr(router, "pintores_perfil", None) or {},
                                           saludo=self._pintar_saludo)

        # --------------------------------------------------------------
        # Barra de arriba
        # --------------------------------------------------------------
        self.texto_actualizado = texto("", 11, 400, D.tenue, mono=True)
        boton_actualizar = ft.Container(
            width=40, height=40, border_radius=12, border=ft.Border.all(1, D.linea),
            alignment=ft.Alignment.CENTER, content=icono("actualizar", 16),
            tooltip="Actualizar", animate_opacity=150, on_click=self._al_actualizar,
        )
        _con_hover(boton_actualizar,
                   lambda dentro: setattr(boton_actualizar, "opacity", 0.86 if dentro else 1))
        barra_superior = vidrio(
            radio=18, sombra=False,
            top=MARGEN, left=0, right=MARGEN, height=ALTO_BARRA_SUPERIOR,
            padding=ft.Padding.only(left=20, right=12),
            contenido=ft.Row([
                texto("Inicio", 15, 700),
                ft.Container(
                    height=28, border_radius=14, bgcolor=D.chip,
                    padding=ft.Padding.symmetric(horizontal=12),
                    content=ft.Row([punto(VERDE), texto("Ventas y mesas en vivo", 12, 500, D.suave)],
                                   spacing=8, tight=True,
                                   vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ),
                self.texto_actualizado,
                ft.Container(expand=True),
                boton_actualizar,
                boton("Crear contenido", "crear", self._ir("contenido")),
                boton("Nuevo platillo", "mas", self._ir("menu", "nuevo"), principal=True),
            ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

        # --------------------------------------------------------------
        # Tarjeta grande: fecha, saludo y las cuatro cifras
        # --------------------------------------------------------------
        self.saludo = ft.Text(
            spans=[ft.TextSpan(self._primer_renglon()),
                   ft.TextSpan("\nAsí va tu negocio hoy.", ft.TextStyle(color=D.tenue))],
            size=TAMANO_SALUDO, font_family="Jakarta800", color=D.texto,
            style=ft.TextStyle(height=1.04, letter_spacing=-1.25),
        )
        self.cifras = {}
        tarjeta_saludo = vidrio(
            radio=30, expand=True,
            padding=ft.Padding.only(left=36, top=34, right=36, bottom=28),
            contenido=ft.Column([
                ft.Column([
                    ft.Row([_logo_fecha(), etiqueta(_fecha_hoy(), 11.5)],
                           spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
                    self.saludo,
                ], spacing=14),
                ft.Row([
                    self._cifra("vendido", "VENDIDO HOY"),
                    self._cifra("mesas", "MESAS ABIERTAS"),
                    self._cifra("venta", "EN VENTA"),
                    self._cifra("contenido", "CONTENIDO"),
                ], spacing=12),
            ], spacing=0, alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        )

        # --------------------------------------------------------------
        # Mesas ahora
        # --------------------------------------------------------------
        self.etiqueta_ocupadas = etiqueta("")
        self.caja_mesas = ft.Container(
            border_radius=16, border=ft.Border.all(1, D.linea), bgcolor=D.solido,
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS, content=self._cargando_texto(),
        )
        self.nota_mesas = texto("", 12, 500, D.tenue)
        tarjeta_mesas = vidrio(
            radio=22, width=ANCHO_MESAS, padding=20,
            contenido=ft.Column([
                ft.Row([texto("Mesas ahora", 14.5, 700), ft.Container(expand=True),
                        self.etiqueta_ocupadas],
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
                self.caja_mesas,
                ft.Container(expand=True),
                ft.Row([self.nota_mesas, ft.Container(expand=True),
                        _boton_chico("Administrar mesas", self._ir("mesas"))],
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
            ], spacing=14, horizontal_alignment=ft.CrossAxisAlignment.STRETCH),
        )

        # --------------------------------------------------------------
        # Fila de abajo: atajos, lo más vendido y lo último del menú
        # --------------------------------------------------------------
        tarjetas_atajo = [self._tarjeta_atajo(*atajo) for atajo in ATAJOS]
        tarjeta_atajos = vidrio(
            radio=22, expand=12, padding=20,
            contenido=ft.Column([
                etiqueta("¿QUÉ HACEMOS HOY?"),
                ft.Row(tarjetas_atajo[:2], spacing=12, expand=True,
                       vertical_alignment=ft.CrossAxisAlignment.STRETCH),
                ft.Row(tarjetas_atajo[2:], spacing=12, expand=True,
                       vertical_alignment=ft.CrossAxisAlignment.STRETCH),
            ], spacing=12),
        )

        self.selector = ft.Container(padding=3, border_radius=12, bgcolor=D.chip)
        self._pintar_selector()
        self.caja_vendidos = ft.Container(
            expand=True, border_radius=16, border=ft.Border.all(1, D.linea), bgcolor=D.solido,
            padding=ft.Padding.symmetric(horizontal=16, vertical=14),
            content=self._cargando_texto(),
        )
        self.nota_vendidos = texto(PERIODOS[self._periodo][2], 12, 500, D.tenue)
        tarjeta_vendidos = vidrio(
            radio=22, expand=10, padding=20,
            contenido=ft.Column([
                ft.Row([texto("Lo más vendido", 14.5, 700), ft.Container(expand=True),
                        self.selector],
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
                self.caja_vendidos,
                self.nota_vendidos,
            ], spacing=12, horizontal_alignment=ft.CrossAxisAlignment.STRETCH),
        )

        self.caja_recientes = ft.Container(
            expand=True, border_radius=16, border=ft.Border.all(1, D.linea), bgcolor=D.solido,
            clip_behavior=ft.ClipBehavior.ANTI_ALIAS, content=self._cargando_texto(),
        )
        tarjeta_recientes = vidrio(
            radio=22, expand=10, padding=20,
            contenido=ft.Column([
                ft.Row([texto("Lo último de tu menú", 14.5, 700), ft.Container(expand=True),
                        _boton_chico("Ver menú", self._ir("menu"))],
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
                self.caja_recientes,
                texto("Tus últimos cambios en Mi menú.", 12, 500, D.tenue),
            ], spacing=12),
        )

        # --------------------------------------------------------------
        # Cuerpo
        # --------------------------------------------------------------
        self.fila_abajo = ft.Row(
            [tarjeta_atajos, tarjeta_vendidos, tarjeta_recientes],
            spacing=MARGEN, height=404, vertical_alignment=ft.CrossAxisAlignment.STRETCH,
        )
        self.columna = ft.Column([
            ft.Row([tarjeta_saludo, tarjeta_mesas], spacing=MARGEN, height=ALTO_FILA_ARRIBA,
                   vertical_alignment=ft.CrossAxisAlignment.STRETCH),
            self.fila_abajo,
        ], spacing=MARGEN)
        # La fila de abajo llena lo que sobre de la ventana. Solo si no cabe ni con su alto
        # mínimo el cuerpo se desplaza: un Column con scroll recorta las sombras del vidrio.
        # ⚠️ on_size_change va en un Container de adentro: puesto en el que lleva top/left, flet
        # lo envuelve y el Stack ya no lo reconoce como posicionado (la vista salía gris).
        cuerpo = ft.Container(top=ALTO_BARRA_SUPERIOR + MARGEN * 2, left=0, right=MARGEN,
                              bottom=MARGEN,
                              content=ft.Container(content=self.columna,
                                                   on_size_change=self._al_cambiar_tamano))
        self.content = ft.Stack([barra_superior, cuerpo], expand=True)

    def did_mount(self):
        self.page_ref.run_task(self._cargar)

    # ------------------------------------------------------------------
    # Piezas
    # ------------------------------------------------------------------
    def _ir(self, ruta, como=None):
        return lambda _: self.router.cambiar_vista(ruta, abrir_dialogo_nuevo=como == "nuevo",
                                                   ocultar_varios=como == "ocultar")

    @staticmethod
    def _cargando_texto():
        return ft.Container(padding=14, content=texto("Cargando…", 13, 500, D.tenue))

    def _primer_renglon(self):
        return f"{saludo_por_hora(datetime.datetime.now().hour)}, {perfil.como_llamarte()}."

    def _pintar_saludo(self):
        try:
            self.saludo.spans[0].text = self._primer_renglon()
            self.saludo.update()
        except RuntimeError:
            pass    # Inicio ya no está en pantalla

    def _cifra(self, clave, titulo):
        valor = texto("—", 26, 800, espaciado=-0.5, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)
        nota = texto("Cargando…", 12.5, 500, D.suave, max_lines=1,
                     overflow=ft.TextOverflow.ELLIPSIS)
        self.cifras[clave] = (valor, nota)
        return ft.Container(
            expand=1, padding=16, border_radius=18, bgcolor=D.solido,
            border=ft.Border.all(1, D.linea),
            content=ft.Column([etiqueta(titulo), valor, nota], spacing=6, tight=True),
        )

    def _poner_cifra(self, clave, valor, nota):
        self.cifras[clave][0].value = valor
        self.cifras[clave][1].value = nota

    def _tarjeta_atajo(self, nombre_icono, titulo, descripcion, ruta, como):
        """Como las ideas del agente: icono arriba y flechita que sale con el cursor encima
        (junto con el borde oscuro); título y descripción abajo. Toda la tarjeta es el botón."""
        flecha = ft.Container(content=icono("derecha", 16, D.tenue), opacity=0,
                              animate_opacity=ft.Animation(150, ft.AnimationCurve.EASE_OUT))
        tarjeta = ft.Container(
            expand=1, padding=16, border_radius=18, bgcolor=D.solido,
            border=ft.Border.all(1, D.linea),
            animate=ft.Animation(150, ft.AnimationCurve.EASE_OUT),
            on_click=self._ir(ruta, como),
            content=ft.Column([
                ft.Row([
                    ft.Container(width=36, height=36, border_radius=11, bgcolor=D.chip,
                                 alignment=ft.Alignment.CENTER, content=icono(nombre_icono, 18)),
                    ft.Container(expand=True),
                    flecha,
                ], vertical_alignment=ft.CrossAxisAlignment.CENTER),
                ft.Column([
                    texto(titulo, 14.5, 700),
                    texto(descripcion, 12.5, 500, D.suave, alto=1.45),
                ], spacing=4, tight=True),
            ], spacing=12, alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        )

        def encender(dentro):
            tarjeta.border = ft.Border.all(1, D.suave if dentro else D.linea)
            flecha.opacity = 1 if dentro else 0
        return _con_hover(tarjeta, encender)

    def _pintar_selector(self):
        segmentos = []
        for i, (nombre, _, _) in enumerate(PERIODOS):
            elegido = i == self._periodo
            segmentos.append(ft.Container(
                height=26, padding=ft.Padding.symmetric(horizontal=10), border_radius=9,
                alignment=ft.Alignment.CENTER,
                bgcolor=D.solido if elegido else None,
                shadow=ft.BoxShadow(blur_radius=3, color="#26000000", offset=ft.Offset(0, 1))
                if elegido else None,
                content=texto(nombre, 12, 600, D.texto if elegido else D.suave),
                on_click=lambda e, i=i: self._elegir_periodo(i),
            ))
        self.selector.content = ft.Row(segmentos, spacing=2, tight=True)

    def _elegir_periodo(self, i):
        if i == self._periodo:
            return
        self._periodo = i
        self._pintar_selector()
        self.nota_vendidos.value = PERIODOS[i][2]
        if self._resumen is not None:
            self._pintar_vendidos()
        self._actualizar(self.selector, self.nota_vendidos, self.caja_vendidos)

    def _al_cambiar_tamano(self, e):
        alto_libre = int(e.height) - ALTO_FILA_ARRIBA - MARGEN
        alto = max(ALTO_MIN_FILA_ABAJO, alto_libre)
        desplazar = ft.ScrollMode.AUTO if alto_libre < ALTO_MIN_FILA_ABAJO else None
        if alto != self.fila_abajo.height or desplazar != self.columna.scroll:
            self.fila_abajo.height = alto
            self.columna.scroll = desplazar
            self._actualizar(self.columna)

    def _actualizar(self, *controles):
        try:
            for c in controles:
                c.update()
        except RuntimeError:
            pass    # se salió de Inicio antes de que llegaran los datos

    # ------------------------------------------------------------------
    # Carga de datos (cada tarjeta por su cuenta)
    # ------------------------------------------------------------------
    def _al_actualizar(self, _):
        if not self._cargando:
            self.page_ref.run_task(self._cargar)

    async def _cargar(self):
        self._cargando = True
        try:
            # Una tras otra, no en paralelo: el cliente de Supabase es uno solo (síncrono) y dos
            # hilos usándolo a la vez tronaban con WinError 10035. Cada tarjeta se pinta al
            # llegar lo suyo.
            await self._cargar_recientes()
            await self._cargar_estadisticas()
            await self._cargar_contenido()
            await self._cargar_ventas()
            self.texto_actualizado.value = f"Actualizado {datetime.datetime.now():%H:%M}"
            self._actualizar(self.texto_actualizado)
        finally:
            self._cargando = False

    async def _cargar_ventas(self):
        try:
            resumen = await asyncio.to_thread(resumen_inicio.leer_ventas)
        except Exception:
            traceback.print_exc()
            self._resumen = None
            self._poner_cifra("vendido", "—", "No se pudo cargar.")
            self._poner_cifra("mesas", "—", "No se pudo cargar.")
            self.etiqueta_ocupadas.value = ""
            self.nota_mesas.value = ""
            self.caja_mesas.content = self._mensaje("No se pudieron cargar las mesas.")
            self.caja_vendidos.content = self._mensaje("No se pudieron cargar las ventas.", 0)
        else:
            self._resumen = resumen
            self._poner_cifra(
                "vendido", _dinero(resumen["vendido_hoy"]),
                _plural(resumen["ventas_hoy"], "venta cerrada", "ventas cerradas")
                if resumen["ventas_hoy"] else "Aún sin ventas cerradas")
            self._poner_cifra(
                "mesas", str(resumen["abiertas"]),
                f"{_dinero(resumen['por_cobrar'])} por cobrar"
                if resumen["abiertas"] else "Ninguna cuenta abierta")
            self._pintar_mesas()
            self._pintar_vendidos()
        valor, nota = self.cifras["vendido"]
        valor_m, nota_m = self.cifras["mesas"]
        self._actualizar(valor, nota, valor_m, nota_m, self.etiqueta_ocupadas, self.nota_mesas,
                         self.caja_mesas, self.caja_vendidos)

    async def _cargar_estadisticas(self):
        try:
            stats = await asyncio.to_thread(PlatilloDAO.obtener_estadisticas)
        except Exception:
            traceback.print_exc()
            self._poner_cifra("venta", "—", "No se pudo cargar.")
        else:
            self._poner_cifra("venta", _plural(stats["total"], "platillo", "platillos"),
                              _plural(stats["categorias_en_uso"], "categoría", "categorías"))
        self._actualizar(*self.cifras["venta"])

    async def _cargar_contenido(self):
        try:
            cuantos = await asyncio.to_thread(resumen_inicio.contar_anuncios_del_mes)
        except Exception:
            traceback.print_exc()
            self._poner_cifra("contenido", "—", "No se pudo leer la biblioteca.")
        else:
            self._poner_cifra("contenido", _plural(cuantos, "post", "posts"),
                              "Este mes, en tu biblioteca")
        self._actualizar(*self.cifras["contenido"])

    async def _cargar_recientes(self):
        try:
            recientes = await asyncio.to_thread(PlatilloDAO.obtener_recientes, TOPE_RECIENTES)
        except Exception:
            traceback.print_exc()
            self.caja_recientes.content = self._mensaje(
                "No se pudieron cargar los últimos movimientos.")
        else:
            if not recientes:
                self.caja_recientes.content = self._mensaje(
                    "Todavía no hay movimientos registrados en tu menú.")
            else:
                ultimo = len(recientes) - 1
                self.caja_recientes.content = ft.Column(
                    [self._fila_reciente(p, i < ultimo) for i, p in enumerate(recientes)],
                    spacing=0)
        self._actualizar(self.caja_recientes)

    # ------------------------------------------------------------------
    # Pintado de las tarjetas
    # ------------------------------------------------------------------
    @staticmethod
    def _mensaje(valor, padding=14):
        return ft.Container(padding=padding,
                            content=texto(valor, 13, 500, D.suave, alto=1.45))

    def _pintar_mesas(self):
        mesas = self._resumen["mesas"]
        if not mesas:
            self.etiqueta_ocupadas.value = ""
            self.nota_mesas.value = ""
            self.caja_mesas.content = self._mensaje(
                "Todavía no tienes mesas. Agrégalas en Mesas.")
            return
        # Las ocupadas primero; dentro de cada grupo, el orden del catálogo.
        ordenadas = [m for m in mesas if m["ocupada"]] + [m for m in mesas if not m["ocupada"]]
        visibles = ordenadas[:TOPE_MESAS]
        ocupadas = sum(1 for m in mesas if m["ocupada"])
        self.etiqueta_ocupadas.value = f"{ocupadas} DE {len(mesas)} OCUPADA{'' if ocupadas == 1 else 'S'}"
        restantes = len(ordenadas) - len(visibles)
        self.nota_mesas.value = (f"y {_plural(restantes, 'mesa más', 'mesas más')}"
                                 if restantes else "")
        ultimo = len(visibles) - 1
        self.caja_mesas.content = ft.Column(
            [self._fila_mesa(m, i < ultimo) for i, m in enumerate(visibles)], spacing=0)

    def _fila_mesa(self, mesa, con_raya):
        if mesa["ocupada"]:
            marca = punto(D.tinta, 8)
            estado = texto("Ocupada", 12.5, 500, D.suave)
            monto = texto(_dinero(mesa["total"]), 12.5, 500, D.texto, mono=True,
                          text_align=ft.TextAlign.RIGHT)
        else:
            marca = ft.Container(width=8, height=8, border_radius=4,
                                 border=ft.Border.all(1.5, D.tenue))
            estado = texto("Disponible", 12.5, 500, D.tenue)
            monto = texto("—", 12.5, 400, D.tenue, mono=True, text_align=ft.TextAlign.RIGHT)
        return ft.Container(
            height=44, padding=ft.Padding.symmetric(horizontal=14),
            border=_raya_abajo() if con_raya else None,
            content=ft.Row([
                marca,
                texto(mesa["nombre"], 13.5, 600, expand=True, max_lines=1,
                      overflow=ft.TextOverflow.ELLIPSIS),
                estado,
                ft.Container(width=64, alignment=ft.Alignment.CENTER_RIGHT, content=monto),
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )

    def _pintar_vendidos(self):
        productos = self._resumen["mas_vendido"][PERIODOS[self._periodo][1]]
        if not productos:
            self.caja_vendidos.content = self._mensaje(
                "Sin ventas cerradas en este periodo.", 0)
            return
        tope = max(p["unidades"] for p in productos)
        self.caja_vendidos.content = ft.Column(
            [self._fila_vendido(i, p, tope) for i, p in enumerate(productos)], spacing=14)

    @staticmethod
    def _fila_vendido(i, producto, tope):
        lleno = max(1, round(producto["unidades"] / tope * 100))
        partes = [ft.Container(expand=lleno, bgcolor=D.tinta, border_radius=3)]
        if lleno < 100:
            partes.append(ft.Container(expand=100 - lleno))
        return ft.Column([
            ft.Row([
                texto(f"{i + 1:02d}", 11, 400, D.tenue, mono=True),
                texto(producto["nombre"], 13.5, 600, expand=True, max_lines=1,
                      overflow=ft.TextOverflow.ELLIPSIS),
                texto(f"{producto['unidades']} · {_dinero(producto['importe'])}", 12, 400,
                      D.suave, mono=True),
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            ft.Container(height=5, border_radius=3, bgcolor=D.chip,
                         content=ft.Row(partes, spacing=0)),
        ], spacing=7, tight=True)

    @staticmethod
    def _fila_reciente(platillo, con_raya):
        es_nuevo = platillo.get("created_at") == platillo.get("updated_at")
        # Sin foto: la imagen negra de siempre (assets/sin-foto.png), igual que Mi menú.
        foto = platillo.get("image_url") or "assets/sin-foto.png"
        insignia = ft.Container(
            border_radius=6, padding=ft.Padding.symmetric(horizontal=8, vertical=4),
            bgcolor=D.tinta if es_nuevo else D.chip,
            content=texto("NUEVO" if es_nuevo else "EDITADO", 10.5, 400,
                          D.sobre_tinta if es_nuevo else D.suave, mono=True, espaciado=0.4),
        )
        return ft.Container(
            expand=True, padding=ft.Padding.symmetric(horizontal=14, vertical=8),
            border=_raya_abajo() if con_raya else None,
            content=ft.Row([
                ft.Container(width=44, height=44, border_radius=11, bgcolor="#000000",
                             clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
                             content=ft.Image(src=foto, width=44, height=44, fit=ft.BoxFit.COVER)),
                ft.Column([
                    texto(platillo.get("nombre") or "", 13.5, 700, max_lines=1,
                          overflow=ft.TextOverflow.ELLIPSIS),
                    texto(_tiempo_relativo(platillo.get("updated_at")), 12, 500, D.tenue),
                ], spacing=3, tight=True, expand=True),
                insignia,
            ], spacing=12, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        )
