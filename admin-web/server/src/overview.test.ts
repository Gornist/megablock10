import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

test("GET /api/overview — агрегаты игроков/взломов/слотов/тревог", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();
  const bob = testDevice();

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "callsign", newValue: "A", reason: "CHARACTER_CREATED" }),
        bob.change({ field: "callsign", newValue: "B", reason: "CHARACTER_CREATED" }),
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT" }),
        alice.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT" }),
        bob.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: true }), reason: "ALERT_SUPPRESSED" }),
      ],
    },
  });

  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON_DRAGONS", slots: [{ index: 0, type: "SHARD", tier: "HARD", copies: 2, title: "t" }] },
      ],
    },
  });

  const res = await app.inject({ method: "GET", url: "/api/overview", headers });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.players.total, 2);
  assert.equal(body.players.online, 2, "обе записи только что пришли — оба online");
  assert.deepEqual(body.breachesLastHour, { success: 1, partial: 0, fail: 0 });
  assert.equal(body.slots.printed, 2);
  assert.equal(body.slots.claimed, 0);
  assert.equal(body.alerts.sent, 1);
  assert.equal(body.alerts.suppressed, 1);
});

test("GET /api/overview — кэш по версии БД: новая запись сразу видна на следующем запросе, без ожидания TTL", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();

  const before = (await app.inject({ method: "GET", url: "/api/overview", headers })).json();
  assert.equal(before.players.total, 0);

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [alice.change({ field: "callsign", newValue: "A", reason: "CHARACTER_CREATED" })] },
  });

  const after = (await app.inject({ method: "GET", url: "/api/overview", headers })).json();
  assert.equal(after.players.total, 1);
});

test("GET /api/overview — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/overview" });
  assert.equal(res.statusCode, 401);
});

test("GET /api/changes/recent — лента с фильтром по since и лимитом", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [alice.change({ field: "callsign", newValue: "A", reason: "CHARACTER_CREATED" })] },
  });

  const all = await app.inject({ method: "GET", url: "/api/changes/recent", headers });
  assert.equal(all.statusCode, 200);
  const allBody = all.json();
  assert.equal(allBody.records.length, 1);
  assert.ok(typeof allBody.now === "number");

  const future = await app.inject({ method: "GET", url: `/api/changes/recent?since=${Date.now() + 60_000}`, headers });
  assert.equal(future.json().records.length, 0, "since в будущем — ничего не найдено");
});

test("GET /api/changes/recent — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/changes/recent" });
  assert.equal(res.statusCode, 401);
});
