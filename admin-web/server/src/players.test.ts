import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

test("GET /api/players — сводка по всем известным персонажам", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const device = testDevice();

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        device.change({ field: "callsign", newValue: "V_KANG", reason: "CHARACTER_CREATED" }),
        device.change({ field: "faction", newValue: "NEON_DRAGONS", reason: "CHARACTER_CREATED" }),
        device.change({ field: "balance", oldValue: "0", newValue: "20", reason: "BREACH_EDDIES" }),
      ],
    },
  });

  const res = await app.inject({ method: "GET", url: "/api/players", headers });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.length, 1);
  assert.equal(body[0].publicKeyB64, device.publicKeyB64);
  assert.equal(body[0].callsign, "V_KANG");
  assert.equal(body[0].faction, "NEON_DRAGONS");
  assert.equal(body[0].balance, 20);
  assert.equal(body[0].online, true, "только что прислал запись — должен быть online");
});

test("GET /api/players — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/players" });
  assert.equal(res.statusCode, 401);
});

test("GET /api/players/:key — снимок конкретного персонажа", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const device = testDevice();

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [device.change({ field: "callsign", newValue: "GHOST", reason: "CHARACTER_CREATED" })] },
  });

  const res = await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(device.publicKeyB64)}`, headers });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().callsign, "GHOST");
});

test("GET /api/players/:key — неизвестный ключ — 404", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "GET", url: "/api/players/несуществующий-ключ", headers });
  assert.equal(res.statusCode, 404);
});

test("GET /api/players/:key/history — пагинация и фильтр по field/reason", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const device = testDevice();

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        device.change({ field: "callsign", newValue: "A", reason: "CHARACTER_CREATED" }),
        device.change({ field: "balance", oldValue: "0", newValue: "5", reason: "BREACH_EDDIES", sourceRef: "nasos-4#0" }),
        device.change({ field: "balance", oldValue: "5", newValue: "15", reason: "BREACH_EDDIES", sourceRef: "nasos-4#1" }),
      ],
    },
  });

  const all = await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/history`, headers });
  assert.equal(all.json().total, 3);

  const byField = await app.inject({
    method: "GET",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/history?field=balance`,
    headers,
  });
  assert.equal(byField.json().total, 2);

  const byReason = await app.inject({
    method: "GET",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/history?reason=CHARACTER_CREATED`,
    headers,
  });
  assert.equal(byReason.json().total, 1);

  const bySource = await app.inject({
    method: "GET",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/history?source=nasos-4`,
    headers,
  });
  assert.equal(bySource.json().total, 2);

  const paged = await app.inject({
    method: "GET",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/history?pageSize=1&page=0`,
    headers,
  });
  const pagedBody = paged.json();
  assert.equal(pagedBody.records.length, 1);
  assert.equal(pagedBody.pageSize, 1);
  assert.equal(pagedBody.total, 3);
});

test("GET /api/players/:key/history — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const res = await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/history` });
  assert.equal(res.statusCode, 401);
});
