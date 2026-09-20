import { test } from "node:test";
import assert from "node:assert/strict";
import { claimSignature } from "./testUtil.js";
import { setup, seedPlayer } from "./testHelpers.js";

test("attention: отрицательный баланс, крупное поступление, недоставленная правка, пропавший игрок", async () => {
  const { app, db, headers } = await setup();
  const neg = await seedPlayer(app, { callsign: "Debtor", faction: "X" });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [neg.change({ field: "balance", oldValue: "0", newValue: "-40", reason: "BREACH_EDDIES" })] } });
  const rich = await seedPlayer(app, { callsign: "Rich", faction: "X", balance: 5000 });
  const quiet = await seedPlayer(app, { callsign: "Quiet", faction: "X" });

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(quiet.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "1", reason: "тест" },
  });
  const old = Date.now() - 20 * 60_000;
  db.prepare(`UPDATE master_pending SET created_at = ?`).run(old);
  db.prepare(`UPDATE changes SET received_at = ? WHERE subject_key = ? AND reason != 'MASTER_OVERRIDE'`).run(old, quiet.publicKeyB64);

  const res = await app.inject({ method: "GET", url: "/api/attention", headers });
  assert.equal(res.statusCode, 200);
  const { items, counts } = res.json() as { items: { kind: string; severity: string; detail: string; subjectKey?: string }[]; counts: { crit: number; warn: number; info: number } };
  const kinds = items.map((i) => i.kind);
  assert.ok(kinds.includes("negative_balance"));
  assert.ok(kinds.includes("balance_jump"));
  assert.ok(kinds.includes("override_undelivered"));
  assert.ok(kinds.includes("went_silent"));
  assert.equal(items[0].severity, "crit", "критичные — первыми");
  assert.match(items.find((i) => i.kind === "balance_jump")!.detail, /Rich: \+5000/);
  assert.equal(items.find((i) => i.kind === "went_silent")!.subjectKey, quiet.publicKeyB64);
  assert.equal(counts.crit + counts.warn + counts.info, items.length);
  assert.equal(rich.publicKeyB64.length > 0, true);
});

test("attention: недоставленная правка при живом heartbeat — критичная (телефон на связи, но не применяет)", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 10 });
  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "1", reason: "тест" },
  });
  db.prepare(`UPDATE master_pending SET created_at = ?`).run(Date.now() - 10 * 60_000);
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: a.publicKeyB64 } }); // heartbeat без ack

  const items = (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as { kind: string; severity: string }[];
  assert.equal(items.find((i) => i.kind === "override_undelivered")?.severity, "crit");
});

test("attention: исчерпанный узел, который продолжают ломать", async () => {
  const { app, headers } = await setup();
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [{ index: 0, type: "SHARD", tier: "HARD", copies: 1, title: "Логи" }] }] },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON" });
  const claimedAt = Date.now();
  const claim = await app.inject({
    method: "POST",
    url: `/api/slots/${encodeURIComponent("nasos-4#0")}/claim`,
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt, signature: claimSignature(alice, "nasos-4#0", claimedAt) },
  });
  assert.equal(claim.json().granted, true);
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s9" })] },
  });

  const items = (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as { kind: string; nodeId?: string }[];
  assert.equal(items.find((i) => i.kind === "node_exhausted_hot")?.nodeId, "nasos-4");
});

test("attention: без мастерского токена — 401", async () => {
  const { app } = await setup();
  assert.equal((await app.inject({ method: "GET", url: "/api/attention" })).statusCode, 401);
});
