export const FIELDS = [
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

/**
 * Одна строка на причину записи — всё, что коллектор о ней знает: подпись для дашборда и три признака, по которым раньше стояли отдельные
 * списки в integrity/anomalies/pulse/analytics (копии расходились: забытая причина давала ложные «необъяснимые скачки» или занижала метрики).
 * Новая причина добавляется ТОЛЬКО здесь, все четыре поля обязательны — компилятор не даст забыть. Порядок строк = порядок в REASONS и
 * в фильтрах дашборда. Kotlin-копия (ChangeFields.kt, WorldRecordDeriver.kt) сверяется общими векторами change-record.json.
 */
export interface ReasonInfo {
  /** Подпись в фильтрах и ленте. */
  label: string;
  /** Баланс по этой причине законно растёт (награда, получение перевода, возврат, старт/сброс, правка мастера) — иначе скачок «необъяснимый». */
  gainsBalance: boolean;
  /** Награда за игру: входит в «эдди за интервал» пульса и в сравнение выбросов. */
  reward: boolean;
  /** Деньги лишь переезжают между игроками — не источник эмиссии. */
  transfer: boolean;
}

const reason = (label: string, flags: Partial<Omit<ReasonInfo, "label">> = {}): ReasonInfo => ({ label, gainsBalance: false, reward: false, transfer: false, ...flags });

export const REASON_INFO = {
  CHARACTER_CREATED: reason("Создание персонажа", { gainsBalance: true }),
  BREACH_ATTEMPT: reason("Попытка взлома"),
  BREACH_BLOCKED: reason("Взлом отклонён"),
  BREACH_LOOT: reason("Добыча с узла", { gainsBalance: true, reward: true }),
  BREACH_EDDIES: reason("Эдди за взлом", { gainsBalance: true, reward: true }),
  SHARD_SCAN: reason("Скан шарда", { gainsBalance: true, reward: true }),
  SHARD_DECRYPT: reason("Расшифровка шарда"),
  TRANSFER_OUT: reason("Перевод (отправка)", { transfer: true }),
  TRANSFER_IN: reason("Перевод (получение)", { gainsBalance: true, transfer: true }),
  TRANSFER_CANCELLED: reason("Перевод отменён", { gainsBalance: true, transfer: true }),
  ITEM_TRANSFER_OUT: reason("Передача предмета (отправка)"),
  ITEM_TRANSFER_IN: reason("Передача предмета (получение)"),
  ITEM_TRANSFER_CANCELLED: reason("Передача предмета отменена"),
  RAM_UPGRADE: reason("Улучшение RAM"),
  ALERT_SENT: reason("Сигнал СБ отправлен"),
  ALERT_SUPPRESSED: reason("Сигнал СБ подавлен"),
  MASTER_OVERRIDE: reason("Правка мастера", { gainsBalance: true }),
  CHARACTER_RESET: reason("Сброс персонажа", { gainsBalance: true }),
  NET_ENTER: reason("Сеть: вход"),
  NET_EXIT: reason("Сеть: выход"),
  NET_FLATLINE: reason("Сеть: флэтлайн"),
  NET_ITEM_OWNER: reason("Сеть: предмет сменил владельца"),
  NET_ALERT: reason("Сеть: тревога аудитора"),
  NET_BREACH: reason("Сеть: взлом хранилища"),
} satisfies Record<string, ReasonInfo>;
export type Reason = keyof typeof REASON_INFO;
export const REASONS = Object.keys(REASON_INFO) as Reason[];

/** Строка таблицы по коду причины из записи; null — код неизвестен (запись старой или чужой версии). */
export function reasonInfo(code: string): ReasonInfo | null {
  return Object.hasOwn(REASON_INFO, code) ? REASON_INFO[code as Reason] : null;
}

/** Список наград для SQL `reason IN (…)`: `'BREACH_LOOT','BREACH_EDDIES','SHARD_SCAN'`. Коды — наши константы, не ввод. */
export function rewardReasonsSql(): string {
  return REASONS.filter((code) => REASON_INFO[code].reward)
    .map((code) => `'${code}'`)
    .join(",");
}

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
