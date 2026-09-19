import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

/**
 * §6.3 ТЗ — самая важная (и самая новая) часть протокола: правка мастера
 * должна долететь до устройства ЧЕРЕЗ ТОТ ЖЕ POST /api/changes, которым
 * устройство просто опрашивает коллектор (даже с пустым records), потому
 * что push-канала нет — см. ChangeRecordStore.kt на клиенте.
 */
test("правка мастера приходит устройству пустым опросом (records: []) с его собственным ключом", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();

  const overrideRes = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "balance", newValue: "777", reason: "тестовая правка" },
  });
  assert.equal(overrideRes.statusCode, 200);

  const poll = await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [], subjectKeyB64: device.publicKeyB64 },
  });
  const body = poll.json();
  assert.equal(body.pending.length, 1);
  assert.equal(body.pending[0].field, "balance");
  assert.equal(body.pending[0].newValue, "777");
  assert.equal(body.pending[0].reason, "MASTER_OVERRIDE");
  assert.equal(body.pending[0].sourceRef, "тестовая правка");
});

test("правка доставляется повторно, пока устройство не подтвердит применение (ackIds)", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "ramCapacity", newValue: "10", reason: "тест" },
  });

  const poll = async (ackIds: string[] = []) =>
    (
      await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: device.publicKeyB64, ackIds } })
    ).json().pending as { id: string }[];

  const first = await poll();
  assert.equal(first.length, 1);
  assert.equal((await poll()).length, 1, "без ack правка должна прийти снова (ответ мог потеряться)");
  assert.equal((await poll([first[0].id])).length, 0, "после ack правка больше не доставляется");
  assert.equal((await poll()).length, 0);
});

test("чужой ключ не может подтвердить правку другого устройства", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const alice = testDevice();
  const bob = testDevice();

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "balance", newValue: "1", reason: "для Алисы" },
  });
  const pending = (await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: alice.publicKeyB64 } })).json().pending;
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: bob.publicKeyB64, ackIds: [pending[0].id] } });
  const again = (await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: alice.publicKeyB64 } })).json().pending;
  assert.equal(again.length, 1);
});

test("устройство не может прислать запись с причиной MASTER_OVERRIDE", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();
  const forged = device.change({ field: "balance", oldValue: "0", newValue: "999999", reason: "MASTER_OVERRIDE", sourceRef: "fake" });
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [forged] } });
  assert.equal(res.json().accepted.length, 0);
  assert.equal(res.json().rejected.length, 1);
});

test("правка для другого устройства не приходит при опросе своим ключом", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const alice = testDevice();
  const bob = testDevice();

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "balance", newValue: "50", reason: "для Алисы" },
  });

  const poll = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: bob.publicKeyB64 } });
  assert.equal(poll.json().pending.length, 0);
});

test("правка также приходит внутри обычного (непустого) батча, если он касается того же subject", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "callsign", newValue: "NEWNAME", reason: "тест" },
  });

  const record = device.change({ field: "balance", oldValue: "0", newValue: "5", reason: "BREACH_EDDIES", sourceRef: "attempt-1" });
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [record] } });
  assert.equal(res.json().pending.length, 1);
});

test("POST /api/players/:key/override отклоняет попытку править коллекционное поле (не из допустимого списка)", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();

  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "daemons.add", newValue: "{}", reason: "нельзя" },
  });
  assert.equal(res.statusCode, 400);
});

test("POST /api/players/:key/override требует непустое основание", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();

  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field: "balance", newValue: "1", reason: "" },
  });
  assert.equal(res.statusCode, 400);
});

test("POST /api/players/:key/override без мастерского токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const device = testDevice();

  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
    payload: { field: "balance", newValue: "1", reason: "x" },
  });
  assert.equal(res.statusCode, 401);
});
