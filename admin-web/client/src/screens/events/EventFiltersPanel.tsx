import { useMemo } from "react";
import type { NodeSummary, PlayerListItem } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { reasonLabel, useMeta } from "../../api/useMeta";
import { AppButton, AppSelect, Badge, Panel } from "../../design/components";
import { NO_FACTION, PERIODS, type EventFilters } from "./eventFilters";

/** Панель фильтров событий: игрок, фракция, узел, тип, причина, период; под ней — выбранное бейджами. */
export function EventFiltersPanel({ filters, set, reset }: { filters: EventFilters; set: (key: keyof EventFilters) => (value: string) => void; reset: () => void }) {
  const meta = useMeta();
  const { data: players } = useApiData<PlayerListItem[]>("/api/players", { pollMs: false });
  const { data: nodes } = useApiData<NodeSummary[]>("/api/nodes", { pollMs: false });
  const sortedPlayers = useMemo(() => [...(players ?? [])].sort((a, b) => a.callsign.localeCompare(b.callsign)), [players]);
  const factions = useMemo(() => [...new Set((players ?? []).map((p) => p.faction))].sort(), [players]);

  const { player, faction, node, kind, reason, period } = filters;
  const active = [
    player && `игрок: ${sortedPlayers.find((p) => p.publicKeyB64 === player)?.callsign ?? "игрок"}`,
    faction && `фракция: ${faction === NO_FACTION ? "без фракции" : faction}`,
    node && `узел: ${(nodes ?? []).find((n) => n.id === node)?.name ?? node}`,
    kind && `тип: ${meta?.kinds.find((k) => k.code === kind)?.label ?? kind}`,
    reason && `причина: ${reasonLabel(meta, reason)}`,
    period && PERIODS.find((p) => p.value === period)?.label,
  ].filter(Boolean) as string[];

  const onChange = (key: keyof EventFilters) => (e: React.ChangeEvent<HTMLSelectElement>) => set(key)(e.target.value);

  return (
    <Panel
      title="Фильтры"
      action={
        <AppButton onClick={reset} disabled={active.length === 0}>
          сбросить
        </AppButton>
      }
    >
      <div className="filter-row filter-wrap">
        <AppSelect value={player} onChange={onChange("player")} aria-label="игрок">
          <option value="">все игроки</option>
          {sortedPlayers.map((p) => (
            <option key={p.publicKeyB64} value={p.publicKeyB64}>
              {p.callsign || p.publicKeyB64.slice(0, 8)}
            </option>
          ))}
        </AppSelect>
        <AppSelect value={faction} onChange={onChange("faction")} aria-label="фракция">
          <option value="">все фракции</option>
          {factions.map((f) => (
            <option key={f || NO_FACTION} value={f || NO_FACTION}>
              {f || "без фракции"}
            </option>
          ))}
        </AppSelect>
        <AppSelect value={node} onChange={onChange("node")} aria-label="узел">
          <option value="">все узлы</option>
          {(nodes ?? []).map((n) => (
            <option key={n.id} value={n.id}>
              {n.name}
            </option>
          ))}
        </AppSelect>
        <AppSelect value={kind} onChange={onChange("kind")} aria-label="тип события">
          <option value="">любой тип</option>
          {(meta?.kinds ?? []).map((k) => (
            <option key={k.code} value={k.code}>
              {k.label}
            </option>
          ))}
        </AppSelect>
        <AppSelect value={reason} onChange={onChange("reason")} aria-label="причина">
          <option value="">любая причина</option>
          {(meta?.reasons ?? []).map((r) => (
            <option key={r.code} value={r.code}>
              {r.label}
            </option>
          ))}
        </AppSelect>
        <AppSelect value={period} onChange={onChange("period")} aria-label="период">
          {PERIODS.map((p) => (
            <option key={p.value} value={p.value}>
              {p.label}
            </option>
          ))}
        </AppSelect>
      </div>
      {active.length > 0 && (
        <div className="filter-summary">
          {active.map((a) => (
            <Badge key={a} tone="accent">
              {a}
            </Badge>
          ))}
        </div>
      )}
    </Panel>
  );
}
