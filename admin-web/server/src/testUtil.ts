import { generateKeyPairSync, sign as cryptoSign, randomUUID } from "node:crypto";
import { buildApp } from "./app.js";
import { openDb, type Db } from "./db/index.js";
import { createMaster } from "./lib/auth.js";

/** In-memory SQLite — каждый тест получает чистую БД, ничего не пишет на диск. */
export function testDb(): Db {
  return openDb(":memory:");
}

export function testApp(db: Db) {
  return buildApp(db, { logger: false });
}

/** Мастер + сессионный токен для тестов защищённых роутов — та же функция, что использует CLI-скрипт create-master. */
export function testMaster(db: Db, name = "Тест") {
  const token = createMaster(db, name);
  return { name, token };
}

export async function loginAs(app: ReturnType<typeof testApp>, name: string, token: string): Promise<string> {
  const res = await app.inject({ method: "POST", url: "/api/auth/login", payload: { name, token } });
  return (res.json() as { sessionToken: string }).sessionToken;
}

/** Поддельное устройство игрока — та же пара EC secp256r1 и та же схема подписи, что IdentityManager на Android (см. lib/crypto.ts, lib/changeRecord.ts). */
export function testDevice() {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const publicKeyB64 = publicKey.export({ type: "spki", format: "der" }).toString("base64");
  let seq = 0;

  function signaturePayload(r: {
    id: string;
    subjectKeyB64: string;
    seq: number;
    happenedAt: number;
    field: string;
    oldValue: string | null;
    newValue: string | null;
    reason: string;
    sourceRef: string | null;
    actor: string;
  }): Buffer {
    const parts = [
      r.id,
      r.subjectKeyB64,
      String(r.seq),
      String(r.happenedAt),
      r.field,
      r.oldValue ?? "",
      r.newValue ?? "",
      r.reason,
      r.sourceRef ?? "",
      r.actor,
    ];
    return Buffer.from(parts.join("|"), "utf8");
  }

  function sign(payload: Buffer, key = privateKey): string {
    return cryptoSign("sha256", payload, { key, dsaEncoding: "der" }).toString("base64");
  }

  function change(input: {
    field: string;
    oldValue?: string | null;
    newValue: string | null;
    reason: string;
    sourceRef?: string | null;
    actor?: string;
    signAs?: { publicKeyB64: string; privateKey: typeof privateKey };
  }) {
    seq += 1;
    const record = {
      id: randomUUID(),
      subjectKeyB64: publicKeyB64,
      seq,
      happenedAt: Date.now(),
      field: input.field,
      oldValue: input.oldValue ?? null,
      newValue: input.newValue,
      reason: input.reason,
      sourceRef: input.sourceRef ?? null,
      actor: input.actor ?? publicKeyB64,
    };
    const signature = sign(signaturePayload(record), input.signAs?.privateKey ?? privateKey);
    return { ...record, signature };
  }

  return { publicKeyB64, privateKey, sign, signaturePayload, change };
}

export function claimSignature(device: ReturnType<typeof testDevice>, slotRef: string, claimedAt: number): string {
  return device.sign(Buffer.from(`${slotRef}|${device.publicKeyB64}|${claimedAt}`, "utf8"));
}
