import { test } from "node:test";
import assert from "node:assert/strict";
import { seedPlayer, setup, type Device } from "./testHelpers.js";
import { testDevice } from "./testUtil.js";

/**
 * Записи мира «Сети» (docs/netrun-world-records.md, §2): субъект и автор — ключ мира, подписывает Мост. Тот же формат подписи и
 * та же пара EC P-256, что у телефона, поэтому «мир» в тестах — обычное тестовое устройство.
 */

const SESSION = "s_9f2c41d07a3e5b60";
const RUNNER = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE";

/** Пять записей из контракта: вход, выход, флэтлайн (другой сессией), смена владельца предмета, тревога аудитора. */
function worldRecords(world: Device) {
  const run = (s: string, extra: object) => JSON.stringify({ session: s, runner: RUNNER, callsign: "Призрак", terminal: "t03", node: "node_07", ...extra });
  return [
    world.change({ field: "net.run", newValue: run(SESSION, { deck: 3, protected: true }), reason: "NET_ENTER", sourceRef: SESSION }),
    world.change({
      field: "net.run",
      newValue: run(SESSION, { outcome: "emergency", duration_s: 400, returned: 2, burned: 1, left_in_node: 1, eddies_paid: 0, lockdown_until: 0 }),
      reason: "NET_EXIT",
      sourceRef: SESSION,
    }),
    world.change({
      field: "net.run",
      newValue: run("s_aaaaaaaaaaaaaaaa", { outcome: "black_ice", disconnect: false, duration_s: 90, left_in_node: 3, cause: "флэтлайн", alert: "al_431_0" }),
      reason: "NET_FLATLINE",
      sourceRef: "s_aaaaaaaaaaaaaaaa",
    }),
    world.change({
      field: "net.item",
      newValue: JSON.stringify({ item: "it_4c1a0b2e9d7f6a81", kind: "SHARD", from: `deck:${SESSION}`, to: "node:node_07", session: SESSION, runner: RUNNER, op: "run.finish", rid: `finish:${SESSION}` }),
      reason: "NET_ITEM_OWNER",
      sourceRef: "it_4c1a0b2e9d7f6a81",
    }),
    world.change({
      field: "net.alert",
      newValue: JSON.stringify({ alert: "al_a_3f9c1e07b2d4", kind: "auditor_item_owner", msg: "it_02bb: владелец deck:s_9f2c, но сессия закрыта", items: ["it_02bb"] }),
      reason: "NET_ALERT",
      sourceRef: "al_a_3f9c1e07b2d4",
    }),
  ];
}

const post = (app: Awaited<ReturnType<typeof setup>>["app"], records: unknown[]) => app.inject({ method: "POST", url: "/api/changes", payload: { records } });

test("capabilities: открытый, без сессии мастера, объявляет world_records и world_events", async () => {
  const { app } = await setup();
  const res = await app.inject({ method: "GET", url: "/api/capabilities" });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().world_records, 1);
  assert.equal(res.json().world_events, 1);
});

test("записи мира из контракта принимаются, а не уходят в rejected (иначе kit молча удалит их из очереди)", async () => {
  const { app } = await setup();
  const world = testDevice();
  const records = worldRecords(world);
  const res = await post(app, records);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json().rejected, []);
  assert.equal(res.json().accepted.length, records.length);
});

test("повтор той же записи мира — «принято» без второй строки, другая запись с занятым id — отказ", async () => {
  const { app, db } = await setup();
  const world = testDevice();
  const [enter] = worldRecords(world);
  await post(app, [enter]);
  const again = await post(app, [enter]);
  assert.deepEqual(again.json().rejected, []);
  assert.equal((db.prepare("SELECT COUNT(*) AS n FROM changes WHERE id = ?").get(enter.id) as { n: number }).n, 1);

  const other = world.change({ field: "net.run", newValue: "{}", reason: "NET_ENTER", sourceRef: "x" });
  const clash = await post(app, [{ ...other, id: enter.id }]);
  assert.match(clash.json().rejected[0].error, /id already used|invalid signature/);
});

test("запись мира с чужим автором (actor ≠ subject) отклоняется — правило для NET_* то же, что у остальных причин", async () => {
  const { app } = await setup();
  const world = testDevice();
  const stranger = testDevice();
  const bad = world.change({ field: "net.alert", newValue: "{}", reason: "NET_ALERT", actor: stranger.publicKeyB64 });
  const res = await post(app, [bad]);
  assert.match(res.json().rejected[0].error, /actor must equal subjectKeyB64/);
});

test("net.* обязан быть JSON-объектом — строка или массив отклоняются", async () => {
  const { app } = await setup();
  const world = testDevice();
  const res = await post(app, [world.change({ field: "net.run", newValue: "[1,2]", reason: "NET_ENTER" }), world.change({ field: "net.item", newValue: "просто текст", reason: "NET_ITEM_OWNER" })]);
  assert.equal(res.json().rejected.length, 2);
});

test("ключ мира не становится игроком: не в списке игроков, не в «Обзоре», не в «на связи»", async () => {
  const { app, headers } = await setup();
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON", balance: 100 });
  const world = testDevice();
  await post(app, worldRecords(world));
  // heartbeat Моста тоже не делает его «игроком на связи»
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: world.publicKeyB64 } });

  const players = (await app.inject({ method: "GET", url: "/api/players", headers })).json() as { publicKeyB64: string }[];
  assert.deepEqual(players.map((p) => p.publicKeyB64), [alice.publicKeyB64]);

  const overview = (await app.inject({ method: "GET", url: "/api/overview", headers })).json() as { players: { online: number; total: number } };
  assert.equal(overview.players.total, 1);
  assert.ok(overview.players.online <= 1);
});

test("в ленте событий записи мира — тип «Сеть», субъект «Сеть», фраза по-русски; флэтлайн виден как тревога", async () => {
  const { app, headers } = await setup();
  const world = testDevice();
  await post(app, worldRecords(world));

  const res = (await app.inject({ method: "GET", url: "/api/events?kind=net", headers })).json() as {
    total: number;
    records: { reason: string; human: { kind: string; subject: string; body: string } }[];
  };
  assert.equal(res.total, 5);
  assert.ok(res.records.every((r) => r.human.subject === "Сеть"));
  const byReason = (reason: string) => res.records.find((r) => r.reason === reason)!.human;
  assert.match(byReason("NET_ENTER").body, /«Призрак» сдал деку \(предметов: 3\).*терминал t03, узел node_07/);
  assert.match(byReason("NET_EXIT").body, /вышел из Сети: аварийный выход.*вернулось 2, сгорело 1, осталось в узле 1/);
  assert.equal(byReason("NET_FLATLINE").kind, "alert");
  assert.match(byReason("NET_FLATLINE").body, /ФЛЭТЛАЙН: «Призрак»/);
  assert.match(byReason("NET_ITEM_OWNER").body, /шард it_4c1a0b2e9d7f6a81: дека → узел node_07/);
  assert.match(byReason("NET_ALERT").body, /тревога аудитора \(auditor_item_owner\)/);

  const meta = (await app.inject({ method: "GET", url: "/api/meta", headers })).json() as { reasons: { code: string }[]; kinds: { code: string }[] };
  assert.ok(meta.reasons.some((r) => r.code === "NET_FLATLINE"));
  assert.ok(meta.kinds.some((k) => k.code === "net"));
});

test("записи игроков не затронуты: баланс и позывной считаются как раньше, когда рядом пишет мир", async () => {
  const { app, headers } = await setup();
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON", balance: 100 });
  await post(app, worldRecords(testDevice()));
  const [p] = (await app.inject({ method: "GET", url: "/api/players", headers })).json() as { callsign: string; balance: number }[];
  assert.equal(p.callsign, "Alice");
  assert.equal(p.balance, 100);
  const history = (await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}`, headers })).json() as { callsign: string };
  assert.equal(history.callsign, "Alice");
});
