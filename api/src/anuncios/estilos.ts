// Los estilos cuyo prompt ya vive en el Worker, por su clave (la misma de la tabla estilos). A Don
// Chuy solo le sale un estilo prendido en el panel de Fragmentless que además esté aquí.
import { anatomia } from './anatomia';
import { banderitas } from './banderitas';
import { barda } from './barda';
import { clasico } from './clasico';
import { comboEnMano } from './comboEnMano';
import type { Estilo } from './comun';
import { cuadros } from './cuadros';
import { desayunos } from './desayunos';
import { diaDeMuertos } from './diaDeMuertos';
import { diagonal } from './diagonal';
import { explosion } from './explosion';
import { futbol } from './futbol';
import { halloween } from './halloween';
import { estrella } from './estrella';
import { estrellas } from './estrellas';
import { letraGigante } from './letraGigante';
import { mano } from './mano';
import { menuDeCafe } from './menuDeCafe';
import { minimalista } from './minimalista';
import { navidad } from './navidad';
import { palabraRepetida } from './palabraRepetida';
import { palabraVertical } from './palabraVertical';
import { promo } from './promo';
import { ranura } from './ranura';
import { reflector } from './reflector';

const TODOS: Estilo[] = [clasico, letraGigante, anatomia, explosion, promo, futbol, navidad, diaDeMuertos, halloween, desayunos, minimalista, estrella, mano, estrellas, palabraRepetida, reflector, diagonal, menuDeCafe, palabraVertical, ranura, comboEnMano, banderitas, barda, cuadros];

export const ESTILOS: ReadonlyMap<string, Estilo> = new Map(TODOS.map((e) => [e.clave, e]));
