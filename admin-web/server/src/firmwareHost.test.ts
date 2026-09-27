import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runConformance } from "./displays/conformance.js";
import { DisplayManager } from "./displays/manager.js";
import { FirmwareHostProcess, freePort } from "./displays/firmwareHostProcess.js";
import { renderQrForDisplay } from "./displays/renderer.js";
import { testDb } from "./testUtil.js";

/**
 * Настоящий сервер мастера ↔ прошивка дисплея, собранная для ПК (firmware/display, docs/firmware-plan.md Ф2). Запускается,
 * когда задан FIRMWARE_HOST_BIN (путь к display_host; CI firmware.yml его собирает), иначе пропускается:
 *
 *   cmake -S firmware/display -B firmware/display/build && cmake --build firmware/display/build
 *   FIRMWARE_HOST_BIN=$PWD/firmware/display/build/display_host npx tsx --test src/firmwareHost.test.ts
 */
const BIN = process.env.FIRMWARE_HOST_BIN;
const skip = !BIN || !existsSync(BIN) ? "FIRMWARE_HOST_BIN не задан — прошивка для ПК не собрана" : false;

const QR_A = "MB10:RAM:v1:ram-aaaa:1";
const QR_B = "MB10:RAM:v1:ram-bbbb:2";
const W = 272;
const H = 792;

async function rig() {
  const out = mkdtempSync(join(tmpdir(), "mb10-fw-"));
  const secret = randomBytes(32).toString("hex");
  const fw = new FirmwareHostProcess({
    bin: BIN!,
    id: "display-017",
    secret,
    port: await freePort(),
    out,
    args: ["--delay", "40", "--header-timeout", "400", "--payload-timeout", "600"],
  });
  const db = testDb();
  const lines: string[] = [];
  const manager = new DisplayManager(db, {
    connectTimeoutMs: 500,
    helloTimeoutMs: 500,
    receivedTimeoutMs: 800,
    displayedTimeoutMs: 1500,
    commandTimeoutMs: 800,
    retryDelaysMs: [100, 300],
    probeIntervalMs: 0,
    onlineWindowMs: 60_000,
    log: (l) => lines.push(l),
  });
  manager.repo.create(fw.id, { name: "ПК", ip: "127.0.0.1", port: fw.port, width: W, height: H, enabled: true }, secret);
  const cleanup = async () => {
    manager.stop();
    await fw.stop();
    rmSync(out, { recursive: true, force: true });
  };
  return { fw, manager, lines, cleanup };
}

test("прошивка для ПК проходит набор совместимости C1–C20", { skip }, async () => {
  const { fw, cleanup } = await rig();
  try {
    await fw.start();
    const results = await runConformance(
      { host: "127.0.0.1", port: fw.port, deviceId: fw.id, key: Buffer.from(fw.secret, "hex"), width: W, height: H },
      { headerTimeoutMs: 400, payloadTimeoutMs: 600, marginMs: 600, replyTimeoutMs: 1000, displayTimeoutMs: 2000, rebootTimeoutMs: 5000, imagesInRow: 5 },
    );
    assert.deepEqual(
      results.filter((r) => !r.ok).map((r) => `${r.id}: ${r.detail}`),
      [],
      fw.log,
    );
    assert.equal(results.length, 20);
  } finally {
    await cleanup();
  }
});

test("сервер мастера → прошивка: на «панели» ровно кадр рендера, после перезапуска кадр и версия из «flash»", { skip }, async () => {
  const { fw, manager, cleanup } = await rig();
  try {
    await fw.start();
    assert.deepEqual(await manager.pushImage(fw.id, QR_A, "a").result, { outcome: "DISPLAYED", version: 1 });
    const expected = renderQrForDisplay(QR_A, W, H).data;
    assert.ok(fw.panelFrame(W, H).equals(expected), "PNG панели не совпал с кадром рендера");
    const item = manager.get(fw.id)!;
    assert.equal(item.fwVersion, "host-0.1.0");
    assert.equal(item.displayedVersion, 1);

    // Выключили и включили: кадр и версия восстанавливаются до сети.
    await fw.stop();
    await fw.start();
    assert.match(fw.log, /boot: restoring frame 1/);
    await manager.probe(fw.id);
    assert.equal(manager.get(fw.id)!.displayedVersion, 1);
    assert.equal(manager.get(fw.id)!.status, "ONLINE");
  } finally {
    await cleanup();
  }
});

test("питание пропало посреди записи кадра: после включения — старый целый кадр, сервер сам досылает новый", { skip }, async () => {
  const { fw, manager, cleanup } = await rig();
  try {
    await fw.start(["--crash-on-save", "2"]);
    assert.equal((await manager.pushImage(fw.id, QR_A, "a").result).outcome, "DISPLAYED");
    const second = await manager.pushImage(fw.id, QR_B, "b").result;
    assert.equal(second.outcome, "FAILED");
    assert.ok(fw.exited, "прошивка должна была упасть посреди записи");
    assert.match(fw.log, /FAULT crash-on-save/);

    await fw.start();
    assert.match(fw.log, /boot: restoring frame 1/);
    assert.ok(fw.panelFrame(W, H).equals(renderQrForDisplay(QR_A, W, H).data), "после сбоя на панели должен быть прежний целый кадр");
    // Плановый опрос видит, что на экране старое, и досылает то, что должно быть.
    await manager.probeAll();
    await manager.idle();
    assert.equal(manager.get(fw.id)!.displayedVersion, 2);
    assert.ok(fw.panelFrame(W, H).equals(renderQrForDisplay(QR_B, W, H).data));
  } finally {
    await cleanup();
  }
});

test("зависание в обновлении панели: сторож перезапускает, кадр уже во flash — сервер засчитывает показ по HELLO", { skip }, async () => {
  const { fw, manager, lines, cleanup } = await rig();
  try {
    await fw.start(["--hang-on-image", "1", "--watchdog-ms", "600"]);
    const r = await manager.pushImage(fw.id, QR_A, "a").result;
    assert.deepEqual(r, { outcome: "DISPLAYED", version: 1 });
    assert.match(fw.log, /FAULT hang-on-image/);
    assert.match(fw.log, /WATCHDOG RESET/);
    assert.match(fw.log, /boot: restoring frame 1/);
    assert.ok(lines.some((l) => l.includes("confirmed by HELLO")), lines.join("\n"));
    assert.ok(fw.panelFrame(W, H).equals(renderQrForDisplay(QR_A, W, H).data));
  } finally {
    await cleanup();
  }
});

test("панель не обновилась один раз — сервер повторяет и добивается показа", { skip }, async () => {
  const { fw, manager, cleanup } = await rig();
  try {
    await fw.start(["--fail-display", "1"]);
    assert.equal((await manager.pushImage(fw.id, QR_A, "a").result).outcome, "DISPLAYED");
    assert.match(fw.log, /FAULT fail-display/);
  } finally {
    await cleanup();
  }
});

test("дисплей «завис» (SIGSTOP): отправка FAILED по таймаутам; ожил — опрос досылает", { skip }, async () => {
  const { fw, manager, cleanup } = await rig();
  try {
    await fw.start();
    fw.proc.kill("SIGSTOP");
    const r = await manager.pushImage(fw.id, QR_A, "a").result;
    assert.equal(r.outcome, "FAILED");
    assert.match(r.error!, /TIMEOUT/);
    fw.proc.kill("SIGCONT");
    await new Promise((res) => setTimeout(res, 100));
    await manager.probeAll();
    await manager.idle();
    assert.equal(manager.get(fw.id)!.displayedVersion, 1);
    assert.equal(manager.get(fw.id)!.lastError, null);
  } finally {
    await cleanup();
  }
});

test("команды из дашборда: тест, подсветка, перезагрузка — и снова на связи с той же версией", { skip }, async () => {
  const { fw, manager, cleanup } = await rig();
  try {
    await fw.start();
    await manager.pushImage(fw.id, QR_A, "a").result;
    assert.equal((await manager.test(fw.id, 1)).outcome, "DISPLAYED");
    assert.equal((await manager.backlight(fw.id, 2, 1)).outcome, "DISPLAYED");
    await fw.waitLog(/backlight off by timer/, 3000);
    const before = fw.log.length;
    assert.equal((await manager.reboot(fw.id)).outcome, "DISPLAYED");
    await fw.waitLog(/listening on/, 5000, before);
    await manager.probe(fw.id);
    assert.equal(manager.get(fw.id)!.displayedVersion, 1);
    assert.equal(manager.get(fw.id)!.status, "ONLINE");
  } finally {
    await cleanup();
  }
});
