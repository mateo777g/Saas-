// El chip de la carta en la caja del Agente IA (lib/carta.ts, CartasDelMes): su esqueleto mientras Postgres dice
// cuántas quedan, cuántas quedan, o «sin_saber» si no se pudo leer (se deja mandar: el Worker vuelve a revisar).
export type ChipCarta = 'cargando' | 'sin_saber' | { quedan: number; de: number; vuelve: string };
