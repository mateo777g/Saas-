// Buscar sin importar acentos ni mayúsculas: «cafe» encuentra «Café americano».
export function sinAcentos(texto: string): string {
  return texto.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
}
