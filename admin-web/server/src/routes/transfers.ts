import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";

interface TransferRow {
  id: string;
  subject_key: string;
  new_value: string | null;
  source_ref: string | null;
  actor: string;
  happened_at: number;
  received_at: number;
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
        `SELECT id, subject_key, new_value, source_ref, actor, happened_at, received_at FROM changes WHERE reason = 'TRANSFER_OUT'`,
      )
      .all() as TransferRow[];
    const ins = db
      .prepare(
        `SELECT id, subject_key, new_value, source_ref, actor, happened_at, received_at FROM changes WHERE reason = 'TRANSFER_IN'`,
      )
      .all() as TransferRow[];

    const insByTx = new Map<string, TransferRow>();
    for (const row of ins) if (row.source_ref) insByTx.set(row.source_ref, row);

    const seen = new Set<string>();
    const transfers = [];
    for (const out of outs) {
      const txId = out.source_ref ?? out.id;
      seen.add(txId);
      const inRow = out.source_ref ? insByTx.get(out.source_ref) : undefined;
      transfers.push({
        txId,
        from: out.subject_key,
        to: inRow ? inRow.subject_key : out.actor,
        amount: out.new_value,
        sentAt: out.received_at,
        confirmedAt: inRow ? inRow.received_at : null,
        oneSided: !inRow,
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
        amount: inRow.new_value,
        sentAt: null,
        confirmedAt: inRow.received_at,
        oneSided: true,
      });
    }

    transfers.sort((a, b) => (b.confirmedAt ?? b.sentAt ?? 0) - (a.confirmedAt ?? a.sentAt ?? 0));
    return transfers;
  });
}
