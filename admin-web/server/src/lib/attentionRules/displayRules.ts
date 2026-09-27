import type { AttentionItem } from "../../apiTypes.js";
import { displayBattery, displayConfigFromEnv } from "../../displays/manager.js";
import { DisplayRepository } from "../../displays/repository.js";
import type { AttentionRule } from "./context.js";

/** Правила про точки на площадке (QR-дисплеи, звуковые точки — docs/sound-nodes.md). */

/**
 * Батарея точки на исходе: КРИТИЧНО — crit, МАЛО — warn (пороги DISPLAY_BATTERY_*: процент и остаток в часах). Выключенные
 * мастером точки не считаются — их батарея никого не подведёт. Точка давно не на связи тоже не считается: её заряд устарел,
 * а «нет связи» видно на экране «Дисплеи».
 */
export const displayBatteryLow: AttentionRule = ({ db, now }) => {
  const cfg = displayConfigFromEnv();
  const repo = new DisplayRepository(db);
  return repo
    .list()
    .filter((row) => row.enabled && row.last_seen_at !== null && now - row.last_seen_at <= cfg.onlineWindowMs)
    .flatMap((row): AttentionItem[] => {
      const b = displayBattery(repo, row, cfg, now);
      if (b.level !== "LOW" && b.level !== "CRITICAL") return [];
      const left = b.hoursLeft !== null ? `, ≈ ${b.hoursLeft < 1 ? `${Math.round(b.hoursLeft * 60)} мин` : `${Math.round(b.hoursLeft)} ч`}` : "";
      return [
        {
          id: `display-battery:${row.id}`,
          kind: "display_battery",
          severity: b.level === "CRITICAL" ? "crit" : "warn",
          title: b.level === "CRITICAL" ? "Точка вот-вот сядет" : "Точке скоро менять батарею",
          detail: `${row.id} (${row.name}): ${b.source === "voltage" ? "~" : ""}${b.percent} %${left}${b.charging ? ", заряжается" : ""}`,
          at: row.last_seen_at ?? now,
        },
      ];
    });
};
