import type { AttentionItem, Severity } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { buildAttentionContext, type AttentionRule } from "./attentionRules/context.js";
import { versionMismatch, pulseAnomalies, playerOutliers, clockSkew, syncStuck } from "./attentionRules/fleetRules.js";
import { balanceJump, negativeBalance, nodeExhaustedHot, overrideFailed, overrideUndelivered, repeatedRevoke, shardCopies, wentSilent } from "./attentionRules/gameRules.js";
import {
  amountMismatch,
  balanceChainBreak,
  balanceUnexplained,
  duplicateReceive,
  provisionConflict,
  transferStuck,
} from "./attentionRules/integrityRules.js";

export type { AttentionItem };

const SEVERITY_ORDER: Record<Severity, number> = { crit: 0, warn: 1, info: 2 };

/** Реестр правил: новое правило — новая функция в attentionRules/ и строка здесь; центральный код не меняется. Порядок влияет только на равные по важности и времени. */
const RULES: AttentionRule[] = [
  negativeBalance,
  balanceJump,
  wentSilent,
  nodeExhaustedHot,
  repeatedRevoke,
  overrideUndelivered,
  overrideFailed,
  shardCopies,
  versionMismatch,
  syncStuck,
  pulseAnomalies,
  playerOutliers,
  clockSkew,
  provisionConflict,
  duplicateReceive,
  amountMismatch,
  balanceUnexplained,
  balanceChainBreak,
  transferStuck,
];

/**
 * Автоподсказки мастеру: что на площадке выглядит неправильно. Каждое правило
 * — дешёвый запрос по уже существующим данным; ничего не пишется и не
 * решается за мастера — только «обрати внимание», с ссылкой на игрока/узел.
 */
export function computeAttention(db: Db, now = Date.now()): AttentionItem[] {
  const ctx = buildAttentionContext(db, now);
  return RULES.flatMap((rule) => rule(ctx)).sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || b.at - a.at);
}
