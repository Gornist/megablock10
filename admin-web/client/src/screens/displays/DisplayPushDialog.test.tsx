import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DisplayItem, DisplayPreview, DisplayPushResponse, DisplayPushState } from "../../api/types";
import { mockApi } from "../../test/mockApi";
import { display } from "../../test/displayFixtures";
import { DisplayPushDialog } from "./DisplayPushDialog";

vi.mock("../../api/client");

const list: DisplayItem[] = [
  display({
    id: "display-017",
    name: "Точка 17",
    status: "ONLINE",
    displayedVersion: 5,
    desiredVersion: 5,
    batteryMv: 3900,
    battery: "OK",
    batteryPct: 72,
    batterySource: "gauge",
    batteryHoursLeft: 31,
  }),
  display({ id: "display-018", name: "Точка 18", status: "OFFLINE", lastSeenAt: null, displayedVersion: null, desiredVersion: null, desiredLabel: null }),
  display({
    id: "display-019",
    name: "Точка 19",
    status: "ERROR",
    lastError: "CONNECT: no TCP connection",
    displayedVersion: 2,
    desiredVersion: 3,
    batteryMv: 3650,
    battery: "CRITICAL",
    batteryPct: 6,
    batterySource: "gauge",
    batteryHoursLeft: 0.5,
  }),
];

const preview: DisplayPreview = {
  qr: "MB10:CONTAINER:v1:x",
  label: "контейнер «X»",
  png: "data:image/png;base64,AAA",
  width: 272,
  height: 792,
  qrVersion: 19,
  modules: 93,
  scale: 2,
};

beforeEach(() => vi.clearAllMocks());

describe("DisplayPushDialog", () => {
  it("предпросмотр, выбор нескольких дисплеев, отправка и итог по каждому", async () => {
    const pushed: DisplayPushResponse = {
      label: "контейнер «X»",
      results: [
        { displayId: "display-017", ok: true, version: 6, outcome: "QUEUED" },
        { displayId: "display-019", ok: true, version: 4, outcome: "QUEUED" },
      ],
    };
    let after = list;
    const calls = mockApi({
      "GET /api/displays": () => after,
      "POST /api/displays/preview": preview,
      "POST /api/displays/push": () => {
        after = [
          { ...list[0], displayedVersion: 6, desiredVersion: 6 },
          list[1],
          { ...list[2], desiredVersion: 4, lastError: "AUTH_FAILED: HELLO signature does not match" },
        ];
        return pushed;
      },
    });
    const onClose = vi.fn();
    render(<DisplayPushDialog source={{ type: "container", id: "nasos-4" }} title="Насосная-4" onClose={onClose} />);
    await screen.findByAltText("кадр для дисплея");
    expect(screen.getByText(/93 модулей, 2 px на модуль/)).toBeTruthy();
    expect(screen.getByText(/только вблизи/)).toBeTruthy();

    const boxes = await screen.findAllByRole("checkbox");
    expect(boxes).toHaveLength(3);
    fireEvent.click(boxes[0]);
    fireEvent.click(boxes[2]);
    fireEvent.click(screen.getByText("Отправить (2)"));
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/push")).toBeTruthy());
    expect(calls.find((c) => c.path === "/api/displays/push")?.body).toEqual({
      displayIds: ["display-017", "display-019"],
      source: { type: "container", id: "nasos-4" },
    });

    await screen.findAllByText("отображено (v6)", {}, { timeout: 4000 });
    await screen.findByText("AUTH_FAILED: HELLO signature does not match");
    fireEvent.click(screen.getByText("Готово"));
    expect(onClose).toHaveBeenCalled();
  });

  it("ход отправки: шкала этапов по данным сервера, макет показывает выбранный дисплей", async () => {
    const push = (phase: DisplayPushState["phase"], over: Partial<DisplayPushState> = {}): DisplayPushState => ({
      version: 6,
      label: "контейнер «X»",
      phase,
      attempt: 1,
      attempts: 3,
      startedAt: 0,
      updatedAt: 0,
      error: null,
      failedAt: null,
      retryAt: null,
      ...over,
    });
    let after = [list[0]];
    mockApi({
      "GET /api/displays": () => after,
      "POST /api/displays/preview": preview,
      "POST /api/displays/push": () => {
        after = [{ ...list[0], desiredVersion: 6, status: "UPDATING", activeVersion: 6, push: push("RECEIVED") }];
        return { label: "контейнер «X»", results: [{ displayId: "display-017", ok: true, version: 6, outcome: "QUEUED" }] };
      },
    });
    render(<DisplayPushDialog source={{ type: "container", id: "nasos-4" }} title="Насосная-4" onClose={() => {}} />);
    await screen.findByAltText("кадр для дисплея");
    // Единственный дисплей выбирается сам, когда придёт список.
    await waitFor(() => expect((screen.getByRole("checkbox") as HTMLInputElement).checked).toBe(true));
    fireEvent.click(screen.getByText("Отправить"));
    // Диалог — в портале, поэтому ищем по document. Кадр принят дисплеем — шаги «Подключение» и «Отправлено» пройдены, идёт «Загружено»; макет «обновляется».
    await screen.findAllByText("загружено — обновляется экран", {}, { timeout: 4000 });
    const steps = () => [...document.querySelectorAll(".push-step")].map((li) => li.className.replace("push-step push-step-", ""));
    expect(steps()).toEqual(["done", "done", "current", "todo"]);
    expect(document.querySelector(".display-mock-loaded")).toBeTruthy();
    expect(screen.getByAltText("кадр на дисплее")).toBeTruthy();

    after = [
      { ...list[0], desiredVersion: 6, displayedVersion: 6, push: push("FAILED", { attempt: 3, error: "TIMEOUT: no DISPLAYED", failedAt: "RECEIVED" }) },
    ];
    // Дисплей подтвердил версию (например, в HELLO следующей попытки) — показан, какой бы ни была последняя ошибка.
    await screen.findAllByText("отображено (v6)", {}, { timeout: 4000 });
    expect(steps()).toEqual(["done", "done", "done", "done"]);
    expect(document.querySelector(".display-mock-shown")).toBeTruthy();
  });

  it("QR не влезает в панель — ошибка предпросмотра, отправка недоступна", async () => {
    mockApi({
      "GET /api/displays": [list[0]],
      "POST /api/displays/preview": () => {
        throw new (class extends Error {
          status = 422;
        })("QR does not fit");
      },
    });
    render(<DisplayPushDialog source={{ type: "qr", qr: "MB10:X" }} title="x" onClose={() => {}} />);
    // Клиент подменён целиком, так что ошибка — не ApiError: показывается общий текст.
    await screen.findByText("не удалось построить предпросмотр");
    expect((screen.getByText("Отправить").closest("button") as HTMLButtonElement).disabled).toBe(true);
  });
});
