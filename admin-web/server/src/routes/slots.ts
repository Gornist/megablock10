import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { verifySignature } from "../lib/crypto.js";
import { containerIdOf, makeSlotRef } from "../lib/slotRef.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { cachedByDbVersion } from "../lib/dbCache.js";
import { checkGameSecret } from "../lib/gameSecret.js";
import type { ContainerSlot } from "./containers.js";

interface ClaimBody {
  claimantKeyB64?: unknown;
  claimedAt?: unknown;
  signature?: unknown;
}

/** Байты подписи заявки — тот же формат, что ClaimProtocol.signaturePayload в Android-клиенте (пригодится, когда сервер станет основным путём арбитража, а P2P-госсип — офлайн-подстраховкой). */
function claimSignaturePayload(slotRef: string, claimantKeyB64: string, claimedAt: number): Buffer {
  return Buffer.from(`${slotRef}|${claimantKeyB64}|${claimedAt}`, "utf8");
}

/**
 * Арбитраж тиражного лута (§5 ТЗ, упрощённая версия из обсуждения объёма
 * работ — п.1): сервер лежит → извлечение уникального слота просто не
 * проходит ("хранилище недоступно"), без очереди "ожидает подтверждения" и
 * без экрана 8.6. Обычный лут и эдди при этом начисляются на устройстве как
 * обычно — сюда вообще не попадают.
 */
export function registerSlotsRoutes(app: FastifyInstance, db: Db) {
  const getContainerStmt = db.prepare(`SELECT slots_json FROM containers WHERE id = ?`);
  const countClaimsStmt = db.prepare(`SELECT COUNT(*) AS n FROM slot_claims WHERE slot_ref = ? AND revoked = 0`);
  const insertClaimStmt = db.prepare(`
    INSERT INTO slot_claims (slot_ref, claimant_key, claimed_at, granted_by, revoked)
    VALUES (?, ?, ?, 'SERVER', 0)
    ON CONFLICT(slot_ref, claimant_key) DO UPDATE SET
      revoked = 0, revoked_by = NULL, revoked_reason = NULL, claimed_at = excluded.claimed_at, granted_by = 'SERVER'
      WHERE slot_claims.revoked = 1
  `);
  // Раньше здесь было DO NOTHING: аннулированная заявка (revoked=1) при повторном клейме оставалась
  // аннулированной, а ответ был granted:true — игрок получал лут, которого реестр не учитывал, и слот
  // можно было выдать сверх тиража.

  const claim = db.transaction((slotRef: string, claimantKeyB64: string, claimedAt: number) => {
    const containerRow = getContainerStmt.get(containerIdOf(slotRef)) as { slots_json: string } | undefined;
    if (!containerRow) return { status: 404 as const, body: { error: "unknown container" } };

    const slots = JSON.parse(containerRow.slots_json) as ContainerSlot[];
    const indexStr = slotRef.slice(slotRef.lastIndexOf("#") + 1);
    const slot = slots.find((s) => String(s.index) === indexStr);
    if (!slot) return { status: 404 as const, body: { error: "unknown slot" } };

    if (slot.copies === 0) {
      // Бесконечный тираж — сервер не арбитрирует (§5), выдаётся всегда.
      return { status: 200 as const, body: { granted: true, copiesLeft: null } };
    }

    const already = countClaimsStmt.get(slotRef) as { n: number };
    const alreadyClaimedBySelf = db
      .prepare(`SELECT 1 FROM slot_claims WHERE slot_ref = ? AND claimant_key = ? AND revoked = 0`)
      .get(slotRef, claimantKeyB64);

    if (!alreadyClaimedBySelf && already.n >= slot.copies) {
      return { status: 200 as const, body: { granted: false, reason: "EXHAUSTED" } };
    }

    insertClaimStmt.run(slotRef, claimantKeyB64, claimedAt);
    const now = countClaimsStmt.get(slotRef) as { n: number };
    return { status: 200 as const, body: { granted: true, copiesLeft: Math.max(0, slot.copies - now.n) } };
  });

  app.post<{ Params: { slotRef: string }; Body: ClaimBody }>("/api/slots/:slotRef/claim", async (request, reply) => {
    if (!checkGameSecret(request, reply)) return;

    const { claimantKeyB64, claimedAt, signature } = request.body ?? {};
    if (typeof claimantKeyB64 !== "string" || typeof claimedAt !== "number" || typeof signature !== "string") {
      return reply.code(400).send({ error: "claimantKeyB64, claimedAt and signature are required" });
    }
    const slotRef = request.params.slotRef;
    const payload = claimSignaturePayload(slotRef, claimantKeyB64, claimedAt);
    if (!verifySignature(claimantKeyB64, payload, signature)) {
      return reply.code(400).send({ error: "invalid signature" });
    }

    const result = claim(slotRef, claimantKeyB64, claimedAt);
    return reply.code(result.status).send(result.body);
  });

  // См. players.ts/dbCache.ts — кэш по версии БД: claim/revoke/restore меняют
  // total_changes(), поэтому реестр обновится на следующем же запросе.
  const cachedSlotRegistry = cachedByDbVersion(db, () => listSlotRegistry(db));

  /** GET /api/slots — реестр тиражей для дашборда (§8.5 ТЗ), только мастера. */
  app.get("/api/slots", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    return cachedSlotRegistry();
  });

  /** POST /api/slots/:ref/revoke — аннулировать заявку (§7 ТЗ). */
  app.post<{ Params: { ref: string }; Body: { claimantKeyB64?: unknown; reason?: unknown } }>(
    "/api/slots/:ref/revoke",
    async (request, reply) => {
      const master = requireMaster(db, request, reply);
      if (!master) return;
      const { claimantKeyB64, reason } = request.body ?? {};
      if (typeof claimantKeyB64 !== "string") return reply.code(400).send({ error: "claimantKeyB64 required" });

      db.prepare(
        `UPDATE slot_claims SET revoked = 1, revoked_by = ?, revoked_reason = ? WHERE slot_ref = ? AND claimant_key = ?`,
      ).run(master.id, typeof reason === "string" ? reason : null, request.params.ref, claimantKeyB64);
      logMasterAction(db, master.id, "SLOT_REVOKE", { slotRef: request.params.ref, claimantKeyB64, reason });
      return { ok: true };
    },
  );

  /** POST /api/slots/:ref/restore — снять revoke со ВСЕХ заявок на слот, вернуть его в оборот (§7 ТЗ). */
  app.post<{ Params: { ref: string } }>("/api/slots/:ref/restore", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    db.prepare(`UPDATE slot_claims SET revoked = 0, revoked_by = NULL, revoked_reason = NULL WHERE slot_ref = ?`).run(
      request.params.ref,
    );
    logMasterAction(db, master.id, "SLOT_RESTORE", { slotRef: request.params.ref });
    return { ok: true };
  });
}

/** Переиспользуется и роутом /api/slots, и CSV-экспортом (routes/exportCsv.ts) — та же причина, что у listNodeSummaries/listPlayerSummaries. */
export function listSlotRegistry(db: Db) {
  const containers = db.prepare(`SELECT id, name, tier, owner_faction, slots_json FROM containers`).all() as {
    id: string;
    name: string;
    tier: string;
    owner_faction: string | null;
    slots_json: string;
  }[];
  const claimsBySlot = new Map<string, { claimantKeyB64: string; claimedAt: number }[]>();
  for (const row of db.prepare(`SELECT slot_ref, claimant_key, claimed_at FROM slot_claims WHERE revoked = 0`).all() as {
    slot_ref: string;
    claimant_key: string;
    claimed_at: number;
  }[]) {
    const list = claimsBySlot.get(row.slot_ref) ?? [];
    list.push({ claimantKeyB64: row.claimant_key, claimedAt: row.claimed_at });
    claimsBySlot.set(row.slot_ref, list);
  }

  const registry = [];
  for (const c of containers) {
    const slots = JSON.parse(c.slots_json) as ContainerSlot[];
    for (const slot of slots) {
      if (slot.copies <= 0) continue; // бесконечный тираж — не в реестре, его нечего балансировать
      const slotRef = makeSlotRef(c.id, slot.index);
      const claimants = claimsBySlot.get(slotRef) ?? [];
      registry.push({
        slotRef,
        containerId: c.id,
        containerName: c.name,
        type: slot.type,
        tier: slot.tier,
        title: slot.title,
        copiesTotal: slot.copies,
        copiesClaimed: claimants.length,
        claimants,
      });
    }
  }
  return registry;
}
