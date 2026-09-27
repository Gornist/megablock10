import { describe, expect, it } from "vitest";
import { attentionTarget } from "./attentionTarget";

describe("куда ведёт тревога", () => {
  const go = (i: Parameters<typeof attentionTarget>[0]) => {
    window.location.hash = "";
    attentionTarget(i)?.();
    return window.location.hash;
  };
  it("игрок, узел, точка на узле — карточка узла; точка без узла — «Локации»", () => {
    expect(go({ subjectKey: "abc" })).toBe("#/players/abc");
    expect(go({ nodeId: "nasos-4" })).toBe("#/nodes/nasos-4");
    expect(go({ nodeId: "nasos-4", displayId: "p-1" })).toBe("#/nodes/nasos-4");
    expect(go({ displayId: "p-1" })).toBe("#/locations");
    expect(attentionTarget({})).toBeUndefined();
  });
});
