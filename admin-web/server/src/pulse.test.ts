import { test } from "node:test";
import assert from "node:assert/strict";
import type { PulseSample } from "./apiTypes.js";
import type { Db } from "./db/index.js";
import { categorizeReject, resetPulseCounters, takePulseSample } from "./lib/pulse.js";
import { testDevice } from "./testUtil.js";
import { seedPlayer, setup, sleep, type App } from "./testHelpers.js";

const MIN = 60_000;
type Item = { kind: string; severity: string; detail: string; subjectKey?: string };

const attention = async (app: App, headers: Record<string, string>) => (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as Item[];
const send = (app: App, ...records: unknown[]) => app.inject({ method: "POST", url: "/api/changes", payload: { records } });

function putSample(db: Db, t: number, over: Partial<PulseSample>) {
  const s: PulseSample = { t, online: 20, records: 30, heartbeats: 40, rejected: 0, rejectedBy: {}, rateLimited: 0, secretDenied: 0, requests: 40, latencyAvgMs: 5, latencyMaxMs: 20, breaches: 0, eddies: 0, transfers: 0, undelivered: 0, ...over };
  db.prepare(`INSERT OR REPLACE INTO pulse_samples (t, data) VALUES (?, ?)`).run(t, JSON.stringify(s));
}
/** n сэмплов, последний — «сейчас», каждый следующий описывается функцией от индекса с конца (0 — самый свежий). */
function putSeries(db: Db, n: number, f: (fromEnd: number) => Partial<PulseSample>, now = Date.now()) {
  for (let i = n - 1; i >= 0; i--) putSample(db, now - i * MIN, f(i));
}

test("categorizeReject раскладывает ошибки приёма по категориям", () => {
  assert.equal(categorizeReject("invalid signature"), "signature");
  assert.equal(categorizeReject("malformed record"), "malformed");
  assert.equal(categorizeReject("unknown reason: X"), "unknown");
  assert.equal(categorizeReject("seq already used by a different record"), "seq");
  assert.equal(categorizeReject("actor must equal subjectKeyB64 for this reason"), "actor");
  assert.equal(categorizeReject("whatever"), "other");
});

test("сэмпл пульса: счётчики приёма и показатели игры за интервал, /api/pulse отдаёт историю", async () => {
  resetPulseCounters();
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 50 });
  const stranger = testDevice();
  await send(app, a.change({ field: "balance", oldValue: "50", newValue: "80", reason: "BREACH_EDDIES" }));
  await send(app, { id: "junk" }, a.change({ field: "balance", oldValue: "80", newValue: "90", reason: "BREACH_EDDIES", signAs: { publicKeyB64: stranger.publicKeyB64, privateKey: stranger.privateKey } }));
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: a.publicKeyB64 } });

  const s = takePulseSample(db, Date.now());
  assert.equal(s.records, 4, "3 записи новичка + 1 принятая");
  assert.equal(s.rejected, 2);
  assert.deepEqual(s.rejectedBy, { malformed: 1, signature: 1 });
  assert.equal(s.heartbeats, 1);
  assert.equal(s.online, 1);
  assert.ok(s.requests >= 4);
  assert.equal(s.eddies, 80, "50 (стартовые) + 30 наградами за интервал");

  const next = takePulseSample(db, Date.now() + 1);
  assert.equal(next.rejected, 0, "счётчики сброшены");

  await sleep(5); // второй сэмпл датирован на 1 мс вперёд
  const res = (await app.inject({ method: "GET", url: "/api/pulse?minutes=5", headers })).json() as { intervalMs: number; samples: PulseSample[] };
  assert.equal(res.intervalMs, 60_000);
  assert.deepEqual(res.samples.map((x) => x.rejected), [2, 0]);
});

test("тревога: массовая потеря связи — онлайн упал ниже 70% пика два сэмпла подряд", async () => {
  const { app, db, headers } = await setup();
  putSeries(db, 8, (i) => ({ online: i < 2 ? 5 : 30 }));
  const item = (await attention(app, headers)).find((i) => i.kind === "mass_silence");
  assert.ok(item);
  assert.equal(item.severity, "crit");
  assert.match(item.detail, /на связи 5 из 30/);
});

test("массовая потеря связи: одиночная просадка, малая игра и молчащий сэмплер тревог не дают", async () => {
  const { app, db, headers } = await setup();
  putSeries(db, 8, (i) => ({ online: i === 0 ? 5 : 30 }));
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "mass_silence").length, 0, "один сэмпл — это шум");

  db.prepare(`DELETE FROM pulse_samples`).run();
  putSeries(db, 8, (i) => ({ online: i < 2 ? 1 : 4 }));
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "mass_silence").length, 0, "пик меньше 5 игроков");

  db.prepare(`DELETE FROM pulse_samples`).run();
  putSeries(db, 8, (i) => ({ online: i < 2 ? 5 : 30 }), Date.now() - 20 * MIN);
  assert.equal((await attention(app, headers)).filter((i) => i.kind === "mass_silence").length, 0, "свежих сэмплов нет — судить не о чем");
});

test("тревога: всплеск отклонений — главная причина в тексте, подпись делает её срочной", async () => {
  const { app, db, headers } = await setup();
  putSeries(db, 4, () => ({ records: 5, rejected: 6, rejectedBy: { signature: 5, malformed: 1 } }));
  const item = (await attention(app, headers)).find((i) => i.kind === "reject_spike");
  assert.ok(item);
  assert.equal(item.severity, "crit");
  assert.match(item.detail, /18 из 33/);
  assert.match(item.detail, /подпись не сходится/);
});

test("тревоги: лимит запросов, неверный секрет и тормоза сервера", async () => {
  const { app, db, headers } = await setup();
  putSeries(db, 4, () => ({ rateLimited: 1, secretDenied: 2, requests: 20, latencyAvgMs: 900 }));
  const kinds = (await attention(app, headers)).map((i) => i.kind);
  for (const k of ["rate_limited", "secret_denied", "server_slow"]) assert.ok(kinds.includes(k), k);

  db.prepare(`DELETE FROM pulse_samples`).run();
  putSeries(db, 4, () => ({}));
  const quiet = (await attention(app, headers)).map((i) => i.kind);
  for (const k of ["rate_limited", "secret_denied", "server_slow", "reject_spike", "mass_silence"]) assert.ok(!quiet.includes(k), k);
});

test("тревога: сумма перевода не сходится — списано одно, получено другое", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 500 });
  const b = await seedPlayer(app, { callsign: "Bob", faction: "X", balance: 0 });
  await send(app, a.change({ field: "balance", oldValue: "500", newValue: "400", reason: "TRANSFER_OUT", sourceRef: "tx-m" }));
  await send(app, b.change({ field: "balance", oldValue: "0", newValue: "300", reason: "TRANSFER_IN", sourceRef: "tx-m", actor: a.publicKeyB64 }));
  const item = (await attention(app, headers)).find((i) => i.kind === "transfer_amount_mismatch");
  assert.ok(item);
  assert.equal(item.severity, "crit");
  assert.match(item.detail, /Alice → Bob: списано 100 €\$, получено 300 €\$/);
});

test("тревога: часы устройства спешат — запись датирована будущим", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 10 });
  const b = await seedPlayer(app, { callsign: "Bob", faction: "X", balance: 10 });
  db.prepare(`UPDATE changes SET happened_at = received_at + ? WHERE subject_key = ? AND field = 'balance'`).run(30 * MIN, a.publicKeyB64);
  db.prepare(`UPDATE changes SET happened_at = received_at - ? WHERE subject_key = ? AND field = 'balance'`).run(3 * 60 * MIN, b.publicKeyB64);
  const items = (await attention(app, headers)).filter((i) => i.kind === "clock_skew");
  assert.equal(items.length, 1, "отставание (офлайн-досылка) — норма, спешащие часы — нет");
  assert.equal(items[0].subjectKey, a.publicKeyB64);
  assert.match(items[0].detail, /Alice: записи датированы на 30 мин вперёд/);
});
