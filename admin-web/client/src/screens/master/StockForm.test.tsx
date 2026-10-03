import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { NetDoc, NetState, NodeStockView } from "../../api/types";
import { ApiError } from "../../api/client";
import { mockApi } from "../../test/mockApi";
import { StockForm } from "./StockForm";

vi.mock("../../api/client", async (orig) => ({ ...(await orig<typeof import("../../api/client")>()), api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } }));

const doc = (id: string, data: Record<string, unknown>): NetDoc => ({ type: "node", id, ver: 1, created: 1, updated: 1, data });
const state = (bridge: NetState["bridge"] = "connected"): NetState => ({
  configured: true,
  bridge,
  error: null,
  info: null,
  serverNow: 1,
  docs: bridge === "connected" ? { node: [doc("node_07", { title: "Склад" })] } : {},
});
const stock: NodeStockView = { node: "node_07", eddies: 100, items: [{ id: "it_aaaaaaaaaaaaaaaa", ver: 1, kind: "SHARD", title: "Лог клиники", tier: 2, effect: null, origin: "master:collector" }] };

beforeEach(() => vi.clearAllMocks());

describe("StockForm", () => {
  it("Моста нет — вместо формы подсказка, запрос запаса не шлётся", async () => {
    const calls = mockApi({ "GET /api/net/state": state("down") });
    render(<StockForm />);
    expect(await screen.findByText(/Мост недоступен/)).toBeTruthy();
    expect(calls.some((c) => c.path.includes("/items"))).toBe(false);
  });

  it("запас узла виден; шард из корзины и эдди уходят одним POST …/stock с rid и без payload — его собирает сервер", async () => {
    const calls = mockApi({
      "GET /api/net/state": state(),
      "GET /api/net/nodes/node_07/items": stock,
      "POST /api/net/nodes/node_07/stock": { node: "node_07", items: ["it_1"], eddies: 150 },
    });
    render(<StockForm />);
    expect(await screen.findByText("Лог клиники")).toBeTruthy();
    fireEvent.change(screen.getByPlaceholderText("Служебный лог клиники"), { target: { value: "Новый шард" } });
    fireEvent.change(screen.getByPlaceholderText("Полный текст, который увидит игрок"), { target: { value: "Текст" } });
    fireEvent.click(screen.getByText("в корзину"));
    fireEvent.change(screen.getByLabelText("сколько эдди добавить"), { target: { value: "50" } });
    fireEvent.click(screen.getByText("положить в узел"));
    await waitFor(() => expect(calls.find((c) => c.method === "POST")).toBeTruthy());
    const post = calls.find((c) => c.method === "POST")!;
    expect(post.path).toBe("/api/net/nodes/node_07/stock");
    const body = post.body as { rid: string; eddies: number; items: { type: string; title: string; tier: string }[] };
    expect(body.rid).toMatch(/^stock-/);
    expect(body.eddies).toBe(50);
    expect(body.items).toMatchObject([{ type: "SHARD", title: "Новый шард", tier: "BASE" }]);
    expect(await screen.findByText(/Запас эдди: 150/)).toBeTruthy();
  });

  it("повтор после ошибки шлёт тот же rid, а если корзину поменяли — новый (иначе Мост ответил бы rid_mismatch)", async () => {
    let fail = true;
    const calls = mockApi({
      "GET /api/net/state": state(),
      "GET /api/net/nodes/node_07/items": stock,
      "POST /api/net/nodes/node_07/stock": () => {
        if (fail) throw new ApiError(503, "Мост недоступен");
        return { node: "node_07", items: [], eddies: 110 };
      },
    });
    render(<StockForm />);
    await screen.findByText("Лог клиники");
    const eddies = screen.getByLabelText("сколько эдди добавить");
    fireEvent.change(eddies, { target: { value: "10" } });
    fireEvent.click(screen.getByText("положить в узел"));
    expect(await screen.findByText(/Мост недоступен/)).toBeTruthy();
    fail = false;
    fireEvent.click(screen.getByText("положить в узел"));
    await waitFor(() => expect(calls.filter((c) => c.method === "POST")).toHaveLength(2));
    const rids = calls.filter((c) => c.method === "POST").map((c) => (c.body as { rid: string }).rid);
    expect(rids[0]).toBe(rids[1]);

    fireEvent.change(screen.getByLabelText("сколько эдди добавить"), { target: { value: "20" } });
    fireEvent.click(screen.getByText("положить в узел"));
    await waitFor(() => expect(calls.filter((c) => c.method === "POST")).toHaveLength(3));
    expect((calls.filter((c) => c.method === "POST")[2].body as { rid: string }).rid).not.toBe(rids[0]);
  });

  it("разгрузка: отмеченный предмет и эдди уходят в POST …/unstock", async () => {
    const calls = mockApi({
      "GET /api/net/state": state(),
      "GET /api/net/nodes/node_07/items": stock,
      "POST /api/net/nodes/node_07/unstock": { node: "node_07", items: ["it_aaaaaaaaaaaaaaaa"], eddies: 80 },
    });
    render(<StockForm />);
    await screen.findByText("Лог клиники");
    fireEvent.click(screen.getByRole("checkbox", { name: /Лог клиники/ }));
    fireEvent.change(screen.getByLabelText("сколько эдди убрать"), { target: { value: "20" } });
    fireEvent.click(screen.getByText("убрать выбранное"));
    await waitFor(() => expect(calls.find((c) => c.method === "POST")).toMatchObject({ path: "/api/net/nodes/node_07/unstock", body: { items: ["it_aaaaaaaaaaaaaaaa"], eddies: 20 } }));
  });
});
