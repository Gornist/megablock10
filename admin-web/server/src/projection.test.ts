import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { testDb } from "./testUtil.js";
import { projectCharacter } from "./lib/projection.js";
import { RAM_CAPACITY_DEFAULT } from "./lib/identityDefaults.js";
import type { Db } from "./db/index.js";

let seqCounter = 0;

/** Пишет строку прямо в changes, минуя роут /api/changes и проверку подписи — здесь тестируется только аггрегатор projectCharacter, не приёмный протокол (тот уже покрыт changes.test.ts). */
function insertChange(
  db: Db,
  subjectKeyB64: string,
  opts: {
    field: string;
    newValue: string | null;
    receivedAt?: number;
    happenedAt?: number;
    reason?: string;
    sourceRef?: string | null;
    actor?: string;
  },
) {
  seqCounter += 1;
  const receivedAt = opts.receivedAt ?? Date.now();
  db.prepare(
    `INSERT INTO changes (id, subject_key, seq, happened_at, received_at, field, old_value, new_value, reason, source_ref, actor, signature)
     VALUES (@id, @subject_key, @seq, @happened_at, @received_at, @field, @old_value, @new_value, @reason, @source_ref, @actor, @signature)`,
  ).run({
    id: randomUUID(),
    subject_key: subjectKeyB64,
    seq: seqCounter,
    happened_at: opts.happenedAt ?? receivedAt,
    received_at: receivedAt,
    field: opts.field,
    old_value: null,
    new_value: opts.newValue,
    reason: opts.reason ?? "CHARACTER_CREATED",
    source_ref: opts.sourceRef ?? null,
    actor: opts.actor ?? subjectKeyB64,
    signature: "",
  });
}

test("projectCharacter — неизвестный ключ (нет ни одной записи) даёт null", () => {
  const db = testDb();
  assert.equal(projectCharacter(db, "нет-такого-ключа"), null);
});

test("projectCharacter — скаляры: побеждает запись с более поздним received_at, а не большим seq", () => {
  const db = testDb();
  const key = "player-1";
  insertChange(db, key, { field: "callsign", newValue: "V_KANG", receivedAt: 1000 });
  insertChange(db, key, { field: "callsign", newValue: "GHOST", receivedAt: 2000 });

  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.callsign, "GHOST");
  assert.equal(snapshot.ramCapacity, RAM_CAPACITY_DEFAULT, "ramCapacity по умолчанию, если поле никогда не менялось");
  assert.equal(snapshot.balance, 0);
});

test("projectCharacter — balance/ramCapacity приводятся к числу", () => {
  const db = testDb();
  const key = "player-2";
  insertChange(db, key, { field: "balance", newValue: "150" });
  insertChange(db, key, { field: "ramCapacity", newValue: "8" });

  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.balance, 150);
  assert.equal(snapshot.ramCapacity, 8);
});

test("projectCharacter — daemons.add/remove работают как карта по daemonId", () => {
  const db = testDb();
  const key = "player-3";
  const daemon = { daemonId: "d1", name: "Mainframe", tier: "HARD", weight: 2, acquiredAt: 1, sourceRef: "nasos-4#1" };
  insertChange(db, key, { field: "daemons.add", newValue: JSON.stringify(daemon), reason: "BREACH_LOOT" });

  let snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.daemons.length, 1);
  assert.deepEqual(snapshot.daemons[0], daemon);

  insertChange(db, key, { field: "daemons.remove", newValue: JSON.stringify({ daemonId: "d1" }), reason: "BREACH_LOOT" });
  snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.daemons.length, 0);
});

test("projectCharacter — shards.add/decrypt/remove", () => {
  const db = testDb();
  const key = "player-4";
  const shard = { shardId: "s1", title: "Логи СБ", tier: "HARD", decrypted: false, acquiredAt: 1, sourceRef: null };
  insertChange(db, key, { field: "shards.add", newValue: JSON.stringify(shard), reason: "SHARD_SCAN" });

  let snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.shards[0].decrypted, false);

  insertChange(db, key, { field: "shards.decrypt", newValue: JSON.stringify({ shardId: "s1" }), reason: "SHARD_DECRYPT" });
  snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.shards[0].decrypted, true, "shards.decrypt должен пометить существующий шард расшифрованным");

  insertChange(db, key, { field: "shards.remove", newValue: JSON.stringify({ shardId: "s1" }), reason: "TRANSFER_OUT" });
  snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.shards.length, 0);
});

test("projectCharacter — shards.decrypt на несуществующий shardId ничего не ломает (тихо игнорируется)", () => {
  const db = testDb();
  const key = "player-4b";
  insertChange(db, key, { field: "shards.decrypt", newValue: JSON.stringify({ shardId: "нет-такого" }), reason: "SHARD_DECRYPT" });
  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.shards.length, 0);
});

test("projectCharacter — counters.breach считает success/partial/fail по тирам раздельно", () => {
  const db = testDb();
  const key = "player-5";
  insertChange(db, key, { field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT" });
  insertChange(db, key, { field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT" });
  insertChange(db, key, { field: "counters.breach", newValue: JSON.stringify({ tier: "BASE", outcome: "partial" }), reason: "BREACH_ATTEMPT" });

  const snapshot = projectCharacter(db, key)!;
  assert.deepEqual(snapshot.counters.breaches, {
    HARD: { success: 1, partial: 0, fail: 1 },
    BASE: { success: 0, partial: 1, fail: 0 },
  });
});

test("projectCharacter — counters.alert разделяет sent/suppressed", () => {
  const db = testDb();
  const key = "player-6";
  insertChange(db, key, { field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT" });
  insertChange(db, key, { field: "counters.alert", newValue: JSON.stringify({ suppressed: true }), reason: "ALERT_SUPPRESSED" });
  insertChange(db, key, { field: "counters.alert", newValue: JSON.stringify({ suppressed: true }), reason: "ALERT_SUPPRESSED" });

  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.counters.alertsSent, 1);
  assert.equal(snapshot.counters.alertsSuppressed, 2);
});

test("projectCharacter — counters.blocked группирует по reason", () => {
  const db = testDb();
  const key = "player-7";
  insertChange(db, key, { field: "counters.blocked", newValue: JSON.stringify({ reason: "COOLDOWN" }), reason: "BREACH_BLOCKED" });
  insertChange(db, key, { field: "counters.blocked", newValue: JSON.stringify({ reason: "COOLDOWN" }), reason: "BREACH_BLOCKED" });
  insertChange(db, key, { field: "counters.blocked", newValue: JSON.stringify({ reason: "ALREADY_CLAIMED" }), reason: "BREACH_BLOCKED" });

  const snapshot = projectCharacter(db, key)!;
  assert.deepEqual(snapshot.counters.breachesBlocked, { COOLDOWN: 2, ALREADY_CLAIMED: 1 });
});

test("projectCharacter — побитый JSON в new_value не роняет проекцию, просто игнорируется (parseSafe)", () => {
  const db = testDb();
  const key = "player-8";
  insertChange(db, key, { field: "daemons.add", newValue: "{не json" });
  insertChange(db, key, { field: "balance", newValue: "42" });

  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.daemons.length, 0);
  assert.equal(snapshot.balance, 42);
});

test("projectCharacter — lastSeenAt/lastSeq берутся как максимум по всем записям, а не по последней в списке", () => {
  const db = testDb();
  const key = "player-9";
  insertChange(db, key, { field: "callsign", newValue: "A", receivedAt: 500 });
  insertChange(db, key, { field: "faction", newValue: "NEON_DRAGONS", receivedAt: 3000 });
  insertChange(db, key, { field: "balance", newValue: "1", receivedAt: 1500 });

  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.lastSeenAt, 3000);
});

test("projectCharacter — slotsClaimed берётся из slot_claims (revoked=0), а не из changes", () => {
  const db = testDb();
  const key = "player-10";
  insertChange(db, key, { field: "callsign", newValue: "X" });

  db.prepare(`INSERT INTO slot_claims (slot_ref, claimant_key, claimed_at, granted_by, revoked) VALUES (?, ?, ?, 'SERVER', 0)`).run(
    "nasos-4#0",
    key,
    Date.now(),
  );
  db.prepare(`INSERT INTO slot_claims (slot_ref, claimant_key, claimed_at, granted_by, revoked) VALUES (?, ?, ?, 'SERVER', 1)`).run(
    "nasos-4#1",
    key,
    Date.now(),
  );

  const snapshot = projectCharacter(db, key)!;
  assert.equal(snapshot.counters.slotsClaimed, 1, "revoked-заявка не должна считаться");
});
