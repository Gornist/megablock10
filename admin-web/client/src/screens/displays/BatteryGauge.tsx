import type { DisplayItem } from "../../api/types";
import { batteryText } from "./displayUtil";

/**
 * Заряд точки наглядно: батарейка с заливкой по проценту и цветом уровня (НОРМА / МАЛО / КРИТИЧНО), рядом «73 % · ≈ 31 ч».
 * Нет данных (топливомера нет и напряжение не шлётся) — «—», а не ноль: так севшую точку не спутать с неизмеряемой.
 */
export function BatteryGauge({
  d,
}: {
  d: Pick<DisplayItem, "batteryPct" | "battery" | "batteryHoursLeft" | "batteryCharging" | "batterySource" | "batteryMv">;
}) {
  const level = d.battery ?? "NONE";
  const pct = d.batteryPct;
  const title =
    pct === null
      ? "заряд не измеряется (нет топливомера MAX17048)"
      : `${pct} %${d.batteryMv !== null ? `, ${(d.batteryMv / 1000).toFixed(2)} В` : ""}${
          d.batterySource === "voltage" ? " — по напряжению, приблизительно" : " — топливомер"
        }`;
  return (
    <span className={`battery battery-${level.toLowerCase()}`} title={title} aria-label={`батарея: ${batteryText(d)}`}>
      <span className="battery-body">
        <span className="battery-fill" style={{ width: `${pct ?? 0}%` }} />
        {d.batteryCharging && <span className="battery-bolt">⚡</span>}
      </span>
      <span className="battery-text mono">{batteryText(d)}</span>
    </span>
  );
}
