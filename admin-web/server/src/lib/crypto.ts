import { createPublicKey, createHash, verify as cryptoVerify } from "node:crypto";

/**
 * Проверяет подпись ключом персонажа (ECDSA secp256r1 / P-256).
 *
 * Формат на входе совпадает с тем, что кладёт Android-клиент:
 * publicKeyB64 — X.509 SubjectPublicKeyInfo DER (PublicKey.getEncoded() у
 * java.security.KeyPair на "EC"), signatureB64 — ASN.1/DER-подпись
 * (Signature.getInstance("SHA256withECDSA") по умолчанию отдаёт DER, как и
 * node:crypto для EC-ключей) — оба конца путём проверены на реальных
 * значениях из IdentityManager, см. crypto.test.ts.
 */
export function verifySignature(publicKeyB64: string, data: Buffer, signatureB64: string): boolean {
  try {
    const publicKey = createPublicKey({
      key: Buffer.from(publicKeyB64, "base64"),
      format: "der",
      type: "spki",
    });
    return cryptoVerify("sha256", data, { key: publicKey, dsaEncoding: "der" }, Buffer.from(signatureB64, "base64"));
  } catch {
    return false;
  }
}

/** Хэш мастерского токена для хранения в БД — сам токен нигде не хранится в открытом виде. */
export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}
