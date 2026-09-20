import { test } from "node:test";
import assert from "node:assert/strict";
import { setup, seedPlayer } from "./testHelpers.js";

test("правка и рассылка мастера не делают игрока «на связи»", async () => {
  const { app, db, headers } = await setup();
  const a = await seedPlayer(app, { callsign: "Alice", faction: "X", balance: 10 });
  db.prepare(`UPDATE changes SET received_at = ?`).run(Date.now() - 60 * 60_000); // игрок давно молчит

  await app.inject({ method: "POST", url: "/api/announcements", headers, payload: { text: "Сбор", all: true } });
  await app.inject({ method: "POST", url: "/api/players/bulk-override", headers, payload: { field: "balance", newValue: "5", mode: "add", reason: "премия", all: true } });

  const list = await app.inject({ method: "GET", url: "/api/players", headers });
  assert.equal(list.json()[0].online, false);
  const overview = (await app.inject({ method: "GET", url: "/api/overview", headers })).json();
  assert.equal(overview.players.online, 0);
  assert.equal(a.publicKeyB64.length > 0, true);
});
