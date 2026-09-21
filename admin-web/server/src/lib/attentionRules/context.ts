import type { AttentionItem } from "../../apiTypes.js";
import type { Db } from "../../db/index.js";
import { positiveNumber } from "../envNumber.js";
import { makeHumanizeContext } from "../humanize.js";
import { activePlayers, getPlayerBase, isActivePlayer, type PlayerBase } from "../playerSummary.js";

export const MIN = 60 * 1000;

/** Пороги — не «истина», а стартовые значения под типичную экономику; правятся переменными окружения без пересборки. */
export function attentionThresholds() {
  return {
    balanceJump: positiveNumber(process.env.ATTN_BALANCE_JUMP, 1000),
    silentAfterMs: positiveNumber(process.env.ATTN_SILENT_MIN, 10) * MIN,
    silentUntilMs: positiveNumber(process.env.ATTN_SILENT_MAX_MIN, 180) * MIN,
    undeliveredAfterMs: positiveNumber(process.env.ATTN_UNDELIVERED_MIN, 2) * MIN,
    syncStuckMs: positiveNumber(process.env.ATTN_SYNC_STUCK_MIN, 3) * MIN,
    transferStuckMs: positiveNumber(process.env.ATTN_TRANSFER_STUCK_MIN, 10) * MIN,
    /** Как давно может быть запись, чтобы проверки целостности о ней ещё напоминали: иначе давний разрыв висел бы всю игру. */
    integrityWindowMs: positiveNumber(process.env.ATTN_INTEGRITY_HOURS, 12) * 60 * MIN,
  };
}

/** Всё, что нужно правилам: считается один раз на вызов computeAttention и передаётся каждому правилу. */
export interface AttentionContext {
  db: Db;
  now: number;
  t: ReturnType<typeof attentionThresholds>;
  /** Действующие игроки: заменённые и сбросившие сессию (устройство свободно) тревог «нет связи/минус» не дают. */
  players: PlayerBase[];
  inactiveKeys: Set<string>;
  playerName: (key: string) => string;
}

/** Правило — чистая функция от контекста: «что на площадке выглядит неправильно». Ничего не пишет и не решает за мастера. */
export type AttentionRule = (c: AttentionContext) => AttentionItem[];

export function buildAttentionContext(db: Db, now: number): AttentionContext {
  const everyone = getPlayerBase(db);
  return {
    db,
    now,
    t: attentionThresholds(),
    players: activePlayers(everyone),
    inactiveKeys: new Set(everyone.filter((p) => !isActivePlayer(p)).map((p) => p.publicKeyB64)),
    playerName: makeHumanizeContext(db).playerName,
  };
}
