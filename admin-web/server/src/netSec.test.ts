import { test } from "node:test";
import assert from "node:assert/strict";
import { buildApp } from "./app.js";
import { BridgeClient } from "./net/bridgeClient.js";
import { FakeBridge } from "./net/fakeBridge.js";
import { NetService } from "./net/netService.js";
import { computeSecDoc, SecSync } from "./net/secSync.js";
import { seedPlayer } from "./testHelpers.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

/** Получатели сигнала СБ: документ settings/sec в Мосте собирается из фракций игроков (docs/netrun-collector-brief.md, задача 3). */

async function waitFor(what: string, cond: () => boolean | Promise<boolean>, ms = 4000) {
  const until = Date.now() + ms;
  while (!(await cond())) {
    if (Date.now() > until) assert.fail(`не дождались: ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

async function setup() {
  const bridge = new FakeBridge({ docs: [{ type: "node", id: "node_07", data: { title: "Склад", eddies: 300 } }] });
  await bridge.start();
  const net = new NetService(new BridgeClient({ url: bridge.url, key: "master-key", backoffMinMs: 20, backoffMaxMs: 60, requestTimeoutMs: 1500 }));
  const db = testDb();
  const app = buildApp(db, { logger: false, net });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const sec = new SecSync(db, net, 0); // таймер выключен — синк вызываем сами
  return {
    bridge,
    net,
    db,
    app,
    headers,
    sec,
    connect: async () => {
      net.start();
      await waitFor("Мост на связи", () => net.connected);
    },
    cleanup: async () => {
      await app.close();
      await bridge.stop();
    },
  };
}

test("computeSecDoc: ключи телефонов действующих игроков по фракциям; без фракции, заменённые и сбросившие сессию — не получатели", async () => {
  const { app, db, cleanup } = await setup();
  try {
    const a = await seedPlayer(app, { callsign: "Ася", faction: "ARASAKA" });
    const b = await seedPlayer(app, { callsign: "Боря", faction: "ARASAKA" });
    const c = await seedPlayer(app, { callsign: "Вова", faction: "NEON" });
    await seedPlayer(app, { callsign: "Нет", faction: "" });
    const doc = computeSecDoc(db);
    assert.deepEqual(doc.factions, { ARASAKA: [a.publicKeyB64, b.publicKeyB64].sort(), NEON: [c.publicKeyB64] });
    assert.equal(doc.default_faction, null);
  } finally {
    await cleanup();
  }
});

test("синк: документа нет — создаётся при подключении сам; потом пишется только когда состав изменился; чужие поля сохраняются", async () => {
  const { app, bridge, sec, connect, cleanup } = await setup();
  try {
    const a = await seedPlayer(app, { callsign: "Ася", faction: "ARASAKA" });
    await connect();

    // Собственный SecSync приложения создаёт документ сразу при подключении — тут только дожидаемся.
    await waitFor("документ создан при подключении", () => bridge.doc("settings", "sec") !== undefined);
    const first = bridge.doc("settings", "sec")!;
    assert.equal(first.ver, 1);
    assert.deepEqual(first.data.factions, { ARASAKA: [a.publicKeyB64] });
    assert.equal(first.data.default_faction, null);
    assert.equal(first.data.key_format, "base64");

    const puts = () => bridge.requests.filter((r) => r.op === "put" && r.id === "sec").length;
    const before = puts();
    assert.equal(await sec.sync(), false, "ничего не менялось — put не уходит");
    assert.equal(puts(), before);
    assert.equal(sec.status().inSync, true);

    // Мост (или мастер на нём) добавил своё поле — при следующем put оно не пропадает.
    bridge.setDoc("settings", "sec", { ...bridge.doc("settings", "sec")!.data, note: "руками" });
    await waitFor("копия увидела правку", () => sec.status().docVer === 2);
    const b = await seedPlayer(app, { callsign: "Боря", faction: "NEON" });
    assert.equal(sec.status().inSync, false);
    assert.equal(await sec.sync(), true);
    const next = bridge.doc("settings", "sec")!;
    assert.equal(next.data.note, "руками");
    assert.deepEqual(next.data.factions, { ARASAKA: [a.publicKeyB64], NEON: [b.publicKeyB64] });
  } finally {
    await cleanup();
  }
});

test("синк: без Моста ничего не делает и не падает; после (пере)подключения документ догоняется сам", async () => {
  const { app, bridge, net, db, connect, cleanup } = await setup();
  try {
    await seedPlayer(app, { callsign: "Ася", faction: "ARASAKA" });
    const sec = new SecSync(db, net, 0);
    sec.start(); // слушает onConnected
    assert.equal(await sec.sync(), false, "Моста пока нет");
    await connect();
    await waitFor("документ создан после подключения", () => bridge.doc("settings", "sec") !== undefined);

    bridge.dropClients();
    await waitFor("обрыв", () => !net.connected);
    assert.deepEqual(sec.status(), { connected: false, inSync: false, docVer: null, lastError: null }, "при обрыве устаревшую копию за «актуально» не выдаём");
    const c = await seedPlayer(app, { callsign: "Вова", faction: "NEON" });
    await waitFor("снова на связи", () => net.connected);
    await waitFor("документ догнан", () => ((bridge.doc("settings", "sec")!.data.factions as Record<string, string[]>).NEON ?? []).includes(c.publicKeyB64));
    sec.stop();
  } finally {
    await cleanup();
  }
});

test("фракция СБ по умолчанию: настройка мастера → документ в Мосте; сброс; валидация; без сессии 401", async () => {
  const { app, headers, bridge, connect, sec, cleanup } = await setup();
  try {
    await seedPlayer(app, { callsign: "Ася", faction: "ARASAKA" });
    await connect();
    sec.start();

    assert.equal((await app.inject({ method: "PUT", url: "/api/net/sec", headers, payload: { defaultFaction: 5 } })).statusCode, 400);
    assert.equal((await app.inject({ method: "PUT", url: "/api/net/sec", payload: { defaultFaction: "СБ" } })).statusCode, 401);

    const set = await app.inject({ method: "PUT", url: "/api/net/sec", headers, payload: { defaultFaction: "  Security  " } });
    assert.equal(set.statusCode, 200);
    assert.equal(set.json().defaultFaction, "Security");
    await waitFor("документ в Мосте", () => bridge.doc("settings", "sec")?.data.default_faction === "Security");
    assert.deepEqual(set.json().recipients, [{ faction: "ARASAKA", count: 1 }]);

    const got = (await app.inject({ method: "GET", url: "/api/net/sec", headers })).json();
    assert.equal(got.defaultFaction, "Security");
    assert.equal(got.sync.inSync, true);

    await app.inject({ method: "PUT", url: "/api/net/sec", headers, payload: { defaultFaction: null } });
    await waitFor("снято", () => bridge.doc("settings", "sec")?.data.default_faction === null);
  } finally {
    await cleanup();
  }
});

test("без Моста настройка СБ всё равно сохраняется и ждёт подключения; статус «не в Мосте»", async () => {
  const db = testDb();
  const app = buildApp(db, { logger: false });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const set = await app.inject({ method: "PUT", url: "/api/net/sec", headers, payload: { defaultFaction: "Security" } });
  assert.equal(set.statusCode, 200);
  assert.equal(set.json().sync.connected, false);
  assert.equal(set.json().sync.docVer, null);
  assert.equal(set.json().sync.inSync, false);
  await app.close();
});

test("владелец узла: пишется в документ node с сохранением остальных полей; снять; нет узла — 404; без Моста — 503", async () => {
  const { app, headers, bridge, net, connect, cleanup } = await setup();
  try {
    await connect();
    const put = (id: string, faction: unknown) => app.inject({ method: "PUT", url: `/api/net/nodes/${id}/owner`, headers, payload: { faction } });

    assert.equal((await put("node_07", 5)).statusCode, 400);
    assert.equal((await put("узел!", "NEON")).statusCode, 400);
    assert.equal((await put("node_404", "NEON")).statusCode, 404);

    const ok = await put("node_07", "NEON");
    assert.equal(ok.statusCode, 200);
    const d = bridge.doc("node", "node_07")!.data;
    assert.equal(d.owner_faction, "NEON");
    assert.equal(d.title, "Склад");
    assert.equal(d.eddies, 300, "ценность узла не тронута");

    const ver = bridge.doc("node", "node_07")!.ver;
    await put("node_07", "NEON");
    assert.equal(bridge.doc("node", "node_07")!.ver, ver, "то же значение — put не уходит");

    assert.equal((await put("node_07", null)).statusCode, 200);
    assert.equal(bridge.doc("node", "node_07")!.data.owner_faction, undefined);

    await bridge.stop();
    await waitFor("обрыв", () => !net.connected);
    assert.equal((await put("node_07", "ARASAKA")).statusCode, 503);
  } finally {
    await app.close();
  }
});
