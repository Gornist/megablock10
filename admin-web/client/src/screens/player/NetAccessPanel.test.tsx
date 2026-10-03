import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { mockApi } from "../../test/mockApi";
import { NetAccessPanel } from "./NetAccessPanel";

vi.mock("../../api/client", async (orig) => ({ ...(await orig<typeof import("../../api/client")>()), api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } }));

beforeEach(() => vi.clearAllMocks());

describe("NetAccessPanel", () => {
  it("игрок без блокировки: «отметить нетраннером» шлёт PUT …/allowed {allowed: true}; ключ кодируется в адресе", async () => {
    const calls = mockApi({ "GET /api/net/runners/A%2Bb%3D": { blocked: false, allowed: false }, "PUT /api/net/runners/A%2Bb%3D/allowed": { blocked: false, allowed: true } });
    render(<NetAccessPanel publicKeyB64="A+b=" />);
    expect(await screen.findByText("не нетраннер")).toBeTruthy();
    fireEvent.click(screen.getByText("отметить нетраннером"));
    await waitFor(() => expect(calls.find((c) => c.method === "PUT")).toMatchObject({ path: "/api/net/runners/A%2Bb%3D/allowed", body: { allowed: true } }));
  });

  it("закрытие допуска требует основание: без текста кнопка подтверждения выключена", async () => {
    const calls = mockApi({ "GET /api/net/runners/KEY": { blocked: false, allowed: true }, "POST /api/net/runners/KEY/block": {} });
    render(<NetAccessPanel publicKeyB64="KEY" />);
    expect(await screen.findByText("нетраннер")).toBeTruthy();
    fireEvent.click(screen.getByText("закрыть допуск"));
    const confirm = screen.getByText("Закрыть допуск") as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("основание"), { target: { value: "драка" } });
    fireEvent.click(confirm);
    await waitFor(() => expect(calls.find((c) => c.method === "POST")).toMatchObject({ path: "/api/net/runners/KEY/block", body: { reason: "драка" } }));
  });
});
