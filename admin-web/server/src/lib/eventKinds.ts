const M = "reason = 'MASTER_OVERRIDE'";

/**
 * Типы событий — те же группы, что цветные маркеры в ленте (humanize.ts,
 * ChangeKind): деньги, предметы, взломы, сигналы СБ, действия мастера, прочее.
 * Считаются по полю и причине записи, поэтому фильтр совпадает с тем, что
 * мастер видит на экране.
 */
export const KIND_SQL: Record<string, string> = {
  money: `(field = 'balance' AND NOT ${M})`,
  item: `(field IN ('daemons.add','daemons.remove','shards.add','shards.remove','shards.decrypt') AND NOT ${M})`,
  breach: `field IN ('counters.breach','counters.blocked')`,
  alert: `field = 'counters.alert'`,
  master: M,
  system: `(field IN ('callsign','faction','ramCapacity') AND NOT ${M})`,
};

/** Подписи типов для фильтров (порядок — порядок в выпадающем списке). */
export const KIND_LABEL_RU: Record<string, string> = {
  money: "Деньги",
  item: "Демоны и шарды",
  breach: "Взломы",
  alert: "Сигналы СБ",
  master: "Действия мастера",
  system: "Профиль (позывной, фракция, RAM)",
};
