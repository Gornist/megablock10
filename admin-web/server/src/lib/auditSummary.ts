/** Названия действий мастеров для фильтра и подписей журнала. */
export const AUDIT_ACTION_LABEL_RU: Record<string, string> = {
  PLAYER_OVERRIDE: "Правка игрока",
  BULK_OVERRIDE: "Массовая правка",
  ANNOUNCEMENT: "Объявление",
  SLOT_REVOKE: "Аннулирование слота",
  SLOT_RESTORE: "Возврат слота в оборот",
  MASTER_CREATED: "Создан мастер",
  CONTAINER_CREATED: "Создан контейнер",
  QR_SHARD: "QR шарда",
  QR_RAM: "QR апгрейда RAM",
};

const FIELD_RU: Record<string, string> = { balance: "баланс", ramCapacity: "буфер RAM", callsign: "позывной", faction: "фракция" };

type Detail = Record<string, unknown> | null;

const str = (v: unknown, fallback = "?") => (typeof v === "string" && v !== "" ? v : typeof v === "number" ? String(v) : fallback);

/** Фраза для журнала: что именно сделал мастер. playerName превращает ключ игрока в позывной. */
export function describeAudit(action: string, detail: Detail, playerName: (key: string) => string): string {
  const d = detail ?? {};
  switch (action) {
    case "PLAYER_OVERRIDE": {
      const field = FIELD_RU[str(d.field, "")] ?? str(d.field);
      const delta = d.mode === "add" ? " (дельта)" : "";
      return `${playerName(str(d.subjectKey, ""))}: ${field} ${str(d.oldValue, "∅")} → ${str(d.newValue, "∅")}${delta}. Основание: ${str(d.justification, "не указано")}`;
    }
    case "BULK_OVERRIDE": {
      const field = FIELD_RU[str(d.field, "")] ?? str(d.field);
      const how = d.mode === "add" ? `${Number(d.newValue) >= 0 ? "+" : ""}${str(d.newValue)}` : `= ${str(d.newValue)}`;
      return `${str(d.target, "игроки")} (${str(d.count, "0")} чел.): ${field} ${how}. Основание: ${str(d.justification, "не указано")}`;
    }
    case "ANNOUNCEMENT":
      return `«${str(d.text)}» → ${str(d.target, "игроки")} (${str(d.count, "0")} чел.)`;
    case "SLOT_REVOKE":
      return `слот ${str(d.slotRef)} аннулирован у ${playerName(str(d.claimantKeyB64, ""))}${d.reason ? `. Причина: ${str(d.reason)}` : ""}`;
    case "SLOT_RESTORE":
      return `слот ${str(d.slotRef)} возвращён в оборот`;
    case "MASTER_CREATED":
      return `создан мастер «${str(d.name)}»`;
    case "CONTAINER_CREATED":
      return `контейнер «${str(d.name)}» (${str(d.containerId)}), тир ${str(d.tier)}, фракция ${str(d.ownerFaction)}, слотов: ${str(d.slots, "0")}`;
    case "QR_SHARD":
      return `шард «${str(d.title)}» (${str(d.shardId)})`;
    case "QR_RAM":
      return `токен ${str(d.token)}: +${str(d.delta)} к буферу`;
    default:
      return action;
  }
}
