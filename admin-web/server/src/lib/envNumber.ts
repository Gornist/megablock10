/** Положительное число из переменной окружения, иначе значение по умолчанию (пусто, мусор, 0 и минус — «не задано»). */
export function positiveNumber(raw: string | undefined, fallback: number): number {
  return raw !== undefined && Number.isFinite(Number(raw)) && Number(raw) > 0 ? Number(raw) : fallback;
}
