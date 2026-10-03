import type { DisplayPushPhase, DisplayPushState } from "../apiTypes.js";

/**
 * Ход последней отправки картинки на каждую точку — для экрана (DisplayItem.push): очередь → соединение → отправка →
 * RECEIVED → DISPLAYED, повторы с причиной прошлой попытки. Только в памяти: после перезапуска сервера хода нет, есть
 * desired/displayed в БД. Новая отправка заменяет запись целиком; этапы старой (её ещё доделывает воркер) её не трогают.
 */
export class PushProgress {
  private readonly states = new Map<string, DisplayPushState>();

  get(displayId: string): DisplayPushState | null {
    return this.states.get(displayId) ?? null;
  }

  /** Картинка встала в очередь. */
  start(displayId: string, version: number, label: string, attempts: number): void {
    const now = Date.now();
    this.states.set(displayId, {
      version,
      label,
      phase: "QUEUED",
      attempt: 0,
      attempts,
      startedAt: now,
      updatedAt: now,
      error: null,
      failedAt: null,
      retryAt: null,
    });
  }

  /** Этап отправки — только если это та же отправка (новая картинка уже заняла место — её не трогать). */
  phase(displayId: string, version: number, phase: DisplayPushPhase, patch: Partial<DisplayPushState> = {}): void {
    const p = this.states.get(displayId);
    if (!p || p.version !== version) return;
    if ((phase === "RETRY" || phase === "FAILED") && p.phase !== "RETRY" && p.phase !== "FAILED") p.failedAt = p.phase;
    // Причина прошлой попытки остаётся видна, пока идёт следующая («попытка 2 из 3: нет ответа»); успех её стирает.
    Object.assign(p, patch, { phase, updatedAt: Date.now() }, phase === "DISPLAYED" ? { error: null, failedAt: null } : {});
  }

  /** Точка показывает версию новее — отправка уйдёт под номером выше; ход остаётся тем же. */
  renumber(displayId: string, from: number, to: number): void {
    const p = this.states.get(displayId);
    if (p && p.version === from) p.version = to;
  }

  forget(displayId: string): void {
    this.states.delete(displayId);
  }
}
