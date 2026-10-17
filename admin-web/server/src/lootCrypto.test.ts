import { test } from "node:test";
import assert from "node:assert/strict";
import { decryptLoot, deriveLootKey, encryptLoot } from "./lib/lootCrypto.js";
import { encodeDaemonLoot, encodeShardLoot } from "./lib/lootCodec.js";
import { loadContract, type LootCryptoVectors } from "./contractVectors.js";

const FALLBACK_KEY = deriveLootKey(undefined);

/**
 * AES-256-GCM, байтовый layout iv || ciphertext || tag, как в LootCrypto.kt на Android. Совместимость с Kotlin держат общие векторы
 * внизу файла; здесь — регресс round-trip внутри самого Node.
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
 * Общие векторы `loot-crypto.json` (посчитаны независимо от Kotlin и TS; их же читает LootCryptoContractTest на Android): ключ по секрету
 * игры (null/пробелы = постоянный ключ v1), блоки AES-GCM, которые обязаны открыться, и блоки, которые обязаны вернуть null.
 * Разойдутся реализации — телефон не прочтёт лут, который собрал коллектор.
 */
const vectors = loadContract<LootCryptoVectors>("loot-crypto");
const secretOf = (s: string | null) => s ?? undefined;

for (const k of vectors.keys) {
  test(`ключ лута: ${k.name}`, () => {
    assert.equal(deriveLootKey(secretOf(k.gameSecret)).toString("hex"), k.keyHex);
  });
}

for (const s of vectors.sealed) {
  test(`блок открывается: ${s.name}`, () => {
    const key = deriveLootKey(secretOf(s.gameSecret));
    assert.equal(decryptLoot(s.sealedB64, key), s.plaintext);
    assert.equal(Buffer.from(s.sealedB64, "base64").subarray(0, 12).toString("hex"), s.ivHex, "IV — первые 12 байт блока");
  });
}

for (const r of vectors.rejected) {
  test(`блок отвергнут (null): ${r.name}`, () => {
    assert.equal(decryptLoot(r.sealedB64, deriveLootKey(secretOf(r.gameSecret))), null);
  });
}
