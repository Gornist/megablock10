import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

async function auth(app: ReturnType<typeof testApp>, db: ReturnType<typeof testDb>) {
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  return { authorization: `Bearer ${session}` };
}

test("GET /api/transfers — сводит TRANSFER_OUT и TRANSFER_IN по txId в одну запись", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();
  const bob = testDevice();

  const out = alice.change({ field: "balance", oldValue: "100", newValue: "80", reason: "TRANSFER_OUT", sourceRef: "tx-1" });
  const inRec = bob.change({ field: "balance", oldValue: "0", newValue: "20", reason: "TRANSFER_IN", sourceRef: "tx-1", actor: alice.publicKeyB64 });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [out, inRec] } });

  const res = await app.inject({ method: "GET", url: "/api/transfers", headers });
  assert.equal(res.statusCode, 200);
  const transfers = res.json();
  assert.equal(transfers.length, 1);
  assert.equal(transfers[0].txId, "tx-1");
  assert.equal(transfers[0].from, alice.publicKeyB64);
  assert.equal(transfers[0].to, bob.publicKeyB64);
  // amount — реальная сумма перевода (old − new баланса отправителя: 100 − 80),
  // не итоговый остаток отправителя после списания (см. routes/transfers.ts).
  assert.equal(transfers[0].amount, 20);
  assert.equal(transfers[0].oneSided, false);
  assert.ok(transfers[0].confirmedAt !== null);
});

test("GET /api/transfers — TRANSFER_OUT без парного TRANSFER_IN помечается oneSided", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();

  const out = alice.change({ field: "balance", oldValue: "50", newValue: "30", reason: "TRANSFER_OUT", sourceRef: "tx-2" });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [out] } });

  const res = await app.inject({ method: "GET", url: "/api/transfers", headers });
  const transfers = res.json();
  assert.equal(transfers.length, 1);
  assert.equal(transfers[0].amount, 20);
  assert.equal(transfers[0].oneSided, true);
  assert.equal(transfers[0].confirmedAt, null);
});

test("GET /api/transfers — TRANSFER_IN без парного TRANSFER_OUT тоже показывается, помеченным oneSided", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();
  const bob = testDevice();

  const inRec = bob.change({ field: "balance", oldValue: "0", newValue: "10", reason: "TRANSFER_IN", sourceRef: "tx-3", actor: alice.publicKeyB64 });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [inRec] } });

  const res = await app.inject({ method: "GET", url: "/api/transfers", headers });
  const transfers = res.json();
  assert.equal(transfers.length, 1);
  assert.equal(transfers[0].txId, "tx-3");
  assert.equal(transfers[0].from, alice.publicKeyB64);
  assert.equal(transfers[0].to, bob.publicKeyB64);
  assert.equal(transfers[0].amount, 10);
  assert.equal(transfers[0].sentAt, null);
  assert.equal(transfers[0].oneSided, true);
});

test("GET /api/transfers — без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "GET", url: "/api/transfers" });
  assert.equal(res.statusCode, 401);
});

test("GET /api/transfers — TRANSFER_CANCELLED помечает перевод отменённым и снимает флаг oneSided", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();

  const out = alice.change({ field: "balance", oldValue: "50", newValue: "30", reason: "TRANSFER_OUT", sourceRef: "tx-c" });
  const cancel = alice.change({ field: "balance", oldValue: "30", newValue: "50", reason: "TRANSFER_CANCELLED", sourceRef: "tx-c" });
  const res0 = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [out, cancel] } });
  assert.equal(res0.json().accepted.length, 2, "сервер должен знать причину TRANSFER_CANCELLED");

  const transfers = (await app.inject({ method: "GET", url: "/api/transfers", headers })).json();
  assert.equal(transfers.length, 1);
  assert.equal(transfers[0].amount, 20);
  assert.ok(transfers[0].cancelledAt !== null);
  assert.equal(transfers[0].oneSided, false);

  const snapshot = (await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}`, headers })).json();
  assert.equal(snapshot.snapshot?.balance ?? snapshot.balance, 50, "баланс на дашборде после отмены снова 50");
});

test("POST /api/changes — передача предмета: ITEM_TRANSFER_* принимаются, shards.remove убирает шард из снимка", async () => {
  const db = testDb();
  const app = testApp(db);
  const headers = await auth(app, db);
  const alice = testDevice();

  const shard = { shardId: "shard:x#0", title: "Схемы", tier: "2", decrypted: false, acquiredAt: 1, sourceRef: "x#0" };
  const add = alice.change({ field: "shards.add", oldValue: null, newValue: JSON.stringify(shard), reason: "BREACH_LOOT", sourceRef: "x#0" });
  const out = alice.change({ field: "shards.remove", oldValue: null, newValue: JSON.stringify({ shardId: "shard:x#0" }), reason: "ITEM_TRANSFER_OUT", sourceRef: "item-1" });
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [add, out] } });
  assert.equal(res.json().accepted.length, 2, "сервер должен знать причину ITEM_TRANSFER_OUT");

  const snapshot = (await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}`, headers })).json();
  assert.equal((snapshot.snapshot?.shards ?? snapshot.shards).length, 0, "после передачи шарда у отправителя не осталось");

  const back = alice.change({ field: "shards.add", oldValue: null, newValue: JSON.stringify(shard), reason: "ITEM_TRANSFER_CANCELLED", sourceRef: "item-1" });
  const res2 = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [back] } });
  assert.equal(res2.json().accepted.length, 1, "сервер должен знать причину ITEM_TRANSFER_CANCELLED");
});
