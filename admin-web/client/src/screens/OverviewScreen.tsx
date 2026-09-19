import { useEffect, useRef, useState } from "react";
import { api } from "../api/client";
import type { ChangeRow, Overview } from "../api/types";
import { EmptyState, HexRow, Panel, StatTile } from "../design/components";
import { formatTime } from "../format";

const POLL_MS = 3000;

export function OverviewScreen() {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [feed, setFeed] = useState<ChangeRow[]>([]);
  const sinceRef = useRef(Date.now() - 30 * 60 * 1000);

  useEffect(() => {
    let cancelled = false;
    async function tick() {
      try {
        const [ov, recent] = await Promise.all([
          api.get<Overview>("/api/overview"),
          api.get<{ records: ChangeRow[]; now: number }>(`/api/changes/recent?since=${sinceRef.current}&limit=500`),
        ]);
        if (cancelled) return;
        setOverview(ov);
        // Курсор двигаем всегда; сервер отдаёт записи с received_at >= курсора, поэтому на границе возможны повторы — режем по id.
        sinceRef.current = recent.now;
        if (recent.records.length > 0) {
          setFeed((prev) => {
            const seen = new Set(prev.map((r) => r.id));
            const fresh = recent.records.filter((r) => !seen.has(r.id)).reverse();
            return fresh.length === 0 ? prev : [...fresh, ...prev].slice(0, 200);
          });
        }
      } catch {
        // сеть моргнула — следующий тик поправит, отдельного индикатора ошибки для polling не делаем
      }
    }
    tick();
    const id = setInterval(tick, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  return (
    <div className="screen-grid">
      <div className="stat-row">
        <StatTile label="Игроков на связи" value={overview ? `${overview.players.online} / ${overview.players.total}` : "—"} />
        <StatTile
          label="Взломы за час (у/ч/п)"
          value={overview ? `${overview.breachesLastHour.success}/${overview.breachesLastHour.partial}/${overview.breachesLastHour.fail}` : "—"}
        />
        <StatTile label="Тиражных слотов в обороте" value={overview ? `${overview.slots.claimed} / ${overview.slots.printed}` : "—"} tone="accent" />
        <StatTile label="Сигналы СБ (ушло / подавлено)" value={overview ? `${overview.alerts.sent} / ${overview.alerts.suppressed}` : "—"} />
      </div>

      <Panel title="Живая лента изменений">
        {feed.length === 0 ? (
          <EmptyState>пока тихо</EmptyState>
        ) : (
          <div className="feed-list">
            {feed.map((r) => (
              <HexRow key={r.id}>
                <span className="feed-time">{formatTime(r.received_at)}</span>{" "}
                <span className="feed-field">{r.field}</span> <span className="feed-reason status-caps">{r.reason}</span>{" "}
                {r.source_ref && <span className="feed-source">{r.source_ref}</span>}
              </HexRow>
            ))}
          </div>
        )}
      </Panel>
    </div>
  );
}
