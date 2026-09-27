import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:net";
import type { AddressInfo } from "node:net";
import { DisplayManager, type DisplayManagerConfig } from "./displays/manager.js";
import { MockDisplay, type MockFaults } from "./displays/mockDisplay.js";
import { BacklightLevel } from "./displays/protocol.js";
import { getPixel, renderQrForDisplay } from "./displays/renderer.js";
import { newDisplaySecret, secretKey } from "./displays/repository.js";
import { testDb } from "./testUtil.js";

const QR_A = "MB10:RAM:v1:ram-aaaa:1";
const QR_B = "MB10:RAM:v1:ram-bbbb:2";
const QR_C = "MB10:RAM:v1:ram-cccc:3";

/** Быстрые таймауты и паузы — тесты не ждут секунд боевых значений. */
const FAST: Partial<DisplayManagerConfig> = {
  connectTimeoutMs: 300,
  helloTimeoutMs: 200,
  receivedTimeoutMs: 300,
  displayedTimeoutMs: 300,
  commandTimeoutMs: 300,
  retryDelaysMs: [20, 40],
  probeIntervalMs: 0,
  log: () => {},
};

async function rig(opts: { displays?: number; faults?: MockFaults; displayDelayMs?: number; config?: Partial<DisplayManagerConfig>; width?: number; height?: number } = {}) {
  const db = testDb();
  const lines: string[] = [];
  const manager = new DisplayManager(db, { ...FAST, log: (l) => lines.push(l), ...opts.config });
  const mocks: MockDisplay[] = [];
  for (let i = 0; i < (opts.displays ?? 1); i++) {
    const id = `display-${String(i + 1).padStart(3, "0")}`;
    const secret = newDisplaySecret();
    const mock = new MockDisplay({
      deviceId: id,
      key: secretKey({ secret }),
      width: opts.width ?? 272,
      height: opts.height ?? 792,
      displayDelayMs: opts.displayDelayMs ?? 5,
      faults: opts.faults,
    });
    const port = await mock.start();
    manager.repo.create(id, { name: `Точка ${i + 1}`, ip: "127.0.0.1", port, width: 272, height: 792, enabled: true }, secret);
    mocks.push(mock);
  }
  const cleanup = async () => {
    manager.stop();
    await Promise.all(mocks.map((m) => m.stop()));
  };
  return { db, manager, mocks, lines, cleanup };
}

/** Свободный порт, на котором никто не слушает — «дисплей выключен». */
async function deadPort(): Promise<number> {
  const s = createServer();
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const port = (s.address() as AddressInfo).port;
  await new Promise<void>((r) => s.close(() => r()));
  return port;
}

test("отправка: connect → HELLO → IMAGE → RECEIVED → DISPLAYED; на дисплее ровно кадр рендера; состояние сохранено", async () => {
  const { manager, mocks, lines, cleanup } = await rig();
  try {
    const job = manager.pushImage("display-001", QR_A, "RAM +1");
    assert.equal(job.version, 1);
    assert.equal(manager.get("display-001")!.status, "UPDATING");
    const r = await job.result;
    assert.deepEqual(r, { outcome: "DISPLAYED", version: 1 });
    assert.deepEqual(mocks[0].framebuffer, renderQrForDisplay(QR_A, 272, 792).data);
    const item = manager.get("display-001")!;
    assert.equal(item.displayedVersion, 1);
    assert.equal(item.desiredVersion, 1);
    assert.equal(item.desiredLabel, "RAM +1");
    assert.equal(item.status, "ONLINE");
    assert.equal(item.fwVersion, "mock-1.0");
    assert.equal(item.lastError, null);
    for (const event of ["DISPLAY_CONNECT", "DISPLAY_SEND_START", "DISPLAY_RECEIVED", "DISPLAY_DISPLAYED", "DISPLAY_DISCONNECT"]) {
      assert.ok(lines.some((l) => l.startsWith(`[DISPLAY] ${event} display-001`)), event);
    }
    assert.ok(lines.some((l) => l.includes("image=1 bytes=26928")));
  } finally {
    await cleanup();
  }
});

test("версии растут: вторая отправка — версия 2, дисплей её принимает", async () => {
  const { manager, mocks, cleanup } = await rig();
  try {
    assert.equal((await manager.pushImage("display-001", QR_A, "a").result).outcome, "DISPLAYED");
    const second = manager.pushImage("display-001", QR_B, "b");
    assert.equal(second.version, 2);
    assert.equal((await second.result).outcome, "DISPLAYED");
    assert.equal(mocks[0].displayedVersion, 2);
  } finally {
    await cleanup();
  }
});

test("дисплей не отвечает на соединение — ограниченные повторы, затем FAILED с ошибкой, без бесконечного цикла", async () => {
  const { manager, mocks, lines, cleanup } = await rig({ faults: { dropConnections: 10 } });
  try {
    const r = await manager.pushImage("display-001", QR_A, "a").result;
    assert.equal(r.outcome, "FAILED");
    assert.equal(mocks[0].connections, 3, "1 попытка + 2 повтора");
    const item = manager.get("display-001")!;
    assert.equal(item.status, "ERROR");
    assert.match(item.lastError!, /DISCONNECT|TIMEOUT/);
    assert.equal(item.displayedVersion, null);
    assert.equal(lines.filter((l) => l.includes("attempt=")).length, 3);
  } finally {
    await cleanup();
  }
});

test("обрыв на первой попытке — повтор успешен (reconnect)", async () => {
  const { manager, mocks, cleanup } = await rig({ faults: { dropConnections: 1 } });
  try {
    const r = await manager.pushImage("display-001", QR_A, "a").result;
    assert.equal(r.outcome, "DISPLAYED");
    assert.equal(mocks[0].connections, 2);
  } finally {
    await cleanup();
  }
});

test("нет TCP вовсе (дисплей выключен) — FAILED по connect", async () => {
  const { manager, cleanup } = await rig({ displays: 0 });
  try {
    manager.repo.create("display-x", { name: "x", ip: "127.0.0.1", port: await deadPort(), width: 272, height: 792, enabled: true }, newDisplaySecret());
    const r = await manager.pushImage("display-x", QR_A, "a").result;
    assert.equal(r.outcome, "FAILED");
    assert.match(r.error!, /CONNECT/);
  } finally {
    await cleanup();
  }
});

test("HELLO не пришёл — таймаут и повтор", async () => {
  const { manager, lines, cleanup } = await rig({ faults: { silentHello: 1 } });
  try {
    assert.equal((await manager.pushImage("display-001", QR_A, "a").result).outcome, "DISPLAYED");
    assert.ok(lines.some((l) => l.startsWith("[DISPLAY] DISPLAY_TIMEOUT display-001") && l.includes("no HELLO")));
  } finally {
    await cleanup();
  }
});

test("битый кадр по дороге — NACK BAD_CRC, повтор проходит; журнал DISPLAY_CRC_FAILED", async () => {
  const { manager, mocks, lines, cleanup } = await rig({ faults: { corruptIncoming: 1 } });
  try {
    assert.equal((await manager.pushImage("display-001", QR_A, "a").result).outcome, "DISPLAYED");
    assert.ok(lines.some((l) => l.startsWith("[DISPLAY] DISPLAY_CRC_FAILED display-001")));
    assert.equal(mocks[0].displayedVersion, 1);
  } finally {
    await cleanup();
  }
});

test("неверный секрет — AUTH_FAILED без повторов, картинка не показана", async () => {
  const { manager, mocks, lines, cleanup } = await rig();
  try {
    manager.repo.setSecret("display-001", newDisplaySecret());
    const r = await manager.pushImage("display-001", QR_A, "a").result;
    assert.equal(r.outcome, "FAILED");
    assert.match(r.error!, /AUTH_FAILED/);
    assert.equal(mocks[0].connections, 1, "повтор с тем же секретом бесполезен");
    assert.equal(mocks[0].framebuffer, null);
    assert.ok(lines.some((l) => l.startsWith("[DISPLAY] DISPLAY_AUTH_FAILED display-001")));
    assert.equal(manager.get("display-001")!.status, "ERROR");
  } finally {
    await cleanup();
  }
});

test("размер панели не совпадает с записью — ошибка конфигурации без повторов", async () => {
  const { manager, mocks, cleanup } = await rig({ width: 792, height: 272 });
  try {
    const r = await manager.pushImage("display-001", QR_A, "a").result;
    assert.equal(r.outcome, "FAILED");
    assert.match(r.error!, /792×272/);
    assert.equal(mocks[0].connections, 1);
  } finally {
    await cleanup();
  }
});

test("DISPLAYED потерялся — повтор видит версию в HELLO и засчитывает, не отправляя кадр второй раз", async () => {
  const { manager, mocks, cleanup } = await rig({ faults: { loseDisplayed: 1 } });
  try {
    const r = await manager.pushImage("display-001", QR_A, "a").result;
    assert.deepEqual(r, { outcome: "DISPLAYED", version: 1 });
    assert.equal(mocks[0].received.filter((e) => e.type === "IMAGE").length, 1);
    assert.equal(manager.get("display-001")!.displayedVersion, 1);
  } finally {
    await cleanup();
  }
});

test("панель не обновилась (NACK DISPLAY_FAILED) — повтор", async () => {
  const { manager, mocks, cleanup } = await rig({ faults: { failDisplay: 1 } });
  try {
    assert.equal((await manager.pushImage("display-001", QR_A, "a").result).outcome, "DISPLAYED");
    assert.equal(mocks[0].received.filter((e) => e.type === "IMAGE").length, 2);
  } finally {
    await cleanup();
  }
});

test("дисплей показывает версию новее сервера (БД из копии) — ручная отправка перенумеровывается выше и проходит", async () => {
  const { manager, mocks, cleanup } = await rig();
  try {
    mocks[0].displayedVersion = 50;
    const r = await manager.pushImage("display-001", QR_A, "a").result;
    assert.deepEqual(r, { outcome: "DISPLAYED", version: 51 });
    assert.equal(mocks[0].displayedVersion, 51);
    assert.equal(manager.get("display-001")!.desiredVersion, 51);
    // Следующая версия — выше показанной.
    assert.equal(manager.pushImage("display-001", QR_B, "b").version, 52);
    await manager.idle();
  } finally {
    await cleanup();
  }
});

test("очередь: одна в работе + одна последняя; промежуточная отбрасывается (101 → 103, без 102)", async () => {
  const { manager, mocks, lines, cleanup } = await rig({ displayDelayMs: 80 });
  try {
    const a = manager.pushImage("display-001", QR_A, "a");
    await new Promise((r) => setTimeout(r, 20)); // A уже в работе
    const b = manager.pushImage("display-001", QR_B, "b");
    const c = manager.pushImage("display-001", QR_C, "c");
    const item = manager.get("display-001")!;
    assert.equal(item.activeVersion, a.version);
    assert.equal(item.pendingVersion, c.version);
    assert.deepEqual(await b.result, { outcome: "SUPERSEDED", version: b.version });
    assert.equal((await a.result).outcome, "DISPLAYED");
    assert.equal((await c.result).outcome, "DISPLAYED");
    assert.deepEqual(
      mocks[0].received.filter((e) => e.type === "IMAGE").map((e) => e.seq),
      [a.version, c.version],
    );
    assert.deepEqual(mocks[0].framebuffer, renderQrForDisplay(QR_C, 272, 792).data);
    assert.ok(lines.some((l) => l.includes("DISPLAY_SUPERSEDED")));
    assert.equal(mocks[0].maxOpenConnections, 1, "к одному дисплею — одно соединение за раз");
  } finally {
    await cleanup();
  }
});

test("массовая отправка: дисплеи обновляются параллельно и независимо, недоступный не блокирует остальных", async () => {
  const { manager, mocks, cleanup } = await rig({ displays: 6, displayDelayMs: 150 });
  try {
    await mocks[2].stop(); // один выключен
    const started = Date.now();
    const results = await Promise.all(mocks.map((m) => manager.pushImage(m.options.deviceId, QR_A, "a").result));
    const elapsed = Date.now() - started;
    assert.deepEqual(
      results.map((r) => r.outcome),
      ["DISPLAYED", "DISPLAYED", "FAILED", "DISPLAYED", "DISPLAYED", "DISPLAYED"],
    );
    // Последовательно было бы ≥ 5 × 150 мс только на «обновление панели»; параллельно — порядка одного.
    assert.ok(elapsed < 4 * 150, `elapsed ${elapsed}`);
  } finally {
    await cleanup();
  }
});

test("лимит одновременных соединений соблюдается", async () => {
  const { manager, mocks, cleanup } = await rig({ displays: 5, displayDelayMs: 50, config: { maxConcurrent: 2 } });
  try {
    let open = 0;
    let peak = 0;
    const timer = setInterval(() => {
      open = mocks.reduce((n, m) => n + m.openConnections, 0);
      peak = Math.max(peak, open);
    }, 2);
    const results = await Promise.all(mocks.map((m) => manager.pushImage(m.options.deviceId, QR_A, "a").result));
    clearInterval(timer);
    assert.ok(results.every((r) => r.outcome === "DISPLAYED"));
    assert.ok(peak <= 2, `peak ${peak}`);
    assert.ok(peak >= 1);
  } finally {
    await cleanup();
  }
});

test("команды: тест, подсветка, перезагрузка — OK от дисплея", async () => {
  const { manager, mocks, cleanup } = await rig();
  try {
    assert.equal((await manager.test("display-001", 20)).outcome, "DISPLAYED");
    assert.equal((await manager.backlight("display-001", BacklightLevel.MEDIUM, 15)).outcome, "DISPLAYED");
    assert.equal(mocks[0].backlight, BacklightLevel.MEDIUM);
    assert.equal((await manager.reboot("display-001")).outcome, "DISPLAYED");
    assert.deepEqual(
      mocks[0].received.map((e) => e.type),
      ["TEST", "BACKLIGHT", "REBOOT"],
    );
  } finally {
    await cleanup();
  }
});

test("опрос: ONLINE по HELLO; выключенный — OFFLINE без ошибки; не дошедшая отправка досылается, когда связь вернулась", async () => {
  const { manager, mocks, cleanup } = await rig({ config: { onlineWindowMs: 60_000 } });
  try {
    assert.equal(manager.get("display-001")!.status, "OFFLINE");
    await manager.probe("display-001");
    assert.equal(manager.get("display-001")!.status, "ONLINE");

    // Дисплей пропал — отправка не дошла.
    mocks[0].faults.dropConnections = 3;
    assert.equal((await manager.pushImage("display-001", QR_B, "b").result).outcome, "FAILED");
    assert.equal(manager.get("display-001")!.status, "ERROR");
    assert.equal(mocks[0].displayedVersion, 0);

    // Связь вернулась: плановый опрос видит, что на экране старое, и досылает ту же версию.
    await manager.probeAll();
    await manager.idle();
    assert.equal(mocks[0].displayedVersion, 1);
    assert.deepEqual(mocks[0].framebuffer, renderQrForDisplay(QR_B, 272, 792).data);
    const item = manager.get("display-001")!;
    assert.equal(item.status, "ONLINE");
    assert.equal(item.lastError, null);
  } finally {
    await cleanup();
  }
});

test("опрос недоступного дисплея не пишет ошибку (это OFFLINE), неверный секрет — пишет", async () => {
  const { manager, mocks, lines, cleanup } = await rig({ displays: 2 });
  try {
    await mocks[0].stop();
    manager.repo.setSecret("display-002", newDisplaySecret());
    await manager.probeAll();
    assert.equal(manager.get("display-001")!.lastError, null);
    assert.equal(manager.get("display-001")!.status, "OFFLINE");
    assert.equal(lines.filter((l) => l.includes("display-001") && l.includes("DISPLAY_ERROR")).length, 0);
    assert.match(manager.get("display-002")!.lastError!, /AUTH_FAILED/);
  } finally {
    await cleanup();
  }
});

test("кадр на панели — тот самый QR: модули на своих местах", async () => {
  const { manager, mocks, cleanup } = await rig();
  try {
    await manager.pushImage("display-001", QR_A, "a").result;
    const expected = renderQrForDisplay(QR_A, 272, 792);
    const fb = { width: 272, height: 792, format: "1bpp" as const, data: mocks[0].framebuffer! };
    assert.equal(getPixel(fb, expected.offsetX, expected.offsetY), true, "угол поискового узора — чёрный");
    assert.equal(getPixel(fb, 0, 0), false);
  } finally {
    await cleanup();
  }
});
