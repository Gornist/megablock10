import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { ensureAuthSchema } from "../lib/auth.js";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS changes (
  id           TEXT PRIMARY KEY,
  subject_key  TEXT NOT NULL,
  seq          INTEGER NOT NULL,
  happened_at  INTEGER NOT NULL,
  received_at  INTEGER NOT NULL,
  field        TEXT NOT NULL,
  old_value    TEXT,
  new_value    TEXT,
  reason       TEXT NOT NULL,
  source_ref   TEXT,
  actor        TEXT NOT NULL,
  signature    TEXT NOT NULL,
  UNIQUE (subject_key, seq)
);
CREATE INDEX IF NOT EXISTS idx_changes_subject_seq ON changes (subject_key, seq);
CREATE INDEX IF NOT EXISTS idx_changes_happened_at ON changes (happened_at);
CREATE INDEX IF NOT EXISTS idx_changes_reason ON changes (reason);
CREATE INDEX IF NOT EXISTS idx_changes_source_ref ON changes (source_ref);
-- overview/аналитика/тревоги фильтруют по field + времени, а лента и "на связи" — по received_at.
CREATE INDEX IF NOT EXISTS idx_changes_field_happened ON changes (field, happened_at);
CREATE INDEX IF NOT EXISTS idx_changes_received_at ON changes (received_at);
-- projectAll читает всю историю в порядке (игрок, время) — без этого индекса это сортировка сотен тысяч строк.
CREATE INDEX IF NOT EXISTS idx_changes_subject_received ON changes (subject_key, received_at, seq);
CREATE INDEX IF NOT EXISTS idx_changes_field_received ON changes (field, received_at);

-- Игроки "под наблюдением" — общий для всех мастеров список с пометкой.
CREATE TABLE IF NOT EXISTS watchlist (
  subject_key TEXT PRIMARY KEY,
  note        TEXT NOT NULL DEFAULT '',
  added_by    TEXT NOT NULL,
  added_at    INTEGER NOT NULL
);

-- Пульс игры: снимок метрик раз в минуту (lib/pulse.ts). Хранится в БД, а не в памяти, чтобы картину можно было листать назад и разбирать постфактум.
CREATE TABLE IF NOT EXISTS pulse_samples (
  t    INTEGER PRIMARY KEY,
  data TEXT NOT NULL
);

-- Тревоги, которые мастер отложил («знаю, не мешай»): id тревоги из lib/attention.ts и до какого времени молчать.
CREATE TABLE IF NOT EXISTS attention_snooze (
  item_id TEXT PRIMARY KEY,
  until   INTEGER NOT NULL
);

-- Выданные мастером QR персонажа (lib/provisions.ts): параметры выдачи, к какому ключу привязан код (первый телефон, приславший
-- CHARACTER_CREATED с source_ref = id), и связь «повторной выдачи» с прежним ключом.
CREATE TABLE IF NOT EXISTS provisions (
  id           TEXT PRIMARY KEY,
  callsign     TEXT NOT NULL,
  faction      TEXT NOT NULL,
  balance      INTEGER NOT NULL,
  ram          INTEGER NOT NULL,
  created_by   TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  replaces_key TEXT,
  bound_key    TEXT,
  bound_at     INTEGER,
  void         INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_provisions_bound ON provisions (bound_key);
CREATE INDEX IF NOT EXISTS idx_provisions_replaces ON provisions (replaces_key);
-- Ключ, чей персонаж перевыдан на другой телефон: в сводках не считается (иначе остаточный баланс удвоит эмиссию).
CREATE TABLE IF NOT EXISTS replaced_keys (
  old_key TEXT PRIMARY KEY,
  new_key TEXT NOT NULL,
  at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_replaced_new ON replaced_keys (new_key);
-- Код персонажа, который попытались применить на втором телефоне (копия QR): по строке на пару (код, ключ) — для тревоги.
CREATE TABLE IF NOT EXISTS provision_conflicts (
  provision_id TEXT NOT NULL,
  key          TEXT NOT NULL,
  at           INTEGER NOT NULL,
  PRIMARY KEY (provision_id, key)
);

-- Снимка Character нет по решению: он всегда пересчитывается SQL-агрегатом
-- по changes на чтение, а не поддерживается построчно (см. обсуждение объёма
-- работ — так рассинхронизироваться нечему).

CREATE TABLE IF NOT EXISTS containers (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  tier          TEXT NOT NULL,
  owner_faction TEXT,
  slots_json    TEXT NOT NULL,
  updated_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS slot_claims (
  slot_ref        TEXT NOT NULL,
  claimant_key    TEXT NOT NULL,
  claimed_at      INTEGER NOT NULL,
  granted_by      TEXT NOT NULL,
  revoked         INTEGER NOT NULL DEFAULT 0,
  revoked_by      TEXT,
  revoked_reason  TEXT,
  PRIMARY KEY (slot_ref, claimant_key)
);

-- Очередь доставки MASTER_OVERRIDE на устройство игрока (§6.3 ТЗ). change_id
-- ссылается на changes.id той же записи, что уже видна в истории на
-- дашборде — эта таблица только про "долетело ли до телефона", не про сам
-- факт правки. delivered = 1 — только когда устройство подтвердило, что
-- применило правку (ackIds); отказ устройства (failures) считается в attempts
-- (миграция 2), после нескольких или неустранимого — failed_at, и правку
-- больше не шлют (см. lib/changeIngest.ts).
CREATE TABLE IF NOT EXISTS master_pending (
  change_id   TEXT PRIMARY KEY,
  subject_key TEXT NOT NULL,
  delivered   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_master_pending_subject ON master_pending (subject_key, delivered);

-- Электронные QR-дисплеи (ESP32 + e-paper, docs/displays.md; код — displays/). id — логическое имя устройства, ip/port —
-- транспортный адрес, не смешиваются. secret — ключ HMAC в hex: не хэш, потому что сервер им подписывает кадры, а хэшем
-- подписать нельзя; наружу через API не отдаётся (только один раз при создании/смене). desired_* — что мастер велел показать
-- (строка QR и версия), displayed_version — что дисплей подтвердил (DISPLAYED или HELLO); расхождение — «не дошло».
CREATE TABLE IF NOT EXISTS displays (
  id                TEXT PRIMARY KEY,
  name              TEXT NOT NULL,
  ip                TEXT NOT NULL,
  port              INTEGER NOT NULL,
  width             INTEGER NOT NULL,
  height            INTEGER NOT NULL,
  enabled           INTEGER NOT NULL DEFAULT 1,
  secret            TEXT NOT NULL,
  hardware_id       TEXT,
  fw_version        TEXT,
  battery_mv        INTEGER,
  rssi              INTEGER,
  last_seen_at      INTEGER,
  last_connected_at INTEGER,
  last_error        TEXT,
  last_error_at     INTEGER,
  desired_version   INTEGER NOT NULL DEFAULT 0,
  desired_qr        TEXT,
  desired_label     TEXT,
  displayed_version INTEGER,
  displayed_at      INTEGER,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL
);

-- Группы точек (локации): мастер раскладывает по ним дисплеи и звуковые точки (docs/sound-nodes.md); displays.group_id —
-- миграция 5. Удалённая группа не удаляет точки — они становятся «без группы».
CREATE TABLE IF NOT EXISTS display_groups (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- Звук точек (audio/, docs/sound-nodes.md): каналы — плейлисты треков с карты точки; клипы — объявления громкой связи
-- (IMA ADPCM WAV, id — sha256); желаемое и доложенное состояние звука — колонки displays и display_groups (миграция 6).
CREATE TABLE IF NOT EXISTS audio_channels (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  tracks     TEXT NOT NULL DEFAULT '[]',
  shuffle    INTEGER NOT NULL DEFAULT 1,
  gap_ms     INTEGER NOT NULL DEFAULT 2000,
  volume     INTEGER NOT NULL DEFAULT 60,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS audio_clips (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  data        BLOB NOT NULL,
  bytes       INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  preset      INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  created_by  TEXT
);

-- История заряда точек (displays/battery.ts): точка раз в DISPLAY_BATTERY_SAMPLE_MS из HELLO — по ней коллектор считает
-- «примерно сколько часов осталось». Хранится DISPLAY_BATTERY_KEEP_MS (4 суток), старое чистится при записи.
CREATE TABLE IF NOT EXISTS display_battery_samples (
  display_id TEXT NOT NULL,
  at         INTEGER NOT NULL,
  mv         INTEGER,
  pct        INTEGER,
  PRIMARY KEY (display_id, at)
);

-- «Сеть» (docs/netrun-world-records.md): допуск нетраннера. blocked ставит приём NET_FLATLINE или мастер, «пощадить» снимает —
-- коллектор источник правды, Мост читает флаг (bridge_synced = 0 — ещё не записан в документ runner Моста, lib/netRunners.ts).
-- runner_key — ключ игрока в base64, как subject_key в changes; в Мосте документ runner — r_<sha256 ключа> (lib/netRunners.ts).
CREATE TABLE IF NOT EXISTS net_runner_flags (
  runner_key       TEXT PRIMARY KEY,
  blocked          INTEGER NOT NULL DEFAULT 0,
  reason           TEXT,
  callsign         TEXT,
  session          TEXT,
  node             TEXT,
  terminal         TEXT,
  detail           TEXT,
  blocked_at       INTEGER,
  last_flatline_at INTEGER,
  spared_at        INTEGER,
  spared_by        TEXT,
  bridge_synced    INTEGER NOT NULL DEFAULT 0,
  updated_at       INTEGER NOT NULL
);

-- «Может входить в Сеть» — решение мастера по игроку (белый список, docs/netrun.md: в Сеть входят только нетраннеры). Мост проверяет его,
-- когда включено settings/global.require_allowed; по умолчанию выключено. Нет строки — мастер ещё не решал.
CREATE TABLE IF NOT EXISTS net_runner_access (
  runner_key TEXT PRIMARY KEY,
  allowed    INTEGER NOT NULL,
  updated_by TEXT,
  updated_at INTEGER NOT NULL
);

-- Настройки самого коллектора, которых нет в окружении и которые мастер правит из дашборда (получатель СБ по умолчанию и т. п.).
CREATE TABLE IF NOT EXISTS collector_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- «Сеть» → площадка (docs/netrun-world-records.md, §3): какая точка стоит у какого узла Сети и/или терминала — по этому коллектор
-- решает, КОМУ из точек идёт быстрое событие (Мост знает только узел и терминал). Это отдельно от displays.node_id: тот — узел
-- коллектора (контейнер из «Мастерской»), а node здесь — id узла в документе Моста (node_07).
CREATE TABLE IF NOT EXISTS net_point_links (
  display_id TEXT PRIMARY KEY,
  net_node   TEXT,
  terminal   TEXT
);
-- Что делает событие: проиграть клип громкой связи на подходящих точках. По умолчанию строк нет — события ничего не делают.
CREATE TABLE IF NOT EXISTS world_event_actions (
  kind    TEXT PRIMARY KEY,
  clip_id TEXT,
  volume  INTEGER,
  chime   INTEGER NOT NULL DEFAULT 1,
  enabled INTEGER NOT NULL DEFAULT 1
);

-- masters/sessions/audit_master — см. lib/auth.ts (ensureAuthSchema),
-- появились позже основной схемы, вынесены отдельно, чтобы не мешать
-- auth-логику с моделью данных игры.
`;

export type Db = Database.Database;

/**
 * Версия 1 — вся SCHEMA выше. До этой правки схема не версионировалась:
 * CREATE TABLE/INDEX IF NOT EXISTS сами по себе безопасны для повторного
 * применения на любой БД, поэтому отсутствие версии не подводило, пока
 * каждое изменение схемы было только новой таблицей (см. git-историю —
 * ALTER TABLE тут не было ни разу). MIGRATIONS — на случай, когда
 * IF NOT EXISTS не спасает: ALTER TABLE ADD COLUMN, смена типа столбца,
 * перекладка данных и т. п. Экспортируется в приложение только через
 * openDb/runMigrations — ensureAuthSchema (masters/sessions/audit_master)
 * намеренно остаётся отдельной, независимой от игровой схемы (см. её
 * комментарий в auth.ts).
 */
export const BASELINE_VERSION = 1;

export interface Migration {
  /** Обязательно baselineVersion + 1, + 2, ... по порядку — без пропусков и дублей, проверяется validateMigrationSequence. */
  version: number;
  /** Синхронная — better-sqlite3 весь и так синхронный; оборачивается в db.transaction для атомарности "несколько операторов сразу". */
  migrate: (db: Db) => void;
}

/** ALTER TABLE ADD COLUMN, если такой колонки ещё нет: миграция переживает повторный прогон (прерванный или по сброшенной версии). */
function addColumnIfMissing(db: Db, table: string, column: string, definition: string): void {
  const columns = db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
  if (!columns.some((c) => c.name === column)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}

// Следующее изменение существующей таблицы (не просто новая таблица — под неё IF NOT EXISTS в SCHEMA по-прежнему достаточно)
// добавляется сюда новым элементом, а не правкой SCHEMA задним числом.
const MIGRATIONS: Migration[] = [
  {
    // Правка мастера, которую телефон не смог применить: сколько раз пытался, последняя причина и когда сервер перестал её слать
    // (failed_at). Раньше телефон подтверждал и неприменённую правку — она пропадала молча (см. lib/changeIngest.ts, reportFailures).
    version: 2,
    migrate: (db) => {
      addColumnIfMissing(db, "master_pending", "attempts", "INTEGER NOT NULL DEFAULT 0");
      addColumnIfMissing(db, "master_pending", "last_error", "TEXT");
      addColumnIfMissing(db, "master_pending", "failed_at", "INTEGER");
    },
  },
  {
    // Где правка мастера встала в хронологии телефона: его последний seq в момент применения (подтверждение, appliedAtSeq).
    // По нему свёртка ставит правку между записями устройства, а не по времени прихода на сервер (см. lib/projection.ts).
    version: 3,
    migrate: (db) => addColumnIfMissing(db, "master_pending", "applied_at_seq", "INTEGER"),
  },
  {
    // Заряд точки от топливомера MAX17048 (docs/sound-nodes.md, «Батарея»): процент и скорость, % в час (минус — разряд).
    // Без топливомера точка шлёт только battery_mv, процент считает сервер (displays/battery.ts).
    version: 4,
    migrate: (db) => {
      addColumnIfMissing(db, "displays", "battery_pct", "INTEGER");
      addColumnIfMissing(db, "displays", "battery_rate", "REAL");
    },
  },
  {
    // Группа точки (display_groups, локация): коллектор показывает точки сворачивающимися группами.
    version: 5,
    migrate: (db) => addColumnIfMissing(db, "displays", "group_id", "TEXT"),
  },
  {
    // Звук (docs/sound-nodes.md): канал и громкость группы; у точки — роли из HELLO, исключения канала и громкости, желаемое
    // состояние с версией, доложенное в HELLO и каталог треков на карте.
    version: 6,
    migrate: (db) => {
      addColumnIfMissing(db, "display_groups", "audio_channel_id", "TEXT");
      addColumnIfMissing(db, "display_groups", "audio_volume", "INTEGER");
      addColumnIfMissing(db, "displays", "roles", "TEXT");
      addColumnIfMissing(db, "displays", "audio_channel_id", "TEXT");
      addColumnIfMissing(db, "displays", "audio_volume", "INTEGER");
      addColumnIfMissing(db, "displays", "audio_version", "INTEGER NOT NULL DEFAULT 0");
      addColumnIfMissing(db, "displays", "audio_state", "TEXT");
      addColumnIfMissing(db, "displays", "audio_reported", "TEXT");
      addColumnIfMissing(db, "displays", "audio_catalog", "TEXT");
    },
  },
  {
    // Точка ↔ узел (контейнер): узел в мире и есть точка с QR-дисплеем и звуком. NULL — точка без узла (динамик в баре).
    version: 7,
    migrate: (db) => addColumnIfMissing(db, "displays", "node_id", "TEXT"),
  },
];

/** Версия схемы после всех миграций. */
export const CURRENT_VERSION = BASELINE_VERSION + MIGRATIONS.length;

/** Вынесена из runMigrations как чистая функция — юнит-тестируется отдельно, без реальной БД (см. dbMigrations.test.ts). */
export function validateMigrationSequence(migrations: Pick<Migration, "version">[], baselineVersion: number): void {
  migrations.forEach((m, i) => {
    const expected = baselineVersion + 1 + i;
    if (m.version !== expected) {
      throw new Error(`db migrations must be a contiguous sequence starting at ${baselineVersion + 1}: expected version ${expected} at index ${i}, got ${m.version}`);
    }
  });
}

/** SCHEMA (idempotent) + миграции, каждая ровно один раз, по возрастанию версии — отслеживается через PRAGMA user_version. */
export function runMigrations(db: Db): void {
  validateMigrationSequence(MIGRATIONS, BASELINE_VERSION);
  db.exec(SCHEMA);
  let version = db.pragma("user_version", { simple: true }) as number;
  if (version < BASELINE_VERSION) {
    db.pragma(`user_version = ${BASELINE_VERSION}`);
    version = BASELINE_VERSION;
  }
  for (const migration of MIGRATIONS) {
    if (migration.version <= version) continue;
    db.transaction(() => {
      migration.migrate(db);
      db.pragma(`user_version = ${migration.version}`);
    })();
    version = migration.version;
  }
}

export function openDb(path: string): Db {
  mkdirSync(dirname(path), { recursive: true });
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  runMigrations(db);
  ensureAuthSchema(db);
  return db;
}
