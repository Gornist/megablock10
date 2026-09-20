import { test } from "node:test";
import assert from "node:assert/strict";
import { setup, seedPlayer, players, poll } from "./testHelpers.js";

test("bulk-override: dryRun ничего не пишет, apply правит только выбранную фракцию и ставит в очередь доставки", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  await seedPlayer(app, { callsign: "Bob", faction: "X", balance: 50 });
  const c = await seedPlayer(app, { callsign: "Cyd", faction: "Y", balance: 10 });

  const body = { field: "balance", newValue: "200", mode: "add", reason: "премия за акт", faction: "X" };
  const dry = await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { ...body, dryRun: true } });
  assert.equal(dry.statusCode, 200);
  assert.equal(dry.json().count, 2);
  assert.deepEqual(dry.json().changes.map((c: { newValue: string }) => c.newValue).sort(), ["250", "300"]);
  assert.equal((await players(app, headers)).find((p) => p.callsign === "Alice")?.balance, 100, "dryRun не должен менять баланс");

  const applied = await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: body });
  assert.equal(applied.statusCode, 200);
  assert.equal(applied.json().count, 2);

  const list = await players(app, headers);
  assert.equal(list.find((p) => p.callsign === "Alice")?.balance, 300);
  assert.equal(list.find((p) => p.callsign === "Bob")?.balance, 250);
  assert.equal(list.find((p) => p.callsign === "Cyd")?.balance, 10, "другая фракция не тронута");

  const pendingA = (await poll(app, a)).json().pending;
  assert.equal(pendingA.length, 1);
  assert.equal(pendingA[0].field, "balance");
  assert.equal(pendingA[0].newValue, "300");
  assert.equal((await poll(app, c)).json().pending.length, 0);
});

test("bulk-override: RAM в режиме add зажимается в потолок, игроки без изменений пропускаются", async () => {
  const { app, headers } = await setup();
  await seedPlayer(app, { callsign: "Low", faction: "X" });
  await seedPlayer(app, { callsign: "Max", faction: "X", ram: 13 });

  const res = await app.inject({
    method: "POST",
    url: "/api/players/bulk-override",
    headers,
    payload: { field: "ramCapacity", newValue: "10", mode: "add", reason: "апгрейд деки", all: true },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().count, 1, "Max уже на потолке — правки для него нет");
  assert.equal(res.json().unchanged, 1);
  const list = await players(app, headers);
  assert.equal(list.find((p) => p.callsign === "Low")?.ramCapacity, 13);
});

test("bulk-override: валидация — один способ выбора, только допустимые поля, обязательное основание", async () => {
  const { app, headers } = await setup();
  await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 5 });
  const post = (payload: object) => app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload });

  assert.equal((await post({ field: "balance", newValue: "1", reason: "r", all: true, faction: "X" })).statusCode, 400, "два способа выбора");
  assert.equal((await post({ field: "balance", newValue: "1", reason: "r" })).statusCode, 400, "ни одного способа выбора");
  assert.equal((await post({ field: "callsign", newValue: "Z", reason: "r", all: true })).statusCode, 400, "позывной массово не правим");
  assert.equal((await post({ field: "balance", newValue: "1", reason: " ", all: true })).statusCode, 400, "основание обязательно");
  assert.equal((await post({ field: "balance", newValue: "1", reason: "r", all: true, mode: "mul" })).statusCode, 400);
  assert.equal((await post({ field: "faction", newValue: "1", mode: "add", reason: "r", all: true })).statusCode, 400, "add для фракции бессмыслен");
  assert.equal((await post({ field: "balance", newValue: "x", reason: "r", all: true })).statusCode, 400);
  const noAuth = await app.inject({ method: "POST", url: "/api/players/bulk-override", payload: { field: "balance", newValue: "1", reason: "r", all: true } });
  assert.equal(noAuth.statusCode, 401);
});

test("override одному игроку: режим add прибавляет к текущему", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "-30", mode: "add", reason: "штраф" },
  });
  assert.equal(res.statusCode, 200);
  assert.equal((await players(app, headers))[0].balance, 70);
});

test("режим add принимает прибавку со знаком «+» (так её и вводит мастер)", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });
  const res = await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "+200", mode: "add", reason: "премия" },
  });
  assert.equal(res.statusCode, 200);
  assert.equal((await players(app, headers))[0].balance, 300);
  const bulk = await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { field: "balance", newValue: " +5 ", mode: "add", reason: "r", all: true, dryRun: true } });
  assert.equal(bulk.json().changes[0].newValue, "305");
});
