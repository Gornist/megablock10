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
