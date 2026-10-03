import type { FastifyInstance } from "fastify";
import type { NetDoc, NetSecView } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { isRef } from "../lib/refs.js";
import { BridgeError } from "../net/bridgeProtocol.js";
import type { NetService } from "../net/netService.js";
import { computeSecDoc, getDefaultFaction, setDefaultFaction, type SecSync } from "../net/secSync.js";
import { makeAct } from "./netAct.js";

/** Получатели сигнала СБ и владелец узла (docs/netrun-collector-brief.md, задача 3). */
export function registerNetSecRoutes(app: FastifyInstance, db: Db, net: NetService, secSync: SecSync) {
  const act = makeAct(db);

  const secView = (): NetSecView => ({
    defaultFaction: getDefaultFaction(db),
    recipients: Object.entries(computeSecDoc(db).factions)
      .map(([faction, keys]) => ({ faction, count: keys.length }))
      .sort((a, b) => a.faction.localeCompare(b.faction)),
    sync: secSync.status(),
  });

  app.get("/api/net/sec", async (request, reply): Promise<NetSecView | void> => {
    if (!requireMaster(db, request, reply)) return;
    return secView();
  });

  /** Фракция СБ по умолчанию: получатель сигнала, если у узла нет владельца. Сохраняется всегда; в Мост уходит, как только он на связи. */
  app.put<{ Body: { defaultFaction?: unknown } }>("/api/net/sec", async (request, reply): Promise<NetSecView | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const f = request.body?.defaultFaction;
    if (f !== null && (typeof f !== "string" || f.trim().length > 64)) return reply.code(400).send({ error: "defaultFaction must be a faction name (max 64) or null" });
    const faction = f === null || f.trim() === "" ? null : f.trim();
    setDefaultFaction(db, faction);
    logMasterAction(db, master.id, "NET_SEC_FACTION", { faction });
    await secSync.sync();
    return secView();
  });

  /** Владелец узла Сети (фракция) — документ node в Мосте: от неё Мост выбирает получателей сигнала СБ. null — владельца нет. */
  app.put<{ Params: { id: string }; Body: { faction?: unknown } }>("/api/net/nodes/:id/owner", async (request, reply) => {
    const id = request.params.id;
    if (!isRef(id)) return reply.code(400).send({ error: "bad node id" });
    const f = request.body?.faction;
    if (f !== null && (typeof f !== "string" || f.trim().length > 64)) return reply.code(400).send({ error: "faction must be a name (max 64) or null" });
    const faction = f === null || f.trim() === "" ? null : f.trim();
    return act(request, reply, async () => {
      const doc = await net.putDoc("node", id, (cur) => {
        if (cur === null) return null; // узла нет — создавать его владельцем незачем
        if ((cur.owner_faction ?? null) === faction) return null;
        const { owner_faction: _old, ...rest } = cur;
        return faction === null ? rest : { ...rest, owner_faction: faction };
      });
      if (!doc) throw new BridgeError("not_found", `node/${id}`);
      return { result: { doc: doc as NetDoc }, audit: { action: "NET_NODE_OWNER", detail: { node: id, faction } } };
    });
  });
}
