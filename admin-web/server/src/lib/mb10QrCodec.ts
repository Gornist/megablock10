/**
 * Зеркало object Mb10QrCodec в app/src/main/java/com/megablok10/app/qr/Mb10Qr.kt
 * — только кодирование (декодировать эти QR должен только телефон игрока,
 * серверу это не нужно). Формат ':'-разделённый, свободный текст в base64.
 */
const MAGIC = "MB10";

function b64(text: string): string {
  return Buffer.from(text, "utf8").toString("base64");
}

export interface ContainerSlotForQr {
  typeName: "SHARD" | "DAEMON";
  tierLevel: number;
  copies: number;
  payload: string; // уже зашифрованный LootCodec-блок, см. lootCrypto.ts
}

export function encodeContainerQr(id: string, name: string, tierLevel: number, ownerFaction: string, slots: ContainerSlotForQr[]): string {
  const loot = slots.map((s) => `${s.typeName},${s.tierLevel},${s.copies},${s.payload}`).join(";");
  return `${MAGIC}:CONTAINER:v1:${id}:${b64(name)}:${tierLevel}:${b64(ownerFaction)}:${b64(loot)}`;
}

export function encodeShardQr(
  id: string,
  decryptAction: boolean,
  tierLevel: number,
  valueHint: string,
  title: string,
  meta: string,
  body: string,
  moneyAmount: number,
): string {
  return `${MAGIC}:SHARD:v1:${id}:${decryptAction ? 1 : 0}:${tierLevel}:${b64(valueHint)}:${b64(title)}:${b64(meta)}:${b64(body)}:${moneyAmount}`;
}

export function encodeRamUpgradeQr(token: string, delta: number): string {
  return `${MAGIC}:RAM:v1:${token}:${delta}`;
}

/** QR персонажа: первый запуск одним кодом (docs/provisioning-qr.md). Пустые url/secret — приложение оставляет свои. */
export function encodeProvisionQr(p: { id: string; url: string; secret: string; callsign: string; faction: string; balance: number; ram: number }): string {
  return `${MAGIC}:PROV:v1:${p.id}:${b64(p.url)}:${b64(p.secret)}:${b64(p.callsign)}:${b64(p.faction)}:${p.balance}:${p.ram}`;
}
