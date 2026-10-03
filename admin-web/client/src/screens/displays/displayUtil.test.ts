import { describe, expect, it } from "vitest";
import { display } from "../../test/displayFixtures";
import type { DisplayPushState } from "../../api/types";
import { batteryText, byBatteryFirst, formatHoursLeft, isOnline, phaseText, pushProgress, pushStep, scaleWarning, screenState } from "./displayUtil";

const push = (over: Partial<DisplayPushState> = {}): DisplayPushState => ({
  version: 5,
  label: "x",
  phase: "QUEUED",
  attempt: 0,
  attempts: 3,
  startedAt: 0,
  updatedAt: 0,
  error: null,
  failedAt: null,
  retryAt: null,
  ...over,
});

describe("pushProgress", () => {
  const queued = { displayId: "d1", ok: true, version: 5, outcome: "QUEUED" as const };

  it("в очереди сервера — отправляется; подтверждена версия — показан", () => {
    expect(pushProgress(queued, display({ status: "UPDATING", activeVersion: 5 })).state).toBe("sending");
    expect(pushProgress(queued, display({ displayedVersion: 5 })).state).toBe("shown");
  });

  it("список ещё не обновился после отправки — не «ошибка», а отправляется", () => {
    expect(pushProgress(queued, display({ desiredVersion: 4, displayedVersion: 4 })).state).toBe("sending");
  });

  it("очередь пуста, версия не показана — ошибка с текстом сервера", () => {
    expect(pushProgress(queued, display({ status: "ERROR", lastError: "CONNECT: no TCP" }))).toEqual({ state: "failed", text: "CONNECT: no TCP" });
  });

  it("отказ сервера и замена новой отправкой", () => {
    expect(pushProgress({ displayId: "d1", ok: false, error: "display is disabled" }, display())).toEqual({ state: "failed", text: "display is disabled" });
    expect(pushProgress(queued, display({ desiredVersion: 6 })).state).toBe("superseded");
  });
});

describe("ход отправки с сервера", () => {
  const queued = { displayId: "d1", ok: true, version: 5, outcome: "QUEUED" as const };

  it("этап этой версии — по серверу: передаётся, загружено, ошибка с причиной", () => {
    expect(pushProgress(queued, display({ push: push({ phase: "SENDING", attempt: 1 }) }))).toMatchObject({ state: "sending", text: "передача кадра" });
    expect(pushProgress(queued, display({ push: push({ phase: "RECEIVED", attempt: 1 }) }))).toMatchObject({
      state: "loaded",
      text: "загружено — обновляется экран",
    });
    expect(pushProgress(queued, display({ push: push({ phase: "FAILED", attempt: 3, error: "CONNECT: no TCP" }) }))).toMatchObject({
      state: "failed",
      text: "CONNECT: no TCP",
    });
  });

  it("ход чужой (более новой) версии не выдаётся за ход этой", () => {
    expect(pushProgress(queued, display({ desiredVersion: 6, push: push({ version: 6, phase: "SENDING" }) })).state).toBe("superseded");
  });

  it("повтор: номер попытки, отсчёт и причина", () => {
    expect(phaseText(push({ phase: "CONNECTING", attempt: 2 }))).toBe("подключение (попытка 2 из 3)");
    expect(phaseText(push({ phase: "RETRY", attempt: 1, error: "TIMEOUT", retryAt: 10_500 }), 8_000)).toBe("повтор через 3 с: TIMEOUT");
  });

  it("шкала: сколько шагов пройдено", () => {
    expect(pushStep("CONNECTING")).toEqual({ done: 0, current: 0 });
    expect(pushStep("RECEIVED")).toEqual({ done: 2, current: 2 });
    expect(pushStep("DISPLAYED")).toEqual({ done: 4, current: -1 });
  });

  it("что на экране у дисплея: ничего не слали / идёт / показано / не дошло", () => {
    expect(screenState(display({ desiredVersion: null }))).toBeNull();
    expect(screenState(display({ push: push({ phase: "RECEIVED" }) }))).toBe("loaded");
    expect(screenState(display({ displayedVersion: 5 }))).toBe("shown");
    expect(screenState(display({ displayedVersion: 4 }))).toBe("failed");
  });
});

describe("scaleWarning", () => {
  it("1 и 2 px на модуль — предупреждение, 3+ — нет", () => {
    expect(scaleWarning(1)).toMatch(/не прочтёт/);
    expect(scaleWarning(2)).toMatch(/вблизи/);
    expect(scaleWarning(3)).toBeNull();
  });
});

describe("батарея", () => {
  it("остаток: минуты, часы, сутки", () => {
    expect(formatHoursLeft(0.4)).toBe("≈ 24 мин");
    expect(formatHoursLeft(31.4)).toBe("≈ 31 ч");
    expect(formatHoursLeft(108)).toBe("≈ 4,5 сут");
  });

  it("подпись: процент и остаток, зарядка, нет данных", () => {
    expect(batteryText({ batteryPct: 73, batteryHoursLeft: 31, batteryCharging: false })).toBe("73 % · ≈ 31 ч");
    expect(batteryText({ batteryPct: 40, batteryHoursLeft: null, batteryCharging: true })).toBe("40 % · заряжается");
    expect(batteryText({ batteryPct: 90, batteryHoursLeft: null, batteryCharging: false })).toBe("90 %");
    expect(batteryText({ batteryPct: null, batteryHoursLeft: null, batteryCharging: false })).toBe("—");
    expect(batteryText({ batteryPct: 70, batteryHoursLeft: null, batteryCharging: false, batterySource: "voltage" })).toBe("~70 %");
  });

  it("сначала севшие: критично → мало → норма → без данных, внутри — по остатку", () => {
    const list = [
      display({ id: "a", battery: null, batteryPct: null }),
      display({ id: "b", battery: "OK", batteryPct: 90, batteryHoursLeft: 60 }),
      display({ id: "c", battery: "LOW", batteryPct: 30, batteryHoursLeft: 9 }),
      display({ id: "d", battery: "CRITICAL", batteryPct: 8, batteryHoursLeft: 2 }),
      display({ id: "e", battery: "LOW", batteryPct: 22, batteryHoursLeft: 20 }),
    ];
    expect([...list].sort(byBatteryFirst).map((d) => d.id)).toEqual(["d", "c", "e", "b", "a"]);
  });
});

describe("isOnline", () => {
  it("на связи — и пока точка принимает кадр; нет связи, ошибка, выключена — нет", () => {
    const statuses = ["ONLINE", "UPDATING", "OFFLINE", "ERROR", "DISABLED"] as const;
    expect(statuses.map((status) => isOnline({ status }))).toEqual([true, true, false, false, false]);
  });
});
