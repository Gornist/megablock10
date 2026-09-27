import { describe, expect, it } from "vitest";
import { NAV, REDIRECTS, resolveSection } from "./nav";

describe("меню коллектора", () => {
  it("две группы: «Игра» и «Мир», без «Дисплеев» и «Звука»", () => {
    expect(NAV.map((g) => g.title)).toEqual(["Игра", "Мир"]);
    expect(NAV[0].items.map((i) => i.label)).toEqual(["Обзор", "События", "Игроки", "Фракции", "Экономика", "Переводы", "Объявления", "Журнал"]);
    expect(NAV[1].items.map((i) => i.label)).toEqual(["Узлы", "Локации", "Громкая связь", "Каналы звука", "Мастерская", "Реестр тиражей"]);
    const paths = NAV.flatMap((g) => g.items.map((i) => i.path));
    expect(paths).not.toContain("displays");
    expect(paths).not.toContain("sound");
    expect(new Set(paths).size).toBe(paths.length);
  });

  it("прежние адреса ведут на новые экраны, и те есть в меню", () => {
    expect(resolveSection("displays")).toBe("nodes");
    expect(resolveSection("sound")).toBe("announce");
    expect(resolveSection(undefined)).toBe("overview");
    expect(resolveSection("players")).toBe("players");
    const paths = new Set(NAV.flatMap((g) => g.items.map((i) => i.path)));
    for (const target of Object.values(REDIRECTS)) expect(paths.has(target)).toBe(true);
  });
});
