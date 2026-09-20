import { test } from "node:test";
import assert from "node:assert/strict";
import { setup, seedPlayer, type App } from "./testHelpers.js";

async function seedEvents() {
  const ctx = await setup();
  const { app, headers } = ctx;
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] },
        { id: "arasaka-1", name: "Арасака-1", tier: "HARD", ownerFaction: "ARASAKA", slots: [] },
      ],
    },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON", balance: 100 });
  const bob = await seedPlayer(app, { callsign: "Bob", faction: "ARASAKA", balance: 50 });
  const nofac = await seedPlayer(app, { callsign: "Nomad", faction: "" });
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s1" }),
        alice.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT", sourceRef: "nasos-4:s1" }),
        bob.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "arasaka-1:s2" }),
        bob.change({ field: "balance", oldValue: "50", newValue: "40", reason: "TRANSFER_OUT", sourceRef: "tx1" }),
        alice.change({ field: "balance", oldValue: "100", newValue: "110", reason: "TRANSFER_IN", sourceRef: "tx1", actor: bob.publicKeyB64 }),
      ],
    },
  });
  await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}/override`, headers, payload: { field: "balance", newValue: "500", reason: "компенсация" } });
  await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Сбор", all: true } });
  return { ...ctx, alice, bob, nofac };
}

const events = async (app: App, headers: Record<string, string>, query = "") =>
  (await app.inject({ method: "GET", url: `/api/events${query}`, headers })).json() as {
    total: number;
    page: number;
    pageSize: number;
    records: { reason: string; field: string; subject_key: string; human: { kind: string; subject: string; body: string } }[];
  };

test("events: фильтр по игроку — только его записи, включая сообщения мастера ему", async () => {
  const { app, headers, alice } = await seedEvents();
  const res = await events(app, headers, `?player=${encodeURIComponent(alice.publicKeyB64)}`);
  assert.ok(res.total > 0);
  assert.ok(res.records.every((r) => r.subject_key === alice.publicKeyB64));
  assert.ok(res.records.some((r) => r.field === "announcement"), "адресату его объявление видно");
});

test("events: без фильтра по игроку объявления не забивают поток", async () => {
  const { app, headers } = await seedEvents();
  const res = await events(app, headers);
  assert.ok(res.records.length > 0);
  assert.ok(res.records.every((r) => r.field !== "announcement"));
});

test("events: фильтр по фракции — записи всех её игроков; «без фракции» отдельным значением", async () => {
  const { app, headers, alice, bob, nofac } = await seedEvents();
  const neon = await events(app, headers, "?faction=NEON");
  assert.ok(neon.total > 0 && neon.records.every((r) => r.subject_key === alice.publicKeyB64));
  const ara = await events(app, headers, "?faction=ARASAKA");
  assert.ok(ara.records.every((r) => r.subject_key === bob.publicKeyB64));
  const none = await events(app, headers, "?faction=__none__");
  assert.ok(none.total > 0 && none.records.every((r) => r.subject_key === nofac.publicKeyB64));
  assert.equal((await events(app, headers, "?faction=НЕТ_ТАКОЙ")).total, 0);
});

test("events: фильтр по типу совпадает с маркером в ленте (human.kind)", async () => {
  const { app, headers } = await seedEvents();
  for (const kind of ["money", "item", "breach", "alert", "master", "system"]) {
    const res = await events(app, headers, `?kind=${kind}&pageSize=200`);
    assert.ok(res.records.every((r) => r.human.kind === kind), `kind=${kind}: попали записи другого типа`);
  }
  assert.ok((await events(app, headers, "?kind=breach")).total >= 2);
  assert.ok((await events(app, headers, "?kind=money")).total >= 4);
  assert.equal((await events(app, headers, "?kind=master")).records[0].human.kind, "master");
  assert.equal((await app.inject({ method: "GET", url: "/api/events?kind=что-то", headers })).statusCode, 400);
});

test("events: фильтр по причине и по узлу, комбинация игрока и узла", async () => {
  const { app, headers, alice } = await seedEvents();
  const byReason = await events(app, headers, "?reason=TRANSFER_IN");
  assert.equal(byReason.total, 1);
  assert.equal((await app.inject({ method: "GET", url: "/api/events?reason=НЕТ", headers })).statusCode, 400);

  const node = await events(app, headers, "?node=nasos-4");
  assert.equal(node.total, 2, "взлом и сигнал по Насосной-4");
  assert.ok(node.records.every((r) => r.subject_key === alice.publicKeyB64));

  const combo = await events(app, headers, `?node=arasaka-1&player=${encodeURIComponent(alice.publicKeyB64)}`);
  assert.equal(combo.total, 0, "Alice узел Арасаки не ломала");
  const combo2 = await events(app, headers, "?faction=NEON&kind=alert");
  assert.equal(combo2.total, 1);
});

test("events: период (since/until), пагинация и порядок «новые сверху»", async () => {
  const { app, headers, db } = await seedEvents();
  db.prepare(`UPDATE changes SET received_at = received_at - 3600000 WHERE reason = 'BREACH_ATTEMPT'`).run();
  const recent = await events(app, headers, `?kind=breach&since=${Date.now() - 1800000}`);
  assert.equal(recent.total, 0, "взломы старше получаса не попадают");
  assert.equal((await events(app, headers, `?kind=breach&until=${Date.now() - 1800000}`)).total, 2);

  const all = await events(app, headers, "?pageSize=200");
  const page0 = await events(app, headers, "?pageSize=3&page=0");
  const page1 = await events(app, headers, "?pageSize=3&page=1");
  assert.equal(page0.total, all.total);
  assert.equal(page0.records.length, 3);
  assert.notEqual(page0.records[0].subject_key + page0.records[0].field, "");
  assert.equal(page1.records.length, Math.min(3, all.total - 3));
  assert.deepEqual(page0.records.concat(page1.records).map((r) => r.human.body), all.records.slice(0, page0.records.length + page1.records.length).map((r) => r.human.body));
});

test("events: без мастерского токена — 401", async () => {
  const { app } = await setup();
  assert.equal((await app.inject({ method: "GET", url: "/api/events" })).statusCode, 401);
});
