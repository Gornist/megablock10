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

export type ChangeKind = "money" | "item" | "breach" | "alert" | "master" | "system" | "net";

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
  /** Получатель; null — перевод ещё не подтверждён получателем (в записи отправки его ключа нет). */
  to: string | null;
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
  kind: "negative_balance" | "balance_jump" | "went_silent" | "node_exhausted_hot" | "revoke_repeat" | "override_undelivered" | "override_failed" | "shard_copies" | "transfer_stuck" | "duplicate_receive" | "balance_chain_break" | "balance_unexplained" | "old_version" | "mass_silence" | "reject_spike" | "rate_limited" | "secret_denied" | "server_slow" | "clock_skew" | "transfer_amount_mismatch" | "emission_spike" | "player_outlier" | "provision_conflict" | "sync_stuck" | "display_battery";
  severity: Severity;
  title: string;
  detail: string;
  subjectKey?: string;
  nodeId?: string;
  /** Тревога про точку (QR-дисплей, звук): без nodeId ссылка ведёт на «Локации». */
  displayId?: string;
  at: number;
}

export interface Attention {
  items: AttentionItem[];
  /** Сколько тревог сейчас отложено мастером (в items их нет). */
  snoozed: number;
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

/** Снимок «пульса игры» за интервал (обычно минуту): что происходило на площадке и как чувствовал себя сервер. */
export interface PulseSample {
  t: number;
  online: number;
  /** Принятые записи и heartbeat-запросы за интервал. */
  records: number;
  heartbeats: number;
  /** Отклонённые записи по причинам: signature, malformed, unknown, seq, actor, other. */
  rejected: number;
  rejectedBy: Record<string, number>;
  rateLimited: number;
  secretDenied: number;
  requests: number;
  latencyAvgMs: number;
  latencyMaxMs: number;
  breaches: number;
  /** Выдано эдди наградами (взлом, шард, добыча). */
  eddies: number;
  transfers: number;
  /** Правок мастера, ещё не дошедших до устройств. */
  undelivered: number;
}

export interface Pulse {
  intervalMs: number;
  samples: PulseSample[];
}

/** Выданный QR персонажа. */
export interface ProvisionItem {
  id: string;
  callsign: string;
  faction: string;
  balance: number;
  ram: number;
  createdAt: number;
  createdBy: string;
  /** Ключ прежней сессии, которую этот код заменяет (повторная выдача). */
  replacesKey: string | null;
  replacesName: string | null;
  boundKey: string | null;
  boundName: string | null;
  boundAt: number | null;
  /** Погашен: перевыдан заново (или заменён более новым кодом). */
  void: boolean;
  /** Второй телефон пытался применить этот код. */
  conflicts: number;
}

export interface ProvisionsResponse {
  /** Что попадёт в QR из настроек сервера: адрес (откуда взят) и есть ли код игры. Сам код не отдаётся. */
  config: { url: string; urlSource: "env" | "request" | "none"; secretSet: boolean };
  items: ProvisionItem[];
}

export interface ProvisionQr {
  item: ProvisionItem;
  qr: string;
  qrImage: string;
}

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

// ── Звук (docs/sound-nodes.md) ──

/** Канал — плейлист треков с карты точки (имена файлов в /mb10/tracks). */
export interface AudioChannel {
  id: string;
  name: string;
  tracks: string[];
  shuffle: boolean;
  gapMs: number;
  volume: number;
}

/** Трек, доложенный точками (LIST): на скольких точках он есть. */
export interface AudioCatalogTrack {
  name: string;
  points: number;
}

/** Клип громкой связи (объявление или заготовка). */
export interface AudioClip {
  id: string;
  name: string;
  bytes: number;
  durationMs: number;
  preset: boolean;
  createdAt: number;
}

/**
 * Ход объявления на точке: QUEUED — ждёт очереди; UPLOADING — клип докачивается (uploadedPct); PLAYING — играет (с durationMs);
 * DONE — доиграло (подтверждено HELLO); STOPPED — прервано; FAILED — не дошло (error).
 */
export type AnnouncePhase = "QUEUED" | "UPLOADING" | "PLAYING" | "DONE" | "STOPPED" | "FAILED";

export interface AnnounceProgress {
  id: number;
  clipId: string;
  clipName: string;
  phase: AnnouncePhase;
  uploadedPct: number;
  durationMs: number | null;
  startedAt: number;
  playingSince: number | null;
  error: string | null;
}

export interface DisplayAudio {
  /** Что должно играть: канал (null — тишина), откуда (исключение точки / группа), громкость. */
  channelId: string | null;
  channelName: string | null;
  source: "override" | "group";
  volume: number;
  desiredVersion: number;
  /** Что точка доложила последним HELLO. */
  reportedVersion: number | null;
  applied: boolean;
  playing: string | null;
  reportedVolume: number | null;
  /** Треки канала, которых нет на карте точки. */
  missing: string[];
  tracksOnCard: number | null;
  sdOk: boolean | null;
  /** Исключения точки (null — как у группы; channel "" — тишина). */
  overrideChannelId: string | null;
  overrideVolume: number | null;
  announce: AnnounceProgress | null;
}

export interface AnnounceResponse {
  id: number;
  clipName: string;
  results: { displayId: string; ok: boolean; error?: string }[];
}

/** Ответ создания дисплея и смены секрета: секрет показывается только здесь, дальше его не отдаёт ни один запрос. */
export interface DisplaySecretResponse {
  display: DisplayItem;
  secret: string;
  /** Что прошить в дисплей (docs/displays.md, «Первичная настройка»): Wi-Fi вписывается руками, серверу он неизвестен. */
  provisioning: { id: string; secret: string; port: number; width: number; height: number };
}

/** Что уйдёт на дисплей: строка QR (та же, что для печати) и кадр как PNG. */
export interface DisplayPreview {
  qr: string;
  label: string;
  png: string;
  width: number;
  height: number;
  qrVersion: number;
  modules: number;
  /** Пикселей на модуль: 1–2 — телефон может не прочесть с обычного расстояния. */
  scale: number;
}

export type DisplayPushOutcome = "QUEUED" | "DISPLAYED" | "FAILED" | "SUPERSEDED";

export interface DisplayPushResult {
  displayId: string;
  ok: boolean;
  version?: number;
  outcome?: DisplayPushOutcome;
  error?: string;
}

export interface DisplayPushResponse {
  label: string;
  results: DisplayPushResult[];
}
