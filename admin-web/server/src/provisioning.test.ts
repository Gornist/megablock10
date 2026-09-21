import { test } from "node:test";
import assert from "node:assert/strict";
import { seedPlayer, setup, type App, type Device } from "./testHelpers.js";
import { testDevice } from "./testUtil.js";

type Item = { id: string; kind: string; severity: string; detail: string; subjectKey?: string };
type Prov = { item: { id: string; void: boolean; boundKey: string | null; replacesKey: string | null; conflicts: number }; qr: string; qrImage: string };

const send = (app: App, ...records: unknown[]) => app.inject({ method: "POST", url: "/api/changes", payload: { records } });
const attention = async (app: App, headers: Record<string, string>) => (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as Item[];
const players = async (app: App, headers: Record<string, string>) =>
  (await app.inject({ method: "GET", url: "/api/players", headers })).json() as { publicKeyB64: string; callsign: string; faction: string; balance: number; ramCapacity: number; sessionResetAt: number | null; replacedBy: string | null; replaces: string | null }[];

async function issue(app: App, headers: Record<string, string>, body: Record<string, unknown> = { callsign: "Alice", faction: "Neon", balance: 500, ram: 8 }) {
  const res = await app.inject({ method: "POST", url: "/api/provisions", headers, payload: body });
  assert.equal(res.statusCode, 200, res.body);
  return res.json() as Prov;
}

/** Как приложение: четыре записи CHARACTER_CREATED с одним sourceRef выдачи. */
const applyCode = (d: Device, id: string, name: string, faction: string, balance: number, ram = 8) => [
  d.change({ field: "callsign", newValue: name, reason: "CHARACTER_CREATED", sourceRef: id }),
  d.change({ field: "faction", newValue: faction, reason: "CHARACTER_CREATED", sourceRef: id }),
  d.change({ field: "ramCapacity", oldValue: "6", newValue: String(ram), reason: "CHARACTER_CREATED", sourceRef: id }),
  d.change({ field: "balance", oldValue: "0", newValue: String(balance), reason: "CHARACTER_CREATED", sourceRef: id }),
];

const b64d = (s: string) => Buffer.from(s, "base64").toString("utf8");

test("QR персонажа: строка по формату приложения, адрес и код игры из настроек сервера, проверки параметров", async () => {
  const { app, headers } = await setup();
  process.env.PUBLIC_URL = "http://10.10.0.10:2517/";
  process.env.GAME_SECRET = "secret-xyz";
  try {
    const r = await issue(app, headers);
    const parts = r.qr.split(":");
    assert.deepEqual(parts.slice(0, 3), ["MB10", "PROV", "v1"]);
    assert.equal(parts[3], r.item.id);
    assert.equal(b64d(parts[4]), "http://10.10.0.10:2517");
    assert.equal(b64d(parts[5]), "secret-xyz");
    assert.equal(b64d(parts[6]), "Alice");
    assert.equal(b64d(parts[7]), "Neon");
    assert.deepEqual(parts.slice(8), ["500", "8"]);
    assert.match(r.qrImage, /^data:image\/png;base64,/);
    assert.match(r.item.id, /^[A-Za-z0-9_-]{1,64}$/, "id проходит проверку приложения");

    const list = (await app.inject({ method: "GET", url: "/api/provisions", headers })).json();
    assert.deepEqual(list.config, { url: "http://10.10.0.10:2517", urlSource: "env", secretSet: true });
    assert.equal(JSON.stringify(list).includes("secret-xyz"), false, "код игры наружу не отдаётся");
  } finally {
    delete process.env.PUBLIC_URL;
    delete process.env.GAME_SECRET;
  }

  for (const bad of [{ callsign: "" }, { callsign: "x".repeat(41) }, { callsign: "A", faction: "f".repeat(41) }, { callsign: "A", balance: -1 }, { callsign: "A", balance: 1_000_001 }, { callsign: "A", balance: 1.5 }, { callsign: "A", ram: 5 }, { callsign: "A", ram: 14 }]) {
    assert.equal((await app.inject({ method: "POST", url: "/api/provisions", headers, payload: bad })).statusCode, 400, JSON.stringify(bad));
  }
  assert.equal((await app.inject({ method: "POST", url: "/api/provisions", payload: { callsign: "A" } })).statusCode, 401);
  const minimal = await issue(app, headers, { callsign: "Solo" });
  assert.deepEqual(minimal.qr.split(":").slice(8), ["0", "0"], "баланс и RAM по умолчанию");
});

test("одноразовость: код привязывается к первому ключу, второй получает отказ и тревогу, свой повтор — не ошибка", async () => {
  const { app, headers } = await setup();
  const { item } = await issue(app, headers);
  const first = testDevice();
  const res = await send(app, ...applyCode(first, item.id, "Alice", "Neon", 500));
  assert.deepEqual(res.json().rejected, []);
  assert.equal((await players(app, headers)).find((p) => p.callsign === "Alice")!.balance, 500);

  // тот же телефон досылает ещё запись с этим кодом — ок
  assert.deepEqual((await send(app, first.change({ field: "faction", newValue: "Neon", reason: "CHARACTER_CREATED", sourceRef: item.id }))).json().rejected, []);

  const copy = testDevice();
  const dup = (await send(app, ...applyCode(copy, item.id, "Alice2", "Neon", 500))).json();
  assert.equal(dup.rejected.length, 4);
  assert.match(dup.rejected[0].error, /already applied on another device/);
  assert.equal((await players(app, headers)).some((p) => p.callsign === "Alice2"), false, "копия в игроки не попала");

  const conflict = (await attention(app, headers)).find((i) => i.kind === "provision_conflict");
  assert.ok(conflict);
  assert.equal(conflict.severity, "crit");
  assert.match(conflict.detail, /Alice/);
  const listed = (await app.inject({ method: "GET", url: "/api/provisions", headers })).json().items[0];
  assert.equal(listed.conflicts, 1);
  assert.equal(listed.boundName, "Alice");

  // неизвестный код (не выдан этим коллектором) принимается как раньше
  const legacy = testDevice();
  assert.deepEqual((await send(app, ...applyCode(legacy, "some-old-code", "Legacy", "X", 10))).json().rejected, []);
});

test("сброс сессии не стирает параметры игрока, а помечает «сессия сброшена»", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "Neon", balance: 500, ram: 8 });
  await send(
    app,
    a.change({ field: "callsign", oldValue: "Alice", newValue: "", reason: "CHARACTER_RESET" }),
    a.change({ field: "faction", oldValue: "Neon", newValue: "", reason: "CHARACTER_RESET" }),
  );
  const p = (await players(app, headers))[0];
  assert.equal(p.callsign, "Alice");
  assert.equal(p.faction, "Neon");
  assert.equal(p.balance, 500);
  assert.equal(p.ramCapacity, 8);
  assert.ok(p.sessionResetAt);
  const detail = (await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(a.publicKeyB64)}`, headers })).json();
  assert.equal(detail.callsign, "Alice");
  assert.ok(detail.sessionResetAt);
});

test("сброшенные и заменённые ключи не считаются в экономике, фракциях, обзоре, тревогах и массовых рассылках", async () => {
  const { app, db, headers } = await setup();
  const live = await seedPlayer(app, { callsign: "Live", faction: "Neon", balance: 100 });
  const gone = await seedPlayer(app, { callsign: "Gone", faction: "Neon", balance: 900 });
  const supply = async () => (await app.inject({ method: "GET", url: "/api/economy", headers })).json();
  assert.equal((await supply()).totalSupply, 1000);

  await send(app, gone.change({ field: "callsign", oldValue: "Gone", newValue: "", reason: "CHARACTER_RESET" }));
  const eco = await supply();
  assert.equal(eco.totalSupply, 100, "остаток сброшенной сессии в обороте не считается");
  assert.equal(eco.playersCounted, 1);
  assert.equal(eco.series[eco.series.length - 1].supply, 100);

  const factions = (await app.inject({ method: "GET", url: "/api/factions", headers })).json() as { faction: string; players: number; totalBalance: number }[];
  assert.deepEqual(factions.map((f) => [f.faction, f.players, f.totalBalance]), [["Neon", 1, 100]]);
  assert.equal((await app.inject({ method: "GET", url: "/api/overview", headers })).json().players.total, 1);

  // «пропал со связи» — только у действующих
  const old = Date.now() - 20 * 60_000;
  db.prepare(`UPDATE changes SET received_at = ?`).run(old);
  const silent = (await attention(app, headers)).filter((i) => i.kind === "went_silent");
  assert.deepEqual(silent.map((i) => i.subjectKey), [live.publicKeyB64]);

  const bulk = await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { field: "balance", newValue: "+10", mode: "add", reason: "r", all: true, dryRun: true } });
  assert.equal(bulk.json().count, 1, "«всем» не включает свободное устройство");
});

test("повторная выдача: параметры из снимка, старый код погашен, после применения прежний ключ «заменён» и не считается", async () => {
  const { app, headers } = await setup();
  const { item } = await issue(app, headers);
  const oldDev = testDevice();
  await send(app, ...applyCode(oldDev, item.id, "Alice", "Neon", 500));
  await send(app, oldDev.change({ field: "balance", oldValue: "500", newValue: "730", reason: "BREACH_EDDIES" }));
  await send(app, oldDev.change({ field: "callsign", oldValue: "Alice", newValue: "", reason: "CHARACTER_RESET" }));

  const re = await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(oldDev.publicKeyB64)}/reissue`, headers, payload: {} });
  assert.equal(re.statusCode, 200, re.body);
  const r = re.json() as Prov;
  const parts = r.qr.split(":");
  assert.equal(b64d(parts[6]), "Alice");
  assert.equal(b64d(parts[7]), "Neon");
  assert.deepEqual(parts.slice(8), ["730", "8"], "баланс и RAM — как были на момент сброса");
  assert.equal(r.item.replacesKey, oldDev.publicKeyB64);

  const list = (await app.inject({ method: "GET", url: "/api/provisions", headers })).json().items as { id: string; void: boolean }[];
  assert.equal(list.find((p) => p.id === item.id)!.void, true, "прежний код погашен");
  const oldCodeAgain = await send(app, testDevice().change({ field: "callsign", newValue: "X", reason: "CHARACTER_CREATED", sourceRef: item.id }));
  assert.match(oldCodeAgain.json().rejected[0].error, /already applied/);

  // мастер поправил параметры при повторной выдаче
  const tweaked = (await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(oldDev.publicKeyB64)}/reissue`, headers, payload: { faction: "Rats", balance: 300 } })).json() as Prov;
  assert.equal(b64d(tweaked.qr.split(":")[7]), "Rats");
  assert.equal(tweaked.qr.split(":")[8], "300");
  const listed = (await app.inject({ method: "GET", url: "/api/provisions", headers })).json().items as { id: string; void: boolean }[];
  assert.equal(listed.find((p) => p.id === r.item.id)!.void, true, "предыдущая неиспользованная перевыдача погашена");
  const stale = await send(app, testDevice().change({ field: "callsign", newValue: "Alice", reason: "CHARACTER_CREATED", sourceRef: r.item.id }));
  assert.match(stale.json().rejected[0].error, /no longer valid/);
  assert.equal((await app.inject({ method: "GET", url: `/api/provisions/${r.item.id}/qr`, headers })).statusCode, 409);
  assert.equal((await app.inject({ method: "GET", url: `/api/provisions/${tweaked.item.id}/qr`, headers })).statusCode, 200, "неприменённый код можно показать снова");

  // новый телефон применяет актуальный код
  const newDev = testDevice();
  assert.deepEqual((await send(app, ...applyCode(newDev, tweaked.item.id, "Alice", "Rats", 300))).json().rejected, []);
  const all = await players(app, headers);
  const oldP = all.find((p) => p.publicKeyB64 === oldDev.publicKeyB64)!;
  const newP = all.find((p) => p.publicKeyB64 === newDev.publicKeyB64)!;
  assert.equal(oldP.replacedBy, newDev.publicKeyB64);
  assert.equal(newP.replaces, oldDev.publicKeyB64);
  assert.equal(oldP.balance, 730, "история прежнего ключа остаётся");

  const eco = (await app.inject({ method: "GET", url: "/api/economy", headers })).json();
  assert.equal(eco.totalSupply, 300, "остаток 730 прежней сессии не удваивает эмиссию");
  assert.equal(eco.playersCounted, 1);
  const detail = (await app.inject({ method: "GET", url: `/api/players/${encodeURIComponent(newDev.publicKeyB64)}`, headers })).json();
  assert.equal(detail.replaces, oldDev.publicKeyB64);

  const audit = (await app.inject({ method: "GET", url: "/api/audit", headers })).json().records as { action: string; summary: string }[];
  assert.ok(audit.some((a) => a.action === "PROVISION_CREATE"));
  assert.match(audit.find((a) => a.action === "PROVISION_REISSUE")!.summary, /выдан заново как «Alice» \(Rats\), баланс 300/);
});

test("повторная выдача: неизвестный игрок — 404, параметры проверяются, отрицательный остаток превращается в 0", async () => {
  const { app, headers } = await setup();
  assert.equal((await app.inject({ method: "POST", url: "/api/players/nobody/reissue", headers, payload: {} })).statusCode, 404);
  const a = await seedPlayer(app, { callsign: "Debtor", faction: "X" });
  await send(app, a.change({ field: "balance", oldValue: "0", newValue: "-40", reason: "BREACH_EDDIES" }));
  const url = `/api/players/${encodeURIComponent(a.publicKeyB64)}/reissue`;
  assert.equal(((await app.inject({ method: "POST", url, headers, payload: {} })).json() as Prov).qr.split(":")[8], "0");
  assert.equal((await app.inject({ method: "POST", url, headers, payload: { ram: 99 } })).statusCode, 400);
  assert.equal((await app.inject({ method: "POST", url, payload: {} })).statusCode, 401);
});
