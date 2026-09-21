import type { FastifyInstance, FastifyRequest } from "fastify";
import QRCode from "qrcode";
import type { ProvisionQr, ProvisionsResponse } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { makeHumanizeContext } from "../lib/humanize.js";
import { projectCharacter } from "../lib/projection.js";
import {
  PROVISION_MAX_BALANCE,
  createProvision,
  getProvision,
  listProvisions,
  provisionConfig,
  provisionQrString,
  rawProvision,
  validateProvisionParams,
} from "../lib/provisions.js";

type ParamsBody = { callsign?: unknown; faction?: unknown; balance?: unknown; ram?: unknown };

/**
 * QR персонажа: выдача и повторная выдача (docs/provisioning-qr.md, docs/character-reissue.md). Форма в «Мастерской» создаёт код с нуля,
 * «Выдать заново» на карточке игрока подставляет сохранённые параметры. Адрес сервера и код игры берутся из настроек сервера, мастер их не вводит.
 */
export function registerProvisionRoutes(app: FastifyInstance, db: Db) {
  async function respond(request: FastifyRequest, id: string): Promise<ProvisionQr> {
    const row = rawProvision(db, id)!;
    const cfg = provisionConfig(request);
    const qr = provisionQrString(row, cfg);
    const item = getProvision(db, id, makeHumanizeContext(db).playerName)!;
    return { item, qr, qrImage: await QRCode.toDataURL(qr, { margin: 1, width: 480 }) };
  }

  app.get("/api/provisions", async (request, reply): Promise<ProvisionsResponse | void> => {
    if (!requireMaster(db, request, reply)) return;
    const cfg = provisionConfig(request);
    return {
      config: { url: cfg.url, urlSource: cfg.urlSource, secretSet: cfg.secret !== "" },
      items: listProvisions(db, makeHumanizeContext(db).playerName),
    };
  });

  app.post<{ Body: ParamsBody }>("/api/provisions", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const b = request.body ?? {};
    const checked = validateProvisionParams({ callsign: b.callsign, faction: b.faction ?? "", balance: b.balance ?? 0, ram: b.ram ?? 0 });
    if (!checked.ok) return reply.code(400).send({ error: checked.error });

    const id = createProvision(db, master.name, checked.value);
    logMasterAction(db, master.id, "PROVISION_CREATE", { id, ...checked.value });
    return respond(request, id);
  });

  /** Тот же код ещё раз (потерян лист/погас экран) — только пока он не применён и не погашен. */
  app.get<{ Params: { id: string } }>("/api/provisions/:id/qr", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const row = rawProvision(db, request.params.id);
    if (!row) return reply.code(404).send({ error: "unknown provision" });
    if (row.bound_key !== null || row.void) return reply.code(409).send({ error: "provision is already applied or no longer valid" });
    return respond(request, row.id);
  });

  /**
   * «Выдать заново» с карточки игрока: параметры по умолчанию — сохранённые (в снимке они не стираются сбросом сессии), мастер может
   * поправить любой. Новый код гасит прежний; когда новый телефон применит его, прежний ключ помечается «заменён».
   * Работает и без сброса на телефоне: если телефон потерян или сломан, сбросить сессию нечем.
   */
  app.post<{ Params: { key: string }; Body: ParamsBody }>("/api/players/:key/reissue", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const snapshot = projectCharacter(db, request.params.key);
    if (!snapshot) return reply.code(404).send({ error: "unknown character" });

    const b = request.body ?? {};
    const checked = validateProvisionParams({
      callsign: b.callsign ?? snapshot.callsign,
      faction: b.faction ?? snapshot.faction,
      balance: b.balance ?? Math.min(PROVISION_MAX_BALANCE, Math.max(0, snapshot.balance)),
      ram: b.ram ?? snapshot.ramCapacity,
    });
    if (!checked.ok) return reply.code(400).send({ error: checked.error });

    const id = createProvision(db, master.name, checked.value, request.params.key);
    logMasterAction(db, master.id, "PROVISION_REISSUE", { id, subjectKey: request.params.key, ...checked.value });
    return respond(request, id);
  });
}
