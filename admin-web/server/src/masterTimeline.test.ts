import { test } from "node:test";
import assert from "node:assert/strict";
import { projectCharacter } from "./lib/projection.js";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

/**
 * Правка мастера встаёт в хронологию телефона, а не в порядок прихода на сервер. Сценарий из аудита: телефон без связи
 * записал трату, мастер тем временем поставил баланс, телефон вернулся и прислал старую трату уже после правки — раньше
 * «последняя по приходу» откатывала баланс к старому значению, хотя на телефоне стоит значение мастера.
 */
async function setup() {
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db);
  const session = await loginAs(app, master.name, master.token);
  const device = testDevice();
  const post = async (payload: Record<string, unknown>) =>
    (await app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: device.publicKeyB64, ...payload } })).json() as {
      pending: { id: string }[];
    };
  const override = async (newValue: string) => {
    const res = await app.inject({
      method: "POST",
      url: `/api/players/${encodeURIComponent(device.publicKeyB64)}/override`,
      headers: { authorization: `Bearer ${session}` },
      payload: { field: "balance", newValue, reason: "правка" },
    });
    assert.equal(res.statusCode, 200);
  };
  const balance = () => projectCharacter(db, device.publicKeyB64)?.balance;
  return { db, device, post, override, balance };
}

test("старая запись, пришедшая после правки мастера, не откатывает её", async () => {
  const { device, post, override, balance } = await setup();
  await post({ records: [device.change({ field: "balance", oldValue: "0", newValue: "100", reason: "CHARACTER_CREATED" })] });   // seq 1
  const offlineSpend = device.change({ field: "balance", oldValue: "100", newValue: "70", reason: "TRANSFER_OUT" });              // seq 2, без связи
  await override("500");
  assert.equal(balance(), 500);

  // Телефон вернулся: прислал старую трату, получил правку, применил её (последний seq у него — 2) и подтвердил.
  const { pending } = await post({ records: [offlineSpend] });
  assert.equal(balance(), 500, "правка ещё не применена телефоном — она последняя");
  await post({ ackIds: [pending[0].id], appliedAtSeq: { [pending[0].id]: 2 } });
  assert.equal(balance(), 500, "трата с seq 2 была до применения правки — правка выигрывает");

  // После правки телефон тратит уже от её значения — это выигрывает у правки.
  await post({ records: [device.change({ field: "balance", oldValue: "500", newValue: "520", reason: "SHARD_SCAN" })] });            // seq 3
  assert.equal(balance(), 520);
});

test("запись, сделанная после применения правки, выигрывает, даже если пришла вместе со старыми", async () => {
  const { device, post, override, balance } = await setup();
  await post({ records: [device.change({ field: "balance", oldValue: "0", newValue: "100", reason: "CHARACTER_CREATED" })] });   // seq 1
  await override("500");
  const { pending } = await post({});
  await post({ ackIds: [pending[0].id], appliedAtSeq: { [pending[0].id]: 1 } });   // применил, когда последним был seq 1
  const after = device.change({ field: "balance", oldValue: "500", newValue: "450", reason: "TRANSFER_OUT" });   // seq 2
  await post({ records: [after] });
  assert.equal(balance(), 450);
});

test("правка, которую телефон не смог применить, в снимок не попадает", async () => {
  const { device, post, override, balance } = await setup();
  await post({ records: [device.change({ field: "balance", oldValue: "0", newValue: "100", reason: "CHARACTER_CREATED" })] });
  await override("500");
  const { pending } = await post({});
  await post({ failures: [{ id: pending[0].id, error: "поле не поддерживается", permanent: true }] });
  assert.equal(balance(), 100, "на телефоне правки нет — дашборд показывает то, что у игрока");
});
