import { test } from "node:test";
import assert from "node:assert/strict";
import type { NetState } from "./apiTypes.js";
import { buildApp } from "./app.js";
import { BridgeClient } from "./net/bridgeClient.js";
import { BridgeError } from "./net/bridgeProtocol.js";
import { FakeBridge } from "./net/fakeBridge.js";
import { Mirror } from "./net/mirror.js";
import { NetService, bridgeOptionsFromEnv } from "./net/netService.js";
import { setupNet, waitFor } from "./testNet.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

/** Клиент Моста и инструменты мастера «Сети» против фейкового Моста по протоколу C1 (net/fakeBridge.ts). */

const doc = (type: string, id: string, ver: number, data: Record<string, unknown> = {}) => ({ type, id, ver, created: 1, updated: 1, data });

const SAMPLE = [
  { type: "settings", id: "global", data: { paused: false, venue_link: true } },
  { type: "node", id: "node_07", data: { title: "Склад", tier: "STANDARD", lockdown_until: 0, eddies: 300 } },
  { type: "terminal", id: "t03", data: { label: "Подвал", node: "node_07", silent: false } },
  { type: "master_req", id: "flatline:s_1", data: { kind: "flatline", ref: "s_1", node: "node_07", summary: "ФЛЭТЛАЙН: Призрак", state: "pending", default: "approve", decision: null } },
  { type: "alert", id: "al_17", data: { kind: "auditor_item_owner", msg: "it_02bb: владелец deck:s_9f2c, но сессия закрыта" } },
  { type: "net_query", id: "nq_1", data: { runner: "Призрак", state: "open", messages: [{ mid: "m1", from: "runner", text: "Где шард?", at: 1 }] } },
  { type: "template", id: "tpl_night", data: { title: "Ночь", settings: { await_flatline: 1 }, node_cfg: { trace_per_s: 3 } } },
];

async function setup(opts: { docs?: typeof SAMPLE } = {}) {
  const { app, bridge, client, net, db, headers, post, cleanup } = await setupNet({
    bridge: { docs: opts.docs ?? SAMPLE },
    client: { backoffMaxMs: 80, pingMs: 5000 },
  });
  const state = async () => (await app.inject({ method: "GET", url: "/api/net/state", headers })).json() as NetState;
  return { bridge, client, net, db, app, headers, state, post, cleanup };
}

test("Mirror: изменения одной транзакции применяются разом, запоздалая версия и повтор seq отбрасываются, удаление убирает документ", () => {
  const m = new Mirror();
  m.replaceSnapshot([doc("node", "n1", 1), doc("deck", "s1", 1, { items: [] })], 10);
  assert.equal(m.seq, 10);

  m.apply({ seq: 11, last: false, doc: doc("item", "it_1", 2) });
  assert.equal(m.get("item", "it_1"), undefined, "кадр транзакции без last не виден");
  m.apply({ seq: 11, last: true, doc: doc("deck", "s1", 2, { items: ["it_1"] }) });
  assert.deepEqual(m.get("deck", "s1")!.data, { items: ["it_1"] });
  assert.ok(m.get("item", "it_1"), "после last — обе части вместе");
  assert.equal(m.seq, 11);

  m.apply({ seq: 11, doc: doc("deck", "s1", 99) });
  assert.equal(m.get("deck", "s1")!.ver, 2, "повтор seq не применяется");
  m.apply({ seq: 12, doc: doc("node", "n1", 0, { stale: true }) });
  assert.equal(m.get("node", "n1")!.ver, 1, "старее известной версии не затирает");

  m.apply({ seq: 13, deleted: true, doc: doc("node", "n1", 1) });
  assert.equal(m.get("node", "n1"), undefined);
  m.clear();
  assert.deepEqual(m.all(), {});
});

test("bridgeOptionsFromEnv: без ключа Мост выключен; адрес по умолчанию — порт Моста 7410", () => {
  assert.equal(bridgeOptionsFromEnv({}), null);
  assert.equal(bridgeOptionsFromEnv({ BRIDGE_MASTER_KEY: "  " }), null);
  assert.deepEqual(bridgeOptionsFromEnv({ BRIDGE_MASTER_KEY: "k" }), { url: "ws://127.0.0.1:7410/netrun/v1", key: "k" });
  assert.deepEqual(bridgeOptionsFromEnv({ BRIDGE_MASTER_KEY: "k", BRIDGE_URL: "ws://10.10.0.10:7411/netrun/v1" }), { url: "ws://10.10.0.10:7411/netrun/v1", key: "k" });
});

test("Мост не настроен: экран получает «выключено», кнопки отвечают 503, остальной коллектор жив; без сессии — 401", async () => {
  const db = testDb();
  const app = buildApp(db, { logger: false });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const state = (await app.inject({ method: "GET", url: "/api/net/state", headers })).json() as NetState;
  assert.deepEqual(state, { configured: false, bridge: "disabled", error: null, info: null, docs: {}, serverNow: state.serverNow });
  const pause = await app.inject({ method: "POST", url: "/api/net/pause", headers, payload: { on: true } });
  assert.equal(pause.statusCode, 503);
  assert.equal(pause.json().code, "bridge_unavailable");
  assert.equal((await app.inject({ method: "GET", url: "/api/net/state" })).statusCode, 401);
  assert.equal((await app.inject({ method: "POST", url: "/api/net/pause", payload: { on: true } })).statusCode, 401);
  assert.equal((await app.inject({ method: "GET", url: "/api/health" })).statusCode, 200);
  await app.close();
});

test("клиент: hello и sub, снимок в копии; изменения Моста приходят потоком; ключ роли уходит только в Мост, не в ответ экрану", async () => {
  const { bridge, state, cleanup } = await setup();
  try {
    const s = await state();
    assert.equal(s.configured, true);
    assert.equal(s.bridge, "connected");
    assert.equal(s.info!.version, "fake-0.1");
    assert.deepEqual(Object.keys(s.docs).sort(), ["alert", "master_req", "net_query", "node", "settings", "template", "terminal"]);
    assert.equal(s.docs.node[0].id, "node_07");
    assert.ok(!JSON.stringify(s).includes("master-key"));

    const hello = bridge.requests.find((r) => r.op === "sub")!;
    assert.deepEqual(hello.types, ["node", "node_cfg", "session", "deck", "terminal", "alert", "master_req", "net_query", "template", "settings"]);

    bridge.setDoc("terminal", "t03", { label: "Подвал", node: "node_07", silent: true });
    await waitFor("пуш chg дошёл", async () => (await state()).docs.terminal[0].data.silent === true);
    bridge.setDoc("item", "it_1", { owner: "node:node_07" }); // тип, на который не подписаны
    assert.equal((await state()).docs.item, undefined);
  } finally {
    await cleanup();
  }
});

test("обрыв: пока Моста нет — «недоступен» и пустая копия (не старое как живое); после возврата снимок включает то, что случилось без нас", async () => {
  const { bridge, client, state, post, cleanup } = await setup();
  try {
    bridge.dropClients();
    await waitFor("клиент увидел обрыв", () => client.status !== "connected");
    const down = await state();
    assert.notEqual(down.bridge, "connected");
    assert.deepEqual(down.docs, {}, "копия сброшена");
    assert.equal(down.info, null);
    assert.equal((await post("/api/net/pause", { on: true })).statusCode, 503);

    bridge.setDoc("node", "node_99", { title: "Новый, пока нас не было" });
    await waitFor("переподключились", () => client.status === "connected");
    const up = await state();
    assert.equal(up.bridge, "connected");
    assert.ok(up.docs.node.some((n) => n.id === "node_99"), "новый снимок заменил копию");
  } finally {
    await cleanup();
  }
});

test("неверный ключ роли: Мост отказывает (unauthorized), клиент остаётся «недоступен» с понятной причиной и не падает", async () => {
  const bridge = new FakeBridge({ docs: SAMPLE });
  await bridge.start();
  const client = new BridgeClient({ url: bridge.url, key: "чужой", backoffMinMs: 20, backoffMaxMs: 40, requestTimeoutMs: 500 });
  const net = new NetService(client);
  net.start();
  try {
    await waitFor("ошибка рукопожатия", () => client.lastError !== null);
    assert.match(net.state().error!, /неверный ключ роли/);
    assert.equal(net.state().bridge === "connected", false);
  } finally {
    net.stop();
    await bridge.stop();
  }
});

test("putDoc: создаёт документ (ver 0), на конфликте версий перечитывает и повторяет, чужие поля сохраняет", async () => {
  const { bridge, net, cleanup } = await setup();
  try {
    const created = await net.putDoc("settings", "sec", (cur) => (cur === null ? { factions: { NEON: ["k1"] }, default_faction: "NEON" } : null));
    assert.equal(created!.ver, 1);

    // Мост поменял документ, пока мы мутируем: наша копия устарела → version_conflict → повтор поверх свежего.
    const stale = net.doc("node", "node_07")!;
    bridge.setDoc("node", "node_07", { ...stale.data, eddies: 999 });
    let calls = 0;
    const updated = await net.putDoc("node", "node_07", (cur) => {
      calls++;
      return { ...cur, owner_faction: "NEON" };
    });
    assert.ok(calls >= 1);
    assert.equal(updated!.data.owner_faction, "NEON");
    assert.equal(updated!.data.eddies, 999, "правка Моста не потеряна — put заменяет data целиком, мы сохранили чужие поля");
    assert.equal(updated!.data.title, "Склад");

    // «Менять нечего» — запрос put не уходит.
    const before = bridge.requests.filter((r) => r.op === "put").length;
    await net.putDoc("settings", "sec", () => null);
    assert.equal(bridge.requests.filter((r) => r.op === "put").length, before);
  } finally {
    await cleanup();
  }
});

test("putDoc: Мост всё время отвечает конфликтом — после нескольких попыток понятная ошибка, а не вечный цикл", async () => {
  const { net, bridge, cleanup } = await setup();
  try {
    const orig = bridge.setDoc.bind(bridge);
    let n = 0;
    await assert.rejects(
      net.putDoc("node", "node_07", (cur) => {
        orig("node", "node_07", { ...cur, bump: ++n }); // каждый раз меняем документ у нас из-под рук
        return { ...cur, mine: true };
      }),
      (e: unknown) => e instanceof BridgeError && e.code === "version_conflict",
    );
  } finally {
    await cleanup();
  }
});

test("пауза Сети и узла, рубильник связи: уходят в Мост как master.*, документы меняются, в журнал — по записи", async () => {
  const { bridge, state, post, db, cleanup } = await setup();
  try {
    assert.equal((await post("/api/net/pause", { on: "yes" })).statusCode, 400);
    assert.equal((await post("/api/net/pause", { on: true, node: "плохой id!" })).statusCode, 400);

    assert.equal((await post("/api/net/pause", { on: true })).statusCode, 200);
    assert.equal(bridge.doc("settings", "global")!.data.paused, true);
    await waitFor("копия обновилась", async () => ((await state()).docs.settings[0].data.paused as boolean) === true);

    assert.equal((await post("/api/net/pause", { on: true, node: "node_07" })).statusCode, 200);
    assert.equal(bridge.doc("node_cfg", "node_07")!.data.paused, true);
    const missing = await post("/api/net/pause", { on: true, node: "node_404" });
    assert.equal(missing.statusCode, 404, "узла нет — отказ Моста дошёл до мастера как 404");

    assert.equal((await post("/api/net/link", { on: false })).statusCode, 200);
    assert.equal(bridge.doc("settings", "global")!.data.venue_link, false);

    const log = db.prepare("SELECT action FROM audit_master WHERE action LIKE 'NET_%' ORDER BY at").all() as { action: string }[];
    assert.deepEqual(log.map((l) => l.action), ["NET_PAUSE", "NET_PAUSE", "NET_LINK"], "отказанное действие (узла нет) в журнал не попало");
  } finally {
    await cleanup();
  }
});

test("цели узла: in_s или deadline (ровно одно), снять цель", async () => {
  const { bridge, post, cleanup } = await setup();
  try {
    assert.equal((await post("/api/net/goal", { node: "node_07", kind: "open", value: 120 })).statusCode, 400, "ни in_s, ни deadline");
    assert.equal((await post("/api/net/goal", { node: "node_07", kind: "open", in_s: 60, deadline: 5 })).statusCode, 400, "и то и другое");
    assert.equal((await post("/api/net/goal", { node: "node_07", kind: "Open!", in_s: 60 })).statusCode, 400);
    assert.equal((await post("/api/net/goal", { node: "node_07", kind: "open", value: 120, in_s: 600 })).statusCode, 200);
    const goal = bridge.doc("node_cfg", "node_07")!.data.goal as { kind: string; value: number; done: boolean };
    assert.equal(goal.kind, "open");
    assert.equal(goal.value, 120);
    assert.equal(goal.done, false);
    assert.equal((await post("/api/net/goal/clear", { node: "node_07" })).statusCode, 200);
    assert.equal(bridge.doc("node_cfg", "node_07")!.data.goal, undefined);
  } finally {
    await cleanup();
  }
});

test("«ждём мастера»: решение уходит в Мост; то же — идемпотентно, другое после решения — 409 с документом запроса", async () => {
  const { bridge, post, cleanup } = await setup();
  try {
    assert.equal((await post("/api/net/decide", { req: "flatline:s_1", decision: "maybe" })).statusCode, 400);
    const ok = await post("/api/net/decide", { req: "flatline:s_1", decision: "deny" });
    assert.equal(ok.statusCode, 200);
    assert.equal(bridge.doc("master_req", "flatline:s_1")!.data.decision, "deny");
    assert.equal((await post("/api/net/decide", { req: "flatline:s_1", decision: "deny" })).statusCode, 200);
    const late = await post("/api/net/decide", { req: "flatline:s_1", decision: "approve" });
    assert.equal(late.statusCode, 409);
    assert.equal(late.json().code, "req_state");
    assert.equal(late.json().doc.data.decision, "deny", "экран показывает итог, а не своё нажатие");
    assert.equal((await post("/api/net/decide", { req: "нет:такого", decision: "approve" })).statusCode, 404);
  } finally {
    await cleanup();
  }
});

test("запрос к Сети: ответ мастера; повтор с тем же mid не дублирует; пустой и слишком длинный текст отклоняются", async () => {
  const { bridge, post, cleanup } = await setup();
  try {
    assert.equal((await post("/api/net/reply", { query: "nq_1", mid: "r1", text: "  " })).statusCode, 400);
    assert.equal((await post("/api/net/reply", { query: "nq_1", mid: "r1", text: "x".repeat(2001) })).statusCode, 400);
    assert.equal((await post("/api/net/reply", { query: "nq_1", mid: "r1", text: "Шард в узле 07" })).statusCode, 200);
    assert.equal((await post("/api/net/reply", { query: "nq_1", mid: "r1", text: "Шард в узле 07" })).statusCode, 200);
    const q = bridge.doc("net_query", "nq_1")!.data as { state: string; messages: { mid: string; text: string }[] };
    assert.equal(q.state, "answered");
    assert.equal(q.messages.filter((m) => m.mid === "r1").length, 1);
  } finally {
    await cleanup();
  }
});

test("тревога аудитора: мастер снимает с версией; устаревшая версия — 409, нет тревоги — 404, без версии — 400", async () => {
  const { bridge, headers, app, db, cleanup } = await setup();
  try {
    const del = (id: string, q: string) => app.inject({ method: "DELETE", url: `/api/net/alerts/${id}${q}`, headers });
    assert.equal((await del("al_17", "")).statusCode, 400);
    assert.equal((await del("al_17", "?ver=7")).statusCode, 409);
    assert.equal((await del("al_404", "?ver=1")).statusCode, 404);
    assert.ok(bridge.doc("alert", "al_17"));
    assert.equal((await del("al_17", "?ver=1")).statusCode, 200);
    assert.equal(bridge.doc("alert", "al_17"), undefined);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM audit_master WHERE action = 'NET_ALERT_CLEAR'").get() as { n: number }).n, 1);
  } finally {
    await cleanup();
  }
});

test("заготовка: применяется к узлам одной командой; нет заготовки или узла — отказ без записи", async () => {
  const { bridge, post, cleanup } = await setup();
  try {
    assert.equal((await post("/api/net/template/apply", { template: "tpl_night" })).statusCode, 400, "node_cfg без nodes — bad_request Моста");
    assert.equal((await post("/api/net/template/apply", { template: "tpl_нет", nodes: ["node_07"] })).statusCode, 400, "id по протоколу — только латиница, цифры и _-.:");
    assert.equal((await post("/api/net/template/apply", { template: "tpl_missing", nodes: ["node_07"] })).statusCode, 404);
    assert.equal((await post("/api/net/template/apply", { template: "tpl_night", nodes: ["node_404"] })).statusCode, 404);
    const ok = await post("/api/net/template/apply", { template: "tpl_night", nodes: ["node_07"] });
    assert.equal(ok.statusCode, 200);
    assert.deepEqual(ok.json().nodes, ["node_07"]);
    assert.equal(bridge.doc("node_cfg", "node_07")!.data.trace_per_s, 3);
    assert.equal((bridge.doc("settings", "global")!.data.template_applied as { id: string }).id, "tpl_night");
  } finally {
    await cleanup();
  }
});

test("ручные операции с ценностями: rid сквозной — повтор не выдаёт дважды (replayed), другие параметры — 409; сдача деки запрещена", async () => {
  const { bridge, post, db, cleanup } = await setup();
  try {
    const give = { op: "op.issue_to_phone", rid: "master-anna:give:17", params: { runner: "MFkw", items: ["it_1"], eddies: 0, reason: "ручная выдача" } };
    const first = await post("/api/net/ops", give);
    assert.equal(first.statusCode, 200);
    assert.equal(first.json().replayed, false);
    const again = await post("/api/net/ops", give); // двойное нажатие / повтор после обрыва
    assert.equal(again.json().replayed, true);
    const sent = bridge.requests.filter((r) => r.op === "op.issue_to_phone");
    assert.ok(sent.every((r) => r.rid === "master-anna:give:17"), "коллектор не меняет rid");

    const clash = await post("/api/net/ops", { ...give, params: { ...give.params, items: ["it_2"] } });
    assert.equal(clash.statusCode, 409);
    assert.equal(clash.json().code, "rid_mismatch");

    assert.equal((await post("/api/net/ops", { op: "op.submit_deck", rid: "x", params: {} })).statusCode, 400);
    assert.equal((await post("/api/net/ops", { op: "op.issue_to_phone", params: {} })).statusCode, 400, "без rid");
    // params не может подменить op и rid, проверенные выше.
    await post("/api/net/ops", { op: "run.finish", rid: "finish:s_1", params: { op: "master.pause", rid: "подмена", session: "s_1" } });
    const fin = bridge.requests.filter((r) => r.op === "run.finish").at(-1)!;
    assert.equal(fin.rid, "finish:s_1");

    const logged = (db.prepare("SELECT detail FROM audit_master WHERE action = 'NET_OP' ORDER BY at").all() as { detail: string }[]).map((r) => JSON.parse(r.detail));
    assert.equal(logged[0].replayed, false);
    assert.equal(logged[1].replayed, true);
  } finally {
    await cleanup();
  }
});
