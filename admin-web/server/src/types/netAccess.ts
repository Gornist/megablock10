// ── «Сеть» (docs/netrun.md): допуск нетраннера ──

/** Флаг допуска нетраннера в Сеть: заблокирован после флэтлайна или мастером; «пощадить» снимает (коллектор — источник правды). */
export interface NetRunnerFlagItem {
  runnerKey: string;
  /** Позывной из записи флэтлайна, а если его нет — из истории игрока. */
  callsign: string;
  blocked: boolean;
  reason: string | null;
  session: string | null;
  node: string | null;
  terminal: string | null;
  /** Подробности флэтлайна (cause, disconnect, left_in_node, alert) — для карточки мастера. */
  detail: Record<string, unknown> | null;
  blockedAt: number | null;
  sparedAt: number | null;
  sparedBy: string | null;
  /** false — Мост ещё не знает об этом решении (догонится при следующем подключении). */
  bridgeSynced: boolean;
  /** Игрок с таким ключом известен коллектору — карточка игрока доступна. */
  knownPlayer: boolean;
  /** Мастер отметил игрока «может входить в Сеть» (белый список). */
  allowed: boolean;
}

/** Допуск игрока в Сеть без блокировки: ответ карточки игрока, когда флага блокировки нет. */
export interface NetRunnerOpen {
  blocked: false;
  allowed: boolean;
}

/** Сводка белого списка: сколько игроков отмечено «нетраннер» — для подтверждения включения проверки в Мосте. */
export interface NetAccessSummary {
  allowedCount: number;
}
