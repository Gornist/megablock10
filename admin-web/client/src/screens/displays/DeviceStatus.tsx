import type { DisplayItem, DisplayStatus } from "../../api/types";
import { Badge } from "../../design/components";
import { BatteryGauge } from "./BatteryGauge";
import { STATUS_LABEL, STATUS_TONE } from "./displayUtil";

/** Связь точки значком: «на связи», «нет связи», «обновляется»… — одинаково во всех списках и карточках. */
export function StatusBadge({ status }: { status: DisplayStatus }) {
  return <Badge tone={STATUS_TONE[status]}>{STATUS_LABEL[status]}</Badge>;
}

/** Связь и батарея рядом — правый край строки точки на «Локациях» и заголовка карточки точки. */
export function StatusAndBattery({ d }: { d: DisplayItem }) {
  return (
    <span className="display-card-status">
      <StatusBadge status={d.status} />
      <BatteryGauge d={d} />
    </span>
  );
}
