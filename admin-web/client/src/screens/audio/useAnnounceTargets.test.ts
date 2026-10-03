import { act, renderHook } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { display } from "../../test/displayFixtures";
import { useAnnounceTargets } from "./useAnnounceTargets";

const points = [display({ id: "a", groupId: "g1" }), display({ id: "b", groupId: "g1" }), display({ id: "c", groupId: null })];

describe("useAnnounceTargets", () => {
  it("все → локации → точки: тело для сервера и число точек; повторный клик снимает отметку", () => {
    const { result } = renderHook(() => useAnnounceTargets(points));
    expect(result.current.targets).toEqual({ all: true });
    expect(result.current.targetCount).toBe(3);

    act(() => result.current.setMode("groups"));
    act(() => result.current.toggleGroup("g1"));
    expect(result.current.targets).toEqual({ groupIds: ["g1"] });
    expect(result.current.targetCount).toBe(2);

    act(() => result.current.setMode("points"));
    act(() => result.current.togglePoint("c"));
    act(() => result.current.togglePoint("a"));
    act(() => result.current.togglePoint("c"));
    expect(result.current.targets).toEqual({ displayIds: ["a"] });
    expect(result.current.targetCount).toBe(1);
  });
});
