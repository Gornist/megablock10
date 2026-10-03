import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AudioChannel, DisplayAudio, DisplayItem } from "../../api/types";
import { mockApi } from "../../test/mockApi";
import { display } from "../../test/displayFixtures";
import { NodePoint, PointBadges } from "./NodePoint";

vi.mock("../../api/client");

const nodes = [{ id: "nasos-4", name: "Насосная-4" }];
const channels: AudioChannel[] = [{ id: "ch-neon", name: "Радио «Неон»", tracks: ["radio-1.mp3"], shuffle: true, gapMs: 0, volume: 60 }];
const audio = (over: Partial<DisplayAudio> = {}): DisplayAudio => ({
  channelId: "ch-neon",
  channelName: "Радио «Неон»",
  source: "group",
  volume: 60,
  desiredVersion: 1,
  reportedVersion: 1,
  applied: true,
  playing: "radio-1.mp3",
  reportedVolume: 60,
  missing: [],
  tracksOnCard: 4,
  sdOk: true,
  overrideChannelId: null,
  overrideVolume: null,
  announce: null,
  ...over,
});

const bound = display({
  id: "p-nasos",
  name: "Насосная, вход",
  nodeId: "nasos-4",
  groupId: "g-tech",
  batteryPct: 64,
  battery: "OK",
  batterySource: "gauge",
  batteryHoursLeft: 40,
  desiredVersion: null,
  displayedVersion: null,
  roles: ["display", "audio"],
  audio: audio({
    announce: {
      id: 9,
      clipId: "c".repeat(64),
      clipName: "Игра началась",
      phase: "PLAYING",
      uploadedPct: 100,
      durationMs: 4000,
      startedAt: 1,
      playingSince: 2,
      error: null,
    },
  }),
});
const free = display({ id: "p-free", name: "Свободная", nodeId: null });

beforeEach(() => vi.clearAllMocks());

describe("NodePoint", () => {
  it("точка узла: та же каноничная карточка, что на «Устройствах»/«Локациях» — полный набор команд, звук, отвязать", async () => {
    const calls = mockApi({
      "GET /api/displays": [bound, free],
      "GET /api/display-groups": [{ id: "g-tech", name: "Техэтаж", count: 1, audioChannelId: "ch-neon", audioVolume: null }],
      "GET /api/audio/channels": channels,
      "GET /api/nodes": nodes,
      "PUT /api/displays/p-nasos/audio": {},
      "PUT /api/displays/p-nasos/node": { ...bound, nodeId: null },
    });
    render(<NodePoint nodeId="nasos-4" />);
    const section = await screen.findByLabelText("точка узла");
    await within(section).findByText("p-nasos");
    await within(section).findByText("Насосная, вход");
    expect(section.querySelector(".display-card-status .badge")?.textContent).toBe("на связи");
    expect(within(section).getByText("64 % · ≈ 40 ч")).toBeTruthy();
    await within(section).findByText("узел «Насосная-4»");
    expect(within(section).getByText("На дисплей")).toBeTruthy();
    // Полный набор команд обслуживания доступен и здесь, не только на «Локациях».
    expect(within(section).getByText("Тест")).toBeTruthy();
    expect(within(section).getByText("Перезагрузить")).toBeTruthy();
    expect(within(section).getByText("Новый секрет")).toBeTruthy();
    // Пока идёт объявление, «что играет» — оно, а не трек фона; рядом — ход объявления.
    expect(within(section).getAllByText("📢 Игра началась")).toHaveLength(2);
    expect(within(section).getByText("играет")).toBeTruthy();

    fireEvent.change(within(section).getByLabelText("фон точки p-nasos"), { target: { value: "" } });
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/p-nasos/audio")?.body).toEqual({ channelId: "", volume: null }));
    fireEvent.click(within(section).getByText("Отвязать узел"));
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/p-nasos/node")?.body).toEqual({ nodeId: null }));
  });

  it("узел без точки: привязать одну из свободных", async () => {
    const calls = mockApi({
      "GET /api/displays": [bound, free],
      "GET /api/display-groups": [],
      "GET /api/audio/channels": [],
      "GET /api/nodes": nodes,
      "PUT /api/displays/p-free/node": { ...free, nodeId: "bar-7" },
    });
    render(<NodePoint nodeId="bar-7" />);
    await screen.findByText(/У узла нет точки/);
    const select = screen.getByLabelText("точка для узла");
    // В списке только непривязанные.
    expect([...select.querySelectorAll("option")].map((o) => o.textContent)).toEqual(["выберите точку…", "Свободная (p-free)"]);
    fireEvent.change(select, { target: { value: "p-free" } });
    fireEvent.click(screen.getByText("Привязать точку"));
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/p-free/node")?.body).toEqual({ nodeId: "bar-7" }));
  });

  it("значки в списке узлов: связь, батарея, звук; нет точки — прочерк", () => {
    const { container, rerender } = render(<PointBadges point={bound as DisplayItem} />);
    expect(container.textContent).toContain("на связи");
    expect(container.textContent).toContain("64%");
    expect(container.textContent).toContain("♪");
    rerender(<PointBadges point={undefined} />);
    expect(container.textContent).toBe("—");
  });
});
