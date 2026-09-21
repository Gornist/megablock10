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
-- факт правки. Доставка once-and-forget: помечаем delivered при первой же
-- отдаче в ответе устройству, без ack от клиента, что он применил —
-- симметрично остальным упрощениям в этом проекте (см. admin-web/README.md).
CREATE TABLE IF NOT EXISTS master_pending (
  change_id   TEXT PRIMARY KEY,
  subject_key TEXT NOT NULL,
  delivered   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_master_pending_subject ON master_pending (subject_key, delivered);

-- masters/sessions/audit_master — см. lib/auth.ts (ensureAuthSchema),
-- появились позже основной схемы, вынесены отдельно, чтобы не мешать
-- auth-логику с моделью данных игры.
`;

export type Db = Database.Database;

export function openDb(path: string): Db {
  mkdirSync(dirname(path), { recursive: true });
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA);
  ensureAuthSchema(db);
  return db;
}
