import type { AttentionItem } from "../../apiTypes.js";
import { REASON_LABEL_RU } from "../humanize.js";
import { parseSafe } from "../json.js";
import { breachesLastHourByNode, getNodeSummaries } from "../nodeSummary.js";
import { seenAt, ONLINE_WINDOW_MS } from "../playerSummary.js";
import { lastPresence } from "../presence.js";
import { MIN, type AttentionRule } from "./context.js";

const num = (v: string | null) => Number(v ?? 0);

/** Отрицательный баланс — признак бага/дыры (раньше именно так нашли печать денег через овердрафт). */
export const negativeBalance: AttentionRule = ({ players, playerName }) =>
  players
    .filter((p) => p.balance < 0)
    .map(
      (p): AttentionItem => ({
        id: `negative:${p.publicKeyB64}`,
        kind: "negative_balance",
        severity: "crit",
        title: "Отрицательный баланс",
        detail: `${p.callsign || playerName(p.publicKeyB64)}: ${p.balance} €$`,
        subjectKey: p.publicKeyB64,
        at: seenAt(p),
      }),
    );

/** Крупное поступление за последний час (кроме мастерских правок — их мастер сделал сам). */
export const balanceJump: AttentionRule = ({ db, now, t, playerName }) => {
  const rows = db
    .prepare(
      `SELECT id, subject_key, received_at, reason, old_value, new_value FROM changes
       WHERE field = 'balance' AND received_at > ? AND reason IN ('BREACH_EDDIES', 'SHARD_SCAN', 'BREACH_LOOT', 'TRANSFER_IN')`,
    )
    .all(now - 60 * MIN) as { id: string; subject_key: string; received_at: number; reason: string; old_value: string | null; new_value: string | null }[];
  const items: AttentionItem[] = [];
  for (const r of rows) {
    const delta = num(r.new_value) - num(r.old_value);
    if (delta < t.balanceJump) continue;
    items.push({
      id: `jump:${r.id}`,
      kind: "balance_jump",
      severity: "warn",
      title: "Крупное поступление",
      detail: `${playerName(r.subject_key)}: +${delta} €$ (${REASON_LABEL_RU[r.reason] ?? r.reason})`,
      subjectKey: r.subject_key,
      at: r.received_at,
    });
  }
  return items;
};

/** Пропал со связи: раньше был активен, сейчас молчит дольше порога (но не «ушёл домой» — верхняя граница). */
export const wentSilent: AttentionRule = ({ players, now, t, playerName }) => {
  const items: AttentionItem[] = [];
  for (const p of players) {
    const age = now - seenAt(p);
    if (age < t.silentAfterMs || age > t.silentUntilMs) continue;
    items.push({
      id: `silent:${p.publicKeyB64}`,
      kind: "went_silent",
      severity: age > 30 * MIN ? "warn" : "info",
      title: "Пропал со связи",
      detail: `${p.callsign || playerName(p.publicKeyB64)}: нет связи ${Math.round(age / MIN)} мин`,
      subjectKey: p.publicKeyB64,
      at: seenAt(p),
    });
  }
  return items;
};

/** Тираж узла исчерпан, а его всё равно ломают — игроки тратят время впустую или ищут обход. */
export const nodeExhaustedHot: AttentionRule = ({ db, now }) => {
  const hot = breachesLastHourByNode(db, now);
  const items: AttentionItem[] = [];
  for (const n of getNodeSummaries(db)) {
    const attempts = hot.get(n.id) ?? 0;
    if (n.slotsTotal > 0 && n.slotsClaimed >= n.slotsTotal && attempts > 0) {
      items.push({
        id: `exhausted:${n.id}`,
        kind: "node_exhausted_hot",
        severity: "warn",
        title: "Узел исчерпан, но его ломают",
        detail: `«${n.name}»: тираж ${n.slotsClaimed}/${n.slotsTotal}, взломов за час: ${attempts}`,
        nodeId: n.id,
        at: n.lastBreachAt ?? now,
      });
    }
  }
  return items;
};

/** Слот аннулируют повторно — спор о лоте, стоит разобраться. */
export const repeatedRevoke: AttentionRule = ({ db }) => {
  const revokes = db.prepare(`SELECT detail, at FROM audit_master WHERE action = 'SLOT_REVOKE'`).all() as { detail: string | null; at: number }[];
  const bySlot = new Map<string, { n: number; at: number }>();
  for (const r of revokes) {
    const slotRef = parseSafe<{ slotRef?: string }>(r.detail)?.slotRef;
    if (!slotRef) continue;
    const e = bySlot.get(slotRef) ?? { n: 0, at: 0 };
    bySlot.set(slotRef, { n: e.n + 1, at: Math.max(e.at, r.at) });
  }
  return [...bySlot]
    .filter(([, e]) => e.n >= 2)
    .map(([slotRef, e]): AttentionItem => ({ id: `revoke:${slotRef}`, kind: "revoke_repeat", severity: "info", title: "Слот аннулировали повторно", detail: `${slotRef}: ${e.n} раза`, at: e.at }));
};

/** Правка/сообщение мастера не дошло до игрока. Если телефон при этом на связи — хуже: применение не проходит. */
export const overrideUndelivered: AttentionRule = ({ db, now, t, inactiveKeys, playerName }) => {
  const rows = db
    .prepare(
      `SELECT subject_key, COUNT(*) AS n, MIN(created_at) AS oldest FROM master_pending
       WHERE delivered = 0 AND created_at < ? GROUP BY subject_key`,
    )
    .all(now - t.undeliveredAfterMs) as { subject_key: string; n: number; oldest: number }[];
  const items: AttentionItem[] = [];
  for (const r of rows) {
    if (inactiveKeys.has(r.subject_key)) continue;
    const online = now - lastPresence(r.subject_key) < ONLINE_WINDOW_MS;
    items.push({
      id: `undelivered:${r.subject_key}`,
      kind: "override_undelivered",
      severity: online ? "crit" : "warn",
      title: online ? "Правка не применяется на устройстве" : "Правка ждёт игрока",
      detail: `${playerName(r.subject_key)}: не доставлено ${r.n} шт., старейшая — ${Math.round((now - r.oldest) / MIN)} мин${online ? " (телефон на связи!)" : ""}`,
      subjectKey: r.subject_key,
      at: r.oldest,
    });
  }
  return items;
};
