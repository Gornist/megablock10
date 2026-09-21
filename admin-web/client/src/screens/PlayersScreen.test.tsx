import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { PlayerListItem } from "../api/types";
import { mockApi } from "../test/mockApi";
import { PlayersScreen } from "./PlayersScreen";

vi.mock("../api/client");

const player = (callsign: string, over: Partial<PlayerListItem> = {}): PlayerListItem => ({
  publicKeyB64: `key-${callsign}`,
  callsign,
  faction: "Neon",
  ramCapacity: 8,
  balance: 100,
  daemonCount: 0,
  shardsByTier: {},
  breaches: { success: 0, partial: 0, fail: 0 },
  slotsClaimed: 0,
  lastSeenAt: Date.now(),
  online: true,
  sessionResetAt: null,
  replacedBy: null,
  replaces: null,
  ...over,
});

const players = [player("Alice"), player("Bob", { faction: "Rats" }), player("Old", { sessionResetAt: 1 }), player("Gone", { replacedBy: "key-Alice" })];

beforeEach(() => {
  vi.clearAllMocks();
  mockApi({ "GET /api/players": players, "GET /api/watch": [] });
});

describe("PlayersScreen", () => {
  it("сброшенные и заменённые сессии скрыты, «выбывшие N» их показывает с пометками", async () => {
    render(<PlayersScreen />);
    await screen.findByText("Alice");
    expect(screen.queryByText("Old")).toBeNull();
    expect(screen.queryByText("Gone")).toBeNull();

    fireEvent.click(screen.getByText("выбывшие 2"));
    expect(screen.getByText("Old")).toBeTruthy();
    expect(screen.getByText("Gone")).toBeTruthy();
    expect(screen.getByText("сброс")).toBeTruthy();
    expect(screen.getByText("заменён")).toBeTruthy();
  });

  it("поиск по позывному и фильтр фракции сужают список", async () => {
    render(<PlayersScreen />);
    await screen.findByText("Alice");
    fireEvent.change(screen.getByPlaceholderText("поиск по позывному"), { target: { value: "bo" } });
    expect(screen.queryByText("Alice")).toBeNull();
    expect(screen.getByText("Bob")).toBeTruthy();
    expect(screen.getByText("Игроки (1/4)")).toBeTruthy();
  });
});
