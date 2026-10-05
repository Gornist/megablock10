const FIELDS = [
  "balance",
  "ramCapacity",
  "callsign",
  "faction",
  "daemons.add",
  "daemons.remove",
  "shards.add",
  "shards.remove",
  "shards.decrypt",
  "counters.breach",
  "counters.alert",
  "counters.blocked",
  // Записи мира («Сеть», docs/netrun-world-records.md): субъект и автор — ключ мира, а не игрок. В свёртку персонажей не входят.
  "net.run",
  "net.item",
  "net.alert",
  "net.breach",
] as const;
export type Field = (typeof FIELDS)[number];

export const REASONS = [
  "CHARACTER_CREATED",
  "BREACH_ATTEMPT",
  "BREACH_BLOCKED",
  "BREACH_LOOT",
  "BREACH_EDDIES",
  "SHARD_SCAN",
  "SHARD_DECRYPT",
  "TRANSFER_OUT",
  "TRANSFER_IN",
  "TRANSFER_CANCELLED",
  "ITEM_TRANSFER_OUT",
  "ITEM_TRANSFER_IN",
  "ITEM_TRANSFER_CANCELLED",
  "RAM_UPGRADE",
  "ALERT_SENT",
  "ALERT_SUPPRESSED",
  "MASTER_OVERRIDE",
  "CHARACTER_RESET",
  "NET_ENTER",
  "NET_EXIT",
  "NET_FLATLINE",
  "NET_ITEM_OWNER",
  "NET_ALERT",
  "NET_BREACH",
] as const;
export type Reason = (typeof REASONS)[number];

/**
 * Запись, как её присылает устройство — сырой JSON из тела запроса, ещё не
 * провалидированный. oldValue/newValue — уже готовая строка (число, короткий
 * текст или JSON.stringify сложного значения), которую сформировало и
 * подписало устройство. Сервер НЕ пересобирает эту строку заново из
 * структурированных данных — берёт байты как есть, иначе подпись не сойдётся
 * из-за расхождений между JSON-сериализаторами Kotlin и JS (порядок ключей,
 * форматирование чисел и т.п.) — та же логика, что у ClaimProtocol.encode.
 */
export interface ChangeRecordInput {
  id: string;
  subjectKeyB64: string;
  seq: number;
  happenedAt: number;
  field: string;
  oldValue: string | null;
  newValue: string | null;
  reason: string;
  sourceRef?: string | null;
  actor: string;
  signature: string;
}

/** Та же запись, уже провалидированная и приведённая к строгим типам полей/причин. */
interface ChangeRecord extends ChangeRecordInput {
  field: Field;
  reason: Reason;
}

import type { StoredChangeRow } from "../apiTypes.js";

export type { StoredChangeRow };

/**
 * Байты, которые подписывает отправитель — pipe-разделённая строка из полей
 * ровно в том виде, в каком они пришли по проводу (см. комментарий у
 * ChangeRecordInput). Формат сознательно такой же плоский, как у
 * ClaimProtocol.signaturePayload в Android-клиенте, а не JSON — чтобы не
 * зависеть от совпадения сериализаторов на двух платформах.
 */
export function signaturePayload(r: ChangeRecordInput): Buffer {
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

export function isField(v: string): v is Field {
  return (FIELDS as readonly string[]).includes(v);
}

/**
 * Запись мира (Мост «Сети»), а не игрока: поле начинается с «net.». Свёртка персонажей, списки игроков, сводки и проверки
 * целостности их не видят — иначе ключ мира появился бы среди «игроков» с нулевым балансом.
 */
export function isWorldField(field: string): boolean {
  return field.startsWith("net.");
}

/** Условие SQL «это запись игрока» — для запросов по changes, которые считают игроков, а не события вообще. alias — псевдоним таблицы. */
export function notWorldSql(alias?: string): string {
  return `${alias ? `${alias}.` : ""}field NOT LIKE 'net.%'`;
}

export function isReason(v: string): v is Reason {
  return (REASONS as readonly string[]).includes(v);
}
