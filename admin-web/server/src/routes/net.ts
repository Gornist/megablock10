import type { FastifyInstance } from "fastify";
import type { NetRunnerFlagItem } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { makeHumanizeContext } from "../lib/humanize.js";
import { createNetRunners, normalizeRunnerKey, type NetRunnerFlag } from "../lib/netRunners.js";

/**
 * «Сеть» на стороне коллектора. Здесь — допуск нетраннера: флаг ставится приёмом NET_FLATLINE, мастер «щадит» или закрывает
 * допуск вручную. Коллектор — источник правды (решение владельца, docs/netrun.md): Мост читает флаг, а не наоборот.
 * Ключ игрока в адресе — base64 (с %-кодированием «+», «/», «=») или base64url, как у Моста; оба вида приводятся к одному.
 */
export function registerNetRoutes(app: FastifyInstance, db: Db) {
  const runners = createNetRunners(db);
  const names = () => makeHumanizeContext(db);

  const view = (f: NetRunnerFlag, playerName: (k: string) => string, known: Set<string>): NetRunnerFlagItem => ({
    runnerKey: f.runnerKey,
    callsign: f.callsign || playerName(f.runnerKey),
    blocked: f.blocked,
    reason: f.reason,
    session: f.session,
    node: f.node,
    terminal: f.terminal,
    detail: f.detail,
    blockedAt: f.blockedAt,
    sparedAt: f.sparedAt,
    sparedBy: f.sparedBy,
    bridgeSynced: f.bridgeSynced,
    knownPlayer: known.has(f.runnerKey),
  });
  const knownKeys = () => new Set((db.prepare(`SELECT DISTINCT subject_key FROM changes WHERE field NOT LIKE 'net.%'`).all() as { subject_key: string }[]).map((r) => r.subject_key));

  app.get("/api/net/runners", async (request, reply): Promise<NetRunnerFlagItem[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    const ctx = names();
    const known = knownKeys();
    return runners.list().map((f) => view(f, ctx.playerName, known));
  });

  /** Флаг одного игрока; нет флага — допуск открыт (blocked: false), а не 404: так экрану игрока не нужна особая ветка. */
  app.get<{ Params: { key: string } }>("/api/net/runners/:key", async (request, reply): Promise<NetRunnerFlagItem | { blocked: false } | void> => {
    if (!requireMaster(db, request, reply)) return;
    const key = normalizeRunnerKey(request.params.key);
    if (!key) return reply.code(400).send({ error: "bad runner key" });
    const flag = runners.get(key);
    if (!flag) return { blocked: false };
    return view(flag, names().playerName, knownKeys());
  });

  app.post<{ Params: { key: string }; Body: { note?: unknown } }>("/api/net/runners/:key/spare", async (request, reply): Promise<NetRunnerFlagItem | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const key = normalizeRunnerKey(request.params.key);
    if (!key) return reply.code(400).send({ error: "bad runner key" });
    const note = typeof request.body?.note === "string" ? request.body.note.trim().slice(0, 300) : "";
    const before = runners.get(key);
    if (!runners.spare(key, master.name, Date.now())) return reply.code(404).send({ error: "no flag for this runner" });
    // Повтор по уже снятому флагу — без второй записи в журнал: действие не меняет ничего.
    if (before?.blocked) logMasterAction(db, master.id, "NET_RUNNER_SPARE", { runnerKey: key, note: note || undefined });
    return view(runners.get(key)!, names().playerName, knownKeys());
  });

  app.post<{ Params: { key: string }; Body: { reason?: unknown } }>("/api/net/runners/:key/block", async (request, reply): Promise<NetRunnerFlagItem | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const key = normalizeRunnerKey(request.params.key);
    if (!key) return reply.code(400).send({ error: "bad runner key" });
    // Закрыть допуск можно только игроку, которого коллектор знает: иначе мастер блокировал бы опечатку в ключе.
    if (!knownKeys().has(key)) return reply.code(404).send({ error: "unknown player" });
    const reason = typeof request.body?.reason === "string" ? request.body.reason.trim().slice(0, 300) : "";
    const before = runners.get(key);
    if (before?.blocked) return view(before, names().playerName, knownKeys());
    runners.block(key, reason, Date.now());
    logMasterAction(db, master.id, "NET_RUNNER_BLOCK", { runnerKey: key, reason: reason || undefined });
    return view(runners.get(key)!, names().playerName, knownKeys());
  });
}
