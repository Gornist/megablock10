import { test } from "node:test";
import assert from "node:assert/strict";
import { buildApp } from "./app.js";
import { toBridgeRunnerKey } from "./lib/netRunners.js";
import { BridgeClient } from "./net/bridgeClient.js";
import { FakeBridge } from "./net/fakeBridge.js";
import { NetService } from "./net/netService.js";
import { seedPlayer } from "./testHelpers.js";
import { loginAs, testDb, testDevice, testMaster } from "./testUtil.js";

/** Решения о допуске нетраннера доходят до документов runner в Мосте: «пощадить», ручное закрытие, догон после обрыва. */

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

/** Флэтлайн от мира: запись NET_FLATLINE с ключом нетраннера в виде Моста (base64url). */
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
    const bridgeKey = toBridgeRunnerKey(p.publicKeyB64);
    // Мост уже заблокировал сам (black_ice) — это его быстрая защита до ответа коллектора.
    bridge.setDoc("runner", bridgeKey, { callsign: "Волна", blocked: true, blocked_reason: "black_ice", runs: 3, tutorial_done: true });
    await connect();
    await flatline(app, bridgeKey);
    await waitFor("флаг поставлен коллектором", () => flags()[0]?.blocked === 1);
    assert.equal(bridge.doc("runner", bridgeKey)!.data.blocked, true);

    const spare = await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/spare`, headers, payload: { note: "договорились" } });
    assert.equal(spare.statusCode, 200);
    await waitFor("runner разблокирован в Мосте", () => bridge.doc("runner", bridgeKey)!.data.blocked === false);
    const d = bridge.doc("runner", bridgeKey)!.data;
    assert.equal(d.blocked_reason, null);
    assert.equal(d.runs, 3, "чужие поля документа сохранены");
    assert.equal(d.tutorial_done, true);
    await waitFor("доставлено", () => flags()[0]?.bridge_synced === 1);
  } finally {
    await cleanup();
  }
});

test("ручное закрытие допуска создаёт runner в Мосте с умолчаниями нового нетраннера; повтор put не шлёт", async () => {
  const { app, bridge, headers, flags, connect, cleanup } = await setup();
  try {
    const p = await seedPlayer(app, { callsign: "Ася", faction: "NEON" });
    await connect();
    const res = await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/block`, headers, payload: { reason: "драка у стойки" } });
    assert.equal(res.statusCode, 200);
    const id = toBridgeRunnerKey(p.publicKeyB64);
    await waitFor("runner создан", () => bridge.doc("runner", id) !== undefined);
    assert.deepEqual(
      { ...bridge.doc("runner", id)!.data },
      { callsign: "", blocked: true, blocked_reason: "драка у стойки", runs: 0, tutorial_done: false },
      "позывной коллектор не выдумывает; блок записан, остальное — как у нового нетраннера",
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
    await flatline(app, toBridgeRunnerKey(p.publicKeyB64));
    await waitFor("флаг поставлен и обработан", () => flags().length === 1 && flags()[0].blocked === 1);
    await app.inject({ method: "POST", url: `/api/net/runners/${encodeURIComponent(p.publicKeyB64)}/spare`, headers, payload: {} });
    await waitFor("доставлено", () => flags()[0].blocked === 0 && flags()[0].bridge_synced === 1);
    assert.equal(bridge.doc("runner", toBridgeRunnerKey(p.publicKeyB64)), undefined, "снимать нечего — документ не создаётся");
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
    assert.equal(bridge.doc("runner", toBridgeRunnerKey(p.publicKeyB64))!.data.blocked, true);
  } finally {
    await cleanup();
  }
});
