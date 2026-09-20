import { test } from "node:test";
import assert from "node:assert/strict";
import { setup, seedPlayer } from "./testHelpers.js";

test("nodes: взломы за час в списке и почасовая динамика в деталях", async () => {
  const { app, headers } = await setup();
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] }] },
  });
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "NEON" });
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "success" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s1" }),
        alice.change({ field: "counters.breach", newValue: JSON.stringify({ tier: "HARD", outcome: "fail" }), reason: "BREACH_ATTEMPT", sourceRef: "nasos-4:s2" }),
      ],
    },
  });

  const list = (await app.inject({ method: "GET", url: "/api/nodes", headers })).json();
  assert.equal(list[0].breachesLastHour, 2);

  const detail = (await app.inject({ method: "GET", url: "/api/nodes/nasos-4?hours=6", headers })).json();
  assert.equal(detail.timeline.length, 6);
  const last = detail.timeline.at(-1);
  assert.equal(last.success + last.fail, 2, "оба взлома в текущем часовом ведре");
  assert.equal(detail.timeline.slice(0, -1).every((b: { success: number; partial: number; fail: number }) => b.success + b.partial + b.fail === 0), true);
});
