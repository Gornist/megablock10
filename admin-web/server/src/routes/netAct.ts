import type { FastifyReply, FastifyRequest } from "fastify";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { BridgeError, BridgeUnavailableError } from "../net/bridgeProtocol.js";

/** Наибольшая длина rid операции с ценностями (экран создаёт его один раз на нажатие). */
export const RID_MAX = 128;
export const ridOk = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= RID_MAX;

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

/** Мастер + вызов Моста + журнал; отказ Моста — в ответ мастеру, без записи в журнал (ничего не сделано). */
export function makeAct(db: Db) {
  return async <T>(
    request: FastifyRequest,
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
}
