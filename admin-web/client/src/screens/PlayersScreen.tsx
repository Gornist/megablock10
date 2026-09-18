import { useMemo, useState } from "react";
import type { PlayerListItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AppInput, AppSelect, EmptyState, ErrorNote, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatAgo, shortKey } from "../format";
import { navigate } from "../router";

const POLL_MS = 8000;

export function PlayersScreen() {
  const { data: players, error } = useApiData<PlayerListItem[]>("/api/players", { pollMs: POLL_MS });
  const [search, setSearch] = useState("");
  const [faction, setFaction] = useState("");

  const factions = useMemo(() => [...new Set((players ?? []).map((p) => p.faction).filter(Boolean))], [players]);

  const filtered = useMemo(() => {
    if (!players) return [];
    return players.filter((p) => {
      if (faction && p.faction !== faction) return false;
      if (search && !p.callsign.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [players, search, faction]);

  const columns: Column<PlayerListItem>[] = [
    { key: "online", label: "", render: (p) => <span className={`online-dot ${p.online ? "on" : ""}`} />, sortValue: (p) => (p.online ? 1 : 0) },
    { key: "callsign", label: "Позывной", render: (p) => p.callsign || shortKey(p.publicKeyB64), sortValue: (p) => p.callsign },
    { key: "faction", label: "Фракция", render: (p) => p.faction, sortValue: (p) => p.faction },
    { key: "ram", label: "RAM", render: (p) => p.ramCapacity, sortValue: (p) => p.ramCapacity },
    { key: "balance", label: "Эдди", render: (p) => p.balance, sortValue: (p) => p.balance },
    {
      key: "shards",
      label: "Шарды",
      render: (p) => Object.entries(p.shardsByTier).map(([t, n]) => `${t}:${n}`).join(" ") || "—",
      sortValue: (p) => Object.values(p.shardsByTier).reduce((a, b) => a + b, 0),
    },
    { key: "daemons", label: "Демоны", render: (p) => p.daemonCount, sortValue: (p) => p.daemonCount },
    {
      key: "breaches",
      label: "Взломы у/ч/п",
      render: (p) => `${p.breaches.success}/${p.breaches.partial}/${p.breaches.fail}`,
      sortValue: (p) => p.breaches.success,
    },
    { key: "slots", label: "Слотов забрано", render: (p) => p.slotsClaimed, sortValue: (p) => p.slotsClaimed },
    { key: "lastSeen", label: "Активность", render: (p) => formatAgo(p.lastSeenAt), sortValue: (p) => p.lastSeenAt },
  ];

  return (
    <Panel
      title={`Игроки${players ? ` (${filtered.length}/${players.length})` : ""}`}
      action={
        <div className="filter-row">
          <AppInput placeholder="поиск по позывному" value={search} onChange={(e) => setSearch(e.target.value)} />
          <AppSelect value={faction} onChange={(e) => setFaction(e.target.value)}>
            <option value="">все фракции</option>
            {factions.map((f) => (
              <option key={f} value={f}>
                {f}
              </option>
            ))}
          </AppSelect>
        </div>
      }
    >
      {error && <ErrorNote>{error}</ErrorNote>}
      {players === null ? (
        <EmptyState>{error ? "" : "загрузка…"}</EmptyState>
      ) : (
        <DataTable columns={columns} rows={filtered} rowKey={(p) => p.publicKeyB64} onRowClick={(p) => navigate("players", p.publicKeyB64)} />
      )}
    </Panel>
  );
}
