import type { PlayerListItem } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useWatch } from "../../api/useWatch";
import { Badge, EmptyState, Panel } from "../../design/components";
import { formatAgo, formatNumber } from "../../format";
import { navigate } from "../../router";

/** Игроки под наблюдением (закладки мастеров): где сейчас, сколько денег, пометка. */
export function WatchPanel() {
  const { items } = useWatch();
  const { data: players } = useApiData<PlayerListItem[]>("/api/players");
  const byKey = new Map((players ?? []).map((p) => [p.publicKeyB64, p]));

  return (
    <Panel title={`Под наблюдением (${items.length})`}>
      {items.length === 0 ? (
        <EmptyState>отметьте игрока звёздочкой в списке или в его карточке</EmptyState>
      ) : (
        items.map((w) => {
          const p = byKey.get(w.publicKeyB64);
          return (
            <div key={w.publicKeyB64} className="attn-item clickable" onClick={() => navigate("players", w.publicKeyB64)}>
              <span className={`online-dot ${p?.online ? "on" : ""}`} />
              <span className="attn-title" style={{ color: "var(--text-main)" }}>
                {p?.callsign || "неизвестный"}
              </span>
              <span className="attn-detail">
                {p ? `${formatNumber(p.balance)} €$ · ${p.faction || "без фракции"}` : ""}
                {w.note && <Badge tone="accent">{w.note}</Badge>}
              </span>
              <span className="attn-time mono">{p ? formatAgo(p.lastSeenAt) : ""}</span>
            </div>
          );
        })
      )}
    </Panel>
  );
}
