import WebSocket from "ws";
import { BridgeError, BridgeUnavailableError, SUBSCRIBE_TYPES, type BridgeDoc, type BridgeStatus } from "./bridgeProtocol.js";
import { Mirror, type ChangePush } from "./mirror.js";

export interface BridgeClientOptions {
  url: string;
  /** Ключ роли master из конфига Моста (roles.master.key) — только на сервере коллектора, в браузер не уходит. */
  key: string;
  client?: string;
  types?: readonly string[];
  requestTimeoutMs?: number;
  backoffMinMs?: number;
  backoffMaxMs?: number;
  /** Пинг WebSocket (протокол: клиент раз в 10 с, Мост закрывает соединение после 30 с тишины). */
  pingMs?: number;
  log?: (line: string) => void;
}

type Pending = { resolve: (msg: Record<string, unknown>) => void; reject: (e: Error) => void; timer: NodeJS.Timeout; onReply?: (msg: Record<string, unknown>) => void };

/**
 * Одно соединение коллектора с Мостом (роль master): hello → sub → снимок в зеркало → потоком изменения. Обрыв — переподключение
 * с нарастающей паузой, снова hello и sub, новый снимок заменяет копию. Пока Моста нет (`status !== "connected"`), запросы отвечают
 * BridgeUnavailableError, а зеркало пусто: экран честно пишет «Мост недоступен», а не показывает устаревшее как живое.
 */
export class BridgeClient {
  status: BridgeStatus = "down";
  lastError: string | null = null;
  info: { bridge: string; worldPub: string } | null = null;
  readonly mirror = new Mirror();

  private ws: WebSocket | null = null;
  private cid = 0;
  private pending = new Map<string, Pending>();
  private attempt = 0;
  private stopped = true;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private pingTimer: NodeJS.Timeout | null = null;
  private connectedListeners: (() => void)[] = [];
  private readonly o: Required<Omit<BridgeClientOptions, "log">> & { log: (line: string) => void };

  constructor(options: BridgeClientOptions) {
    this.o = {
      client: "collector",
      types: SUBSCRIBE_TYPES,
      requestTimeoutMs: 8000,
      backoffMinMs: 1000,
      backoffMaxMs: 30_000,
      pingMs: 10_000,
      log: () => {},
      ...options,
    };
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = null;
    this.stopPing();
    const ws = this.ws;
    this.ws = null;
    ws?.terminate();
    this.failPending(new BridgeUnavailableError("коллектор остановлен"));
    this.mirror.clear();
    this.status = "down";
  }

  /** Вызвать после каждого (пере)подключения, когда снимок уже в зеркале: догнать то, что копилось без Моста (флаги нетраннеров, получатели СБ). */
  onConnected(listener: () => void): void {
    this.connectedListeners.push(listener);
  }

  /** Запрос к Мосту. ok:false → BridgeError с кодом; нет связи или таймаут → BridgeUnavailableError (повторить с тем же rid). */
  async request(msg: Record<string, unknown>): Promise<Record<string, unknown>> {
    const ws = this.ws;
    if (this.status !== "connected" || !ws) throw new BridgeUnavailableError();
    return this.send(ws, msg);
  }

  private connect(): void {
    this.status = "connecting";
    const ws = new WebSocket(this.o.url);
    this.ws = ws;
    ws.on("open", () => void this.handshake(ws));
    ws.on("message", (data) => this.onMessage(ws, data.toString()));
    ws.on("close", () => this.onClose(ws));
    ws.on("error", (e) => {
      this.lastError = e.message;
    });
  }

  private async handshake(ws: WebSocket): Promise<void> {
    try {
      const hello = await this.send(ws, { op: "hello", proto: 1, role: "master", client: this.o.client, key: this.o.key });
      // Снимок кладём в зеркало в тот же момент, когда пришёл ответ на sub (а не в продолжении после await): пуши chg могут идти
      // следом в том же тике, и снимок, применённый позже них, затёр бы их — копия молча осталась бы устаревшей.
      await this.send(ws, { op: "sub", types: [...this.o.types] }, (snap) =>
        this.mirror.replaceSnapshot((snap.docs as BridgeDoc[] | undefined) ?? [], Number(snap.seq ?? 0)),
      );
      if (ws !== this.ws) return;
      this.info = { bridge: String(hello.bridge ?? ""), worldPub: String(hello.world_pub ?? "") };
      this.attempt = 0;
      this.lastError = null;
      this.status = "connected";
      this.pingTimer = setInterval(() => ws.ping(), this.o.pingMs);
      this.pingTimer.unref();
      this.o.log(`[NET] Мост на связи: ${this.o.url}, seq=${this.mirror.seq}`);
      for (const l of this.connectedListeners) l();
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : String(e);
      this.o.log(`[NET] рукопожатие с Мостом не удалось: ${this.lastError}`);
      ws.terminate();
    }
  }

  private send(ws: WebSocket, msg: Record<string, unknown>, onReply?: (msg: Record<string, unknown>) => void): Promise<Record<string, unknown>> {
    const cid = `c${++this.cid}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(cid);
        reject(new BridgeUnavailableError("Мост не ответил вовремя"));
      }, this.o.requestTimeoutMs);
      this.pending.set(cid, { resolve, reject, timer, onReply });
      ws.send(JSON.stringify({ v: 1, cid, ...msg }), (err) => {
        if (!err) return;
        clearTimeout(timer);
        this.pending.delete(cid);
        reject(new BridgeUnavailableError(err.message));
      });
    });
  }

  private onMessage(ws: WebSocket, text: string): void {
    if (ws !== this.ws) return;
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(text) as Record<string, unknown>;
    } catch {
      return;
    }
    if (typeof msg.re === "string") {
      const p = this.pending.get(msg.re);
      if (!p) return;
      clearTimeout(p.timer);
      this.pending.delete(msg.re);
      if (msg.ok === false) {
        const err = (msg.err ?? {}) as { code?: string; msg?: string; doc?: BridgeDoc };
        p.reject(new BridgeError(err.code ?? "internal", err.msg ?? "ошибка Моста", err.doc));
      } else {
        p.onReply?.(msg);
        p.resolve(msg);
      }
    } else if (msg.push === "chg") {
      this.mirror.apply(msg as unknown as ChangePush);
    }
  }

  private onClose(ws: WebSocket): void {
    if (ws !== this.ws) return;
    this.ws = null;
    this.stopPing();
    this.failPending(new BridgeUnavailableError("связь с Мостом оборвалась"));
    this.mirror.clear();
    this.status = "down";
    if (this.stopped) return;
    // Пауза растёт 1 → 2 → 4 … до потолка, с небольшим разбросом, чтобы перезапуск Моста не встречал все клиенты в одну миллисекунду.
    const delay = Math.min(this.o.backoffMaxMs, this.o.backoffMinMs * 2 ** this.attempt) * (0.85 + Math.random() * 0.3);
    this.attempt++;
    this.o.log(`[NET] Моста нет, повтор через ${Math.round(delay)} мс${this.lastError ? ` (${this.lastError})` : ""}`);
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
    this.reconnectTimer.unref();
  }

  private stopPing(): void {
    if (this.pingTimer) clearInterval(this.pingTimer);
    this.pingTimer = null;
  }

  private failPending(e: Error): void {
    for (const p of this.pending.values()) {
      clearTimeout(p.timer);
      p.reject(e);
    }
    this.pending.clear();
  }
}
