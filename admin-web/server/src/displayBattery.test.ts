import { test } from "node:test";
import assert from "node:assert/strict";
import { computeAttention } from "./lib/attention.js";
import { estimateBattery, percentFromMilliVolts, type BatterySample, type BatteryThresholds } from "./displays/battery.js";
import { DisplayManager } from "./displays/manager.js";
import { MockDisplay } from "./displays/mockDisplay.js";
import { newDisplaySecret, secretKey } from "./displays/repository.js";
import { testDb } from "./testUtil.js";

const T: BatteryThresholds = { lowMv: 3500, criticalMv: 3300, lowPct: 25, criticalPct: 10, lowHours: 12, criticalHours: 4, windowMs: 2 * 3_600_000 };
const HOUR = 3_600_000;
const NOW = 100 * HOUR;

/** История: заряд падает на ratePerHour за час, точка каждые 5 минут за последние hours часов. */
function discharge(fromPct: number, ratePerHour: number, hours: number, gauge = true): BatterySample[] {
  const out: BatterySample[] = [];
  for (let m = hours * 60; m > 0; m -= 5) {
    const pct = fromPct - (ratePerHour * m) / 60; // m минут назад: при разряде (rate < 0) было больше
    out.push({ at: NOW - m * 60_000, mv: null, pct: gauge ? Math.round(pct) : null });
  }
  return out;
}

test("процент по напряжению — та же кривая Li-ion, что в прошивке (battery.cpp)", () => {
  assert.equal(percentFromMilliVolts(4300), 100);
  assert.equal(percentFromMilliVolts(4200), 100);
  assert.equal(percentFromMilliVolts(3840), 50);
  assert.equal(percentFromMilliVolts(3830), 48);
  assert.equal(percentFromMilliVolts(3270), 0);
  assert.equal(percentFromMilliVolts(3000), 0);
});

test("остаток — по наклону истории за 2 ч: 60 % при разряде 10 %/ч — ≈ 6 ч, это МАЛО (< 12 ч)", () => {
  const e = estimateBattery({ mv: 3870, pct: 60, rate: null, at: NOW }, discharge(60, -10, 2), T, NOW);
  assert.equal(e.percent, 60);
  assert.equal(e.source, "gauge");
  assert.ok(e.hoursLeft !== null && Math.abs(e.hoursLeft - 6) < 0.3, String(e.hoursLeft));
  assert.equal(e.level, "LOW");
  assert.equal(e.charging, false);
});

test("пороги: мало процентов или мало часов — КРИТИЧНО; полная и медленно разряжается — НОРМА", () => {
  assert.equal(estimateBattery({ mv: null, pct: 8, rate: null, at: NOW }, [], T, NOW).level, "CRITICAL");
  assert.equal(estimateBattery({ mv: null, pct: 20, rate: null, at: NOW }, [], T, NOW).level, "LOW");
  assert.equal(estimateBattery({ mv: null, pct: 40, rate: null, at: NOW }, discharge(40, -15, 2), T, NOW).level, "CRITICAL", "≈ 2,7 ч");
  const slow = estimateBattery({ mv: null, pct: 90, rate: null, at: NOW }, discharge(90, -1.2, 2), T, NOW);
  assert.equal(slow.level, "OK");
  assert.ok(slow.hoursLeft! > 60, String(slow.hoursLeft));
});

test("истории мало (точка только включилась) — остаток по скорости топливомера; нет ни того, ни другого — остатка нет", () => {
  assert.equal(estimateBattery({ mv: null, pct: 60, rate: -5, at: NOW }, [], T, NOW).hoursLeft, 12);
  assert.equal(estimateBattery({ mv: null, pct: 60, rate: null, at: NOW }, [], T, NOW).hoursLeft, null);
  // Три точки за 10 минут — ещё не тренд (нужно ≥ четверти окна).
  assert.equal(estimateBattery({ mv: null, pct: 60, rate: null, at: NOW }, discharge(60, -10, 1 / 6), T, NOW).hoursLeft, null);
});

test("заряжается — остаток не выдумывается, признак зарядки", () => {
  const e = estimateBattery({ mv: null, pct: 50, rate: null, at: NOW }, discharge(50, 20, 2), T, NOW);
  assert.equal(e.charging, true);
  assert.equal(e.hoursLeft, null);
});

test("без топливомера: процент по напряжению со сглаживанием — провал под громкой музыкой не роняет заряд", () => {
  const history: BatterySample[] = [
    { at: NOW - 10 * 60_000, mv: 3950, pct: null },
    { at: NOW - 5 * 60_000, mv: 3955, pct: null },
  ];
  const dip = estimateBattery({ mv: 3700, pct: null, rate: null, at: NOW }, history, T, NOW);
  assert.equal(dip.source, "voltage");
  assert.equal(dip.percent, 70, "медиана 3700/3950/3955 — 3950 мВ");
  assert.equal(estimateBattery({ mv: 3250, pct: null, rate: null, at: NOW }, [], T, NOW).level, "CRITICAL");
});

test("HELLO с топливомером → в DisplayItem процент, источник и остаток; история пишется; «Требует внимания» — при критичном заряде", async () => {
  const db = testDb();
  const manager = new DisplayManager(db, { probeIntervalMs: 0, retryDelaysMs: [], batterySampleMs: 0, log: () => {} });
  const secret = newDisplaySecret();
  const mock = new MockDisplay({ deviceId: "display-001", key: secretKey({ secret }), width: 792, height: 272, status: { batteryMv: 3980, batteryPct: 75, batteryRate: -2.5 } });
  const port = await mock.start();
  try {
    manager.repo.create("display-001", { name: "Бар", ip: "127.0.0.1", port, width: 792, height: 272, enabled: true }, secret);
    assert.equal(manager.get("display-001")!.batteryPct, null, "до первого HELLO заряда нет");
    await manager.probe("display-001");
    const item = manager.get("display-001")!;
    assert.equal(item.batteryPct, 75);
    assert.equal(item.batterySource, "gauge");
    assert.equal(item.batteryHoursLeft, 30, "75 % / 2,5 %/ч");
    assert.equal(item.battery, "OK");
    assert.equal(manager.repo.batterySamples("display-001", 0).length, 1);
    assert.deepEqual(computeAttention(db).filter((a) => a.kind === "display_battery"), []);

    mock.options.status = { batteryMv: 3650, batteryPct: 7, batteryRate: -3 };
    await manager.probe("display-001");
    assert.equal(manager.get("display-001")!.battery, "CRITICAL");
    const alarms = computeAttention(db).filter((a) => a.kind === "display_battery");
    assert.equal(alarms.length, 1);
    assert.equal(alarms[0].severity, "crit");
    assert.match(alarms[0].detail, /display-001 \(Бар\): 7 %, ≈ 2 ч/);
    // Ссылка тревоги: точка без узла — на «Локации» (displayId), стоящая узлом — на узел (nodeId).
    assert.equal(alarms[0].displayId, "display-001");
    assert.equal(alarms[0].nodeId, undefined);
    manager.repo.setNode("display-001", "bar-7");
    assert.equal(computeAttention(db).find((a) => a.kind === "display_battery")!.nodeId, "bar-7");

    // Топливомер вынули — процент по напряжению, а не прежние 7 %.
    mock.options.status = { batteryMv: 4200 };
    await manager.probe("display-001");
    const noGauge = manager.get("display-001")!;
    assert.equal(noGauge.batterySource, "voltage");
    assert.ok(noGauge.batteryPct! > 7, String(noGauge.batteryPct));
  } finally {
    manager.stop();
    await mock.stop();
  }
});

test("удаление точки чистит её историю заряда", () => {
  const db = testDb();
  const manager = new DisplayManager(db, { probeIntervalMs: 0, log: () => {} });
  manager.repo.create("display-x", { name: "x", ip: "127.0.0.1", port: 1, width: 792, height: 272, enabled: true }, newDisplaySecret());
  manager.repo.recordBattery("display-x", 1000, 3900, 60, 0, HOUR);
  manager.repo.recordBattery("display-x", 2000, 3890, 59, 5000, HOUR);
  assert.equal(manager.repo.batterySamples("display-x", 0).length, 1, "чаще интервала — не пишется");
  manager.repo.delete("display-x");
  assert.equal(manager.repo.batterySamples("display-x", 0).length, 0);
  manager.stop();
});
