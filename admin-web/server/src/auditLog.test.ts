import { test } from "node:test";
import assert from "node:assert/strict";
import { describeAudit } from "./lib/auditSummary.js";
import { setup, seedPlayer } from "./testHelpers.js";

test("audit: журнал показывает правки, массовые правки, объявления и создание контейнера — с именем мастера и фразой", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "500", reason: "компенсация" },
  });
  await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { field: "faction", newValue: "Z", reason: "переход", all: true } });
  await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Сбор у входа", all: true } });
  await app.inject({ method: "POST", url: "/api/master/containers", headers, payload: { name: "Насос", tier: "BASE", ownerFaction: "X", slots: [] } });

  const res = await app.inject({ method: "GET", url: "/api/audit", headers });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.total, 4);
  const actions = body.records.map((r: { action: string }) => r.action).sort();
  assert.deepEqual(actions, ["ANNOUNCEMENT", "BULK_OVERRIDE", "CONTAINER_CREATED", "PLAYER_OVERRIDE"]);
  assert.ok(body.records.every((r: { masterName: string }) => r.masterName === "Мастер-1"));
  const override = body.records.find((r: { action: string }) => r.action === "PLAYER_OVERRIDE");
  assert.match(override.summary, /Alice: баланс 100 → 500.*компенсация/);

  const filtered = await app.inject({ method: "GET", url: "/api/audit?action=ANNOUNCEMENT", headers });
  assert.equal(filtered.json().total, 1);
  assert.ok(body.actions.length >= 4, "список действий для фильтра");
  assert.equal((await app.inject({ method: "GET", url: "/api/audit" })).statusCode, 401);
});

test("describeAudit: фразы по действиям", () => {
  const name = (k: string) => (k === "k1" ? "Alice" : k);
  assert.match(describeAudit("SLOT_REVOKE", { slotRef: "n#0", claimantKeyB64: "k1", reason: "дубль" }, name), /Alice.*дубль/);
  assert.match(describeAudit("BULK_OVERRIDE", { field: "balance", mode: "add", newValue: "100", target: "все игроки", count: 3, justification: "премия" }, name), /все игроки \(3 чел\.\): баланс \+100/);
  assert.equal(describeAudit("НЕИЗВЕСТНОЕ", null, name), "НЕИЗВЕСТНОЕ");
});
