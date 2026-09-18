import { test } from "node:test";
import assert from "node:assert/strict";
import { testApp, testDb, testDevice } from "./testUtil.js";

test("POST /api/changes принимает валидный батч и он виден в снимке персонажа", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();

  const res = await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        device.change({ field: "callsign", newValue: "V_KANG", reason: "CHARACTER_CREATED" }),
        device.change({ field: "faction", newValue: "NEON_DRAGONS", reason: "CHARACTER_CREATED" }),
      ],
    },
  });

  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.accepted.length, 2);
  assert.deepEqual(body.rejected, []);
  assert.equal(body.knownSeq[device.publicKeyB64], 2);
});

test("POST /api/changes отбраковывает запись с испорченной подписью, не роняя весь батч", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();

  const good = device.change({ field: "callsign", newValue: "V_KANG", reason: "CHARACTER_CREATED" });
  const tampered = device.change({ field: "balance", oldValue: "0", newValue: "50", reason: "BREACH_EDDIES" });
  tampered.newValue = "999999"; // подменили значение уже после подписи

  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [good, tampered] } });

  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.deepEqual(body.accepted, [good.id]);
  assert.equal(body.rejected.length, 1);
  assert.equal(body.rejected[0].id, tampered.id);
  assert.match(body.rejected[0].error, /signature/);
});

test("POST /api/changes — повторная отправка того же батча идемпотентна (пункт 13 чек-листа ТЗ)", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const records = [device.change({ field: "callsign", newValue: "V_KANG", reason: "CHARACTER_CREATED" })];

  const first = await app.inject({ method: "POST", url: "/api/changes", payload: { records } });
  const second = await app.inject({ method: "POST", url: "/api/changes", payload: { records } });

  assert.deepEqual(first.json().accepted, second.json().accepted);
  assert.deepEqual(second.json().rejected, []);

  const countRow = db.prepare("SELECT COUNT(*) AS n FROM changes").get() as { n: number };
  assert.equal(countRow.n, 1, "повтор не должен создавать дубль строки в changes");
});

test("POST /api/changes отклоняет неизвестное поле/причину", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();

  const badField = device.change({ field: "not.a.real.field", newValue: "x", reason: "CHARACTER_CREATED" });
  const badReason = device.change({ field: "callsign", newValue: "x", reason: "NOT_A_REAL_REASON" });

  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [badField, badReason] } });
  const body = res.json();
  assert.equal(body.accepted.length, 0);
  assert.equal(body.rejected.length, 2);
});

test("POST /api/changes — TRANSFER_IN подписывается получателем (subject), а actor — контрагент", async () => {
  const db = testDb();
  const app = testApp(db);
  const alice = testDevice();
  const bob = testDevice();

  const bobIn = bob.change({ field: "balance", oldValue: "0", newValue: "10", reason: "TRANSFER_IN", sourceRef: "tx-1", actor: alice.publicKeyB64 });

  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [bobIn] } });
  assert.deepEqual(res.json().accepted, [bobIn.id]);
});

test("POST /api/changes отклоняет TRANSFER_OUT, если actor не равен subject (подмена контрагента)", async () => {
  const db = testDb();
  const app = testApp(db);
  const alice = testDevice();
  const mallory = testDevice();

  const forged = alice.change({ field: "balance", oldValue: "10", newValue: "0", reason: "TRANSFER_OUT", sourceRef: "tx-1", actor: mallory.publicKeyB64 });

  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [forged] } });
  const body = res.json();
  assert.equal(body.accepted.length, 0);
  assert.match(body.rejected[0].error, /actor/);
});

test("POST /api/changes — размер батча ограничен", async () => {
  const db = testDb();
  const app = testApp(db);
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: new Array(201).fill(0) } });
  assert.equal(res.statusCode, 400);
});
