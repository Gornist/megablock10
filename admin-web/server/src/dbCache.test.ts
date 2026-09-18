import { test } from "node:test";
import assert from "node:assert/strict";
import { cachedByDbVersion } from "./lib/dbCache.js";
import { testDb } from "./testUtil.js";

test("cachedByDbVersion не пересчитывает, пока в БД ничего не записали", () => {
  const db = testDb();
  let calls = 0;
  const cached = cachedByDbVersion(db, () => {
    calls += 1;
    return "значение";
  });

  cached();
  cached();
  cached();
  assert.equal(calls, 1, "три чтения подряд без записи в БД должны пересчитать только один раз");
});

test("cachedByDbVersion пересчитывает сразу после любой записи в БД — не ждёт TTL", () => {
  const db = testDb();
  db.exec(`CREATE TABLE probe (n INTEGER)`);
  let calls = 0;
  const cached = cachedByDbVersion(db, () => {
    calls += 1;
    return calls;
  });

  assert.equal(cached(), 1);
  assert.equal(cached(), 1, "без записи — тот же результат из кэша");

  db.prepare(`INSERT INTO probe (n) VALUES (1)`).run();
  assert.equal(cached(), 2, "после INSERT должно пересчитаться немедленно, а не по таймеру");

  db.prepare(`UPDATE probe SET n = 2 WHERE n = 1`).run();
  assert.equal(cached(), 3, "и после UPDATE тоже");
});

test("cachedByDbVersion не считает изменением запись, которая ничего не затронула (0 rows affected)", () => {
  const db = testDb();
  db.exec(`CREATE TABLE probe (n INTEGER)`);
  let calls = 0;
  const cached = cachedByDbVersion(db, () => {
    calls += 1;
    return calls;
  });

  cached();
  db.prepare(`UPDATE probe SET n = 2 WHERE n = 999`).run(); // ни одной строки не совпало
  assert.equal(cached(), 1, "total_changes() не растёт на UPDATE без совпадений — переcчёта быть не должно");
});
