import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

test("heartbeat пустым батчем держит игрока «на связи», хотя свежих записей изменений нет", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const alice = testDevice();

  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [alice.change({ field: "callsign", oldValue: null, newValue: "Alice", reason: "CHARACTER_CREATED" })] },
  });
  // запись «состарилась» на 10 минут — вне окна «на связи»
  db.prepare(`UPDATE changes SET received_at = received_at - 10 * 60 * 1000`).run();

  const before = (await app.inject({ method: "GET", url: "/api/players", headers })).json();
  assert.equal(before[0].online, false, "без heartbeat игрок с давними записями не на связи");
  assert.equal((await app.inject({ method: "GET", url: "/api/overview", headers })).json().players.online, 0);

  // телефон присылает heartbeat — пустой батч с ключом
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: alice.publicKeyB64 } });

  const after = (await app.inject({ method: "GET", url: "/api/players", headers })).json();
  assert.equal(after[0].online, true, "heartbeat отмечает игрока на связи");
  assert.equal((await app.inject({ method: "GET", url: "/api/overview", headers })).json().players.online, 1);
});

test("heartbeat неизвестного игрока (без единой записи) не раздувает счётчик «на связи»", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const stranger = testDevice();

  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: stranger.publicKeyB64 } });
  assert.equal((await app.inject({ method: "GET", url: "/api/overview", headers })).json().players.online, 0);
});
