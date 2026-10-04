// ── Журнал и объявления ──

export interface AuditRecord {
  id: string;
  at: number;
  action: string;
  actionLabel: string;
  masterName: string;
  summary: string;
}

export interface AuditResponse {
  total: number;
  page: number;
  pageSize: number;
  actions: { action: string; label: string }[];
  records: AuditRecord[];
}

export interface AnnouncementItem {
  id: string;
  at: number;
  text: string;
  recipients: number;
  delivered: number;
  masterName: string;
}

export interface AnnouncementRecipient {
  publicKeyB64: string;
  callsign: string;
  delivered: boolean;
}

/** Снимок «пульса игры» за интервал (обычно минуту): что происходило на площадке и как чувствовал себя сервер. */
export interface PulseSample {
  t: number;
  online: number;
  /** Принятые записи и heartbeat-запросы за интервал. */
  records: number;
  heartbeats: number;
  /** Отклонённые записи по причинам: signature, malformed, unknown, seq, actor, other. */
  rejected: number;
  rejectedBy: Record<string, number>;
  rateLimited: number;
  secretDenied: number;
  requests: number;
  latencyAvgMs: number;
  latencyMaxMs: number;
  breaches: number;
  /** Выдано эдди наградами (взлом, шард, добыча). */
  eddies: number;
  transfers: number;
  /** Правок мастера, ещё не дошедших до устройств. */
  undelivered: number;
}

export interface Pulse {
  intervalMs: number;
  samples: PulseSample[];
}

/** Выданный QR персонажа. */
export interface ProvisionItem {
  id: string;
  callsign: string;
  faction: string;
  balance: number;
  ram: number;
  createdAt: number;
  createdBy: string;
  /** Ключ прежней сессии, которую этот код заменяет (повторная выдача). */
  replacesKey: string | null;
  replacesName: string | null;
  boundKey: string | null;
  boundName: string | null;
  boundAt: number | null;
  /** Погашен: перевыдан заново (или заменён более новым кодом). */
  void: boolean;
  /** Второй телефон пытался применить этот код. */
  conflicts: number;
}

export interface ProvisionsResponse {
  /** Что попадёт в QR из настроек сервера: адрес (откуда взят) и есть ли код игры. Сам код не отдаётся. */
  config: { url: string; urlSource: "env" | "request" | "none"; secretSet: boolean };
  items: ProvisionItem[];
}

export interface ProvisionQr {
  item: ProvisionItem;
  qr: string;
  qrImage: string;
}
