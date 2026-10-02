import { WebSocketServer, type WebSocket } from "ws";
import type { BridgeDoc } from "./bridgeProtocol.js";

/**
 * Минимальный Мост по протоколу C1 (docs/netrun-bridge-protocol.md) — для тестов клиента и разработки экрана «Сеть» без devbox и
 * настоящего Моста. Умеет рукопожатие и роль master, get/list/put/del с проверкой версии, sub с снимком и потоком chg, master.*
 * (пауза, рубильник, цели, решение, ответ, заготовки) и op.issue_to_phone с rid. Это НЕ эталон правил Моста: логики забега,
 * аудитора и ценностей здесь нет — только то, чем пользуется коллектор. Настоящий Мост — netrun/tools/live_run.sh на ветке agent/netrun.
 */

export interface FakeBridgeOptions {
  key?: string;
  port?: number;
  /** Мост без документов — пустая «Сеть». */
  docs?: Omit<BridgeDoc, "created" | "updated" | "ver">[];
}

interface Conn {
  ws: WebSocket;
  role: string | null;
  client: string | null;
  types: Set<string>;
}

const err = (re: unknown, code: string, msg: string, doc?: BridgeDoc) => ({ v: 1, re, ok: false, err: { code, msg, ...(doc ? { doc } : {}) } });

export class FakeBridge {
  readonly docs = new Map<string, BridgeDoc>();
  /** Все запросы, дошедшие до Моста (после hello) — тесты проверяют, что именно отправил коллектор. */
  readonly requests: Record<string, unknown>[] = [];
  seq = 100;
  port = 0;
  private wss: WebSocketServer | null = null;
  private conns = new Set<Conn>();
  private rids = new Map<string, { params: string; reply: Record<string, unknown> }>();
  private readonly key: string;
  private readonly initial: NonNullable<FakeBridgeOptions["docs"]>;
  private readonly wantedPort: number;

  constructor(options: FakeBridgeOptions = {}) {
    this.key = options.key ?? "master-key";
    this.initial = options.docs ?? [];
    this.wantedPort = options.port ?? 0;
  }

  get url(): string {
    return `ws://127.0.0.1:${this.port}/netrun/v1`;
  }

  async start(): Promise<number> {
    const now = Date.now();
    for (const d of this.initial) this.docs.set(`${d.type}/${d.id}`, { ...d, ver: 1, created: now, updated: now });
    this.wss = new WebSocketServer({ port: this.wantedPort, host: "127.0.0.1" });
    await new Promise<void>((resolve) => this.wss!.once("listening", () => resolve()));
    this.wss.on("connection", (ws) => {
      const c: Conn = { ws, role: null, client: null, types: new Set() };
      this.conns.add(c);
      ws.on("message", (data) => this.onMessage(c, data.toString()));
      ws.on("close", () => this.conns.delete(c));
    });
    this.port = (this.wss.address() as { port: number }).port;
    return this.port;
  }

  /** Закрыть все соединения (Мост перезапустился / пропала сеть), но слушать дальше — клиент должен переподключиться. */
  dropClients(): void {
    for (const c of this.conns) c.ws.terminate();
  }

  async stop(): Promise<void> {
    this.dropClients();
    await new Promise<void>((resolve) => (this.wss ? this.wss.close(() => resolve()) : resolve()));
    this.wss = null;
  }

  /** Записать документ «со стороны Моста» (правило, сервер мира) и разослать подписчикам. */
  setDoc(type: string, id: string, data: Record<string, unknown>): BridgeDoc {
    return this.write([{ type, id, data }])[0];
  }

  deleteDoc(type: string, id: string): void {
    const doc = this.docs.get(`${type}/${id}`);
    if (!doc) return;
    this.docs.delete(`${type}/${id}`);
    this.push([{ doc, deleted: true }]);
  }

  doc(type: string, id: string): BridgeDoc | undefined {
    return this.docs.get(`${type}/${id}`);
  }

  private write(changes: { type: string; id: string; data: Record<string, unknown> }[]): BridgeDoc[] {
    const now = Date.now();
    const out = changes.map(({ type, id, data }) => {
      const prev = this.docs.get(`${type}/${id}`);
      const doc: BridgeDoc = { type, id, ver: (prev?.ver ?? 0) + 1, created: prev?.created ?? now, updated: now, data };
      this.docs.set(`${type}/${id}`, doc);
      return doc;
    });
    this.push(out.map((doc) => ({ doc })));
    return out;
  }

  private push(items: { doc: BridgeDoc; deleted?: boolean }[]): void {
    const seq = ++this.seq;
    items.forEach((it, i) => {
      const frame = JSON.stringify({ v: 1, push: "chg", seq, last: i === items.length - 1, ...(it.deleted ? { deleted: true } : {}), doc: it.doc });
      for (const c of this.conns) if (c.types.has(it.doc.type)) c.ws.send(frame);
    });
  }

  private onMessage(c: Conn, text: string): void {
    const m = JSON.parse(text) as Record<string, unknown>;
    const reply = (body: Record<string, unknown>) => c.ws.send(JSON.stringify({ v: 1, re: m.cid, ok: true, ...body }));
    const fail = (code: string, msg: string, doc?: BridgeDoc) => c.ws.send(JSON.stringify(err(m.cid, code, msg, doc)));

    if (m.op === "hello") {
      if (m.proto !== 1) return fail("unsupported_version", "proto");
      if (m.key !== this.key) return fail("unauthorized", "неверный ключ роли");
      c.role = String(m.role);
      c.client = String(m.client);
      return reply({ proto: 1, bridge: "fake-0.1", now: Date.now(), world_pub: "FAKEWORLDPUB" });
    }
    if (!c.role) return fail("unauthorized", "сначала hello");
    this.requests.push(m);

    const isMaster = c.role === "master" || c.role === "test";
    switch (m.op) {
      case "get": {
        const d = this.docs.get(`${m.type}/${m.id}`);
        return d ? reply({ doc: d }) : fail("not_found", `${m.type}/${m.id}`);
      }
      case "list":
        return reply({ seq: this.seq, docs: [...this.docs.values()].filter((d) => d.type === m.type) });
      case "sub": {
        const types = (m.types as string[]) ?? [];
        for (const t of types) c.types.add(t);
        return reply({ seq: this.seq, docs: [...this.docs.values()].filter((d) => types.includes(d.type)) });
      }
      case "unsub":
        for (const t of (m.types as string[]) ?? []) c.types.delete(t);
        return reply({});
      case "put": {
        const cur = this.docs.get(`${m.type}/${m.id}`);
        if (m.ver === 0 && cur) return fail("exists", "документ уже есть", cur);
        if (m.ver !== 0 && !cur) return fail("not_found", `${m.type}/${m.id}`);
        if (cur && m.ver !== cur.ver) return fail("version_conflict", `версия ${cur.ver}, а не ${m.ver}`, cur);
        return reply({ doc: this.write([{ type: String(m.type), id: String(m.id), data: m.data as Record<string, unknown> }])[0] });
      }
      case "del": {
        const cur = this.docs.get(`${m.type}/${m.id}`);
        if (!cur) return fail("not_found", `${m.type}/${m.id}`);
        if (m.ver !== cur.ver) return fail("version_conflict", `версия ${cur.ver}`, cur);
        this.deleteDoc(cur.type, cur.id);
        return reply({});
      }
    }

    if (typeof m.op === "string" && m.op.startsWith("master.")) {
      if (!isMaster) return fail("forbidden", "только master");
      return this.master(m, reply, fail);
    }
    if (m.op === "op.issue_to_phone" || m.op === "op.take_from_node" || m.op === "op.leave_in_node" || m.op === "run.finish") {
      // rid: повтор с теми же параметрами — сохранённый ответ (replayed), с другими — rid_mismatch (раздел 6 протокола).
      const rid = String(m.rid ?? "");
      const { cid: _cid, rid: _rid, ...params } = m;
      const sig = JSON.stringify(params);
      const seen = this.rids.get(`${c.role}/${c.client}/${rid}`);
      if (seen) return seen.params === sig ? reply({ ...seen.reply, replayed: true }) : fail("rid_mismatch", "rid уже использован с другими параметрами");
      const body = { replayed: false, transfers: [], eddies_transfer: null };
      this.rids.set(`${c.role}/${c.client}/${rid}`, { params: sig, reply: body });
      return reply(body);
    }
    return fail("bad_request", `неизвестный op: ${String(m.op)}`);
  }

  private master(m: Record<string, unknown>, reply: (b: Record<string, unknown>) => void, fail: (code: string, msg: string, doc?: BridgeDoc) => void): void {
    const global = () => this.docs.get("settings/global")?.data ?? {};
    switch (m.op) {
      case "master.pause": {
        if (typeof m.node === "string") {
          const cfg = this.docs.get(`node_cfg/${m.node}`);
          if (!this.docs.get(`node/${m.node}`)) return fail("not_found", String(m.node));
          return reply({ doc: this.setDoc("node_cfg", m.node, { ...(cfg?.data ?? {}), paused: m.on === true }) });
        }
        return reply({ doc: this.setDoc("settings", "global", { ...global(), paused: m.on === true, paused_at: Date.now() }) });
      }
      case "master.link":
        return reply({ doc: this.setDoc("settings", "global", { ...global(), venue_link: m.on === true }) });
      case "master.goal": {
        const node = String(m.node);
        if (!this.docs.get(`node/${node}`)) return fail("not_found", node);
        const cfg = this.docs.get(`node_cfg/${node}`);
        const deadline = typeof m.deadline === "number" ? m.deadline : Date.now() + Number(m.in_s ?? 0) * 1000;
        return reply({ doc: this.setDoc("node_cfg", node, { ...(cfg?.data ?? {}), goal: { kind: m.kind, value: m.value, deadline, set_at: Date.now(), done: false, result: null } }) });
      }
      case "master.goal_clear": {
        const node = String(m.node);
        const cfg = this.docs.get(`node_cfg/${node}`);
        if (!cfg) return fail("not_found", node);
        const { goal: _goal, ...rest } = cfg.data;
        return reply({ doc: this.setDoc("node_cfg", node, rest) });
      }
      case "master.decide": {
        const req = this.docs.get(`master_req/${m.req}`);
        if (!req) return fail("not_found", String(m.req));
        if (req.data.state === "decided") return req.data.decision === m.decision ? reply({ doc: req }) : fail("req_state", "уже решено", req);
        return reply({ doc: this.setDoc("master_req", String(m.req), { ...req.data, state: "decided", decision: m.decision, decided_by: "master", decided_at: Date.now() }) });
      }
      case "master.reply": {
        const q = this.docs.get(`net_query/${m.query}`);
        if (!q) return fail("not_found", String(m.query));
        const messages = (q.data.messages as { mid: string }[]) ?? [];
        if (messages.some((x) => x.mid === m.mid)) return reply({ doc: q });
        return reply({ doc: this.setDoc("net_query", String(m.query), { ...q.data, state: "answered", messages: [...messages, { mid: m.mid, from: "master", text: m.text, at: Date.now() }] }) });
      }
      case "master.template_apply": {
        const tpl = this.docs.get(`template/${m.template}`);
        if (!tpl) return fail("not_found", String(m.template));
        const nodes = (m.nodes as string[]) ?? [];
        const t = tpl.data as { settings?: Record<string, unknown>; node_cfg?: Record<string, unknown> };
        if (t.node_cfg && nodes.length === 0) return fail("bad_request", "node_cfg без nodes");
        for (const n of nodes) if (!this.docs.get(`node/${n}`)) return fail("not_found", n);
        if (t.settings) this.setDoc("settings", "global", { ...global(), ...t.settings, template_applied: { id: m.template, at: Date.now() } });
        for (const n of nodes) this.setDoc("node_cfg", n, { ...(this.docs.get(`node_cfg/${n}`)?.data ?? {}), ...(t.node_cfg ?? {}) });
        return reply({ template: m.template, nodes, settings: Object.keys(t.settings ?? {}) });
      }
    }
    return fail("bad_request", `неизвестный op: ${String(m.op)}`);
  }
}
