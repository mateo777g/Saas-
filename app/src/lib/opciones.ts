// Cómo se dice en pantalla cuántas opciones se eligen de un grupo (maqueta de Opciones y áreas
// GhrEVWPmevfBZtWzi4exKi). Solo pasa a palabras el mínimo y el máximo que guardó Postgres. Donde
// la maqueta dice «Pepe elige», la app habla sin nombre: Pepe era el mesero de ejemplo.

// La columna «Cómo se elige»: «Obligatorio · elige 1», «Opcional · hasta 3», «Obligatorio · de 1 a 3».
export function regla(minimo: number, maximo: number): string {
  if (minimo === 0) return maximo === 1 ? 'Opcional · solo 1' : `Opcional · hasta ${maximo}`;
  if (minimo === maximo) return `Obligatorio · elige ${minimo}`;
  return `Obligatorio · de ${minimo} a ${maximo}`;
}

// La de las pastillas de la ventana del producto y la lista de Agregar grupo: «elige 1», «hasta 3».
export function reglaCorta(minimo: number, maximo: number): string {
  if (minimo === 0) return maximo === 1 ? 'opcional' : `hasta ${maximo}`;
  if (minimo === maximo) return `elige ${minimo}`;
  return `de ${minimo} a ${maximo}`;
}

// La frase debajo de Mínimo y Máximo en la ventana del grupo.
export function frase(minimo: number, maximo: number): string {
  if (minimo === 0) {
    return maximo === 1 ? 'Opcional: se puede elegir una o ninguna.' : `Opcional: se eligen hasta ${maximo}, o ninguna.`;
  }
  if (minimo === maximo) return minimo === 1 ? 'Obligatorio: se elige una.' : `Obligatorio: se eligen ${minimo}.`;
  return `Obligatorio: se eligen de ${minimo} a ${maximo}.`;
}
