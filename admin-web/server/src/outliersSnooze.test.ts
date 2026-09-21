import { test } from "node:test";
import assert from "node:assert/strict";
import type { PulseSample } from "./apiTypes.js";
import type { Db } from "./db/index.js";
import { robustStats } from "./lib/anomalies.js";
import { seedPlayer, setup, type App, type Device } from "./testHelpers.js";

const MIN = 60_000;
type Item = { id: string; kind: string; severity: string; detail: string; subjectKey?: string };

const attention = async (app: App, headers: Record<string, string>, q = "") =>
  (await app.inject({ method: "GET", url: `/api/attention${q}`, headers })).json() as { items: Item[]; snoozed: number };

function putSample(db: Db, t: number, over: Partial<PulseSample>) {
  const s: PulseSample = { t, online: 20, records: 30, heartbeats: 40, rejected: 0, rejectedBy: {}, rateLimited: 0, secretDenied: 0, requests: 40, latencyAvgMs: 5, latencyMaxMs: 20, breaches: 0, eddies: 0, transfers: 0, undelivered: 0, ...over };
  db.prepare(`INSERT OR REPLACE INTO pulse_samples (t, data) VALUES (?, ?)`).run(t, JSON.stringify(s));
}
function putSeries(db: Db, n: number, f: (fromEnd: number) => Partial<PulseSample>, now = Date.now()) {
  for (let i = n - 1; i >= 0; i--) putSample(db, now - i * MIN, f(i));
}

async function breach(app: App, d: Device, times: number) {
  const records = Array.from({ length: times }, () => d.change({ field: "counters.breach", newValue: JSON.stringify({ outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:1" }));
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records } });
  assert.deepEqual(res.json().rejected, []);
}

test("robustStats: выброс не сдвигает базу", () => {
  const { median, sigma } = robustStats([4, 5, 5, 6, 6, 7, 500]);
  assert.equal(median, 6);
  assert.ok(sigma < 3);
  assert.deepEqual(robustStats([]), { median: 0, sigma: 0 });
});

test("выброс по взломам: сравнение с медианой активных игроков, малые числа и малая игра не в счёт", async () => {
  const { app, headers } = await setup();
  const players: Device[] = [];
  for (const n of ["A", "B", "C", "D", "E", "Fast"]) players.push(await seedPlayer(app, { callsign: n, faction: "X" }));
  for (const p of players.slice(0, 5)) await breach(app, p, 3);
  await breach(app, players[5], 3);
  assert.equal((await attention(app, headers)).items.filter((i) => i.kind === "player_outlier").length, 0, "3 против 3 — норма");

  await breach(app, players[5], 40);
  const outliers = (await attention(app, headers)).items.filter((i) => i.kind === "player_outlier");
  assert.equal(outliers.length, 1);
  assert.equal(outliers[0].subjectKey, players[5].publicKeyB64);
  assert.match(outliers[0].detail, /Fast: 43 взломов за 15 мин, у остальных активных медиана 3/);
});

test("выброс: без пяти активных игроков сравнивать не с чем", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "A", faction: "X" });
  const b = await seedPlayer(app, { callsign: "B", faction: "X" });
  await breach(app, a, 50);
  await breach(app, b, 1);
  assert.equal((await attention(app, headers)).items.filter((i) => i.kind === "player_outlier").length, 0);
});

test("скачок эмиссии эдди относительно обычного темпа игры", async () => {
  const { app, db, headers } = await setup();
  putSeries(db, 60, (i) => ({ eddies: i < 3 ? 2000 : 10 }));
  const item = (await attention(app, headers)).items.find((i) => i.kind === "emission_spike");
  assert.ok(item);
  assert.match(item.detail, /за 3 мин выдано 6000 €\$/);

  db.prepare(`DELETE FROM pulse_samples`).run();
  putSeries(db, 60, () => ({ eddies: 10 }));
  assert.equal((await attention(app, headers)).items.filter((i) => i.kind === "emission_spike").length, 0);
  db.prepare(`DELETE FROM pulse_samples`).run();
  putSeries(db, 10, (i) => ({ eddies: i < 3 ? 2000 : 10 }));
  assert.equal((await attention(app, headers)).items.filter((i) => i.kind === "emission_spike").length, 0, "меньше 20 сэмплов истории — базы нет");
});

test("snooze: тревога молчит, пока отложена, возвращается по запросу, действие пишется в журнал", async () => {
  const { app, headers } = await setup();
  const d = await seedPlayer(app, { callsign: "Debtor", faction: "X" });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [d.change({ field: "balance", oldValue: "0", newValue: "-40", reason: "BREACH_EDDIES" })] } });
  const before = await attention(app, headers);
  const item = before.items.find((i) => i.kind === "negative_balance")!;
  assert.ok(item);
  assert.equal(before.snoozed, 0);

  const post = (payload: Record<string, unknown>) => app.inject({ method: "POST", url: "/api/attention/snooze", headers, payload });
  assert.equal((await post({ id: item.id, minutes: 30 })).statusCode, 200);
  const hidden = await attention(app, headers);
  assert.equal(hidden.items.some((i) => i.id === item.id), false);
  assert.equal(hidden.snoozed, 1);
  assert.equal((await attention(app, headers, "?all=1")).items.some((i) => i.id === item.id), true);

  const audit = (await app.inject({ method: "GET", url: "/api/audit", headers })).json().records as { action: string; summary: string }[];
  assert.match(audit.find((r) => r.action === "ATTENTION_SNOOZE")!.summary, /«Отрицательный баланс» отложена на 30 мин/);

  await post({ id: item.id, minutes: 0 });
  assert.equal((await attention(app, headers)).items.some((i) => i.id === item.id), true);
});

test("snooze: срок истёк — тревога снова видна; кривой ввод отклоняется; нужен мастер", async () => {
  const { app, db, headers } = await setup();
  const d = await seedPlayer(app, { callsign: "Debtor", faction: "X" });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [d.change({ field: "balance", oldValue: "0", newValue: "-40", reason: "BREACH_EDDIES" })] } });
  const id = (await attention(app, headers)).items.find((i) => i.kind === "negative_balance")!.id;
  await app.inject({ method: "POST", url: "/api/attention/snooze", headers, payload: { id, minutes: 5 } });
  db.prepare(`UPDATE attention_snooze SET until = ?`).run(Date.now() - 1);
  assert.equal((await attention(app, headers)).items.some((i) => i.id === id), true);

  for (const bad of [{}, { id, minutes: -1 }, { id, minutes: 99999 }, { id, minutes: "5" }, { id: "", minutes: 5 }]) {
    assert.equal((await app.inject({ method: "POST", url: "/api/attention/snooze", headers, payload: bad })).statusCode, 400, JSON.stringify(bad));
  }
  assert.equal((await app.inject({ method: "POST", url: "/api/attention/snooze", payload: { id, minutes: 5 } })).statusCode, 401);
});

test("replay: эпизоды тревог по прошлому пульсу — начало, конец, длительность", async () => {
  const { app, db, headers } = await setup();
  const base = Date.now() - 2 * 60 * MIN;
  putSeries(db, 12, (i) => ({ online: i < 4 && i > 1 ? 5 : 30 }), base); // просадка на двух сэмплах
  const url = `/api/anomalies/replay?from=${base - 10 * MIN}&to=${base + 5 * MIN}&stepMin=1`;
  const res = (await app.inject({ method: "GET", url, headers })).json() as { episodes: { kind: string; firstAt: number; lastAt: number; steps: number }[] };
  const ep = res.episodes.find((e) => e.kind === "mass_silence");
  assert.ok(ep);
  assert.ok(ep.steps >= 1);
  assert.ok(ep.firstAt >= base - 10 * MIN && ep.lastAt <= base + 5 * MIN);

  assert.equal((await app.inject({ method: "GET", url: `/api/anomalies/replay?from=${base}&to=${base - 1}`, headers })).statusCode, 400);
  assert.equal((await app.inject({ method: "GET", url: `/api/anomalies/replay?from=1&to=${Date.now()}&stepMin=1`, headers })).statusCode, 400, "слишком много шагов");
});
