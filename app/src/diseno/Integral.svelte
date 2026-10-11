<!--
  El logo de Fragmentless: la doble integral ∫∫ acostada (la misma de web/index.html, #integral).
  Toma el color del texto que la rodea (currentColor). Va en la barra lateral, junto a la fecha
  de Inicio y en la etiqueta de las manchas.
-->
<script lang="ts" module>
  const TRAZO =
    'M 299.5 47.5 A 19 19 0 1 1 272.15 57.5 C 258 54 245 72 238 100 C 232 124 222 172 216 200 C 210 230 204 264 196 292 C 182 340 156 360 122 360 C 112 360 106 355.7 100.5 352.5 A 19 19 0 1 1 127.85 342.5 C 142 346 155 328 162 300 C 168 276 178 228 184 200 C 190 170 196 136 204 108 C 218 60 244 40 278 40 C 288 40 294 44.3 299.5 47.5 Z';
</script>

<script lang="ts">
  let { ancho, alto }: { ancho: number; alto: number } = $props();
</script>

<svg width={ancho} height={alto} viewBox="104 25 322 350" aria-hidden="true">
  <g fill="currentColor" transform="rotate(90 265 200)">
    <path d={TRAZO} />
    <path transform="translate(130 0)" d={TRAZO} />
  </g>
</svg>

<style>
  svg {
    display: block;
    flex: none;
  }
</style>
