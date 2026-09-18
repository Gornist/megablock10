import { test } from "node:test";
import assert from "node:assert/strict";
import { decryptLoot, encryptLoot } from "./lib/lootCrypto.js";
import { encodeDaemonLoot, encodeShardLoot } from "./lib/lootCodec.js";

/**
 * AES-256-GCM, тот же ключ и байтовый layout (iv || ciphertext || tag), что
 * LootCrypto.kt на Android — реальная кросс-проверка с javax.crypto была
 * сделана вручную (см. admin-web/README.md), здесь только регресс round-trip
 * внутри самого Node, чтобы будущая правка не сломала совместимость молча.
 */
test("encryptLoot/decryptLoot — round-trip для шарда", () => {
  const plain = encodeShardLoot({
    title: "Секретный лог",
    meta: "получен только что",
    body: "Полный текст шарда.",
    valueHint: "ценный документ",
    decryptAction: true,
    moneyAmount: 25,
  });
  const encrypted = encryptLoot(plain);
  assert.notEqual(encrypted, plain);
  assert.equal(decryptLoot(encrypted), plain);
});

test("encryptLoot/decryptLoot — round-trip для демона", () => {
  const plain = encodeDaemonLoot({ name: "Backdoor.exe", sequence: ["1C", "55"], tierLevel: 2, effect: "EXTRACT_SHARD" });
  assert.equal(decryptLoot(encryptLoot(plain)), plain);
});

test("encryptLoot — два вызова на тот же текст дают разный ciphertext (случайный IV)", () => {
  const plain = "SHARD|dGVzdA==|||0|0";
  assert.notEqual(encryptLoot(plain), encryptLoot(plain));
});

test("decryptLoot — возвращает null на битом/чужом payload, не бросает исключение", () => {
  assert.equal(decryptLoot("не-валидный-base64!!!"), null);
  assert.equal(decryptLoot(""), null);
  // валидный base64, но слишком короткий для iv+tag — не должен падать
  assert.equal(decryptLoot(Buffer.from("x").toString("base64")), null);
});
