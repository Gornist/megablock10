import { test } from "node:test";
import assert from "node:assert/strict";
import { testDevice } from "./testUtil.js";
import { setup, sleep } from "./testHelpers.js";

test("until: состояние игрока и список на момент T не видят более поздних записей", async () => {
  const { app, headers } = await setup();
  const a = testDevice();
  await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: {
      records: [
        a.change({ field: "callsign", newValue: "Alice", reason: "CHARACTER_CREATED" }),
        a.change({ field: "balance", oldValue: "0", newValue: "100", reason: "BREACH_EDDIES" }),
      ],
    },
  });
  await sleep(5);
  const t = Date.now();
  await sleep(5);
  await app.inject({ method: "POST", url: "/api/changes", payload: { records: [a.change({ field: "balance", oldValue: "100", newValue: "900", reason: "BREACH_EDDIES" })] } });

  const key = encodeURIComponent(a.publicKeyB64);
  assert.equal((await app.inject({ method: "GET", url: `/api/players/${key}`, headers })).json().balance, 900);
  assert.equal((await app.inject({ method: "GET", url: `/api/players/${key}?until=${t}`, headers })).json().balance, 100);
  const list = (await app.inject({ method: "GET", url: `/api/players?until=${t}`, headers })).json();
  assert.equal(list[0].balance, 100);
  assert.equal(list[0].online, false, "«на связи» на момент в прошлом не определено");
  assert.equal((await app.inject({ method: "GET", url: `/api/players/${key}?until=1`, headers })).statusCode, 404, "до появления персонажа его нет");
});
