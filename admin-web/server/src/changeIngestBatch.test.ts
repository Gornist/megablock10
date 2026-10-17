import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { testApp, testDb, testDevice } from "./testUtil.js";
import { seedPlayer, setup } from "./testHelpers.js";

/**
 * Приём `/api/changes`: порядок свёртки баланса держится на `seq`, поэтому две разные записи одного субъекта с одним seq — конфликт,
 * а не «последняя победила». И батч принимается одной транзакцией: сбой посреди него не оставляет половину записей и побочных эффектов.
 */

type Device = ReturnType<typeof testDevice>;
type App = ReturnType<typeof testApp>;
type Rec = ReturnType<Device["change"]>;

async function send(app: App, records: unknown[]) {
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records } });
  return { status: res.statusCode, body: res.json() as { accepted: string[]; rejected: { id: string; error: string }[] } };
}

/** Другая запись (другой id и содержимое) с уже занятым seq того же субъекта, подпись честная. */
function withSeq(device: Device, rec: Rec, seq: number, over: Partial<Rec> = {}): Rec {
  const next = { ...rec, ...over, id: randomUUID(), seq };
  return { ...next, signature: device.sign(device.signaturePayload(next)) };
}

const count = (db: ReturnType<typeof testDb>) => (db.prepare(`SELECT COUNT(*) AS n FROM changes`).get() as { n: number }).n;

test("конфликт seq: другая запись того же субъекта с занятым seq отвергается, первая цела", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const first = device.change({ field: "balance", oldValue: "0", newValue: "50", reason: "SHARD_SCAN" });
  assert.deepEqual((await send(app, [first])).body.accepted, [first.id]);

  const clash = withSeq(device, first, first.seq, { newValue: "9999" });
  const res = await send(app, [clash]);
  assert.deepEqual(res.body.accepted, []);
  assert.deepEqual(res.body.rejected, [{ id: clash.id, error: "seq already used by a different record" }]);

  assert.equal(count(db), 1, "в журнале только первая запись");
  const row = db.prepare(`SELECT id, new_value FROM changes WHERE subject_key = ? AND seq = ?`).get(first.subjectKeyB64, first.seq) as { id: string; new_value: string };
  assert.deepEqual(row, { id: first.id, new_value: "50" });
});

test("конфликт seq внутри одного батча: берётся первая, вторая отвергнута, остальные записи батча принимаются", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const a = device.change({ field: "balance", oldValue: "0", newValue: "10", reason: "SHARD_SCAN" });
  const dup = withSeq(device, a, a.seq, { newValue: "777" });
  const c = device.change({ field: "balance", oldValue: "10", newValue: "30", reason: "SHARD_SCAN" });

  const res = await send(app, [a, dup, c]);
  assert.deepEqual(res.body.accepted, [a.id, c.id]);
  assert.deepEqual(res.body.rejected, [{ id: dup.id, error: "seq already used by a different record" }]);
  assert.equal(count(db), 2);
});

test("один и тот же seq у разных субъектов — не конфликт", async () => {
  const db = testDb();
  const app = testApp(db);
  const alice = testDevice();
  const bob = testDevice();
  const a = alice.change({ field: "balance", oldValue: "0", newValue: "10", reason: "SHARD_SCAN" });
  const b = bob.change({ field: "balance", oldValue: "0", newValue: "20", reason: "SHARD_SCAN" });
  assert.equal(a.seq, b.seq);
  const res = await send(app, [a, b]);
  assert.deepEqual(res.body.rejected, []);
  assert.equal(count(db), 2);
});

const flatlineFor = (world: Device, runner: string, seq?: number) => {
  const rec = world.change({
    field: "net.run",
    newValue: JSON.stringify({ session: "s_1", runner, callsign: "Призрак", terminal: "t03", node: "node_07", outcome: "black_ice", disconnect: false, left_in_node: 3, cause: "флэтлайн", alert: "al_1" }),
    reason: "NET_FLATLINE",
    sourceRef: "s_1",
  });
  return seq === undefined ? rec : withSeq(world, rec, seq);
};

const flagCount = (db: ReturnType<typeof testDb>) => (db.prepare(`SELECT COUNT(*) AS n FROM net_runner_flags`).get() as { n: number }).n;

test("NET_FLATLINE с конфликтом seq отвергается целиком — флаг нетраннера не ставится", async () => {
  const { app, db } = await setup();
  const runner = await seedPlayer(app, { callsign: "Призрак", faction: "NEON", balance: 10 });
  const world = testDevice();
  const ok = world.change({ field: "net.run", newValue: JSON.stringify({ session: "s_0", runner: "ничей", outcome: "ok" }), reason: "NET_ENTER" });
  assert.deepEqual((await send(app, [ok])).body.rejected, []);
  assert.equal(flagCount(db), 0);

  const clash = flatlineFor(world, runner.publicKeyB64, ok.seq);
  const res = await send(app, [clash]);
  assert.deepEqual(res.body.rejected, [{ id: clash.id, error: "seq already used by a different record" }]);
  assert.equal(flagCount(db), 0, "отвергнутая запись не оставляет побочного эффекта");

  const fresh = flatlineFor(world, runner.publicKeyB64);
  assert.deepEqual((await send(app, [fresh])).body.rejected, []);
  assert.equal(flagCount(db), 1, "принятая — ставит");
});

test("исключение посреди батча откатывает весь батч, включая побочный эффект флэтлайна; повтор после починки принимает всё", async () => {
  const { app, db } = await setup();
  const runner = await seedPlayer(app, { callsign: "Призрак", faction: "NEON", balance: 10 });
  const before = count(db);
  const device = testDevice();
  const good = device.change({ field: "balance", oldValue: "0", newValue: "40", reason: "SHARD_SCAN" });
  const world = testDevice();
  const flat = flatlineFor(world, runner.publicKeyB64);
  const boom = device.change({ field: "balance", oldValue: "40", newValue: "666", reason: "SHARD_SCAN" });

  // Сбой БД на третьей записи (не ошибка проверки, а исключение из INSERT) — как заполненный диск или блокировка.
  db.exec(`CREATE TRIGGER boom BEFORE INSERT ON changes WHEN NEW.new_value = '666' BEGIN SELECT RAISE(ABORT, 'disk is on fire'); END`);
  const res = await send(app, [good, flat, boom]);
  assert.equal(res.status, 500);
  assert.deepEqual(res.body, { error: "internal error" } as never, "детали БД наружу не отдаются");
  assert.equal(count(db), before, "ни одной записи батча не осталось");
  assert.equal(flagCount(db), 0, "флаг нетраннера откатан вместе с записью");

  db.exec(`DROP TRIGGER boom`);
  const retry = await send(app, [good, flat, boom]);
  assert.deepEqual(retry.body.rejected, []);
  assert.deepEqual(retry.body.accepted, [good.id, flat.id, boom.id]);
  assert.equal(count(db), before + 3);
  assert.equal(flagCount(db), 1);
});
