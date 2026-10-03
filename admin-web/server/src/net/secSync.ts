import type { Db } from "../db/index.js";
import { getSetting, setSetting } from "../lib/collectorSettings.js";
import { activePlayers, getPlayerBase } from "../lib/playerSummary.js";
import type { NetService } from "./netService.js";
import { PeriodicSync } from "./periodicSync.js";

/** Фракция СБ по умолчанию (получатель сигнала, если у узла нет владельца) — настройка мастера. */
const DEFAULT_FACTION_KEY = "net.sec_default_faction";

/** Документ `settings/sec` для Моста (docs/netrun-collector-brief.md, задача 3): кому из телефонов идёт сигнал СБ `SEC//MB10`. */
export interface SecDoc {
  factions: Record<string, string[]>;
  default_faction: string | null;
}

/** Как документ лежит в Мосте: наши поля плюс пометка, кто писал (лишние поля Мост игнорирует). */
const withMeta = (d: SecDoc) => ({ ...d, updated_by: "collector" });

/** Сравнение по смыслу, а не по порядку: порядок фракций и ключей в документе роли не играет, а лишний put на каждый опрос — шум в Мосте. */
const normalize = (d: SecDoc): string =>
  JSON.stringify({
    default_faction: d.default_faction ?? null,
    factions: Object.keys(d.factions)
      .sort()
      .map((f) => [f, [...d.factions[f]].sort()]),
  });

export function getDefaultFaction(db: Db): string | null {
  return getSetting(db, DEFAULT_FACTION_KEY);
}

export function setDefaultFaction(db: Db, faction: string | null): void {
  setSetting(db, DEFAULT_FACTION_KEY, faction);
}

/**
 * Получатели сигнала СБ по фракциям: ключи ТЕЛЕФОНОВ действующих игроков (заменённые и сбросившие сессию — не получатели:
 * их устройство свободно или это старый телефон). Ключи — обычный base64, как их знает коллектор и сами телефоны.
 */
export function computeSecDoc(db: Db): SecDoc {
  const factions: Record<string, string[]> = {};
  for (const p of activePlayers(getPlayerBase(db))) {
    if (!p.faction) continue;
    (factions[p.faction] ??= []).push(p.publicKeyB64);
  }
  for (const keys of Object.values(factions)) keys.sort();
  return { factions, default_faction: getDefaultFaction(db) };
}

export interface SecSyncStatus {
  /** Мост на связи. Нет — остальные поля неизвестны (копия документов устарела), запись ждёт подключения. */
  connected: boolean;
  /** Документ в Мосте совпадает с тем, что коллектор хочет в нём видеть. */
  inSync: boolean;
  /** Версия документа в Мосте; null — документа нет (сигнал СБ пока никуда не уходит). */
  docVer: number | null;
  lastError: string | null;
}

/**
 * Держит `settings/sec` в Мосте равным составу фракций коллектора: при каждом подключении (в том числе после обрыва и
 * перезапуска Моста) и раз в `intervalMs`. Пишет только когда документ отличается — игроки меняются редко, а Мост не должен
 * получать put впустую. Пока документа нет, Мост сигнал СБ никуда не отправляет — это сознательная безопасная сторона.
 */
export class SecSync extends PeriodicSync {
  constructor(
    private readonly db: Db,
    net: NetService,
    intervalMs = Number(process.env.NET_SEC_SYNC_MS ?? 30_000),
  ) {
    super(net, intervalMs);
  }

  status(): SecSyncStatus {
    if (!this.net.connected) return { connected: false, inSync: false, docVer: null, lastError: this.lastError };
    const cur = this.net.doc("settings", "sec");
    const want = computeSecDoc(this.db);
    const have = cur ? ({ factions: (cur.data.factions as Record<string, string[]>) ?? {}, default_faction: (cur.data.default_faction as string | null) ?? null } satisfies SecDoc) : null;
    return { connected: true, inSync: have !== null && normalize(have) === normalize(want), docVer: cur?.ver ?? null, lastError: this.lastError };
  }

  /** Привести документ к нужному виду. true — записали; false — менять нечего или Моста нет (догонится при подключении/по таймеру). */
  async sync(): Promise<boolean> {
    return this.exclusive(async () => {
      const want = computeSecDoc(this.db);
      let wrote = false;
      await this.net.putDoc("settings", "sec", (cur) => {
        const have: SecDoc | null = cur ? { factions: (cur.factions as Record<string, string[]>) ?? {}, default_faction: (cur.default_faction as string | null) ?? null } : null;
        if (have && normalize(have) === normalize(want)) return null;
        wrote = true;
        return { ...(cur ?? {}), ...withMeta(want) };
      });
      return wrote;
    }, false, (total, next) => total || next);
  }
}
