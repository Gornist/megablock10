import { test } from "node:test";
import assert from "node:assert/strict";
import { encodeDaemonLoot, encodeShardLoot } from "./lib/lootCodec.js";

/**
 * Как и в mb10QrCodec.test.ts — lootCodec.ts тут только кодирует (декодирует
 * шифрованный лут-слот только телефон игрока, LootCodec.decode в
 * app/src/main/java/com/megablok10/app/breach/LootCodec.kt). Раунд-трип
 * проверяем локальным декодером, списанным с этого Kotlin-эталона 1:1.
 */
function unb64(text: string): string {
  return Buffer.from(text, "base64").toString("utf8");
}

function decode(plain: string) {
  const parts = plain.split("|");
  if (parts.length === 0) return null;
  switch (parts[0]) {
    case "SHARD": {
      if (parts.length < 7) return null;
      return {
        kind: "SHARD" as const,
        title: unb64(parts[1]),
        meta: unb64(parts[2]),
        body: unb64(parts[3]),
        valueHint: unb64(parts[4]),
        decryptAction: parts[5] === "1",
        moneyAmount: Number(parts[6]) || 0,
      };
    }
    case "DAEMON": {
      if (parts.length < 5) return null;
      return {
        kind: "DAEMON" as const,
        name: unb64(parts[1]),
        sequence: parts[2].split(","),
        tierLevel: Number(parts[3]) || 1,
        effect: parts[4],
      };
    }
    default:
      return null;
  }
}

test("encodeShardLoot — раунд-трип со всеми полями", () => {
  const plain = encodeShardLoot({
    title: "Логи СБ",
    meta: "узел: насосная-4",
    body: "СЕКРЕТНЫЙ ТЕКСТ | с трубой внутри",
    valueHint: "дорогой на вид",
    decryptAction: true,
    moneyAmount: 250,
  });

  const decoded = decode(plain);
  assert.deepEqual(decoded, {
    kind: "SHARD",
    title: "Логи СБ",
    meta: "узел: насосная-4",
    body: "СЕКРЕТНЫЙ ТЕКСТ | с трубой внутри", // "|" внутри свободного текста не ломает разбор — он тоже в base64
    valueHint: "дорогой на вид",
    decryptAction: true,
    moneyAmount: 250,
  });
});

test("encodeShardLoot — decryptAction=false и moneyAmount=0", () => {
  const plain = encodeShardLoot({ title: "Пустышка", meta: "", body: "тело", valueHint: "", decryptAction: false, moneyAmount: 0 });
  const decoded = decode(plain);
  assert.equal(decoded?.kind, "SHARD");
  assert.equal(decoded?.decryptAction, false);
  assert.equal(decoded?.moneyAmount, 0);
});

test("encodeDaemonLoot — раунд-трип, sequence сохраняет порядок", () => {
  const plain = encodeDaemonLoot({ name: "Mainframe", sequence: ["UP", "UP", "DOWN", "LEFT"], tierLevel: 2, effect: "EXTRACT_SHARD" });
  const decoded = decode(plain);
  assert.deepEqual(decoded, {
    kind: "DAEMON",
    name: "Mainframe",
    sequence: ["UP", "UP", "DOWN", "LEFT"],
    tierLevel: 2,
    effect: "EXTRACT_SHARD",
  });
});

test("decode — отклоняет усечённый SHARD-блок (не хватает полей)", () => {
  const plain = encodeShardLoot({ title: "x", meta: "y", body: "z", valueHint: "w", decryptAction: true, moneyAmount: 1 });
  const truncated = plain.split("|").slice(0, 4).join("|");
  assert.equal(decode(truncated), null);
});

test("decode — неизвестный тип блока (не SHARD/DAEMON) отклоняется", () => {
  assert.equal(decode("UNKNOWN|abc"), null);
});
