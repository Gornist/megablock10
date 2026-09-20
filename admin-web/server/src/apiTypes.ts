/**
 * Типы ответов API — ЕДИНСТВЕННОЕ описание формы данных между сервером и
 * дашбордом. Сервер аннотирует ими то, что отдаёт, клиент (client/src/api/types.ts)
 * импортирует их отсюда, так что расхождение ловит компилятор, а не мастер на
 * живой игре. Файл только для типов: никаких значений и никаких импортов —
 * клиент собирается отдельно и не должен тянуть серверный код.
 */

// ── Обзор и лента ──

/** Строка таблицы changes как она лежит в БД (snake_case) — так её отдают ручки истории и ленты. */
export interface StoredChangeRow {
  id: string;
  subject_key: string;
  seq: number;
  happened_at: number;
  received_at: number;
  field: string;
  old_value: string | null;
  new_value: string | null;
  reason: string;
  source_ref: string | null;
  actor: string;
  signature: string;
}

export interface Overview {
  players: { online: number; total: number };
  breachesLastHour: { success: number; partial: number; fail: number };
  slots: { claimed: number; printed: number };
  alerts: { sent: number; suppressed: number };
}

export type ChangeKind = "money" | "item" | "breach" | "alert" | "master" | "system";

/** Человекочитаемая часть записи изменения — собирает сервер (lib/humanize.ts); сырые поля остаются рядом для «деталей». */
export interface HumanChange {
  kind: ChangeKind;
  /** Чья запись (позывной или укороченный ключ). */
  subject: string;
  /** Что произошло, без подлежащего — для истории игрока; в ленте перед ним ставится subject. */
  body: string;
}

export type ChangeRow = StoredChangeRow & { human?: HumanChange };

export interface EventsResponse {
  total: number;
  page: number;
  pageSize: number;
  records: ChangeRow[];
}

export interface Meta {
  reasons: { code: string; label: string }[];
  kinds: { code: string; label: string }[];
}

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

// ── Узлы и тиражи ──

export interface NodeSummary {
  id: string;
  name: string;
  tier: string;
  ownerFaction: string | null;
  slotsTotal: number;
  slotsClaimed: number;
  breaches: { success: number; partial: number; fail: number };
  uniquePlayers: number;
  alertsSent: number;
  alertsSuppressed: number;
  lastBreachAt: number | null;
  /** Есть только в списке /api/nodes: зависит от текущего времени, поэтому считается поверх кэша. */
  breachesLastHour?: number;
}

export interface NodeDetail extends NodeSummary {
  breachers: { actor: string; lastAt: number; n: number }[];
  timeline: { t: number; success: number; partial: number; fail: number }[];
}

export interface SlotRegistryItem {
  slotRef: string;
  containerId: string;
  containerName: string;
  type: string;
  tier: string;
  title: string;
  copiesTotal: number;
  copiesClaimed: number;
  claimants: { claimantKeyB64: string; claimantName?: string; claimedAt: number }[];
}

export interface Transfer {
  txId: string;
  from: string;
  to: string;
  fromName?: string;
  toName?: string;
  amount: number;
  sentAt: number | null;
  confirmedAt: number | null;
  cancelledAt: number | null;
  oneSided: boolean;
}

// ── Аналитика и подсказки ──

export type Severity = "crit" | "warn" | "info";

export interface AttentionItem {
  id: string;
  kind: "negative_balance" | "balance_jump" | "went_silent" | "node_exhausted_hot" | "revoke_repeat" | "override_undelivered";
  severity: Severity;
  title: string;
  detail: string;
  subjectKey?: string;
  nodeId?: string;
  at: number;
}

export interface Attention {
  items: AttentionItem[];
  counts: { crit: number; warn: number; info: number };
}

export interface Economy {
  totalSupply: number;
  playersCounted: number;
  series: { t: number; supply: number }[];
  sources: { reason: string; label: string; total: number }[];
  transferVolume: number;
  distribution: { mean: number; median: number; p90: number; gini: number; negative: number };
  top: { publicKeyB64: string; callsign: string; faction: string; balance: number }[];
}

export interface FactionEvents {
  breachesOwn: number;
  breachesForeign: number;
  alertsSent: number;
  alertsSuppressed: number;
  alertsReceived: number;
}

export interface FactionRow extends FactionEvents {
  faction: string;
  players: number;
  online: number;
  totalBalance: number;
  avgBalance: number;
  daemons: number;
  shards: number;
  breaches: { success: number; partial: number; fail: number };
  slotsClaimed: number;
}

// ── Журнал и объявления ──

export interface AuditRecord {
  id: string;
  at: number;
  action: string;
  actionLabel: string;
  masterName: string;
  summary: string;
}

export interface AuditResponse {
  total: number;
  page: number;
  pageSize: number;
  actions: { action: string; label: string }[];
  records: AuditRecord[];
}

export interface AnnouncementItem {
  id: string;
  at: number;
  text: string;
  recipients: number;
  delivered: number;
  masterName: string;
}

export interface AnnouncementRecipient {
  publicKeyB64: string;
  callsign: string;
  delivered: boolean;
}
