import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DisplayGroup, DisplayItem, DisplayPreview, DisplayPushResponse, DisplayPushState, DisplaySecretResponse } from "../api/types";
import { mockApi } from "../test/mockApi";
import { DisplaysScreen } from "./DisplaysScreen";
import { DisplayPushDialog } from "./displays/DisplayPushDialog";
import { display } from "../test/displayFixtures";

vi.mock("../api/client");

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

describe("DisplaysScreen", () => {
  it("список: статусы, что на экране, ошибка, «Повторить» у не дошедшей отправки", async () => {
    mockApi({ "GET /api/displays": list });
    const { container } = render(<DisplaysScreen />);
    await screen.findByText("display-017");
    const badges = [...container.querySelectorAll(".panel .panel .badge")].map((b) => b.textContent);
    // По умолчанию — «сначала севшие»: критичная батарея первой, без данных о заряде — последней.
    expect(badges).toEqual(["ошибка", "на связи", "нет связи"]);
    expect(screen.getByText("6 % · ≈ 30 мин")).toBeTruthy();
    expect(screen.getByText("72 % · ≈ 31 ч")).toBeTruthy();
    expect(container.querySelector(".battery-none .battery-text")?.textContent).toBe("—");
    expect(container.querySelector(".battery-critical")).toBeTruthy();
    const tiles = [...container.querySelectorAll(".stat-tile")].map((t) => t.textContent);
    expect(tiles).toContain("1батарея: критично");
    fireEvent.change(screen.getByLabelText("порядок"), { target: { value: "id" } });
    expect([...container.querySelectorAll(".panel .panel .badge")].map((b) => b.textContent)).toEqual(["на связи", "нет связи", "ошибка"]);
    expect(screen.getByText(/CONNECT: no TCP connection/)).toBeTruthy();
    expect(screen.getByText(/не дошло/)).toBeTruthy();
    expect(screen.getAllByText("Повторить")).toHaveLength(1);
  });

  it("добавление: запрос с числами, секрет показывается после создания", async () => {
    const created: DisplaySecretResponse = {
      display: list[1],
      secret: "ab".repeat(32),
      provisioning: { id: "display-018", secret: "ab".repeat(32), port: 47200, width: 792, height: 272 },
    };
    const calls = mockApi({ "GET /api/displays": [], "POST /api/displays": created });
    render(<DisplaysScreen />);
    fireEvent.click(await screen.findByText("+ дисплей"));
    fireEvent.change(screen.getByPlaceholderText("display-017"), { target: { value: "display-018" } });
    fireEvent.change(screen.getByPlaceholderText("Точка 17, техэтаж"), { target: { value: "Точка 18" } });
    fireEvent.change(screen.getByPlaceholderText("10.10.0.217"), { target: { value: "10.10.0.218" } });
    fireEvent.click(screen.getByText("Добавить"));
    await screen.findByText("ab".repeat(32));
    expect(calls.find((c) => c.method === "POST")?.body).toEqual({
      id: "display-018",
      name: "Точка 18",
      ip: "10.10.0.218",
      port: 47200,
      width: 792,
      height: 272,
      enabled: true,
      groupId: null,
    });
  });

  it("команда дисплею: ответ показывается мастеру", async () => {
    const calls = mockApi({ "GET /api/displays": [list[0]], "POST /api/displays/display-017/test": { ok: true, display: list[0] } });
    render(<DisplaysScreen />);
    fireEvent.click(await screen.findByText("Тест"));
    await screen.findByText("тестовый экран на 30 с");
    expect(calls.find((c) => c.path.endsWith("/test"))?.body).toEqual({ seconds: 30 });
  });
});

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

describe("DisplaysScreen — группы", () => {
  const groups: DisplayGroup[] = [
    { id: "g-bar", name: "Бар «Посмертие»", count: 2 },
    { id: "g-clinic", name: "Клиника", count: 0 },
  ];
  const inGroups: DisplayItem[] = [
    display({ id: "display-021", name: "Стойка", groupId: "g-bar", battery: "CRITICAL", batteryPct: 5, batterySource: "gauge", batteryHoursLeft: 1 }),
    display({ id: "display-022", name: "Сцена", groupId: "g-bar", status: "OFFLINE" }),
    display({ id: "display-023", name: "Склад", groupId: null }),
  ];

  beforeEach(() => localStorage.clear());

  it("секции по группам сворачиваются (запоминается), в заголовке — сколько на связи и севшие; «Без группы» — в конце", async () => {
    mockApi({ "GET /api/displays": inGroups, "GET /api/display-groups": groups });
    const { container, unmount } = render(<DisplaysScreen />);
    await waitFor(() => expect(container.querySelector(".display-group-title")).toBeTruthy());
    const titles = () => [...container.querySelectorAll(".display-group-title")].map((t) => t.textContent);
    expect(titles()).toEqual(["Бар «Посмертие»", "Клиника", "Без группы"]);
    const bar = container.querySelector('[data-group="g-bar"]')!;
    expect(bar.textContent).toContain("2 · на связи 1/2");
    expect(bar.textContent).toContain("батарея: 1 критично");
    expect(container.querySelector('[data-group="g-clinic"]')!.textContent).toContain("в группе пока нет дисплеев");
    expect(screen.getByText("display-021")).toBeTruthy();

    fireEvent.click(bar.querySelector(".display-group-toggle")!);
    expect(screen.queryByText("display-021")).toBeNull();
    expect(bar.querySelector(".display-group-toggle")!.getAttribute("aria-expanded")).toBe("false");
    expect(bar.textContent).toContain("батарея: 1 критично");
    unmount();
    // Перезагрузили страницу — группа осталась свёрнутой.
    render(<DisplaysScreen />);
    await screen.findByText("display-023");
    expect(screen.queryByText("display-021")).toBeNull();
  });

  it("карточка: статус и батарея — справа в шапке; группа меняется прямо из карточки", async () => {
    const calls = mockApi({
      "GET /api/displays": inGroups,
      "GET /api/display-groups": groups,
      "PUT /api/displays/display-023/group": { ...inGroups[2], groupId: "g-clinic" },
    });
    const { container } = render(<DisplaysScreen />);
    await screen.findByText("display-023");
    const header = screen.getByText("display-021").closest(".panel-header")!;
    expect(header.querySelector(".display-card-status .badge")?.textContent).toBe("на связи");
    expect(header.querySelector(".display-card-status .battery-text")?.textContent).toBe("5 % · ≈ 1 ч");
    fireEvent.change(screen.getByLabelText("группа display-023"), { target: { value: "g-clinic" } });
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/display-023/group")?.body).toEqual({ groupId: "g-clinic" }));
    expect(container.querySelector('[data-group="none"]')).toBeTruthy();
  });
});
