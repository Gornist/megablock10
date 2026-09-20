import type { NodeSummary } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { Panel, StatTile } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatAgo, tierLabel } from "../format";

export function NodesScreen() {
  const { data: nodes, error } = useApiData<NodeSummary[]>("/api/nodes");

  const byTier = new Map<string, number>();
  for (const n of nodes ?? []) byTier.set(n.tier, (byTier.get(n.tier) ?? 0) + 1);

  const columns: Column<NodeSummary>[] = [
    { key: "name", label: "Имя", render: (n) => n.name, sortValue: (n) => n.name },
    { key: "tier", label: "Сложность", render: (n) => tierLabel(n.tier), sortValue: (n) => n.tier },
    { key: "faction", label: "Владелец", render: (n) => n.ownerFaction ?? "—", sortValue: (n) => n.ownerFaction ?? "" },
    { key: "slots", label: "Слотов забрано/всего", render: (n) => `${n.slotsClaimed}/${n.slotsTotal}`, sortValue: (n) => n.slotsClaimed },
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
      <Panel title={`Узлы${nodes ? ` (${nodes.length})` : ""}`}>
        <AsyncPanel data={nodes} error={error} isEmpty={(d) => d.length === 0} emptyLabel="контейнеров пока нет — залейте их из Мастерской">
          {(d) => <DataTable columns={columns} rows={d} rowKey={(n) => n.id} />}
        </AsyncPanel>
      </Panel>
    </div>
  );
}
