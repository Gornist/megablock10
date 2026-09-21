import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Attention } from "../../api/types";
import { mockApi } from "../../test/mockApi";
import { AttentionPanel } from "./AttentionPanel";

vi.mock("../../api/client");

const item = (id: string, title: string, severity: "crit" | "warn" | "info" = "warn") => ({ id, kind: "negative_balance" as const, severity, title, detail: `детали ${title}`, at: Date.now() });

const attention = (over: Partial<Attention> = {}): Attention => ({
  items: [item("a", "Отрицательный баланс", "crit"), item("b", "Пропал со связи")],
  snoozed: 0,
  counts: { crit: 1, warn: 1, info: 0 },
  ...over,
});

beforeEach(() => vi.clearAllMocks());

describe("AttentionPanel", () => {
  it("показывает тревоги со счётчиками по важности", async () => {
    mockApi({ "GET /api/attention": attention() });
    render(<AttentionPanel />);
    await screen.findByText("Отрицательный баланс");
    expect(screen.getByText("Пропал со связи")).toBeTruthy();
    expect(screen.getByText("срочно 1")).toBeTruthy();
    expect(screen.getByText("важно 1")).toBeTruthy();
  });

  it("«⏸ 30 мин» откладывает именно эту тревогу на 30 минут и перезагружает список", async () => {
    const calls = mockApi({ "GET /api/attention": attention(), "POST /api/attention/snooze": { ok: true } });
    render(<AttentionPanel />);
    await screen.findByText("Отрицательный баланс");
    fireEvent.click(screen.getAllByText("⏸ 30 мин")[0]);
    await waitFor(() => expect(calls.some((c) => c.method === "POST")).toBe(true));
    expect(calls.find((c) => c.method === "POST")).toMatchObject({ path: "/api/attention/snooze", body: { id: "a", minutes: 30 } });
    await waitFor(() => expect(calls.filter((c) => c.method === "GET").length).toBeGreaterThan(1));
  });

  it("«отложено N» переключает показ отложенных (?all=1)", async () => {
    const calls = mockApi({ "GET /api/attention": attention({ snoozed: 2 }), "GET /api/attention?all=1": attention({ snoozed: 2, items: [item("z", "Скрытая тревога")] }) });
    render(<AttentionPanel />);
    fireEvent.click(await screen.findByText("отложено 2"));
    await screen.findByText("Скрытая тревога");
    expect(calls.some((c) => c.path === "/api/attention?all=1")).toBe(true);
    expect(screen.getByText("скрыть отложенные")).toBeTruthy();
  });

  it("пусто — «всё спокойно»; переключатель звука запоминается", async () => {
    mockApi({ "GET /api/attention": attention({ items: [], counts: { crit: 0, warn: 0, info: 0 } }) });
    render(<AttentionPanel />);
    await screen.findByText("всё спокойно");
    fireEvent.click(screen.getByText("🔕 выкл"));
    expect(screen.getByText("🔔 вкл")).toBeTruthy();
    expect(localStorage.getItem("mb10.notifyCrit")).toBe("1");
  });
});
