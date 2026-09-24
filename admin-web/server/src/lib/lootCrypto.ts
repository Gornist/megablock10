import { createCipheriv, createDecipheriv, createHmac, randomBytes } from "node:crypto";

/**
 * Зеркало app/src/main/java/com/megablok10/app/breach/LootCrypto.kt — тот
 * же ключ (см. deriveLootKey), тот же AES-256-GCM. Java's Cipher.doFinal()
 * в GCM-режиме кладёт тег аутентификации (16 байт) СРАЗУ ЗА шифротекстом в
 * один массив; Node отдаёт тег отдельным вызовом getAuthTag() — здесь
 * вручную склеиваем в тот же порядок байт (iv || ciphertext || tag), чтобы
 * Android читал ровно то же, что генерирует этот сервер, и наоборот.
 */
// Ключ по умолчанию, если GAME_SECRET не настроен (см. deriveLootKey) — тот
// самый ключ, что был единственным в v1. Смена этой константы делает
// нечитаемыми payload'ы всех уже напечатанных QR игр без GAME_SECRET.
const FALLBACK_KEY = Buffer.from("MB10-LOOT-v1-key-breach-protocol", "utf8"); // 32 байт — AES-256
const HKDF_SALT = Buffer.alloc(32); // "нет соли" по RFC 5869 — HashLen нулей, явно, а не по умолчанию
const HKDF_INFO = Buffer.from("mb10-loot-v1", "utf8");
const IV_BYTES = 12;
const TAG_BYTES = 16;

/**
 * Ключ AES-256 для лута этой игры: без GAME_SECRET — FALLBACK_KEY (как было
 * всегда), с GAME_SECRET — HKDF-SHA256(secret) с тем же salt/info на Android
 * (LootCrypto.deriveKey), так что ключ у всех телефонов этой игры совпадает,
 * но не совпадает с ключом другой игры или со старым публичным ключом.
 * До GAME_SECRET ключ был один статичный и лежал прямо в этом файле в
 * открытом репозитории — расшифровать любой QR любой игры мог кто угодно,
 * не только реверс-инженер APK. HKDF от секрета конкретной игры поднимает
 * это до «нужно знать секрет именно этой игры», без нового формата QR и
 * новой инфраструктуры — secret уже доставляется на телефон полем QR
 * персонажа (см. docs/provisioning-qr.md).
 */
export function deriveLootKey(gameSecret: string | undefined): Buffer {
  const secret = gameSecret?.trim();
  if (!secret) return FALLBACK_KEY;
  const prk = createHmac("sha256", HKDF_SALT).update(secret, "utf8").digest();
  return createHmac("sha256", prk).update(Buffer.concat([HKDF_INFO, Buffer.from([0x01])])).digest();
}

export function encryptLoot(plain: string, key: Buffer): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", key, iv, { authTagLength: TAG_BYTES });
  const ciphertext = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, ciphertext, tag]).toString("base64");
}

/** null — payload битый или зашифрован другим ключом (совместимо с LootCrypto.decrypt на клиенте). */
export function decryptLoot(payloadB64: string, key: Buffer): string | null {
  try {
    const bytes = Buffer.from(payloadB64, "base64");
    const iv = bytes.subarray(0, IV_BYTES);
    const tag = bytes.subarray(bytes.length - TAG_BYTES);
    const ciphertext = bytes.subarray(IV_BYTES, bytes.length - TAG_BYTES);
    const decipher = createDecipheriv("aes-256-gcm", key, iv, { authTagLength: TAG_BYTES });
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}
