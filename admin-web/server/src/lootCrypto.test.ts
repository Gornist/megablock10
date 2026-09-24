import { test } from "node:test";
import assert from "node:assert/strict";
import { decryptLoot, deriveLootKey, encryptLoot } from "./lib/lootCrypto.js";
import { encodeDaemonLoot, encodeShardLoot } from "./lib/lootCodec.js";

const FALLBACK_KEY = deriveLootKey(undefined);

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
  const encrypted = encryptLoot(plain, FALLBACK_KEY);
  assert.notEqual(encrypted, plain);
  assert.equal(decryptLoot(encrypted, FALLBACK_KEY), plain);
});

test("encryptLoot/decryptLoot — round-trip для демона", () => {
  const plain = encodeDaemonLoot({ name: "Backdoor.exe", sequence: ["1C", "55"], tierLevel: 2, effect: "EXTRACT_SHARD" });
  assert.equal(decryptLoot(encryptLoot(plain, FALLBACK_KEY), FALLBACK_KEY), plain);
});

test("encryptLoot — два вызова на тот же текст дают разный ciphertext (случайный IV)", () => {
  const plain = "SHARD|dGVzdA==|||0|0";
  assert.notEqual(encryptLoot(plain, FALLBACK_KEY), encryptLoot(plain, FALLBACK_KEY));
});

test("decryptLoot — возвращает null на битом/чужом payload, не бросает исключение", () => {
  assert.equal(decryptLoot("не-валидный-base64!!!", FALLBACK_KEY), null);
  assert.equal(decryptLoot("", FALLBACK_KEY), null);
  // валидный base64, но слишком короткий для iv+tag — не должен падать
  assert.equal(decryptLoot(Buffer.from("x").toString("base64"), FALLBACK_KEY), null);
});

test("deriveLootKey — без GAME_SECRET даёт прежний фиксированный ключ (32 байта)", () => {
  assert.equal(deriveLootKey(undefined).length, 32);
  assert.deepEqual(deriveLootKey(undefined), deriveLootKey(""));
  assert.deepEqual(deriveLootKey(undefined), deriveLootKey("   "));
});

test("deriveLootKey — с GAME_SECRET даёт другой ключ, детерминированно по секрету", () => {
  const keyA = deriveLootKey("game-one-secret");
  const keyB = deriveLootKey("game-two-secret");
  assert.equal(keyA.length, 32);
  assert.notDeepEqual(keyA, FALLBACK_KEY);
  assert.notDeepEqual(keyA, keyB);
  assert.deepEqual(deriveLootKey("game-one-secret"), keyA); // детерминированность
});

test("deriveLootKey — payload одной игры не читается ключом другой игры или ключом без секрета", () => {
  const keyA = deriveLootKey("game-one-secret");
  const keyB = deriveLootKey("game-two-secret");
  const encrypted = encryptLoot("SHARD|dGVzdA==|||0|0", keyA);
  assert.equal(decryptLoot(encrypted, keyB), null);
  assert.equal(decryptLoot(encrypted, FALLBACK_KEY), null);
  assert.equal(decryptLoot(encrypted, keyA), "SHARD|dGVzdA==|||0|0");
});

/**
 * Тестовый вектор для сверки с LootCrypto.deriveKey на Android (HKDF-SHA256,
 * salt = 32 нулевых байта, info = "mb10-loot-v1"). Значение посчитано этой
 * же функцией и захардкожено на обеих сторонах — если реализации разойдутся
 * (например, кто-то поменяет salt/info на одной стороне), один из двух
 * тестов, а не оба сразу, покраснеет.
 */
test("deriveLootKey — тестовый вектор для сверки с Kotlin-стороной (LootCryptoTest.deriveKey matches shared vector)", () => {
  const key = deriveLootKey("mb10-cross-check-secret");
  assert.equal(key.toString("hex"), "232aab80471b62a518d8b054f2a1aeb0cd62c28586a02df3f1106ec15eca4a2d");
});
