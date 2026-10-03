import { test } from "node:test";
import assert from "node:assert/strict";
import { buildApp } from "./app.js";
import { bridgeRunnerDocId } from "./lib/netRunners.js";
import { BridgeClient } from "./net/bridgeClient.js";
import { FakeBridge } from "./net/fakeBridge.js";
import { NetService } from "./net/netService.js";
import { seedPlayer } from "./testHelpers.js";
import { loginAs, testDb, testDevice, testMaster } from "./testUtil.js";

/**
 * Решения мастера о нетраннере доходят до документов runner в Мосте (id r_<sha256 ключа>, ключ в data.key): «пощадить», ручное закрытие,
 * «может входить в Сеть» (allowed), фракция персонажа, догон после обрыва.
 */

async function waitFor(what: string, cond: () => boolean | Promise<boolean>, ms = 4000) {
  const until = Date.now() + ms;
  while (!(await cond())) {
    if (Date.now() > until) assert.fail(`не дождались: ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

async function setup(docs: ConstructorParameters<typeof FakeBridge>[0] = {}) {
  const bridge = new FakeBridge(docs);
  await bridge.start();
  const net = new NetService(new BridgeClient({ url: bridge.url, key: "master-key", backoffMinMs: 20, backoffMaxMs: 60, requestTimeoutMs: 1500 }));
  const db = testDb();
  const app = buildApp(db, { logger: false, net });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const flags = () => db.prepare("SELECT runner_key, blocked, bridge_synced FROM net_runner_flags").all() as { runner_key: string; blocked: number; bridge_synced: number }[];
  return {
    bridge,
    net,
    db,
    app,
    headers,
    flags,
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

/** Флэтлайн от мира: запись NET_FLATLINE с ключом нетраннера (обычный base64, как у телефона). */
async function flatline(app: Awaited<ReturnType<typeof setup>>["app"], runner: string) {
  const world = testDevice();
  const rec = world.change({
    field: "net.run",
    newValue: JSON.stringify({ session: "s_aaaaaaaaaaaaaaaa", runner, callsign: "Волна", terminal: "t03", node: "node_07", outcome: "black_ice", disconnect: false, left_in_node: 2, cause: "флэтлайн" }),
    reason: "NET_FLATLINE",
    sourceRef: "s_aaaaaaaaaaaaaaaa",
  });
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records: [rec] } });
  assert.deepEqual(res.json().rejected, []);
}

test("«пощадить»: флаг уходит в документ runner Моста (blocked=false), запись помечается доставленной", async () => {
  const { app, bridge, headers, flags, connect, cleanup } = await setup();
  try {
    const p = await seedPlayer(app, { callsign: "Волна", faction: "NEON" });
    const id = bridgeRunnerDocId(p.publicKeyB64);
    // Мост уже заблокировал сам (black_ice) — это его быстрая защита до ответа коллектора.
    bridge.setDoc("runner", id, { key: p.publicKeyB64, callsign: "Волна", blocked: true, blocked_reason: "black_ice", runs: 3, tutorial_done: true });
    await connect();
    await flatline(app, p.publicKeyB64);
    await waitFor("флаг поставлен коллектором", () => flags()[0]?.blocked === 1);
    assert.equal(bridge.doc("runner", id)!.data.blocked, true);

    const spare = await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/spare`, headers, payload: { note: "договорились" } });
    assert.equal(spare.statusCode, 200);
    await waitFor("runner разблокирован в Мосте", () => bridge.doc("runner", id)!.data.blocked === false);
    const d = bridge.doc("runner", id)!.data;
    assert.equal(d.blocked_reason, null);
    assert.equal(d.runs, 3, "чужие поля документа сохранены");
    assert.equal(d.tutorial_done, true);
    assert.equal(d.key, p.publicKeyB64);
    assert.equal(d.faction, "NEON", "фракцию персонажа коллектор пишет вместе с флагом");
    await waitFor("доставлено", () => flags()[0]?.bridge_synced === 1);
  } finally {
    await cleanup();
  }
});

test("ручное закрытие допуска создаёт runner в Мосте с key и умолчаниями нового нетраннера; повтор put не шлёт", async () => {
  const { app, bridge, headers, flags, connect, cleanup } = await setup();
  try {
    const p = await seedPlayer(app, { callsign: "Ася", faction: "NEON" });
    await connect();
    const res = await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/block`, headers, payload: { reason: "драка у стойки" } });
    assert.equal(res.statusCode, 200);
    const id = bridgeRunnerDocId(p.publicKeyB64);
    await waitFor("runner создан", () => bridge.doc("runner", id) !== undefined);
    assert.deepEqual(
      { ...bridge.doc("runner", id)!.data },
      { key: p.publicKeyB64, callsign: "Ася", blocked: true, blocked_reason: "драка у стойки", allowed: false, faction: "NEON", runs: 0, tutorial_done: false },
    );
    await waitFor("доставлено", () => flags()[0]?.bridge_synced === 1);
    const puts = () => bridge.requests.filter((r) => r.op === "put" && r.type === "runner").length;
    const before = puts();
    await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/block`, headers, payload: { reason: "ещё раз" } });
    await new Promise((r) => setTimeout(r, 100));
    assert.equal(puts(), before, "уже закрыто — ничего не пишем");
  } finally {
    await cleanup();
  }
});

test("«пощадить» того, кого Мост не знает, ничего не создаёт — но помечается доставленным", async () => {
  const { app, bridge, headers, flags, connect, cleanup } = await setup();
  try {
    const p = await seedPlayer(app, { callsign: "Боря", faction: "NEON" });
    await connect();
    await flatline(app, p.publicKeyB64);
    await waitFor("флаг поставлен и обработан", () => flags().length === 1 && flags()[0].blocked === 1);
    await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/spare`, headers, payload: {} });
    await waitFor("доставлено", () => flags()[0].blocked === 0 && flags()[0].bridge_synced === 1);
    assert.equal(bridge.doc("runner", bridgeRunnerDocId(p.publicKeyB64)), undefined, "снимать нечего — документ не создаётся");
  } finally {
    await cleanup();
  }
});

test("Моста нет: решение сохраняется и ждёт; при подключении догоняется само", async () => {
  const { app, bridge, headers, flags, connect, cleanup } = await setup();
  try {
    const p = await seedPlayer(app, { callsign: "Вова", faction: "NEON" });
    const res = await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/block`, headers, payload: { reason: "по просьбе мастера" } });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().bridgeSynced, false);
    assert.equal(flags()[0].bridge_synced, 0);

    await connect();
    await waitFor("догнали после подключения", () => flags()[0].bridge_synced === 1);
    assert.equal(bridge.doc("runner", bridgeRunnerDocId(p.publicKeyB64))!.data.blocked, true);
  } finally {
    await cleanup();
  }
});

test("«нетраннер» (белый список): отметка уходит в runner.allowed вместе с фракцией; снять — allowed=false; неизвестный игрок — 404", async () => {
  const { app, bridge, headers, connect, cleanup } = await setup();
  try {
    const p = await seedPlayer(app, { callsign: "Гоша", faction: "ARASAKA" });
    await connect();
    const put = (key: string, body: unknown) => app.inject({ method: "PUT", url: `/api/net/runners/${encodeURIComponent(key)}/allowed`, headers, payload: body as object });
    assert.equal((await put(p.publicKeyB64, { allowed: "да" })).statusCode, 400);
    assert.equal((await put("QUJD", { allowed: true })).statusCode, 404);
    assert.equal((await put(p.publicKeyB64, { allowed: true })).statusCode, 200);

    const id = bridgeRunnerDocId(p.publicKeyB64);
    await waitFor("runner создан с allowed", () => bridge.doc("runner", id)?.data.allowed === true);
    assert.equal(bridge.doc("runner", id)!.data.faction, "ARASAKA");
    assert.equal(bridge.doc("runner", id)!.data.blocked, false);
    assert.equal(bridge.doc("runner", id)!.data.key, p.publicKeyB64);

    const flag = (await app.inject({ method: "GET", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}`, headers })).json();
    assert.deepEqual(flag, { blocked: false, allowed: true });
    assert.equal((await app.inject({ method: "GET", url: "/api/net/access", headers })).json().allowedCount, 1);

    await put(p.publicKeyB64, { allowed: false });
    await waitFor("allowed снят", () => bridge.doc("runner", id)!.data.allowed === false);
  } finally {
    await cleanup();
  }
});

test("проверка допуска в Мосте: включается мастером в settings/global.require_allowed, остальные настройки целы; нет документа — 404", async () => {
  const { app, bridge, headers, connect, cleanup } = await setup({ docs: [{ type: "settings", id: "global", data: { paused: false, auditor_period_s: 2 } }] });
  try {
    await connect();
    const post = (payload: unknown) => app.inject({ method: "POST", url: "/api/net/require-allowed", headers, payload: payload as object });
    assert.equal((await post({ on: "да" })).statusCode, 400);
    assert.equal((await post({ on: true })).statusCode, 200);
    assert.deepEqual({ ...bridge.doc("settings", "global")!.data }, { paused: false, auditor_period_s: 2, require_allowed: true });
    const ver = bridge.doc("settings", "global")!.ver;
    await post({ on: true });
    assert.equal(bridge.doc("settings", "global")!.ver, ver, "уже включено — put не уходит");
    await post({ on: false });
    assert.equal(bridge.doc("settings", "global")!.data.require_allowed, false);
  } finally {
    await cleanup();
  }
});
