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
       WHERE delivered = 0 AND failed_at IS NULL AND created_at < ? GROUP BY subject_key`,
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

/** Телефон сообщил, что правку мастера применить не может (или не смог несколько раз подряд): сервер её больше не шлёт — решает мастер. */
export const overrideFailed: AttentionRule = ({ db, inactiveKeys, playerName }) => {
  const rows = db
    .prepare(
      `SELECT mp.subject_key, mp.failed_at, mp.attempts, mp.last_error, c.field, c.new_value
       FROM master_pending mp JOIN changes c ON c.id = mp.change_id
       WHERE mp.delivered = 0 AND mp.failed_at IS NOT NULL ORDER BY mp.failed_at DESC`,
    )
    .all() as { subject_key: string; failed_at: number; attempts: number; last_error: string | null; field: string; new_value: string | null }[];
  const bySubject = new Map<string, typeof rows>();
  for (const r of rows) {
    if (inactiveKeys.has(r.subject_key)) continue;
    bySubject.set(r.subject_key, [...(bySubject.get(r.subject_key) ?? []), r]);
  }
  return [...bySubject].map(([key, list]): AttentionItem => {
    const last = list[0];
    return {
      id: `override_failed:${key}`,
      kind: "override_failed",
      severity: "crit",
      title: "Правка не применилась на телефоне",
      detail: `${playerName(key)}: ${list.length} шт.; последняя — ${last.field} → «${last.new_value ?? ""}»: ${last.last_error ?? "без причины"} (попыток: ${last.attempts})`,
      subjectKey: key,
      at: last.failed_at,
    };
  });
};

/**
 * Один и тот же шард отсканировали с QR несколько игроков — скорее всего, копия напечатанного QR (фото, ксерокс): деньги из шарда
 * зачисляются каждому телефону по разу. Подпись мастера на QR от этого не защищает — копия подписана так же. Считаются только
 * прямые сканы: передача шарда из рук в руки (ITEM_TRANSFER_IN) и лут контейнера с тиражом (BREACH_LOOT) — законные пути.
 */
export const shardCopies: AttentionRule = ({ db, inactiveKeys, playerName }) => {
  const rows = db
    .prepare(
      `SELECT json_extract(new_value, '$.shardId') AS shard_id, MAX(json_extract(new_value, '$.title')) AS title,
              GROUP_CONCAT(DISTINCT subject_key) AS keys, MAX(received_at) AS at
       FROM changes
       WHERE field = 'shards.add' AND reason = 'SHARD_SCAN' AND json_valid(new_value)
       GROUP BY shard_id HAVING COUNT(DISTINCT subject_key) > 1`,
    )
    .all() as { shard_id: string | null; title: string | null; keys: string; at: number }[];
  return rows
    .filter((r) => r.shard_id)
    .map((r) => ({ ...r, active: r.keys.split(",").filter((k) => !inactiveKeys.has(k)) }))
    .filter((r) => r.active.length > 1)
    .map(
      (r): AttentionItem => ({
        id: `shard_copies:${r.shard_id}`,
        kind: "shard_copies",
        severity: "warn",
        title: "Один шард отсканировали несколько игроков",
        detail: `«${r.title ?? r.shard_id}» (${r.shard_id}): ${r.active.length} игроков — ${r.active.map(playerName).join(", ")}. Копия QR?`,
        at: r.at,
      }),
    );
};
