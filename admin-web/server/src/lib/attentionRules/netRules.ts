import type { AttentionItem } from "../../apiTypes.js";
import { parseSafe } from "../json.js";
import { createNetRunners } from "../netRunners.js";
import { recentMasterAlerts } from "../worldEventLog.js";
import type { AttentionRule } from "./context.js";

/** Правила про «Сеть» (Мост, нетраннеры): то, на что мастер должен отреагировать сразу. Тревоги Моста поверх сюда добавит экран «Сеть». */

/**
 * Флэтлайн: нетраннера поймал Black ICE, допуск в Сеть закрыт до решения мастера. Программа персонажа не убивает — она приносит
 * мастеру эту карточку. Пока флаг стоит, тревога срочная: решить надо до того, как игрок вернётся к стойке. Ссылка ведёт на игрока,
 * если он известен коллектору (ключ мира в игроки не попадает, а вот нетраннер — обычный игрок со своим телефоном).
 */
export const netFlatline: AttentionRule = ({ db, players, playerName }) => {
  const known = new Set(players.map((p) => p.publicKeyB64));
  return createNetRunners(db)
    .list()
    .filter((f) => f.blocked)
    .map((f): AttentionItem => {
      const where = [f.node ? `узел ${f.node}` : null, f.terminal ? `терминал ${f.terminal}` : null].filter(Boolean).join(", ");
      const left = f.detail?.left_in_node;
      return {
        id: `flatline:${f.runnerKey}`,
        kind: "net_flatline",
        severity: "crit",
        title: "ФЛЭТЛАЙН — решите судьбу нетраннера",
        detail: `${f.callsign || playerName(f.runnerKey)}: ${f.reason ?? "флэтлайн"}${where ? ` (${where})` : ""}${typeof left === "number" && left > 0 ? `; в узле осталось предметов: ${left}` : ""}`,
        ...(known.has(f.runnerKey) ? { subjectKey: f.runnerKey } : {}),
        at: f.blockedAt ?? f.updatedAt,
      };
    });
};

/**
 * Тревоги аудитора Моста (рассинхрон предметов и эдди, «аудитор молчит»): единственные записи мира, на которые мастер реагирует
 * сразу. Тревога флэтлайна отдельно не дублируется — она уже карточка выше. Снятие тревоги делается на Мосте и записью не
 * сопровождается, поэтому показываем за окно целостности (ATTN_INTEGRITY_HOURS) — мастер может отложить или принять к сведению.
 */
export const netAuditorAlerts: AttentionRule = ({ db, now, t }) => {
  const rows = db
    .prepare(`SELECT source_ref, new_value, received_at FROM changes WHERE field = 'net.alert' AND received_at > ? ORDER BY received_at DESC LIMIT 100`)
    .all(now - t.integrityWindowMs) as { source_ref: string | null; new_value: string | null; received_at: number }[];
  const items: AttentionItem[] = [];
  for (const r of rows) {
    const v = parseSafe<{ kind?: string; msg?: string }>(r.new_value);
    if (!v || v.kind === "flatline") continue;
    items.push({
      id: `net-alert:${r.source_ref ?? r.received_at}`,
      kind: "net_alert",
      severity: "crit",
      title: "Тревога аудитора Сети",
      detail: `${v.kind ?? "без вида"}: ${v.msg ?? "без описания"}`,
      at: r.received_at,
    });
  }
  return items;
};

/**
 * Быстрое событие `alert.master` — новая тревога аудитора, «звонок мастеру» (docs/netrun-world-records.md, §3): на площадку оно не
 * идёт, живёт секунды и в записи синка не дублируется (тревога аудитора приходит отдельно, NET_ALERT). Здесь оно просто заметно
 * сразу, пока мастер у экрана.
 */
export const netMasterAlert: AttentionRule = ({ now }) =>
  recentMasterAlerts(now).map(
    (a): AttentionItem => ({
      id: `net-master-alert:${a.id}`,
      kind: "net_master_alert",
      severity: "crit",
      title: "Сеть зовёт мастера",
      detail: [a.node ? `узел ${a.node}` : null, a.terminal ? `терминал ${a.terminal}` : null].filter(Boolean).join(", ") || "новая тревога аудитора",
      at: a.at,
    }),
  );
