import type { DisplayItem, DisplayPushResult, DisplayStatus } from "../../api/types";

/** Что показать: контейнер из справочника (QR собирает сервер) или готовая строка MB10-QR (шард, RAM). */
export type DisplaySource = { type: "container"; id: string } | { type: "qr"; qr: string; label?: string };

export const STATUS_LABEL: Record<DisplayStatus, string> = {
  ONLINE: "на связи",
  OFFLINE: "нет связи",
  UPDATING: "обновляется",
  ERROR: "ошибка",
  DISABLED: "выключен",
};

export const STATUS_TONE: Record<DisplayStatus, "ok" | "danger" | "warn" | "accent" | "neutral"> = {
  ONLINE: "ok",
  OFFLINE: "neutral",
  UPDATING: "accent",
  ERROR: "danger",
  DISABLED: "neutral",
};

export type PushProgress = { state: "sending" | "shown" | "failed" | "superseded"; text: string };

/**
 * Где сейчас отправка на один дисплей — по ответу на отправку и живому списку дисплеев: показан (дисплей подтвердил версию не ниже
 * отправленной), в работе (версия ещё в очереди сервера), не удалось (очередь пуста, а версия не показана — причина в lastError).
 */
export function pushProgress(result: DisplayPushResult, display: DisplayItem | undefined): PushProgress {
  if (!result.ok && result.outcome !== "SUPERSEDED") return { state: "failed", text: result.error ?? "не удалось" };
  if (result.outcome === "SUPERSEDED") return { state: "superseded", text: "заменён более новой отправкой" };
  const version = result.version ?? 0;
  if (!display) return { state: "failed", text: "дисплей удалён" };
  if ((display.displayedVersion ?? 0) >= version) return { state: "shown", text: `показан (v${display.displayedVersion})` };
  // Список ещё с прошлого опроса — сервер уже принял отправку, а мы её не видим.
  if ((display.desiredVersion ?? 0) < version) return { state: "sending", text: "отправляется…" };
  // Сервер мог перенумеровать версию выше (дисплей оказался впереди) — тогда в очереди уже она.
  const queued = [display.activeVersion, display.pendingVersion].some((v) => v !== null && v >= version);
  if (queued || (result.outcome === "QUEUED" && display.status === "UPDATING")) return { state: "sending", text: "отправляется…" };
  if ((display.desiredVersion ?? 0) > version) return { state: "superseded", text: "заменён более новой отправкой" };
  return { state: "failed", text: display.lastError ?? "не подтвердил показ" };
}

/** 1 px на модуль — телефону на пределе; 2 — читается вблизи. Порог — чтобы мастер проверил телефоном до игры. */
export function scaleWarning(scale: number): string | null {
  if (scale <= 1) return "1 пиксель на модуль — телефон, скорее всего, не прочтёт. Уменьшите число слотов или возьмите панель крупнее.";
  if (scale === 2) return "2 пикселя на модуль — читается только вблизи; проверьте телефоном на месте.";
  return null;
}
