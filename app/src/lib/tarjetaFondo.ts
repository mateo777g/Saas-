// @ts-nocheck — copiado de la maqueta aprobada (planes/trabajo/tarjeta-lealtad/maqueta/liquido.js, v22) casi tal cual:
// WebGL y canvas a mano, sin tipos.
// El fondo de la tarjeta de lealtad en sus seis estilos (la tarjeta de lealtad, 22 nov 2026). Cada uno se pinta una vez en
// el color que eligió Don Chuy y queda como imagen (una tarjeta impresa): Líquido (el fondo de cards-shader-effect), Agua
// (el «Liquid Checkout» de Nimbus UI: su agua y sus burbujas sí se mueven, en vivo, un solo WebGL para todas), Metal y
// Brillante (el material del «Card Tilt Depth», MIT, con su destello al tocarla) y Olas (canvas 2D). Liso no pinta nada.
//   pintarTarjeta(elemento, color, estilo, todos) pone las variables de diseno/tarjetaLealtad.css en el elemento.
//   destelloTarjeta(tarjeta) cruza el destello de Metal o Brillante una vez. vigilarAguaViva() mueve el agua.
// Lo usan la tarjeta del menú, Tu tarjeta del panel y el cobro.
const cache = new Map();
const VS = 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0., 1.); }';
const FS = `precision highp float;
uniform vec2 res; uniform vec3 cHondo, cSombra, cMedio, cLuz; uniform float semilla, escala, bandas;
float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3. - 2. * f);
return mix(mix(hash(i), hash(i + vec2(1., 0.)), u.x), mix(hash(i + vec2(0., 1.)), hash(i + vec2(1., 1.)), u.x), u.y); }
float fbm(vec2 p){ float v = 0., a = .5; mat2 r = mat2(.8, .6, -.6, .8);
for (int i = 0; i < 3; i++){ v += a * noise(p); p = r * p * 2.03 + 1.7; a *= .5; } return v / .875; }
void main(){
vec2 uv = (gl_FragCoord.xy - .5 * res) / res.y;
uv = mat2(.9, -.44, .44, .9) * uv;
uv *= vec2(.8, 1.9) * escala;
uv += semilla;
vec2 q = vec2(fbm(uv * .9), fbm(uv * .9 + vec2(5.2, 1.3)));
vec2 r = vec2(fbm(uv * .9 + 2.6 * q + vec2(1.7, 9.2)), fbm(uv * .9 + 2.6 * q + vec2(8.3, 2.8)));
float f = fbm(uv * .9 + 2.4 * r);
float b = .5 + .5 * sin(f * bandas + q.x * 4.);
b = smoothstep(.06, .94, b);
float t = mix(b, f, .25);
vec3 col = mix(cHondo, cSombra, smoothstep(.12, .42, t));
col = mix(col, cMedio, smoothstep(.3, .55, t));
col = mix(col, cLuz, smoothstep(.5, .78, t));
// el claro no es plano: se aclara con el pliegue y se apaga hacia la sombra
col = mix(col, cMedio, smoothstep(.55, 1., t) * (1. - q.y) * .35);
col = mix(col, cLuz * 1.12, smoothstep(.7, 1., t) * smoothstep(.45, .8, r.x) * .5);
// grano, más en la sombra
col += (hash(gl_FragCoord.xy + semilla * 97.) - .5) * (.1 - .05 * t);
gl_FragColor = vec4(col, 1.);
}`;
function rgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255]; }
function aHsl([r, g, b]) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
  if (!d) return [0, 0, l];
  const s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn);
  const h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
}
function deHsl(h, s, l) {
  h = ((h % 360) + 360) % 360; s = Math.max(0, Math.min(1, s)); l = Math.max(0, Math.min(1, l));
  const k = (n) => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return [f(0), f(8), f(4)];
}
// Los cuatro tonos salen del color elegido: el claro un poco más claro, el medio es él, y dos sombras hondas. Con un color
// claro (sus letras van en negro) las sombras no bajan tanto, para que el negro se lea encima de todo el fondo.
function tonos(color) {
  const [h, s, l] = aHsl(rgb(color));
  if (lum(color) > 0.42) return {
    cLuz: deHsl(h - 3, Math.min(1, s + .05), Math.min(.86, l + .14)),
    cMedio: deHsl(h, s * .9, l),
    cSombra: deHsl(h + 6, s * .8, l * .78),
    cHondo: deHsl(h + 10, s * .85, l * .62),
  };
  return {
    cLuz: deHsl(h - 4, Math.min(1, s * 1.08 + .05), Math.min(.78, l + .16)),
    cMedio: deHsl(h, s * .85, l),
    cSombra: deHsl(h + 10, s * .55, Math.min(.3, l * .55)),
    cHondo: deHsl(h + 18, Math.min(1, s * 1.05 + .1), Math.min(.13, l * .25)),
  };
}
let lienzo = null, gl = null, prog = null;
function preparar() {
  lienzo = document.createElement('canvas');
  gl = lienzo.getContext('webgl', { preserveDrawingBuffer: true });
  if (!gl) return false;
  const sh = (tipo, src) => { const s = gl.createShader(tipo); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) console.error('[liquido]', gl.getShaderInfoLog(s)); return s; };
  prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(prog);
  gl.useProgram(prog);
  const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const lp = gl.getAttribLocation(prog, 'p'); gl.enableVertexAttribArray(lp); gl.vertexAttribPointer(lp, 2, gl.FLOAT, false, 0, 0);
  return true;
}
const tlLiquido = (color, semilla = 0.91, ancho = 672, alto = 424, escala = 2, bandas = 9) => {
  const llave = `${color}|${semilla}|${ancho}|${escala}|${bandas}`;
  if (cache.has(llave)) return cache.get(llave);
  if (!gl && !preparar()) return null;
  lienzo.width = ancho; lienzo.height = alto;
  gl.viewport(0, 0, ancho, alto);
  const t = tonos(color);
  gl.uniform2f(gl.getUniformLocation(prog, 'res'), ancho, alto);
  gl.uniform1f(gl.getUniformLocation(prog, 'semilla'), semilla * 10);
  gl.uniform1f(gl.getUniformLocation(prog, 'escala'), escala);
  gl.uniform1f(gl.getUniformLocation(prog, 'bandas'), bandas);
  for (const k of Object.keys(t)) gl.uniform3fv(gl.getUniformLocation(prog, k), t[k]);
  gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  const url = lienzo.toDataURL('image/jpeg', 0.9);
  cache.set(llave, url);
  return url;
};
// ─── Estilo «Agua» (del «Liquid Checkout · Tidepool» de Nimbus UI, 22 nov 2026) ───
// El developer tomó el agua adentro, el brillo del vidrio y las burbujas, con el agua siempre a la misma altura (42 %) y
// quieta: una sola foto del shader (sin inclinarse, sin mecerse; nada se mueve solo). Sus tres tonos (el vidrio de arriba,
// el de abajo y el agua) salen del color elegido; el agua se oscurece parejo hacia el fondo, en cualquier color.
const FS_AGUA = `precision highp float;
uniform vec2 uRes; uniform float uDpr; uniform float uTime; uniform float uLevel; uniform vec3 uA; uniform vec3 uB; uniform vec3 uW; uniform float uR; uniform float uSheen;
float sdRB(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.)) + min(max(q.x, q.y), 0.) - r; }
float caus(vec2 p, float t){ vec2 q = p; float c = 0.; for (int i = 0; i < 3; i++){ q += vec2(sin(q.y * 1.1 + t), cos(q.x * 1.3 - t * .7)) * .6; c += 1. / (1. + 16. * abs(sin(q.x) * sin(q.y))); } return c / 3.; }
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float surfY(float x){ return uRes.y * (1. - uLevel) + 1.2 * sin(x * .045 + uTime * 2.6) + 1.2 * sin(x * .11 - uTime * 1.7); }
void main(){
vec2 p = vec2(gl_FragCoord.x, uRes.y * uDpr - gl_FragCoord.y) / uDpr;
vec2 c = uRes * .5; float d = sdRB(p - c, c - .5, uR);
vec2 uv = p / uRes;
vec3 col = mix(uA, uB, clamp(uv.y * .75 + uv.x * .4, 0., 1.));
vec2 q = (uv - vec2(.22, .15)) * vec2(1.5, 2.3); col += .16 * exp(-dot(q, q) * 2.5);
float s = surfY(p.x); float sd = p.y - s;
float under = smoothstep(-.8, .8, sd); float depth = clamp(sd / uRes.y, 0., 1.);
vec3 wc = mix(uW, uW * .42, depth * 1.3);
float cs = caus(p * .042 + vec2(0., uTime * .05), uTime * .9);
wc += mix(vec3(1.), uW, .2) * smoothstep(.55, 1., cs) * .38 * (1. - depth * .7);
float bub = 0.;
for (int i = 0; i < 7; i++){ float fi = float(i); float bx = uRes.x * (.1 + .8 * hash(vec2(fi, 3.1))); float sp = 30. + 40. * hash(vec2(fi, 7.7));
  float by = uRes.y - mod(uTime * sp + hash(vec2(fi, 1.3)) * uRes.y, uRes.y * 1.2); float br = 1.2 + 2.2 * hash(vec2(fi, 9.1));
  vec2 bp = p - vec2(bx + sin(uTime * 2. + fi) * 3., by); float bd = length(bp) - br;
  bub += (smoothstep(.8, -.8, bd) * .25 + smoothstep(.8, 0., abs(bd)) * .5) * step(s + br, by); }
wc += vec3(1.) * bub;
col = mix(col, mix(col, wc, .74), under);
col += vec3(1.) * (exp(-pow(sd + 1., 2.) / 2.) * .75 + exp(-pow(sd - 3.5, 2.) / 12.) * .14);
float ang = dot(uv - .5, normalize(vec2(1., .55)));
vec3 irid = .5 + .5 * cos(6.2831 * (vec3(0., .33, .67) + ang * 1.7 + uTime * .03));
float sheen = exp(-pow((ang - .06) / .07, 2.)) * .2 + exp(-pow((ang + .3) / .025, 2.)) * .1;
col += mix(vec3(1.), irid, .5) * sheen * uSheen;
float rim = smoothstep(-7., 0., d); col = mix(col, mix(vec3(1.), irid, .65), rim * .16);
col += smoothstep(-1.6, 0., d) * .35 * (.35 + .65 * (1. - uv.y));
col += (hash(p) - .5) * .014;
gl_FragColor = vec4(col, 1.);
}`;
function tonosAgua(color) {
  const [h, s, l] = aHsl(rgb(color));
  return {
    uA: deHsl(h - 6, Math.min(1, s * 1.05), Math.min(0.8, l + 0.14)),
    uB: deHsl(h + 4, Math.min(1, s * 1.1), Math.max(0.1, l - 0.16)),
    uW: deHsl(h - 10, Math.min(1, s * 0.95 + 0.1), Math.min(0.68, l + 0.2)),
  };
}
let lienzoA = null, glA = null, progA = null;
function prepararAgua() {
  lienzoA = document.createElement('canvas');
  glA = lienzoA.getContext('webgl', { preserveDrawingBuffer: true });
  if (!glA) return false;
  const sh = (tipo, src) => { const s = glA.createShader(tipo); glA.shaderSource(s, src); glA.compileShader(s);
    if (!glA.getShaderParameter(s, glA.COMPILE_STATUS)) console.error('[agua]', glA.getShaderInfoLog(s)); return s; };
  progA = glA.createProgram();
  glA.attachShader(progA, sh(glA.VERTEX_SHADER, VS)); glA.attachShader(progA, sh(glA.FRAGMENT_SHADER, FS_AGUA)); glA.linkProgram(progA);
  glA.useProgram(progA);
  glA.bindBuffer(glA.ARRAY_BUFFER, glA.createBuffer());
  glA.bufferData(glA.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), glA.STATIC_DRAW);
  const lp = glA.getAttribLocation(progA, 'p'); glA.enableVertexAttribArray(lp); glA.vertexAttribPointer(lp, 2, glA.FLOAT, false, 0, 0);
  return true;
}
// 336 × 212 (la proporción de la tarjeta) a 2×; el agua al 42 %, en el instante 3.7 s (las burbujas a media subida).
const tlAgua = (color) => {
  const llave = `agua|${color}`;
  if (cache.has(llave)) return cache.get(llave);
  if (!glA && !prepararAgua()) return null;
  lienzoA.width = 672; lienzoA.height = 424;
  glA.viewport(0, 0, 672, 424);
  const u = (n) => glA.getUniformLocation(progA, n);
  glA.uniform2f(u('uRes'), 336, 212);
  glA.uniform1f(u('uDpr'), 2);
  glA.uniform1f(u('uTime'), 3.7);
  glA.uniform1f(u('uLevel'), 0.42);
  glA.uniform1f(u('uR'), 17);
  glA.uniform1f(u('uSheen'), 0); // los brillos van aparte, en CSS, y se mecen (tarjeta.css, .tl-destello de Agua)
  const t = tonosAgua(color);
  for (const k of Object.keys(t)) glA.uniform3fv(u(k), t[k]);
  glA.drawArrays(glA.TRIANGLE_STRIP, 0, 4);
  const url = lienzoA.toDataURL('image/jpeg', 0.92);
  cache.set(llave, url);
  return url;
};
// ─── Estilos «Metal» y «Brillante» (del «Card Tilt Depth» de haim repael azoulay, MIT; 22 nov 2026) ───
// El developer tomó el grosor, el material y el destello, y los dos materiales como dos estilos. La cara es el color elegido;
// el material (metal cepillado o brillante, la luz a -35°) se pinta una vez en la pose de reposo, como foto. En una cara
// oscura la luz se suma; en una clara (letras negras) se sombrea donde no le llega, como en el componente.
const FS_MATERIAL = `precision highp float;
uniform vec2 u_res; uniform float u_px; uniform float u_radius; uniform vec2 u_tilt; uniform vec4 u_light; uniform float u_ms;
uniform float u_tone; uniform vec3 u_face; uniform vec3 u_ink;
float sdRoundBox(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + vec2(r); return length(max(q, vec2(0.))) + min(max(q.x, q.y), 0.) - r; }
float gaussian(float x, float w){ return exp(-.5 * x * x / max(w * w, .0001)); }
float hash(float n){ return fract(sin(n) * 43758.5453); }
void main(){
vec2 v_uv = vec2(gl_FragCoord.x * u_px / u_res.x, 1. - gl_FragCoord.y * u_px / u_res.y);
vec2 hs = u_res * .5; vec2 p = (v_uv - .5) * u_res;
float r = clamp(u_radius, 0., min(hs.x, hs.y)); float d = sdRoundBox(p, hs, r); float edge = max(-d, 0.);
vec2 q = p / max(hs, vec2(1.)); vec2 tl = clamp(u_tilt, vec2(-1.), vec2(1.));
float ang = u_light.x; vec2 L = vec2(sin(ang), -cos(ang)); vec2 Lt = normalize(L + vec2(-tl.y, tl.x) * .35);
float along = dot(q, Lt); float across = dot(q, vec2(-Lt.y, Lt.x));
float bandPos = -.1 + dot(vec2(tl.y, -tl.x), L) * .7;
float metallic = u_light.w; float ms = clamp(u_ms, 0., 1.);
float wG = mix(.22, .09, ms);
float glossy = pow(gaussian(along - bandPos, wG), 1. + ms) + gaussian(along - bandPos - .3, .06) * .45;
float wM = mix(.35, .65, ms); float streak = 0.;
for (int i = 0; i < 3; i++){ float f = 90. + float(i) * 70.; streak += sin(across * f + hash(float(i) * 7.3) * 6.28 + along * 9.) * (.5 - float(i) * .12); }
streak = .5 + .5 * streak / 1.2;
float hair = hash(floor(across * 160. + along * 2.)) * .6 + hash(floor(across * 47.)) * .4;
streak = mix(streak, streak * (.55 + .9 * hair), .7);
float broad = gaussian(along - bandPos, wM);
float metal = broad * mix(.75, .35 + .65 * streak, ms) * .9 + gaussian(along - bandPos, wM * .3) * .3;
float spec = mix(glossy, metal, metallic) * (.65 + .35 * clamp(length(tl), 0., 1.));
vec2 e = vec2(.75, 0.);
vec2 n = normalize(vec2(sdRoundBox(p + e.xy, hs, r) - sdRoundBox(p - e.xy, hs, r), sdRoundBox(p + e.yx, hs, r) - sdRoundBox(p - e.yx, hs, r)) + .00001);
float lit = dot(n, Lt); float facing = .45 + .55 * clamp(lit, 0., 1.);
float rim = exp(-edge / 1.8) * facing; float rimSoft = exp(-edge / 7.) * facing * .25;
float bevelPx = u_light.z;
float bev = (1. - smoothstep(0., max(bevelPx, .001), edge)) * step(.5, bevelPx);
float bevShape = bev * sin(bev * 1.5708);
float bevHi = bevShape * clamp(lit, 0., 1.) * .9; float bevLo = bevShape * clamp(-lit, 0., 1.) * .55;
float toLight = clamp(.5 + .5 * dot(q, Lt), 0., 1.); float amount = u_light.y;
float hi = (spec * .36 + rim * .8 + rimSoft + toLight * .06 + bevHi) * amount;
vec3 colD = u_ink * hi; float aD = clamp(hi + bevLo * amount, 0., 1.); colD = min(colD, vec3(aD));
vec3 oscura = colD + u_face * (1. - aD);
float reach = clamp(spec * .8, 0., 1.);
float rimShade = exp(-edge / 1.6) * clamp(.35 - lit * .65, 0., 1.) * .3;
float aL = clamp((mix(.07, .17, metallic) * (1. - reach) + (1. - toLight) * .05 + rimShade + bevLo) * amount, 0., 1.);
vec3 clara = u_ink * aL + u_face * (1. - aL);
gl_FragColor = vec4(mix(clara, oscura, u_tone), 1.);
}`;
let lienzoM = null, glM = null, progM = null;
function prepararMaterial() {
  lienzoM = document.createElement('canvas');
  glM = lienzoM.getContext('webgl', { preserveDrawingBuffer: true });
  if (!glM) return false;
  const sh = (tipo, src) => { const s = glM.createShader(tipo); glM.shaderSource(s, src); glM.compileShader(s);
    if (!glM.getShaderParameter(s, glM.COMPILE_STATUS)) console.error('[material]', glM.getShaderInfoLog(s)); return s; };
  progM = glM.createProgram();
  glM.attachShader(progM, sh(glM.VERTEX_SHADER, VS)); glM.attachShader(progM, sh(glM.FRAGMENT_SHADER, FS_MATERIAL)); glM.linkProgram(progM);
  glM.useProgram(progM);
  glM.bindBuffer(glM.ARRAY_BUFFER, glM.createBuffer());
  glM.bufferData(glM.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), glM.STATIC_DRAW);
  const lp = glM.getAttribLocation(progM, 'p'); glM.enableVertexAttribArray(lp); glM.vertexAttribPointer(lp, 2, glM.FLOAT, false, 0, 0);
  return true;
}
// Los valores del componente: luz a -35°, 0.8 de luz, bisel de 3, fuerza 0.5; la pose de reposo (3.5° y -4.5° de 10°).
const tlMaterial = (color, metalico, negra) => {
  const llave = `material|${color}|${metalico}`;
  if (cache.has(llave)) return cache.get(llave);
  if (!glM && !prepararMaterial()) return null;
  lienzoM.width = 672; lienzoM.height = 424;
  glM.viewport(0, 0, 672, 424);
  const u = (n) => glM.getUniformLocation(progM, n);
  glM.uniform2f(u('u_res'), 336, 212);
  glM.uniform1f(u('u_px'), 0.5);
  glM.uniform1f(u('u_radius'), 17);
  glM.uniform2f(u('u_tilt'), 0.35, -0.45);
  glM.uniform4f(u('u_light'), (-35 * Math.PI) / 180, 0.8, 3, metalico ? 1 : 0);
  glM.uniform1f(u('u_ms'), 0.5);
  glM.uniform1f(u('u_tone'), negra ? 0 : 1);
  glM.uniform3fv(u('u_face'), rgb(color));
  glM.uniform3fv(u('u_ink'), negra ? rgb('#151515') : [1, 1, 1]);
  glM.drawArrays(glM.TRIANGLE_STRIP, 0, 4);
  const url = lienzoM.toDataURL('image/jpeg', 0.92);
  cache.set(llave, url);
  return url;
};

// El destello: una franja de luz (y otra delgadita detrás) que cruza una vez la tarjeta de Metal o Brillante cuando la
// tocan o le pasan el mouse (900 ms, como el componente). Quieto con «reducir movimiento».
export function destelloTarjeta(t) {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return;
  const raiz = t.closest('[data-tl-estilo]');
  if (!raiz || !['metal', 'brillante'].includes(raiz.dataset.tlEstilo)) return;
  t.querySelectorAll('.tl-destello').forEach((d) => {
    d.getAnimations().forEach((a) => a.cancel());
    d.animate([{ backgroundPosition: '100% 0', opacity: 1 }, { backgroundPosition: '0% 0', opacity: 1 }], { duration: 900, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' });
  });
}
// ─── Estilo «Olas» (22 nov 2026, el último): como Liso, con olas suaves de la referencia del developer (las tarjetas de
// Fidely): el color de fondo, una banda de otro tono que cruza en diagonal con orillas curvas y una esquina más clara abajo
// a la derecha. Se dibuja una vez con canvas 2D en tonos del color elegido, todos del mismo matiz.
const tlOlas = (color) => {
  const llave = `olas|${color}`;
  if (cache.has(llave)) return cache.get(llave);
  const W = 672, H = 424, cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const g = cv.getContext('2d');
  if (!g) return null;
  const [h, s, l] = aHsl(rgb(color));
  const css = (v) => `rgb(${v.map((x) => Math.round(x * 255)).join(',')})`;
  const base = rgb(color);
  // Todo en el mismo tono del color elegido (el developer: «en la misma tonalidad roja»); solo cambia qué tan claro es.
  // Con un color claro, la banda va un poco más oscura para que se note.
  const banda = deHsl(h, s, l > 0.6 ? l - 0.07 : Math.min(0.9, l + 0.08));
  const claro = deHsl(h, s * 0.9, l > 0.6 ? Math.min(0.95, l + 0.06) : Math.min(0.92, l + 0.17));
  const luz = deHsl(h, s, Math.min(0.95, l + (l > 0.6 ? 0.05 : 0.1)));
  g.fillStyle = css(base); g.fillRect(0, 0, W, H);
  // Una ola clara arriba a la izquierda, detrás del nombre.
  g.fillStyle = css(luz); g.globalAlpha = 0.55;
  g.beginPath(); g.moveTo(0, 0); g.lineTo(W * 0.58, 0);
  g.bezierCurveTo(W * 0.46, H * 0.18, W * 0.24, H * 0.2, 0, H * 0.42); g.closePath(); g.fill();
  // La banda: entra por la izquierda a media altura y sube hacia la derecha, con su orilla de arriba curva.
  g.globalAlpha = 1; g.fillStyle = css(banda);
  g.beginPath(); g.moveTo(0, H * 0.6);
  g.bezierCurveTo(W * 0.28, H * 0.48, W * 0.52, H * 0.62, W * 0.74, H * 0.46);
  g.bezierCurveTo(W * 0.86, H * 0.37, W * 0.94, H * 0.36, W, H * 0.34);
  g.lineTo(W, H); g.lineTo(0, H); g.closePath(); g.fill();
  // La esquina más clara de abajo a la derecha.
  g.fillStyle = css(claro);
  g.beginPath(); g.moveTo(W * 0.38, H);
  g.bezierCurveTo(W * 0.58, H * 0.86, W * 0.74, H * 0.9, W, H * 0.66);
  g.lineTo(W, H); g.closePath(); g.fill();
  const url = cv.toDataURL('image/png');
  cache.set(llave, url);
  return url;
};
// ─── El agua viva (22 nov 2026, el developer: «el agua moviéndose y las burbujas, también») ───
// Cada tarjeta Agua que se ve lleva un <canvas> encima de su foto (debajo del velo y de lo escrito): un solo WebGL pinta el
// shader de Agua con el tiempo corriendo (la orilla se mece, la luz del fondo se mueve, las burbujas suben; la tarjeta no
// se inclina) y se copia a cada tarjeta de ese color. Solo corre mientras hay una tarjeta Agua a la vista; con «reducir
// movimiento» se queda la foto quieta.
const vivo = { cv: null, gl: null, prog: null, raf: 0, t0: 0 };
function prepararVivo() {
  vivo.cv = document.createElement('canvas');
  const gl = (vivo.gl = vivo.cv.getContext('webgl', { preserveDrawingBuffer: true }));
  if (!gl) return false;
  const sh = (tipo, src) => { const s = gl.createShader(tipo); gl.shaderSource(s, src); gl.compileShader(s); return s; };
  const p = (vivo.prog = gl.createProgram());
  gl.attachShader(p, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, FS_AGUA)); gl.linkProgram(p);
  gl.useProgram(p);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const lp = gl.getAttribLocation(p, 'p'); gl.enableVertexAttribArray(lp); gl.vertexAttribPointer(lp, 2, gl.FLOAT, false, 0, 0);
  vivo.cv.width = 504; vivo.cv.height = 318; gl.viewport(0, 0, 504, 318);
  const u = (n) => gl.getUniformLocation(p, n);
  gl.uniform2f(u('uRes'), 336, 212); gl.uniform1f(u('uDpr'), 1.5); gl.uniform1f(u('uLevel'), 0.42);
  gl.uniform1f(u('uR'), 17); gl.uniform1f(u('uSheen'), 0);
  return true;
}
const quietoAgua = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
function tarjetasAgua() {
  return [...document.querySelectorAll('.tl-frente')].filter((f) => {
    if (f.closest('[data-tl-estilo]')?.dataset.tlEstilo !== 'agua' || !f.offsetParent) return false;
    const r = f.getBoundingClientRect();
    return r.width > 0 && r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth;
  });
}
function cuadroAgua(ahora) {
  vivo.raf = 0;
  const lista = tarjetasAgua();
  if (!lista.length || quietoAgua() || document.hidden) return;
  if (!vivo.gl && !prepararVivo()) return;
  const gl = vivo.gl, u = (n) => gl.getUniformLocation(vivo.prog, n);
  const t = 3.7 + (ahora - vivo.t0) / 1000;
  const porColor = new Map();
  for (const f of lista) {
    const c = getComputedStyle(f).getPropertyValue('--tl-color').trim() || '#2B5BAA';
    if (!porColor.has(c)) porColor.set(c, []);
    porColor.get(c).push(f);
  }
  gl.uniform1f(u('uTime'), t);
  for (const [c, tarjetas] of porColor) {
    const tn = tonosAgua(c);
    for (const k of Object.keys(tn)) gl.uniform3fv(u(k), tn[k]);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    for (const f of tarjetas) {
      let lienzo = f.querySelector(':scope > canvas.tl-agua-viva');
      if (!lienzo) {
        lienzo = document.createElement('canvas');
        lienzo.className = 'tl-agua-viva';
        lienzo.setAttribute('aria-hidden', 'true');
        f.prepend(lienzo);
      }
      const d = Math.min(devicePixelRatio || 1, 2), w = Math.round(f.clientWidth * d), h = Math.round(f.clientHeight * d);
      if (lienzo.width !== w || lienzo.height !== h) { lienzo.width = w; lienzo.height = h; }
      lienzo.getContext('2d').drawImage(vivo.cv, 0, 0, w, h);
    }
  }
  vivo.raf = requestAnimationFrame(cuadroAgua);
}
// Se asoma cada 400 ms por si apareció una tarjeta Agua (cambiar de estilo, de pestaña o de pantalla), solo mientras haya
// una tarjeta Agua montada: cada una llama vigilarAguaViva() y, al irse, lo que regresa.
let vigilantes = 0, reloj = 0;
export function vigilarAguaViva() {
  if (!vigilantes++) reloj = setInterval(() => {
    if (vivo.raf || quietoAgua() || document.hidden) return;
    if (tarjetasAgua().length) { if (!vivo.t0) vivo.t0 = performance.now(); vivo.raf = requestAnimationFrame(cuadroAgua); }
  }, 400);
  return () => {
    if (--vigilantes) return;
    clearInterval(reloj);
    if (vivo.raf) cancelAnimationFrame(vivo.raf);
    vivo.raf = 0;
  };
}
// Blanco o negro: lo que se lea mejor sobre el color (luminancia relativa, como WCAG).
const lum = (c) => { const v = rgb(c).map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4)); return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]; };
// tlPintar(elemento, color, estilo, todos): pone en el elemento las variables de tarjeta.css. Pinta el fondo del estilo que
// lleva (o de todos, para los cuadros de estilos del panel).
export const pintarTarjeta = (el, color, estilo, todos) => {
  const [h, s, l] = aHsl(rgb(color));
  const negra = lum(color) > 0.42;
  const os = deHsl(h + 8, Math.min(1, s * 0.9 + 0.05), negra ? 0.2 : Math.min(0.2, l * 0.42));
  const hex = (v) => '#' + v.map((x) => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, '0')).join('');
  el.style.setProperty('--tl-color', color);
  el.style.setProperty('--tl-oscuro', hex(os));
  el.style.setProperty('--tl-tinta', negra ? '#151515' : '#ffffff');
  el.dataset.tlTinta = negra ? 'negra' : 'blanca';
  if (estilo) el.dataset.tlEstilo = estilo;
  const quiere = (k) => todos || estilo === k;
  const url = (u) => (u ? `url(${u})` : 'none');
  if (quiere('liquido')) el.style.setProperty('--tl-fondo-liquido', url(tlLiquido(color)));
  if (quiere('agua')) {
    const ta = tonosAgua(color);
    el.style.setProperty('--tl-fondo-agua', url(tlAgua(color)));
    el.style.setProperty('--tl-agua-a', hex(ta.uA));
    el.style.setProperty('--tl-agua-b', hex(ta.uB));
  }
  if (quiere('metal')) el.style.setProperty('--tl-fondo-metal', url(tlMaterial(color, true, negra)));
  if (quiere('brillante')) el.style.setProperty('--tl-fondo-brillo', url(tlMaterial(color, false, negra)));
  if (quiere('olas')) el.style.setProperty('--tl-fondo-olas', url(tlOlas(color)));
  // El canto: la cara vista de lado, un paso hacia su tinta (como el componente).
  const f = rgb(color), t = negra ? 0.08 : 1;
  el.style.setProperty('--tl-canto', hex(f.map((v) => v + (t - v) * 0.12)));
};
