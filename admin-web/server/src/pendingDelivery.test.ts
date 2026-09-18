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

test("одна и та же правка не доставляется дважды", async () => {
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

  const poll = async () =>
    (
      await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: device.publicKeyB64 } })
    ).json().pending.length;

  assert.equal(await poll(), 1);
  assert.equal(await poll(), 0, "повторный опрос не должен вернуть уже доставленную правку");
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
