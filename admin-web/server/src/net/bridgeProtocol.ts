/**
 * Протокол Моста «Сети» (docs/netrun-bridge-protocol.md, C1) — то, что нужно коллектору как клиенту роли `master`.
 * Протокол — контракт соседней сессии: здесь только его отражение, неудобное в нём не обходим, а возвращаем ей вопросом.
 */

export interface BridgeDoc {
  type: string;
  id: string;
  /** +1 на каждое изменение; put принимает версию, которую клиент видел (0 — создать). */
  ver: number;
  created: number;
  updated: number;
  data: Record<string, unknown>;
}

/** Типы документов, на которые коллектор подписан: всё, что показывает экран «Сеть». `item` и `runner` — не подписываем (предметов много, runner читаем по требованию). */
export const SUBSCRIBE_TYPES = ["node", "node_cfg", "session", "deck", "terminal", "alert", "master_req", "net_query", "template", "settings"] as const;

/** Ответ Моста `ok: false`: код из таблицы раздела 2 протокола, сообщение и (для конфликтов) текущий документ. */
export class BridgeError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly doc?: BridgeDoc,
  ) {
    super(message);
    this.name = "BridgeError";
  }
}

/** Моста нет на связи (не настроен, обрыв, таймаут): операцию можно повторить позже с тем же rid. */
export class BridgeUnavailableError extends Error {
  constructor(message = "Мост недоступен") {
    super(message);
    this.name = "BridgeUnavailableError";
  }
}

export type BridgeStatus = "connecting" | "connected" | "down";
