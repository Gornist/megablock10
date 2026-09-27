import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AudioCatalogTrack, AudioChannel, AudioClip, DisplayAudio, DisplayGroup, DisplayItem } from "../api/types";
import { mockApi } from "../test/mockApi";
import { display } from "../test/displayFixtures";
import { LocationsScreen } from "./LocationsScreen";

vi.mock("../api/client");

const audio = (over: Partial<DisplayAudio> = {}): DisplayAudio => ({
  channelId: "ch-neon",
  channelName: "Радио «Неон»",
  source: "group",
  volume: 70,
  desiredVersion: 3,
  reportedVersion: 3,
  applied: true,
  playing: "radio-1.mp3",
  reportedVolume: 70,
  missing: [],
  tracksOnCard: 12,
  sdOk: true,
  overrideChannelId: null,
  overrideVolume: null,
  announce: null,
  ...over,
});

const groups: DisplayGroup[] = [
  { id: "g-bar", name: "Бар «Посмертие»", count: 2, audioChannelId: "ch-neon", audioVolume: 70 },
  { id: "g-sq", name: "Площадь", count: 1, audioChannelId: null, audioVolume: null },
];
const channels: AudioChannel[] = [{ id: "ch-neon", name: "Радио «Неон»", tracks: ["radio-1.mp3", "ad-neon.mp3"], shuffle: true, gapMs: 0, volume: 60 }];
const catalog: AudioCatalogTrack[] = [
  { name: "ad-neon.mp3", points: 2 },
  { name: "radio-1.mp3", points: 2 },
  { name: "rain.mp3", points: 1 },
];
const clips: AudioClip[] = [{ id: "a".repeat(64), name: "Игра началась", bytes: 40000, durationMs: 4800, preset: true, createdAt: 1 }];

const list: DisplayItem[] = [
  display({ id: "bar-1", name: "Бар, стойка", groupId: "g-bar", roles: ["display", "audio"], audio: audio() }),
  display({
    id: "bar-2",
    name: "Бар, туалет",
    groupId: "g-bar",
    roles: ["display", "audio"],
    audio: audio({ applied: false, missing: ["ad-neon.mp3"], playing: null }),
  }),
  display({
    id: "sq-1",
    name: "Площадь, фонтан",
    groupId: "g-sq",
    roles: ["display", "audio"],
    audio: audio({ channelId: null, channelName: null, playing: null }),
  }),
  display({ id: "qr-only", name: "Только QR", groupId: "g-sq" }),
];

function routes(extra: Record<string, unknown> = {}) {
  return mockApi({
    "GET /api/displays": list,
    "GET /api/display-groups": groups,
    "GET /api/audio/channels": channels,
    "GET /api/audio/catalog": catalog,
    "GET /api/audio/clips": clips,
    "GET /api/nodes": [],
    ...extra,
  });
}

beforeEach(() => vi.clearAllMocks());

describe("LocationsScreen — звук", () => {
  it("звук в локациях: что где играет, чего нет на карте; канал локации, фон и громкость точки — сразу на сервер", async () => {
    const calls = routes({ "PUT /api/display-groups/g-sq/audio": {}, "PUT /api/displays/bar-2/audio": {} });
    const { container } = render(<LocationsScreen />);
    await screen.findByText("Бар, стойка");
    // Точка без звука — в локации без звуковых полей.
    expect(container.querySelector('[data-point="qr-only"] .location-point-audio')).toBeNull();

    const bar2 = container.querySelector('[data-point="bar-2"]') as HTMLElement;
    expect(within(bar2).getByText("доходит…")).toBeTruthy();
    expect(within(bar2).getByText("нет на карте: 1")).toBeTruthy();
    expect(within(container.querySelector('[data-point="bar-1"]') as HTMLElement).getByText("♪ radio-1.mp3")).toBeTruthy();

    fireEvent.change(screen.getByLabelText("канал группы Площадь"), { target: { value: "ch-neon" } });
    await waitFor(() => expect(calls.some((c) => c.method === "PUT" && c.path === "/api/display-groups/g-sq/audio")).toBe(true));
    expect(calls.find((c) => c.path === "/api/display-groups/g-sq/audio")!.body).toEqual({ channelId: "ch-neon", volume: null });

    fireEvent.change(screen.getByLabelText("фон точки bar-2"), { target: { value: "" } });
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/bar-2/audio")?.body).toEqual({ channelId: "", volume: null }));

    const vol = screen.getByLabelText("громкость точки bar-1");
    fireEvent.change(vol, { target: { value: "35" } });
    fireEvent.blur(vol);
    await waitFor(() => expect(calls.find((c) => c.path === "/api/displays/bar-1/audio")?.body).toEqual({ channelId: null, volume: 35 }));
  });
});
