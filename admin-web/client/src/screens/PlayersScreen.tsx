import { useMemo, useState } from "react";
import type { PlayerListItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { useWatch } from "../api/useWatch";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppInput, AppSelect, Badge, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatAgo, fromDatetimeLocal, shortKey, tierLabel, toDatetimeLocal } from "../format";
import { navigate } from "../router";
import { BulkOverridePanel } from "./players/BulkOverridePanel";

export function PlayersScreen() {
  const [asOf, setAsOf] = useState("");
  const [nowLocal] = useState(() => toDatetimeLocal(Date.now()));
  const asOfMs = asOf ? fromDatetimeLocal(asOf) : null;
  // «На момент T» — историческая картина, не меняется: без polling.
  const { data: players, error, reload } = useApiData<PlayerListItem[]>(asOfMs ? `/api/players?until=${asOfMs}` : "/api/players", {
    pollMs: asOfMs ? false : undefined,
  });
  const watch = useWatch();
  const [search, setSearch] = useState("");
  const [faction, setFaction] = useState("");
  const [onlyWatched, setOnlyWatched] = useState(false);
  // Сброшенные и перевыданные сессии по умолчанию скрыты: это не игроки на площадке, а «хвосты» прежних телефонов.
  const [showRetired, setShowRetired] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkOpen, setBulkOpen] = useState(false);

  const factions = useMemo(() => [...new Set((players ?? []).map((p) => p.faction).filter(Boolean))], [players]);

  const filtered = useMemo(() => {
    if (!players) return [];
    return players.filter((p) => {
      if (!showRetired && (p.sessionResetAt !== null || p.replacedBy !== null)) return false;
      if (faction && p.faction !== faction) return false;
      if (onlyWatched && !watch.byKey.has(p.publicKeyB64)) return false;
      if (search && !p.callsign.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [players, search, faction, onlyWatched, showRetired, watch.byKey]);

  const retiredCount = (players ?? []).filter((p) => p.sessionResetAt !== null || p.replacedBy !== null).length;

  const toggleSelected = (key: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  const columns: Column<PlayerListItem>[] = [
    {
      key: "select",
      label: "",
      render: (p) => (
        <input type="checkbox" checked={selected.has(p.publicKeyB64)} onClick={(e) => e.stopPropagation()} onChange={() => toggleSelected(p.publicKeyB64)} aria-label="выбрать" />
      ),
    },
    {
      key: "watch",
      label: "",
      render: (p) => {
        const on = watch.byKey.has(p.publicKeyB64);
        return (
          <button
            type="button"
            className={`watch-star ${on ? "on" : ""}`}
            title={on ? "снять наблюдение" : "следить"}
            onClick={(e) => {
              e.stopPropagation();
              if (on) void watch.remove(p.publicKeyB64);
              else void watch.set(p.publicKeyB64);
            }}
          >
            {on ? "★" : "☆"}
          </button>
        );
      },
      sortValue: (p) => (watch.byKey.has(p.publicKeyB64) ? 1 : 0),
    },
    { key: "online", label: "", render: (p) => <span className={`online-dot ${p.online ? "on" : ""}`} />, sortValue: (p) => (p.online ? 1 : 0) },
    {
      key: "callsign",
      label: "Позывной",
      render: (p) => (
        <>
          {p.callsign || shortKey(p.publicKeyB64)}{" "}
          {p.replacedBy ? <Badge>заменён</Badge> : p.sessionResetAt !== null ? <Badge tone="accent">сброс</Badge> : null}
        </>
      ),
      sortValue: (p) => p.callsign,
    },
    {
      key: "version",
      label: "Версия",
      render: (p) => (
        <span className="mono" title={p.wireVersions ? Object.entries(p.wireVersions).map(([k, v]) => `${k} v${v}`).join(", ") : undefined}>
          {p.appVersion ?? "—"}
        </span>
      ),
      sortValue: (p) => p.appVersion ?? "",
    },
    { key: "faction", label: "Фракция", render: (p) => p.faction, sortValue: (p) => p.faction },
    { key: "ram", label: "RAM", render: (p) => p.ramCapacity, sortValue: (p) => p.ramCapacity },
    { key: "balance", label: "Эдди", render: (p) => p.balance, sortValue: (p) => p.balance },
    {
      key: "shards",
      label: "Шарды",
      render: (p) => Object.entries(p.shardsByTier).map(([t, n]) => `${tierLabel(t)} × ${n}`).join(", ") || "—",
      sortValue: (p) => Object.values(p.shardsByTier).reduce((a, b) => a + b, 0),
    },
    { key: "daemons", label: "Демоны", render: (p) => p.daemonCount, sortValue: (p) => p.daemonCount },
    {
      key: "breaches",
      label: "Взломы: успех / частично / провал",
      render: (p) => `${p.breaches.success}/${p.breaches.partial}/${p.breaches.fail}`,
      sortValue: (p) => p.breaches.success,
    },
    { key: "slots", label: "Слотов забрано", render: (p) => p.slotsClaimed, sortValue: (p) => p.slotsClaimed },
    {
      key: "queue",
      label: "Очередь",
      render: (p) =>
        p.pendingCount ? (
          <span className="mono" title="неотправленные записи на телефоне (по последнему heartbeat)">
            {p.pendingCount} · {Math.round((p.oldestPendingAgeMs ?? 0) / 60_000)} мин
          </span>
        ) : (
          "—"
        ),
      sortValue: (p) => p.pendingCount ?? 0,
    },
    { key: "lastSeen", label: "Активность", render: (p) => formatAgo(p.lastSeenAt), sortValue: (p) => p.lastSeenAt },
  ];

  return (
    <div className="screen-grid">
      {asOfMs && (
        <div className="asof-banner">
          Состояние на {new Date(asOfMs).toLocaleString("ru-RU")} — это история, не текущая картина. Массовые правки отключены.{" "}
          <button type="button" className="change-toggle" onClick={() => setAsOf("")}>
            вернуться к текущему
          </button>
        </div>
      )}

      {bulkOpen && !asOfMs && players && (
        <BulkOverridePanel
          players={players}
          selectedKeys={[...selected]}
          factionFilter={faction}
          onDone={() => {
            setSelected(new Set());
            reload();
          }}
          onClose={() => setBulkOpen(false)}
        />
      )}

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
            {retiredCount > 0 && (
              <AppButton variant={showRetired ? "primary" : "default"} onClick={() => setShowRetired((v) => !v)}>
                выбывшие {retiredCount}
              </AppButton>
            )}
            <AppButton variant={onlyWatched ? "primary" : "default"} onClick={() => setOnlyWatched((v) => !v)}>
              ★ {watch.items.length}
            </AppButton>
            <AppInput
              type="datetime-local"
              title="Показать состояние на момент времени"
              value={asOf}
              max={nowLocal}
              onChange={(e) => setAsOf(e.target.value)}
            />
          </div>
        }
      >
        {!asOfMs && (
          <div className="filter-row" style={{ marginBottom: 10 }}>
            <AppButton onClick={() => setSelected(new Set(filtered.map((p) => p.publicKeyB64)))} disabled={filtered.length === 0}>
              выбрать видимых ({filtered.length})
            </AppButton>
            <AppButton onClick={() => setSelected(new Set())} disabled={selected.size === 0}>
              снять выбор
            </AppButton>
            <AppButton variant="primary" onClick={() => setBulkOpen(true)}>
              Массовая правка{selected.size > 0 ? ` (${selected.size})` : ""}
            </AppButton>
          </div>
        )}
        <AsyncPanel data={players} error={error}>
          {() => <DataTable columns={columns} rows={filtered} rowKey={(p) => p.publicKeyB64} onRowClick={(p) => navigate("players", p.publicKeyB64)} />}
        </AsyncPanel>
      </Panel>
    </div>
  );
}
