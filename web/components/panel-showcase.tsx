import { TiltedGridHero } from "@/components/ui/tilted-grid-hero";
import type { CSSProperties } from "react";

const palabras = (texto: string, desde = 0) => texto.split(" ").map((palabra, i) => (
  <span key={`${desde}-${i}`} style={{ "--i": desde + i } as CSSProperties}>{palabra}{" "}</span>
));

const images = [
  { src: "prueba/vista-sesion.webp", alt: "Inicio de sesión" },
  { src: "prueba/vista-inicio.webp", alt: "Resumen del restaurante" },
  { src: "prueba/vista-menu.webp", alt: "Administración del menú" },
  { src: "prueba/vista-mesas.webp", alt: "Control de mesas y cuentas" },
  { src: "prueba/vista-agente.webp", alt: "Agente de inteligencia artificial" },
  { src: "prueba/vista-contenido.webp", alt: "Creación de anuncios" },
  { src: "prueba/vista-biblioteca.webp", alt: "Biblioteca de contenido" },
];

export default function PanelShowcase() {
  return <TiltedGridHero images={images} speed={3.5} tileHeight={26} axis={56} curve={80}
    className="panel-reel" aria-labelledby="panel-titulo" aria-describedby="panel-resumen">
    <div className="panel-copy">
      <h2 id="panel-titulo" className="se-pinta">{palabras("Todo tu restaurante.")}<br />{palabras("En un solo lugar.", 3)}</h2>
      <p id="panel-resumen" className="se-enciende">{palabras("De tu menú a tus ventas, de tus mesas a tus redes. Administra tu restaurante, consulta a tu agente de IA y crea contenido para tu negocio desde un mismo panel.")}</p>
    </div>
  </TiltedGridHero>;
}
