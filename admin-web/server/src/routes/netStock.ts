import type { FastifyInstance } from "fastify";
import type { NetStockResult, NodeStockView } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { buildStockItem, type StockPayload } from "../lib/netPayload.js";
import { isIntIn, isRef } from "../lib/refs.js";
import type { NetService } from "../net/netService.js";
import { makeAct, RID_MAX, ridOk } from "./netAct.js";

/** Наполнение узлов из «Мастерской» (docs/netrun-bridge-protocol.md, master.stock_node / master.unstock_node). */
export function registerNetStockRoutes(app: FastifyInstance, db: Db, net: NetService) {
  const act = makeAct(db);

  /** Что лежит в узле сейчас — документы item с owner node:<узел>; нужен, чтобы мастер выбрал, что убрать. Типа item в подписке нет, читаем list. */
  app.get<{ Params: { id: string } }>("/api/net/nodes/:id/items", async (request, reply) => {
    const id = request.params.id;
    if (!isRef(id)) return reply.code(400).send({ error: "bad node id" });
    return act<NodeStockView>(request, reply, async () => {
      const docs = await net.listDocs("item");
      const items = docs
        .filter((d) => d.data.owner === `node:${id}`)
        .map((d) => {
          const shard = (d.data.shard ?? {}) as { tier?: number; title?: string };
          const daemon = (d.data.daemon ?? {}) as { tier?: number; name?: string; effect?: string };
          return {
            id: d.id,
            ver: d.ver,
            kind: String(d.data.kind ?? ""),
            title: String(shard.title ?? daemon.name ?? ""),
            tier: shard.tier ?? daemon.tier ?? null,
            effect: daemon.effect ?? null,
            origin: String(d.data.origin ?? ""),
          };
        })
        .sort((a, b) => a.kind.localeCompare(b.kind) || a.id.localeCompare(b.id));
      const eddies = net.doc("node", id)?.data.eddies;
      return { result: { node: id, eddies: typeof eddies === "number" ? eddies : null, items } };
    });
  });

  /** Из ответа Моста — только то, что нужно экрану (без служебного конверта v/re/ok). */
  const stockResult = (r: Record<string, unknown>): NetStockResult => ({ node: String(r.node), items: (r.items as string[]) ?? [], eddies: Number(r.eddies), ...(r.replayed === true ? { replayed: true } : {}) });

  const eddiesOk = (v: unknown) => v === undefined || isIntIn(v, 0, 1_000_000_000);

  /**
   * Положить в узел шарды, демонов и эдди. Экран присылает предметы в человеческом виде, коллектор собирает payload (ItemPayloadCodec) по
   * правилам «Мастерской». rid создаёт экран один раз на нажатие: повтор после обрыва уйдёт с тем же rid и теми же байтами, и Мост
   * не создаст копий (replayed: true).
   */
  app.post<{ Params: { id: string }; Body: { rid?: unknown; items?: unknown; eddies?: unknown } }>("/api/net/nodes/:id/stock", async (request, reply) => {
    const node = request.params.id;
    if (!isRef(node)) return reply.code(400).send({ error: "bad node id" });
    const b = request.body ?? {};
    if (!ridOk(b.rid)) return reply.code(400).send({ error: `rid is required (max ${RID_MAX})` });
    if (!eddiesOk(b.eddies)) return reply.code(400).send({ error: "eddies must be a non-negative integer" });
    if (b.items !== undefined && !(Array.isArray(b.items) && b.items.length <= 50)) return reply.code(400).send({ error: "items must be a list (max 50)" });
    const input = (b.items as unknown[] | undefined) ?? [];
    const eddies = (b.eddies as number | undefined) ?? 0;
    if (input.length === 0 && eddies === 0) return reply.code(400).send({ error: "nothing to stock: add items or eddies" });
    const items: StockPayload[] = [];
    for (const [i, raw] of input.entries()) {
      const r = buildStockItem(raw, b.rid, i);
      if (!r.ok) return reply.code(400).send({ error: r.error });
      items.push(r.item);
    }
    return act<NetStockResult>(request, reply, async () => {
      const r = stockResult(await net.request({ op: "master.stock_node", rid: b.rid, node, items, eddies }));
      return { result: r, audit: { action: "NET_STOCK", detail: { node, rid: b.rid, items: items.length, eddies, replayed: r.replayed === true } } };
    });
  });

  /** Убрать из узла предметы (в `burned:master`, документ остаётся в журнале Моста) и/или часть запаса эдди. Тот же rid-контракт. */
  app.post<{ Params: { id: string }; Body: { rid?: unknown; items?: unknown; eddies?: unknown } }>("/api/net/nodes/:id/unstock", async (request, reply) => {
    const node = request.params.id;
    if (!isRef(node)) return reply.code(400).send({ error: "bad node id" });
    const b = request.body ?? {};
    if (!ridOk(b.rid)) return reply.code(400).send({ error: `rid is required (max ${RID_MAX})` });
    if (!eddiesOk(b.eddies)) return reply.code(400).send({ error: "eddies must be a non-negative integer" });
    if (b.items !== undefined && !(Array.isArray(b.items) && b.items.length <= 100 && b.items.every(isRef))) return reply.code(400).send({ error: "items must be a list of item ids (max 100)" });
    const items = (b.items as string[] | undefined) ?? [];
    const eddies = (b.eddies as number | undefined) ?? 0;
    if (items.length === 0 && eddies === 0) return reply.code(400).send({ error: "nothing to remove: pick items or eddies" });
    return act<NetStockResult>(request, reply, async () => {
      const r = stockResult(await net.request({ op: "master.unstock_node", rid: b.rid, node, items, eddies }));
      return { result: r, audit: { action: "NET_UNSTOCK", detail: { node, rid: b.rid, items: items.length, eddies, replayed: r.replayed === true } } };
    });
  });
}
