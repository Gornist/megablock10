import { test } from "node:test";
import assert from "node:assert/strict";
import { parseClientVersions } from "./lib/presence.js";
import { seedPlayer, setup, type App, type Device } from "./testHelpers.js";

const beat = (app: App, d: Device, presence: unknown) =>
  app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: d.publicKeyB64, presence } });
const list = async (app: App, headers: Record<string, string>) =>
  (await app.inject({ method: "GET", url: "/api/players", headers })).json() as { callsign: string; appVersion?: string; wireVersions?: Record<string, number> }[];

test("parseClientVersions: принимает только разумные значения", () => {
  assert.deepEqual(parseClientVersions("0.1-mvp", { chat: 1, call: 2, claim: 1 }), { appVersion: "0.1-mvp", wireVersions: { chat: 1, call: 2, claim: 1 } });
  assert.deepEqual(parseClientVersions("<script>", { chat: "1", "x y": 2, big: 5000, ok: 3 }), { appVersion: null, wireVersions: { ok: 3 } });
  assert.equal(parseClientVersions(42, [1, 2]), null);
  assert.equal(parseClientVersions(undefined, undefined), null);
});

test("версии из heartbeat видны в списке игроков; незнакомому ключу не сохраняются", async () => {
  const { app, headers } = await setup();
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "X" });
  await beat(app, alice, { appVersion: "0.1-mvp", wireVersions: { chat: 1, call: 2, claim: 1 } });
  const old = (await list(app, headers)).find((p) => p.callsign === "Alice")!;
  assert.equal(old.appVersion, "0.1-mvp");
  assert.deepEqual(old.wireVersions, { chat: 1, call: 2, claim: 1 });

  // heartbeat без версий версию не стирает; чужой ключ не попадает в память
  await beat(app, alice, { chatPort: 40000 });
  assert.equal((await list(app, headers))[0].appVersion, "0.1-mvp");
});

test("attention: игрок с другой версией протокола, когда у большинства одна", async () => {
  const { app, headers } = await setup();
  const versions = { chat: 1, call: 2, claim: 1 };
  const names = ["A", "B", "C"];
  for (const n of names) {
    const d = await seedPlayer(app, { callsign: n, faction: "X" });
    await beat(app, d, { appVersion: "0.2", wireVersions: versions });
  }
  const odd = await seedPlayer(app, { callsign: "Old", faction: "X" });
  await beat(app, odd, { appVersion: "0.1", wireVersions: { chat: 1, call: 1, claim: 1 } });

  const items = (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as { kind: string; severity: string; detail: string; subjectKey?: string }[];
  const v = items.filter((i) => i.kind === "old_version");
  assert.equal(v.length, 1);
  assert.equal(v[0].severity, "warn");
  assert.equal(v[0].subjectKey, odd.publicKeyB64);
  assert.match(v[0].detail, /Old: 0\.1 call1,chat1,claim1, у большинства \(3 из 4\) — 0\.2 call2,chat1,claim1/);
});

test("attention: без явного большинства версия не считается отклонением", async () => {
  const { app, headers } = await setup();
  for (const [n, v] of [["A", "0.1"], ["B", "0.2"], ["C", "0.3"]]) {
    const d = await seedPlayer(app, { callsign: n, faction: "X" });
    await beat(app, d, { appVersion: v, wireVersions: { chat: 1 } });
  }
  const items = (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as { kind: string }[];
  assert.equal(items.filter((i) => i.kind === "old_version").length, 0);
});
