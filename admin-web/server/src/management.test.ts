import { test } from "node:test";
import assert from "node:assert/strict";
import { gini } from "./lib/analytics.js";
import { describeAudit } from "./lib/auditSummary.js";
import { resetPresence } from "./lib/presence.js";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

type App = ReturnType<typeof testApp>;
type Device = ReturnType<typeof testDevice>;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function setup() {
  resetPresence();
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db, "Мастер-1");
  const session = await loginAs(app, master.name, master.token);
  return { db, app, headers: { authorization: `Bearer ${session}` } };
}

async function seedPlayer(app: App, opts: { callsign: string; faction: string; balance?: number; ram?: number }): Promise<Device> {
  const device = testDevice();
  const records = [
    device.change({ field: "callsign", newValue: opts.callsign, reason: "CHARACTER_CREATED" }),
    device.change({ field: "faction", newValue: opts.faction, reason: "CHARACTER_CREATED" }),
  ];
  if (opts.balance !== undefined) records.push(device.change({ field: "balance", oldValue: "0", newValue: String(opts.balance), reason: "BREACH_EDDIES" }));
  if (opts.ram !== undefined) records.push(device.change({ field: "ramCapacity", oldValue: "6", newValue: String(opts.ram), reason: "RAM_UPGRADE" }));
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records } });
  assert.equal(res.json().rejected.length, 0, JSON.stringify(res.json().rejected));
  return device;
}

async function players(app: App, headers: Record<string, string>) {
  return (await app.inject({ method: "GET", url: "/api/players", headers })).json() as {
    publicKeyB64: string;
    callsign: string;
    balance: number;
    ramCapacity: number;
    faction: string;
  }[];
}

const poll = (app: App, device: Device, ackIds: string[] = []) =>
  app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: device.publicKeyB64, ackIds } });

// ───────────── массовые правки ─────────────

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

// ───────────── журнал мастеров ─────────────

test("audit: журнал показывает правки, массовые правки, объявления и создание контейнера — с именем мастера и фразой", async () => {
  const { app, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 100 });

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "500", reason: "компенсация" },
  });
  await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { field: "faction", newValue: "Z", reason: "переход", all: true } });
  await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Сбор у входа", all: true } });
  await app.inject({ method: "POST", url: "/api/master/containers", headers, payload: { name: "Насос", tier: "BASE", ownerFaction: "X", slots: [] } });

  const res = await app.inject({ method: "GET", url: "/api/audit", headers });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.total, 4);
  const actions = body.records.map((r: { action: string }) => r.action).sort();
  assert.deepEqual(actions, ["ANNOUNCEMENT", "BULK_OVERRIDE", "CONTAINER_CREATED", "PLAYER_OVERRIDE"]);
  assert.ok(body.records.every((r: { masterName: string }) => r.masterName === "Мастер-1"));
  const override = body.records.find((r: { action: string }) => r.action === "PLAYER_OVERRIDE");
  assert.match(override.summary, /Alice: баланс 100 → 500.*компенсация/);

  const filtered = await app.inject({ method: "GET", url: "/api/audit?action=ANNOUNCEMENT", headers });
  assert.equal(filtered.json().total, 1);
  assert.ok(body.actions.length >= 4, "список действий для фильтра");
  assert.equal((await app.inject({ method: "GET", url: "/api/audit" })).statusCode, 401);
});

test("describeAudit: фразы по действиям", () => {
  const name = (k: string) => (k === "k1" ? "Alice" : k);
  assert.match(describeAudit("SLOT_REVOKE", { slotRef: "n#0", claimantKeyB64: "k1", reason: "дубль" }, name), /Alice.*дубль/);
  assert.match(describeAudit("BULK_OVERRIDE", { field: "balance", mode: "add", newValue: "100", target: "все игроки", count: 3, justification: "премия" }, name), /все игроки \(3 чел\.\): баланс \+100/);
  assert.equal(describeAudit("НЕИЗВЕСТНОЕ", null, name), "НЕИЗВЕСТНОЕ");
});

// ───────────── объявления ─────────────

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

// ───────────── экономика и фракции ─────────────

test("economy: эмиссия по источникам без переводов, оборот, распределение, серия сходится с суммой балансов", async () => {
  const { app, headers } = await setup();
  const a = testDevice();
  const b = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        a.change({ field: "callsign", newValue: "Alice", reason: "CHARACTER_CREATED" }),
        b.change({ field: "callsign", newValue: "Bob", reason: "CHARACTER_CREATED" }),
        a.change({ field: "balance", oldValue: "0", newValue: "100", reason: "BREACH_EDDIES" }),
        b.change({ field: "balance", oldValue: "0", newValue: "50", reason: "SHARD_SCAN" }),
        a.change({ field: "balance", oldValue: "100", newValue: "70", reason: "TRANSFER_OUT", sourceRef: "tx1" }),
        b.change({ field: "balance", oldValue: "50", newValue: "80", reason: "TRANSFER_IN", sourceRef: "tx1", actor: a.publicKeyB64 }),
      ],
    },
  });

  const res = await app.inject({ method: "GET", url: "/api/economy", headers });
  assert.equal(res.statusCode, 200);
  const e = res.json();
  assert.equal(e.totalSupply, 150);
  assert.equal(e.transferVolume, 30);
  assert.deepEqual(e.sources.map((s: { reason: string; total: number }) => [s.reason, s.total]), [["BREACH_EDDIES", 100], ["SHARD_SCAN", 50]]);
  assert.equal(e.series.at(-1).supply, 150, "серия сходится с суммой балансов");
  assert.equal(e.top[0].callsign, "Bob");
  assert.equal(e.distribution.median, 70);
  assert.equal(e.distribution.negative, 0);
  assert.equal((await app.inject({ method: "GET", url: "/api/economy" })).statusCode, 401);
});

test("gini: поровну → 0, всё у одного → близко к 1", () => {
  assert.equal(gini([5, 5, 5, 5]), 0);
  assert.equal(gini([0, 0, 0, 10]), 0.75);
  assert.equal(gini([]), 0);
});

test("factions: сумма по игрокам, свои/чужие взломы, кому уходят сигналы СБ", async () => {
  const { app, headers } = await setup();
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] }] },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON", balance: 100 });
  const bob = await seedPlayer(app, { callsign: "Bob", faction: "ARASAKA", balance: 300 });
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s1" }),
        bob.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s2" }),
        bob.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT", sourceRef: "nasos-4:s2" }),
      ],
    },
  });

  const rows = (await app.inject({ method: "GET", url: "/api/factions", headers })).json() as Record<string, number | string>[];
  const neon = rows.find((r) => r.faction === "NEON")!;
  const ara = rows.find((r) => r.faction === "ARASAKA")!;
  assert.equal(rows[0].faction, "ARASAKA", "сортировка по деньгам");
  assert.equal(ara.totalBalance, 300);
  assert.equal(ara.breachesForeign, 1);
  assert.equal(ara.alertsSent, 1);
  assert.equal(neon.breachesOwn, 1);
  assert.equal(neon.alertsReceived, 1, "сигнал ушёл владельцам узла — фракции NEON");
  assert.equal(neon.online, 1);
});

// ───────────── узлы ─────────────

test("nodes: взломы за час в списке и почасовая динамика в деталях", async () => {
  const { app, headers } = await setup();
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] }] },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON" });
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s1" }),
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s2" }),
      ],
    },
  });

  const list = (await app.inject({ method: "GET", url: "/api/nodes", headers })).json();
  assert.equal(list[0].breachesLastHour, 2);

  const detail = (await app.inject({ method: "GET", url: "/api/nodes/nasos-4?hours=6", headers })).json();
  assert.equal(detail.timeline.length, 6);
  const last = detail.timeline.at(-1);
  assert.equal(last.success + last.fail, 2, "оба взлома в текущем часовом ведре");
  assert.equal(detail.timeline.slice(0, -1).every((b: { success: number; partial: number; fail: number }) => b.success + b.partial + b.fail === 0), true);
});

// ───────────── состояние на момент T ─────────────

test("until: состояние игрока и список на момент T не видят более поздних записей", async () => {
  const { app, headers } = await setup();
  const a = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        a.change({ field: "callsign", newValue: "Alice", reason: "CHARACTER_CREATED" }),
        a.change({ field: "balance", oldValue: "0", newValue: "100", reason: "BREACH_EDDIES" }),
      ],
    },
  });
  await sleep(5);
  const t = Date.now();
  await sleep(5);
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [a.change({ field: "balance", oldValue: "100", newValue: "900", reason: "BREACH_EDDIES" })] } });

  const key = encodeURIComponent(a.publicKeyB64);
  assert.equal((await app.inject({ method: "GET", url: `/api/players/${key}`, headers })).json().balance, 900);
  assert.equal((await app.inject({ method: "GET", url: `/api/players/${key}?until=${t}`, headers })).json().balance, 100);
  const list = (await app.inject({ method: "GET", url: `/api/players?until=${t}`, headers })).json();
  assert.equal(list[0].balance, 100);
  assert.equal(list[0].online, false, "«на связи» на момент в прошлом не определено");
  assert.equal((await app.inject({ method: "GET", url: `/api/players/${key}?until=1`, headers })).statusCode, 404, "до появления персонажа его нет");
});

// ───────────── тревоги ─────────────

test("attention: отрицательный баланс, крупное поступление, недоставленная правка, пропавший игрок", async () => {
  const { app, db, headers } = await setup();
  const neg = await seedPlayer(app, { callsign: "Debtor", faction: "X" });
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [neg.change({ field: "balance", oldValue: "0", newValue: "-40", reason: "BREACH_EDDIES" })] } });
  const rich = await seedPlayer(app, { callsign: "Rich", faction: "X", balance: 5000 });
  const quiet = await seedPlayer(app, { callsign: "Quiet", faction: "X" });

  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(quiet.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "1", reason: "тест" },
  });
  const old = Date.now() - 20 * 60_000;
  db.prepare(`UPDATE master_pending SET created_at = ?`).run(old);
  db.prepare(`UPDATE changes SET received_at = ? WHERE subject_key = ? AND reason != 'MASTER_OVERRIDE'`).run(old, quiet.publicKeyB64);

  const res = await app.inject({ method: "GET", url: "/api/attention", headers });
  assert.equal(res.statusCode, 200);
  const { items, counts } = res.json() as { items: { kind: string; severity: string; detail: string; subjectKey?: string }[]; counts: { crit: number; warn: number; info: number } };
  const kinds = items.map((i) => i.kind);
  assert.ok(kinds.includes("negative_balance"));
  assert.ok(kinds.includes("balance_jump"));
  assert.ok(kinds.includes("override_undelivered"));
  assert.ok(kinds.includes("went_silent"));
  assert.equal(items[0].severity, "crit", "критичные — первыми");
  assert.match(items.find((i) => i.kind === "balance_jump")!.detail, /Rich: \+5000/);
  assert.equal(items.find((i) => i.kind === "went_silent")!.subjectKey, quiet.publicKeyB64);
  assert.equal(counts.crit + counts.warn + counts.info, items.length);
  assert.equal(rich.publicKeyB64.length > 0, true);
});

test("attention: недоставленная правка при живом heartbeat — критичная (телефон на связи, но не применяет)", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 10 });
  await app.inject({
    method: "POST",
    url: `/api/players/${encodeURIComponent(a.publicKeyB64)}/override`,
    headers,
    payload: { field: "balance", newValue: "1", reason: "тест" },
  });
  db.prepare(`UPDATE master_pending SET created_at = ?`).run(Date.now() - 10 * 60_000);
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: a.publicKeyB64 } }); // heartbeat без ack

  const items = (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as { kind: string; severity: string }[];
  assert.equal(items.find((i) => i.kind === "override_undelivered")?.severity, "crit");
});

test("attention: исчерпанный узел, который продолжают ломать", async () => {
  const { app, headers } = await setup();
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [{ index: 0, type: "SHARD", tier: "HARD", copies: 1, title: "Логи" }] }] },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON" });
  const { claimSignature } = await import("./testUtil.js");
  const claimedAt = Date.now();
  const claim = await app.inject({
    method: "POST",
    url: `/api/slots/${encodeURIComponent("nasos-4#0")}/claim`,
    payload: { claimantKeyB64: alice.publicKeyB64, claimedAt, signature: claimSignature(alice, "nasos-4#0", claimedAt) },
  });
  assert.equal(claim.json().granted, true);
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s9" })] },
  });

  const items = (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as { kind: string; nodeId?: string }[];
  assert.equal(items.find((i) => i.kind === "node_exhausted_hot")?.nodeId, "nasos-4");
});

test("attention: без мастерского токена — 401", async () => {
  const { app } = await setup();
  assert.equal((await app.inject({ method: "GET", url: "/api/attention" })).statusCode, 401);
});

// ───────────── закладки ─────────────

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

test("правка и рассылка мастера не делают игрока «на связи»", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 10 });
  db.prepare(`UPDATE changes SET received_at = ?`).run(Date.now() - 60 * 60_000); // игрок давно молчит

  await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Сбор", all: true } });
  await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { field: "balance", newValue: "5", mode: "add", reason: "премия", all: true } });

  const list = await app.inject({ method: "GET", url: "/api/players", headers });
  assert.equal(list.json()[0].online, false);
  const overview = (await app.inject({ method: "GET", url: "/api/overview", headers })).json();
  assert.equal(overview.players.online, 0);
  assert.equal(a.publicKeyB64.length > 0, true);
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

// ───────────── фильтры событий ─────────────

async function seedEvents() {
  const ctx = await setup();
  const { app, headers } = ctx;
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: {
      containers: [
        { id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] },
        { id: "arasaka-1", name: "Арасака-1", tier: "HARD", ownerFaction: "ARASAKA", slots: [] },
      ],
    },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON", balance: 100 });
  const bob = await seedPlayer(app, { callsign: "Bob", faction: "ARASAKA", balance: 50 });
  const nofac = await seedPlayer(app, { callsign: "Nomad", faction: "" });
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s1" }),
        alice.change({ field: "counters.alert", newValue: JSON.stringify({ suppressed: false }), reason: "ALERT_SENT", sourceRef: "nasos-4:s1" }),
        bob.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "arasaka-1:s2" }),
        bob.change({ field: "balance", oldValue: "50", newValue: "40", reason: "TRANSFER_OUT", sourceRef: "tx1" }),
        alice.change({ field: "balance", oldValue: "100", newValue: "110", reason: "TRANSFER_IN", sourceRef: "tx1", actor: bob.publicKeyB64 }),
      ],
    },
  });
  await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}/override`, headers, payload: { field: "balance", newValue: "500", reason: "компенсация" } });
  await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Сбор", all: true } });
  return { ...ctx, alice, bob, nofac };
}

const events = async (app: App, headers: Record<string, string>, query = "") =>
  (await app.inject({ method: "GET", url: `/api/events${query}`, headers })).json() as {
    total: number;
    page: number;
    pageSize: number;
    records: { reason: string; field: string; subject_key: string; human: { kind: string; subject: string; body: string } }[];
  };

test("events: фильтр по игроку — только его записи, включая сообщения мастера ему", async () => {
  const { app, headers, alice } = await seedEvents();
  const res = await events(app, headers, `?player=${encodeURIComponent(alice.publicKeyB64)}`);
  assert.ok(res.total > 0);
  assert.ok(res.records.every((r) => r.subject_key === alice.publicKeyB64));
  assert.ok(res.records.some((r) => r.field === "announcement"), "адресату его объявление видно");
});

test("events: без фильтра по игроку объявления не забивают поток", async () => {
  const { app, headers } = await seedEvents();
  const res = await events(app, headers);
  assert.ok(res.records.length > 0);
  assert.ok(res.records.every((r) => r.field !== "announcement"));
});

test("events: фильтр по фракции — записи всех её игроков; «без фракции» отдельным значением", async () => {
  const { app, headers, alice, bob, nofac } = await seedEvents();
  const neon = await events(app, headers, "?faction=NEON");
  assert.ok(neon.total > 0 && neon.records.every((r) => r.subject_key === alice.publicKeyB64));
  const ara = await events(app, headers, "?faction=ARASAKA");
  assert.ok(ara.records.every((r) => r.subject_key === bob.publicKeyB64));
  const none = await events(app, headers, "?faction=__none__");
  assert.ok(none.total > 0 && none.records.every((r) => r.subject_key === nofac.publicKeyB64));
  assert.equal((await events(app, headers, "?faction=НЕТ_ТАКОЙ")).total, 0);
});

test("events: фильтр по типу совпадает с маркером в ленте (human.kind)", async () => {
  const { app, headers } = await seedEvents();
  for (const kind of ["money", "item", "breach", "alert", "master", "system"]) {
    const res = await events(app, headers, `?kind=${kind}&pageSize=200`);
    assert.ok(res.records.every((r) => r.human.kind === kind), `kind=${kind}: попали записи другого типа`);
  }
  assert.ok((await events(app, headers, "?kind=breach")).total >= 2);
  assert.ok((await events(app, headers, "?kind=money")).total >= 4);
  assert.equal((await events(app, headers, "?kind=master")).records[0].human.kind, "master");
  assert.equal((await app.inject({ method: "GET", url: "/api/events?kind=что-то", headers })).statusCode, 400);
});

test("events: фильтр по причине и по узлу, комбинация игрока и узла", async () => {
  const { app, headers, alice } = await seedEvents();
  const byReason = await events(app, headers, "?reason=TRANSFER_IN");
  assert.equal(byReason.total, 1);
  assert.equal((await app.inject({ method: "GET", url: "/api/events?reason=НЕТ", headers })).statusCode, 400);

  const node = await events(app, headers, "?node=nasos-4");
  assert.equal(node.total, 2, "взлом и сигнал по Насосной-4");
  assert.ok(node.records.every((r) => r.subject_key === alice.publicKeyB64));

  const combo = await events(app, headers, `?node=arasaka-1&player=${encodeURIComponent(alice.publicKeyB64)}`);
  assert.equal(combo.total, 0, "Alice узел Арасаки не ломала");
  const combo2 = await events(app, headers, "?faction=NEON&kind=alert");
  assert.equal(combo2.total, 1);
});

test("events: период (since/until), пагинация и порядок «новые сверху»", async () => {
  const { app, headers, db } = await seedEvents();
  db.prepare(`UPDATE changes SET received_at = received_at - 3600000 WHERE reason = 'BREACH_ATTEMPT'`).run();
  const recent = await events(app, headers, `?kind=breach&since=${Date.now() - 1800000}`);
  assert.equal(recent.total, 0, "взломы старше получаса не попадают");
  assert.equal((await events(app, headers, `?kind=breach&until=${Date.now() - 1800000}`)).total, 2);

  const all = await events(app, headers, "?pageSize=200");
  const page0 = await events(app, headers, "?pageSize=3&page=0");
  const page1 = await events(app, headers, "?pageSize=3&page=1");
  assert.equal(page0.total, all.total);
  assert.equal(page0.records.length, 3);
  assert.notEqual(page0.records[0].subject_key + page0.records[0].field, "");
  assert.equal(page1.records.length, Math.min(3, all.total - 3));
  assert.deepEqual(page0.records.concat(page1.records).map((r) => r.human.body), all.records.slice(0, page0.records.length + page1.records.length).map((r) => r.human.body));
});

test("events: без мастерского токена — 401", async () => {
  const { app } = await setup();
  assert.equal((await app.inject({ method: "GET", url: "/api/events" })).statusCode, 401);
});
