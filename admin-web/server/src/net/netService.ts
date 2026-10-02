import { BridgeClient, type BridgeClientOptions } from "./bridgeClient.js";
import { BridgeError, BridgeUnavailableError, type BridgeDoc } from "./bridgeProtocol.js";
import type { NetState } from "../apiTypes.js";

/** Адрес и ключ Моста — конфиг сервера (переменные окружения, не репозиторий и не браузер). Нет ключа — функции Моста выключены. */
export function bridgeOptionsFromEnv(env: NodeJS.ProcessEnv = process.env): Pick<BridgeClientOptions, "url" | "key"> | null {
  const key = env.BRIDGE_MASTER_KEY?.trim();
  if (!key) return null;
  return { url: env.BRIDGE_URL?.trim() || "ws://127.0.0.1:7410/netrun/v1", key };
}

/**
 * «Сеть» глазами коллектора: одно соединение с Мостом (BridgeClient), копия документов и операции мастера. Браузер к Мосту не
 * подключается — он ходит сюда по REST под сессией мастера, а сюда доходят только проверенные операции. Нет клиента (Мост не
 * настроен) — всё отвечает «Мост недоступен», остальной коллектор работает как раньше.
 */
export class NetService {
  constructor(private readonly client: BridgeClient | null = null) {}

  get configured(): boolean {
    return this.client !== null;
  }

  start(): void {
    this.client?.start();
  }

  stop(): void {
    this.client?.stop();
  }

  /** После каждого (пере)подключения, когда снимок уже в копии: догнать то, что копилось без Моста. */
  onConnected(listener: () => void): void {
    this.client?.onConnected(listener);
  }

  get connected(): boolean {
    return this.client?.status === "connected";
  }

  /** Копия документа (только пока Мост на связи — иначе undefined: устаревшее «как живое» не отдаём). */
  doc(type: string, id: string): BridgeDoc | undefined {
    return this.connected ? this.client!.mirror.get(type, id) : undefined;
  }

  state(now = Date.now()): NetState {
    if (!this.client) return { configured: false, bridge: "disabled", error: null, info: null, docs: {}, serverNow: now };
    const c = this.client;
    const up = c.status === "connected";
    return {
      configured: true,
      bridge: c.status,
      error: up ? null : c.lastError,
      info: up && c.info ? { version: c.info.bridge, worldPub: c.info.worldPub, seq: c.mirror.seq } : null,
      docs: up ? c.mirror.all() : {},
      serverNow: now,
    };
  }

  /** Запрос к Мосту; Мост не настроен или не на связи — BridgeUnavailableError. */
  async request(msg: Record<string, unknown>): Promise<Record<string, unknown>> {
    if (!this.client) throw new BridgeUnavailableError("Мост не настроен (BRIDGE_MASTER_KEY)");
    return this.client.request(msg);
  }

  /**
   * Своя запись в документ Моста с проверкой версии (docs/netrun-bridge-protocol.md, put): прочитать → изменить → записать; на
   * version_conflict (или exists при создании) взять текущий документ из ответа и повторить. mutate получает прежние данные
   * (null — документа нет) и возвращает новые, либо null — «менять нечего». data при put заменяется целиком, поэтому mutate
   * обязан вернуть полный объект, сохранив чужие поля.
   */
  async putDoc(type: string, id: string, mutate: (current: Record<string, unknown> | null) => Record<string, unknown> | null, attempts = 4): Promise<BridgeDoc | null> {
    let current: BridgeDoc | null = this.doc(type, id) ?? (await this.getDoc(type, id));
    for (let i = 0; i < attempts; i++) {
      const next = mutate(current?.data ?? null);
      if (next === null) return current;
      try {
        const r = await this.request({ op: "put", type, id, ver: current?.ver ?? 0, data: next });
        return r.doc as BridgeDoc;
      } catch (e) {
        if (!(e instanceof BridgeError) || (e.code !== "version_conflict" && e.code !== "exists")) throw e;
        current = e.doc ?? (await this.getDoc(type, id));
      }
    }
    throw new BridgeError("version_conflict", `${type}/${id}: документ меняется быстрее, чем коллектор успевает записать`);
  }

  private async getDoc(type: string, id: string): Promise<BridgeDoc | null> {
    try {
      return (await this.request({ op: "get", type, id })).doc as BridgeDoc;
    } catch (e) {
      if (e instanceof BridgeError && e.code === "not_found") return null;
      throw e;
    }
  }
}
