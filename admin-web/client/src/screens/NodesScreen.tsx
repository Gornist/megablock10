import { useState } from "react";
import type { NodeDetail, NodeSummary, PlayerListItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { OutcomeBars } from "../design/charts";
import { AppButton, Badge, Panel, StatTile } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatAgo, tierLabel } from "../format";
import { navigate } from "../router";

const HOUR_OPTIONS = [6, 24, 72] as const;

export function NodesScreen({ nodeId }: { nodeId?: string }) {
  const { data: nodes, error } = useApiData<NodeSummary[]>("/api/nodes");

  const byTier = new Map<string, number>();
  for (const n of nodes ?? []) byTier.set(n.tier, (byTier.get(n.tier) ?? 0) + 1);

  const columns: Column<NodeSummary>[] = [
    { key: "name", label: "Имя", render: (n) => n.name, sortValue: (n) => n.name },
    { key: "tier", label: "Сложность", render: (n) => tierLabel(n.tier), sortValue: (n) => n.tier },
    { key: "faction", label: "Владелец", render: (n) => n.ownerFaction ?? "—", sortValue: (n) => n.ownerFaction ?? "" },
    { key: "slots", label: "Слотов забрано/всего", render: (n) => `${n.slotsClaimed}/${n.slotsTotal}`, sortValue: (n) => n.slotsClaimed },
    { key: "hour", label: "Взломов за час", render: (n) => n.breachesLastHour ?? 0, sortValue: (n) => n.breachesLastHour ?? 0 },
    { key: "breaches", label: "Взломы: успех / частично / провал", render: (n) => `${n.breaches.success}/${n.breaches.partial}/${n.breaches.fail}`, sortValue: (n) => n.breaches.success },
    { key: "players", label: "Уникальных игроков", render: (n) => n.uniquePlayers, sortValue: (n) => n.uniquePlayers },
    { key: "alerts", label: "Сигналы СБ: отправлено / подавлено", render: (n) => `${n.alertsSent}/${n.alertsSuppressed}`, sortValue: (n) => n.alertsSent },
    { key: "last", label: "Последний взлом", render: (n) => formatAgo(n.lastBreachAt), sortValue: (n) => n.lastBreachAt ?? 0 },
  ];

  return (
    <div className="screen-grid">
      <div className="stat-row">
        {[...byTier.entries()].map(([tier, n]) => (
          <StatTile key={tier} label={tier} value={n} />
        ))}
      </div>
      {nodeId && <NodeDetailPanel nodeId={nodeId} />}
      <Panel title={`Узлы${nodes ? ` (${nodes.length})` : ""}`}>
        <AsyncPanel data={nodes} error={error} isEmpty={(d) => d.length === 0} emptyLabel="контейнеров пока нет — залейте их из Мастерской">
          {(d) => <DataTable columns={columns} rows={d} rowKey={(n) => n.id} onRowClick={(n) => navigate("nodes", n.id)} />}
        </AsyncPanel>
      </Panel>
    </div>
  );
}

/** Динамика взломов одного узла по часам и кто его ломал — «горячие» узлы и момент, когда их начали ломать. */
function NodeDetailPanel({ nodeId }: { nodeId: string }) {
  const [hours, setHours] = useState<(typeof HOUR_OPTIONS)[number]>(24);
  const { data: node, error } = useApiData<NodeDetail>(`/api/nodes/${encodeURIComponent(nodeId)}?hours=${hours}`);
  const { data: players } = useApiData<PlayerListItem[]>("/api/players");
  const nameOf = (key: string) => (players ?? []).find((p) => p.publicKeyB64 === key)?.callsign || key.slice(0, 8);

  return (
    <Panel
      title={node ? `Узел «${node.name}» — ${tierLabel(node.tier)}, владелец ${node.ownerFaction ?? "—"}` : "Узел"}
      action={
        <div className="filter-row">
          {HOUR_OPTIONS.map((h) => (
            <AppButton key={h} variant={h === hours ? "primary" : "default"} onClick={() => setHours(h)}>
              {h} ч
            </AppButton>
          ))}
          <AppButton onClick={() => navigate("events", "node", nodeId)}>события узла →</AppButton>
          <AppButton onClick={() => navigate("nodes")}>закрыть</AppButton>
        </div>
      }
    >
      <AsyncPanel data={node} error={error}>
        {(n) => (
          <>
            <OutcomeBars buckets={n.timeline} />
            <p className="hint-text">Кто ломал (последний взлом · попыток):</p>
            <div>
              {n.breachers.length === 0 ? (
                <span className="hint-text">никто</span>
              ) : (
                n.breachers.map((b) => (
                  <Badge key={b.actor} tone="neutral">
                    <span className="tier-pick" onClick={() => navigate("players", b.actor)}>
                      {nameOf(b.actor)} · {formatAgo(b.lastAt)} · {b.n}
                    </span>
                  </Badge>
                ))
              )}
            </div>
          </>
        )}
      </AsyncPanel>
    </Panel>
  );
}
