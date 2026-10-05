import json, os, datetime

RAIZ = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(RAIZ, "project")
os.makedirs(P, exist_ok=True)

LOGO = "/_blob/046960f4c783273481b143d1efbb6d4b"
TEMAS = {
    "claro": dict(
        dither="/_blob/6866293fc1d145d8dcfb7c6a279c1df3", ground="#fafaf8",
        glass="rgba(255,255,255,0.80)", glass_line="rgba(0,0,0,0.08)", solid="#ffffff",
        text="#0b0b0b", muted="#5f5f5a", faint="#8b8b85", line="rgba(0,0,0,0.09)",
        chip="rgba(0,0,0,0.045)", ink="#0b0b0b", on_ink="#ffffff", shadow="0 24px 60px rgba(0,0,0,0.18)",
        user_bg="#0b0b0b", user_text="#ffffff"),
    "oscuro": dict(
        dither="/_blob/468337459f046ada60b1eaa3c3192cc3", ground="#161616",
        glass="rgba(14,14,14,0.78)", glass_line="rgba(255,255,255,0.09)", solid="#1b1b1b",
        text="#f5f5f2", muted="#a6a6a0", faint="#7c7c77", line="rgba(255,255,255,0.10)",
        chip="rgba(255,255,255,0.06)", ink="#f5f5f2", on_ink="#0b0b0b", shadow="0 24px 60px rgba(0,0,0,0.55)",
        user_bg="#f5f5f2", user_text="#0b0b0b"),
}
ACENTO = "#E8622A"
OK = "#3f9b5a"

def ico(d, s=18, w=1.7):
    return (f'<svg width="{s}" height="{s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{d}</svg>')

I = dict(
    inicio='<rect x="3" y="3" width="7" height="7" rx="1.5"></rect><rect x="14" y="3" width="7" height="7" rx="1.5"></rect><rect x="3" y="14" width="7" height="7" rx="1.5"></rect><rect x="14" y="14" width="7" height="7" rx="1.5"></rect>',
    menu='<path d="M8 6h13"></path><path d="M8 12h13"></path><path d="M8 18h13"></path><circle cx="4" cy="6" r="1"></circle><circle cx="4" cy="12" r="1"></circle><circle cx="4" cy="18" r="1"></circle>',
    mesas='<path d="M3 9h18"></path><path d="M5 9v10"></path><path d="M19 9v10"></path><path d="M8 5h8"></path>',
    ia='<path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"></path><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"></path>',
    crear='<path d="M12 20h9"></path><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"></path>',
    biblio='<rect x="3" y="3" width="18" height="18" rx="2"></rect><circle cx="9" cy="9" r="2"></circle><path d="M21 15l-5-5L5 21"></path>',
    ayuda='<circle cx="12" cy="12" r="9"></circle><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"></path><path d="M12 17h.01"></path>',
    ajustes='<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"></path>',
    salir='<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><path d="M16 17l5-5-5-5"></path><path d="M21 12H9"></path>',
    flecha='<path d="M12 19V5"></path><path d="M5 12l7-7 7 7"></path>',
    derecha='<path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path>',
    hoy='<rect x="3" y="4" width="18" height="17" rx="2"></rect><path d="M16 2v4"></path><path d="M8 2v4"></path><path d="M3 10h18"></path><rect x="7" y="13" width="4" height="4" rx="0.5"></rect>',
    semana='<path d="M3 3v18h18"></path><path d="M7 15l4-4 3 3 5-6"></path>',
    mes='<rect x="3" y="3" width="18" height="18" rx="2"></rect><path d="M8 17v-5"></path><path d="M12 17V8"></path><path d="M16 17v-3"></path>',
    historial='<path d="M3 12a9 9 0 1 0 3-6.7L3 8"></path><path d="M3 3v5h5"></path><path d="M12 7v5l3 2"></path>',
    mas='<path d="M12 5v14"></path><path d="M5 12h14"></path>',
    copiar='<rect x="9" y="9" width="12" height="12" rx="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>',
    datos='<ellipse cx="12" cy="5" rx="8" ry="3"></ellipse><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5"></path><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"></path>',
    candado='<rect x="4" y="11" width="16" height="10" rx="2"></rect><path d="M8 11V7a4 4 0 0 1 8 0v4"></path>',
)

def head(titulo, t):
    return f'''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>{titulo}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&amp;family=JetBrains+Mono:wght@400;500&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0;background:{t['ground']};font-family:"Plus Jakarta Sans",system-ui,sans-serif;color:{t['text']}}}
.dither{{image-rendering:pixelated}}
.glass{{backdrop-filter:blur(18px) saturate(1.1);-webkit-backdrop-filter:blur(18px) saturate(1.1)}}
.mono{{font-family:"JetBrains Mono",ui-monospace,monospace}}
button{{font-family:inherit;cursor:pointer}}
a{{color:{t['text']}}}a:hover{{color:{ACENTO}}}
</style>
</helmet>
'''

def foot(w, h):
    props = json.dumps({"$preview": {"width": w, "height": h}})
    return f'''</x-dc>
<script type="text/x-dc" data-dc-script data-props='{props}'>
class Component extends DCLogic {{
renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''

def barra(t, activa="ia"):
    def item(k, texto, badge=None):
        on = k == activa
        bg = t['ink'] if on else "transparent"
        col = t['on_ink'] if on else t['muted']
        b = ""
        if badge:
            b = (f'<span class="mono" style="margin-left: auto; font-size: 10px; padding: 3px 7px; border-radius: 6px; '
                 f'background: {ACENTO}; color: #ffffff; letter-spacing: 0.04em">{badge}</span>')
        return (f'<a href="#" style="display: flex; align-items: center; gap: 12px; height: 42px; padding: 0 14px; '
                f'border-radius: 12px; background: {bg}; color: {col}; text-decoration: none; font-size: 14px; '
                f'font-weight: {600 if on else 500}">{ico(I[k])}<span>{texto}</span>{b}</a>')
    def grupo(texto):
        return (f'<div class="mono" style="font-size: 10.5px; letter-spacing: 0.14em; color: {t["faint"]}; '
                f'padding: 14px 14px 6px">{texto}</div>')
    return f'''<nav aria-label="Menú del panel" class="glass" style="position: absolute; left: 16px; top: 16px; bottom: 16px; width: 244px; box-sizing: border-box; padding: 18px 12px 14px; display: flex; flex-direction: column; background: {t['glass']}; border: 1px solid {t['glass_line']}; border-radius: 22px; box-shadow: {t['shadow']}">
<div style="display: flex; align-items: center; gap: 12px; padding: 0 6px 18px">
<div style="width: 40px; height: 40px; border-radius: 12px; background: #0b0b0b; display: flex; align-items: center; justify-content: center">
<img src="{LOGO}" alt="" style="width: 26px; height: 26px">
</div>
<div style="display: flex; flex-direction: column; gap: 2px">
<div style="font-size: 15px; font-weight: 800; letter-spacing: 0.02em">FRAGMENTLESS</div>
<div class="mono" style="font-size: 10.5px; color: {t['faint']}">Plan Básico</div>
</div>
</div>
<div style="display: flex; flex-direction: column; gap: 2px">
{item("inicio", "Inicio")}
{grupo("GENERAL")}
{item("menu", "Mi menú")}
{item("mesas", "Mesas")}
{item("ia", "Agente IA", "IA")}
{item("crear", "Crear contenido")}
{item("biblio", "Mi biblioteca")}
</div>
<div style="flex-grow: 1"></div>
<div style="display: flex; flex-direction: column; gap: 2px">
{item("ayuda", "Ayuda")}
{item("ajustes", "Ajustes")}
{item("salir", "Cerrar sesión")}
</div>
<div style="margin-top: 12px; padding: 12px 8px 0; border-top: 1px solid {t['line']}; display: flex; align-items: center; gap: 10px">
<div style="width: 34px; height: 34px; border-radius: 17px; background: {t['chip']}; border: 1px solid {t['line']}; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 13px">W</div>
<div style="display: flex; flex-direction: column; gap: 1px">
<div style="font-size: 13px; font-weight: 700">Wilson</div>
<div class="mono" style="font-size: 10.5px; color: {t['faint']}">Básico</div>
</div>
</div>
</nav>'''

def barra_superior(t, titulo, sub):
    return f'''<header class="glass" style="position: absolute; left: 276px; right: 16px; top: 16px; height: 60px; box-sizing: border-box; padding: 0 12px 0 20px; display: flex; align-items: center; gap: 14px; background: {t['glass']}; border: 1px solid {t['glass_line']}; border-radius: 18px">
<div style="font-size: 15px; font-weight: 700">{titulo}</div>
<div style="display: flex; align-items: center; gap: 8px; height: 28px; padding: 0 12px; border-radius: 14px; background: {t['chip']}; font-size: 12px; color: {t['muted']}">
<span style="width: 7px; height: 7px; border-radius: 4px; background: {OK}"></span>{sub}</div>
<div style="flex-grow: 1"></div>
<button type="button" style="display: flex; align-items: center; gap: 8px; height: 40px; padding: 0 14px; border-radius: 12px; border: 1px solid {t['line']}; background: transparent; color: {t['text']}; font-size: 13px; font-weight: 600">{ico(I['historial'], 16)}Historial</button>
<button type="button" style="display: flex; align-items: center; gap: 8px; height: 40px; padding: 0 16px; border-radius: 12px; border: 0; background: {t['ink']}; color: {t['on_ink']}; font-size: 13px; font-weight: 600">{ico(I['mas'], 16, 2)}Nueva conversación</button>
</header>'''

def fondo(t):
    return (f'<img class="dither" src="{t["dither"]}" alt="" style="position: absolute; left: 0; top: 0; '
            f'width: 100%; height: 100%; object-fit: cover">')

def compositor(t, chat=False):
    seg = "".join(
        f'<button type="button" style="height: 30px; padding: 0 12px; border-radius: 9px; border: 0; font-size: 12.5px; '
        f'font-weight: 600; background: {t["solid"] if i == 0 else "transparent"}; color: {t["text"] if i == 0 else t["muted"]}; '
        f'box-shadow: {"0 1px 3px rgba(0,0,0,0.15)" if i == 0 else "none"}">{p}</button>'
        for i, p in enumerate(["Hoy", "Semana", "Mes"]))
    ph = "Pregunta lo que quieras de tu negocio…" if not chat else "Sigue preguntando… por ejemplo, ¿y ayer?"
    return f'''<div style="position: relative; background: {t['solid']}; border: 1px solid {t['line']}; border-radius: 22px; box-shadow: 0 10px 30px rgba(0,0,0,0.10); padding: 16px 16px 12px 20px; display: flex; flex-direction: column; gap: {10 if chat else 18}px">
<label for="pregunta{'-chat' if chat else ''}" style="position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0)">Tu pregunta</label>
<textarea id="pregunta{'-chat' if chat else ''}" rows="{1 if chat else 2}" placeholder="{ph}" style="resize: none; border: 0; outline: none; background: transparent; color: {t['text']}; font-family: inherit; font-size: 16px; line-height: 1.5"></textarea>
<div style="display: flex; align-items: center; gap: 10px">
<div role="group" aria-label="Periodo" style="display: flex; gap: 2px; padding: 3px; border-radius: 12px; background: {t['chip']}">{seg}</div>
<span class="mono" style="font-size: 11px; color: {t['faint']}">Enter envía · Shift+Enter salto</span>
<div style="flex-grow: 1"></div>
<button type="button" aria-label="Enviar" style="width: 44px; height: 44px; border-radius: 14px; border: 0; background: {ACENTO}; color: #ffffff; display: flex; align-items: center; justify-content: center">{ico(I['flecha'], 20, 2.2)}</button>
</div>
</div>'''

def idea(t, k, titulo, desc):
    return f'''<button type="button" style="text-align: left; display: flex; flex-direction: column; gap: 14px; padding: 16px; border-radius: 18px; border: 1px solid {t['line']}; background: {t['solid']}; color: {t['text']}">
<div style="display: flex; align-items: center; justify-content: space-between; width: 100%">
<div style="width: 36px; height: 36px; border-radius: 11px; background: {t['chip']}; display: flex; align-items: center; justify-content: center">{ico(I[k], 18)}</div>
<span style="color: {t['faint']}">{ico(I['derecha'], 16)}</span>
</div>
<div style="display: flex; flex-direction: column; gap: 4px">
<div style="font-size: 14.5px; font-weight: 700">{titulo}</div>
<div style="font-size: 12.5px; line-height: 1.45; color: {t['muted']}">{desc}</div>
</div>
</button>'''

def bienvenida(nombre_tema):
    t = TEMAS[nombre_tema]
    return head("Agente IA — bienvenida", t) + f'''<div style="position: relative; width: 1440px; height: 900px; overflow: hidden; background: {t['ground']}">
{fondo(t)}
{barra(t)}
{barra_superior(t, "Agente IA", "Leyendo tus ventas en vivo")}
<main style="position: absolute; left: 276px; right: 16px; top: 92px; bottom: 16px; display: flex; align-items: center; justify-content: center">
<section class="glass" style="width: 780px; box-sizing: border-box; padding: 40px 40px 28px; display: flex; flex-direction: column; gap: 28px; background: {t['glass']}; border: 1px solid {t['glass_line']}; border-radius: 30px; box-shadow: {t['shadow']}">
<div style="display: flex; flex-direction: column; gap: 14px">
<div style="display: flex; align-items: center; gap: 10px">
<img src="{LOGO}" alt="" style="width: 30px; height: 30px">
<span class="mono" style="font-size: 11.5px; letter-spacing: 0.14em; color: {t['faint']}">DOMINGO, 28 DE SEPTIEMBRE</span>
</div>
<h1 style="margin: 0; font-size: 50px; line-height: 1.04; font-weight: 800; letter-spacing: -0.025em">Buenas tardes, Wilson.<br><span style="color: {t['faint']}">¿Qué revisamos hoy?</span></h1>
</div>
{compositor(t)}
<div style="display: flex; flex-direction: column; gap: 12px">
<div class="mono" style="font-size: 10.5px; letter-spacing: 0.14em; color: {t['faint']}">IDEAS PARA TI</div>
<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px">
{idea(t, "hoy", "Qué se vendió hoy", "Por producto, con el total al final.")}
{idea(t, "semana", "Reporte de la semana", "Lunes a hoy, producto por producto.")}
{idea(t, "mes", "Reporte del mes", "Lo que más dejó este mes.")}
</div>
</div>
<div style="display: flex; align-items: center; gap: 8px; font-size: 12px; color: {t['faint']}">{ico(I['candado'], 14)}Solo responde sobre tu negocio. Las cifras salen de tus ventas cerradas.</div>
</section>
</main>
</div>
''' + foot(1440, 900)

def conversacion():
    t = TEMAS["claro"]
    filas = [("Tacos al pastor", "[cant.]", "$[monto]"), ("Gringa", "[cant.]", "$[monto]"),
             ("Quesadilla", "[cant.]", "$[monto]"), ("Horchata", "[cant.]", "$[monto]")]
    tr = "".join(
        f'<tr><td style="padding: 11px 14px; border-top: 1px solid {t["line"]}">{a}</td>'
        f'<td class="mono" style="padding: 11px 14px; border-top: 1px solid {t["line"]}; text-align: right; color: {t["muted"]}">{b}</td>'
        f'<td class="mono" style="padding: 11px 14px; border-top: 1px solid {t["line"]}; text-align: right">{c}</td></tr>'
        for a, b, c in filas)
    fuente = lambda k, txt: (f'<div style="display: flex; align-items: center; gap: 10px; font-size: 13px">'
                             f'<span style="color: {t["faint"]}">{ico(I[k], 16)}</span>{txt}</div>')
    return head("Agente IA — conversación", t) + f'''<div style="position: relative; width: 1440px; height: 900px; overflow: hidden; background: {t['ground']}">
{fondo(t)}
{barra(t)}
{barra_superior(t, "Ventas de hoy por producto", "Leyendo tus ventas en vivo")}
<main class="glass" style="position: absolute; left: 276px; top: 92px; bottom: 16px; width: 812px; box-sizing: border-box; display: flex; flex-direction: column; background: {t['glass']}; border: 1px solid {t['glass_line']}; border-radius: 26px; box-shadow: {t['shadow']}">
<div style="flex-grow: 1; overflow: hidden; padding: 32px 40px 16px; display: flex; flex-direction: column; gap: 26px">
<div style="align-self: flex-end; max-width: 460px; padding: 12px 18px; border-radius: 18px 18px 6px 18px; background: {t['user_bg']}; color: {t['user_text']}; font-size: 14.5px; line-height: 1.5">¿Qué se vendió hoy?</div>
<div style="display: flex; gap: 14px">
<img src="{LOGO}" alt="" style="width: 28px; height: 28px; margin-top: 2px">
<div style="flex-grow: 1; display: flex; flex-direction: column; gap: 14px">
<div style="font-size: 16px; line-height: 1.6">Hoy llevas <b>[n] ventas cerradas</b>. Esto es lo que salió, de lo que más dejó a lo que menos:</div>
<div style="border: 1px solid {t['line']}; border-radius: 16px; overflow: hidden; background: {t['solid']}">
<table style="width: 100%; border-collapse: collapse; font-size: 14px">
<thead><tr style="background: {t['chip']}"><th scope="col" class="mono" style="text-align: left; padding: 10px 14px; font-size: 11px; font-weight: 500; letter-spacing: 0.1em; color: {t['faint']}">PRODUCTO</th><th scope="col" class="mono" style="text-align: right; padding: 10px 14px; font-size: 11px; font-weight: 500; letter-spacing: 0.1em; color: {t['faint']}">PIEZAS</th><th scope="col" class="mono" style="text-align: right; padding: 10px 14px; font-size: 11px; font-weight: 500; letter-spacing: 0.1em; color: {t['faint']}">TOTAL</th></tr></thead>
<tbody>{tr}</tbody>
</table>
</div>
<div style="display: flex; align-items: baseline; justify-content: space-between; padding: 14px 18px; border-radius: 14px; background: {t['ink']}; color: {t['on_ink']}">
<span style="font-size: 13px; font-weight: 600">Total de hoy</span><span class="mono" style="font-size: 20px; font-weight: 500">$[total]</span></div>
<div style="font-size: 13.5px; color: {t['muted']}">Además hay <b>[n] mesas abiertas</b> que todavía no cuentan en este total.</div>
<div style="display: flex; gap: 8px">
<button type="button" style="display: flex; align-items: center; gap: 6px; height: 32px; padding: 0 12px; border-radius: 10px; border: 1px solid {t['line']}; background: {t['solid']}; color: {t['muted']}; font-size: 12.5px; font-weight: 600">{ico(I['copiar'], 14)}Copiar</button>
<button type="button" style="height: 32px; padding: 0 12px; border-radius: 10px; border: 1px solid {t['line']}; background: {t['solid']}; color: {t['text']}; font-size: 12.5px; font-weight: 600">Compárala con ayer</button>
<button type="button" style="height: 32px; padding: 0 12px; border-radius: 10px; border: 1px solid {t['line']}; background: {t['solid']}; color: {t['text']}; font-size: 12.5px; font-weight: 600">Ver la semana</button>
</div>
</div>
</div>
</div>
<div style="padding: 0 24px 24px">{compositor(t, chat=True)}</div>
</main>
<aside class="glass" style="position: absolute; left: 1104px; right: 16px; top: 92px; box-sizing: border-box; padding: 20px; display: flex; flex-direction: column; gap: 14px; background: {t['glass']}; border: 1px solid {t['glass_line']}; border-radius: 22px; box-shadow: {t['shadow']}">
<div class="mono" style="font-size: 10.5px; letter-spacing: 0.14em; color: {t['faint']}">LO QUE LEÍ PARA RESPONDER</div>
{fuente("menu", "Tu menú · [n] platillos")}
{fuente("mesas", "Tus mesas · [n]")}
{fuente("datos", "Ventas · últimas [n]")}
<div style="height: 1px; background: {t['line']}"></div>
<div style="font-size: 12.5px; line-height: 1.5; color: {t['muted']}">El día se cuenta de 6:00 a 6:00. Las sumas las hace el panel, no la IA.</div>
</aside>
</div>
''' + foot(1440, 900)

archivos = {
    "Main.dc.html": bienvenida("claro"),
    "Conversacion.dc.html": conversacion(),
    "Oscuro.dc.html": bienvenida("oscuro"),
}
for n, s in archivos.items():
    open(os.path.join(P, n), "w", encoding="utf-8").write(s)

ahora = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
canvas = {
    "v": 3, "createdOnFiles": {"v": 1, "at": ahora}, "title": "Agente IA rediseño",
    "launch": {"view": "canvas"}, "pages": [],
    "boards": {
        "Main.dc.html": {"x": 0, "y": 0, "w": 1440, "h": 900, "title": "Bienvenida · tema claro"},
        "Conversacion.dc.html": {"x": 1520, "y": 0, "w": 1440, "h": 900, "title": "Conversación · tema claro"},
        "Oscuro.dc.html": {"x": 0, "y": 1020, "w": 1440, "h": 900, "title": "Bienvenida · tema oscuro"},
    },
    "order": ["Main.dc.html", "Conversacion.dc.html", "Oscuro.dc.html"],
    "notes": {}, "designSystems": [],
}
open(os.path.join(P, "canvas.json"), "w", encoding="utf-8").write(json.dumps(canvas, ensure_ascii=False, indent=1))
print("ok")
