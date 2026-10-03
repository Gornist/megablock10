import type { DisplayItem } from "../../api/types";
import { StatTile } from "../../design/components";

/**
 * Счётчики над списком точек («Устройства», «Локации»): связь, а если хоть одна точка мерит заряд — и батарея.
 * Без данных о батарее второй ряд не показывается: нули там читались бы как «всё в порядке».
 */
export function DeviceStats({ displays }: { displays: DisplayItem[] }) {
  const count = (s: DisplayItem["status"]) => displays.filter((d) => d.status === s).length;
  const withBattery = displays.filter((d) => d.battery !== null);
  const batteryCount = (l: DisplayItem["battery"]) => withBattery.filter((d) => d.battery === l).length;
  return (
    <>
      <div className="stat-row">
        <StatTile label="на связи" value={count("ONLINE")} tone="ok" />
        <StatTile label="обновляются" value={count("UPDATING")} tone="accent" />
        <StatTile label="ошибка" value={count("ERROR")} tone="danger" />
        <StatTile label="нет связи" value={count("OFFLINE")} />
      </div>
      {withBattery.length > 0 && (
        <div className="stat-row">
          <StatTile label="батарея в норме" value={batteryCount("OK")} tone="ok" />
          <StatTile label="батарея: мало" value={batteryCount("LOW")} tone="money" />
          <StatTile label="батарея: критично" value={batteryCount("CRITICAL")} tone="danger" />
        </div>
      )}
    </>
  );
}
