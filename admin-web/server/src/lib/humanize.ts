import type { Db } from "../db/index.js";

/**
 * Перевод сырой записи изменения (field/reason/source_ref/JSON) в фразу для мастера.
 * Сырые поля остаются в записи — дашборд прячет их под «детали»; тут только человекочитаемая часть.
 * Фразы без рода глагола («перевод 100 €$ → Bob», «взлом узла … — успех»), потому что подлежащее — игрок, а его пол мы не знаем.
 */
import type { ChangeKind, HumanChange } from "../apiTypes.js";

export type { HumanChange };

export interface ChangeRowLike {
  subject_key: string;
  field: string;
  old_value: string | null;
  new_value: string | null;
  reason: string;
  source_ref: string | null;
  actor: string;
}

export interface HumanizeContext {
  playerName(key: string): string;
  containerName(containerId: string): string | null;
  /** Второй участник парной записи (перевода/передачи предмета) с тем же source_ref. */
  peerName(sourceRef: string | null, subjectKey: string, reasons: string[]): string | null;
  /** Название демона/шарда по id из истории того же игрока (в записях remove лежит только id). */
  itemTitle(subjectKey: string, field: "daemons.add" | "shards.add", id: string): string | null;
}

const TIER_RU: Record<string, string> = { BASE: "базовый", HARD: "сложный", NIGHTMARE: "кошмар", "1": "базовый", "2": "сложный", "3": "кошмар" };
const OUTCOME_RU: Record<string, string> = { success: "успех", partial: "частично", fail: "провал" };
const BLOCK_RU: Record<string, string> = { NO_LINK: "нет связи с сетью игры", COOLDOWN: "узел остывает после прошлого взлома", EXHAUSTED: "тираж узла исчерпан" };

/** Названия причин для фильтров и подписей (клиент берёт их отсюда же по смыслу; ключи — коды причин из протокола). */
export const REASON_LABEL_RU: Record<string, string> = {
  CHARACTER_CREATED: "Создание персонажа",
  CHARACTER_RESET: "Сброс персонажа",
  BREACH_ATTEMPT: "Попытка взлома",
  BREACH_BLOCKED: "Взлом отклонён",
  BREACH_LOOT: "Добыча с узла",
  BREACH_EDDIES: "Эдди за взлом",
  SHARD_SCAN: "Скан шарда",
  SHARD_DECRYPT: "Расшифровка шарда",
  TRANSFER_OUT: "Перевод (отправка)",
  TRANSFER_IN: "Перевод (получение)",
  TRANSFER_CANCELLED: "Перевод отменён",
  ITEM_TRANSFER_OUT: "Передача предмета (отправка)",
  ITEM_TRANSFER_IN: "Передача предмета (получение)",
  ITEM_TRANSFER_CANCELLED: "Передача предмета отменена",
  RAM_UPGRADE: "Улучшение RAM",
  ALERT_SENT: "Сигнал СБ отправлен",
  ALERT_SUPPRESSED: "Сигнал СБ подавлен",
  MASTER_OVERRIDE: "Правка мастера",
};

function parse<T>(raw: string | null): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

/** Идентификатор узла из source_ref: «containerId:seed», «containerId», «shard:containerId#0», «daemon:containerId#1». */
export function containerIdOfSourceRef(sourceRef: string | null): string | null {
  if (!sourceRef) return null;
  const stripped = sourceRef.replace(/^(shard|daemon):/, "");
  const id = stripped.split(/[#:]/)[0];
  return id || null;
}

const money = (n: number) => `${n} €$`;
const num = (v: string | null) => Number(v ?? 0);

/** Всё, что нужно форматтеру одной записи: сама запись, справочники и готовые помощники «подлежащее/узел/основание». */
interface Fmt {
  row: ChangeRowLike;
  ctx: HumanizeContext;
  done: (kind: ChangeKind, body: string) => HumanChange;
  node: () => string;
}
type Formatter = (f: Fmt) => HumanChange;

const orQ = (v: string | null) => v ?? "?";
const basis = (row: ChangeRowLike) => (row.source_ref ? `. Основание: ${row.source_ref}` : "");

/** Значение мастер поправил сам (MASTER_OVERRIDE) или устройство записало его само — от этого зависит вид записи и тип строки. */
const kindOfScalar = (row: ChangeRowLike): ChangeKind => (row.reason === "MASTER_OVERRIDE" ? "master" : "system");

/** Баланс: по причине записи. */
const BALANCE_BY_REASON: Record<string, (f: Fmt, delta: number, amount: number) => HumanChange> = {
  TRANSFER_OUT: ({ row, ctx, done }, _d, amount) => {
    const peer = ctx.peerName(row.source_ref, row.subject_key, ["TRANSFER_IN"]);
    return done("money", `перевод ${money(amount)} → ${peer ?? "получатель ещё не подтвердил"}`);
  },
  TRANSFER_IN: ({ row, ctx, done }, _d, amount) => done("money", `получен перевод ${money(amount)} от ${ctx.playerName(row.actor)}`),
  TRANSFER_CANCELLED: ({ done }, _d, amount) => done("money", `перевод ${money(amount)} отменён отправителем, деньги вернулись`),
  BREACH_EDDIES: ({ done, node }, _d, amount) => done("money", `+${amount} €$ за взлом узла ${node()}`),
  SHARD_SCAN: ({ done }, delta, amount) => done("money", `${delta >= 0 ? "+" : "−"}${amount} €$ из шарда`),
  BREACH_LOOT: ({ done }, delta, amount) => done("money", `${delta >= 0 ? "+" : "−"}${amount} €$ из шарда`),
  MASTER_OVERRIDE: ({ row, done }) => done("master", `мастер изменил баланс: ${orQ(row.old_value)} → ${orQ(row.new_value)}${basis(row)}`),
};

const formatBalance: Formatter = (f) => {
  const delta = num(f.row.new_value) - num(f.row.old_value);
  const byReason = BALANCE_BY_REASON[f.row.reason];
  return byReason ? byReason(f, delta, Math.abs(delta)) : f.done("money", `баланс ${orQ(f.row.old_value)} → ${orQ(f.row.new_value)}`);
};

const formatRam: Formatter = ({ row, done }) =>
  row.reason === "MASTER_OVERRIDE"
    ? done("master", `мастер изменил буфер RAM: ${orQ(row.old_value)} → ${orQ(row.new_value)}${basis(row)}`)
    : done("system", `буфер RAM ${orQ(row.old_value)} → ${orQ(row.new_value)} (улучшение деки)`);

/** Позывной и фракция различаются только словами: создание/сброс/смена. */
const formatIdentity = (created: (v: string | null) => string, reset: string, changed: string): Formatter => ({ row, done }) => {
  if (row.reason === "CHARACTER_CREATED") return done("system", created(row.new_value));
  if (row.reason === "CHARACTER_RESET") return done("system", reset);
  return done(kindOfScalar(row), `${changed} «${orQ(row.old_value)}» → «${row.new_value}»${row.reason === "MASTER_OVERRIDE" ? basis(row) : ""}`);
};

const ITEM_PEER_OUT = ["ITEM_TRANSFER_OUT"];
const ITEM_PEER_IN = ["ITEM_TRANSFER_IN"];

const formatDaemonAdd: Formatter = ({ row, ctx, done }) => {
  const d = parse<{ name?: string; tier?: string }>(row.new_value);
  const name = d?.name ? `«${d.name}»` : "демон";
  if (row.reason === "ITEM_TRANSFER_IN") return done("item", `получен демон ${name} от ${ctx.peerName(row.source_ref, row.subject_key, ITEM_PEER_OUT) ?? "игрока"}`);
  if (row.reason === "ITEM_TRANSFER_CANCELLED") return done("item", `демон ${name} вернулся: передача отменена`);
  return done("item", `демон ${name}${d?.tier ? ` (тир ${d.tier})` : ""} добавлен в коллекцию`);
};

/** Запись remove несёт только id — название берём из истории того же игрока. */
const formatItemRemove = (idKey: "daemonId" | "shardId", addField: "daemons.add" | "shards.add", noun: string): Formatter => ({ row, ctx, done }) => {
  const title = ctx.itemTitle(row.subject_key, addField, parse<Record<string, string>>(row.new_value)?.[idKey] ?? "");
  return done("item", `${noun} ${title ? `«${title}»` : "из коллекции"} передан → ${ctx.peerName(row.source_ref, row.subject_key, ITEM_PEER_IN) ?? "получатель ещё не принял"}`);
};

const formatShardAdd: Formatter = ({ row, ctx, done, node }) => {
  const s = parse<{ title?: string; tier?: string; decrypted?: boolean }>(row.new_value);
  const title = s?.title ? `«${s.title}»` : "шард";
  const state = s?.decrypted === false ? ", зашифрован" : s?.decrypted ? ", открыт" : "";
  if (row.reason === "ITEM_TRANSFER_IN") return done("item", `получен шард ${title} от ${ctx.peerName(row.source_ref, row.subject_key, ITEM_PEER_OUT) ?? "игрока"}`);
  if (row.reason === "ITEM_TRANSFER_CANCELLED") return done("item", `шард ${title} вернулся: передача отменена`);
  if (row.reason === "BREACH_LOOT") return done("item", `извлечён шард ${title} (тир ${s?.tier ?? "?"}${state}) с узла ${node()}`);
  return done("item", `отсканирован шард ${title} (тир ${s?.tier ?? "?"}${state})`);
};

const formatShardDecrypt: Formatter = ({ row, ctx, done }) => {
  const title = ctx.itemTitle(row.subject_key, "shards.add", parse<{ shardId?: string }>(row.new_value)?.shardId ?? "");
  return done("item", `расшифрован шард ${title ? `«${title}»` : ""}`.trim());
};

const formatBreach: Formatter = ({ row, done, node }) => {
  const p = parse<{ tier?: string; outcome?: string }>(row.new_value);
  const tier = p?.tier ? ` (${TIER_RU[p.tier] ?? p.tier})` : "";
  return done("breach", `взлом узла ${node()}${tier} — ${OUTCOME_RU[p?.outcome ?? ""] ?? p?.outcome ?? "результат неизвестен"}`);
};

const formatBlocked: Formatter = ({ row, done, node }) => {
  const p = parse<{ reason?: string }>(row.new_value);
  return done("breach", `попытка взлома узла ${node()} отклонена: ${BLOCK_RU[p?.reason ?? ""] ?? p?.reason ?? "причина неизвестна"}`);
};

const formatAlert: Formatter = ({ row, done, node }) =>
  parse<{ suppressed?: boolean }>(row.new_value)?.suppressed
    ? done("alert", `сигнал СБ по узлу ${node()} не отправлен (подавлен демоном или узел свой)`)
    : done("alert", `сигнал СБ по узлу ${node()} отправлен владельцам`);

/** Форматтеры по полю записи; неизвестное поле показывается как есть. */
const FORMATTERS: Record<string, Formatter> = {
  balance: formatBalance,
  ramCapacity: formatRam,
  callsign: formatIdentity((v) => `создан персонаж, позывной «${v}»`, "персонаж сброшен на устройстве", "позывной"),
  faction: formatIdentity((v) => `фракция «${v}»`, "фракция сброшена", "фракция"),
  "daemons.add": formatDaemonAdd,
  "daemons.remove": formatItemRemove("daemonId", "daemons.add", "демон"),
  "shards.add": formatShardAdd,
  "shards.remove": formatItemRemove("shardId", "shards.add", "шард"),
  "shards.decrypt": formatShardDecrypt,
  "counters.breach": formatBreach,
  "counters.blocked": formatBlocked,
  "counters.alert": formatAlert,
  announcement: ({ row, done }) => done("master", `сообщение от мастера: «${row.new_value ?? ""}»`),
};

export function humanizeChange(row: ChangeRowLike, ctx: HumanizeContext): HumanChange {
  const subject = ctx.playerName(row.subject_key);
  const f: Fmt = {
    row,
    ctx,
    done: (kind, body) => ({ kind, subject, body }),
    node: () => {
      const id = containerIdOfSourceRef(row.source_ref);
      const name = id ? ctx.containerName(id) : null;
      return name ? `«${name}»` : id ? `«${id}»` : "«неизвестный»";
    },
  };
  return (FORMATTERS[row.field] ?? (({ row: r, done }) => done("system", `${r.field}: ${r.old_value ?? "∅"} → ${r.new_value ?? "∅"}`)))(f);
}

const shortKey = (key: string) => (key.length <= 12 ? key : `${key.slice(0, 6)}…${key.slice(-4)}`);

/** Контекст на одну выдачу: результаты запросов кэшируются, чтобы лента из сотни записей не делала сотни одинаковых обращений к БД. */
export function makeHumanizeContext(db: Db): HumanizeContext {
  const names = new Map<string, string>();
  const containers = new Map<string, string | null>();
  const peers = new Map<string, string | null>();
  const titles = new Map<string, string | null>();

  const nameStmt = db.prepare(`SELECT new_value FROM changes WHERE subject_key = ? AND field = 'callsign' AND new_value IS NOT NULL AND new_value != '' ORDER BY seq DESC LIMIT 1`);
  const containerStmt = db.prepare(`SELECT name FROM containers WHERE id = ?`);
  const peerStmt = (n: number) => db.prepare(`SELECT subject_key FROM changes WHERE source_ref = ? AND subject_key != ? AND reason IN (${Array(n).fill("?").join(",")}) LIMIT 1`);
  const itemStmt = db.prepare(`SELECT new_value FROM changes WHERE subject_key = ? AND field = ? AND new_value LIKE ? ESCAPE '\\' ORDER BY seq DESC LIMIT 1`);

  const playerName = (key: string): string => {
    if (!key) return "неизвестный";
    let n = names.get(key);
    if (n === undefined) {
      n = (nameStmt.get(key) as { new_value: string } | undefined)?.new_value ?? shortKey(key);
      names.set(key, n);
    }
    return n;
  };

  return {
    playerName,
    containerName(id) {
      if (!containers.has(id)) containers.set(id, (containerStmt.get(id) as { name: string } | undefined)?.name ?? null);
      return containers.get(id) ?? null;
    },
    peerName(sourceRef, subjectKey, reasons) {
      if (!sourceRef) return null;
      const cacheKey = `${sourceRef}|${subjectKey}|${reasons.join(",")}`;
      if (!peers.has(cacheKey)) {
        const row = peerStmt(reasons.length).get(sourceRef, subjectKey, ...reasons) as { subject_key: string } | undefined;
        peers.set(cacheKey, row ? playerName(row.subject_key) : null);
      }
      return peers.get(cacheKey) ?? null;
    },
    itemTitle(subjectKey, field, id) {
      if (!id) return null;
      const cacheKey = `${subjectKey}|${field}|${id}`;
      if (!titles.has(cacheKey)) {
        const idKey = field === "daemons.add" ? "daemonId" : "shardId";
        const row = itemStmt.get(subjectKey, field, `%"${idKey}":"${id.replace(/[\\%_]/g, "\\$&")}"%`) as { new_value: string } | undefined;
        const parsed = row ? parse<{ name?: string; title?: string }>(row.new_value) : null;
        titles.set(cacheKey, parsed?.name ?? parsed?.title ?? null);
      }
      return titles.get(cacheKey) ?? null;
    },
  };
}

/** Дописывает к записям готовую человекочитаемую часть (`human`), сырые поля не трогает. */
export function withHuman<T extends ChangeRowLike>(db: Db, rows: T[]): (T & { human: HumanChange })[] {
  const ctx = makeHumanizeContext(db);
  return rows.map((r) => ({ ...r, human: humanizeChange(r, ctx) }));
}
