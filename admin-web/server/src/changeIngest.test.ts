import { test } from "node:test";
import assert from "node:assert/strict";
import { isChangeRecordInput, validateRecord } from "./lib/changeIngest.js";
import { testDevice } from "./testUtil.js";

test("isChangeRecordInput: форма записи проверяется по полям", () => {
  const d = testDevice();
  const good = d.change({ field: "balance", oldValue: "0", newValue: "5", reason: "BREACH_EDDIES" });
  assert.equal(isChangeRecordInput(good), true);
  assert.equal(isChangeRecordInput({ ...good, seq: 1.5 }), false);
  assert.equal(isChangeRecordInput({ ...good, sourceRef: 7 }), false);
  assert.equal(isChangeRecordInput({ ...good, signature: undefined }), false);
  assert.equal(isChangeRecordInput(null), false);
  assert.equal(isChangeRecordInput("x"), false);
});

test("validateRecord: неизвестные поле и причина, правка мастера с устройства, чужой автор, чужая подпись", () => {
  const d = testDevice();
  const other = testDevice();
  const ok = d.change({ field: "balance", oldValue: "0", newValue: "5", reason: "BREACH_EDDIES" });
  assert.deepEqual(validateRecord(ok), { ok: true });
  assert.match((validateRecord({ ...ok, field: "nope" }) as { error: string }).error, /unknown field/);
  assert.match((validateRecord({ ...ok, reason: "NOPE" }) as { error: string }).error, /unknown reason/);
  assert.match((validateRecord({ ...ok, reason: "MASTER_OVERRIDE" }) as { error: string }).error, /only be issued by the collector/);
  assert.match((validateRecord({ ...ok, actor: other.publicKeyB64 }) as { error: string }).error, /actor must equal/);
  const forged = d.change({ field: "balance", newValue: "9", reason: "BREACH_EDDIES", signAs: { publicKeyB64: other.publicKeyB64, privateKey: other.privateKey } });
  assert.match((validateRecord(forged) as { error: string }).error, /invalid signature/);
});

test("validateRecord: TRANSFER_IN подписывает получатель, а автором может быть контрагент", () => {
  const sender = testDevice();
  const receiver = testDevice();
  const inRec = receiver.change({ field: "balance", oldValue: "0", newValue: "10", reason: "TRANSFER_IN", sourceRef: "tx", actor: sender.publicKeyB64 });
  assert.deepEqual(validateRecord(inRec), { ok: true });
});
