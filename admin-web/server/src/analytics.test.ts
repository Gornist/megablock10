import { test } from "node:test";
import assert from "node:assert/strict";
import { gini } from "./lib/analytics.js";
import { testDevice } from "./testUtil.js";
import { setup, seedPlayer } from "./testHelpers.js";

test("economy: эмиссия по источникам без переводов, оборот, распределение, серия сходится с суммой балансов", async () => {
  const { app, headers } = await setup();
  const a = testDevice();
  const b = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        a.change({ field: "callsign", newValue: "Alice", reason: "CHARACTER_CREATED" }),
        b.change({ field: "callsign", newValue: "Bob", reason: "CHARACTER_CREATED" }),
        a.change({ field: "balance", oldValue: "0", newValue: "100", reason: "BREACH_EDDIES" }),
        b.change({ field: "balance", oldValue: "0", newValue: "50", reason: "SHARD_SCAN" }),
        a.change({ field: "balance", oldValue: "100", newValue: "70", reason: "TRANSFER_OUT", sourceRef: "tx1" }),
        b.change({ field: "balance", oldValue: "50", newValue: "80", reason: "TRANSFER_IN", sourceRef: "tx1", actor: a.publicKeyB64 }),
      ],
    },
  });

  const res = await app.inject({ method: "GET", url: "/api/economy", headers });
  assert.equal(res.statusCode, 200);
  const e = res.json();
  assert.equal(e.totalSupply, 150);
  assert.equal(e.transferVolume, 30);
  assert.deepEqual(e.sources.map((s: { reason: string; total: number }) => [s.reason, s.total]), [["BREACH_EDDIES", 100], ["SHARD_SCAN", 50]]);
  assert.equal(e.series.at(-1).supply, 150, "серия сходится с суммой балансов");
  assert.equal(e.top[0].callsign, "Bob");
  assert.equal(e.distribution.median, 70);
  assert.equal(e.distribution.negative, 0);
  assert.equal((await app.inject({ method: "GET", url: "/api/economy" })).statusCode, 401);
});

test("gini: поровну → 0, всё у одного → близко к 1", () => {
  assert.equal(gini([5, 5, 5, 5]), 0);
  assert.equal(gini([0, 0, 0, 10]), 0.75);
  assert.equal(gini([]), 0);
});

test("factions: сумма по игрокам, свои/чужие взломы, кому уходят сигналы СБ", async () => {
  const { app, headers } = await setup();
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] }] },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON", balance: 100 });
  const bob = await seedPlayer(app, { callsign: "Bob", faction: "ARASAKA", balance: 300 });
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s1" }),
        bob.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s2" }),
        bob.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT", sourceRef: "nasos-4:s2" }),
      ],
    },
  });

  const rows = (await app.inject({ method: "GET", url: "/api/factions", headers })).json() as Record<string, number | string>[];
  const neon = rows.find((r) => r.faction === "NEON")!;
  const ara = rows.find((r) => r.faction === "ARASAKA")!;
  assert.equal(rows[0].faction, "ARASAKA", "сортировка по деньгам");
  assert.equal(ara.totalBalance, 300);
  assert.equal(ara.breachesForeign, 1);
  assert.equal(ara.alertsSent, 1);
  assert.equal(neon.breachesOwn, 1);
  assert.equal(neon.alertsReceived, 1, "сигнал ушёл владельцам узла — фракции NEON");
  assert.equal(neon.online, 1);
});
