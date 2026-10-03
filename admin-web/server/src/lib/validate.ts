/** Проверки тела запроса, общие для маршрутов точек и звука (routes/displays.ts, routes/audio.ts). */

/** Целое в [min, max]. */
export function intIn(v: unknown, min: number, max: number): v is number {
  return Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
}

/** Массив строк — или null, если это не он. */
export function strings(v: unknown): string[] | null {
  return Array.isArray(v) && v.every((x) => typeof x === "string") ? (v as string[]) : null;
}
