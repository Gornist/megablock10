import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AudioService } from "./audio/audioService.js";
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
// Дисплеи висят горизонтально: кадр 792×272 (прошивка для ПК по умолчанию такая же).
const W = 792;
const H = 272;

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
  return { fw, db, manager, lines, cleanup };
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

// ── Звук (docs/sound-nodes.md, З2): тот же сервер и та же прошивка для ПК с ролью audio; карта — каталог, динамик — журнал. ──

/** WAV PCM16 моно 16 кГц, ms миллисекунд тона. */
function wav(ms: number): Buffer {
  const n = 16 * ms;
  const b = Buffer.alloc(44 + n * 2);
  b.write("RIFF", 0, "ascii");
  b.writeUInt32LE(36 + n * 2, 4);
  b.write("WAVEfmt ", 8, "ascii");
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(16000, 24);
  b.writeUInt32LE(32000, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write("data", 36, "ascii");
  b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) b.writeInt16LE(Math.round(Math.sin(i / 7) * 9000), 44 + i * 2);
  return b;
}

async function audioRig(extra: string[] = []) {
  const r = await rig();
  // Карта точки: три трека (по размеру — ≈ 1 с каждый «MP3 128 кбит/с»).
  const tracks = join(r.fw.out, `${r.fw.id}-sd`, "tracks");
  mkdirSync(tracks, { recursive: true });
  for (const t of ["radio-1.mp3", "rain.mp3", "ad-arasaka.mp3"]) writeFileSync(join(tracks, t), Buffer.alloc(16_000, 1));
  const audio = new AudioService(r.db, r.manager, { replyTimeoutMs: 1500 });
  await r.fw.start(["--roles", "display,audio", ...extra]);
  return { ...r, audio };
}

async function until(what: string, cond: () => boolean, ms = 5000) {
  const deadline = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > deadline) assert.fail(`не дождались: ${what}`);
    await new Promise((res) => setTimeout(res, 20));
  }
}

test("звук: первый HELLO — роль audio; канал доходит до прошивки, каталог карты — по LIST; перезагрузка — фон тот же до сети", { skip }, async () => {
  const { fw, manager, audio, cleanup } = await audioRig();
  try {
    await manager.probe(fw.id);
    await manager.idle();
    assert.deepEqual(manager.get(fw.id)!.roles, ["display", "audio"]);
    await until("каталог карты", () => audio.catalog().length === 3);
    assert.deepEqual(audio.catalog().map((t) => t.name), ["ad-arasaka.mp3", "radio-1.mp3", "rain.mp3"]);

    const ch = audio.repo.createChannel({ name: "Радио", tracks: ["radio-1.mp3", "lost.mp3", "rain.mp3"], shuffle: false, gapMs: 0, volume: 55 });
    audio.repo.setDisplayAudio(fw.id, ch.id, null);
    audio.sync();
    await manager.idle();
    await fw.waitLog(/AUDIO track radio-1\.mp3 vol=55/, 3000);
    await manager.probe(fw.id);
    const view = manager.get(fw.id)!.audio!;
    assert.equal(view.applied, true);
    assert.deepEqual(view.missing, ["lost.mp3"]);
    assert.equal(view.sdOk, true);
    assert.equal(view.tracksOnCard, 3);
    // Трек доиграл (≈ 1 с) — следующий из канала, отсутствующий пропущен.
    await fw.waitLog(/AUDIO track rain\.mp3/, 4000);

    // Громкость — без перезапуска трека.
    const before = fw.log.length;
    audio.repo.setDisplayAudio(fw.id, ch.id, 30);
    audio.sync();
    await manager.idle();
    await fw.waitLog(/AUDIO volume 30/, 3000, before);

    // Перезагрузка: состояние из «flash», фон — сразу при загрузке, версия та же, сервер ничего не досылает.
    const version = manager.get(fw.id)!.audio!.desiredVersion;
    const rebootAt = fw.log.length;
    assert.equal((await manager.reboot(fw.id)).outcome, "DISPLAYED");
    await fw.waitLog(/listening on/, 5000, rebootAt);
    assert.match(fw.log.slice(rebootAt), new RegExp(`audio boot: state v${version}`));
    assert.match(fw.log.slice(rebootAt), /AUDIO track (radio-1|rain)\.mp3 vol=30/);
    await manager.probe(fw.id);
    assert.equal(manager.get(fw.id)!.audio!.reportedVersion, version);
    assert.equal(manager.get(fw.id)!.audio!.applied, true);
  } finally {
    audio.stop();
    await cleanup();
  }
});

test("звук: объявление — клип докачивается после обрыва, фон приглушается, «доиграло» — по HELLO; повтор клипа не грузится", { skip }, async () => {
  const { fw, manager, audio, cleanup } = await audioRig(["--drop-mid-clip", "1"]);
  try {
    await manager.probe(fw.id);
    await manager.idle();
    const ch = audio.repo.createChannel({ name: "Фон", tracks: ["radio-1.mp3"], shuffle: false, gapMs: 0, volume: 80 });
    audio.repo.setDisplayAudio(fw.id, ch.id, null);
    audio.sync();
    await manager.idle();
    await fw.waitLog(/AUDIO track radio-1\.mp3 vol=80/, 3000);

    const data = wav(1200); // 38 444 байта — три куска
    const id = createHash("sha256").update(data).digest("hex");
    audio.repo.saveClip(id, "Игра началась", data, 1200, true, null);
    const r = audio.announce(id, { displayIds: [fw.id] }, { volume: 90, chime: true, duck: 25 });
    assert.ok(r && r.results[0].ok);
    await fw.waitLog(/AUDIO clip [0-9a-f]{12} vol=90 chime=1 len=1200/, 5000);
    assert.match(fw.log, /FAULT drop-mid-clip/);
    assert.match(fw.log, /clip [0-9a-f]{12}: 16384 of 38444 bytes already here/, "докачка с места обрыва");
    assert.match(fw.log, /AUDIO volume 20/, "фон приглушён до 25 % от 80");
    await until("PLAYING", () => manager.get(fw.id)!.audio!.announce?.phase === "PLAYING");
    // Длительность 1,2 с + сигнал 0,9 с; сервер сам опрашивает после неё.
    await until("DONE", () => manager.get(fw.id)!.audio!.announce?.phase === "DONE", 8000);
    assert.match(fw.log, /AUDIO clip finished/);
    assert.match(fw.log, /AUDIO volume 80/, "фон вернулся");

    const again = fw.log.length;
    audio.announce(id, { displayIds: [fw.id] }, { chime: false });
    await fw.waitLog(/AUDIO clip [0-9a-f]{12} vol=80 chime=0/, 4000, again);
    assert.doesNotMatch(fw.log.slice(again), /already here/, "клип уже на карте — CLIP_BEGIN ответил полной длиной, кусков нет");
    audio.stopAnnouncement({ displayIds: [fw.id] });
    await fw.waitLog(/AUDIO clip stopped/, 3000, again);
  } finally {
    audio.stop();
    await cleanup();
  }
});

test("звук: карты нет — точка докладывает sd:false, фон молчит; дисплей без роли audio звуковых команд не получает", { skip }, async () => {
  const { fw, manager, audio, cleanup } = await audioRig(["--no-sd"]);
  try {
    await manager.probe(fw.id);
    await manager.idle();
    const ch = audio.repo.createChannel({ name: "Фон", tracks: ["radio-1.mp3"], shuffle: false, gapMs: 0, volume: 50 });
    audio.repo.setDisplayAudio(fw.id, ch.id, null);
    audio.sync();
    await manager.idle();
    await manager.probe(fw.id);
    const view = manager.get(fw.id)!.audio!;
    assert.equal(view.sdOk, false);
    assert.equal(view.applied, true, "состояние принято и сохранено — заиграет, когда вставят карту");
    assert.deepEqual(view.missing, ["radio-1.mp3"]);
    assert.doesNotMatch(fw.log, /AUDIO track/);
  } finally {
    audio.stop();
    await cleanup();
  }

  const plain = await rig();
  const plainAudio = new AudioService(plain.db, plain.manager);
  try {
    await plain.fw.start();
    await plain.manager.probe(plain.fw.id);
    assert.deepEqual(plain.manager.get(plain.fw.id)!.roles, ["display"]);
    assert.equal(plain.manager.get(plain.fw.id)!.audio, null);
    assert.equal(plainAudio.sync(), 0);
  } finally {
    plainAudio.stop();
    await plain.cleanup();
  }
});
