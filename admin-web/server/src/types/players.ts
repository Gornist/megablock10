// ── Игроки ──

export interface PlayerListItem {
  publicKeyB64: string;
  callsign: string;
  faction: string;
  ramCapacity: number;
  balance: number;
  daemonCount: number;
  shardsByTier: Record<string, number>;
  breaches: { success: number; partial: number; fail: number };
  slotsClaimed: number;
  lastSeenAt: number;
  online: boolean;
  /** Версия приложения и протоколов по последнему heartbeat; нет — телефон не сообщал (старая сборка или сервер перезапускался). */
  appVersion?: string;
  wireVersions?: Record<string, number>;
  /** Очередь неотправленных записей на телефоне по последнему heartbeat: телефон на связи, но синхронизация может застрять. */
  pendingCount?: number;
  oldestPendingAgeMs?: number;
  /** Сессия сброшена на телефоне — устройство свободно; в сводках такой игрок не считается. */
  sessionResetAt: number | null;
  /** Ключ нового телефона, на который персонаж перевыдан; такой (прежний) ключ в сводках не считается. */
  replacedBy: string | null;
  /** Прежний ключ, чей персонаж выдан этому телефону (ссылка «предыдущая сессия»). */
  replaces: string | null;
}

export interface DaemonEntry {
  daemonId: string;
  name: string;
  tier: string;
  weight: number;
  acquiredAt: number;
  sourceRef: string | null;
}

export interface ShardEntry {
  shardId: string;
  title: string;
  tier: string;
  decrypted: boolean;
  acquiredAt: number;
  sourceRef: string | null;
}

export interface Counters {
  breaches: Record<string, { success: number; partial: number; fail: number }>;
  slotsClaimed: number;
  alertsSent: number;
  alertsSuppressed: number;
  breachesBlocked: Record<string, number>;
}

export interface CharacterSnapshot {
  publicKeyB64: string;
  callsign: string;
  faction: string;
  ramCapacity: number;
  balance: number;
  daemons: DaemonEntry[];
  shards: ShardEntry[];
  counters: Counters;
  lastSeenAt: number;
  lastSeq: number;
  /** Когда игрок сбросил сессию на телефоне (устройство свободно, персонаж остаётся у мастера); null — не сбрасывал. */
  sessionResetAt: number | null;
  /** Ссылки повторной выдачи; заполняет GET /api/players/:key (сама свёртка истории о них не знает). */
  replacedBy?: string | null;
  replaces?: string | null;
}

/** Как выбрать адресатов массовой правки/рассылки — ровно один способ (см. lib/masterRecords.ts). */
export type TargetSelector = { keys: string[] } | { faction: string } | { all: true };

export interface BulkPreview {
  dryRun: boolean;
  target: string;
  count: number;
  unchanged: number;
  changes?: { publicKeyB64: string; callsign: string; oldValue: string | null; newValue: string }[];
}

export interface WatchItem {
  publicKeyB64: string;
  note: string;
  addedAt: number;
  addedBy: string;
}
