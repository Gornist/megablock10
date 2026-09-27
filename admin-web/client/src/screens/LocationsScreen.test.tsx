import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AudioChannel, DisplayAudio, DisplayGroup, DisplayItem, DisplaySecretResponse, NodeSummary } from "../api/types";
import { mockApi } from "../test/mockApi";
import { display } from "../test/displayFixtures";
import { LocationsScreen } from "./LocationsScreen";

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

const groups: DisplayGroup[] = [
  { id: "g-bar", name: "Бар «Посмертие»", count: 2, audioChannelId: "ch-jazz", audioVolume: 50 },
  { id: "g-clinic", name: "Клиника", count: 0, audioChannelId: null, audioVolume: null },
];
const channels: AudioChannel[] = [{ id: "ch-jazz", name: "Бар: джаз", tracks: ["jazz.mp3"], shuffle: false, gapMs: 0, volume: 45 }];
const nodes = [
  { id: "nasos-4", name: "Насосная-4" },
  { id: "bar-7", name: "Бар «Посмертие»" },
] as NodeSummary[];

const audio = (over: Partial<DisplayAudio> = {}): DisplayAudio => ({
  channelId: "ch-jazz",
  channelName: "Бар: джаз",
  source: "group",
  volume: 50,
  desiredVersion: 2,
  reportedVersion: 2,
  applied: true,
  playing: "jazz.mp3",
  reportedVolume: 50,
  missing: [],
  tracksOnCard: 3,
  sdOk: true,
  overrideChannelId: null,
  overrideVolume: null,
  announce: null,
  ...over,
});

const inGroups: DisplayItem[] = [
  display({
    id: "display-021",
    name: "Стойка",
    groupId: "g-bar",
    nodeId: "bar-7",
    battery: "CRITICAL",
    batteryPct: 5,
    batterySource: "gauge",
    batteryHoursLeft: 1,
    roles: ["display", "audio"],
    audio: audio(),
  }),
  display({ id: "display-022", name: "Сцена", groupId: "g-bar", status: "OFFLINE" }),
  display({ id: "display-023", name: "Склад", groupId: null }),
];

function routes(over: Record<string, unknown> = {}) {
  return mockApi({
    "GET /api/displays": list,
    "GET /api/display-groups": [],
    "GET /api/audio/channels": channels,
    "GET /api/nodes": nodes,
    ...over,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
});

describe("LocationsScreen", () => {
  it("точки строками: статус и батарея, «сначала севшие»; «подробнее» — карточка с ошибкой и «Повторить»", async () => {
    routes();
    const { container } = render(<LocationsScreen />);
    await screen.findByText("display-017");
    const badges = () => [...container.querySelectorAll(".location-point-line .badge")].map((b) => b.textContent);
    // По умолчанию — «сначала севшие»: критичная батарея первой, без данных о заряде — последней.
    expect(badges()).toEqual(["ошибка", "на связи", "нет связи"]);
    expect(screen.getByText("6 % · ≈ 30 мин")).toBeTruthy();
    expect(screen.getByText("72 % · ≈ 31 ч")).toBeTruthy();
    const tiles = [...container.querySelectorAll(".stat-tile")].map((t) => t.textContent);
    expect(tiles).toContain("1батарея: критично");
    fireEvent.change(screen.getByLabelText("порядок"), { target: { value: "id" } });
    expect(badges()).toEqual(["на связи", "нет связи", "ошибка"]);
    // Карточка точки — по «подробнее»: там адрес, ошибка и «Повторить» у не дошедшей отправки.
    const row = container.querySelector('[data-point="display-019"]') as HTMLElement;
    fireEvent.click(row.querySelector(".display-group-toggle")!);
    expect(within(row).getByText(/CONNECT: no TCP connection/)).toBeTruthy();
    expect(within(row).getByText(/не дошло/)).toBeTruthy();
    expect(within(row).getAllByText("Повторить")).toHaveLength(1);
  });

  it("добавление: запрос с числами и узлом, занятый узел недоступен; секрет и строка настройки платы после создания", async () => {
    const created: DisplaySecretResponse = {
      display: list[1],
      secret: "ab".repeat(32),
      provisioning: { id: "display-018", secret: "ab".repeat(32), port: 47200, width: 792, height: 272 },
    };
    const calls = routes({ "GET /api/displays": [display({ id: "display-001", nodeId: "bar-7" })], "POST /api/displays": created });
    render(<LocationsScreen />);
    fireEvent.click(await screen.findByText("+ точка"));
    fireEvent.change(screen.getByPlaceholderText("display-017"), { target: { value: "display-018" } });
    fireEvent.change(screen.getByPlaceholderText("Точка 17, техэтаж"), { target: { value: "Точка 18" } });
    fireEvent.change(screen.getByPlaceholderText("10.10.0.217"), { target: { value: "10.10.0.218" } });
    const nodeSelect = await screen.findByLabelText("узел");
    await waitFor(() => expect(nodeSelect.querySelectorAll("option")).toHaveLength(3));
    expect((nodeSelect.querySelector('option[value="bar-7"]') as HTMLOptionElement).disabled).toBe(true);
    expect(nodeSelect.querySelector('option[value="bar-7"]')!.textContent).toContain("занят (display-001)");
    fireEvent.change(nodeSelect, { target: { value: "nasos-4" } });
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
      nodeId: "nasos-4",
    });
    // Строка настройки платы: со звуком — роль audio (точка появится в «Громкой связи»).
    const config = () => document.querySelector("pre.qr-raw")!.textContent!;
    expect(config()).not.toContain("audio");
    fireEvent.click(screen.getByLabelText(/со звуком/));
    expect(JSON.parse(config()).roles).toEqual(["display", "audio"]);
  });

  it("команда точке из карточки: ответ показывается мастеру", async () => {
    const calls = routes({ "GET /api/displays": [list[0]], "POST /api/displays/display-017/test": { ok: true, display: list[0] } });
    const { container } = render(<LocationsScreen />);
    await screen.findByText("display-017");
    fireEvent.click(container.querySelector('[data-point="display-017"] .display-group-toggle')!);
    fireEvent.click(await screen.findByText("Тест"));
    await screen.findByText("тестовый экран на 30 с");
    expect(calls.find((c) => c.path.endsWith("/test"))?.body).toEqual({ seconds: 30 });
  });
});

describe("LocationsScreen — локации", () => {
  it("локации сворачиваются (запоминается); в заголовке — на связи, севшие и фон; «Без локации» — в конце", async () => {
    routes({ "GET /api/displays": inGroups, "GET /api/display-groups": groups });
    const { container, unmount } = render(<LocationsScreen />);
    await waitFor(() => expect(container.querySelector(".display-group-title")).toBeTruthy());
    const titles = () => [...container.querySelectorAll(".display-group-title")].map((t) => t.textContent);
    expect(titles()).toEqual(["Бар «Посмертие»", "Клиника", "Без локации"]);
    const bar = container.querySelector('[data-group="g-bar"]')!;
    expect(bar.textContent).toContain("2 · на связи 1/2");
    expect(bar.textContent).toContain("батарея: 1 критично");
    await waitFor(() => expect((screen.getByLabelText("канал группы Бар «Посмертие»") as HTMLSelectElement).value).toBe("ch-jazz"));
    expect(container.querySelector('[data-group="g-clinic"]')!.textContent).toContain("в локации пока нет точек");
    // Точка, стоящая узлом, — со ссылкой на узел; звуковая — что играет.
    const stoika = container.querySelector('[data-point="display-021"]') as HTMLElement;
    await waitFor(() => expect(within(stoika).getByText("узел «Бар «Посмертие»»")).toBeTruthy());
    expect(within(stoika).getByText("♪ jazz.mp3")).toBeTruthy();

    fireEvent.click(bar.querySelector(".display-group-toggle")!);
    expect(screen.queryByText("display-021")).toBeNull();
    expect(bar.querySelector(".display-group-toggle")!.getAttribute("aria-expanded")).toBe("false");
    expect(bar.textContent).toContain("батарея: 1 критично");
    unmount();
    // Перезагрузили страницу — локация осталась свёрнутой.
    render(<LocationsScreen />);
    await screen.findByText("display-023");
    expect(screen.queryByText("display-021")).toBeNull();
  });

  it("фон локации и точки меняются сразу; локация точки — из её карточки", async () => {
    const calls = routes({
      "GET /api/displays": inGroups,
      "GET /api/display-groups": groups,
      "PUT /api/display-groups/g-clinic/audio": {},
      "PUT /api/displays/display-021/audio": {},
      "PUT /api/displays/display-023/group": { ...inGroups[2], groupId: "g-clinic" },
    });
    const { container } = render(<LocationsScreen />);
    await screen.findByText("display-023");
    await waitFor(() => expect(screen.getByLabelText("канал группы Клиника").querySelectorAll("option").length).toBe(2));
    fireEvent.change(screen.getByLabelText("канал группы Клиника"), { target: { value: "ch-jazz" } });
    await waitFor(() => expect(calls.find((c) => c.path === "/api/display-groups/g-clinic/audio")?.body).toEqual({ channelId: "ch-jazz", volume: null }));
    fireEvent.change(screen.getByLabelText("фон точки display-021"), { target: { value: "" } });
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/display-021/audio")?.body).toEqual({ channelId: "", volume: null }));

    fireEvent.click(container.querySelector('[data-point="display-023"] .display-group-toggle')!);
    fireEvent.change(await screen.findByLabelText("группа display-023"), { target: { value: "g-clinic" } });
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/display-023/group")?.body).toEqual({ groupId: "g-clinic" }));
  });
});
