import type { FastifyInstance } from "fastify";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { validateContainerSlots, type ContainerSlot } from "../lib/containerSlots.js";

export type { ContainerSlot };

interface ContainerInput {
  id?: unknown;
  name?: unknown;
  tier?: unknown;
  ownerFaction?: unknown;
  slots?: unknown;
}

/**
 * POST /api/containers — Мастерская заливает справочник контейнеров,
 * перезапись по id (§3.3 ТЗ). Защищено мастерским токеном — Мастерская
 * пушит сюда с тем же токеном, что и вход в дашборд (см. §9: "всё, кроме
 * /api/changes и /api/slots/:ref/claim — только с мастерским токеном").
 */
export function upsertContainer(
  db: Db,
  input: { id: string; name: string; tier: string; ownerFaction: string | null; slots: ContainerSlot[] },
) {
  db.prepare(
    `INSERT INTO containers (id, name, tier, owner_faction, slots_json, updated_at)
     VALUES (@id, @name, @tier, @owner_faction, @slots_json, @updated_at)
     ON CONFLICT(id) DO UPDATE SET
       name = excluded.name, tier = excluded.tier, owner_faction = excluded.owner_faction,
       slots_json = excluded.slots_json, updated_at = excluded.updated_at`,
  ).run({
    id: input.id,
    name: input.name,
    tier: input.tier,
    owner_faction: input.ownerFaction,
    slots_json: JSON.stringify(input.slots),
    updated_at: Date.now(),
  });
}

export function registerContainersRoute(app: FastifyInstance, db: Db) {
  app.post<{ Body: { containers?: unknown } }>("/api/containers", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;

    const list = request.body?.containers;
    if (!Array.isArray(list)) return reply.code(400).send({ error: "containers must be an array" });

    const errors: { id: string; error: string }[] = [];
    let count = 0;
    for (const raw of list) {
      if (typeof raw !== "object" || raw === null) {
        errors.push({ id: "?", error: "malformed container" });
        continue;
      }
      const c = raw as ContainerInput;
      if (typeof c.id !== "string" || typeof c.name !== "string" || typeof c.tier !== "string" || !Array.isArray(c.slots)) {
        errors.push({ id: typeof c.id === "string" ? c.id : "?", error: "malformed container" });
        continue;
      }
      const validated = validateContainerSlots(c.slots);
      if (!validated.ok) {
        errors.push({ id: c.id, error: validated.error });
        continue;
      }
      upsertContainer(db, {
        id: c.id,
        name: c.name,
        tier: c.tier,
        ownerFaction: typeof c.ownerFaction === "string" ? c.ownerFaction : null,
        slots: validated.slots,
      });
      count += 1;
    }

    return { upserted: count, errors };
  });
}
