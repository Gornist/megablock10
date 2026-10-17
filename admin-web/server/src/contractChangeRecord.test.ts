import { test } from "node:test";
import assert from "node:assert/strict";
import { FIELDS, REASONS, signaturePayload, type ChangeRecordInput } from "./lib/changeRecord.js";
import { verifySignature } from "./lib/crypto.js";
import { loadContract, type ChangeRecordVectors } from "./contractVectors.js";

/**
 * Запись изменений против общих векторов `change-record.json` (посчитаны независимо от Kotlin и TS): байты подписи, проверка ECDSA P-256 и
 * закрытые списки полей и причин. Расхождение здесь — это разные байты подписи у телефона и коллектора, то есть все записи отвергнуты.
 */
const v = loadContract<ChangeRecordVectors>("change-record");

for (const c of v.payload) {
  test(`байты подписи: ${c.name}`, () => {
    const r = { ...c.record, signature: "" } as unknown as ChangeRecordInput;
    assert.equal(signaturePayload(r).toString("utf8"), c.payload_utf8);
  });
}

for (const c of v.signature) {
  test(`подпись: ${c.name}`, () => {
    assert.equal(verifySignature(c.publicKeyB64, Buffer.from(c.payload_utf8, "utf8"), c.signatureB64), c.valid);
  });
}

test("закрытые списки: FIELDS и REASONS коллектора = device ∪ world из векторов, master_only среди них нет", () => {
  assert.deepEqual([...FIELDS].sort(), [...v.fields.device, ...v.fields.world].sort());
  assert.deepEqual([...REASONS].sort(), [...v.reasons.device, ...v.reasons.world].sort());
  for (const f of v.fields.master_only) assert.ok(!(FIELDS as readonly string[]).includes(f), `${f} пишет только мастер на устройство — сервер его от устройств не принимает`);
});
