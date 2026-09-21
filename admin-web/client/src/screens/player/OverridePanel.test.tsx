import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError } from "../../api/client";
import { mockApi } from "../../test/mockApi";
import { OverridePanel } from "./OverridePanel";

// ApiError настоящий (нужен instanceof в useAsyncAction), api подменён.
vi.mock("../../api/client", async (orig) => ({ ...(await orig<typeof import("../../api/client")>()), api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } }));

beforeEach(() => vi.clearAllMocks());

const fill = (value: string, reason: string) => {
  fireEvent.change(screen.getByPlaceholderText(/на сколько|новое значение/), { target: { value } });
  fireEvent.change(screen.getByPlaceholderText("основание (обязательно)"), { target: { value: reason } });
};

describe("OverridePanel", () => {
  it("баланс: отправляет поле, значение, режим и основание; после успеха чистит форму и зовёт onDone", async () => {
    const calls = mockApi({ "POST /api/players/KEY/override": { id: "x" } });
    const onDone = vi.fn();
    render(<OverridePanel publicKeyB64="KEY" onDone={onDone} />);
    fireEvent.change(screen.getAllByRole("combobox")[1], { target: { value: "add" } });
    fill("+200", "премия");
    fireEvent.click(screen.getByText("Применить"));
    await waitFor(() => expect(onDone).toHaveBeenCalled());
    expect(calls[0]).toMatchObject({ method: "POST", path: "/api/players/KEY/override", body: { field: "balance", newValue: "+200", reason: "премия", mode: "add" } });
    expect((screen.getByPlaceholderText("основание (обязательно)") as HTMLInputElement).value).toBe("");
  });

  it("позывной и фракцию можно только задать: переключателя режима нет, уходит mode=set", async () => {
    const calls = mockApi({ "POST /api/players/KEY/override": {} });
    render(<OverridePanel publicKeyB64="KEY" onDone={() => {}} />);
    fireEvent.change(screen.getAllByRole("combobox")[0], { target: { value: "callsign" } });
    expect(screen.getAllByRole("combobox").length).toBe(1);
    fill("Neo", "смена позывного");
    fireEvent.click(screen.getByText("Применить"));
    await waitFor(() => expect(calls.length).toBe(1));
    expect(calls[0].body).toMatchObject({ field: "callsign", mode: "set", newValue: "Neo" });
  });

  it("ошибка сервера показывается, форма остаётся заполненной и onDone не зовётся", async () => {
    mockApi({ "POST /api/players/KEY/override": () => Promise.reject(new ApiError(400, "balance must be an integer")) });
    const onDone = vi.fn();
    render(<OverridePanel publicKeyB64="KEY" onDone={onDone} />);
    fill("abc", "тест");
    fireEvent.click(screen.getByText("Применить"));
    await screen.findByText("balance must be an integer");
    expect(onDone).not.toHaveBeenCalled();
    expect((screen.getByPlaceholderText("основание (обязательно)") as HTMLInputElement).value).toBe("тест");
  });
});
