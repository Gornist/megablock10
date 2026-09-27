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
  DISPLAY_CREATE: { label: "Дисплей добавлен", describe: (d) => `дисплей ${str(d.displayId)} «${str(d.name)}», ${str(d.ip)}:${str(d.port)}` },
  DISPLAY_UPDATE: {
    label: "Дисплей изменён",
    describe: (d) =>
      `дисплей ${str(d.displayId)} «${str(d.name)}», ${str(d.ip)}:${str(d.port)}${d.nodeId ? `, узел ${str(d.nodeId)}` : ""}${d.enabled === false ? ", выключен" : ""}`,
  },
  DISPLAY_DELETE: { label: "Дисплей удалён", describe: (d) => `дисплей ${str(d.displayId)} удалён` },
  DISPLAY_GROUP_CREATE: { label: "Группа дисплеев создана", describe: (d) => `группа «${str(d.name)}»` },
  DISPLAY_GROUP_RENAME: { label: "Группа дисплеев переименована", describe: (d) => `«${str(d.from)}» → «${str(d.name)}»` },
  DISPLAY_GROUP_DELETE: { label: "Группа дисплеев удалена", describe: (d) => `группа «${str(d.name)}» удалена, её дисплеи — без группы` },
  DISPLAY_SET_NODE: { label: "Точка на узле", describe: (d) => `точка ${str(d.displayId)} → ${d.nodeId ? `узел ${str(d.nodeId)}` : "без узла"}` },
  DISPLAY_SET_GROUP: { label: "Дисплей в группу", describe: (d) => `дисплей ${str(d.displayId)} → ${d.groupId ? `группа ${str(d.groupId)}` : "без группы"}` },
  DISPLAY_SECRET: { label: "Секрет дисплея сменён", describe: (d) => `дисплей ${str(d.displayId)}: новый секрет, нужно прошить заново` },
  DISPLAY_PUSH: { label: "QR на дисплей", describe: (d) => `${str(d.label)} → ${str(d.displays)}` },
  DISPLAY_COMMAND: {
    label: "Команда дисплею",
    describe: (d) => `дисплей ${str(d.displayId)}: ${str(d.command)}${d.level ? ` ${str(d.level)}` : ""}`,
  },
  AUDIO_CHANNEL_CREATE: { label: "Звуковой канал создан", describe: (d) => `канал «${str(d.name)}», треков: ${str(d.tracks)}` },
  AUDIO_CHANNEL_UPDATE: { label: "Звуковой канал изменён", describe: (d) => `канал «${str(d.name)}», треков: ${str(d.tracks)}` },
  AUDIO_CHANNEL_DELETE: { label: "Звуковой канал удалён", describe: (d) => `канал «${str(d.name)}» удалён, его точки — в тишине` },
  AUDIO_GROUP: {
    label: "Фон группы",
    describe: (d) => `группа «${str(d.name)}»: ${d.channel ? `канал «${str(d.channel)}»` : "тишина"}${d.volume != null ? `, громкость ${str(d.volume)}` : ""}`,
  },
  AUDIO_POINT: {
    label: "Фон точки",
    describe: (d) =>
      `точка ${str(d.displayId)}: ${d.channel === null ? "как у группы" : d.channel === "" ? "тишина" : `канал «${str(d.channel)}»`}${d.volume != null ? `, громкость ${str(d.volume)}` : ""}`,
  },
  AUDIO_CLIP_SAVE: { label: "Клип громкой связи", describe: (d) => `«${str(d.name)}», ${Math.round(Number(d.durationMs) / 100) / 10} с${d.preset ? ", заготовка" : ""}` },
  AUDIO_CLIP_DELETE: { label: "Клип удалён", describe: (d) => `«${str(d.name)}»` },
  AUDIO_ANNOUNCE: {
    label: "Объявление",
    describe: (d) => `«${str(d.clip)}» → точек: ${str(d.points)}${Number(d.skipped) > 0 ? `, пропущено: ${str(d.skipped)}` : ""}`,
  },
  AUDIO_ANNOUNCE_STOP: { label: "Объявление остановлено", describe: (d) => `точек: ${str(d.points)}` },
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
