import type { FastifyInstance, FastifyReply } from "fastify";
import type { NetDoc, NetSecView, NetState, NetStockResult, NodeStockView } from "../apiTypes.js";
import { buildStockItem, type StockPayload } from "../lib/netPayload.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { BridgeError, BridgeUnavailableError } from "../net/bridgeProtocol.js";
import type { NetService } from "../net/netService.js";
import { computeSecDoc, getDefaultFaction, setDefaultFaction, type SecSync } from "../net/secSync.js";

/** Операции с ценностями, которые мастер вправе вызвать вручную («кнопка раньше автоматики»); сдача деки (`op.submit_deck`) — нет, она только от телефона. */
const VALUE_OPS = ["op.issue_to_phone", "op.take_from_node", "op.leave_in_node", "run.finish"] as const;

const REF = /^[A-Za-z0-9_.:-]{1,64}$/;
const RID_MAX = 128;

const HTTP_BY_CODE: Record<string, number> = {
  not_found: 404,
  version_conflict: 409,
  exists: 409,
  req_state: 409,
  rid_mismatch: 409,
  wrong_owner: 409,
  session_state: 409,
  protected_item: 409,
  bad_request: 400,
  value_field: 400,
};

/**
 * Ответ мастеру на отказ Моста. «Мост недоступен» — 503 (повторить позже; для операций с ценностями — с тем же rid);
 * ответ Моста с кодом — как есть, с понятным статусом и документом из ответа (его показывает экран при конфликте).
 * Неожиданное пробрасываем дальше — общий обработчик ошибок отдаст 500 без деталей.
 */
function bridgeFail(reply: FastifyReply, e: unknown): void {
  if (e instanceof BridgeUnavailableError) {
    reply.code(503).send({ error: e.message, code: "bridge_unavailable" });
  } else if (e instanceof BridgeError) {
    reply.code(HTTP_BY_CODE[e.code] ?? 502).send({ error: e.message, code: e.code, ...(e.doc ? { doc: e.doc } : {}) });
  } else throw e;
}

const isRef = (v: unknown): v is string => typeof v === "string" && REF.test(v);
const isInt = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;

/**
 * Инструменты мастера «Сети» (docs/netrun-bridge-protocol.md, §6a): браузер вызывает REST коллектора под сессией мастера, а
 * коллектор отправляет в Мост master.* / op.* по своему единственному соединению (роль master). Каждое действие — в журнале.
 */
export function registerNetBridgeRoutes(app: FastifyInstance, db: Db, net: NetService, secSync: SecSync) {
  /** Мастер + вызов Моста + журнал; отказ Моста — в ответ мастеру, без записи в журнал (ничего не сделано). */
  const act = async <T>(
    request: Parameters<typeof requireMaster>[1],
    reply: FastifyReply,
    run: () => Promise<{ result: T; audit?: { action: string; detail: unknown } }>,
  ): Promise<T | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    try {
      const { result, audit } = await run();
      if (audit) logMasterAction(db, master.id, audit.action, audit.detail);
      return result;
    } catch (e) {
      bridgeFail(reply, e);
    }
  };

  app.get("/api/net/state", async (request, reply): Promise<NetState | void> => {
    if (!requireMaster(db, request, reply)) return;
    return net.state();
  });

  app.post<{ Body: { on?: unknown; node?: unknown } }>("/api/net/pause", async (request, reply) => {
    const b = request.body ?? {};
    if (typeof b.on !== "boolean") return reply.code(400).send({ error: "on must be boolean" });
    if (b.node !== undefined && !isRef(b.node)) return reply.code(400).send({ error: "bad node" });
    return act(request, reply, async () => ({
      result: { doc: (await net.request({ op: "master.pause", on: b.on, ...(b.node ? { node: b.node } : {}) })).doc as NetDoc },
      audit: { action: "NET_PAUSE", detail: { on: b.on, node: b.node } },
    }));
  });

  app.post<{ Body: { on?: unknown } }>("/api/net/link", async (request, reply) => {
    const on = request.body?.on;
    if (typeof on !== "boolean") return reply.code(400).send({ error: "on must be boolean" });
    return act(request, reply, async () => ({
      result: { doc: (await net.request({ op: "master.link", on })).doc as NetDoc },
      audit: { action: "NET_LINK", detail: { on } },
    }));
  });

  app.post<{ Body: { node?: unknown; kind?: unknown; value?: unknown; in_s?: unknown; deadline?: unknown } }>("/api/net/goal", async (request, reply) => {
    const b = request.body ?? {};
    if (!isRef(b.node)) return reply.code(400).send({ error: "node is required" });
    if (typeof b.kind !== "string" || !/^[a-z_]{1,32}$/.test(b.kind)) return reply.code(400).send({ error: "kind is required (open, lockdown, trace, ice…)" });
    if (b.value !== undefined && (typeof b.value !== "number" || !Number.isFinite(b.value))) return reply.code(400).send({ error: "value must be a number" });
    if ((b.in_s === undefined) === (b.deadline === undefined)) return reply.code(400).send({ error: "set either in_s or deadline" });
    if (b.in_s !== undefined && !isInt(b.in_s, 1, 86_400)) return reply.code(400).send({ error: "in_s must be 1..86400" });
    if (b.deadline !== undefined && !isInt(b.deadline, 1, Number.MAX_SAFE_INTEGER)) return reply.code(400).send({ error: "deadline must be a time in ms" });
    const goal = { node: b.node, kind: b.kind, ...(b.value !== undefined ? { value: b.value } : {}), ...(b.in_s !== undefined ? { in_s: b.in_s } : { deadline: b.deadline }) };
    return act(request, reply, async () => ({
      result: { doc: (await net.request({ op: "master.goal", ...goal })).doc as NetDoc },
      audit: { action: "NET_GOAL", detail: goal },
    }));
  });

  app.post<{ Body: { node?: unknown } }>("/api/net/goal/clear", async (request, reply) => {
    const node = request.body?.node;
    if (!isRef(node)) return reply.code(400).send({ error: "node is required" });
    return act(request, reply, async () => ({
      result: { doc: (await net.request({ op: "master.goal_clear", node })).doc as NetDoc },
      audit: { action: "NET_GOAL", detail: { node, cleared: true } },
    }));
  });

  app.post<{ Body: { req?: unknown; decision?: unknown } }>("/api/net/decide", async (request, reply) => {
    const b = request.body ?? {};
    if (typeof b.req !== "string" || b.req.length === 0 || b.req.length > 200) return reply.code(400).send({ error: "req is required" });
    if (b.decision !== "approve" && b.decision !== "deny") return reply.code(400).send({ error: "decision must be approve or deny" });
    return act(request, reply, async () => ({
      result: { doc: (await net.request({ op: "master.decide", req: b.req, decision: b.decision })).doc as NetDoc },
      audit: { action: "NET_DECIDE", detail: { req: b.req, decision: b.decision } },
    }));
  });

  app.post<{ Body: { query?: unknown; mid?: unknown; text?: unknown } }>("/api/net/reply", async (request, reply) => {
    const b = request.body ?? {};
    if (!isRef(b.query)) return reply.code(400).send({ error: "query is required" });
    if (typeof b.mid !== "string" || b.mid.length === 0 || b.mid.length > 64) return reply.code(400).send({ error: "mid is required (max 64)" });
    const text = typeof b.text === "string" ? b.text.trim() : "";
    if (text.length === 0 || text.length > 2000) return reply.code(400).send({ error: "text must be 1..2000 chars" });
    return act(request, reply, async () => ({
      result: { doc: (await net.request({ op: "master.reply", query: b.query, mid: b.mid, text })).doc as NetDoc },
      audit: { action: "NET_REPLY", detail: { query: b.query, text: text.slice(0, 200) } },
    }));
  });

  app.post<{ Body: { template?: unknown; nodes?: unknown } }>("/api/net/template/apply", async (request, reply) => {
    const b = request.body ?? {};
    if (!isRef(b.template)) return reply.code(400).send({ error: "template is required" });
    if (b.nodes !== undefined && !(Array.isArray(b.nodes) && b.nodes.length <= 100 && b.nodes.every(isRef))) return reply.code(400).send({ error: "nodes must be a list of node ids" });
    const nodes = (b.nodes as string[] | undefined) ?? [];
    return act(request, reply, async () => ({
      result: await net.request({ op: "master.template_apply", template: b.template, ...(nodes.length > 0 ? { nodes } : {}) }),
      audit: { action: "NET_TEMPLATE", detail: { template: b.template, nodes } },
    }));
  });

  /**
   * Проверка «в Сеть входят только отмеченные нетраннеры» — settings/global.require_allowed. Включает мастер: пока выключено, Мост
   * проверяет только блокировку. Остальные поля настроек сохраняются; нет документа настроек — 404, создавать его за Мост незачем.
   */
  app.post<{ Body: { on?: unknown } }>("/api/net/require-allowed", async (request, reply) => {
    const on = request.body?.on;
    if (typeof on !== "boolean") return reply.code(400).send({ error: "on must be boolean" });
    return act(request, reply, async () => {
      const doc = await net.putDoc("settings", "global", (cur) => {
        if (cur === null) return null;
        if ((cur.require_allowed === true) === on) return null;
        return { ...cur, require_allowed: on };
      });
      if (!doc) throw new BridgeError("not_found", "settings/global");
      return { result: { doc: doc as NetDoc }, audit: { action: "NET_REQUIRE_ALLOWED", detail: { on } } };
    });
  });

  /** Снять тревогу (аудитора, сервера мира) — мастер «принял к сведению». Версию присылает экран: если тревога успела измениться, Мост ответит version_conflict. */
  app.delete<{ Params: { id: string }; Querystring: { ver?: string } }>("/api/net/alerts/:id", async (request, reply) => {
    const id = request.params.id;
    if (!isRef(id)) return reply.code(400).send({ error: "bad alert id" });
    const ver = Number(request.query.ver);
    if (!isInt(ver, 1, Number.MAX_SAFE_INTEGER)) return reply.code(400).send({ error: "ver is required" });
    return act(request, reply, async () => {
      await net.request({ op: "del", type: "alert", id, ver });
      return { result: { ok: true }, audit: { action: "NET_ALERT_CLEAR", detail: { alert: id } } };
    });
  });

  /**
   * Ручная операция с ценностями. rid создаёт экран ОДИН раз на нажатие и при повторе (обрыв, двойное нажатие) шлёт тот же:
   * Мост по rid не выполнит второй раз, а вернёт сохранённый ответ с replayed: true. Коллектор rid не придумывает и не меняет —
   * иначе повтор перестал бы быть повтором и предмет выдался бы дважды.
   */
  app.post<{ Body: { op?: unknown; rid?: unknown; params?: unknown } }>("/api/net/ops", async (request, reply) => {
    const b = request.body ?? {};
    if (typeof b.op !== "string" || !(VALUE_OPS as readonly string[]).includes(b.op)) return reply.code(400).send({ error: `op must be one of: ${VALUE_OPS.join(", ")}` });
    if (typeof b.rid !== "string" || b.rid.length === 0 || b.rid.length > RID_MAX) return reply.code(400).send({ error: `rid is required (max ${RID_MAX})` });
    if (b.params !== undefined && (typeof b.params !== "object" || b.params === null || Array.isArray(b.params))) return reply.code(400).send({ error: "params must be an object" });
    const params = (b.params ?? {}) as Record<string, unknown>;
    // op/rid/служебные поля конверта из params не принимаем: иначе params перебил бы то, что проверено выше.
    const { op: _op, rid: _rid, v: _v, cid: _cid, ...rest } = params;
    return act(request, reply, async () => {
      const r = await net.request({ ...rest, op: b.op, rid: b.rid });
      return { result: r, audit: { action: "NET_OP", detail: { op: b.op, rid: b.rid, replayed: r.replayed === true } } };
    });
  });

  // ── Наполнение узлов из «Мастерской» (docs/netrun-bridge-protocol.md, master.stock_node / master.unstock_node) ──

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

  const ridOk = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= RID_MAX;
  const eddiesOk = (v: unknown) => v === undefined || isInt(v, 0, 1_000_000_000);

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
      const r = (await net.request({ op: "master.stock_node", rid: b.rid, node, items, eddies })) as unknown as NetStockResult;
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
      const r = (await net.request({ op: "master.unstock_node", rid: b.rid, node, items, eddies })) as unknown as NetStockResult;
      return { result: r, audit: { action: "NET_UNSTOCK", detail: { node, rid: b.rid, items: items.length, eddies, replayed: r.replayed === true } } };
    });
  });

  // ── Получатели сигнала СБ и владелец узла (docs/netrun-collector-brief.md, задача 3) ──

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
