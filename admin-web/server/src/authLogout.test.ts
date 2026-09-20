import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testMaster } from "./testUtil.js";

test("logout закрывает сессию на сервере: тот же токен после выхода — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const headers = { authorization: `Bearer ${session}` };
  assert.equal((await app.inject({ method: "GET", url: "/api/overview", headers })).statusCode, 200);

  const out = await app.inject({ method: "POST", url: "/api/auth/logout", headers });
  assert.equal(out.statusCode, 200);
  assert.equal((await app.inject({ method: "GET", url: "/api/overview", headers })).statusCode, 401);
  assert.equal((await app.inject({ method: "POST", url: "/api/auth/logout", headers })).statusCode, 200, "повторный выход — не ошибка");
  assert.equal((await app.inject({ method: "POST", url: "/api/auth/logout" })).statusCode, 200, "без токена — тоже");
});

test("в БД лежит хэш сессионного токена, а не сам токен; просроченные сессии удаляются при следующем входе", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const stored = (db.prepare(`SELECT token FROM sessions`).all() as { token: string }[]).map((r) => r.token);
  assert.ok(!stored.includes(session), "открытый токен не должен попасть в таблицу (и в бэкапы)");
  assert.equal(stored[0].length, 64, "sha256 в hex");

  db.prepare(`UPDATE sessions SET expires_at = ?`).run(Date.now() - 1000);
  await loginAs(app, master.name, master.token);
  assert.equal((db.prepare(`SELECT COUNT(*) AS n FROM sessions`).get() as { n: number }).n, 1, "остаётся только свежая");
});
