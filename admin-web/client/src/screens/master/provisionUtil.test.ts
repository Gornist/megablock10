import { describe, expect, it } from "vitest";
import type { ProvisionItem } from "../../api/types";
import { provisionStatus, ramLabel } from "./provisionUtil";

const item = (over: Partial<ProvisionItem>): ProvisionItem => ({
  id: "i", callsign: "A", faction: "", balance: 0, ram: 0, createdAt: 0, createdBy: "M", replacesKey: null, replacesName: null, boundKey: null, boundName: null, boundAt: null, void: false, conflicts: 0, ...over,
});

describe("provisionStatus", () => {
  it("ждёт игрока → применён → перевыдан; конфликт важнее всего", () => {
    expect(provisionStatus(item({})).label).toBe("ждёт игрока");
    expect(provisionStatus(item({ boundKey: "k", boundName: "Alice" }))).toEqual({ label: "применён · Alice", tone: "ok" });
    expect(provisionStatus(item({ boundKey: "k", boundName: "Alice", void: true })).label).toMatch(/перевыдан/);
    expect(provisionStatus(item({ void: true })).label).toBe("погашен");
    expect(provisionStatus(item({ boundKey: "k", conflicts: 1 }))).toEqual({ label: "применён дважды!", tone: "danger" });
  });
  it("RAM 0 — по умолчанию", () => {
    expect(ramLabel(0)).toBe("по умолчанию");
    expect(ramLabel(8)).toBe("8");
  });
});
