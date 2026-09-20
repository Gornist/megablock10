import { test } from "node:test";
import assert from "node:assert/strict";
import { setup, seedPlayer, poll } from "./testHelpers.js";

test("announcements: рассылка доходит через heartbeat, статус доставки растёт после ack, в живую ленту не попадает", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X" });
  const b = await seedPlayer(app, { callsign: "Bob", faction: "Y" });

  const dry = await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Тревога", faction: "X", dryRun: true } });
  assert.equal(dry.json().count, 1);
  assert.deepEqual(dry.json().recipients, ["Alice"]);

  const sent = await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "  Сбор у входа  ", all: true } });
  assert.equal(sent.statusCode, 200);
  assert.equal(sent.json().count, 2);

  const pending = (await poll(app, a)).json().pending;
  assert.equal(pending.length, 1);
  assert.equal(pending[0].field, "announcement");
  assert.equal(pending[0].newValue, "Сбор у входа");

  let list = (await app.inject({ method: "GET", url: "/api/announcements", headers })).json();
  assert.equal(list.length, 1);
  assert.equal(list[0].recipients, 2);
  assert.equal(list[0].delivered, 0, "пока ack не пришёл — не доставлено");
  assert.equal(list[0].masterName, "Мастер-1");

  await poll(app, a, [pending[0].id]);
  list = (await app.inject({ method: "GET", url: "/api/announcements", headers })).json();
  assert.equal(list[0].delivered, 1);

  const rec = (await app.inject({ method: "GET", url: `/api/announcements/${list[0].id}/recipients`, headers })).json();
  assert.deepEqual(rec.map((r: { callsign: string; delivered: boolean }) => [r.callsign, r.delivered]), [["Bob", false], ["Alice", true]], "недоставленные — первыми");
  assert.equal(b.publicKeyB64.length > 0, true);

  const feed = (await app.inject({ method: "GET", url: "/api/changes/recent?since=0", headers })).json().records as { field: string }[];
  assert.ok(!feed.some((r) => r.field === "announcement"), "100 строк «сообщение мастера» не должны забивать ленту");
});

test("announcements: валидация текста и адресатов", async () => {
  const { app, headers } = await setup();
  await seedPlayer(app, { callsign: "Alice", faction: "X" });
  const post = (payload: object) => app.inject({ method: "POST", url: "/api/announcements", headers, payload });
  assert.equal((await post({ text: "", all: true })).statusCode, 400);
  assert.equal((await post({ text: "a".repeat(501), all: true })).statusCode, 400);
  assert.equal((await post({ text: "ok" })).statusCode, 400, "не выбраны адресаты");
  assert.equal((await post({ text: "ok", faction: "нет-такой" })).statusCode, 400, "в выбранной фракции никого нет");
  assert.equal((await app.inject({ method: "GET", url: "/api/announcements/unknown/recipients", headers })).statusCode, 404);
});
