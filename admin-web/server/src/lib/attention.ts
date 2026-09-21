import type { Db } from "../db/index.js";
import { positiveNumber } from "./envNumber.js";
import { REASON_LABEL_RU, makeHumanizeContext } from "./humanize.js";
import { parseSafe } from "./json.js";
import { lastPresence } from "./presence.js";
import { ONLINE_WINDOW_MS, activePlayers, getPlayerBase, isActivePlayer, seenAt, withOnline } from "./playerSummary.js";
import { breachesLastHourByNode, getNodeSummaries } from "./nodeSummary.js";
import { computeClockAnomalies, computeOutliers, computePulseAnomalies } from "./anomalies.js";
import { provisionConflicts } from "./provisions.js";
import { findUnexplainedJumps, getIntegrityFindings } from "./integrity.js";

import type { AttentionItem, Severity } from "../apiTypes.js";

export type { AttentionItem };

const MIN = 60 * 1000;
const SEVERITY_ORDER: Record<Severity, number> = { crit: 0, warn: 1, info: 2 };

/** Пороги — не «истина», а стартовые значения под типичную экономику; правятся переменными окружения без пересборки. */
function thresholds() {
  return {
    balanceJump: positiveNumber(process.env.ATTN_BALANCE_JUMP, 1000),
    silentAfterMs: positiveNumber(process.env.ATTN_SILENT_MIN, 10) * MIN,
    silentUntilMs: positiveNumber(process.env.ATTN_SILENT_MAX_MIN, 180) * MIN,
    undeliveredAfterMs: positiveNumber(process.env.ATTN_UNDELIVERED_MIN, 2) * MIN,
    transferStuckMs: positiveNumber(process.env.ATTN_TRANSFER_STUCK_MIN, 10) * MIN,
    /** Как давно может быть запись, чтобы проверки целостности о ней ещё напоминали: иначе давний разрыв висел бы всю игру. */
    integrityWindowMs: positiveNumber(process.env.ATTN_INTEGRITY_HOURS, 12) * 60 * MIN,
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
  const everyone = getPlayerBase(db);
  const players = activePlayers(everyone); // заменённые и сбросившие сессию (устройство свободно) тревог «нет связи/минус» не дают
  const inactiveKeys = new Set(everyone.filter((p) => !isActivePlayer(p)).map((p) => p.publicKeyB64));
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
    if (inactiveKeys.has(r.subject_key)) continue;
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

  items.push(...versionItems(withOnline(players, now), ctx.playerName));
  items.push(...computePulseAnomalies(db, now));
  items.push(...computeOutliers(db, ctx.playerName, now));
  items.push(...computeClockAnomalies(db, ctx.playerName, now - t.integrityWindowMs));
  items.push(...integrityItems(db, ctx.playerName, now, t));

  return items.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || b.at - a.at);
}

/** Проверки целостности (lib/integrity.ts): перекрёстные признаки подделки и зависших переводов. */
function integrityItems(db: Db, playerName: (key: string) => string, now: number, t: ReturnType<typeof thresholds>): AttentionItem[] {
  const items: AttentionItem[] = [];
  const found = getIntegrityFindings(db);
  const since = now - t.integrityWindowMs;

  for (const c of provisionConflicts(db)) {
    if (c.at < since) continue;
    items.push({
      id: `provision:${c.provisionId}:${c.key}`,
      kind: "provision_conflict",
      severity: "crit",
      title: "Код персонажа применили на двух телефонах",
      detail: `код «${c.callsign}» (${c.provisionId.slice(0, 8)}) уже у ${c.boundKey ? playerName(c.boundKey) : "другого телефона"}, вторая попытка — ${playerName(c.key)}: копия QR или напечатан дубль`,
      subjectKey: c.key,
      at: c.at,
    });
  }

  for (const d of found.duplicateReceives) {
    if (d.at < since) continue;
    const names = d.subjectKeys.map(playerName).join(", ");
    items.push({
      id: `duplicate:${d.reason}:${d.sourceRef}`,
      kind: "duplicate_receive",
      severity: "crit",
      title: d.reason === "TRANSFER_IN" ? "Один платёж получили двое" : "Один предмет получили двое",
      detail: `${names} (перевод ${d.sourceRef.slice(0, 8)}) — честное приложение так не делает`,
      subjectKey: d.subjectKeys[0],
      at: d.at,
    });
  }

  for (const m of found.amountMismatches) {
    if (m.at < since) continue;
    items.push({
      id: `mismatch:${m.txId}`,
      kind: "transfer_amount_mismatch",
      severity: "crit",
      title: "Сумма перевода не сходится",
      detail: `${playerName(m.fromKey)} → ${playerName(m.toKey)}: списано ${m.sent} €$, получено ${m.received} €$`,
      subjectKey: m.toKey,
      at: m.at,
    });
  }

  for (const j of findUnexplainedJumps(db, since, t.balanceJump)) {
    items.push({
      id: `unexplained:${j.id}`,
      kind: "balance_unexplained",
      severity: "crit",
      title: "Баланс вырос без причины",
      detail: `${playerName(j.subjectKey)}: +${j.delta} €$ по причине «${REASON_LABEL_RU[j.reason] ?? j.reason}», которая денег не даёт`,
      subjectKey: j.subjectKey,
      at: j.at,
    });
  }

  for (const b of found.chainBreaks) {
    if (b.at < since) continue;
    items.push({
      id: `chain:${b.subjectKey}:${b.at}`,
      kind: "balance_chain_break",
      severity: "warn",
      title: "Разрыв цепочки баланса",
      detail: `${playerName(b.subjectKey)}: по журналу было ${b.expected} €$, а запись исходит из ${b.actual} €$${b.count > 1 ? ` (разрывов: ${b.count})` : ""}`,
      subjectKey: b.subjectKey,
      at: b.at,
    });
  }

  for (const u of found.unpairedTransfers) {
    if (now - u.at < t.transferStuckMs) continue;
    const mins = Math.round((now - u.at) / MIN);
    const what = u.kind === "money" ? `платёж${u.amount ? ` ${u.amount} €$` : ""}` : "передача предмета";
    items.push({
      id: `stuck:${u.kind}:${u.txId}:${u.side}`,
      kind: "transfer_stuck",
      severity: "warn",
      title: u.side === "out" ? "Перевод завис: не получен" : "Получение без отправки",
      detail:
        u.side === "out"
          ? `${playerName(u.subjectKey)}: ${what} отправлен ${mins} мин назад, получения и отмены нет. Если получатель не выйдет на связь — поправить баланс/предмет правкой мастера`
          : `${playerName(u.subjectKey)}: ${what} получен ${mins} мин назад, записи отправки нет (телефон отправителя не на связи?)`,
      subjectKey: u.subjectKey,
      at: u.at,
    });
  }

  return items;
}

const versionKey = (p: { appVersion?: string; wireVersions?: Record<string, number> }) =>
  `${p.appVersion ?? "?"} ${Object.entries(p.wireVersions ?? {}).sort().map(([k, v]) => `${k}${v}`).join(",")}`.trim();

/**
 * Игроки на связи с сборкой, отличной от той, что у большинства: старый APK не понимает новый протокол (чат/звонки/заявки
 * проверяют версию), так что такому игроку нужно обновить приложение. Считаем, только когда у большинства (>50%) версия одна —
 * иначе «эталона» нет, и подсказка была бы шумом.
 */
function versionItems(players: ReturnType<typeof withOnline>, playerName: (key: string) => string): AttentionItem[] {
  const reporting = players.filter((p) => p.online && (p.appVersion || p.wireVersions));
  if (reporting.length < 3) return [];
  const counts = new Map<string, number>();
  for (const p of reporting) counts.set(versionKey(p), (counts.get(versionKey(p)) ?? 0) + 1);
  const [majorityKey, majorityCount] = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
  if (majorityCount * 2 <= reporting.length) return [];

  const wireOf = (key: string) => key.slice(key.indexOf(" ") + 1);
  return reporting
    .filter((p) => versionKey(p) !== majorityKey)
    .map((p): AttentionItem => {
      const protocolDiffers = wireOf(versionKey(p)) !== wireOf(majorityKey);
      return {
        id: `version:${p.publicKeyB64}`,
        kind: "old_version",
        severity: protocolDiffers ? "warn" : "info",
        title: protocolDiffers ? "Другая версия протоколов" : "Другая версия приложения",
        detail: `${p.callsign || playerName(p.publicKeyB64)}: ${versionKey(p)}, у большинства (${majorityCount} из ${reporting.length}) — ${majorityKey}`,
        subjectKey: p.publicKeyB64,
        at: p.lastSeenAt,
      };
    });
}
