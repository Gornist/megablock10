import type { DisplayItem, DisplayPushPhase, DisplayPushResult, DisplayPushState, DisplayStatus } from "../../api/types";

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

/**
 * sending — сервер ещё передаёт (очередь, подключение, передача, повтор); loaded — дисплей принял и проверил кадр, обновляет e-paper;
 * shown — на экране; failed — не дошло; superseded — обогнала более новая отправка.
 */
export type PushState = "sending" | "loaded" | "shown" | "failed" | "superseded";
export type PushProgress = {
  state: PushState;
  text: string;
  push?: DisplayPushState;
};

const PHASE_STATE: Record<DisplayPushPhase, PushState> = {
  QUEUED: "sending",
  CONNECTING: "sending",
  SENDING: "sending",
  RETRY: "sending",
  RECEIVED: "loaded",
  DISPLAYED: "shown",
  FAILED: "failed",
  SUPERSEDED: "superseded",
};

/** Этап отправки словами: «подключение (попытка 2 из 3)», «загружено — обновляется экран», «повтор через 3 с: …». */
export function phaseText(p: DisplayPushState, now = Date.now()): string {
  const attempt = p.attempt > 1 ? ` (попытка ${p.attempt} из ${p.attempts})` : "";
  switch (p.phase) {
    case "QUEUED":
      return "в очереди";
    case "CONNECTING":
      return `подключение${attempt}`;
    case "SENDING":
      return `передача кадра${attempt}`;
    case "RECEIVED":
      return "загружено — обновляется экран";
    case "DISPLAYED":
      return `отображено (v${p.version})`;
    case "RETRY": {
      const left = p.retryAt ? Math.max(0, Math.ceil((p.retryAt - now) / 1000)) : 0;
      return `повтор${left ? ` через ${left} с` : ""}: ${p.error ?? "нет ответа"}`;
    }
    case "FAILED":
      return p.error ?? "не удалось";
    case "SUPERSEDED":
      return "заменён более новой отправкой";
  }
}

export const PUSH_STEPS = ["Подключение", "Отправлено", "Загружено", "Отображено"] as const;

/** Сколько шагов PUSH_STEPS пройдено и какой идёт сейчас (-1 — никакой: итог или ошибка). */
export function pushStep(phase: DisplayPushPhase): {
  done: number;
  current: number;
} {
  switch (phase) {
    case "QUEUED":
    case "CONNECTING":
    case "RETRY":
      return { done: 0, current: 0 };
    case "SENDING":
      return { done: 1, current: 1 };
    case "RECEIVED":
      return { done: 2, current: 2 };
    case "DISPLAYED":
      return { done: 4, current: -1 };
    default:
      return { done: 0, current: -1 };
  }
}

/**
 * Где сейчас отправка на один дисплей — по ответу на отправку и живому списку дисплеев. Если сервер ведёт ход этой версии
 * (display.push) — по его этапу; иначе по версиям: показан (дисплей подтвердил версию не ниже отправленной), в работе (версия
 * ещё в очереди сервера), не удалось (очередь пуста, а версия не показана — причина в lastError).
 */
export function pushProgress(result: DisplayPushResult, display: DisplayItem | undefined, now = Date.now()): PushProgress {
  if (!result.ok && result.outcome !== "SUPERSEDED") return { state: "failed", text: result.error ?? "не удалось" };
  if (result.outcome === "SUPERSEDED") return { state: "superseded", text: "заменён более новой отправкой" };
  const version = result.version ?? 0;
  if (!display) return { state: "failed", text: "дисплей удалён" };
  if ((display.displayedVersion ?? 0) >= version)
    return {
      state: "shown",
      text: `отображено (v${display.displayedVersion})`,
      push: display.push ?? undefined,
    };
  const push = display.push;
  if (push && push.version === version) return { state: PHASE_STATE[push.phase], text: phaseText(push, now), push };
  // Список ещё с прошлого опроса — сервер уже принял отправку, а мы её не видим.
  if ((display.desiredVersion ?? 0) < version) return { state: "sending", text: "отправляется…" };
  // Сервер мог перенумеровать версию выше (дисплей оказался впереди) — тогда в очереди уже она.
  const queued = [display.activeVersion, display.pendingVersion].some((v) => v !== null && v >= version);
  if (queued || (result.outcome === "QUEUED" && display.status === "UPDATING")) return { state: "sending", text: "отправляется…" };
  if ((display.desiredVersion ?? 0) > version) return { state: "superseded", text: "заменён более новой отправкой" };
  return { state: "failed", text: display.lastError ?? "не подтвердил показ" };
}

/** Что сейчас на экране у дисплея — для макета в карточке: по ходу последней отправки или по версиям. */
export function screenState(d: DisplayItem): PushState | null {
  if (d.desiredVersion === null) return null;
  if (d.push && d.push.version === d.desiredVersion) return PHASE_STATE[d.push.phase];
  if ((d.displayedVersion ?? 0) >= d.desiredVersion) return "shown";
  return d.activeVersion !== null || d.pendingVersion !== null ? "sending" : "failed";
}

export const PUSH_TONE: Record<PushState, "ok" | "danger" | "warn" | "accent" | "neutral"> = {
  sending: "accent",
  loaded: "warn",
  shown: "ok",
  failed: "danger",
  superseded: "neutral",
};

/** 1 px на модуль — телефону на пределе; 2 — читается вблизи. Порог — чтобы мастер проверил телефоном до игры. */
export function scaleWarning(scale: number): string | null {
  if (scale <= 1) return "1 пиксель на модуль — телефон, скорее всего, не прочтёт. Уменьшите число слотов или возьмите панель крупнее.";
  if (scale === 2) return "2 пикселя на модуль — читается только вблизи; проверьте телефоном на месте.";
  return null;
}
