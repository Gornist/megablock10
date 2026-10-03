import { render, renderHook, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { mockApi } from "../../test/mockApi";
import { display } from "../../test/displayFixtures";
import { DeviceStats } from "./DeviceStats";
import { takenNodesOf, useDeviceData } from "./useDeviceData";

vi.mock("../../api/client");

describe("useDeviceData", () => {
  it("грузит точки, локации, каналы и узлы и считает производные", async () => {
    const calls = mockApi({
      "GET /api/displays": [display({ id: "p1", nodeId: "n1" }), display({ id: "p2" })],
      "GET /api/display-groups": [{ id: "g1", name: "Бар" }],
      "GET /api/audio/channels": [],
      "GET /api/nodes": [
        { id: "n1", name: "Насосная", extra: 1 },
        { id: "n2", name: "Склад" },
      ],
    });
    const { result } = renderHook(() => useDeviceData());
    await waitFor(() => expect(result.current.displays).toHaveLength(2));
    await waitFor(() => expect(result.current.namedNodes).toEqual([
      { id: "n1", name: "Насосная" },
      { id: "n2", name: "Склад" },
    ]));
    expect(result.current.nodeName.get("n2")).toBe("Склад");
    expect(result.current.takenNodes).toEqual(new Map([["n1", "p1"]]));
    await waitFor(() => expect(result.current.groups).toHaveLength(1));

    const before = calls.length;
    result.current.reloadAll();
    await waitFor(() => expect(calls.slice(before).map((c) => c.path).sort()).toEqual(["/api/display-groups", "/api/displays"]));
  });

  it("узел без точки не занят", () => {
    expect(takenNodesOf([display({ id: "p1" }), display({ id: "p2", nodeId: "n5" })])).toEqual(new Map([["n5", "p2"]]));
  });
});

describe("DeviceStats", () => {
  it("ряд батареи — только если хоть одна точка мерит заряд", () => {
    const { rerender } = render(<DeviceStats displays={[display({ status: "ONLINE" }), display({ id: "d2", status: "ERROR" })]} />);
    expect(screen.queryByText("батарея в норме")).toBeNull();
    rerender(<DeviceStats displays={[display({ battery: "LOW", batteryPct: 15 })]} />);
    expect(screen.getByText("батарея: мало")).toBeTruthy();
  });
});
