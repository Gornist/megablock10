import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { toCsv } from "../lib/csv.js";
import { listPlayerSummaries } from "./players.js";
import { listNodeSummaries } from "./nodes.js";
import { listSlotRegistry } from "./slots.js";

const KINDS = ["players", "nodes", "slots", "history"] as const;
type Kind = (typeof KINDS)[number];

/**
 * GET /api/export/:kind.csv — players | nodes | slots | history (§7 ТЗ).
 * Строки те же, что видно в соответствующих экранах (listPlayerSummaries/
 * listNodeSummaries/listSlotRegistry) — раньше экспорт пересчитывал
 * агрегаты заново своими руками и рисковал незаметно разойтись с UI.
 */
export function registerExportRoute(app: FastifyInstance, db: Db) {
  app.get<{ Params: { kind: string } }>("/api/export/:kind", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const raw = request.params.kind;
    if (!raw.endsWith(".csv")) return reply.code(404).send({ error: "not found" });
    const kind = raw.slice(0, -".csv".length);
    if (!isKind(kind)) return reply.code(400).send({ error: `unknown export kind: ${kind}` });

    const rows = buildRows(db, kind);
    reply.header("content-type", "text/csv; charset=utf-8");
    reply.header("content-disposition", `attachment; filename="${kind}.csv"`);
    return toCsv(rows);
  });
}

function isKind(v: string): v is Kind {
  return (KINDS as readonly string[]).includes(v);
}

function buildRows(db: Db, kind: Kind): Record<string, unknown>[] {
  switch (kind) {
    case "players":
      return listPlayerSummaries(db).map((s) => ({
        publicKeyB64: s.publicKeyB64,
        callsign: s.callsign,
        faction: s.faction,
        ramCapacity: s.ramCapacity,
        balance: s.balance,
        daemonCount: s.daemonCount,
        shardCount: Object.values(s.shardsByTier).reduce((a, b) => a + b, 0),
        breachSuccess: s.breaches.success,
        breachPartial: s.breaches.partial,
        breachFail: s.breaches.fail,
        slotsClaimed: s.slotsClaimed,
        online: s.online,
        lastSeenAt: s.lastSeenAt,
      }));
    case "nodes":
      return listNodeSummaries(db).map((n) => ({
        id: n.id,
        name: n.name,
        tier: n.tier,
        ownerFaction: n.ownerFaction,
        slotsClaimed: n.slotsClaimed,
        slotsTotal: n.slotsTotal,
        breachSuccess: n.breaches.success,
        breachPartial: n.breaches.partial,
        breachFail: n.breaches.fail,
        uniquePlayers: n.uniquePlayers,
        alertsSent: n.alertsSent,
        alertsSuppressed: n.alertsSuppressed,
        lastBreachAt: n.lastBreachAt,
      }));
    case "slots":
      return listSlotRegistry(db).map((s) => ({
        slotRef: s.slotRef,
        containerName: s.containerName,
        title: s.title,
        type: s.type,
        tier: s.tier,
        copiesTotal: s.copiesTotal,
        copiesClaimed: s.copiesClaimed,
        claimants: s.claimants.map((c) => `${c.claimantKeyB64}@${c.claimedAt}`).join("; "),
      }));
    case "history":
      return db.prepare(`SELECT * FROM changes ORDER BY received_at ASC`).all() as Record<string, unknown>[];
  }
}
