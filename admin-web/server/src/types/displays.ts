import type { DisplayAudio } from "./audio.js";

// ── Электронные QR-дисплеи (docs/displays.md) ──

/** DISABLED — выключен мастером; UPDATING — идёт отправка или ждёт очередь; ERROR — последняя операция не удалась; ONLINE/OFFLINE — по последнему HELLO. */
export type DisplayStatus = "ONLINE" | "OFFLINE" | "UPDATING" | "ERROR" | "DISABLED";

export type BatteryLevel = "OK" | "LOW" | "CRITICAL";

export interface DisplayItem {
  id: string;
  name: string;
  ip: string;
  port: number;
  width: number;
  height: number;
  enabled: boolean;
  status: DisplayStatus;
  /** Аппаратный id (MAC) из HELLO. */
  hardwareId: string | null;
  fwVersion: string | null;
  batteryMv: number | null;
  /** Группа (локация) — DisplayGroup.id; null — без группы. */
  groupId: string | null;
  /** Узел (контейнер), которым точка стоит в мире — NodeSummary.id; null — без узла (просто динамик в локации). */
  nodeId: string | null;
  /** Что умеет точка (из HELLO): "display", "audio". */
  roles: string[];
  /** Звук точки; null — точка без звука. */
  audio: DisplayAudio | null;
  /** Уровень: по проценту, остатку в часах и (без топливомера) напряжению — пороги DISPLAY_BATTERY_*. */
  battery: BatteryLevel | null;
  /** Заряд, %: от топливомера или по напряжению (batterySource). null — точка не шлёт заряд. */
  batteryPct: number | null;
  batterySource: "gauge" | "voltage" | null;
  /** Примерно сколько часов осталось — по истории заряда; null — не разряжается заметно или данных пока мало. */
  batteryHoursLeft: number | null;
  batteryCharging: boolean;
  rssi: number | null;
  lastSeenAt: number | null;
  lastConnectedAt: number | null;
  lastError: string | null;
  lastErrorAt: number | null;
  /** Что мастер велел показать: версия и подпись («контейнер Насосная-4»); null — ещё ничего не отправляли. */
  desiredVersion: number | null;
  desiredLabel: string | null;
  /** Что дисплей подтвердил (DISPLAYED или HELLO). Меньше desiredVersion — последняя отправка не дошла. */
  displayedVersion: number | null;
  displayedAt: number | null;
  /** Очередь сервера на этот дисплей: версия в отправке и следующая ждущая (не больше одной — промежуточные отбрасываются). */
  activeVersion: number | null;
  pendingVersion: number | null;
  /** Ход последней отправки картинки (с момента запуска сервера); null — отправок не было. */
  push: DisplayPushState | null;
}

/**
 * Этап отправки картинки на дисплей: QUEUED — ждёт очереди или лимита соединений; CONNECTING — TCP и HELLO; SENDING — кадр
 * передаётся; RECEIVED — дисплей принял и проверил кадр (длина, CRC, подпись), пишет во flash и обновляет e-paper; DISPLAYED —
 * на экране; RETRY — попытка не удалась, следующая по таймеру; FAILED — попытки кончились; SUPERSEDED — обогнала более новая.
 */
export type DisplayPushPhase = "QUEUED" | "CONNECTING" | "SENDING" | "RECEIVED" | "DISPLAYED" | "RETRY" | "FAILED" | "SUPERSEDED";

export interface DisplayPushState {
  /** Версия картинки (может вырасти, если дисплей показывал более новую — сервер перенумеровал). */
  version: number;
  label: string;
  phase: DisplayPushPhase;
  /** Номер текущей попытки (1…attempts); 0 — ещё не начиналась. */
  attempt: number;
  attempts: number;
  startedAt: number;
  updatedAt: number;
  /** Причина последней неудачной попытки (RETRY/FAILED). */
  error: string | null;
  /** На каком этапе оборвалась последняя неудачная попытка (CONNECTING, SENDING или RECEIVED). */
  failedAt: DisplayPushPhase | null;
  /** RETRY: когда следующая попытка. */
  retryAt: number | null;
}

/** Группа точек (локация): дисплеи и звуковые точки раскладываются по ним в коллекторе. */
export interface DisplayGroup {
  id: string;
  name: string;
  /** Сколько точек в группе. */
  count: number;
  /** Фон группы: канал (null — тишина) и громкость (null — как у канала). */
  audioChannelId: string | null;
  audioVolume: number | null;
}
