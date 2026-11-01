import { useEffect, useRef, type CSSProperties } from "react";

export interface GlassBlogCardProps {
  title: string;
  description: string;
  src: string;
  alt: string;
  icon: "notebook" | "terminal" | "sparkles";
}

const palabras = (texto: string) => texto.split(/\s+/).map((palabra, i) => (
  <span key={i} style={{ "--i": i } as CSSProperties}>{palabra}{" "}</span>
));

// Adaptación de la tarjeta de referencia al contenido de producto de Fragmentless.
export function GlassBlogCard({ title, description, src, alt, icon }: GlassBlogCardProps) {
  const ref = useRef<HTMLElement>(null);
  useEffect(() => {
    const card = ref.current;
    if (!card) return;
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      card.setAttribute("data-visible", "");
      observer.disconnect();
    }, { threshold: .15 });
    observer.observe(card.querySelector('.glass-feature-content')!);
    return () => observer.disconnect();
  }, []);

  return <article ref={ref} className="glass-feature-card">
    <div className="glass-feature-image">
      <img src={src} alt={alt} loading="lazy" width="1200" height="675" />
    </div>
    <div className="glass-feature-content">
      <svg className="glass-feature-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
        {icon === "notebook" && <>
          <rect x="5" y="3" width="15" height="18" rx="2" />
          <path d="M9 3v18M3 7h4M3 12h4M3 17h4M12 8h5M12 12h5" />
        </>}
        {icon === "terminal" && <>
          <rect x="4.5" y="3" width="15" height="18" rx="2" />
          <path d="M10 17.5h4" />
        </>}
        {icon === "sparkles" && <>
          <path d="m10 3 2.1 4.9L17 10l-4.9 2.1L10 17l-2.1-4.9L3 10l4.9-2.1L10 3Zm8 12 1.2 2.8L22 19l-2.8 1.2L18 23l-1.2-2.8L14 19l2.8-1.2L18 15Z" />
        </>}
      </svg>
      <h2 className="se-pinta">{palabras(title)}</h2>
      <p className="se-enciende">{palabras(description)}</p>
    </div>
  </article>;
}
