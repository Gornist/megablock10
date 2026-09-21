import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ProvisionQr } from "../../api/types";
import { mockApi } from "../../test/mockApi";
import { ProvisionIssuer } from "./ProvisionIssuer";

vi.mock("../../api/client");

const result: ProvisionQr = {
  item: { id: "i1", callsign: "Alice", faction: "Neon", balance: 500, ram: 8, createdAt: 0, createdBy: "M", replacesKey: null, replacesName: null, boundKey: null, boundName: null, boundAt: null, void: false, conflicts: 0 },
  qr: "MB10:PROV:v1:i1",
  qrImage: "data:image/png;base64,AAA",
};
const config = { config: { url: "http://10.10.0.10:2517", urlSource: "env", secretSet: true }, items: [] };

function setup(props: Partial<React.ComponentProps<typeof ProvisionIssuer>> = {}) {
  const onResult = vi.fn();
  const onIssued = vi.fn();
  render(
    <ProvisionIssuer
      title="Новый персонаж"
      intro="вводный текст"
      initial={{ callsign: "", faction: "Neon", balance: "500", ram: "8" }}
      endpoint="/api/provisions"
      submitLabel="Выдать"
      submitAgainLabel="Выдать ещё"
      keepAfterIssue={{ callsign: "" }}
      onResult={onResult}
      onIssued={onIssued}
      {...props}
    />,
  );
  return { onResult, onIssued };
}

beforeEach(() => vi.clearAllMocks());

describe("ProvisionIssuer", () => {
  it("кнопка недоступна без позывного; запрос уходит с числовыми баланс и RAM", async () => {
    const calls = mockApi({ "GET /api/provisions": config, "POST /api/provisions": result });
    const { onResult } = setup();
    const button = screen.getByText("Выдать").closest("button") as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    fireEvent.change(screen.getByPlaceholderText("Alice"), { target: { value: "Alice" } });
    expect(button.disabled).toBe(false);
    fireEvent.click(button);
    await waitFor(() => expect(onResult).toHaveBeenCalledWith(result));
    expect(calls.find((c) => c.method === "POST")?.body).toEqual({ callsign: "Alice", faction: "Neon", balance: 500, ram: 8 });
  });

  it("после выдачи очищается только то, что сказано в keepAfterIssue; подпись кнопки меняется; onIssued получает значения", async () => {
    mockApi({ "GET /api/provisions": config, "POST /api/provisions": result });
    const { onIssued } = setup();
    fireEvent.change(screen.getByPlaceholderText("Alice"), { target: { value: "Alice" } });
    fireEvent.click(screen.getByText("Выдать"));
    await screen.findByText("Выдать ещё");
    expect((screen.getByPlaceholderText("Alice") as HTMLInputElement).value).toBe("");
    expect((screen.getByPlaceholderText("Neon") as HTMLInputElement).value).toBe("Neon");
    expect(onIssued).toHaveBeenCalledWith({ callsign: "Alice", faction: "Neon", balance: "500", ram: "8" });
  });

  it("показывает, что попадёт в QR: адрес сервера и код игры", async () => {
    mockApi({ "GET /api/provisions": config });
    setup();
    await screen.findByText("http://10.10.0.10:2517");
    expect(screen.getByText(/код игры/)).toBeTruthy();
  });
});
