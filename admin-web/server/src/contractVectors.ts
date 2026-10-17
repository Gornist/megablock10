import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Общие известные ответы контрактов между зонами (аудит 17.10): один JSON — один контракт, читают приложение, Мост и коллектор.
 * Файлы лежат в `rules/src/test/resources/contracts/` (см. README рядом) и правятся только вместе с форматом. Только для тестов.
 * Корень репозитория ищется вверх от этого файла — так же, как делает `ContractVectors` на стороне Android.
 */
const REL = join("rules", "src", "test", "resources", "contracts");

function contractsDir(): string {
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 12; i++) {
    const candidate = join(dir, REL);
    if (existsSync(candidate)) return candidate;
    dir = dirname(dir);
  }
  throw new Error(`не найден каталог общих векторов ${REL} выше ${fileURLToPath(import.meta.url)}`);
}

/** Читает `contracts/<name>.json`, например `loadContract<ChangeRecordVectors>("change-record")`. */
export function loadContract<T>(name: string): T {
  return JSON.parse(readFileSync(join(contractsDir(), `${name}.json`), "utf8")) as T;
}

export interface ChangeRecordVectors {
  payload: { name: string; record: Record<string, unknown>; payload_utf8: string }[];
  signature: { name: string; publicKeyB64: string; payload_utf8: string; signatureB64: string; valid: boolean }[];
  fields: { device: string[]; world: string[]; master_only: string[] };
  reasons: { device: string[]; world: string[] };
}

export interface QrVectors {
  containers: { name: string; id: string; containerName: string; tier: number; ownerFaction: string; loot: { type: "SHARD" | "DAEMON"; tier: number; copies: number; payload: string }[]; line: string }[];
  shards: { name: string; id: string; decryptAction: boolean; tier: number; valueHint: string; title: string; meta: string; body: string; moneyAmount: number; line: string }[];
  ram: { name: string; token: string; delta: number; line: string }[];
  provisions: { name: string; id: string; collectorUrl: string; gameSecret: string; callsign: string; faction: string; startBalance: number; ramCapacity: number; line: string }[];
  secAlerts: { name: string; line: string }[];
}

export interface LootCryptoVectors {
  keys: { name: string; gameSecret: string | null; keyHex: string }[];
  sealed: { name: string; gameSecret: string | null; ivHex: string; plaintext: string; sealedB64: string }[];
  rejected: { name: string; gameSecret: string | null; sealedB64: string }[];
}
