"use client";

import * as React from "react";
import { Renderer, Plane, Program, Mesh, Texture, Vec2 } from "ogl";
import { cn } from "@/lib/utils";

const CAMERA = 1.6;
const arc = (bend: number) => (CAMERA - 1 + Math.cos(bend)) / (2 * CAMERA * Math.sin(bend));

// Shared vertices make each screenshot one continuous surface. Separate CSS
// facets can expose the page through compositor seams while rotating.
const vertex = `
attribute vec3 position;
attribute vec2 uv;
uniform vec2 viewport;
uniform vec2 tileSize;
uniform float radius;
uniform float angle;
uniform float axis;
varying vec2 vUv;
void main() {
  vUv = uv;
  float theta = angle - position.x * tileSize.x / radius;
  float x = -radius * sin(theta);
  float z = radius * (1.0 - cos(theta));
  float distance = radius * 1.6;
  float w = distance - z;
  gl_Position = vec4(2.0 * x * distance / viewport.x,
    (1.0 - 2.0 * axis) * w + 2.0 * position.y * tileSize.y * distance / viewport.y,
    0.0, w);
}`;

const fragment = `
precision highp float;
uniform sampler2D picture;
uniform vec2 tileSize;
uniform vec2 crop;
varying vec2 vUv;
void main() {
  vec2 p = abs((vUv - 0.5) * tileSize) - (tileSize * 0.5 - 8.0);
  float edge = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - 8.0;
  if (edge > 0.0) discard;
  gl_FragColor = texture2D(picture, (vUv - 0.5) * crop + 0.5);
}`;

export type TiltedGridImage = { src: string; alt?: string };
export type TiltedGridHeroProps = {
  images: TiltedGridImage[];
  speed?: number;
  tileHeight?: number;
  aspectRatio?: number;
  gap?: number;
  axis?: number;
  curve?: number;
  fade?: number;
  children?: React.ReactNode;
  className?: string;
};

export function TiltedGridHero({ images, speed = 4, tileHeight = 26, aspectRatio = 16 / 9,
  gap = 6, axis = 56, curve = 80, fade = 12, children, className, ...props
}: React.ComponentProps<"div"> & TiltedGridHeroProps) {
  const ref = React.useRef<HTMLDivElement>(null);
  const canvasRef = React.useRef<HTMLCanvasElement>(null);
  const [fallback, setFallback] = React.useState(false);

  React.useEffect(() => {
    const canvas = canvasRef.current;
    const host = ref.current;
    if (!canvas || !host || !images.length) return;
    let renderer: Renderer;
    try {
      renderer = new Renderer({ canvas, alpha: true, antialias: true, dpr: Math.min(devicePixelRatio || 1, 2) });
      if (!renderer.gl) throw new Error("WebGL unavailable");
    } catch { setFallback(true); return; }
    setFallback(false);
    const gl = renderer.gl;
    const geometry = new Plane(gl, { widthSegments: 96 });
    const program = new Program(gl, {
      vertex, fragment, cullFace: null, depthTest: false, depthWrite: false,
      uniforms: {
        viewport: { value: new Vec2() }, tileSize: { value: new Vec2() },
        radius: { value: 1 }, angle: { value: 0 }, axis: { value: axis / 100 },
        picture: { value: null }, crop: { value: new Vec2(1, 1) },
      },
    });
    const mesh = new Mesh(gl, { geometry, program, frustumCulled: false });
    let disposed = false, visible = true, lost = false;
    let frame = 0, elapsed = 0, last = performance.now();
    let columns = 0, pitch = 0, sweep = 0, limit = 0;
    const step = Math.max(.1, speed);
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    const textures = images.map(({ src }) => {
      const texture = new Texture(gl, { generateMipmaps: false, minFilter: gl.LINEAR });
      const image = new Image();
      image.onload = () => { if (!disposed) { texture.image = image; texture.needsUpdate = true; draw(); } };
      image.src = src;
      return { texture, image };
    });
    function draw() {
      if (disposed || lost || !columns) return;
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      for (let t = 0; t < columns; t++) {
        const progress = elapsed / step + t;
        const lap = Math.floor(progress / columns);
        const angle = -sweep + (progress % columns) * pitch;
        if (Math.abs(angle) > limit) continue;
        const item = textures[(lap * columns + columns - 1 - t) % textures.length];
        if (!item.image.complete || !item.image.naturalWidth) continue;
        const ratio = item.image.naturalWidth / item.image.naturalHeight;
        program.uniforms.crop.value.set(Math.min(1, aspectRatio / ratio), Math.min(1, ratio / aspectRatio));
        program.uniforms.angle.value = angle;
        program.uniforms.picture.value = item.texture;
        renderer.render({ scene: mesh, clear: false });
      }
    }
    const active = () => visible && !document.hidden && !lost;
    const loop = (now: number) => {
      frame = 0;
      if (!active()) return;
      elapsed += Math.min((now - last) / 1000, .05);
      last = now;
      draw();
      if (!motion.matches) frame = requestAnimationFrame(loop);
    };
    const sync = () => {
      cancelAnimationFrame(frame);
      frame = 0;
      last = performance.now();
      if (active()) { draw(); if (!motion.matches) frame = requestAnimationFrame(loop); }
    };
    const resize = () => {
      const w = Math.max(1, host.clientWidth), h = Math.max(1, host.clientHeight);
      const height = Math.min(tileHeight / 100 * h, .55 * w / aspectRatio);
      const bend = Math.min(85, Math.max(5, curve)) * Math.PI / 180;
      const radius = w * arc(bend);
      pitch = (aspectRatio + gap / 100) * height / radius;
      limit = bend + aspectRatio * height / radius / 2;
      columns = Math.min(60, Math.max(2, Math.ceil(2 * limit / pitch)));
      sweep = columns * pitch / 2;
      renderer.setSize(w, h);
      canvas.style.width = "100%";
      canvas.style.height = "100%";
      program.uniforms.viewport.value.set(w, h);
      program.uniforms.tileSize.value.set(height * aspectRatio, height);
      program.uniforms.radius.value = radius;
      draw();
    };
    const sizes = new ResizeObserver(resize);
    const visibility = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; sync(); });
    const onLost = (event: Event) => { event.preventDefault(); lost = true; setFallback(true); sync(); };
    canvas.addEventListener("webglcontextlost", onLost);
    sizes.observe(host);
    visibility.observe(host);
    document.addEventListener("visibilitychange", sync);
    motion.addEventListener("change", sync);
    resize();
    sync();
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      sizes.disconnect(); visibility.disconnect();
      document.removeEventListener("visibilitychange", sync);
      motion.removeEventListener("change", sync);
      canvas.removeEventListener("webglcontextlost", onLost);
      textures.forEach(({ texture, image }) => { image.onload = null; gl.deleteTexture(texture.texture); });
      geometry.remove(); program.remove();
      gl.getExtension("WEBGL_lose_context")?.loseContext();
    };
  }, [images, speed, tileHeight, aspectRatio, gap, axis, curve]);

  const mask = `linear-gradient(90deg,transparent,#000 ${fade}%,#000 ${100 - fade}%,transparent)`;
  return <div ref={ref} className={cn("relative overflow-hidden", className)} {...props}>
    <div aria-hidden className="pointer-events-none absolute inset-0" style={{ maskImage: mask, WebkitMaskImage: mask }}>
      <canvas ref={canvasRef} className="absolute inset-0 block w-full h-full" style={{ visibility: fallback ? "hidden" : "visible" }} />
      {fallback && <div className="absolute flex w-full gap-4" style={{ top: `${axis}%`, transform: "translateY(-50%)" }}>
        {images.slice(0, 3).map(image => <img key={image.src} src={image.src} alt="" className="w-1/3 rounded-lg object-cover" />)}
      </div>}
    </div>
    {children}
  </div>;
}

export default TiltedGridHero;
