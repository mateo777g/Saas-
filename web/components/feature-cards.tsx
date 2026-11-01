import { GlassBlogCard, type GlassBlogCardProps } from "@/components/ui/glass-blog-card-shadcnui";

const items: GlassBlogCardProps[] = [
  {
    title: "Adiós a la libreta",
    icon: "notebook",
    description: "¿Sigues anotando tus ventas a mano y sumando con la calculadora? Nuestro sistema lo hace por ti.",
    src: "prueba/tarjeta-libreta.webp",
    alt: "Una mujer registra las ventas a mano en una libreta junto a una calculadora.",
  },
  {
    title: "Punto de venta",
    icon: "terminal",
    description: "Toma pedidos y cierra cuentas desde la mesa.",
    src: "prueba/tarjeta-mesera.webp",
    alt: "Una mesera toma el pedido de una cliente desde una tablet.",
  },
  {
    title: "Agente de IA",
    icon: "sparkles",
    description: "Deja la calculadora: pregúntale cuánto vendiste.",
    src: "prueba/tarjeta-cuentas.webp",
    alt: "Una mujer consulta el agente de IA del restaurante en su laptop.",
  },
];

export default function FeatureCards() {
  return <div className="feature-grid">{items.map((item) => <GlassBlogCard key={item.src} {...item} />)}</div>;
}
