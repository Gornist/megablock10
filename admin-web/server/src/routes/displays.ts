import type { FastifyInstance } from "fastify";
import { isIP } from "node:net";
import type { DisplayGroup, DisplayItem, DisplayPreview, DisplayPushResponse, DisplayPushResult, DisplaySecretResponse } from "../apiTypes.js";
import type { Db } from "../db/index.js";
import { BACKLIGHT_LEVELS, type DisplayManager, type OpResult } from "../displays/manager.js";
import { DEFAULT_DISPLAY_PORT } from "../displays/protocol.js";
import { bitmapToPngDataUrl, renderQrForDisplay } from "../displays/renderer.js";
import { newDisplaySecret, type DisplayConfigInput } from "../displays/repository.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { containerQrFromDb } from "../lib/containerQr.js";

/** CrowPanel 5.79" в портретной ориентации — панель, под которую делалась первая версия (docs/displays.md). */
// CrowPanel 5.79″ висит горизонтально: родные 792×272.
export const DEFAULT_DISPLAY_WIDTH = 792;
export const DEFAULT_DISPLAY_HEIGHT = 272;

/** id уходит в заголовок кадра (32 байта ASCII) и в URL. */
const DISPLAY_ID = /^[A-Za-z0-9_.-]{1,32}$/;

type Source = { type?: unknown; id?: unknown; qr?: unknown; label?: unknown };
type ConfigBody = {
  id?: unknown;
  name?: unknown;
  ip?: unknown;
  port?: unknown;
  width?: unknown;
  height?: unknown;
  enabled?: unknown;
  groupId?: unknown;
  nodeId?: unknown;
};

type Resolved = { ok: true; qr: string; label: string } | { ok: false; status: number; error: string };

/**
 * Что показать: контейнер из справочника (строка QR собирается тем же кодом, что и «Показать QR» в Мастерской) или готовая
 * строка MB10-QR (шард, RAM — они в БД не хранятся). Картинку сервер рисует сам: браузер не строит кадры и не ходит к дисплеям.
 */
function resolveSource(db: Db, source: Source | undefined): Resolved {
  if (!source || typeof source !== "object") return { ok: false, status: 400, error: "source is required" };
  if (source.type === "container") {
    if (typeof source.id !== "string") return { ok: false, status: 400, error: "source.id is required" };
    const found = containerQrFromDb(db, source.id);
    if (!found.ok) return found;
    return { ok: true, qr: found.qr, label: `контейнер «${found.name}»` };
  }
  if (source.type === "qr") {
    if (typeof source.qr !== "string" || !source.qr.startsWith("MB10:")) return { ok: false, status: 400, error: "source.qr must be an MB10 QR string" };
    const label = typeof source.label === "string" && source.label.trim() ? source.label.trim().slice(0, 120) : `QR ${source.qr.split(":")[1] ?? ""}`;
    return { ok: true, qr: source.qr, label };
  }
  return { ok: false, status: 400, error: "source.type must be container or qr" };
}

function intIn(v: unknown, min: number, max: number): v is number {
  return Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
}

function parseConfig(b: ConfigBody, current?: DisplayConfigInput): { ok: true; value: DisplayConfigInput } | { ok: false; error: string } {
  const name = b.name ?? current?.name;
  const ip = b.ip ?? current?.ip;
  const port = b.port ?? current?.port ?? DEFAULT_DISPLAY_PORT;
  const width = b.width ?? current?.width ?? DEFAULT_DISPLAY_WIDTH;
  const height = b.height ?? current?.height ?? DEFAULT_DISPLAY_HEIGHT;
  const enabled = b.enabled ?? current?.enabled ?? true;
  // groupId: не передан — оставить как было; null — без группы; строка — группа (существование проверяет маршрут).
  const groupId = b.groupId === undefined ? (current?.groupId ?? null) : b.groupId;
  // nodeId — так же: не передан — как было; null — без узла; строка — узел (существование и занятость проверяет маршрут).
  const nodeId = b.nodeId === undefined ? (current?.nodeId ?? null) : b.nodeId;
  if (typeof name !== "string" || !name.trim() || name.length > 64) return { ok: false, error: "name is required (max 64)" };
  if (typeof ip !== "string" || isIP(ip) === 0) return { ok: false, error: "ip must be an IP address (displays have fixed addresses)" };
  if (!intIn(port, 1, 65535)) return { ok: false, error: "port must be 1..65535" };
  if (!intIn(width, 8, 4096) || !intIn(height, 8, 4096)) return { ok: false, error: "width/height must be integers 8..4096" };
  if (typeof enabled !== "boolean") return { ok: false, error: "enabled must be boolean" };
  if (groupId !== null && typeof groupId !== "string") return { ok: false, error: "groupId must be a group id or null" };
  if (nodeId !== null && typeof nodeId !== "string") return { ok: false, error: "nodeId must be a node (container) id or null" };
  return { ok: true, value: { name: name.trim(), ip, port, width, height, enabled, groupId, nodeId } };
}

function preview(qr: string, label: string, width: number, height: number): DisplayPreview {
  const r = renderQrForDisplay(qr, width, height);
  return { qr, label, png: bitmapToPngDataUrl(r), width, height, qrVersion: r.qrVersion, modules: r.modules, scale: r.scale };
}

function resultOf(displayId: string, version: number | undefined, r: OpResult): DisplayPushResult {
  return { displayId, ok: r.outcome === "DISPLAYED", version: r.version ?? version, outcome: r.outcome, error: r.error };
}

/** audioChanged — точки переехали между группами / включились: пересчитать, что им играть (AudioService.sync). */
export function registerDisplayRoutes(app: FastifyInstance, db: Db, displays: DisplayManager, audioChanged: () => void = () => {}) {
  const repo = displays.repo;

  /** Узел точки: существует (400) и не занят другой точкой (409) — одна точка на узел. */
  function checkNode(nodeId: string | null | undefined, displayId: string): { status: number; error: string } | null {
    if (!nodeId) return null;
    if (!repo.nodeExists(nodeId)) return { status: 400, error: "unknown node" };
    const taken = repo.displayOfNode(nodeId, displayId);
    if (taken) return { status: 409, error: `node already has a point: ${taken.id}` };
    return null;
  }

  function secretResponse(id: string, secret: string): DisplaySecretResponse {
    const display = displays.get(id)!;
    return { display, secret, provisioning: { id, secret, port: display.port, width: display.width, height: display.height } };
  }

  app.get("/api/displays", async (request, reply): Promise<DisplayItem[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    return displays.list();
  });

  app.get<{ Params: { id: string } }>("/api/displays/:id", async (request, reply): Promise<DisplayItem | void> => {
    if (!requireMaster(db, request, reply)) return;
    const item = displays.get(request.params.id);
    if (!item) return reply.code(404).send({ error: "unknown display" });
    return item;
  });

  app.post<{ Body: ConfigBody }>("/api/displays", async (request, reply): Promise<DisplaySecretResponse | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const b = request.body ?? {};
    if (typeof b.id !== "string" || !DISPLAY_ID.test(b.id)) return reply.code(400).send({ error: "id: letters, digits, '_', '-', '.' (max 32)" });
    if (repo.get(b.id)) return reply.code(409).send({ error: "display with this id already exists" });
    const cfg = parseConfig(b);
    if (!cfg.ok) return reply.code(400).send({ error: cfg.error });
    if (cfg.value.groupId && !repo.getGroup(cfg.value.groupId)) return reply.code(400).send({ error: "unknown group" });
    const bad = checkNode(cfg.value.nodeId, b.id);
    if (bad) return reply.code(bad.status).send({ error: bad.error });
    const secret = newDisplaySecret();
    const id = b.id;
    db.transaction(() => {
      repo.create(id, cfg.value, secret);
      logMasterAction(db, master.id, "DISPLAY_CREATE", { displayId: id, ...cfg.value });
    })();
    return secretResponse(id, secret);
  });

  app.put<{ Params: { id: string }; Body: ConfigBody }>("/api/displays/:id", async (request, reply): Promise<DisplayItem | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const row = repo.get(request.params.id);
    if (!row) return reply.code(404).send({ error: "unknown display" });
    const cfg = parseConfig(request.body ?? {}, {
      name: row.name,
      ip: row.ip,
      port: row.port,
      width: row.width,
      height: row.height,
      enabled: row.enabled === 1,
      groupId: row.group_id,
      nodeId: row.node_id,
    });
    if (!cfg.ok) return reply.code(400).send({ error: cfg.error });
    if (cfg.value.groupId && !repo.getGroup(cfg.value.groupId)) return reply.code(400).send({ error: "unknown group" });
    const bad = checkNode(cfg.value.nodeId, row.id);
    if (bad) return reply.code(bad.status).send({ error: bad.error });
    db.transaction(() => {
      repo.update(row.id, cfg.value);
      logMasterAction(db, master.id, "DISPLAY_UPDATE", { displayId: row.id, ...cfg.value });
    })();
    audioChanged();
    return displays.get(row.id)!;
  });

  // ── Группы (локации) ──

  function groupList(): DisplayGroup[] {
    const counts = new Map<string, number>();
    for (const r of repo.list()) if (r.group_id) counts.set(r.group_id, (counts.get(r.group_id) ?? 0) + 1);
    return repo
      .listGroups()
      .map((g) => ({ id: g.id, name: g.name, count: counts.get(g.id) ?? 0, audioChannelId: g.audio_channel_id, audioVolume: g.audio_volume }));
  }

  function groupName(raw: unknown): string | null {
    return typeof raw === "string" && raw.trim() && raw.trim().length <= 64 ? raw.trim() : null;
  }

  app.get("/api/display-groups", async (request, reply): Promise<DisplayGroup[] | void> => {
    if (!requireMaster(db, request, reply)) return;
    return groupList();
  });

  app.post<{ Body: { name?: unknown } }>("/api/display-groups", async (request, reply): Promise<DisplayGroup | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const name = groupName(request.body?.name);
    if (!name) return reply.code(400).send({ error: "name is required (max 64)" });
    if (repo.groupByName(name)) return reply.code(409).send({ error: "group with this name already exists" });
    const g = db.transaction(() => {
      const created = repo.createGroup(name);
      logMasterAction(db, master.id, "DISPLAY_GROUP_CREATE", { groupId: created.id, name });
      return created;
    })();
    return { id: g.id, name: g.name, count: 0, audioChannelId: null, audioVolume: null };
  });

  app.put<{ Params: { id: string }; Body: { name?: unknown } }>("/api/display-groups/:id", async (request, reply): Promise<DisplayGroup | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const g = repo.getGroup(request.params.id);
    if (!g) return reply.code(404).send({ error: "unknown group" });
    const name = groupName(request.body?.name);
    if (!name) return reply.code(400).send({ error: "name is required (max 64)" });
    const clash = repo.groupByName(name);
    if (clash && clash.id !== g.id) return reply.code(409).send({ error: "group with this name already exists" });
    db.transaction(() => {
      repo.renameGroup(g.id, name);
      logMasterAction(db, master.id, "DISPLAY_GROUP_RENAME", { groupId: g.id, from: g.name, name });
    })();
    return groupList().find((x) => x.id === g.id)!;
  });

  app.delete<{ Params: { id: string } }>("/api/display-groups/:id", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const g = repo.getGroup(request.params.id);
    if (!g) return reply.code(404).send({ error: "unknown group" });
    db.transaction(() => {
      repo.deleteGroup(g.id);
      logMasterAction(db, master.id, "DISPLAY_GROUP_DELETE", { groupId: g.id, name: g.name });
    })();
    audioChanged();
    return { ok: true };
  });

  /** Быстро переложить точку в другую группу (из карточки), не трогая остальные настройки. */
  app.put<{ Params: { id: string }; Body: { groupId?: unknown } }>("/api/displays/:id/group", async (request, reply): Promise<DisplayItem | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const row = repo.get(request.params.id);
    if (!row) return reply.code(404).send({ error: "unknown display" });
    const groupId = request.body?.groupId ?? null;
    if (groupId !== null && (typeof groupId !== "string" || !repo.getGroup(groupId))) return reply.code(400).send({ error: "unknown group" });
    db.transaction(() => {
      repo.setGroup(row.id, groupId);
      logMasterAction(db, master.id, "DISPLAY_SET_GROUP", { displayId: row.id, groupId });
    })();
    audioChanged();
    return displays.get(row.id)!;
  });

  /** Привязать точку к узлу (из карточки узла) или отвязать (nodeId: null), не трогая остальные настройки. */
  app.put<{ Params: { id: string }; Body: { nodeId?: unknown } }>("/api/displays/:id/node", async (request, reply): Promise<DisplayItem | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const row = repo.get(request.params.id);
    if (!row) return reply.code(404).send({ error: "unknown display" });
    const nodeId = request.body?.nodeId ?? null;
    if (nodeId !== null && typeof nodeId !== "string") return reply.code(400).send({ error: "nodeId must be a node (container) id or null" });
    const bad = checkNode(nodeId, row.id);
    if (bad) return reply.code(bad.status).send({ error: bad.error });
    db.transaction(() => {
      repo.setNode(row.id, nodeId);
      logMasterAction(db, master.id, "DISPLAY_SET_NODE", { displayId: row.id, nodeId });
    })();
    return displays.get(row.id)!;
  });

  app.delete<{ Params: { id: string } }>("/api/displays/:id", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const id = request.params.id;
    if (!repo.get(id)) return reply.code(404).send({ error: "unknown display" });
    db.transaction(() => {
      repo.delete(id);
      logMasterAction(db, master.id, "DISPLAY_DELETE", { displayId: id });
    })();
    displays.forget(id);
    return { ok: true };
  });

  /** Новый секрет (старый утёк или плату заменили): показывается один раз, дисплей надо прошить заново. */
  app.post<{ Params: { id: string } }>("/api/displays/:id/secret", async (request, reply): Promise<DisplaySecretResponse | void> => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const id = request.params.id;
    if (!repo.get(id)) return reply.code(404).send({ error: "unknown display" });
    const secret = newDisplaySecret();
    db.transaction(() => {
      repo.setSecret(id, secret);
      logMasterAction(db, master.id, "DISPLAY_SECRET", { displayId: id });
    })();
    return secretResponse(id, secret);
  });

  /** Предпросмотр кадра до отправки: размер по дисплею (displayId) или явный, по умолчанию — CrowPanel 792×272 (горизонтально). */
  app.post<{ Body: { source?: Source; displayId?: unknown } }>("/api/displays/preview", async (request, reply): Promise<DisplayPreview | void> => {
    if (!requireMaster(db, request, reply)) return;
    const b = request.body ?? {};
    const src = resolveSource(db, b.source);
    if (!src.ok) return reply.code(src.status).send({ error: src.error });
    let width = DEFAULT_DISPLAY_WIDTH;
    let height = DEFAULT_DISPLAY_HEIGHT;
    if (typeof b.displayId === "string") {
      const row = repo.get(b.displayId);
      if (!row) return reply.code(404).send({ error: "unknown display" });
      ({ width, height } = row);
    }
    try {
      return preview(src.qr, src.label, width, height);
    } catch (err) {
      return reply.code(422).send({ error: (err as Error).message });
    }
  });

  /** Что сейчас должно быть на дисплее — тем же рендером. */
  app.get<{ Params: { id: string } }>("/api/displays/:id/preview", async (request, reply): Promise<DisplayPreview | void> => {
    if (!requireMaster(db, request, reply)) return;
    const row = repo.get(request.params.id);
    if (!row) return reply.code(404).send({ error: "unknown display" });
    if (!row.desired_qr) return reply.code(404).send({ error: "nothing was sent to this display yet" });
    return preview(row.desired_qr, row.desired_label ?? "", row.width, row.height);
  });

  /**
   * Отправка на один или несколько дисплеев. Каждый обновляется независимо (не «всё или ничего»); по умолчанию ответ сразу —
   * с назначенными версиями, ход видно в GET /api/displays (UPDATING → ONLINE/ERROR). wait: true — дождаться итога по каждому.
   */
  async function push(masterId: string, displayIds: string[], source: Source | undefined, wait: boolean): Promise<{ status: number; body: DisplayPushResponse | { error: string } }> {
    const src = resolveSource(db, source);
    if (!src.ok) return { status: src.status, body: { error: src.error } };
    const results: DisplayPushResult[] = [];
    const waits: Promise<DisplayPushResult>[] = [];
    for (const id of [...new Set(displayIds)]) {
      const row = repo.get(id);
      if (!row) {
        results.push({ displayId: id, ok: false, error: "unknown display" });
        continue;
      }
      if (!row.enabled) {
        results.push({ displayId: id, ok: false, error: "display is disabled" });
        continue;
      }
      try {
        renderQrForDisplay(src.qr, row.width, row.height); // не влезает — сказать сразу, не ставя в очередь
      } catch (err) {
        results.push({ displayId: id, ok: false, error: (err as Error).message });
        continue;
      }
      const job = displays.pushImage(id, src.qr, src.label);
      if (wait) waits.push(job.result.then((r) => resultOf(id, job.version, r)));
      else results.push({ displayId: id, ok: true, version: job.version, outcome: "QUEUED" });
    }
    results.push(...(await Promise.all(waits)));
    logMasterAction(db, masterId, "DISPLAY_PUSH", {
      label: src.label,
      displays: results.map((r) => `${r.displayId}${r.version ? `@${r.version}` : ""}${r.ok ? "" : " ✗"}`).join(", "),
    });
    return { status: 200, body: { label: src.label, results } };
  }

  app.post<{ Body: { displayIds?: unknown; source?: Source; wait?: unknown } }>("/api/displays/push", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const b = request.body ?? {};
    if (!Array.isArray(b.displayIds) || b.displayIds.length === 0 || !b.displayIds.every((x) => typeof x === "string")) {
      return reply.code(400).send({ error: "displayIds must be a non-empty array of ids" });
    }
    const r = await push(master.id, b.displayIds as string[], b.source, b.wait === true);
    return reply.code(r.status).send(r.body);
  });

  app.post<{ Params: { id: string }; Body: { source?: Source; wait?: unknown } }>("/api/displays/:id/push", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    if (!repo.get(request.params.id)) return reply.code(404).send({ error: "unknown display" });
    const r = await push(master.id, [request.params.id], request.body?.source, request.body?.wait === true);
    return reply.code(r.status).send(r.body);
  });

  /** Команды ждут ответа дисплея — они короткие, а мастер у дисплея хочет видеть «сработало/нет» сразу. */
  async function command(masterId: string, id: string, name: string, detail: Record<string, unknown>, run: () => Promise<OpResult>): Promise<{ status: number; body: unknown }> {
    const row = repo.get(id);
    if (!row) return { status: 404, body: { error: "unknown display" } };
    if (!row.enabled) return { status: 409, body: { error: "display is disabled" } };
    logMasterAction(db, masterId, "DISPLAY_COMMAND", { displayId: id, command: name, ...detail });
    const r = await run();
    return { status: 200, body: { ok: r.outcome === "DISPLAYED", error: r.error, display: displays.get(id) } };
  }

  app.post<{ Params: { id: string }; Body: { seconds?: unknown } }>("/api/displays/:id/test", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const seconds = intIn(request.body?.seconds, 1, 600) ? request.body!.seconds : 30;
    const r = await command(master.id, request.params.id, "TEST", { seconds }, () => displays.test(request.params.id, seconds as number));
    return reply.code(r.status).send(r.body);
  });

  app.post<{ Params: { id: string }; Body: { level?: unknown; seconds?: unknown } }>("/api/displays/:id/backlight", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const levelName = request.body?.level;
    if (typeof levelName !== "string" || !(levelName in BACKLIGHT_LEVELS)) return reply.code(400).send({ error: "level must be OFF, LOW, MEDIUM or HIGH" });
    const seconds = intIn(request.body?.seconds, 0, 3600) ? (request.body!.seconds as number) : 0;
    const r = await command(master.id, request.params.id, "BACKLIGHT", { level: levelName, seconds }, () =>
      displays.backlight(request.params.id, BACKLIGHT_LEVELS[levelName], seconds),
    );
    return reply.code(r.status).send(r.body);
  });

  app.post<{ Params: { id: string } }>("/api/displays/:id/reboot", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;
    const r = await command(master.id, request.params.id, "REBOOT", {}, () => displays.reboot(request.params.id));
    return reply.code(r.status).send(r.body);
  });

  /** «Проверить связь»: connect + HELLO сейчас, не дожидаясь планового опроса. */
  app.post<{ Params: { id: string } }>("/api/displays/:id/probe", async (request, reply) => {
    if (!requireMaster(db, request, reply)) return;
    const id = request.params.id;
    if (!repo.get(id)) return reply.code(404).send({ error: "unknown display" });
    const pending = displays.probe(id);
    const r = pending ? await pending : { outcome: "DISPLAYED" as const };
    return { ok: r.outcome === "DISPLAYED", error: r.error, display: displays.get(id) };
  });
}
