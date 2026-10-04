// ── Аналитика и подсказки ──

export type Severity = "crit" | "warn" | "info";

export interface AttentionItem {
  id: string;
  kind: "negative_balance" | "balance_jump" | "went_silent" | "node_exhausted_hot" | "revoke_repeat" | "override_undelivered" | "override_failed" | "shard_copies" | "transfer_stuck" | "duplicate_receive" | "balance_chain_break" | "balance_unexplained" | "old_version" | "mass_silence" | "reject_spike" | "rate_limited" | "secret_denied" | "server_slow" | "clock_skew" | "transfer_amount_mismatch" | "emission_spike" | "player_outlier" | "provision_conflict" | "sync_stuck" | "display_battery" | "net_flatline" | "net_alert" | "net_master_alert";
  severity: Severity;
  title: string;
  detail: string;
  subjectKey?: string;
  nodeId?: string;
  /** Тревога про точку (QR-дисплей, звук): без nodeId ссылка ведёт на «Локации». */
  displayId?: string;
  at: number;
}

export interface Attention {
  items: AttentionItem[];
  /** Сколько тревог сейчас отложено мастером (в items их нет). */
  snoozed: number;
  counts: { crit: number; warn: number; info: number };
}

export interface Economy {
  totalSupply: number;
  playersCounted: number;
  series: { t: number; supply: number }[];
  sources: { reason: string; label: string; total: number }[];
  transferVolume: number;
  distribution: { mean: number; median: number; p90: number; gini: number; negative: number };
  top: { publicKeyB64: string; callsign: string; faction: string; balance: number }[];
}

export interface FactionEvents {
  breachesOwn: number;
  breachesForeign: number;
  alertsSent: number;
  alertsSuppressed: number;
  alertsReceived: number;
}

export interface FactionRow extends FactionEvents {
  faction: string;
  players: number;
  online: number;
  totalBalance: number;
  avgBalance: number;
  daemons: number;
  shards: number;
  breaches: { success: number; partial: number; fail: number };
  slotsClaimed: number;
}
