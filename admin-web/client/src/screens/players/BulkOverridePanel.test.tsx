import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { BulkPreview, PlayerListItem } from "../../api/types";
import { mockApi } from "../../test/mockApi";
import { BulkOverridePanel } from "./BulkOverridePanel";

vi.mock("../../api/client");

const player = (callsign: string): PlayerListItem => ({
  publicKeyB64: `k-${callsign}`, callsign, faction: "Neon", ramCapacity: 8, balance: 100, daemonCount: 0, shardsByTier: {},
  breaches: { success: 0, partial: 0, fail: 0 }, slotsClaimed: 0, lastSeenAt: 0, online: true, sessionResetAt: null, replacedBy: null, replaces: null,
});
const players = [player("Alice"), player("Bob")];
const preview: BulkPreview = { dryRun: true, target: "все игроки", count: 2, unchanged: 0, changes: [
  { publicKeyB64: "k-Alice", callsign: "Alice", oldValue: "100", newValue: "300" },
  { publicKeyB64: "k-Bob", callsign: "Bob", oldValue: "100", newValue: "300" },
] };

const setup = () => {
  const onDone = vi.fn();
  render(<BulkOverridePanel players={players} selectedKeys={[]} factionFilter="" onDone={onDone} onClose={() => {}} />);
  return onDone;
};
const fillForm = (value = "+200", reason = "премия") => {
  fireEvent.change(screen.getByPlaceholderText("+200"), { target: { value } });
  fireEvent.change(screen.getByPlaceholderText("премия за акт 2"), { target: { value: reason } });
};
const applyButton = () => screen.getByText(/^Применить/).closest("button") as HTMLButtonElement;

beforeEach(() => vi.clearAllMocks());

describe("BulkOverridePanel", () => {
  it("«Применить» недоступно без предпросмотра; предпросмотр уходит с dryRun и показывает «было → станет»", async () => {
    const calls = mockApi({ "POST /api/players/bulk-override": (b?: unknown) => ((b as { dryRun?: boolean }).dryRun ? preview : { dryRun: false, target: "все игроки", count: 2, unchanged: 0 }) });
    setup();
    fillForm();
    expect(applyButton().disabled).toBe(true);
    fireEvent.click(screen.getByText("Предпросмотр"));
    await screen.findByText(/изменится у 2/);
    expect(calls[0].body).toMatchObject({ all: true, field: "balance", newValue: "+200", mode: "add", reason: "премия", dryRun: true });
    expect(screen.getAllByText(/100 → 300/).length).toBe(2);
    expect(applyButton().disabled).toBe(false);
  });

  it("любое изменение формы после предпросмотра снова блокирует «Применить»", async () => {
    mockApi({ "POST /api/players/bulk-override": preview });
    setup();
    fillForm();
    fireEvent.click(screen.getByText("Предпросмотр"));
    await screen.findByText(/изменится у 2/);
    fireEvent.change(screen.getByPlaceholderText("+200"), { target: { value: "+500" } });
    expect(applyButton().disabled).toBe(true);
  });

  it("применение отправляет тот же запрос без dryRun, сообщает результат и зовёт onDone", async () => {
    const calls = mockApi({ "POST /api/players/bulk-override": (b?: unknown) => ((b as { dryRun?: boolean }).dryRun ? preview : { dryRun: false, target: "все игроки", count: 2, unchanged: 0 }) });
    const onDone = setup();
    fillForm();
    fireEvent.click(screen.getByText("Предпросмотр"));
    await screen.findByText(/изменится у 2/);
    fireEvent.click(applyButton());
    await waitFor(() => expect(onDone).toHaveBeenCalled());
    const applied = calls[calls.length - 1].body as Record<string, unknown>;
    expect(applied.dryRun).toBeUndefined();
    expect(applied).toMatchObject({ all: true, newValue: "+200", reason: "премия" });
    await screen.findByText(/Готово: все игроки, изменено 2 чел\./);
  });

  it("без основания предпросмотр недоступен", () => {
    mockApi({});
    setup();
    fireEvent.change(screen.getByPlaceholderText("+200"), { target: { value: "+200" } });
    expect((screen.getByText("Предпросмотр").closest("button") as HTMLButtonElement).disabled).toBe(true);
  });
});
