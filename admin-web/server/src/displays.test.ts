import { test } from "node:test";
import assert from "node:assert/strict";
import type { DisplayGroup, DisplayItem, DisplayPreview, DisplayPushResponse, DisplaySecretResponse } from "./apiTypes.js";
import { buildApp } from "./app.js";
import { DisplayManager } from "./displays/manager.js";
import { MockDisplay } from "./displays/mockDisplay.js";
import { renderQrForDisplay } from "./displays/renderer.js";
import { secretKey } from "./displays/repository.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

const FAST = { connectTimeoutMs: 300, helloTimeoutMs: 200, receivedTimeoutMs: 300, displayedTimeoutMs: 300, commandTimeoutMs: 300, retryDelaysMs: [20], probeIntervalMs: 0, log: () => {} };

async function setup() {
  const db = testDb();
  const displays = new DisplayManager(db, FAST);
  const app = buildApp(db, { logger: false, displays });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const mocks: MockDisplay[] = [];

  /** Дисплей через API + mock-плата с выданным секретом, как при установке. */
  async function addDisplay(id: string, extra: Record<string, unknown> = {}) {
    const mock = new MockDisplay({ deviceId: id, key: Buffer.alloc(32), width: 792, height: 272, displayDelayMs: 5 });
    const port = await mock.start();
    const res = await app.inject({ method: "POST", url: "/api/displays", headers, payload: { id, name: `Точка ${id}`, ip: "127.0.0.1", port, ...extra } });
    assert.equal(res.statusCode, 200, res.body);
    const body = res.json() as DisplaySecretResponse;
    // «Прошили» плату выданным секретом.
    (mock.options as { key: Buffer }).key = secretKey({ secret: body.secret });
    mocks.push(mock);
    return { mock, body };
  }

  async function createContainer(id: string) {
    const res = await app.inject({
      method: "POST",
      url: "/api/master/containers",
      headers,
      payload: { id, name: "Насосная-4", tier: "HARD", ownerFaction: "Otryad_SB", slots: [{ type: "SHARD", tier: "BASE", copies: 1, shard: { title: "Логи", body: "код 4471" } }] },
    });
    assert.equal(res.statusCode, 200, res.body);
    return res.json() as { qr: string };
  }

  const cleanup = async () => {
    await app.close();
    await Promise.all(mocks.map((m) => m.stop()));
  };
  return { db, app, headers, displays, addDisplay, createContainer, cleanup };
}

test("без сессии мастера — 401 на всё", async () => {
  const { app, cleanup } = await setup();
  try {
    for (const [method, url] of [
      ["GET", "/api/displays"],
      ["POST", "/api/displays"],
      ["POST", "/api/displays/push"],
      ["POST", "/api/displays/preview"],
      ["POST", "/api/displays/x/reboot"],
    ] as const) {
      assert.equal((await app.inject({ method, url, payload: {} })).statusCode, 401, url);
    }
  } finally {
    await cleanup();
  }
});

test("регистрация: секрет отдаётся один раз, в списке и карточке его нет", async () => {
  const { app, headers, addDisplay, cleanup } = await setup();
  try {
    const { body } = await addDisplay("display-017");
    assert.match(body.secret, /^[0-9a-f]{64}$/);
    assert.deepEqual(body.provisioning, { id: "display-017", secret: body.secret, port: body.display.port, width: 792, height: 272 });
    assert.equal(body.display.status, "OFFLINE");

    const list = await app.inject({ method: "GET", url: "/api/displays", headers });
    assert.equal((list.json() as DisplayItem[]).length, 1);
    assert.ok(!list.body.includes(body.secret));
    const one = await app.inject({ method: "GET", url: "/api/displays/display-017", headers });
    assert.ok(!one.body.includes(body.secret));
    assert.ok(!("secret" in one.json()));

    const again = await app.inject({ method: "POST", url: "/api/displays/display-017/secret", headers });
    assert.notEqual((again.json() as DisplaySecretResponse).secret, body.secret);
  } finally {
    await cleanup();
  }
});

test("регистрация: проверка полей и дубликатов", async () => {
  const { app, headers, cleanup } = await setup();
  try {
    const post = (payload: Record<string, unknown>) => app.inject({ method: "POST", url: "/api/displays", headers, payload });
    assert.equal((await post({ id: "a b", name: "x", ip: "10.0.0.1" })).statusCode, 400);
    assert.equal((await post({ id: "d1", name: "x", ip: "display.local" })).statusCode, 400, "только IP — адреса дисплеев постоянные");
    assert.equal((await post({ id: "d1", name: "x", ip: "10.0.0.1", port: 70000 })).statusCode, 400);
    assert.equal((await post({ id: "d1", name: "", ip: "10.0.0.1" })).statusCode, 400);
    const ok = await post({ id: "d1", name: "Точка 1", ip: "10.0.0.1" });
    assert.equal(ok.statusCode, 200);
    const d = (ok.json() as DisplaySecretResponse).display;
    assert.deepEqual([d.port, d.width, d.height, d.enabled], [47200, 792, 272, true]);
    assert.equal((await post({ id: "d1", name: "x", ip: "10.0.0.2" })).statusCode, 409);

    const put = await app.inject({ method: "PUT", url: "/api/displays/d1", headers, payload: { ip: "10.0.0.9", enabled: false } });
    assert.equal(put.statusCode, 200);
    assert.equal((put.json() as DisplayItem).ip, "10.0.0.9");
    assert.equal((put.json() as DisplayItem).name, "Точка 1");
    assert.equal((put.json() as DisplayItem).status, "DISABLED");

    assert.equal((await app.inject({ method: "DELETE", url: "/api/displays/d1", headers })).statusCode, 200);
    assert.equal((await app.inject({ method: "GET", url: "/api/displays/d1", headers })).statusCode, 404);
  } finally {
    await cleanup();
  }
});

test("предпросмотр контейнера: та же строка QR, что выдала Мастерская для печати, и кадр как PNG", async () => {
  const { app, headers, createContainer, cleanup } = await setup();
  try {
    const printed = await createContainer("nasos-4");
    const res = await app.inject({ method: "POST", url: "/api/displays/preview", headers, payload: { source: { type: "container", id: "nasos-4" } } });
    assert.equal(res.statusCode, 200, res.body);
    const p = res.json() as DisplayPreview;
    assert.equal(p.qr, printed.qr);
    assert.equal(p.label, "контейнер «Насосная-4»");
    assert.match(p.png, /^data:image\/png;base64,/);
    assert.deepEqual([p.width, p.height], [792, 272]);
    assert.ok(p.scale >= 1);

    assert.equal((await app.inject({ method: "POST", url: "/api/displays/preview", headers, payload: { source: { type: "container", id: "nope" } } })).statusCode, 404);
    assert.equal((await app.inject({ method: "POST", url: "/api/displays/preview", headers, payload: { source: { type: "qr", qr: "hello" } } })).statusCode, 400);
  } finally {
    await cleanup();
  }
});

test("контейнер, залитый извне без содержимого слотов, на дисплей не отправить — QR не из чего собрать", async () => {
  const { app, headers, addDisplay, cleanup } = await setup();
  try {
    await addDisplay("d1");
    await app.inject({
      method: "POST",
      url: "/api/containers",
      headers,
      payload: { containers: [{ id: "ext-1", name: "Внешний", tier: "BASE", ownerFaction: "X", slots: [{ type: "SHARD", tier: "BASE", copies: 1, title: "t" }] }] },
    });
    const res = await app.inject({ method: "POST", url: "/api/displays/d1/push", headers, payload: { source: { type: "container", id: "ext-1" } } });
    assert.equal(res.statusCode, 409);
  } finally {
    await cleanup();
  }
});

test("отправка контейнера на дисплей: на панели — кадр того же QR; журнал мастеров", async () => {
  const { app, headers, addDisplay, createContainer, cleanup } = await setup();
  try {
    const { mock } = await addDisplay("d1");
    const printed = await createContainer("nasos-4");
    const res = await app.inject({ method: "POST", url: "/api/displays/d1/push", headers, payload: { source: { type: "container", id: "nasos-4" }, wait: true } });
    assert.equal(res.statusCode, 200, res.body);
    const body = res.json() as DisplayPushResponse;
    assert.deepEqual(body.results, [{ displayId: "d1", ok: true, version: 1, outcome: "DISPLAYED" }]);
    assert.deepEqual(mock.framebuffer, renderQrForDisplay(printed.qr, 792, 272).data);

    const item = (await app.inject({ method: "GET", url: "/api/displays/d1", headers })).json() as DisplayItem;
    assert.equal(item.displayedVersion, 1);
    assert.equal(item.desiredLabel, "контейнер «Насосная-4»");
    assert.equal(item.status, "ONLINE");

    const current = await app.inject({ method: "GET", url: "/api/displays/d1/preview", headers });
    assert.equal((current.json() as DisplayPreview).qr, printed.qr);

    const audit = await app.inject({ method: "GET", url: "/api/audit", headers });
    assert.ok(audit.body.includes("DISPLAY_PUSH"));
  } finally {
    await cleanup();
  }
});

test("групповая отправка: каждый дисплей независимо, неизвестный и выключенный — отдельной строкой", async () => {
  const { app, headers, addDisplay, displays, cleanup } = await setup();
  try {
    const a = await addDisplay("d1");
    const b = await addDisplay("d2");
    await addDisplay("d3", { enabled: false });
    const qr = "MB10:SHARD:v1:shard-1:0:1:::::0";
    const res = await app.inject({
      method: "POST",
      url: "/api/displays/push",
      headers,
      payload: { displayIds: ["d1", "d2", "d3", "nope"], source: { type: "qr", qr, label: "шард" } },
    });
    assert.equal(res.statusCode, 200, res.body);
    const results = (res.json() as DisplayPushResponse).results;
    assert.deepEqual(
      results.map((r) => [r.displayId, r.ok, r.outcome ?? r.error]),
      [
        ["d1", true, "QUEUED"],
        ["d2", true, "QUEUED"],
        ["d3", false, "display is disabled"],
        ["nope", false, "unknown display"],
      ],
    );
    await displays.idle();
    assert.equal(a.mock.displayedVersion, 1);
    assert.equal(b.mock.displayedVersion, 1);
    const list = (await app.inject({ method: "GET", url: "/api/displays", headers })).json() as DisplayItem[];
    assert.deepEqual(
      list.map((d) => [d.id, d.status]),
      [
        ["d1", "ONLINE"],
        ["d2", "ONLINE"],
        ["d3", "DISABLED"],
      ],
    );
  } finally {
    await cleanup();
  }
});

test("отправка на недоступный дисплей: итог FAILED, в карточке ERROR и текст ошибки", async () => {
  const { app, headers, addDisplay, cleanup } = await setup();
  try {
    const { mock } = await addDisplay("d1");
    await mock.stop();
    const res = await app.inject({ method: "POST", url: "/api/displays/d1/push", headers, payload: { source: { type: "qr", qr: "MB10:RAM:v1:r:1" }, wait: true } });
    const r = (res.json() as DisplayPushResponse).results[0];
    assert.equal(r.ok, false);
    assert.equal(r.outcome, "FAILED");
    const item = (await app.inject({ method: "GET", url: "/api/displays/d1", headers })).json() as DisplayItem;
    assert.equal(item.status, "ERROR");
    assert.match(item.lastError!, /CONNECT/);
    assert.equal(item.desiredVersion, 1);
    assert.equal(item.displayedVersion, null);
  } finally {
    await cleanup();
  }
});

test("команды: тест, подсветка (проверка уровня), перезагрузка, проверка связи", async () => {
  const { app, headers, addDisplay, cleanup } = await setup();
  try {
    const { mock } = await addDisplay("d1");
    const post = (url: string, payload: Record<string, unknown> = {}) => app.inject({ method: "POST", url, headers, payload });
    assert.equal((await post("/api/displays/d1/test", { seconds: 10 })).json().ok, true);
    assert.equal((await post("/api/displays/d1/backlight", { level: "BRIGHT" })).statusCode, 400);
    assert.equal((await post("/api/displays/d1/backlight", { level: "HIGH", seconds: 15 })).json().ok, true);
    assert.equal(mock.backlight, 3);
    assert.equal((await post("/api/displays/d1/reboot")).json().ok, true);
    const probe = (await post("/api/displays/d1/probe")).json() as { ok: boolean; display: DisplayItem };
    assert.equal(probe.ok, true);
    assert.equal(probe.display.status, "ONLINE");
    assert.equal((await post("/api/displays/nope/reboot")).statusCode, 404);
  } finally {
    await cleanup();
  }
});

test("группы: создать, назначить при создании, из карточки и правкой; переименовать; удалить — дисплеи остаются без группы", async () => {
  const { app, headers, addDisplay, cleanup } = await setup();
  try {
    const create = async (name: string) => app.inject({ method: "POST", url: "/api/display-groups", headers, payload: { name } });
    const bar = (await create("Бар «Посмертие»")).json() as DisplayGroup;
    assert.equal(bar.count, 0);
    assert.equal((await create("  бар «посмертие» ")).statusCode, 409, "имя без учёта регистра и пробелов по краям");
    assert.equal((await create("")).statusCode, 400);
    const clinic = (await create("Клиника")).json() as DisplayGroup;

    await addDisplay("display-001", { groupId: bar.id });
    await addDisplay("display-002");
    const get = async (id: string) => (await app.inject({ method: "GET", url: `/api/displays/${id}`, headers })).json() as DisplayItem;
    assert.equal((await get("display-001")).groupId, bar.id);
    assert.equal((await get("display-002")).groupId, null);
    const bad = await app.inject({ method: "POST", url: "/api/displays", headers, payload: { id: "display-009", name: "x", ip: "127.0.0.1", groupId: "g-nope" } });
    assert.equal(bad.statusCode, 400);

    // Из карточки — только группа, остальное не трогается.
    let res = await app.inject({ method: "PUT", url: "/api/displays/display-002/group", headers, payload: { groupId: clinic.id } });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal((res.json() as DisplayItem).groupId, clinic.id);
    assert.equal((await get("display-002")).name, "Точка display-002");
    // Правка без groupId группу не сбрасывает; null — убирает.
    res = await app.inject({ method: "PUT", url: "/api/displays/display-002", headers, payload: { name: "Клиника, вход" } });
    assert.equal((res.json() as DisplayItem).groupId, clinic.id);
    res = await app.inject({ method: "PUT", url: "/api/displays/display-002", headers, payload: { groupId: null } });
    assert.equal((res.json() as DisplayItem).groupId, null);
    await app.inject({ method: "PUT", url: "/api/displays/display-002/group", headers, payload: { groupId: clinic.id } });

    const list = async () => (await app.inject({ method: "GET", url: "/api/display-groups", headers })).json() as DisplayGroup[];
    assert.deepEqual(
      (await list()).map((g) => [g.name, g.count]),
      [
        ["Бар «Посмертие»", 1],
        ["Клиника", 1],
      ],
    );
    res = await app.inject({ method: "PUT", url: `/api/display-groups/${clinic.id}`, headers, payload: { name: "Клиника Трамы" } });
    assert.equal((res.json() as DisplayGroup).name, "Клиника Трамы");
    res = await app.inject({ method: "PUT", url: `/api/display-groups/${clinic.id}`, headers, payload: { name: "бар «посмертие»" } });
    assert.equal(res.statusCode, 409);

    res = await app.inject({ method: "DELETE", url: `/api/display-groups/${bar.id}`, headers });
    assert.equal(res.statusCode, 200);
    assert.equal((await get("display-001")).groupId, null, "дисплей не удалён, просто без группы");
    assert.deepEqual(
      (await list()).map((g) => g.name),
      ["Клиника Трамы"],
    );
    const audit = await app.inject({ method: "GET", url: "/api/audit?limit=50", headers });
    assert.match(audit.body, /DISPLAY_GROUP_CREATE|Группа дисплеев создана/);
  } finally {
    await cleanup();
  }
});

test("точка ↔ узел: создать с узлом, чужой узел — 400, второй точке тот же узел — 409, перепривязать и отвязать", async () => {
  const { app, headers, db, createContainer, cleanup } = await setup();
  try {
    await createContainer("nasos-4");
    await createContainer("bar-7");
    const add = (payload: Record<string, unknown>) => app.inject({ method: "POST", url: "/api/displays", headers, payload });
    const base = { ip: "10.0.0.1", port: 47200 };
    const created = await add({ id: "p-1", name: "Насосная", ...base, nodeId: "nasos-4" });
    assert.equal(created.statusCode, 200, created.body);
    assert.equal((created.json() as DisplaySecretResponse).display.nodeId, "nasos-4");

    const unknown = await add({ id: "p-2", name: "Бар", ...base, nodeId: "no-such-node" });
    assert.equal(unknown.statusCode, 400);
    assert.match(unknown.body, /unknown node/);
    assert.equal((await add({ id: "p-2", name: "Бар", ...base, nodeId: 7 })).statusCode, 400);

    const taken = await add({ id: "p-2", name: "Бар", ...base, nodeId: "nasos-4" });
    assert.equal(taken.statusCode, 409);
    assert.match(taken.body, /p-1/);

    // Точка без узла — норма; правкой — привязать к свободному узлу; к занятому — 409.
    assert.equal((await add({ id: "p-2", name: "Бар", ...base })).statusCode, 200);
    const put = (id: string, payload: Record<string, unknown>) => app.inject({ method: "PUT", url: `/api/displays/${id}`, headers, payload });
    assert.equal((await put("p-2", { nodeId: "nasos-4" })).statusCode, 409);
    const upd = await put("p-2", { nodeId: "bar-7" });
    assert.equal(upd.statusCode, 200, upd.body);
    assert.equal((upd.json() as DisplayItem).nodeId, "bar-7");
    // Правка без nodeId узел не трогает; повторное сохранение той же точки со своим узлом — не конфликт.
    assert.equal(((await put("p-2", { name: "Бар «Посмертие»" })).json() as DisplayItem).nodeId, "bar-7");
    assert.equal((await put("p-1", { nodeId: "nasos-4" })).statusCode, 200);

    // Быстрая привязка из карточки узла.
    const node = (id: string, nodeId: unknown) => app.inject({ method: "PUT", url: `/api/displays/${id}/node`, headers, payload: { nodeId } });
    assert.equal((await node("p-2", "nasos-4")).statusCode, 409);
    assert.equal(((await node("p-1", null)).json() as DisplayItem).nodeId, null);
    assert.equal(((await node("p-2", "nasos-4")).json() as DisplayItem).nodeId, "nasos-4");
    assert.equal((await node("nope", null)).statusCode, 404);

    const actions = db.prepare(`SELECT action, detail FROM audit_master WHERE action IN ('DISPLAY_SET_NODE', 'DISPLAY_UPDATE') ORDER BY at`).all() as {
      action: string;
      detail: string;
    }[];
    assert.ok(actions.some((a) => a.action === "DISPLAY_UPDATE" && JSON.parse(a.detail).nodeId === "bar-7"));
    assert.equal(actions.filter((a) => a.action === "DISPLAY_SET_NODE").length, 2);
  } finally {
    await cleanup();
  }
});
