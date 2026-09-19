import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

test("POST /api/master/containers — генерирует QR и сохраняет контейнер с SHARD и DAEMON слотами", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/containers",
    headers,
    payload: {
      id: "nasos-4",
      name: "Насосная-4",
      tier: "HARD",
      ownerFaction: "NEON_DRAGONS",
      slots: [
        { type: "SHARD", tier: "HARD", copies: 1, shard: { title: "Логи СБ", body: "секретный текст", meta: "m", valueHint: "v", decryptAction: true, moneyAmount: 50 } },
        { type: "DAEMON", tier: "BASE", copies: 0, daemon: { name: "Mainframe", sequence: ["UP", "DOWN"], effect: "EXTRACT_SHARD" } },
      ],
    },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.containerId, "nasos-4");
  assert.ok(typeof body.qr === "string" && body.qr.startsWith("MB10:CONTAINER:v1:"));
  assert.ok(typeof body.qrImage === "string" && body.qrImage.startsWith("data:image/png;base64,"));

  const row = db.prepare(`SELECT * FROM containers WHERE id = ?`).get("nasos-4") as { slots_json: string; tier: string; owner_faction: string };
  assert.ok(row, "контейнер должен быть записан в БД");
  assert.equal(row.tier, "HARD");
  assert.equal(row.owner_faction, "NEON_DRAGONS");
  const slots = JSON.parse(row.slots_json);
  assert.equal(slots.length, 2);
  assert.equal(slots[0].type, "SHARD");
  assert.equal(slots[0].index, 0);
  assert.ok(slots[0].payload, "у SHARD-слота должен быть зашифрованный payload");
  assert.equal(slots[1].type, "DAEMON");
  assert.equal(slots[1].index, 1);
});

test("POST /api/master/containers — id генерируется автоматически, если не передан", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/containers",
    headers,
    payload: { name: "Точка без id", tier: "BASE", ownerFaction: "INDEPENDENT", slots: [] },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.ok(body.containerId.startsWith("container-"));
});

test("POST /api/master/containers — без обязательных полей верхнего уровня — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/containers",
    headers,
    payload: { name: "", tier: "BASE", ownerFaction: "X", slots: [] },
  });
  assert.equal(res.statusCode, 400);
});

test("POST /api/master/containers — SHARD-слот без title/body — 400, ничего не сохраняется", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/containers",
    headers,
    payload: {
      id: "bad-box",
      name: "Плохой ящик",
      tier: "BASE",
      ownerFaction: "X",
      slots: [{ type: "SHARD", tier: "BASE", copies: 1, shard: { title: "", body: "" } }],
    },
  });
  assert.equal(res.statusCode, 400);
  assert.equal(db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get("bad-box"), undefined);
});

test("POST /api/master/containers — DAEMON-слот без sequence — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/containers",
    headers,
    payload: {
      id: "bad-daemon",
      name: "Плохой демон",
      tier: "BASE",
      ownerFaction: "X",
      slots: [{ type: "DAEMON", tier: "BASE", copies: 1, daemon: { name: "D", sequence: [] } }],
    },
  });
  assert.equal(res.statusCode, 400);
});

test("POST /api/master/containers — отрицательные copies отклоняются валидатором слотов (не проходят мимо Number.isInteger)", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/containers",
    headers,
    payload: {
      id: "neg-copies",
      name: "Отрицательный тираж",
      tier: "BASE",
      ownerFaction: "X",
      slots: [{ type: "SHARD", tier: "BASE", copies: -1, shard: { title: "t", body: "b" } }],
    },
  });
  assert.equal(res.statusCode, 400);
  assert.equal(db.prepare(`SELECT 1 FROM containers WHERE id = ?`).get("neg-copies"), undefined);
});

test("POST /api/master/containers — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "POST", url: "/api/master/containers", payload: { name: "x", tier: "BASE", ownerFaction: "X", slots: [] } });
  assert.equal(res.statusCode, 401);
});

test("POST /api/master/shards — генерирует QR шарда", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({
    method: "POST",
    url: "/api/master/shards",
    headers,
    payload: { id: "shard-x", title: "Личное дело", body: "текст шарда", tier: "HARD", decryptAction: true, moneyAmount: 10 },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.shardId, "shard-x");
  assert.ok(body.qr.startsWith("MB10:SHARD:v1:"));
  assert.ok(body.qrImage.startsWith("data:image/png;base64,"));
});

test("POST /api/master/shards — без title/body — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "POST", url: "/api/master/shards", headers, payload: { title: "", body: "" } });
  assert.equal(res.statusCode, 400);
});

test("POST /api/master/shards — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "POST", url: "/api/master/shards", payload: { title: "t", body: "b" } });
  assert.equal(res.statusCode, 401);
});

test("POST /api/master/ram — генерирует QR апгрейда RAM с одноразовым токеном", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "POST", url: "/api/master/ram", headers, payload: { delta: 2 } });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.ok(body.token.startsWith("ram-"));
  assert.ok(body.qr.startsWith("MB10:RAM:v1:"));
});

test("POST /api/master/ram — delta не положительное целое — 400", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const zero = await app.inject({ method: "POST", url: "/api/master/ram", headers, payload: { delta: 0 } });
  assert.equal(zero.statusCode, 400);

  const negative = await app.inject({ method: "POST", url: "/api/master/ram", headers, payload: { delta: -1 } });
  assert.equal(negative.statusCode, 400);

  const fractional = await app.inject({ method: "POST", url: "/api/master/ram", headers, payload: { delta: 1.5 } });
  assert.equal(fractional.statusCode, 400);
});

test("POST /api/master/ram — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "POST", url: "/api/master/ram", payload: { delta: 1 } });
  assert.equal(res.statusCode, 401);
});

test("POST /api/master/containers — id с разделителями QR, кривые коды демона и неизвестный эффект отклоняются", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const post = async (payload: Record<string, unknown>) =>
    (await app.inject({ method: "POST", url: "/api/master/containers", headers, payload })).statusCode;
  const shardSlot = { type: "SHARD", tier: "BASE", copies: 1, shard: { title: "t", body: "b" } };
  const base = { name: "N", tier: "BASE", ownerFaction: "F", slots: [shardSlot] };

  assert.equal(await post({ ...base, id: "a:b" }), 400);
  assert.equal(await post({ ...base, id: "a#b" }), 400);
  assert.equal(await post({ ...base, id: "ok-id_1.2" }), 200);
  assert.equal(
    await post({ ...base, id: "d1", slots: [{ type: "DAEMON", tier: "BASE", copies: 0, daemon: { name: "D", sequence: ["1C,55"] } }] }),
    400,
  );
  assert.equal(
    await post({ ...base, id: "d2", slots: [{ type: "DAEMON", tier: "BASE", copies: 0, daemon: { name: "D", sequence: ["1C"], effect: "NOPE" } }] }),
    400,
  );
  assert.equal(await post({ ...base, id: "s1", slots: [{ ...shardSlot, shard: { title: "t", body: "b", moneyAmount: -5 } }] }), 400);
  assert.equal(await post({ ...base, id: "s2", slots: [{ ...shardSlot, shard: { title: "t", body: "b", moneyAmount: 1.5 } }] }), 400);
});

test("POST /api/master/shards — id с ':' и дробные/отрицательные деньги отклоняются", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const post = async (payload: Record<string, unknown>) =>
    (await app.inject({ method: "POST", url: "/api/master/shards", headers, payload })).statusCode;
  assert.equal(await post({ id: "a:b", title: "t", body: "b" }), 400);
  assert.equal(await post({ title: "t", body: "b", moneyAmount: -1 }), 400);
  assert.equal(await post({ title: "t", body: "b", moneyAmount: 25 }), 200);
});
