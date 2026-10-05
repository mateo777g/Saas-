import flet as ft

class Sidebar(ft.Container):
    def __init__(self, router):
        super().__init__()
        self.router = router
        self.width = 330
        self.height = float("inf")
        self.bgcolor = "#0d0905"
        self.padding = 24
        
        # Enlace directo a WhatsApp (reemplaza con tu número)
        numero_whatsapp = "+52 1 272 366 2604"
        url_wa = f"https://wa.me/{numero_whatsapp}"

        self.content = ft.Column(
            [
                # --- SECCIÓN SUPERIOR: Logo y Navegación ---
                ft.Column(
                    [
                        ft.Row(
                            [
                                ft.CircleAvatar(
                                    foreground_image_src="assets/logomonky.png",
                                    radius=26,
                                    bgcolor=ft.Colors.TRANSPARENT
                                ),
                                ft.Column(
                                    [
                                        ft.Text("Taku monky", color=ft.Colors.WHITE, weight="bold", size=19, font_family="Georgia", italic=True),
                                        ft.Text("PANEL DEL DUEÑO", color="#f4ca83", size=10, weight="bold")
                                    ],
                                    spacing=1
                                )
                            ],
                            spacing=14
                        ),
                        ft.Divider(height=35, color="#1c1610"),
                        
                        self._crear_boton_menu("Inicio", ft.Icons.GRID_VIEW_ROUNDED, "home"),
                        self._crear_boton_menu("Mi menú", ft.Icons.REORDER_ROUNDED, "menu"),
                        self._crear_boton_menu("Mesas", ft.Icons.TABLE_RESTAURANT_OUTLINED, "mesas"),
                        self._crear_boton_menu("Agente IA", ft.Icons.SMART_TOY_OUTLINED, "agente_financiero", tiene_ia=True),
                        self._crear_boton_menu("Crear contenido", ft.Icons.AUTO_AWESOME, "contenido"),
                        self._crear_boton_menu("Mi biblioteca", ft.Icons.DASHBOARD_CUSTOMIZE_OUTLINED, "biblioteca"),
                        self._crear_boton_menu("Ajustes", ft.Icons.SETTINGS_OUTLINED, "ajustes"),
                    ],
                    spacing=8
                ),

                # Espaciador que empuja la tarjeta de ayuda al fondo
                ft.Container(expand=True),

                # --- SECCIÓN INFERIOR: Tarjeta de Soporte ---
                ft.Container(
                    bgcolor="#18120b",
                    border=ft.Border.all(1, "#2c2013"),
                    border_radius=16,
                    padding=18,
                    content=ft.Column(
                        [
                            ft.Text(
                                "¿Necesitas ayuda?",
                                color="#f4ca83",
                                size=16,
                                weight="bold",
                                font_family="Georgia",
                                italic=True
                            ),
                            ft.Text(
                                "Te respondemos en WhatsApp en menos de una hora.",
                                color="#999288",
                                size=12
                            ),
                            ft.Container(height=4),
                            ft.OutlinedButton(
                                content=ft.Text("Abrir WhatsApp", color="#f4ca83", weight="bold", size=13),
                                style=ft.ButtonStyle(
                                    side=ft.BorderSide(1, "#f4ca83"),
                                    shape=ft.RoundedRectangleBorder(radius=20),
                                    padding=ft.Padding.symmetric(vertical=12)
                                ),
                                width=float("inf"),
                                on_click=lambda _: self.router.page.launch_url(url_wa)
                            )
                        ],
                        spacing=6
                    )
                )
            ],
            expand=True
        )

    def _crear_boton_menu(self, texto: str, icono: str, ruta: str, tiene_ia: bool = False):
        activo = self.router.vista_actual == ruta
        
        color_texto = "#f4ca83" if activo else "#66625d"
        bg_color = "#211a11" if activo else ft.Colors.TRANSPARENT
        
        elementos = [
            ft.Icon(icono, color=color_texto, size=20),
            ft.Text(texto, color=color_texto, size=15, weight="w600" if activo else "normal", expand=True)
        ]
        
        if tiene_ia:
            elementos.append(
                ft.Container(
                    content=ft.Text("IA", color="#0d0905", size=10, weight="bold"),
                    bgcolor="#f4ca83",
                    padding=ft.Padding.symmetric(horizontal=8, vertical=3),
                    border_radius=10
                )
            )

        return ft.Container(
            content=ft.Row(elementos, spacing=14),
            bgcolor=bg_color,
            padding=ft.Padding.symmetric(horizontal=16, vertical=12),
            border_radius=22,
            ink=True,
            on_click=lambda _: self.router.cambiar_vista(ruta)
        )
