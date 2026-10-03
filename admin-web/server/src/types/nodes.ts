// ── Узлы и тиражи ──

export interface NodeSummary {
  id: string;
  name: string;
  tier: string;
  ownerFaction: string | null;
  slotsTotal: number;
  slotsClaimed: number;
  breaches: { success: number; partial: number; fail: number };
  uniquePlayers: number;
  alertsSent: number;
  alertsSuppressed: number;
  lastBreachAt: number | null;
  /** Есть только в списке /api/nodes: зависит от текущего времени, поэтому считается поверх кэша. */
  breachesLastHour?: number;
}

export interface NodeDetail extends NodeSummary {
  breachers: { actor: string; lastAt: number; n: number }[];
  timeline: { t: number; success: number; partial: number; fail: number }[];
}

export interface SlotRegistryItem {
  slotRef: string;
  containerId: string;
  containerName: string;
  type: string;
  tier: string;
  title: string;
  copiesTotal: number;
  copiesClaimed: number;
  claimants: { claimantKeyB64: string; claimantName?: string; claimedAt: number }[];
}

export interface Transfer {
  txId: string;
  from: string;
  /** Получатель; null — перевод ещё не подтверждён получателем (в записи отправки его ключа нет). */
  to: string | null;
  fromName?: string;
  toName?: string;
  amount: number;
  sentAt: number | null;
  confirmedAt: number | null;
  cancelledAt: number | null;
  oneSided: boolean;
}
