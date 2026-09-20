import type { Db } from "../db/index.js";
import { REASON_LABEL_RU, makeHumanizeContext } from "./humanize.js";
import { parseSafe } from "./json.js";
import { lastPresence } from "./presence.js";
import { ONLINE_WINDOW_MS, getPlayerBase, seenAt } from "./playerSummary.js";
import { breachesLastHourByNode, getNodeSummaries } from "./nodeSummary.js";

import type { AttentionItem, Severity } from "../apiTypes.js";

export type { AttentionItem, Severity };

const MIN = 60 * 1000;
const SEVERITY_ORDER: Record<Severity, number> = { crit: 0, warn: 1, info: 2 };

/** Пороги — не «истина», а стартовые значения под типичную экономику; правятся переменными окружения без пересборки. */
export function thresholds() {
  const num = (v: string | undefined, d: number) => (v !== undefined && Number.isFinite(Number(v)) && Number(v) > 0 ? Number(v) : d);
  return {
    balanceJump: num(process.env.ATTN_BALANCE_JUMP, 1000),
    silentAfterMs: num(process.env.ATTN_SILENT_MIN, 10) * MIN,
    silentUntilMs: num(process.env.ATTN_SILENT_MAX_MIN, 180) * MIN,
    undeliveredAfterMs: num(process.env.ATTN_UNDELIVERED_MIN, 2) * MIN,
  };
}

const num = (v: string | null) => Number(v ?? 0);

/**
 * Автоподсказки мастеру: что на площадке выглядит неправильно. Каждое правило
 * — дешёвый запрос по уже существующим данным; ничего не пишется и не
 * решается за мастера — только «обрати внимание», с ссылкой на игрока/узел.
 */
export function computeAttention(db: Db, now = Date.now()): AttentionItem[] {
  const t = thresholds();
  const players = getPlayerBase(db);
  const ctx = makeHumanizeContext(db);
  const items: AttentionItem[] = [];

  // 1. Отрицательный баланс — признак бага/дыры (раньше именно так нашли печать денег через овердрафт).
  for (const p of players) {
    if (p.balance < 0) {
      items.push({
        id: `negative:${p.publicKeyB64}`,
        kind: "negative_balance",
        severity: "crit",
        title: "Отрицательный баланс",
        detail: `${p.callsign || ctx.playerName(p.publicKeyB64)}: ${p.balance} €$`,
        subjectKey: p.publicKeyB64,
        at: seenAt(p),
      });
    }
  }

  // 2. Крупное поступление за последний час (кроме мастерских правок — их мастер сделал сам).
  const jumpRows = db
    .prepare(
      `SELECT id, subject_key, received_at, reason, old_value, new_value FROM changes
       WHERE field = 'balance' AND received_at > ? AND reason IN ('BREACH_EDDIES', 'SHARD_SCAN', 'BREACH_LOOT', 'TRANSFER_IN')`,
    )
    .all(now - 60 * MIN) as { id: string; subject_key: string; received_at: number; reason: string; old_value: string | null; new_value: string | null }[];
  for (const r of jumpRows) {
    const delta = num(r.new_value) - num(r.old_value);
    if (delta < t.balanceJump) continue;
    items.push({
      id: `jump:${r.id}`,
      kind: "balance_jump",
      severity: "warn",
      title: "Крупное поступление",
      detail: `${ctx.playerName(r.subject_key)}: +${delta} €$ (${REASON_LABEL_RU[r.reason] ?? r.reason})`,
      subjectKey: r.subject_key,
      at: r.received_at,
    });
  }

  // 3. Пропал со связи: раньше был активен, сейчас молчит дольше порога (но не «ушёл домой» — верхняя граница).
  for (const p of players) {
    const age = now - seenAt(p);
    if (age >= t.silentAfterMs && age <= t.silentUntilMs) {
      const mins = Math.round(age / MIN);
      items.push({
        id: `silent:${p.publicKeyB64}`,
        kind: "went_silent",
        severity: age > 30 * MIN ? "warn" : "info",
        title: "Пропал со связи",
        detail: `${p.callsign || ctx.playerName(p.publicKeyB64)}: нет связи ${mins} мин`,
        subjectKey: p.publicKeyB64,
        at: seenAt(p),
      });
    }
  }

  // 4. Тираж узла исчерпан, а его всё равно ломают — игроки тратят время впустую или ищут обход.
  const hot = breachesLastHourByNode(db, now);
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

  // 5. Слот аннулируют повторно — спор о лоте, стоит разобраться.
  const revokes = db.prepare(`SELECT detail, at FROM audit_master WHERE action = 'SLOT_REVOKE'`).all() as { detail: string | null; at: number }[];
  const bySlot = new Map<string, { n: number; at: number }>();
  for (const r of revokes) {
    const slotRef = parseSafe<{ slotRef?: string }>(r.detail)?.slotRef;
    if (!slotRef) continue;
    const e = bySlot.get(slotRef) ?? { n: 0, at: 0 };
    bySlot.set(slotRef, { n: e.n + 1, at: Math.max(e.at, r.at) });
  }
  for (const [slotRef, e] of bySlot) {
    if (e.n >= 2) {
      items.push({
        id: `revoke:${slotRef}`,
        kind: "revoke_repeat",
        severity: "info",
        title: "Слот аннулировали повторно",
        detail: `${slotRef}: ${e.n} раза`,
        at: e.at,
      });
    }
  }

  // 6. Правка/сообщение мастера не дошло до игрока. Если телефон при этом на связи — хуже: применение не проходит.
  const undelivered = db
    .prepare(
      `SELECT subject_key, COUNT(*) AS n, MIN(created_at) AS oldest FROM master_pending
       WHERE delivered = 0 AND created_at < ? GROUP BY subject_key`,
    )
    .all(now - t.undeliveredAfterMs) as { subject_key: string; n: number; oldest: number }[];
  for (const r of undelivered) {
    const online = now - lastPresence(r.subject_key) < ONLINE_WINDOW_MS;
    items.push({
      id: `undelivered:${r.subject_key}`,
      kind: "override_undelivered",
      severity: online ? "crit" : "warn",
      title: online ? "Правка не применяется на устройстве" : "Правка ждёт игрока",
      detail: `${ctx.playerName(r.subject_key)}: не доставлено ${r.n} шт., старейшая — ${Math.round((now - r.oldest) / MIN)} мин${online ? " (телефон на связи!)" : ""}`,
      subjectKey: r.subject_key,
      at: r.oldest,
    });
  }

  return items.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || b.at - a.at);
}
