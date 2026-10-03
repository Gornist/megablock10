import { test } from "node:test";
import assert from "node:assert/strict";
import { seedPlayer, setup, type App } from "./testHelpers.js";
import { testDevice } from "./testUtil.js";
import { bridgeRunnerDocId, normalizeRunnerKey } from "./lib/netRunners.js";

/** Флаг нетраннера и карточка флэтлайна: приём NET_FLATLINE ставит флаг, мастер «щадит» — коллектор источник правды. */

const flatline = (world: ReturnType<typeof testDevice>, runner: string, over: Record<string, unknown> = {}, happenedAt = Date.now()) => {
  const rec = world.change({
    field: "net.run",
    newValue: JSON.stringify({ session: "s_1", runner, callsign: "Призрак", terminal: "t03", node: "node_07", outcome: "black_ice", disconnect: false, left_in_node: 3, cause: "флэтлайн", alert: "al_431_0", ...over }),
    reason: "NET_FLATLINE",
    sourceRef: "s_1",
  });
  return { ...rec, happenedAt, signature: world.sign(world.signaturePayload({ ...rec, happenedAt })) };
};

const post = (app: App, records: unknown[]) => app.inject({ method: "POST", url: "/api/changes", payload: { records } });
const enc = encodeURIComponent;

test("ключ нетраннера: обычный base64 как есть, base64url без «=» (адрес в браузере) приводится к нему; id документа Моста — r_ + sha256", () => {
  const std = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+/ab+c==";
  assert.equal(normalizeRunnerKey("MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE-_ab-c"), std);
  assert.equal(normalizeRunnerKey(std), std);
  assert.equal(normalizeRunnerKey("не ключ!"), null);
  // Эталон — как считает live_run.sh Моста: printf %s KEY_LIVE_ALICE | sha256sum | cut -c1-32.
  assert.equal(bridgeRunnerDocId("KEY_LIVE_ALICE"), "r_dab70cd3b302c608e7cd46839fe1b0e2");
  assert.match(bridgeRunnerDocId(std), /^r_[0-9a-f]{32}$/);
});

test("NET_FLATLINE ставит флаг и срочную тревогу со ссылкой на игрока; мир в игроки не попадает", async () => {
  const { app, headers } = await setup();
  const runner = await seedPlayer(app, { callsign: "Призрак", faction: "NEON", balance: 10 });
  const world = testDevice();
  const res = await post(app, [flatline(world, runner.publicKeyB64)]);
  assert.deepEqual(res.json().rejected, []);

  const flags = (await app.inject({ method: "GET", url: "/api/net/runners", headers })).json() as { runnerKey: string; blocked: boolean; knownPlayer: boolean; reason: string; callsign: string }[];
  assert.equal(flags.length, 1);
  assert.equal(flags[0].runnerKey, runner.publicKeyB64);
  assert.ok(flags[0].blocked && flags[0].knownPlayer);
  assert.equal(flags[0].reason, "флэтлайн");

  const attn = (await app.inject({ method: "GET", url: "/api/attention", headers })).json() as { items: { kind: string; severity: string; subjectKey?: string; detail: string }[] };
  const card = attn.items.find((i) => i.kind === "net_flatline")!;
  assert.equal(card.severity, "crit");
  assert.equal(card.subjectKey, runner.publicKeyB64);
  assert.match(card.detail, /Призрак.*node_07.*t03.*осталось предметов: 3/);
});

test("обрыв до флэтлайна — причина «обрыв до флэтлайна»", async () => {
  const { app, headers } = await setup();
  const runner = await seedPlayer(app, { callsign: "Призрак", faction: "NEON" });
  await post(app, [flatline(testDevice(), runner.publicKeyB64, { disconnect: true, cause: "обрыв до флэтлайна" })]);
  const [f] = (await app.inject({ method: "GET", url: "/api/net/runners", headers })).json() as { reason: string }[];
  assert.equal(f.reason, "обрыв до флэтлайна");
});

test("«пощадить» снимает флаг и тревогу, пишет журнал; повтор безопасен и журнал не дублирует", async () => {
  const { app, headers, db } = await setup();
  const runner = await seedPlayer(app, { callsign: "Призрак", faction: "NEON" });
  await post(app, [flatline(testDevice(), runner.publicKeyB64)]);

  const url = `/api/net/runners/${enc(runner.publicKeyB64)}/spare`;
  const first = await app.inject({ method: "POST", url, headers, payload: { note: "вытащили сами" } });
  assert.equal(first.statusCode, 200);
  assert.equal(first.json().blocked, false);
  assert.equal(first.json().sparedBy, "Мастер-1");
  assert.equal(first.json().bridgeSynced, false, "Мост ещё не знает решения — догонится при подключении");

  const again = await app.inject({ method: "POST", url, headers, payload: {} });
  assert.equal(again.statusCode, 200);
  assert.equal((db.prepare("SELECT COUNT(*) AS n FROM audit_master WHERE action = 'NET_RUNNER_SPARE'").get() as { n: number }).n, 1);

  const attn = (await app.inject({ method: "GET", url: "/api/attention", headers })).json() as { items: { kind: string }[] };
  assert.ok(!attn.items.some((i) => i.kind === "net_flatline"));
});

test("старая запись флэтлайна, пришедшая после «пощады», флаг заново не ставит; новый флэтлайн — ставит", async () => {
  const { app, headers } = await setup();
  const runner = await seedPlayer(app, { callsign: "Призрак", faction: "NEON" });
  const world = testDevice();
  const key = runner.publicKeyB64;
  const old = flatline(world, key, { session: "s_old" }, Date.now() - 60_000);
  await post(app, [flatline(world, key, { session: "s_1" }, Date.now() - 30_000)]);
  await app.inject({ method: "POST", url: `/api/net/runners/${enc(runner.publicKeyB64)}/spare`, headers, payload: {} });

  await post(app, [old]); // догнавшая очередь Моста: случилась ДО «пощады»
  let [f] = (await app.inject({ method: "GET", url: "/api/net/runners", headers })).json() as { blocked: boolean }[];
  assert.equal(f.blocked, false);

  await post(app, [flatline(world, key, { session: "s_new" }, Date.now() + 5)]);
  [f] = (await app.inject({ method: "GET", url: "/api/net/runners", headers })).json() as { blocked: boolean }[];
  assert.equal(f.blocked, true);
});

test("мастер закрывает допуск вручную — только известному игроку; «пощадить» по несуществующему флагу — 404; без сессии — 401", async () => {
  const { app, headers } = await setup();
  const runner = await seedPlayer(app, { callsign: "Нетраннер", faction: "NEON" });
  const k = enc(runner.publicKeyB64);

  assert.equal((await app.inject({ method: "POST", url: `/api/net/runners/${k}/spare`, headers, payload: {} })).statusCode, 404);
  assert.equal((await app.inject({ method: "POST", url: `/api/net/runners/${enc("QUJD")}/block`, headers, payload: {} })).statusCode, 404);

  const blocked = await app.inject({ method: "POST", url: `/api/net/runners/${k}/block`, headers, payload: { reason: "ушёл в самоволку" } });
  assert.equal(blocked.statusCode, 200);
  assert.equal(blocked.json().blocked, true);
  assert.equal(blocked.json().reason, "ушёл в самоволку");

  const one = (await app.inject({ method: "GET", url: `/api/net/runners/${k}`, headers })).json();
  assert.equal(one.blocked, true);
  const none = (await app.inject({ method: "GET", url: `/api/net/runners/${enc("QUJD")}`, headers })).json();
  assert.deepEqual(none, { blocked: false, allowed: false });

  assert.equal((await app.inject({ method: "GET", url: "/api/net/runners" })).statusCode, 401);
  assert.equal((await app.inject({ method: "POST", url: `/api/net/runners/${k}/spare`, payload: {} })).statusCode, 401);
});

test("тревога аудитора Моста — в «внимании», тревога флэтлайна отдельно не дублируется", async () => {
  const { app, headers } = await setup();
  const world = testDevice();
  await post(app, [
    world.change({ field: "net.alert", newValue: JSON.stringify({ alert: "al_a_1", kind: "auditor_eddies", msg: "эдди в минус", items: [] }), reason: "NET_ALERT", sourceRef: "al_a_1" }),
    world.change({ field: "net.alert", newValue: JSON.stringify({ alert: "al_17", kind: "flatline", msg: "флэтлайн" }), reason: "NET_ALERT", sourceRef: "al_17" }),
  ]);
  const attn = (await app.inject({ method: "GET", url: "/api/attention", headers })).json() as { items: { kind: string; detail: string }[] };
  const alerts = attn.items.filter((i) => i.kind === "net_alert");
  assert.equal(alerts.length, 1);
  assert.match(alerts[0].detail, /auditor_eddies: эдди в минус/);
});
