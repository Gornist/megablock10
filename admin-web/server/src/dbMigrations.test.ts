import { test } from "node:test";
import assert from "node:assert/strict";
import { BASELINE_VERSION, CURRENT_VERSION, runMigrations, validateMigrationSequence, type Migration } from "./db/index.js";
import { testDb } from "./testUtil.js";

/**
 * Инфраструктура версионируемых миграций (см. db/index.ts) — до этой правки
 * схема была одним CREATE TABLE/INDEX IF NOT EXISTS без PRAGMA user_version,
 * что безопасно только для новых таблиц. Здесь проверяем сам механизм:
 * baseline применяется один раз, повторный прогон — не более чем no-op, а
 * плохо сформированная последовательность версий ловится до того, как
 * что-либо тронет реальную БД.
 */

test("openDb (через testDb) поднимает user_version свежей БД до последней миграции", () => {
  const db = testDb();
  assert.equal(db.pragma("user_version", { simple: true }), CURRENT_VERSION);
  assert.ok(CURRENT_VERSION > BASELINE_VERSION);
});

test("миграция 2: у master_pending есть счётчик попыток, причина и отметка «не применилась»", () => {
  const db = testDb();
  const columns = (db.prepare(`PRAGMA table_info(master_pending)`).all() as { name: string }[]).map((c) => c.name);
  for (const c of ["attempts", "last_error", "failed_at"]) assert.ok(columns.includes(c), `нет колонки ${c}`);
});

test("свежая БД после runMigrations содержит таблицы из SCHEMA", () => {
  const db = testDb();
  const tables = db.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'`).all() as { name: string }[];
  const names = tables.map((t) => t.name);
  for (const expected of ["changes", "watchlist", "provisions", "containers", "slot_claims", "master_pending"]) {
    assert.ok(names.includes(expected), `таблица ${expected} должна существовать после runMigrations`);
  }
});

test("повторный runMigrations на уже смигрированной БД — no-op: версия не меняется, ошибок нет", () => {
  const db = testDb();
  const before = db.pragma("user_version", { simple: true });
  runMigrations(db);
  runMigrations(db);
  assert.equal(db.pragma("user_version", { simple: true }), before);
});

test("runMigrations поднимает БД с user_version=0 (как до появления версионирования) до последней версии, не трогая данные", () => {
  const db = testDb(); // уже последняя версия — имитируем "старую" базу без версии, откатив pragma вручную (миграции идемпотентны)
  db.pragma(`user_version = 0`);
  db.exec(`INSERT INTO watchlist (subject_key, note, added_by, added_at) VALUES ('pk-1', 'заметка', 'master-1', 1000)`);

  runMigrations(db);

  assert.equal(db.pragma("user_version", { simple: true }), CURRENT_VERSION);
  const row = db.prepare(`SELECT note FROM watchlist WHERE subject_key = 'pk-1'`).get() as { note: string };
  assert.equal(row.note, "заметка");
});

test("миграция применяется ровно один раз и поднимает user_version до своей версии", () => {
  const db = testDb();
  db.pragma(`user_version = ${BASELINE_VERSION}`); // проверяем механизм на локальной миграции, а не на списке проекта
  let calls = 0;
  const migration: Migration = {
    version: BASELINE_VERSION + 1,
    migrate: (d) => {
      calls += 1;
      d.exec(`ALTER TABLE watchlist ADD COLUMN priority INTEGER NOT NULL DEFAULT 0`);
    },
  };
  const applyOnce = () => {
    // Тот же порядок операций, что в runMigrations, но с локальным списком миграций — сам runMigrations читает module-level MIGRATIONS;
    // здесь проверяем именно механизм "применить один раз и поднять версию", а не список миграций.
    const version = db.pragma("user_version", { simple: true }) as number;
    if (migration.version <= version) return;
    db.transaction(() => {
      migration.migrate(db);
      db.pragma(`user_version = ${migration.version}`);
    })();
  };

  applyOnce();
  applyOnce(); // второй прогон не должен повторно выполнить ALTER TABLE (упал бы: колонка уже есть)

  assert.equal(calls, 1, "migrate() должна выполниться ровно один раз");
  assert.equal(db.pragma("user_version", { simple: true }), BASELINE_VERSION + 1);
  const columns = db.prepare(`PRAGMA table_info(watchlist)`).all() as { name: string }[];
  assert.ok(columns.some((c) => c.name === "priority"));
});

test("validateMigrationSequence принимает пустой список и непрерывную последовательность от baseline+1", () => {
  assert.doesNotThrow(() => validateMigrationSequence([], BASELINE_VERSION));
  assert.doesNotThrow(() =>
    validateMigrationSequence(
      [{ version: BASELINE_VERSION + 1 }, { version: BASELINE_VERSION + 2 }, { version: BASELINE_VERSION + 3 }],
      BASELINE_VERSION,
    ),
  );
});

test("validateMigrationSequence бросает на пропуске версии", () => {
  assert.throws(() => validateMigrationSequence([{ version: BASELINE_VERSION + 1 }, { version: BASELINE_VERSION + 3 }], BASELINE_VERSION));
});

test("validateMigrationSequence бросает на дублирующейся версии", () => {
  assert.throws(() => validateMigrationSequence([{ version: BASELINE_VERSION + 1 }, { version: BASELINE_VERSION + 1 }], BASELINE_VERSION));
});

test("validateMigrationSequence бросает, если первая миграция не сразу за baseline", () => {
  assert.throws(() => validateMigrationSequence([{ version: BASELINE_VERSION + 2 }], BASELINE_VERSION));
});
