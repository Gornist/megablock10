import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import Database from "better-sqlite3";
import { runBackup } from "./lib/backup.js";
import { testDb } from "./testUtil.js";

test("runBackup создаёт файл с рабочей копией схемы БД", () => {
  const db = testDb();
  const dir = mkdtempSync(join(tmpdir(), "mb10-backup-"));
  try {
    const path = runBackup(db, dir);
    const copy = new Database(path, { readonly: true });
    const row = copy.prepare(`SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'changes'`).get();
    assert.ok(row, "в бэкапе должна быть таблица changes");
    copy.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("runBackup чистит старые копии сверх retention", () => {
  const db = testDb();
  const dir = mkdtempSync(join(tmpdir(), "mb10-backup-"));
  try {
    runBackup(db, dir, 2);
    runBackup(db, dir, 2);
    runBackup(db, dir, 2);
    const files = readdirSync(dir);
    assert.equal(files.length, 2, "должно остаться не больше retention файлов");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
