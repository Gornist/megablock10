import { test } from "node:test";
import assert from "node:assert/strict";
import { encodeContainerQr, encodeRamUpgradeQr, encodeShardQr, type ContainerSlotForQr } from "./lib/mb10QrCodec.js";

/**
 * mb10QrCodec.ts кодирует ТОЛЬКО (декодирует QR исключительно телефон
 * игрока — см. комментарий в самом файле), поэтому "round-trip" здесь
 * означает: разобрать строку тем же алгоритмом, что и decode() в
 * app/src/main/java/com/megablok10/app/qr/Mb10Qr.kt (Mb10QrCodec.decode),
 * скопированным сюда как эталон, и убедиться, что то, что генерирует
 * сервер, парсится клиентом байт-в-байт так же, как задумано. Если формат
 * разъедется — эти тесты должны сломаться раньше, чем реальный QR на игре.
 */
const MAGIC = "MB10";

function unb64(text: string): string {
  return Buffer.from(text, "base64").toString("utf8");
}

function decodeContainer(parts: string[]) {
  if (parts.length < 8) return null;
  const lootBlob = unb64(parts[7]);
  const loot =
    lootBlob.length === 0
      ? []
      : lootBlob.split(";").map((slot) => {
          const f = slot.split(",");
          const payload = f.slice(3).join(","); // limit=4 на Kotlin-стороне — всё после 3-й запятой это payload
          return { type: f[0], tierLevel: Number(f[1]), copies: Number(f[2]), payload };
        });
  return {
    id: parts[3],
    name: unb64(parts[4]),
    tierLevel: Number(parts[5]),
    ownerFaction: unb64(parts[6]),
    loot,
  };
}

function decodeShard(parts: string[]) {
  if (parts.length < 10) return null;
  return {
    id: parts[3],
    decryptAction: parts[4] === "1",
    tier: Number(parts[5]),
    valueHint: unb64(parts[6]),
    title: unb64(parts[7]),
    meta: unb64(parts[8]),
    body: unb64(parts[9]),
    moneyAmount: parts[10] !== undefined ? Number(parts[10]) : 0,
  };
}

function decodeRamUpgrade(parts: string[]) {
  if (parts.length < 5) return null;
  return { token: parts[3], delta: Number(parts[4]) };
}

function decode(raw: string) {
  const parts = raw.split(":");
  if (parts.length < 2 || parts[0] !== MAGIC) return null;
  switch (parts[1]) {
    case "CONTAINER":
      return { kind: "CONTAINER" as const, value: decodeContainer(parts) };
    case "SHARD":
      return { kind: "SHARD" as const, value: decodeShard(parts) };
    case "RAM":
      return { kind: "RAM" as const, value: decodeRamUpgrade(parts) };
    default:
      return null;
  }
}

test("encodeContainerQr — раунд-трип с несколькими слотами (SHARD + DAEMON)", () => {
  const slots: ContainerSlotForQr[] = [
    { typeName: "SHARD", tierLevel: 2, copies: 1, payload: "cGF5bG9hZC1vbmU=" },
    { typeName: "DAEMON", tierLevel: 1, copies: 0, payload: "cGF5bG9hZC10d28=" },
  ];
  const qr = encodeContainerQr("nasos-4", "Насосная-4", 2, "NEON_DRAGONS", slots);

  const decoded = decode(qr);
  assert.equal(decoded?.kind, "CONTAINER");
  const container = decoded!.value!;
  assert.equal(container.id, "nasos-4");
  assert.equal(container.name, "Насосная-4");
  assert.equal(container.tierLevel, 2);
  assert.equal(container.ownerFaction, "NEON_DRAGONS");
  assert.equal(container.loot.length, 2);
  assert.deepEqual(container.loot[0], { type: "SHARD", tierLevel: 2, copies: 1, payload: "cGF5bG9hZC1vbmU=" });
  assert.deepEqual(container.loot[1], { type: "DAEMON", tierLevel: 1, copies: 0, payload: "cGF5bG9hZC10d28=" });
});

test("encodeContainerQr — пустой список слотов декодируется в пустой лут, не в массив с одним мусорным элементом", () => {
  const qr = encodeContainerQr("empty-box", "Пустой ящик", 1, "", []);
  const decoded = decode(qr);
  assert.equal(decoded?.kind, "CONTAINER");
  assert.deepEqual(decoded!.value!.loot, []);
});

test("encodeShardQr — раунд-трип, decryptAction=true и moneyAmount сохраняются", () => {
  const qr = encodeShardQr("shard-1", true, 3, "дорогой на вид", "Логи СБ", "meta-x", "СЕКРЕТНЫЙ ТЕКСТ", 150);
  const decoded = decode(qr);
  assert.equal(decoded?.kind, "SHARD");
  assert.deepEqual(decoded!.value, {
    id: "shard-1",
    decryptAction: true,
    tier: 3,
    valueHint: "дорогой на вид",
    title: "Логи СБ",
    meta: "meta-x",
    body: "СЕКРЕТНЫЙ ТЕКСТ",
    moneyAmount: 150,
  });
});

test("encodeShardQr — decryptAction=false и moneyAmount=0 (значения по умолчанию)", () => {
  const qr = encodeShardQr("shard-2", false, 1, "", "Пустышка", "", "тело", 0);
  const decoded = decode(qr);
  assert.equal(decoded?.kind, "SHARD");
  assert.equal(decoded!.value!.decryptAction, false);
  assert.equal(decoded!.value!.moneyAmount, 0);
});

test("encodeRamUpgradeQr — раунд-трип", () => {
  const qr = encodeRamUpgradeQr("ram-abc123", 2);
  const decoded = decode(qr);
  assert.deepEqual(decoded, { kind: "RAM", value: { token: "ram-abc123", delta: 2 } });
});

test("decode — отклоняет строку без правильного MAGIC-префикса", () => {
  const notOurs = "OTHER:CONTAINER:v1:x";
  assert.equal(decode(notOurs), null);
});

test("decode — отклоняет усечённый CONTAINER (не долетели все сегменты)", () => {
  const qr = encodeContainerQr("nasos-4", "Насосная-4", 2, "NEON_DRAGONS", []);
  const truncated = qr.split(":").slice(0, 5).join(":"); // обрезаем последние сегменты
  const decoded = decode(truncated);
  assert.equal(decoded?.kind, "CONTAINER");
  assert.equal(decoded!.value, null);
});

test("encodeContainerQr — свободный текст с ':' и ';' внутри имени/фракции не ломает разбор (всё через base64)", () => {
  const qr = encodeContainerQr("nasos-5", "Название: с двоеточием; и точкой с запятой", 1, "Фракция:X", []);
  const decoded = decode(qr);
  assert.equal(decoded?.kind, "CONTAINER");
  assert.equal(decoded!.value!.name, "Название: с двоеточием; и точкой с запятой");
  assert.equal(decoded!.value!.ownerFaction, "Фракция:X");
});
