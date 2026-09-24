import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import QRCode from "qrcode";
import type { Db } from "../db/index.js";
import { logMasterAction, requireMaster } from "../lib/auth.js";
import { deriveLootKey, encryptLoot } from "../lib/lootCrypto.js";
import { encodeDaemonLoot, encodeShardLoot } from "../lib/lootCodec.js";
import { encodeContainerQr, encodeRamUpgradeQr, encodeShardQr } from "../lib/mb10QrCodec.js";
import { tierLevel } from "../lib/tier.js";
import { validateContainerSlot } from "../lib/containerSlots.js";
import type { ContainerSlot } from "../lib/containerSlots.js";
import { upsertContainer } from "./containers.js";

interface ShardSlotInput {
  title?: unknown;
  meta?: unknown;
  body?: unknown;
  valueHint?: unknown;
  decryptAction?: unknown;
  moneyAmount?: unknown;
}
interface DaemonSlotInput {
  name?: unknown;
  sequence?: unknown;
  effect?: unknown;
}
interface SlotInput {
  type?: unknown;
  tier?: unknown;
  copies?: unknown;
  shard?: ShardSlotInput;
  daemon?: DaemonSlotInput;
}
interface ContainerBody {
  id?: unknown;
  name?: unknown;
  tier?: unknown;
  ownerFaction?: unknown;
  slots?: SlotInput[];
}

/**
 * id попадает в QR как есть, а формат — ':'-разделённый (а slotRef дальше собирается через '#'):
 * id вроде "nasos:4" или "a#b" даёт QR, который приложение разбирает со сдвигом полей или не разбирает вовсе.
 */
const SAFE_ID = /^[A-Za-z0-9_.-]{1,64}$/;

const DAEMON_EFFECTS = new Set(["EXTRACT_SHARD", "EXTRACT_DAEMON", "GHOST", "TIMESKEW", "BLACKOUT", "JITTER", "DECRYPT", "MINER"]);
/** Коды демона склеиваются через ',' внутри LootCodec ("|"-формат) — символы-разделители в коде ломают разбор на телефоне. */
const SAFE_CODE = /^[A-Za-z0-9]{1,8}$/;

/** Деньги в шарде — неотрицательное целое; дробное/отрицательное приложение молча превращало в 0. */
function moneyOrNull(v: unknown): number | null {
  if (v === undefined || v === null) return 0;
  return Number.isSafeInteger(v) && (v as number) >= 0 ? (v as number) : null;
}

/**
 * Генератор QR прямо в дашборде — перенесено из Мастерской в Android-
 * приложении (MasterToolScreen.kt): то же шифрование (AES-256-GCM, тот же
 * ключ, см. lib/lootCrypto.ts) и тот же формат QR (lib/mb10QrCodec.ts),
 * так что игрок сканирует результат обычным сканером приложения — оно не
 * знает и не должно знать, что QR напечатан с ноутбука, а не с телефона
 * мастера. Печатать/показывать с экрана ноутбука удобнее, чем с телефона —
 * вот и весь мотив переноса.
 */
export function registerMasterRoutes(app: FastifyInstance, db: Db) {
  app.post<{ Body: ContainerBody }>("/api/master/containers", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const body = request.body ?? {};
    const name = body.name;
    const tier = body.tier;
    const ownerFaction = body.ownerFaction;
    if (typeof name !== "string" || !name.trim() || typeof tier !== "string" || typeof ownerFaction !== "string" || !ownerFaction.trim()) {
      return reply.code(400).send({ error: "name, tier and ownerFaction are required" });
    }
    if (!Array.isArray(body.slots)) return reply.code(400).send({ error: "slots must be an array" });

    const id = typeof body.id === "string" && body.id.trim() ? body.id : `container-${randomUUID().slice(0, 8)}`;
    if (!SAFE_ID.test(id)) {
      return reply.code(400).send({ error: "id may contain only letters, digits, '_', '-', '.' (max 64)" });
    }
    const slots: ContainerSlot[] = [];
    const lootKey = deriveLootKey(process.env.GAME_SECRET);

    for (const [index, raw] of body.slots.entries()) {
      const type = raw.type === "DAEMON" ? "DAEMON" : "SHARD";
      const slotTier = typeof raw.tier === "string" ? raw.tier : "BASE";
      const copies = Number.isInteger(raw.copies) ? (raw.copies as number) : 0;

      let plain: string;
      let title: string;
      if (type === "SHARD") {
        const s = raw.shard ?? {};
        title = typeof s.title === "string" ? s.title : "";
        if (!title.trim() || typeof s.body !== "string" || !s.body.trim()) {
          return reply.code(400).send({ error: `slot ${index}: shard title/body required` });
        }
        const money = moneyOrNull(s.moneyAmount);
        if (money === null) return reply.code(400).send({ error: `slot ${index}: moneyAmount must be a non-negative integer` });
        plain = encodeShardLoot({
          title,
          meta: typeof s.meta === "string" ? s.meta : "",
          body: s.body,
          valueHint: typeof s.valueHint === "string" ? s.valueHint : "",
          decryptAction: s.decryptAction === true,
          moneyAmount: money,
        });
      } else {
        const d = raw.daemon ?? {};
        title = typeof d.name === "string" ? d.name : "";
        const sequence = Array.isArray(d.sequence) ? d.sequence.filter((x): x is string => typeof x === "string") : [];
        if (!title.trim() || sequence.length === 0) {
          return reply.code(400).send({ error: `slot ${index}: daemon name/sequence required` });
        }
        if (!sequence.every((code) => SAFE_CODE.test(code))) {
          return reply.code(400).send({ error: `slot ${index}: daemon codes must be 1-8 letters/digits` });
        }
        // Неизвестный эффект телефон молча заменял на EXTRACT_SHARD — демон работал не так, как задумал мастер.
        if (d.effect !== undefined && (typeof d.effect !== "string" || !DAEMON_EFFECTS.has(d.effect))) {
          return reply.code(400).send({ error: `slot ${index}: unknown daemon effect` });
        }
        plain = encodeDaemonLoot({
          name: title,
          sequence,
          tierLevel: tierLevel(slotTier),
          effect: typeof d.effect === "string" ? d.effect : "EXTRACT_SHARD",
        });
      }

      const payload = encryptLoot(plain, lootKey);
      // Тот же валидатор, что и у routes/containers.ts — гарантирует, что
      // сгенерированный здесь слот проходит ровно те же проверки (в частности,
      // ловит copies < 0, которое раньше проскакивало мимо Number.isInteger).
      const validated = validateContainerSlot(index, { type, tier: slotTier, copies, title, payload });
      if (!validated.ok) return reply.code(400).send({ error: validated.error });
      slots.push(validated.slot);
    }

    upsertContainer(db, { id, name, tier, ownerFaction, slots });
    logMasterAction(db, master.id, "CONTAINER_CREATED", { containerId: id, name, tier, ownerFaction, slots: slots.length });

    const qr = encodeContainerQr(
      id,
      name,
      tierLevel(tier),
      ownerFaction,
      slots.map((s) => ({ typeName: s.type, tierLevel: tierLevel(s.tier), copies: s.copies, payload: s.payload! })),
    );
    const qrImage = await QRCode.toDataURL(qr, { margin: 1, width: 480 });
    return { containerId: id, qr, qrImage };
  });

  app.post<{
    Body: {
      id?: unknown;
      decryptAction?: unknown;
      tier?: unknown;
      valueHint?: unknown;
      title?: unknown;
      meta?: unknown;
      body?: unknown;
      moneyAmount?: unknown;
    };
  }>("/api/master/shards", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const b = request.body ?? {};
    if (typeof b.title !== "string" || !b.title.trim() || typeof b.body !== "string" || !b.body.trim()) {
      return reply.code(400).send({ error: "title and body are required" });
    }
    const id = typeof b.id === "string" && b.id.trim() ? b.id : `shard-${randomUUID().slice(0, 8)}`;
    if (!SAFE_ID.test(id)) {
      return reply.code(400).send({ error: "id may contain only letters, digits, '_', '-', '.' (max 64)" });
    }
    const money = moneyOrNull(b.moneyAmount);
    if (money === null) return reply.code(400).send({ error: "moneyAmount must be a non-negative integer" });
    const tier = typeof b.tier === "string" ? tierLevel(b.tier) : 1;
    const qr = encodeShardQr(
      id,
      b.decryptAction === true,
      tier,
      typeof b.valueHint === "string" ? b.valueHint : "",
      b.title,
      typeof b.meta === "string" ? b.meta : "",
      b.body,
      money,
    );
    const qrImage = await QRCode.toDataURL(qr, { margin: 1, width: 480 });
    logMasterAction(db, master.id, "QR_SHARD", { shardId: id, title: b.title });
    return { shardId: id, qr, qrImage };
  });

  app.post<{ Body: { delta?: unknown } }>("/api/master/ram", async (request, reply) => {
    const master = requireMaster(db, request, reply);
    if (!master) return;

    const delta = request.body?.delta;
    if (!Number.isInteger(delta) || (delta as number) <= 0) return reply.code(400).send({ error: "delta must be a positive integer" });

    const token = `ram-${randomUUID().slice(0, 8)}`;
    const qr = encodeRamUpgradeQr(token, delta as number);
    const qrImage = await QRCode.toDataURL(qr, { margin: 1, width: 480 });
    logMasterAction(db, master.id, "QR_RAM", { token, delta });
    return { token, qr, qrImage };
  });
}
