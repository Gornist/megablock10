import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

test("POST /api/containers — заливает несколько контейнеров, перезаписывая по id", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const first = await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON_DRAGONS", slots: [{ index: 0, type: "SHARD", tier: "HARD", copies: 1, title: "Логи СБ" }] },
      ],
    },
  });
  assert.equal(first.statusCode, 200);
  assert.deepEqual(first.json(), { upserted: 1, errors: [] });

  // перезалив с тем же id — обновляет, не дублирует
  const second = await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "nasos-4", name: "Насосная-4 (обновлено)", tier: "NIGHTMARE", ownerFaction: "NEON_DRAGONS", slots: [] },
      ],
    },
  });
  assert.equal(second.statusCode, 200);
  const row = db.prepare(`SELECT COUNT(*) AS n FROM containers`).get() as { n: number };
  assert.equal(row.n, 1);
  const updated = db.prepare(`SELECT name, tier FROM containers WHERE id = ?`).get("nasos-4") as { name: string; tier: string };
  assert.equal(updated.name, "Насосная-4 (обновлено)");
  assert.equal(updated.tier, "NIGHTMARE");
});

test("POST /api/containers — containers не массив — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const res = await app.inject({ method: "POST", url: "/api/containers", headers, payload: { containers: "не массив" } });
  assert.equal(res.statusCode, 400);
});

test("POST /api/containers — контейнер без обязательных верхнеуровневых полей — попадает в errors, не роняя остальной батч", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "bad", slots: [] }, // нет name/tier
        { id: "good", name: "Хороший", tier: "BASE", ownerFaction: "X", slots: [] },
      ],
    },
  });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.upserted, 1);
  assert.equal(body.errors.length, 1);
  assert.equal(body.errors[0].id, "bad");
  assert.equal(db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get("good") !== undefined, true);
  assert.equal(db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get("bad"), undefined);
});

test("POST /api/containers — слот с некорректным type/copies отклоняется валидатором (та же проверка, что и у master.ts)", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "bad-slot", name: "X", tier: "BASE", ownerFaction: "Y", slots: [{ index: 0, type: "NOT_A_TYPE", tier: "BASE", copies: 1, title: "t" }] },
        { id: "neg-copies", name: "X", tier: "BASE", ownerFaction: "Y", slots: [{ index: 0, type: "SHARD", tier: "BASE", copies: -3, title: "t" }] },
      ],
    },
  });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.upserted, 0);
  assert.equal(body.errors.length, 2);
  assert.equal(db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get("bad-slot"), undefined);
  assert.equal(db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get("neg-copies"), undefined);
});

test("POST /api/containers — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "POST", url: "/api/containers", payload: { containers: [] } });
  assert.equal(res.statusCode, 401);
});
