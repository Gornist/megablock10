import { test } from "node:test";
import assert from "node:assert/strict";
import { computeAttention } from "./lib/attention.js";
import { testApp, testDb, testDevice } from "./testUtil.js";

/** Копия QR шарда: один shardId отсканировали несколько игроков — мастер видит это в «Требует внимания». */
const shard = (id: string, title: string) => JSON.stringify({ shardId: id, title, tier: "1", decrypted: true, acquiredAt: 1, sourceRef: null });

async function scan(app: ReturnType<typeof testApp>, device: ReturnType<typeof testDevice>, reason = "SHARD_SCAN", id = "sh-1") {
  const res = await app.inject({
    method: "POST",
    url: "/api/changes",
    payload: { records: [device.change({ field: "shards.add", newValue: shard(id, "Чертёж"), reason, sourceRef: id })] },
  });
  assert.deepEqual(res.json().rejected, []);
}

test("один шард, отсканированный двумя игроками, — предупреждение", async () => {
  const db = testDb();
  const app = testApp(db);
  const [a, b] = [testDevice(), testDevice()];
  await scan(app, a);
  assert.equal(computeAttention(db).filter((i) => i.kind === "shard_copies").length, 0, "один игрок — не копия");
  await scan(app, b);
  const item = computeAttention(db).find((i) => i.kind === "shard_copies");
  assert.ok(item);
  assert.match(item.detail, /«Чертёж» \(sh-1\): 2 игроков/);
});

test("передача шарда и лут контейнера копией не считаются", async () => {
  const db = testDb();
  const app = testApp(db);
  const [a, b, c] = [testDevice(), testDevice(), testDevice()];
  await scan(app, a);
  await scan(app, b, "ITEM_TRANSFER_IN");
  await scan(app, c, "BREACH_LOOT");
  assert.equal(computeAttention(db).filter((i) => i.kind === "shard_copies").length, 0);
});
