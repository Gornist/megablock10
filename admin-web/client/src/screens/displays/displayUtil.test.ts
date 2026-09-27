import { describe, expect, it } from "vitest";
import { display } from "../../test/displayFixtures";
import { pushProgress, scaleWarning } from "./displayUtil";

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

describe("scaleWarning", () => {
  it("1 и 2 px на модуль — предупреждение, 3+ — нет", () => {
    expect(scaleWarning(1)).toMatch(/не прочтёт/);
    expect(scaleWarning(2)).toMatch(/вблизи/);
    expect(scaleWarning(3)).toBeNull();
  });
});
