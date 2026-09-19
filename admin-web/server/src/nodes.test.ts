import { test } from "node:test";
import assert from "node:assert/strict";
import { claimSignature, loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

async function seedContainer(app: ReturnType<typeof testApp>, headers: Record<string, string>) {
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        {
          id: "nasos-4",
          name: "Насосная-4",
          tier: "HARD",
          ownerFaction: "NEON_DRAGONS",
          slots: [
            { index: 0, type: "SHARD", tier: "HARD", copies: 1, title: "Логи СБ" },
            { index: 1, type: "DAEMON", tier: "BASE", copies: 1, title: "Mainframe" },
          ],
        },
      ],
    },
  });
}

test("GET /api/nodes — сводка по контейнерам (слоты/тираж/взломы/тревоги)", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  await seedContainer(app, headers);

  const alice = testDevice();
  const bob = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:seed-1" }),
        bob.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:seed-2" }),
        alice.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT", sourceRef: "nasos-4:seed-1" }),
        bob.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: true }), reason: "ALERT_SUPPRESSED", sourceRef: "nasos-4:seed-2" }),
      ],
    },
  });

  const claimedAt = Date.now();
  await app.inject({
    method: "POST",
    url: "/api/slots/nasos-4%230/claim",
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt, signature: claimSignature(alice, "nasos-4#0", claimedAt) },
  });

  const res = await app.inject({ method: "GET", url: "/api/nodes", headers });
  assert.equal(res.statusCode, 200);
  const nodes = res.json();
  assert.equal(nodes.length, 1);
  const node = nodes[0];
  assert.equal(node.id, "nasos-4");
  assert.equal(node.slotsTotal, 2);
  assert.equal(node.slotsClaimed, 1);
  assert.deepEqual(node.breaches, { success: 1, partial: 0, fail: 1 });
  assert.equal(node.uniquePlayers, 2);
  assert.equal(node.alertsSent, 1);
  assert.equal(node.alertsSuppressed, 1);
  assert.ok(node.lastBreachAt !== null);
});

test("GET /api/nodes/:id — детальная карточка с раскладкой взломщиков по actor", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  await seedContainer(app, headers);

  const alice = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:seed-1" }),
      ],
    },
  });

  const res = await app.inject({ method: "GET", url: "/api/nodes/nasos-4", headers });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.id, "nasos-4");
  assert.equal(body.breachers.length, 1);
  assert.equal(body.breachers[0].actor, alice.publicKeyB64);
  assert.equal(body.breachers[0].n, 1);
});

test("GET /api/nodes/:id — неизвестный контейнер — 404", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);

  const res = await app.inject({ method: "GET", url: "/api/nodes/нет-такого", headers });
  assert.equal(res.statusCode, 404);
});

test("GET /api/nodes — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/nodes" });
  assert.equal(res.statusCode, 401);
});

test("GET /api/nodes — '_' в id контейнера не захватывает записи соседнего контейнера (LIKE-шаблон)", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const mk = (id: string) => ({ id, name: id, tier: "BASE", ownerFaction: "F", slots: [{ index: 0, type: "SHARD", tier: "BASE", copies: 1, title: "t" }] });
  await app.inject({ method: "POST", url: "/api/containers", headers, payload: { containers: [mk("pump_1"), mk("pumpX1")] } });

  const alice = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "BASE", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "pumpX1:seed-1" })],
    },
  });

  const nodes = (await app.inject({ method: "GET", url: "/api/nodes", headers })).json() as { id: string; breaches: { success: number } }[];
  assert.equal(nodes.find((n) => n.id === "pumpX1")!.breaches.success, 1);
  assert.equal(nodes.find((n) => n.id === "pump_1")!.breaches.success, 0, "взлом pumpX1 не должен считаться взломом pump_1");
});
