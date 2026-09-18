import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

/**
 * Зеркало app/src/main/java/com/megablok10/app/breach/LootCrypto.kt — тот
 * же ключ, тот же AES-256-GCM. Java's Cipher.doFinal() в GCM-режиме кладёт
 * тег аутентификации (16 байт) СРАЗУ ЗА шифротекстом в один массив; Node
 * отдаёт тег отдельным вызовом getAuthTag() — здесь вручную склеиваем в
 * тот же порядок байт (iv || ciphertext || tag), чтобы Android читал ровно
 * то же, что генерирует этот сервер, и наоборот.
 *
 * Ключ намеренно не меняется между запусками — смена этой константы делает
 * нечитаемыми payload'ы всех уже напечатанных QR текущей игры.
 */
const KEY = Buffer.from("MB10-LOOT-v1-key-breach-protocol", "utf8"); // 32 байт — AES-256
const IV_BYTES = 12;
const TAG_BYTES = 16;

export function encryptLoot(plain: string): string {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", KEY, iv, { authTagLength: TAG_BYTES });
  const ciphertext = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, ciphertext, tag]).toString("base64");
}

/** null — payload битый или зашифрован другим ключом (совместимо с LootCrypto.decrypt на клиенте). */
export function decryptLoot(payloadB64: string): string | null {
  try {
    const bytes = Buffer.from(payloadB64, "base64");
    const iv = bytes.subarray(0, IV_BYTES);
    const tag = bytes.subarray(bytes.length - TAG_BYTES);
    const ciphertext = bytes.subarray(IV_BYTES, bytes.length - TAG_BYTES);
    const decipher = createDecipheriv("aes-256-gcm", KEY, iv, { authTagLength: TAG_BYTES });
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}
