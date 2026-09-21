import type { CharacterSnapshot } from "../../api/types";
import { Panel } from "../../design/components";

/** Счётчики игры игрока: взломы по исходам, заблокированные попытки, слоты, сигналы СБ. */
export function CountersPanel({ snapshot }: { snapshot: CharacterSnapshot }) {
  const breachTotals = Object.values(snapshot.counters.breaches).reduce(
    (acc, b) => ({ success: acc.success + b.success, partial: acc.partial + b.partial, fail: acc.fail + b.fail }),
    { success: 0, partial: 0, fail: 0 },
  );
  const blockedTotal = Object.values(snapshot.counters.breachesBlocked).reduce((a, b) => a + b, 0);
  return (
    <Panel title="Счётчики">
      <div className="counters-grid">
        <span>
          Взломы (успех / частично / провал): <span className="mono">{breachTotals.success}/{breachTotals.partial}/{breachTotals.fail}</span>
        </span>
        <span>
          Заблокировано попыток: <span className="mono">{blockedTotal}</span>
          {blockedTotal > 0 && (
            <span className="hint-text">
              {" "}
              ({Object.entries(snapshot.counters.breachesBlocked).map(([reason, n]) => `${reason}: ${n}`).join(", ")})
            </span>
          )}
        </span>
        <span>
          Слотов забрано: <span className="mono">{snapshot.counters.slotsClaimed}</span>
        </span>
        <span>
          Сигналы СБ (отправлено / подавлено): <span className="mono">{snapshot.counters.alertsSent}/{snapshot.counters.alertsSuppressed}</span>
        </span>
      </div>
    </Panel>
  );
}
