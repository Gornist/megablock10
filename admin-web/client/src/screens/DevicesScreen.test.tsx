import { fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DisplayGroup, DisplayItem, NodeSummary } from "../api/types";
import { mockApi } from "../test/mockApi";
import { display } from "../test/displayFixtures";
import { DevicesScreen } from "./DevicesScreen";

vi.mock("../api/client");
vi.mock("../router", () => ({ navigate: vi.fn() }));

const groups: DisplayGroup[] = [{ id: "g-bar", name: "Бар «Посмертие»", count: 1, audioChannelId: null, audioVolume: null }];
const nodes = [{ id: "bar-7", name: "Бар «Посмертие»" }] as NodeSummary[];

const list: DisplayItem[] = [
  display({
    id: "display-017",
    name: "Точка 17",
    status: "ONLINE",
    groupId: "g-bar",
    nodeId: "bar-7",
    batteryMv: 3900,
    battery: "OK",
    batteryPct: 72,
    batterySource: "gauge",
    batteryHoursLeft: 31,
  }),
  display({ id: "display-018", name: "Точка 18", status: "OFFLINE", lastSeenAt: null, displayedVersion: null, desiredVersion: null, desiredLabel: null }),
  display({
    id: "display-019",
    name: "Точка 19 звуковая",
    status: "ERROR",
    lastError: "CONNECT: no TCP connection",
    roles: ["display", "audio"],
    audio: {
      channelId: null,
      channelName: null,
      source: "group",
      volume: 60,
      desiredVersion: 1,
      reportedVersion: 1,
      applied: true,
      playing: null,
      reportedVolume: 60,
      missing: [],
      tracksOnCard: 0,
      sdOk: true,
      overrideChannelId: null,
      overrideVolume: null,
      announce: null,
    },
  }),
];

function routes(over: Record<string, unknown> = {}) {
  return mockApi({
    "GET /api/displays": list,
    "GET /api/display-groups": groups,
    "GET /api/audio/channels": [],
    "GET /api/nodes": nodes,
    ...over,
  });
}

beforeEach(() => vi.clearAllMocks());

describe("DevicesScreen", () => {
  it("плоский список всех точек с локацией/узлом/звуком; фильтр по связи и поиск сужают список", async () => {
    routes();
    render(<DevicesScreen />);
    await screen.findByText("display-017");
    expect(screen.getByText("display-018")).toBeTruthy();
    expect(screen.getByText("display-019")).toBeTruthy();
    expect(screen.getByText("Устройства (3)")).toBeTruthy();

    const row017 = screen.getByText("display-017").closest("tr")!;
    expect(within(row017).getAllByText("Бар «Посмертие»")).toHaveLength(2); // локация + узел — одноимённые в фикстуре
    const row019 = screen.getByText("display-019").closest("tr")!;
    expect(within(row019).getByText("♪")).toBeTruthy();

    fireEvent.change(screen.getByLabelText("фильтр по связи"), { target: { value: "OFFLINE" } });
    expect(screen.queryByText("display-017")).toBeNull();
    expect(screen.getByText("display-018")).toBeTruthy();
    expect(screen.getByText("Устройства (1 из 3)")).toBeTruthy();

    fireEvent.change(screen.getByLabelText("фильтр по связи"), { target: { value: "" } });
    fireEvent.change(screen.getByPlaceholderText("поиск по имени/id"), { target: { value: "звуковая" } });
    expect(screen.queryByText("display-017")).toBeNull();
    expect(screen.getByText("display-019")).toBeTruthy();
  });

  it("только со звуком — сужает до звуковых точек", async () => {
    routes();
    render(<DevicesScreen />);
    await screen.findByText("display-017");
    fireEvent.click(screen.getByLabelText(/только со звуком/));
    expect(screen.queryByText("display-017")).toBeNull();
    expect(screen.queryByText("display-018")).toBeNull();
    expect(screen.getByText("display-019")).toBeTruthy();
  });

  it("клик по строке открывает каноничную карточку устройства с полным набором команд", async () => {
    routes({ "GET /api/displays/display-017/preview": { qr: "q", label: "l", png: "p", width: 792, height: 272, qrVersion: 1, modules: 1, scale: 3 } });
    render(<DevicesScreen deviceId="display-017" />);
    await screen.findByText("Устройство «Точка 17»");
    expect(screen.getByText("Изменить")).toBeTruthy();
    expect(screen.getByText("Новый секрет")).toBeTruthy();
    expect(screen.getByText("Удалить")).toBeTruthy();
    expect(screen.getByText("Тест")).toBeTruthy();
  });

  it("«+ устройство» открывает форму без привязки к локации", async () => {
    routes();
    render(<DevicesScreen />);
    fireEvent.click(await screen.findByText("+ устройство"));
    const groupSelect = screen.getByLabelText("группа") as HTMLSelectElement;
    expect(groupSelect.value).toBe("");
  });
});
