import { test } from "node:test";
import assert from "node:assert/strict";
import { loginAs, testApp, testDb, testMaster } from "./testUtil.js";

/** Запись с «сломанными» часами телефона: happened_at на пять дней назад, а на сервер она пришла только что. */
function insertSkewed(db: ReturnType<typeof testDb>, id: string, subject: string, reason: string, sourceRef: string, newValue: string, seq: number) {
  const now = Date.now();
  db.prepare(
    `INSERT INTO changes (id, subject_key, seq, happened_at, received_at, field, old_value, new_value, reason, source_ref, actor, signature)
     VALUES (?, ?, ?, ?, ?, 'counters.breach', NULL, ?, ?, ?, ?, '')`,
  ).run(id, subject, seq, now - 5 * 86_400_000, now, newValue, reason, sourceRef, subject);
}

test("«за последний час» на Обзоре и в узлах считается по часам сервера — сбитые часы телефона цифры не искажают", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  await app.inject({
    method: "POST",
    url: "/api/containers",
    headers,
    payload: { containers: [{ id: "nasos-4", name: "Насосная-4", tier: "HARD", ownerFaction: "NEON", slots: [] }] },
  });
  insertSkewed(db, "r1", "alice", "BREACH_ATTEMPT", "nasos-4:s1", JSON.stringify({ tier: "HARD", outcome: "success" }), 1);

  const overview = (await app.inject({ method: "GET", url: "/api/overview", headers })).json();
  assert.equal(overview.breachesLastHour.success, 1);
  const nodes = (await app.inject({ method: "GET", url: "/api/nodes", headers })).json();
  assert.equal(nodes[0].breachesLastHour, 1);
  const detail = (await app.inject({ method: "GET", url: "/api/nodes/nasos-4?hours=2", headers })).json();
  assert.equal(detail.timeline.at(-1).success, 1);
  assert.ok(Date.now() - nodes[0].lastBreachAt < 60_000, "последний взлом — по времени сервера, а не «пять дней назад»");
});
