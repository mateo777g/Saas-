// Los ingredientes de una sucursal en vivo (inventario, 19 nov 2026): los lee al empezar, con cada cambio del tiempo
// real (cada cuenta que se cierra mueve la existencia) y al volver a la pestaña. Vive encima de las vistas, como la
// vigía de Pedidos, para que el numerito de «Inventario» salga en cualquiera: en el panel del gerente (barra lateral) y
// en el aparato de la cocina (su pestaña). La vista Inventario y la pestaña de la cocina leen de aquí su tabla.
// Solo la arranca quien puede leer los ingredientes: el gerente y la cocina (la caja no).
import type { SupabaseClient } from '@supabase/supabase-js';
import { cuantosSeAcaban, leerIngredientes, type Ingrediente } from './inventario';
import { escuchar } from './pos';

export class VigiaInventario {
  ingredientes = $state<Ingrediente[] | null>(null);
  error = $state<unknown>(null);
  acaban = $derived(this.ingredientes ? cuantosSeAcaban(this.ingredientes) : 0);
  // El numerito: cuántos se acaban o se acabaron; sin ninguno, nada.
  insignia = $derived(this.acaban > 0 ? String(this.acaban) : undefined);

  #cliente: SupabaseClient;
  #restauranteId: string;
  #leyendo: Promise<void> | null = null;
  #otraVez = false;
  #reloj: ReturnType<typeof setTimeout> | undefined;

  constructor(cliente: SupabaseClient, restauranteId: string) {
    this.#cliente = cliente;
    this.#restauranteId = restauranteId;
  }

  // Lee ya; si ya estaba leyendo, una vez más al terminar. Si falla, se queda lo que había (y su error).
  async leer(): Promise<void> {
    if (this.#leyendo) {
      this.#otraVez = true;
      return this.#leyendo;
    }
    this.#leyendo = (async () => {
      do {
        this.#otraVez = false;
        try {
          this.ingredientes = await leerIngredientes(this.#cliente, this.#restauranteId);
          this.error = null;
        } catch (falla) {
          console.error('[inventario] no se pudieron leer los ingredientes; se queda lo que había:', falla);
          this.error = falla;
        }
      } while (this.#otraVez);
    })();
    try {
      await this.#leyendo;
    } finally {
      this.#leyendo = null;
    }
  }

  // Una cuenta que se cierra mueve varios ingredientes a la vez: se juntan sus avisos y se lee una vez.
  #programar = () => {
    clearTimeout(this.#reloj);
    this.#reloj = setTimeout(() => void this.leer(), 250);
  };

  // Regresa cómo dejar de vigilar.
  iniciar(): () => void {
    void this.leer();
    const dejar = escuchar(this.#cliente, this.#restauranteId, ['ingredientes'], this.#programar);
    const alVolver = () => {
      if (document.visibilityState === 'visible') this.#programar();
    };
    document.addEventListener('visibilitychange', alVolver);
    return () => {
      clearTimeout(this.#reloj);
      dejar();
      document.removeEventListener('visibilitychange', alVolver);
    };
  }
}
