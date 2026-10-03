import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError } from "../api/client";
import type { NetDoc, NetRunnerFlagItem, NetSecView, NetState, WorldEventsConfig } from "../api/types";
import { mockApi } from "../test/mockApi";
import { NetScreen } from "./NetScreen";

// ApiError настоящий (нужен instanceof в useNetCall), api подменён.
vi.mock("../api/client", async (orig) => ({ ...(await orig<typeof import("../api/client")>()), api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } }));

const NOW = 1_800_000_000_000;
const doc = (type: string, id: string, data: Record<string, unknown>, ver = 1): NetDoc => ({ type, id, ver, created: NOW - 60_000, updated: NOW - 1000, data });

const state = (over: Partial<NetState> = {}): NetState => ({
  configured: true,
  bridge: "connected",
  error: null,
  info: { version: "1.0", worldPub: "pub", seq: 7 },
  serverNow: NOW,
  docs: {
    settings: [doc("settings", "global", { paused: false, venue_link: true })],
    node: [doc("node", "node_07", { title: "Склад", tier: "STANDARD", lockdown_until: NOW + 65_000, eddies: 300, owner_faction: "ARASAKA" })],
    node_cfg: [doc("node_cfg", "node_07", { paused: false, goal: { kind: "open", value: 120, deadline: NOW + 125_000, done: false } })],
    session: [doc("session", "s_1", { state: "active", terminal: "t03", node: "node_07", callsign: "Призрак", loot_eddies: 40, confirmed_at: NOW - 120_000, world: { trace: 72 } })],
    deck: [doc("deck", "s_1", { items: ["a", "b", "c"] })],
    terminal: [doc("terminal", "t03", { label: "Подвал", node: "node_07", silent: true, battery: 18, fps: 0, link: 40, beat_at: NOW - 95_000 })],
    master_req: [doc("master_req", "flatline:s_9", { kind: "flatline", node: "node_07", summary: "ФЛЭТЛАЙН: Волна", state: "pending", default: "approve", expires_at: NOW + 45_000 })],
    alert: [doc("alert", "al_17", { kind: "auditor_item_owner", msg: "it_02bb: владелец deck:s_9f2c, но сессия закрыта" }, 3)],
    net_query: [doc("net_query", "nq_1", { runner: "Призрак", state: "open", messages: [{ mid: "m1", from: "runner", text: "Где шард?", at: NOW - 30_000 }] })],
    template: [doc("template", "tpl_night", { title: "Ночь", settings: { await_flatline: 1 }, node_cfg: { trace_per_s: 3 } })],
  },
  ...over,
});

const flag = (over: Partial<NetRunnerFlagItem> = {}): NetRunnerFlagItem => ({
  runnerKey: "KEY=",
  callsign: "Волна",
  blocked: true,
  reason: "флэтлайн",
  session: "s_9",
  node: "node_09",
  terminal: "t04",
  detail: { cause: "black ICE", left_in_node: 3 },
  blockedAt: Date.now() - 60_000,
  sparedAt: null,
  sparedBy: null,
  bridgeSynced: false,
  knownPlayer: true,
  ...over,
});

const sec: NetSecView = { defaultFaction: "Security", recipients: [{ faction: "ARASAKA", count: 2 }], sync: { connected: true, inSync: true, docVer: 3, lastError: null } };
const venue: WorldEventsConfig = {
  kinds: [
    { kind: "flatline", label: "Флэтлайн", when: "нетраннер погиб", byTerminal: true, byNode: true },
    { kind: "alert.master", label: "Зов мастера", when: "новая тревога", byTerminal: false, byNode: false },
  ],
  actions: [{ kind: "flatline", clipId: null, clipName: null, volume: null, chime: true, enabled: false }],
  links: [{ displayId: "display-017", displayName: "Точка 17", netNode: null, terminal: null }],
};

function routes(over: Record<string, unknown> = {}) {
  return mockApi({
    "GET /api/net/state": state(),
    "GET /api/net/runners": [flag()],
    "GET /api/net/sec": sec,
    "GET /api/net/world-events/config": venue,
    "GET /api/audio/clips": [],
    ...over,
  });
}

beforeEach(() => vi.clearAllMocks());

describe("NetScreen", () => {
  it("Мост недоступен: вместо данных — плашка, узлов и тревог нет; настройки СБ и площадки остаются", async () => {
    routes({ "GET /api/net/state": state({ bridge: "down", error: "ECONNREFUSED", info: null, docs: {} }), "GET /api/net/runners": [] });
    render(<NetScreen />);
    expect((await screen.findAllByText("Мост недоступен")).length).toBeGreaterThan(0);
    expect(screen.queryByText(/Узлы Сети/)).toBeNull();
    expect(screen.queryByText(/Ждём мастера/)).toBeNull();
    expect(await screen.findByText("Служба безопасности (сигнал СБ)")).toBeTruthy();
    expect(await screen.findByText("Площадка: звуки событий Сети")).toBeTruthy();
  });

  it("не настроен: подсказка про BRIDGE_URL/BRIDGE_MASTER_KEY", async () => {
    routes({ "GET /api/net/state": state({ configured: false, bridge: "disabled", info: null, docs: {} }), "GET /api/net/runners": [] });
    render(<NetScreen />);
    expect(await screen.findByText("Мост не настроен")).toBeTruthy();
    expect(screen.getByText(/BRIDGE_MASTER_KEY/)).toBeTruthy();
  });

  it("на связи: узлы, нетраннеры, терминалы, запрос и заготовки показаны из снимка", async () => {
    routes();
    render(<NetScreen />);
    expect(await screen.findByText("Узлы Сети (1)")).toBeTruthy();
    expect(screen.getByText("локдаун 1:05")).toBeTruthy();
    expect(screen.getByText(/открыть узел 120 · 2:05/)).toBeTruthy();
    expect(screen.getByText("ARASAKA")).toBeTruthy();
    expect(screen.getByText("Нетраннеры в Сети (1)")).toBeTruthy();
    expect(screen.getByText(/72/)).toBeTruthy();
    expect(screen.getByText("молчат")).toBeTruthy();
    expect(screen.getByText("Где шард?")).toBeTruthy();
    expect(screen.getByText("Ночь")).toBeTruthy();
  });

  it("«Ждём мастера»: подтвердить и отклонить уходят в /api/net/decide с id запроса", async () => {
    const calls = routes({ "POST /api/net/decide": { doc: {} } });
    render(<NetScreen />);
    await screen.findByText("Ждём мастера (1)");
    expect(screen.getByText("0:45")).toBeTruthy();
    fireEvent.click(screen.getByText("отклонить"));
    await waitFor(() => expect(calls.find((c) => c.path === "/api/net/decide")).toBeTruthy());
    expect(calls.find((c) => c.path === "/api/net/decide")).toMatchObject({ method: "POST", body: { req: "flatline:s_9", decision: "deny" } });
  });

  it("пауза Сети требует подтверждения; без него запроса нет", async () => {
    const calls = routes({ "POST /api/net/pause": { doc: {} } });
    render(<NetScreen />);
    fireEvent.click(await screen.findByText("пауза Сети"));
    expect(calls.some((c) => c.path === "/api/net/pause")).toBe(false);
    fireEvent.click(screen.getByText("Пауза"));
    await waitFor(() => expect(calls.find((c) => c.path === "/api/net/pause")).toMatchObject({ body: { on: true } }));
  });

  it("флэтлайн: карточка с подробностями, «пощадить» ведёт на /spare по ключу; Мост ещё не знает — виден бейдж", async () => {
    const calls = routes({ "POST /api/net/runners/KEY%3D/spare": flag({ blocked: false }) });
    render(<NetScreen />);
    await screen.findByText("Флэтлайн: допуск закрыт (1)");
    expect(screen.getByText("Мост ещё не знает")).toBeTruthy();
    expect(screen.getByText(/black ICE/)).toBeTruthy();
    fireEvent.click(screen.getByText("пощадить"));
    fireEvent.click(screen.getByText("Пощадить"));
    await waitFor(() => expect(calls.some((c) => c.method === "POST" && c.path.endsWith("/spare"))).toBe(true));
  });

  it("тревога аудитора: «принять» снимает тревогу с её версией", async () => {
    const calls = routes({ "DELETE /api/net/alerts/al_17?ver=3": { ok: true } });
    render(<NetScreen />);
    await screen.findByText("Тревоги Сети (1)");
    fireEvent.click(screen.getByText("принять"));
    await waitFor(() => expect(calls.some((c) => c.method === "DELETE" && c.path === "/api/net/alerts/al_17?ver=3")).toBe(true));
  });

  it("ответ нетраннеру: после отказа Моста повтор шлёт тот же mid, после успеха — новый", async () => {
    let fail = true;
    const calls = routes({
      "POST /api/net/reply": () => {
        if (fail) throw new ApiError(503, "Мост недоступен");
        return { doc: {} };
      },
    });
    render(<NetScreen />);
    const input = await screen.findByLabelText("ответ Призрак");
    fireEvent.change(input, { target: { value: "Шард в узле 07" } });
    fireEvent.click(screen.getByText("ответить"));
    expect(await screen.findByText(/Мост недоступен/)).toBeTruthy();
    fail = false;
    fireEvent.click(screen.getByText("ответить"));
    await waitFor(() => expect(calls.filter((c) => c.path === "/api/net/reply")).toHaveLength(2));
    const [a, b] = calls.filter((c) => c.path === "/api/net/reply").map((c) => c.body as { mid: string; query: string; text: string });
    expect(a.mid).toBe(b.mid);
    expect(a).toMatchObject({ query: "nq_1", text: "Шард в узле 07" });
  });

  it("заготовка: узлы выбираются в окне, применение уходит с их списком", async () => {
    const calls = routes({ "POST /api/net/template/apply": { template: "tpl_night" } });
    render(<NetScreen />);
    fireEvent.click(await screen.findByText("применить…"));
    const apply = screen.getByText("Применить");
    expect((apply as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(within(document.body).getByLabelText(/node_07/));
    fireEvent.click(apply);
    await waitFor(() => expect(calls.find((c) => c.path === "/api/net/template/apply")).toMatchObject({ body: { template: "tpl_night", nodes: ["node_07"] } }));
  });

  it("владелец узла: сохраняется PUT на /api/net/nodes/:id/owner", async () => {
    const calls = routes({ "PUT /api/net/nodes/node_07/owner": { doc: {} } });
    render(<NetScreen />);
    fireEvent.click(await screen.findByText("владелец"));
    fireEvent.change(screen.getByLabelText("фракция-владелец"), { target: { value: "NEON" } });
    fireEvent.click(screen.getByText("Сохранить"));
    await waitFor(() => expect(calls.find((c) => c.method === "PUT")).toMatchObject({ path: "/api/net/nodes/node_07/owner", body: { faction: "NEON" } }));
  });
});
