import { test } from "node:test";
import assert from "node:assert/strict";
import type { AudioClip, DisplaySecretResponse, WorldEventsConfig } from "./apiTypes.js";
import { buildApp } from "./app.js";
import { DisplayManager } from "./displays/manager.js";
import { MockDisplay } from "./displays/mockDisplay.js";
import { secretKey } from "./displays/repository.js";
import { parseWorldEvent } from "./lib/worldEvents.js";
import { resetWorldEventLog } from "./lib/worldEventLog.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

/** Быстрые события «Сети» (docs/netrun-world-records.md, §3) на настоящих mock-точках — тот же стенд, что у audio.test.ts. */

const FAST = { connectTimeoutMs: 300, helloTimeoutMs: 200, receivedTimeoutMs: 300, displayedTimeoutMs: 300, commandTimeoutMs: 300, retryDelaysMs: [20, 20], probeIntervalMs: 0, log: () => {} };

function wav(ms: number, rate = 16000): Buffer {
  const samples = Math.round((rate * ms) / 1000);
  const b = Buffer.alloc(44 + samples * 2);
  b.write("RIFF", 0, "ascii");
  b.writeUInt32LE(36 + samples * 2, 4);
  b.write("WAVEfmt ", 8, "ascii");
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write("data", 36, "ascii");
  b.writeUInt32LE(samples * 2, 40);
  return b;
}

async function waitFor(what: string, cond: () => boolean | Promise<boolean>, ms = 3000) {
  const until = Date.now() + ms;
  while (!(await cond())) {
    if (Date.now() > until) assert.fail(`не дождались: ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

async function setup() {
  resetWorldEventLog();
  const db = testDb();
  const displays = new DisplayManager(db, FAST);
  const app = buildApp(db, { logger: false, displays });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const mocks: MockDisplay[] = [];

  async function addPoint(id: string) {
    const mock = new MockDisplay({ deviceId: id, key: Buffer.alloc(32), width: 792, height: 272, displayDelayMs: 5, roles: ["display", "audio"], tracks: ["radio-1.mp3"], announceSpeed: 0.1 });
    const port = await mock.start();
    const res = await app.inject({ method: "POST", url: "/api/displays", headers, payload: { id, name: `Точка ${id}`, ip: "127.0.0.1", port } });
    assert.equal(res.statusCode, 200, res.body);
    (mock.options as { key: Buffer }).key = secretKey({ secret: (res.json() as DisplaySecretResponse).secret });
    mocks.push(mock);
    await probeUntil(id);
    return mock;
  }
  const probeUntil = async (id: string) => {
    const until = Date.now() + 3000;
    for (;;) {
      const run = displays.probe(id);
      if (run) return run;
      if (Date.now() > until) assert.fail(`точка ${id} занята — опрос не принят`);
      await new Promise((r) => setTimeout(r, 10));
    }
  };
  const addClip = async () =>
    (await app.inject({ method: "POST", url: "/api/audio/clips", headers, payload: { name: "Сирена", data: wav(800).toString("base64") } })).json() as AudioClip;
  const link = (id: string, netNode: string | null, terminal: string | null) => app.inject({ method: "PUT", url: `/api/net/point-links/${id}`, headers, payload: { netNode, terminal } });
  const bind = (kind: string, clipId: string | null, extra: object = {}) => app.inject({ method: "PUT", url: `/api/net/world-events/actions/${kind}`, headers, payload: { clipId, ...extra } });
  const send = (events: unknown[], h: Record<string, string> = {}) => app.inject({ method: "POST", url: "/api/world-events", headers: h, payload: { events } });
  const ev = (over: Record<string, unknown> = {}) => ({ id: `ev_${Math.random().toString(36).slice(2)}`, kind: "run.enter", ts: Date.now(), ttl_ms: 5000, node: "node_07", terminal: "t03", session: "s_1", level: null, ...over });
  const cleanup = async () => {
    await app.close();
    await Promise.all(mocks.map((m) => m.stop()));
  };
  return { db, app, headers, addPoint, addClip, link, bind, send, ev, cleanup };
}

test("parseWorldEvent: по контракту — вид из семи, id, ts, ttl_ms; всё остальное отклоняется", () => {
  const ok = parseWorldEvent({ id: "ev_7d1c0a", kind: "trace.level", ts: 1790000650000, ttl_ms: 5000, node: "node_07", terminal: "t03", session: "s_9f", level: "TRACE" });
  assert.deepEqual(ok, { id: "ev_7d1c0a", kind: "trace.level", ts: 1790000650000, ttlMs: 5000, node: "node_07", terminal: "t03", session: "s_9f", level: "TRACE" });
  assert.equal(parseWorldEvent({ id: "x", kind: "run.enter", ts: 1 })!.ttlMs, 5000, "ttl по умолчанию — 5 с");
  assert.equal(parseWorldEvent({ id: "x", kind: "run.enter", ts: 1 })!.terminal, null);
  for (const bad of [null, "x", {}, { id: "x", kind: "bogus", ts: 1 }, { id: "", kind: "run.enter", ts: 1 }, { id: "x", kind: "run.enter" }, { id: "x", kind: "run.enter", ts: 1, ttl_ms: 999999 }, { id: "x", kind: "run.enter", ts: 1, node: 5 }]) {
    assert.equal(parseWorldEvent(bad), null, JSON.stringify(bad));
  }
});

test("POST /api/world-events: без секрета игры 401, не массив 400, пустая настройка — событие принято и ничего не делает", async () => {
  const prev = process.env.GAME_SECRET;
  process.env.GAME_SECRET = "s3cret";
  const { send, ev, app, cleanup } = await setup();
  try {
    assert.equal((await send([ev()])).statusCode, 401);
    const ok = await send([ev()], { "x-game-secret": "s3cret" });
    assert.equal(ok.statusCode, 200);
    assert.equal(ok.json().accepted, 1);
    const notArray = await app.inject({ method: "POST", url: "/api/world-events", headers: { "x-game-secret": "s3cret" }, payload: { events: "x" } });
    assert.equal(notArray.statusCode, 400);
    const tooMany = await send(Array.from({ length: 51 }, () => ev()), { "x-game-secret": "s3cret" });
    assert.equal(tooMany.statusCode, 400);
  } finally {
    if (prev === undefined) delete process.env.GAME_SECRET;
    else process.env.GAME_SECRET = prev;
    await cleanup();
  }
});

test("просроченное (ttl_ms) и повторное (id) событие отбрасываются, невалидное не мешает остальным", async () => {
  const { send, ev, cleanup } = await setup();
  try {
    const fresh = ev();
    const res = await send([fresh, fresh, ev({ ts: Date.now() - 6000 }), { id: "bad", kind: "nope", ts: 1 }, ev({ kind: "lockdown" })]);
    assert.deepEqual(res.json(), { accepted: 2, expired: 1, duplicate: 1, invalid: 1 });
    const again = await send([fresh]);
    assert.equal(again.json().duplicate, 1, "повтор после повторной попытки Моста не звучит дважды");
  } finally {
    await cleanup();
  }
});

test("событие по терминалу играет клип на точке этого терминала, а не на чужой; по узлу — на точках узла", async () => {
  const { addPoint, addClip, link, bind, send, ev, cleanup } = await setup();
  try {
    const t03 = await addPoint("p-t03");
    const t07 = await addPoint("p-t07");
    const hall = await addPoint("p-hall");
    const clip = await addClip();
    for (const [id, node, terminal] of [["p-t03", null, "t03"], ["p-t07", null, "t07"], ["p-hall", "node_07", null]] as const) assert.equal((await link(id, node, terminal)).statusCode, 200);

    assert.equal((await bind("run.enter", clip.id)).statusCode, 200);
    assert.equal((await bind("lockdown", clip.id, { volume: 95, chime: false })).statusCode, 200);

    // run.enter — только терминал t03: узловая точка (зал) его не слышит.
    assert.equal((await send([ev({ kind: "run.enter", terminal: "t03", node: "node_07" })])).json().accepted, 1);
    await waitFor("играет p-t03", () => t03.announcement?.state === "playing" || t03.announcement?.state === "done");
    assert.equal(t07.announcement, null);
    assert.equal(hall.announcement, null, "run.enter идёт по терминалу, не по узлу");

    // lockdown — точки узла (зал), терминальные не трогает.
    await send([ev({ kind: "lockdown", terminal: "t07", node: "node_07" })]);
    await waitFor("играет зал", () => hall.announcement != null);
    assert.equal(t07.announcement, null, "lockdown идёт по узлу, не по терминалу");
  } finally {
    await cleanup();
  }
});

test("без назначенного клипа, при выключенном действии и без связи точки событие ничего не играет; alert.master на площадку не идёт", async () => {
  const { addPoint, addClip, link, bind, send, ev, cleanup } = await setup();
  try {
    const p = await addPoint("p-1");
    const clip = await addClip();
    await link("p-1", "node_07", "t03");

    await send([ev({ kind: "flatline" })]);
    assert.equal(p.announcement, null, "по умолчанию события ничего не делают");

    await bind("flatline", clip.id, { enabled: false });
    await send([ev({ kind: "flatline" })]);
    assert.equal(p.announcement, null, "выключенное действие");

    await bind("ice.hunt", clip.id);
    await send([ev({ kind: "ice.hunt", node: "node_99" })]);
    assert.equal(p.announcement, null, "точка стоит у другого узла");

    const refused = await bind("alert.master", clip.id);
    assert.equal(refused.statusCode, 400, "тревога мастеру — только панель мастера");
  } finally {
    await cleanup();
  }
});

test("alert.master попадает в «Требует внимания» мастеру", async () => {
  const { app, headers, send, ev, cleanup } = await setup();
  try {
    await send([ev({ kind: "alert.master", terminal: null, node: "node_07" })]);
    const attn = (await app.inject({ method: "GET", url: "/api/attention", headers })).json() as { items: { kind: string; severity: string; detail: string }[] };
    const card = attn.items.find((i) => i.kind === "net_master_alert")!;
    assert.equal(card.severity, "crit");
    assert.match(card.detail, /node_07/);
  } finally {
    await cleanup();
  }
});

test("настройка: валидация, конфиг для экрана, «проверить» играет так же, как событие от Моста; без сессии — 401", async () => {
  const { app, headers, addPoint, addClip, link, bind, cleanup } = await setup();
  try {
    const p = await addPoint("p-1");
    const clip = await addClip();
    await link("p-1", null, "t03");

    assert.equal((await bind("bogus", clip.id)).statusCode, 404);
    assert.equal((await bind("flatline", "f".repeat(64))).statusCode, 400, "неизвестный клип");
    assert.equal((await bind("flatline", clip.id, { volume: 101 })).statusCode, 400);
    assert.equal((await link("nope", "n", null)).statusCode, 404);
    assert.equal((await link("p-1", "плохой id!", null)).statusCode, 400);

    const saved = await bind("flatline", clip.id, { volume: 90 });
    assert.equal(saved.statusCode, 200);
    assert.equal(saved.json().clipName, "Сирена");
    assert.equal(saved.json().enabled, true, "назначили клип — действие включено");

    const cfg = (await app.inject({ method: "GET", url: "/api/net/world-events/config", headers })).json() as WorldEventsConfig;
    assert.equal(cfg.kinds.length, 7);
    assert.equal(cfg.actions.find((a) => a.kind === "flatline")!.volume, 90);
    assert.equal(cfg.actions.find((a) => a.kind === "run.enter")!.enabled, false);
    assert.deepEqual(cfg.links, [{ displayId: "p-1", displayName: "Точка p-1", netNode: null, terminal: "t03" }]);

    const test = await app.inject({ method: "POST", url: "/api/net/world-events/test", headers, payload: { kind: "flatline", terminal: "t03" } });
    assert.equal(test.statusCode, 200);
    assert.deepEqual(test.json().playedOn, ["p-1"]);
    await waitFor("«проверить» сыграло", () => p.announcement != null);

    // Снять связь: пустые узел и терминал.
    await link("p-1", null, null);
    assert.deepEqual(((await app.inject({ method: "GET", url: "/api/net/world-events/config", headers })).json() as WorldEventsConfig).links, []);

    assert.equal((await app.inject({ method: "GET", url: "/api/net/world-events/config" })).statusCode, 401);
    assert.equal((await app.inject({ method: "POST", url: "/api/net/world-events/test", payload: { kind: "flatline" } })).statusCode, 401);
  } finally {
    await cleanup();
  }
});
