import { test } from "node:test";
import assert from "node:assert/strict";
import { REASONS } from "./lib/changeRecord.js";
import { REASON_LABEL_RU } from "./lib/humanize.js";
import { KIND_LABEL_RU, KIND_SQL } from "./lib/eventKinds.js";
import { loginAs, testApp, testDb, testMaster } from "./testUtil.js";

test("у каждой причины протокола есть русская подпись, а у каждого типа — и подпись, и условие фильтра", () => {
  for (const r of REASONS) assert.ok(REASON_LABEL_RU[r], `нет подписи для причины ${r}`);
  assert.deepEqual(Object.keys(KIND_LABEL_RU).sort(), Object.keys(KIND_SQL).sort());
});

test("GET /api/meta отдаёт причины и типы; без токена — 401", async () => {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const res = await app.inject({ method: "GET", url: "/api/meta", headers });
  assert.equal(res.statusCode, 200);
  const body = res.json() as { reasons: { code: string; label: string }[]; kinds: { code: string; label: string }[] };
  assert.equal(body.reasons.length, REASONS.length);
  assert.deepEqual(body.reasons[0], { code: REASONS[0], label: REASON_LABEL_RU[REASONS[0]] });
  assert.deepEqual(body.kinds.map((k) => k.code), Object.keys(KIND_LABEL_RU));
  assert.equal((await app.inject({ method: "GET", url: "/api/meta" })).statusCode, 401);
});
