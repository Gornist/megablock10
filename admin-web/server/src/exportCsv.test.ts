import { test } from "node:test";
import assert from "node:assert/strict";
import { seedPlayer, setup } from "./testHelpers.js";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

async function seedGame(app: ReturnType<typeof testApp>, headers: Record<string, string>) {
  const device = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [device.change({ field: "callsign", newValue: "V_KANG", reason: "CHARACTER_CREATED" })] },
  });
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON_DRAGONS", slots: [{ index: 0, type: "SHARD", tier: "HARD", copies: 1, title: "t" }] },
      ],
    },
  });
  return device;
}

test("GET /api/export/players.csv — заголовок и строка с данными игрока", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const device = await seedGame(app, headers);

  const res = await app.inject({ method: "GET", url: "/api/export/players.csv", headers });
  assert.equal(res.statusCode, 200);
  assert.match(res.headers["content-type"] as string, /text\/csv/);
  const text = res.body;
  assert.match(text, /^publicKeyB64,callsign,faction/);
  assert.match(text, new RegExp(device.publicKeyB64.replace(/[+/=]/g, "\\$&")));
});

test("GET /api/export/nodes.csv — строка по контейнеру", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  await seedGame(app, headers);

  const res = await app.inject({ method: "GET", url: "/api/export/nodes.csv", headers });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /nasos-4/);
});

test("GET /api/export/slots.csv — реестр тиражей", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  await seedGame(app, headers);

  const res = await app.inject({ method: "GET", url: "/api/export/slots.csv", headers });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /slotRef/);
  assert.match(res.body, /nasos-4#0/);
});

test("GET /api/export/history.csv — полная история changes", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  await seedGame(app, headers);

  const res = await app.inject({ method: "GET", url: "/api/export/history.csv", headers });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /CHARACTER_CREATED/);
});

test("GET /api/export/:kind.csv — неизвестный kind — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const res = await app.inject({ method: "GET", url: "/api/export/bogus.csv", headers });
  assert.equal(res.statusCode, 400);
});

test("GET /api/export/:kind — без расширения .csv — 404", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const res = await app.inject({ method: "GET", url: "/api/export/players", headers });
  assert.equal(res.statusCode, 404);
});

test("GET /api/export/players.csv — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/export/players.csv" });
  assert.equal(res.statusCode, 401);
});

test("GET /api/export/audit.csv — журнал действий мастеров", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 10 });
  await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`, headers, payload: { field: "balance", newValue: "99", reason: "тест" } });
  const res = await app.inject({ method: "GET", url: "/api/export/audit.csv", headers });
  assert.equal(res.statusCode, 200);
  const [head, ...rows] = res.body.trim().split("\n");
  assert.equal(head, "at,master,action,detail");
  assert.equal(rows.length, (db.prepare(`SELECT COUNT(*) AS n FROM audit_master`).get() as { n: number }).n);
  assert.match(rows[0], /Мастер-1/);
});
