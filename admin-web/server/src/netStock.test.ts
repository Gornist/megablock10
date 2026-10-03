import { test } from "node:test";
import assert from "node:assert/strict";
import { buildApp } from "./app.js";
import { buildStockItem } from "./lib/netPayload.js";
import { BridgeClient } from "./net/bridgeClient.js";
import { FakeBridge } from "./net/fakeBridge.js";
import { NetService } from "./net/netService.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

/** Наполнение узлов «Сети» из «Мастерской»: payload по ItemPayloadCodec Моста, rid-контракт, запас и разгрузка узла. */

async function waitFor(what: string, cond: () => boolean | Promise<boolean>, ms = 4000) {
  const until = Date.now() + ms;
  while (!(await cond())) {
    if (Date.now() > until) assert.fail(`не дождались: ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

const b64 = (t: string) => Buffer.from(t, "utf8").toString("base64");
const SHARD = { type: "SHARD", tier: "HARD", title: "Служебный лог", meta: "клиника", body: "Текст: с | разделителем", valueHint: "ценный", decryptAction: true, moneyAmount: 250, id: "shard-test1" };
const DAEMON = { type: "DAEMON", tier: "BASE", name: "Призрак", sequence: ["1C", "BD"], effect: "GHOST", id: "daemon-test1" };

async function setup(withBridge = true) {
  const bridge = new FakeBridge({ docs: [{ type: "node", id: "node_07", data: { title: "Склад", eddies: 100 } }] });
  await bridge.start();
  const net = new NetService(new BridgeClient({ url: bridge.url, key: "master-key", backoffMinMs: 20, backoffMaxMs: 60, requestTimeoutMs: 1500 }));
  const db = testDb();
  const app = buildApp(db, { logger: false, net });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  if (withBridge) {
    net.start();
    await waitFor("Мост на связи", () => net.connected);
  }
  const post = (url: string, payload: unknown) => app.inject({ method: "POST", url, headers, payload: payload as object });
  return {
    bridge,
    db,
    app,
    headers,
    post,
    cleanup: async () => {
      await app.close();
      await bridge.stop();
    },
  };
}

test("payload предмета — ровно формат ItemPayloadCodec: шард и демон, base64 свободного текста, расшифровка по требованию взлома", () => {
  const s = buildStockItem(SHARD, "stock:1", 0);
  assert.ok(s.ok);
  assert.deepEqual(s.item, {
    kind: "SHARD",
    payload: ["SHARD", "shard-test1", "1", "2", b64("ценный"), b64("Служебный лог"), b64("клиника"), b64("Текст: с | разделителем"), "250", "0"].join("|"),
  });
  const open = buildStockItem({ ...SHARD, decryptAction: false }, "stock:1", 0);
  assert.ok(open.ok && open.item.payload.endsWith("|250|1"), "шард без взлома лежит уже расшифрованным");
  const d = buildStockItem(DAEMON, "stock:1", 1);
  assert.ok(d.ok);
  assert.deepEqual(d.item, { kind: "DAEMON", payload: ["DAEMON", "daemon-test1", b64("Призрак"), "1C,BD", "1", "GHOST"].join("|") });
});

test("id предмета без явного задан от rid и номера: тот же rid — те же байты (иначе Мост ответит rid_mismatch), другой — другой id", () => {
  const a = buildStockItem({ ...SHARD, id: undefined }, "stock:1", 0);
  const again = buildStockItem({ ...SHARD, id: undefined }, "stock:1", 0);
  const other = buildStockItem({ ...SHARD, id: undefined }, "stock:2", 0);
  assert.ok(a.ok && again.ok && other.ok);
  assert.equal(a.item.payload, again.item.payload);
  assert.notEqual(a.item.payload, other.item.payload);
  assert.match(a.item.payload, /^SHARD\|shard-[0-9a-f]{8}\|/);
});

test("ввод проверяется так же, как в генераторе QR: пустой текст, чужой тип, плохие коды и эффект, деньги, тир, id", () => {
  const bad = (raw: unknown) => {
    const r = buildStockItem(raw, "r", 0);
    assert.equal(r.ok, false, JSON.stringify(raw));
  };
  bad({ ...SHARD, title: " " });
  bad({ ...SHARD, body: "" });
  bad({ ...SHARD, moneyAmount: -1 });
  bad({ ...SHARD, moneyAmount: 1.5 });
  bad({ ...SHARD, tier: "EASY" });
  bad({ ...SHARD, id: "a:b" });
  bad({ ...DAEMON, name: "" });
  bad({ ...DAEMON, sequence: [] });
  bad({ ...DAEMON, sequence: ["1C,BD"] });
  bad({ ...DAEMON, effect: "EXPLODE" });
  bad({ type: "ITEM" });
  bad(null);
});

test("наполнение: предметы и эдди ложатся в узел; повтор того же rid — replayed без копий; другие параметры с тем же rid — 409", async () => {
  const { bridge, post, db, cleanup } = await setup();
  try {
    const body = { rid: "stock:17", items: [SHARD, DAEMON], eddies: 50 };
    const first = await post("/api/net/nodes/node_07/stock", body);
    assert.equal(first.statusCode, 200);
    assert.equal(first.json().eddies, 150);
    assert.equal(first.json().items.length, 2);
    assert.deepEqual(Object.keys(first.json()).sort(), ["eddies", "items", "node"], "служебный конверт Моста наружу не отдаём");
    const items = [...bridge.docs.values()].filter((d) => d.type === "item");
    assert.equal(items.length, 2);
    assert.ok(items.every((d) => d.data.owner === "node:node_07" && d.data.origin === "master:collector"));
    assert.equal(bridge.doc("node", "node_07")!.data.eddies, 150);

    const again = await post("/api/net/nodes/node_07/stock", body);
    assert.equal(again.statusCode, 200);
    assert.equal(again.json().replayed, true);
    assert.equal([...bridge.docs.values()].filter((d) => d.type === "item").length, 2, "повтор не плодит копий");
    assert.equal(bridge.doc("node", "node_07")!.data.eddies, 150);

    const clash = await post("/api/net/nodes/node_07/stock", { ...body, eddies: 99 });
    assert.equal(clash.statusCode, 409);
    assert.equal(clash.json().code, "rid_mismatch");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM audit_master WHERE action = 'NET_STOCK'").get() as { n: number }).n, 2);
  } finally {
    await cleanup();
  }
});

test("запас узла: список без тел шардов; разгрузка уводит предмет в burned:master и вычитает эдди; чужой предмет — 409, лишние эдди — 400", async () => {
  const { bridge, post, app, headers, cleanup } = await setup();
  try {
    const stocked = await post("/api/net/nodes/node_07/stock", { rid: "stock:1", items: [SHARD, DAEMON], eddies: 0 });
    const [shardId, daemonId] = stocked.json().items as string[];

    const view = (await app.inject({ method: "GET", url: "/api/net/nodes/node_07/items", headers })).json();
    assert.equal(view.node, "node_07");
    assert.equal(view.eddies, 100);
    assert.equal(view.items.length, 2);
    assert.ok(view.items.every((i: { payload?: unknown }) => i.payload === undefined), "тело не отдаём");

    assert.equal((await post("/api/net/nodes/node_07/unstock", { rid: "u:1", items: ["it_0000000000000000"] })).statusCode, 409);
    assert.equal((await post("/api/net/nodes/node_07/unstock", { rid: "u:2", eddies: 500 })).statusCode, 400);
    const ok = await post("/api/net/nodes/node_07/unstock", { rid: "u:3", items: [shardId], eddies: 30 });
    assert.equal(ok.statusCode, 200);
    assert.equal(ok.json().eddies, 70);
    assert.equal(bridge.doc("item", shardId)!.data.owner, "burned:master");
    assert.equal(bridge.doc("item", daemonId)!.data.owner, "node:node_07");

    const after = (await app.inject({ method: "GET", url: "/api/net/nodes/node_07/items", headers })).json();
    assert.deepEqual(after.items.map((i: { id: string }) => i.id), [daemonId]);
  } finally {
    await cleanup();
  }
});

test("проверка ввода и доступа: без rid, пустой запрос, плохой предмет, плохой id узла — 400; нет узла — 404; без сессии — 401", async () => {
  const { app, post, cleanup } = await setup();
  try {
    assert.equal((await post("/api/net/nodes/node_07/stock", { items: [SHARD] })).statusCode, 400);
    assert.equal((await post("/api/net/nodes/node_07/stock", { rid: "s:1" })).statusCode, 400);
    const bad = await post("/api/net/nodes/node_07/stock", { rid: "s:2", items: [{ ...SHARD, title: "" }] });
    assert.equal(bad.statusCode, 400);
    assert.match(bad.json().error, /предмет 1/);
    assert.equal((await post("/api/net/nodes/node_07/stock", { rid: "s:3", eddies: -5 })).statusCode, 400);
    assert.equal((await post("/api/net/nodes/узел!/stock", { rid: "s:4", eddies: 5 })).statusCode, 400);
    assert.equal((await post("/api/net/nodes/node_404/stock", { rid: "s:5", eddies: 5 })).statusCode, 404);
    assert.equal((await post("/api/net/nodes/node_07/unstock", { rid: "u:4" })).statusCode, 400);
    assert.equal((await app.inject({ method: "POST", url: "/api/net/nodes/node_07/stock", payload: { rid: "x", eddies: 1 } })).statusCode, 401);
    assert.equal((await app.inject({ method: "GET", url: "/api/net/nodes/node_07/items" })).statusCode, 401);
  } finally {
    await cleanup();
  }
});

test("Моста нет: наполнение и список отвечают 503, ничего не записано", async () => {
  const { post, app, headers, cleanup } = await setup(false);
  try {
    assert.equal((await post("/api/net/nodes/node_07/stock", { rid: "s:1", eddies: 5 })).statusCode, 503);
    assert.equal((await app.inject({ method: "GET", url: "/api/net/nodes/node_07/items", headers })).statusCode, 503);
  } finally {
    await cleanup();
  }
});
