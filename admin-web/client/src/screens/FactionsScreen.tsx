import type { FactionRow } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { ShareBar } from "../design/charts";
import { Panel, StatTile } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatNumber } from "../format";
import { navigate } from "../router";
import { NO_FACTION } from "./events/eventFilters";

/**
 * Срез по фракциям: деньги, боевая активность, чьи узлы ломают (свои/чужие) и
 * куда уходят сигналы СБ — для LARP с фракционным противостоянием это главный
 * ответ на «кто сейчас сильнее и кто на кого давит».
 */
export function FactionsScreen() {
  const { data: rows, error } = useApiData<FactionRow[]>("/api/factions");
  const maxBalance = Math.max(1, ...(rows ?? []).map((r) => r.totalBalance));
  const name = (f: string) => f || "без фракции";

  const columns: Column<FactionRow>[] = [
    { key: "faction", label: "Фракция", render: (r) => <strong>{name(r.faction)}</strong>, sortValue: (r) => r.faction },
    { key: "players", label: "Игроков (на связи)", render: (r) => `${r.players} (${r.online})`, sortValue: (r) => r.players },
    {
      key: "balance",
      label: "Эдди всего",
      render: (r) => (
        <>
          <span className="mono">{formatNumber(r.totalBalance)}</span> <ShareBar value={r.totalBalance} max={maxBalance} />
        </>
      ),
      sortValue: (r) => r.totalBalance,
    },
    { key: "avg", label: "Средний баланс", render: (r) => formatNumber(r.avgBalance), sortValue: (r) => r.avgBalance },
    { key: "daemons", label: "Демоны", render: (r) => r.daemons, sortValue: (r) => r.daemons },
    { key: "shards", label: "Шарды", render: (r) => r.shards, sortValue: (r) => r.shards },
    { key: "breaches", label: "Взломы: успех / частично / провал", render: (r) => `${r.breaches.success}/${r.breaches.partial}/${r.breaches.fail}`, sortValue: (r) => r.breaches.success },
    { key: "own", label: "Взломы своих / чужих узлов", render: (r) => `${r.breachesOwn} / ${r.breachesForeign}`, sortValue: (r) => r.breachesForeign },
    { key: "alerts", label: "СБ: подали → / получили ←", render: (r) => `${r.alertsSent} → / ${r.alertsReceived} ←`, sortValue: (r) => r.alertsReceived },
    { key: "slots", label: "Слотов забрано", render: (r) => r.slotsClaimed, sortValue: (r) => r.slotsClaimed },
  ];

  return (
    <div className="screen-grid">
      <div className="stat-row">
        <StatTile label="Фракций" value={rows?.length ?? "—"} />
        <StatTile label="Игроков всего" value={rows ? rows.reduce((a, r) => a + r.players, 0) : "—"} />
        <StatTile label="Эдди у всех" value={rows ? formatNumber(rows.reduce((a, r) => a + r.totalBalance, 0)) : "—"} tone="money" />
      </div>
      <Panel title="Фракции">
        <AsyncPanel data={rows} error={error} isEmpty={(d) => d.length === 0} emptyLabel="игроков пока нет">
          {(d) => <DataTable columns={columns} rows={d} rowKey={(r) => r.faction || "—"} onRowClick={(r) => navigate("events", "faction", r.faction || NO_FACTION)} />}
        </AsyncPanel>
        <p className="hint-text">
          Клик по строке — все события фракции. «Свои / чужие» — по владельцу узла (задаётся в Мастерской); узлы без владельца не учитываются. «СБ получили» — сигналы, ушедшие владельцам узлов этой фракции.
        </p>
      </Panel>
    </div>
  );
}
