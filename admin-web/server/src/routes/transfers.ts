import { makeHumanizeContext } from "../lib/humanize.js";
import type { FastifyInstance } from "fastify";
import type { Transfer } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";

interface TransferRow {
  id: string;
  subject_key: string;
  old_value: string | null;
  new_value: string | null;
  source_ref: string | null;
  actor: string;
  happened_at: number;
  received_at: number;
}

/**
 * balance — это абсолютный баланс ПОСЛЕ применения дельты (см.
 * TransactionStore.kt.emitBalanceChange на Android-стороне), не сама
 * дельта. Раньше amount тут был просто new_value записи TRANSFER_OUT —
 * т.е. остаток отправителя после списания, а не сумма перевода. Сумму
 * восстанавливаем как разницу old/new, с учётом знака: у TRANSFER_OUT
 * баланс уменьшается (old − new), у TRANSFER_IN — увеличивается (new − old).
 */
function transferAmount(row: TransferRow, direction: "out" | "in"): number {
  const oldBalance = Number(row.old_value ?? 0);
  const newBalance = Number(row.new_value ?? 0);
  return direction === "out" ? oldBalance - newBalance : newBalance - oldBalance;
}

/**
 * GET /api/transfers — сводит обе половины перевода по txId (source_ref),
 * §4 и §7 ТЗ. "Односторонний" помечается булевым полем, а не таймером на
 * сервере — сколько он уже висит, дашборд считает сам от receivedAt
 * (упрощение №6 из обсуждения объёма работ).
 */
export function registerTransfersRoute(app: FastifyInstance, db: Db) {
  app.get("/api/transfers", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const outs = db
      .prepare(
        `SELECT id, subject_key, old_value, new_value, source_ref, actor, happened_at, received_at FROM changes WHERE reason = 'TRANSFER_OUT'`,
      )
      .all() as TransferRow[];
    const ins = db
      .prepare(
        `SELECT id, subject_key, old_value, new_value, source_ref, actor, happened_at, received_at FROM changes WHERE reason = 'TRANSFER_IN'`,
      )
      .all() as TransferRow[];

    // Отправитель отменил недоставленный платёж (TransactionStore.cancelOutgoing на Android) —
    // деньги вернулись к нему, это не "висящий" односторонний перевод.
    const cancelledByTx = new Map<string, number>();
    const cancels = db
      .prepare(`SELECT source_ref, received_at FROM changes WHERE reason = 'TRANSFER_CANCELLED' AND source_ref IS NOT NULL`)
      .all() as { source_ref: string; received_at: number }[];
    for (const row of cancels) cancelledByTx.set(row.source_ref, row.received_at);

    const insByTx = new Map<string, TransferRow>();
    for (const row of ins) if (row.source_ref) insByTx.set(row.source_ref, row);

    const seen = new Set<string>();
    const transfers: Transfer[] = [];
    for (const out of outs) {
      const txId = out.source_ref ?? out.id;
      seen.add(txId);
      const inRow = out.source_ref ? insByTx.get(out.source_ref) : undefined;
      transfers.push({
        txId,
        from: out.subject_key,
        // В записи отправки actor — сам отправитель (сервер требует actor = subject), так что получатель известен только по записи получения.
        to: inRow ? inRow.subject_key : null,
        amount: transferAmount(out, "out"),
        sentAt: out.received_at,
        confirmedAt: inRow ? inRow.received_at : null,
        cancelledAt: cancelledByTx.get(txId) ?? null,
        oneSided: !inRow && !cancelledByTx.has(txId),
      });
    }
    // TRANSFER_IN без пары TRANSFER_OUT (второе устройство ещё не досылало) — тоже показываем, помеченным односторонним.
    for (const inRow of ins) {
      const txId = inRow.source_ref ?? inRow.id;
      if (seen.has(txId)) continue;
      transfers.push({
        txId,
        from: inRow.actor,
        to: inRow.subject_key,
        amount: transferAmount(inRow, "in"),
        sentAt: null,
        confirmedAt: inRow.received_at,
        cancelledAt: null,
        oneSided: true,
      });
    }

    // Имена вместо ключей: на дашборде «от MFkw…» ничего не говорит мастеру.
    const names = makeHumanizeContext(db);
    for (const t of transfers) {
      t.fromName = names.playerName(t.from);
      if (t.to) t.toName = names.playerName(t.to);
    }

    transfers.sort((a, b) => (b.confirmedAt ?? b.sentAt ?? 0) - (a.confirmedAt ?? a.sentAt ?? 0));
    return transfers;
  });
}
