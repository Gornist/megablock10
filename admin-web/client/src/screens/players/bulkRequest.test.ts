import { describe, expect, it } from "vitest";
import { buildBulkRequest, defaultTarget, type BulkForm } from "./bulkRequest";

const base: BulkForm = { target: "all", selectedKeys: [], factionFilter: "", field: "balance", mode: "add", value: "+200", reason: "премия" };

describe("buildBulkRequest", () => {
  it("«всем»: селектор all, режим и основание как в форме", () => {
    const r = buildBulkRequest(base);
    expect(r.request).toEqual({ all: true, field: "balance", newValue: "+200", mode: "add", reason: "премия" });
    expect(r.ready).toBe(true);
  });

  it("фракция всегда «установить», даже если в форме выбрано «прибавить»", () => {
    const r = buildBulkRequest({ ...base, field: "faction", mode: "add", value: "NEON" });
    expect(r.mode).toBe("set");
    expect(r.request.mode).toBe("set");
  });

  it("не готово без значения, без основания и без адресатов", () => {
    expect(buildBulkRequest({ ...base, value: "  " }).ready).toBe(false);
    expect(buildBulkRequest({ ...base, reason: "" }).ready).toBe(false);
    expect(buildBulkRequest({ ...base, target: "selected", selectedKeys: [] }).ready).toBe(false);
    expect(buildBulkRequest({ ...base, target: "faction", factionFilter: "" }).ready).toBe(false);
    expect(buildBulkRequest({ ...base, target: "selected", selectedKeys: ["k"] }).request).toMatchObject({ keys: ["k"] });
    expect(buildBulkRequest({ ...base, target: "faction", factionFilter: "Neon" }).request).toMatchObject({ faction: "Neon" });
  });
});

describe("defaultTarget", () => {
  it("выбранные важнее фракции из фильтра, фракция важнее «всех»", () => {
    expect(defaultTarget(3, "Neon")).toBe("selected");
    expect(defaultTarget(0, "Neon")).toBe("faction");
    expect(defaultTarget(0, "")).toBe("all");
  });
});
