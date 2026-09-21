type Detail = Record<string, unknown> | null;
type Describe = (d: Record<string, unknown>, playerName: (key: string) => string) => string;

const FIELD_RU: Record<string, string> = { balance: "баланс", ramCapacity: "буфер RAM", callsign: "позывной", faction: "фракция" };

const str = (v: unknown, fallback = "?") => (typeof v === "string" && v !== "" ? v : typeof v === "number" ? String(v) : fallback);

const fieldRu = (d: Record<string, unknown>) => FIELD_RU[str(d.field, "")] ?? str(d.field);
const provisionTail = (d: Record<string, unknown>) =>
  `${d.faction ? ` (${str(d.faction)})` : ""}, баланс ${str(d.balance, "0")}, RAM ${Number(d.ram) ? str(d.ram) : "по умолчанию"}`;

/**
 * Действия мастеров в журнале: название для фильтра и фраза «что именно сделал мастер». Одно место на действие — добавить новое
 * значит добавить одну запись сюда (раньше подпись и фраза жили в разных местах).
 */
const AUDIT_ACTIONS: Record<string, { label: string; describe: Describe }> = {
  PLAYER_OVERRIDE: {
    label: "Правка игрока",
    describe: (d, playerName) =>
      `${playerName(str(d.subjectKey, ""))}: ${fieldRu(d)} ${str(d.oldValue, "∅")} → ${str(d.newValue, "∅")}${d.mode === "add" ? " (дельта)" : ""}. Основание: ${str(d.justification, "не указано")}`,
  },
  BULK_OVERRIDE: {
    label: "Массовая правка",
    describe: (d) => {
      const how = d.mode === "add" ? `${Number(d.newValue) >= 0 ? "+" : ""}${str(d.newValue)}` : `= ${str(d.newValue)}`;
      return `${str(d.target, "игроки")} (${str(d.count, "0")} чел.): ${fieldRu(d)} ${how}. Основание: ${str(d.justification, "не указано")}`;
    },
  },
  ANNOUNCEMENT: { label: "Объявление", describe: (d) => `«${str(d.text)}» → ${str(d.target, "игроки")} (${str(d.count, "0")} чел.)` },
  SLOT_REVOKE: {
    label: "Аннулирование слота",
    describe: (d, playerName) => `слот ${str(d.slotRef)} аннулирован у ${playerName(str(d.claimantKeyB64, ""))}${d.reason ? `. Причина: ${str(d.reason)}` : ""}`,
  },
  SLOT_RESTORE: { label: "Возврат слота в оборот", describe: (d) => `слот ${str(d.slotRef)} возвращён в оборот` },
  MASTER_CREATED: { label: "Создан мастер", describe: (d) => `создан мастер «${str(d.name)}»` },
  CONTAINER_CREATED: {
    label: "Создан контейнер",
    describe: (d) => `контейнер «${str(d.name)}» (${str(d.containerId)}), тир ${str(d.tier)}, фракция ${str(d.ownerFaction)}, слотов: ${str(d.slots, "0")}`,
  },
  QR_SHARD: { label: "QR шарда", describe: (d) => `шард «${str(d.title)}» (${str(d.shardId)})` },
  QR_RAM: { label: "QR апгрейда RAM", describe: (d) => `токен ${str(d.token)}: +${str(d.delta)} к буферу` },
  ATTENTION_SNOOZE: { label: "Тревога отложена", describe: (d) => `«${str(d.title, str(d.id))}» отложена на ${str(d.minutes)} мин` },
  PROVISION_CREATE: { label: "QR персонажа", describe: (d) => `QR персонажа «${str(d.callsign)}»${provisionTail(d)}` },
  PROVISION_REISSUE: {
    label: "Персонаж выдан заново",
    describe: (d, playerName) => `${playerName(str(d.subjectKey, ""))}: выдан заново как «${str(d.callsign)}»${provisionTail(d)}`,
  },
};

/** Названия действий мастеров для фильтра и подписей журнала. */
export const AUDIT_ACTION_LABEL_RU: Record<string, string> = Object.fromEntries(Object.entries(AUDIT_ACTIONS).map(([k, v]) => [k, v.label]));

/** Фраза для журнала: что именно сделал мастер. playerName превращает ключ игрока в позывной. Неизвестное действие — его код. */
export function describeAudit(action: string, detail: Detail, playerName: (key: string) => string): string {
  return AUDIT_ACTIONS[action]?.describe(detail ?? {}, playerName) ?? action;
}
