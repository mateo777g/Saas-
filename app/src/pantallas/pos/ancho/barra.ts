// Quién abre Vender, la Caja o Pedidos a lo ancho (adaptabilidad; maqueta GBWEGCsQFcwKkWm7Qe9FPA v4), para su barra
// de arriba (Barra.svelte). El aparato: su logo, el restaurante, quién está y sus pestañas en el dock (Vender · Caja ·
// Pedidos, el «2» de Pedidos en su esquina). El panel del gerente: «‹ Inicio», el título y, a la derecha, la cajita de
// sucursales.
import type { Snippet } from 'svelte';

export type OpcionDock = { valor: string; texto: string; icono: string; insignia?: string | null };

export type Anfitrion =
  | {
      donde: 'aparato';
      restaurante: string;
      linea: string; // «Lupita · Caja»
      pestanas: OpcionDock[];
      pestana: string;
      alPestana: (valor: string) => void;
    }
  | { donde: 'panel'; alInicio: () => void; sucursal?: Snippet };
