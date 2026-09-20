import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testMaster } from "./testUtil.js";
import { setup, seedPlayer } from "./testHelpers.js";

test("watch: добавить с пометкой, увидеть у любого мастера, обновить пометку, снять", async () => {
  const { app, headers, db } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X" });
  const key = encodeURIComponent(a.publicKeyB64);

  assert.equal((await app.inject({ method: "PUT", url: "/api/watch/неизвестный", headers, payload: {} })).statusCode, 404);
  assert.equal((await app.inject({ method: "PUT", url: `/api/watch/${key}`, headers, payload: { note: "x".repeat(301) } })).statusCode, 400);
  assert.equal((await app.inject({ method: "PUT", url: `/api/watch/${key}`, headers, payload: { note: " подозрительный баланс " } })).statusCode, 200);

  const other = testMaster(db, "Мастер-2");
  const otherHeaders = { authorization: `Bearer ${await loginAs(app, other.name, other.token)}` };
  const list = (await app.inject({ method: "GET", url: "/api/watch", headers: otherHeaders })).json();
  assert.equal(list.length, 1);
  assert.equal(list[0].note, "подозрительный баланс");
  assert.equal(list[0].addedBy, "Мастер-1");

  await app.inject({ method: "PUT", url: `/api/watch/${key}`, headers: otherHeaders, payload: { note: "проверено" } });
  const updated = (await app.inject({ method: "GET", url: "/api/watch", headers })).json();
  assert.equal(updated.length, 1, "повторное добавление обновляет пометку, а не плодит записи");
  assert.equal(updated[0].note, "проверено");

  await app.inject({ method: "DELETE", url: `/api/watch/${key}`, headers });
  assert.equal((await app.inject({ method: "GET", url: "/api/watch", headers })).json().length, 0);
  assert.equal((await app.inject({ method: "GET", url: "/api/watch" })).statusCode, 401);
});
