import { useCallback, useRef } from "react";
import { usePolledData } from "../api/useApiData";
import { POLL_LIVE_MS } from "../api/pollIntervals";
import { api } from "../api/client";
import type { ChangeRow, Overview } from "../api/types";
import { ChangeLine } from "../design/ChangeLine";
import { AppButton, EmptyState, Panel, StatTile } from "../design/components";
import { navigate } from "../router";
import { AttentionPanel } from "./overview/AttentionPanel";
import { PulsePanel } from "./overview/PulsePanel";
import { WatchPanel } from "./overview/WatchPanel";

const POLL_MS = POLL_LIVE_MS;

interface OverviewTick {
  overview: Overview;
  feed: ChangeRow[];
}

export function OverviewScreen() {
  const sinceRef = useRef(Date.now() - 30 * 60 * 1000);
  const feedRef = useRef<ChangeRow[]>([]);

  // Комбинирует /api/overview и живую ленту в один тик (общий интервал, одна ошибка на двоих
  // — сеть моргнула, следующий тик поправит сам, отдельный индикатор ошибки для polling не делаем).
  // Курсор и накопленная лента живут в ref: usePolledData просто подставляет то, что вернул fetch.
  const fetchTick = useCallback(async (): Promise<OverviewTick> => {
    const [overview, recent] = await Promise.all([
      api.get<Overview>("/api/overview"),
      api.get<{ records: ChangeRow[]; now: number }>(`/api/changes/recent?since=${sinceRef.current}&limit=500`),
    ]);
    // Курсор двигаем всегда; сервер отдаёт записи с received_at >= курсора, поэтому на границе возможны повторы — режем по id.
    sinceRef.current = recent.now;
    if (recent.records.length > 0) {
      const seen = new Set(feedRef.current.map((r) => r.id));
      const fresh = recent.records.filter((r) => !seen.has(r.id)).reverse();
      if (fresh.length > 0) feedRef.current = [...fresh, ...feedRef.current].slice(0, 200);
    }
    return { overview, feed: feedRef.current };
  }, []);

  const { data } = usePolledData(fetchTick, { pollMs: POLL_MS });
  const overview = data?.overview ?? null;
  const feed = data?.feed ?? [];

  return (
    <div className="screen-grid">
      <div className="stat-row">
        <StatTile label="Игроков на связи" value={overview ? `${overview.players.online} / ${overview.players.total}` : "—"} />
        <StatTile
          label="Взломы за час: успех / частично / провал"
          value={overview ? `${overview.breachesLastHour.success}/${overview.breachesLastHour.partial}/${overview.breachesLastHour.fail}` : "—"}
        />
        <StatTile label="Тиражных слотов в обороте" value={overview ? `${overview.slots.claimed} / ${overview.slots.printed}` : "—"} tone="accent" />
        <StatTile label="Сигналы СБ: отправлено / подавлено" value={overview ? `${overview.alerts.sent} / ${overview.alerts.suppressed}` : "—"} />
      </div>

      <div className="two-col">
        <AttentionPanel />
        <WatchPanel />
      </div>

      <PulsePanel />

      <Panel title="Живая лента изменений" action={<AppButton onClick={() => navigate("events")}>все события с фильтрами →</AppButton>}>
        {feed.length === 0 ? (
          <EmptyState>пока тихо</EmptyState>
        ) : (
          <div className="feed-list">
            {feed.map((r) => (
              <ChangeLine key={r.id} row={r} showSubject />
            ))}
          </div>
        )}
      </Panel>
    </div>
  );
}
