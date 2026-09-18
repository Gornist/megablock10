import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign as cryptoSign } from "node:crypto";
import { verifySignature } from "./lib/crypto.js";

/**
 * Совместимость с Android — verifySignature читает X.509 SPKI DER + подпись
 * ASN.1/DER (SHA256withECDSA), тот же формат, что IdentityManager.sign на
 * телефоне. Кросс-проверка с реальной Java (`javax.crypto`, тот же код, что
 * в LootCrypto.kt) была сделана вручную во время разработки — здесь
 * закрепляем регресс автоматическим тестом на паре secp256r1 внутри Node.
 */
function makeIdentity() {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return {
    publicKeyB64: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
    privateKey,
  };
}

test("verifySignature принимает валидную подпись", () => {
  const identity = makeIdentity();
  const data = Buffer.from("hello|world|123", "utf8");
  const signature = cryptoSign("sha256", data, { key: identity.privateKey, dsaEncoding: "der" }).toString("base64");
  assert.equal(verifySignature(identity.publicKeyB64, data, signature), true);
});

test("verifySignature отклоняет подпись чужим ключом", () => {
  const identity = makeIdentity();
  const impostor = makeIdentity();
  const data = Buffer.from("hello|world|123", "utf8");
  const signature = cryptoSign("sha256", data, { key: impostor.privateKey, dsaEncoding: "der" }).toString("base64");
  assert.equal(verifySignature(identity.publicKeyB64, data, signature), false);
});

test("verifySignature отклоняет подпись, если данные изменили после подписи", () => {
  const identity = makeIdentity();
  const signed = Buffer.from("balance|100", "utf8");
  const tampered = Buffer.from("balance|999999", "utf8");
  const signature = cryptoSign("sha256", signed, { key: identity.privateKey, dsaEncoding: "der" }).toString("base64");
  assert.equal(verifySignature(identity.publicKeyB64, tampered, signature), false);
});

test("verifySignature не бросает исключение на мусорном входе, а возвращает false", () => {
  assert.equal(verifySignature("не-base64-ключ!!!", Buffer.from("x"), "тоже-не-base64!!!"), false);
  assert.equal(verifySignature("", Buffer.from(""), ""), false);
});
