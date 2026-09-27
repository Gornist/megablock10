import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { runConformance, type ConformanceOptions } from "./displays/conformance.js";
import { MockDisplay, type MockDisplayOptions } from "./displays/mockDisplay.js";

/** Короткие таймауты mock-дисплея и такие же ожидания набора — прогон за пару секунд. */
const FAST_MOCK = { displayDelayMs: 20, headerTimeoutMs: 200, payloadTimeoutMs: 300 };
const FAST_RUN: Partial<ConformanceOptions> = { headerTimeoutMs: 200, payloadTimeoutMs: 300, marginMs: 400, replyTimeoutMs: 500, displayTimeoutMs: 1000, rebootTimeoutMs: 2000, imagesInRow: 5 };

async function withMock(over: Partial<MockDisplayOptions>, run: (m: MockDisplay, key: Buffer) => Promise<void>) {
  const key = randomBytes(32);
  const mock = new MockDisplay({ deviceId: "display-017", key, width: 272, height: 792, ...FAST_MOCK, ...over });
  await mock.start();
  try {
    await run(mock, key);
  } finally {
    await mock.stop();
  }
}

const target = (m: MockDisplay, key: Buffer) => ({ host: "127.0.0.1", port: m.port, deviceId: "display-017", key, width: 272, height: 792 });

test("эталонный mock-дисплей проходит весь набор C1–C20", async () => {
  await withMock({}, async (mock, key) => {
    const results = await runConformance(target(mock, key), FAST_RUN);
    assert.deepEqual(
      results.filter((r) => !r.ok).map((r) => `${r.id}: ${r.detail}`),
      [],
    );
    assert.equal(results.length, 20);
  });
});

test("набор ловит ошибки реализации: чужой секрет — C1 и дальше не идёт", async () => {
  await withMock({}, async (mock) => {
    const results = await runConformance(target(mock, randomBytes(32)), FAST_RUN);
    assert.equal(results.length, 1);
    assert.equal(results[0].ok, false);
    assert.match(results[0].detail, /подпись HELLO/);
  });
});

test("набор ловит ошибки реализации: не тот размер панели, потерянный DISPLAYED, отказ панели", async () => {
  await withMock({ width: 800, height: 480 }, async (mock, key) => {
    const [c1] = await runConformance(target(mock, key), FAST_RUN, ["C1"]);
    assert.match(c1.detail, /панель 800×480/);
  });
  await withMock({ faults: { loseDisplayed: 1 } }, async (mock, key) => {
    const [c2] = await runConformance(target(mock, key), FAST_RUN, ["C2"]);
    assert.equal(c2.ok, false);
    assert.match(c2.detail, /DISPLAYED/);
  });
  await withMock({ faults: { failDisplay: 1 } }, async (mock, key) => {
    const [c2] = await runConformance(target(mock, key), FAST_RUN, ["C2"]);
    assert.match(c2.detail, /DISPLAY_FAILED/);
  });
});

test("набор ловит дисплей без таймаутов (C6, C18) — они часть контракта", async () => {
  await withMock({ headerTimeoutMs: 60_000, payloadTimeoutMs: 60_000 }, async (mock, key) => {
    const results = await runConformance(target(mock, key), FAST_RUN, ["C6", "C18"]);
    assert.deepEqual(
      results.map((r) => [r.id, r.ok]),
      [
        ["C6", false],
        ["C18", false],
      ],
    );
  });
});
