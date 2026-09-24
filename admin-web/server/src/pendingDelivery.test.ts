import { test } from "node:test";
import assert from "node:assert/strict";
import { MAX_APPLY_ATTEMPTS } from "./lib/changeIngest.js";
import { computeAttention } from "./lib/attention.js";
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

test("POST /api/players/:key/override отклоняет значения, которые устройство не сможет применить", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();
  const send = async (field: string, newValue: unknown) =>
    (
      await app.inject({
        method: "POST",
        url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
        headers: { authorization: `Bearer ${session}` },
        payload: { field, newValue, reason: "тест" },
      })
    ).statusCode;

  assert.equal(await send("balance", "abc"), 400);
  assert.equal(await send("balance", null), 400);
  assert.equal(await send("ramCapacity", "99"), 400);
  assert.equal(await send("callsign", "  "), 400);
  assert.equal(await send("balance", "-50"), 200);
  assert.equal(await send("ramCapacity", "10"), 200);
});

// Правка, которую телефон не смог применить, не подтверждается и не теряется молча: сервер шлёт её снова, считает отказы,
// а после MAX_APPLY_ATTEMPTS (или сразу, если повтор бесполезен) перестаёт слать и показывает мастеру.
async function overrideFor(app: Awaited<ReturnType<typeof testApp>>, session: string, key: string, field: string, newValue: string) {
  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(key)}/override`,
    headers: { authorization: `Bearer ${session}` },
    payload: { field, newValue, reason: "тест" },
  });
  assert.equal(res.statusCode, 200);
}

function pollerFor(app: Awaited<ReturnType<typeof testApp>>, key: string) {
  return async (extra: { ackIds?: string[]; failures?: unknown[] } = {}) =>
    (await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: key, ...extra } })).json().pending as { id: string }[];
}

test("неприменённая правка приходит снова и не считается доставленной", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();
  await overrideFor(app, session, device.publicKeyB64, "balance", "500");
  const poll = pollerFor(app, device.publicKeyB64);

  const [edit] = await poll();
  const again = await poll({ failures: [{ id: edit.id, error: "SQLiteException: disk I/O error", permanent: false }] });
  assert.deepEqual(again.map((p) => p.id), [edit.id], "после отказа правка приходит снова");
  const row = db.prepare(`SELECT delivered, attempts, last_error, failed_at FROM master_pending WHERE change_id = ?`).get(edit.id) as {
    delivered: number; attempts: number; last_error: string; failed_at: number | null;
  };
  assert.deepEqual(row, { delivered: 0, attempts: 1, last_error: "SQLiteException: disk I/O error", failed_at: null });

  assert.equal((await poll({ ackIds: [edit.id] })).length, 0, "применилась со второй попытки — подтверждение работает как раньше");
});

test("после MAX_APPLY_ATTEMPTS отказов правку больше не шлют, мастер видит её в «Требует внимания»", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();
  await overrideFor(app, session, device.publicKeyB64, "ramCapacity", "10");
  const poll = pollerFor(app, device.publicKeyB64);

  const [edit] = await poll();
  let pending = [edit];
  for (let i = 0; i < MAX_APPLY_ATTEMPTS; i++) pending = await poll({ failures: [{ id: edit.id, error: "сбой записи", permanent: false }] });
  assert.equal(pending.length, 0, "сервер сдался — больше не шлёт");

  const item = computeAttention(db).find((a) => a.kind === "override_failed");
  assert.ok(item, "мастер видит неприменённую правку");
  assert.equal(item.subjectKey, device.publicKeyB64);
  assert.match(item.detail, /ramCapacity → «10»: сбой записи \(попыток: 5\)/);
  assert.equal(computeAttention(db).filter((a) => a.kind === "override_undelivered").length, 0, "это не «ждёт игрока», а отказ");
});

test("правку, которую телефон не может применить в принципе, сервер перестаёт слать сразу", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();
  await overrideFor(app, session, device.publicKeyB64, "balance", "500");
  const poll = pollerFor(app, device.publicKeyB64);

  const [edit] = await poll();
  const after = await poll({ failures: [{ id: edit.id, error: "поле «x» не поддерживается этой версией приложения", permanent: true }] });
  assert.equal(after.length, 0);
  const row = db.prepare(`SELECT attempts, failed_at FROM master_pending WHERE change_id = ?`).get(edit.id) as { attempts: number; failed_at: number | null };
  assert.equal(row.attempts, 1);
  assert.notEqual(row.failed_at, null);
});

test("чужой ключ не может сообщить об отказе по правке другого устройства", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const alice = testDevice();
  const bob = testDevice();
  await overrideFor(app, session, alice.publicKeyB64, "balance", "1");
  const [edit] = await pollerFor(app, alice.publicKeyB64)();

  await pollerFor(app, bob.publicKeyB64)({ failures: [{ id: edit.id, error: "не моё", permanent: true }] });
  assert.deepEqual((await pollerFor(app, alice.publicKeyB64)()).map((p) => p.id), [edit.id]);
});
