// ── Обзор и лента ──

/** Строка таблицы changes как она лежит в БД (snake_case) — так её отдают ручки истории и ленты. */
export interface StoredChangeRow {
  id: string;
  subject_key: string;
  seq: number;
  happened_at: number;
  received_at: number;
  field: string;
  old_value: string | null;
  new_value: string | null;
  reason: string;
  source_ref: string | null;
  actor: string;
  signature: string;
}

export interface Overview {
  players: { online: number; total: number };
  breachesLastHour: { success: number; partial: number; fail: number };
  slots: { claimed: number; printed: number };
  alerts: { sent: number; suppressed: number };
}

export type ChangeKind = "money" | "item" | "breach" | "alert" | "master" | "system" | "net";

/** Человекочитаемая часть записи изменения — собирает сервер (lib/humanize.ts); сырые поля остаются рядом для «деталей». */
export interface HumanChange {
  kind: ChangeKind;
  /** Чья запись (позывной или укороченный ключ). */
  subject: string;
  /** Что произошло, без подлежащего — для истории игрока; в ленте перед ним ставится subject. */
  body: string;
}

export type ChangeRow = StoredChangeRow & { human?: HumanChange };

export interface EventsResponse {
  total: number;
  page: number;
  pageSize: number;
  records: ChangeRow[];
}

export interface Meta {
  reasons: { code: string; label: string }[];
  kinds: { code: string; label: string }[];
}
