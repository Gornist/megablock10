import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import type { AnnouncementItem, AnnouncementRecipient } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { makeHumanizeContext } from "../lib/humanize.js";
import { insertMasterRecords, selectTargets, type TargetSelectorInput } from "../lib/masterRecords.js";
import { getPlayerBase } from "../lib/playerSummary.js";

const ANNOUNCEMENT_FIELD = "announcement";
const MAX_TEXT = 500;
const REF_PREFIX = "broadcast:";

/**
 * Объявления мастера игрокам. Канал доставки — тот же, что у правок (pending
 * на heartbeat телефона), поэтому «рассылка» — это обычные мастерские записи
 * (по одной на адресата) с field=announcement и общим source_ref
 * `broadcast:<id>`: по нему собирается история рассылок и статус доставки
 * («87 из 100 получили»). Телефон применяет запись, показывает сообщение и
 * подтверждает ack-ом — только после этого запись считается доставленной.
 */
export function registerAnnouncementsRoutes(app: FastifyInstance, db: Db) {
  app.post<{ Body: TargetSelectorInput & { text?: unknown; dryRun?: unknown } }>("/api/announcements", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const body = request.body ?? {};
    const text = typeof body.text === "string" ? body.text.trim() : "";
    if (!text) return reply.code(400).send({ error: "text is required" });
    if (text.length > MAX_TEXT) return reply.code(400).send({ error: `text is too long, max ${MAX_TEXT}` });

    const targets = selectTargets(getPlayerBase(db), body);
    if (!targets.ok) return reply.code(400).send({ error: targets.error });
    if (targets.players.length === 0) return reply.code(400).send({ error: "no matching players" });

    if (body.dryRun === true) {
      return { dryRun: true, target: targets.label, count: targets.players.length, recipients: targets.players.map((p) => p.callsign || p.publicKeyB64.slice(0, 8)) };
    }

    const broadcastId = randomUUID();
    insertMasterRecords(
      db,
      master.id,
      targets.players.map((p) => ({
        subjectKey: p.publicKeyB64,
        field: ANNOUNCEMENT_FIELD,
        oldValue: null,
        newValue: text,
        sourceRef: `${REF_PREFIX}${broadcastId}`,
      })),
    );
    logMasterAction(db, master.id, "ANNOUNCEMENT", { broadcastId, text, target: targets.label, count: targets.players.length });
    return { dryRun: false, broadcastId, target: targets.label, count: targets.players.length };
  });

  /** История рассылок: текст, время, сколько адресатов и сколько уже применили. */
  app.get("/api/announcements", async (request, reply): Promise<AnnouncementItem[] | void> => {
    if (!requireMaster(db, request, reply)) return;

    const rows = db
      .prepare(
        `SELECT c.source_ref AS ref, MIN(c.received_at) AS at, MAX(c.new_value) AS text, MAX(c.actor) AS actor,
                COUNT(*) AS recipients, COALESCE(SUM(mp.delivered), 0) AS delivered
         FROM changes c LEFT JOIN master_pending mp ON mp.change_id = c.id
         WHERE c.field = ? GROUP BY c.source_ref ORDER BY at DESC LIMIT 50`,
      )
      .all(ANNOUNCEMENT_FIELD) as { ref: string; at: number; text: string; actor: string; recipients: number; delivered: number }[];

    const masterName = db.prepare(`SELECT name FROM masters WHERE id = ?`);
    return rows.map((r) => ({
      id: r.ref.slice(REF_PREFIX.length),
      at: r.at,
      text: r.text,
      recipients: r.recipients,
      delivered: r.delivered,
      masterName: (masterName.get(r.actor.replace(/^master:/, "")) as { name: string } | undefined)?.name ?? "неизвестный мастер",
    }));
  });

  /** Кому из адресатов рассылка ещё не дошла — для «позвонить/подойти лично». */
  app.get<{ Params: { id: string } }>("/api/announcements/:id/recipients", async (request, reply): Promise<AnnouncementRecipient[] | void> => {
    if (!requireMaster(db, request, reply)) return;

    const rows = db
      .prepare(
        `SELECT c.subject_key AS key, COALESCE(mp.delivered, 0) AS delivered
         FROM changes c LEFT JOIN master_pending mp ON mp.change_id = c.id
         WHERE c.field = ? AND c.source_ref = ?`,
      )
      .all(ANNOUNCEMENT_FIELD, `${REF_PREFIX}${request.params.id}`) as { key: string; delivered: number }[];
    if (rows.length === 0) return reply.code(404).send({ error: "unknown announcement" });

    const ctx = makeHumanizeContext(db);
    return rows
      .map((r) => ({ publicKeyB64: r.key, callsign: ctx.playerName(r.key), delivered: r.delivered === 1 }))
      .sort((a, b) => Number(a.delivered) - Number(b.delivered) || a.callsign.localeCompare(b.callsign));
  });
}
