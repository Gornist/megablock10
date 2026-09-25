import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

/**
 * Приём записей не принимает «что пришло»: занятый id с другим содержимым — конфликт, а не «уже есть»; значение не того вида
 * отбраковывается при приёме, а не пропускается молча свёрткой. И правка мастера не бывает без записи в журнале мастера.
 */
async function send(app: ReturnType<typeof testApp>, records: unknown[]) {
  return (await app.inject({ method: "POST", url: "/api/changes", payload: { records } })).json() as {
    accepted: string[];
    rejected: { id: string; error: string }[];
  };
}

test("повтор той же записи — «принято», другая запись с тем же id — конфликт", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const first = device.change({ field: "balance", oldValue: "0", newValue: "50", reason: "SHARD_SCAN" });
  assert.deepEqual((await send(app, [first])).accepted, [first.id]);
  assert.deepEqual((await send(app, [first])).accepted, [first.id], "повтор той же записи идемпотентен");

  const other = device.change({ field: "balance", oldValue: "50", newValue: "80", reason: "SHARD_SCAN" });
  const clash = { ...other, id: first.id };
  clash.signature = device.sign(device.signaturePayload(clash));   // подпись честная — различается только содержимое
  const res = await send(app, [clash]);
  assert.deepEqual(res.accepted, []);
  assert.deepEqual(res.rejected, [{ id: first.id, error: "id already used by a different record" }]);
  const row = db.prepare(`SELECT new_value FROM changes WHERE id = ?`).get(first.id) as { new_value: string };
  assert.equal(row.new_value, "50", "первая запись не тронута");
});

test("значения не того вида отбраковываются при приёме", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const bad = [
    device.change({ field: "balance", oldValue: "0", newValue: "сто", reason: "SHARD_SCAN" }),
    device.change({ field: "balance", oldValue: "0", newValue: "1.5", reason: "SHARD_SCAN" }),
    device.change({ field: "ramCapacity", oldValue: "6", newValue: "99", reason: "RAM_UPGRADE" }),
    device.change({ field: "callsign", newValue: "x".repeat(65), reason: "CHARACTER_CREATED" }),
    device.change({ field: "shards.add", newValue: "не json", reason: "SHARD_SCAN" }),
    device.change({ field: "counters.breach", newValue: "[1,2]", reason: "BREACH_ATTEMPT" }),
    device.change({ field: "balance", oldValue: "0", newValue: "10", reason: "SHARD_SCAN", sourceRef: "r".repeat(201) }),
  ];
  const res = await send(app, bad);
  assert.deepEqual(res.accepted, []);
  assert.equal(res.rejected.length, bad.length);
  assert.equal((db.prepare(`SELECT COUNT(*) AS n FROM changes`).get() as { n: number }).n, 0);
});

test("обычные записи телефона проходят проверку значений", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const good = [
    device.change({ field: "callsign", newValue: "V", reason: "CHARACTER_CREATED" }),
    device.change({ field: "balance", oldValue: "0", newValue: "-40", reason: "TRANSFER_OUT" }),
    device.change({ field: "ramCapacity", oldValue: "6", newValue: "13", reason: "RAM_UPGRADE" }),
    device.change({ field: "shards.add", newValue: JSON.stringify({ shardId: "s-1", title: "Чертёж" }), reason: "SHARD_SCAN" }),
    device.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "BASE", outcome: "success" }), reason: "BREACH_ATTEMPT" }),
    device.change({ field: "callsign", oldValue: "V", newValue: "", reason: "CHARACTER_RESET" }),
  ];
  const res = await send(app, good);
  assert.deepEqual(res.rejected, []);
  assert.equal(res.accepted.length, good.length);
});

test("правка мастера и запись в его журнал — одна транзакция", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();
  db.exec(`DROP TABLE audit_master`);   // журнал недоступен — как если бы запись в него упала посреди операции

  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "balance", newValue: "500", reason: "штраф" },
  });
  assert.equal(res.statusCode, 500);
  assert.equal((db.prepare(`SELECT COUNT(*) AS n FROM changes`).get() as { n: number }).n, 0, "правки без записи в журнале нет");
  assert.equal((db.prepare(`SELECT COUNT(*) AS n FROM master_pending`).get() as { n: number }).n, 0, "и доставлять нечего");
});
