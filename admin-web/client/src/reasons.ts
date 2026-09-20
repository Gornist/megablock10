/** Названия причин записей на русском — для фильтров и раскрытых «деталей» (коды остаются протокольными). */
export const REASON_LABEL: Record<string, string> = {
  CHARACTER_CREATED: "Создание персонажа",
  CHARACTER_RESET: "Сброс персонажа",
  BREACH_ATTEMPT: "Попытка взлома",
  BREACH_BLOCKED: "Взлом отклонён",
  BREACH_LOOT: "Добыча с узла",
  BREACH_EDDIES: "Эдди за взлом",
  SHARD_SCAN: "Скан шарда",
  SHARD_DECRYPT: "Расшифровка шарда",
  TRANSFER_OUT: "Перевод (отправка)",
  TRANSFER_IN: "Перевод (получение)",
  TRANSFER_CANCELLED: "Перевод отменён",
  ITEM_TRANSFER_OUT: "Передача предмета (отправка)",
  ITEM_TRANSFER_IN: "Передача предмета (получение)",
  ITEM_TRANSFER_CANCELLED: "Передача предмета отменена",
  RAM_UPGRADE: "Улучшение RAM",
  ALERT_SENT: "Сигнал СБ отправлен",
  ALERT_SUPPRESSED: "Сигнал СБ подавлен",
  MASTER_OVERRIDE: "Правка мастера",
};

export const reasonLabel = (code: string) => REASON_LABEL[code] ?? code;
