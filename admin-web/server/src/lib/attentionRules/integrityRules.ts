import type { AttentionItem } from "../../apiTypes.js";
import { REASON_LABEL_RU } from "../humanize.js";
import { findUnexplainedJumps, getIntegrityFindings } from "../integrity.js";
import { provisionConflicts } from "../provisions.js";
import { MIN, type AttentionRule } from "./context.js";

/** Проверки целостности (lib/integrity.ts): перекрёстные признаки подделки и зависших переводов. Все — в окне integrityWindowMs. */

/** Код персонажа применили на двух телефонах (копия QR). */
export const provisionConflict: AttentionRule = ({ db, now, t, playerName }) =>
  provisionConflicts(db)
    .filter((c) => c.at >= now - t.integrityWindowMs)
    .map(
      (c): AttentionItem => ({
        id: `provision:${c.provisionId}:${c.key}`,
        kind: "provision_conflict",
        severity: "crit",
        title: "Код персонажа применили на двух телефонах",
        detail: `код «${c.callsign}» (${c.provisionId.slice(0, 8)}) уже у ${c.boundKey ? playerName(c.boundKey) : "другого телефона"}, вторая попытка — ${playerName(c.key)}: копия QR или напечатан дубль`,
        subjectKey: c.key,
        at: c.at,
      }),
    );

/** Один платёж или предмет получили двое: честное приложение так не делает. */
export const duplicateReceive: AttentionRule = ({ db, now, t, playerName }) =>
  getIntegrityFindings(db)
    .duplicateReceives.filter((d) => d.at >= now - t.integrityWindowMs)
    .map(
      (d): AttentionItem => ({
        id: `duplicate:${d.reason}:${d.sourceRef}`,
        kind: "duplicate_receive",
        severity: "crit",
        title: d.reason === "TRANSFER_IN" ? "Один платёж получили двое" : "Один предмет получили двое",
        detail: `${d.subjectKeys.map(playerName).join(", ")} (перевод ${d.sourceRef.slice(0, 8)}) — честное приложение так не делает`,
        subjectKey: d.subjectKeys[0],
        at: d.at,
      }),
    );

/** Списано одно, получено другое. */
export const amountMismatch: AttentionRule = ({ db, now, t, playerName }) =>
  getIntegrityFindings(db)
    .amountMismatches.filter((m) => m.at >= now - t.integrityWindowMs)
    .map(
      (m): AttentionItem => ({
        id: `mismatch:${m.txId}`,
        kind: "transfer_amount_mismatch",
        severity: "crit",
        title: "Сумма перевода не сходится",
        detail: `${playerName(m.fromKey)} → ${playerName(m.toKey)}: списано ${m.sent} €$, получено ${m.received} €$`,
        subjectKey: m.toKey,
        at: m.at,
      }),
    );

/** Баланс вырос по причине, которая денег не даёт. */
export const balanceUnexplained: AttentionRule = ({ db, now, t, playerName }) =>
  findUnexplainedJumps(db, now - t.integrityWindowMs, t.balanceJump).map(
    (j): AttentionItem => ({
      id: `unexplained:${j.id}`,
      kind: "balance_unexplained",
      severity: "crit",
      title: "Баланс вырос без причины",
      detail: `${playerName(j.subjectKey)}: +${j.delta} €$ по причине «${REASON_LABEL_RU[j.reason] ?? j.reason}», которая денег не даёт`,
      subjectKey: j.subjectKey,
      at: j.at,
    }),
  );

/** oldValue записи не равен newValue предыдущей у того же игрока. */
export const balanceChainBreak: AttentionRule = ({ db, now, t, playerName }) =>
  getIntegrityFindings(db)
    .chainBreaks.filter((b) => b.at >= now - t.integrityWindowMs)
    .map(
      (b): AttentionItem => ({
        id: `chain:${b.subjectKey}:${b.at}`,
        kind: "balance_chain_break",
        severity: "warn",
        title: "Разрыв цепочки баланса",
        detail: `${playerName(b.subjectKey)}: по журналу было ${b.expected} €$, а запись исходит из ${b.actual} €$${b.count > 1 ? ` (разрывов: ${b.count})` : ""}`,
        subjectKey: b.subjectKey,
        at: b.at,
      }),
    );

/** Перевод без пары дольше порога: отправка без получения и отмены либо получение без отправки. */
export const transferStuck: AttentionRule = ({ db, now, t, playerName }) =>
  getIntegrityFindings(db)
    .unpairedTransfers.filter((u) => now - u.at >= t.transferStuckMs)
    .map((u): AttentionItem => {
      const mins = Math.round((now - u.at) / MIN);
      const what = u.kind === "money" ? `платёж${u.amount ? ` ${u.amount} €$` : ""}` : "передача предмета";
      return {
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
      };
    });
