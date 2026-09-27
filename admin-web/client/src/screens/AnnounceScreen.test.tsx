import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AnnounceResponse, AudioCatalogTrack, AudioChannel, AudioClip, DisplayAudio, DisplayGroup, DisplayItem } from "../api/types";
import { mockApi } from "../test/mockApi";
import { display } from "../test/displayFixtures";
import { AnnounceScreen } from "./AnnounceScreen";

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
    ...extra,
  });
}

beforeEach(() => vi.clearAllMocks());

describe("AnnounceScreen", () => {
  it("звуковых точек нет — объяснение, как они появляются", async () => {
    mockApi({
      "GET /api/displays": [display()],
      "GET /api/display-groups": [],
      "GET /api/audio/channels": [],
      "GET /api/audio/catalog": [],
      "GET /api/audio/clips": [],
    });
    render(<AnnounceScreen />);
    expect(await screen.findByText("Как появляется звуковая точка")).toBeTruthy();
  });

  it("громкая связь: клип → группа → объявить; ход по точкам", async () => {
    const response: AnnounceResponse = {
      id: 77,
      clipName: "Игра началась",
      results: [
        { displayId: "bar-1", ok: true },
        { displayId: "bar-2", ok: true },
      ],
    };
    const calls = routes({ "POST /api/audio/announce": response });
    render(<AnnounceScreen />);
    const announce = await screen.findByRole("button", { name: /объявить/ });
    expect((announce as HTMLButtonElement).disabled, "без клипа — нельзя").toBe(true);
    fireEvent.click(screen.getByText("Игра началась"));
    fireEvent.click(screen.getByRole("radio", { name: "группы" }));
    fireEvent.click(screen.getByRole("checkbox", { name: /Бар «Посмертие»/ }));
    const button = screen.getByRole("button", { name: /объявить «Игра началась» → 2/ });
    fireEvent.click(button);
    await waitFor(() => expect(calls.some((c) => c.path === "/api/audio/announce")).toBe(true));
    expect(calls.find((c) => c.path === "/api/audio/announce")!.body).toEqual({
      clipId: clips[0].id,
      targets: { groupIds: ["g-bar"] },
      volume: 80,
      chime: true,
    });
  });

  it("ход объявления: загрузка с процентом, играет, не дошло; кнопка «прервать»", async () => {
    const at = { id: 5, clipId: clips[0].id, clipName: "Игра началась", uploadedPct: 40, durationMs: 4800, startedAt: 1, playingSince: null, error: null };
    const running = list.map((d) =>
      d.id === "bar-1"
        ? { ...d, audio: audio({ announce: { ...at, phase: "UPLOADING" as const } }) }
        : d.id === "bar-2"
          ? { ...d, audio: audio({ announce: { ...at, phase: "PLAYING" as const } }) }
          : d.id === "sq-1"
            ? { ...d, audio: audio({ announce: { ...at, phase: "FAILED" as const, error: "CONNECT: no TCP connection" } }) }
            : d,
    );
    const calls = routes({ "GET /api/displays": running, "POST /api/audio/announce/stop": { ok: true } });
    render(<AnnounceScreen />);
    const progress = await screen.findByLabelText("ход объявления");
    expect(within(progress).getByText("загрузка 40 %")).toBeTruthy();
    expect(within(progress).getByText("играет")).toBeTruthy();
    expect(within(progress).queryByText(/не дошло/), "чужое завершённое объявление не показывается").toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "прервать" }));
    await waitFor(() => expect(calls.find((c) => c.path === "/api/audio/announce/stop")?.body).toEqual({ targets: { all: true } }));
  });
});
