/**
 * Общие правила ввода предметов — шардов и демонов: их генерирует «Мастерская» (QR для телефонов) и она же наполняет узлы «Сети»
 * (docs/netrun-bridge-protocol.md, master.stock_node). Одни и те же проверки, чтобы предмет, прошедший в одно место, не отказывал в другом.
 */

/**
 * id попадает в QR как есть, а формат — ':'-разделённый (а slotRef дальше собирается через '#'):
 * id вроде "nasos:4" или "a#b" даёт QR, который приложение разбирает со сдвигом полей или не разбирает вовсе.
 */
export const SAFE_ID = /^[A-Za-z0-9_.-]{1,64}$/;

export const DAEMON_EFFECTS = new Set(["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]);
/** Коды демона склеиваются через ',' внутри LootCodec ("|"-формат) — символы-разделители в коде ломают разбор на телефоне. */
export const SAFE_CODE = /^[A-Za-z0-9]{1,8}$/;

/** Деньги в шарде — неотрицательное целое; дробное/отрицательное приложение молча превращало в 0. */
export function moneyOrNull(v: unknown): number | null {
  if (v === undefined || v === null) return 0;
  return Number.isSafeInteger(v) && (v as number) >= 0 ? (v as number) : null;
}
