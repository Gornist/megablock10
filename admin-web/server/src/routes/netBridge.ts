import type { FastifyInstance } from "fastify";
import type { NetDoc, NetState } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { requireMaster } from "../lib/auth.js";
import { isIntIn, isRef } from "../lib/refs.js";
import { BridgeError } from "../net/bridgeProtocol.js";
import type { NetService } from "../net/netService.js";
import type { SecSync } from "../net/secSync.js";
import { makeAct, RID_MAX } from "./netAct.js";
import { registerNetSecRoutes } from "./netSec.js";
import { registerNetStockRoutes } from "./netStock.js";

/** Операции с ценностями, которые мастер вправе вызвать вручную («кнопка раньше автоматики»); сдача деки (`op.submit_deck`) — нет, она только от телефона. */
const VALUE_OPS = ["op.issue_to_phone", "op.take_from_node", "op.leave_in_node", "run.finish"] as const;

/**
 * Инструменты мастера «Сети» (docs/netrun-bridge-protocol.md, §6a): браузер вызывает REST коллектора под сессией мастера, а
 * коллектор отправляет в Мост master.* / op.* по своему единственному соединению (роль master). Каждое действие — в журнале.
 */
export function registerNetBridgeRoutes(app: FastifyInstance, db: Db, net: NetService, secSync: SecSync) {
  const act = makeAct(db);

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
    if (b.in_s !== undefined && !isIntIn(b.in_s, 1, 86_400)) return reply.code(400).send({ error: "in_s must be 1..86400" });
    if (b.deadline !== undefined && !isIntIn(b.deadline, 1, Number.MAX_SAFE_INTEGER)) return reply.code(400).send({ error: "deadline must be a time in ms" });
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
    if (!isIntIn(ver, 1, Number.MAX_SAFE_INTEGER)) return reply.code(400).send({ error: "ver is required" });
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

  registerNetStockRoutes(app, db, net);
  registerNetSecRoutes(app, db, net, secSync);
}
