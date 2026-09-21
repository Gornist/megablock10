import { describe, expect, it } from "vitest";
import { EMPTY_FILTERS, eventsQuery, filtersFromPreset } from "./eventFilters";

describe("filtersFromPreset", () => {
  it("ссылки с карточек игрока, фракции и узла подставляют свой фильтр", () => {
    expect(filtersFromPreset({ type: "player", value: "KEY" })).toEqual({ ...EMPTY_FILTERS, player: "KEY" });
    expect(filtersFromPreset({ type: "faction", value: "Neon" })).toEqual({ ...EMPTY_FILTERS, faction: "Neon" });
    expect(filtersFromPreset({ type: "node", value: "nasos-4" })).toEqual({ ...EMPTY_FILTERS, node: "nasos-4" });
  });
  it("неизвестный тип и пустой адрес дают пустые фильтры", () => {
    expect(filtersFromPreset({ type: "weird", value: "x" })).toEqual(EMPTY_FILTERS);
    expect(filtersFromPreset({})).toEqual(EMPTY_FILTERS);
  });
});

describe("eventsQuery", () => {
  it("пустые фильтры не попадают в адрес", () => {
    expect(eventsQuery(EMPTY_FILTERS, 0, 50)).toBe("/api/events?page=0&pageSize=50");
  });
  it("период превращается в since от переданного «сейчас»", () => {
    const q = new URLSearchParams(eventsQuery({ ...EMPTY_FILTERS, period: "15", player: "K", kind: "money" }, 2, 50, 1_000_000).split("?")[1]);
    expect(q.get("since")).toBe(String(1_000_000 - 15 * 60_000));
    expect(q.get("player")).toBe("K");
    expect(q.get("kind")).toBe("money");
    expect(q.get("page")).toBe("2");
  });
});
