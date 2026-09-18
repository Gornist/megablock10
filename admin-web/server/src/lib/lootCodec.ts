/**
 * Зеркало app/src/main/java/com/megablok10/app/breach/LootCodec.kt — формат
 * содержимого лут-слота ДО шифрования (lootCrypto.ts шифрует уже готовую
 * строку отсюда, не наоборот). Поля через '|', свободный текст в base64.
 */

export interface ShardLootInput {
  title: string;
  meta: string;
  body: string;
  valueHint: string;
  decryptAction: boolean;
  moneyAmount: number;
}

export interface DaemonLootInput {
  name: string;
  sequence: string[];
  tierLevel: number;
  effect: string;
}

function b64(text: string): string {
  return Buffer.from(text, "utf8").toString("base64");
}

export function encodeShardLoot(loot: ShardLootInput): string {
  return ["SHARD", b64(loot.title), b64(loot.meta), b64(loot.body), b64(loot.valueHint), loot.decryptAction ? "1" : "0", String(loot.moneyAmount)].join(
    "|",
  );
}

export function encodeDaemonLoot(loot: DaemonLootInput): string {
  return ["DAEMON", b64(loot.name), loot.sequence.join(","), String(loot.tierLevel), loot.effect].join("|");
}
