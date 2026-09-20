import { useMemo, useState } from "react";
import type { EventsResponse, NodeSummary, PlayerListItem } from "../api/types";
import { useApiData } from "../api/useApiData";
import { reasonLabel, useMeta } from "../api/useMeta";
import { ChangeLine } from "../design/ChangeLine";
import { AppButton, AppSelect, Badge, EmptyState, ErrorNote, Panel } from "../design/components";

const PAGE_SIZE = 50;
const POLL_MS = 5000;
/** Как в API: значение фильтра «игроки без фракции» (пустую строку в адресе не передать). */
export const NO_FACTION = "__none__";


const PERIODS: { value: string; label: string }[] = [
  { value: "", label: "за всё время" },
  { value: "15", label: "за 15 минут" },
  { value: "60", label: "за час" },
  { value: "360", label: "за 6 часов" },
  { value: "1440", label: "за сутки" },
];

/** Начальный фильтр из адреса: #/events/player/<ключ>, #/events/faction/<имя>, #/events/node/<id> (ссылки с карточек игрока, фракции, узла). */
export interface EventsPreset {
  type?: string;
  value?: string;
}

/**
 * События с фильтрами: по игроку, фракции, типу, причине, узлу и периоду.
 * Фильтрует сервер (/api/events), а не браузер, поэтому работает и по истории,
 * которая давно вышла за живую ленту Обзора. Первая страница обновляется сама.
 */
export function EventsScreen({ preset }: { preset: EventsPreset }) {
  const [player, setPlayer] = useState(preset.type === "player" ? (preset.value ?? "") : "");
  const [faction, setFaction] = useState(preset.type === "faction" ? (preset.value ?? "") : "");
  const [node, setNode] = useState(preset.type === "node" ? (preset.value ?? "") : "");
  const [kind, setKind] = useState("");
  const [reason, setReason] = useState("");
  const [period, setPeriod] = useState("");
  const [page, setPage] = useState(0);

  const meta = useMeta();
  const { data: players } = useApiData<PlayerListItem[]>("/api/players", { pollMs: false });
  const { data: nodes } = useApiData<NodeSummary[]>("/api/nodes", { pollMs: false });
  const sortedPlayers = useMemo(() => [...(players ?? [])].sort((a, b) => a.callsign.localeCompare(b.callsign)), [players]);
  const factions = useMemo(() => [...new Set((players ?? []).map((p) => p.faction))].sort(), [players]);

  // Первая страница обновляется сама; листая историю, страница не должна «плыть» под руками.
  const { data: result, error } = useApiData<EventsResponse>(
    () => {
      const q = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
      if (player) q.set("player", player);
      if (faction) q.set("faction", faction);
      if (node) q.set("node", node);
      if (kind) q.set("kind", kind);
      if (reason) q.set("reason", reason);
      if (period) q.set("since", String(Date.now() - Number(period) * 60_000));
      return `/api/events?${q}`;
    },
    { key: JSON.stringify([player, faction, node, kind, reason, period, page]), pollMs: page === 0 ? POLL_MS : false },
  );

  const nameOfPlayer = sortedPlayers.find((p) => p.publicKeyB64 === player)?.callsign ?? "игрок";
  const nameOfNode = (nodes ?? []).find((n) => n.id === node)?.name ?? node;
  const active = [
    player && `игрок: ${nameOfPlayer}`,
    faction && `фракция: ${faction === NO_FACTION ? "без фракции" : faction}`,
    node && `узел: ${nameOfNode}`,
    kind && `тип: ${meta?.kinds.find((k) => k.code === kind)?.label ?? kind}`,
    reason && `причина: ${reasonLabel(meta, reason)}`,
    period && PERIODS.find((p) => p.value === period)?.label,
  ].filter(Boolean) as string[];

  const change = (set: (v: string) => void) => (e: React.ChangeEvent<HTMLSelectElement>) => {
    set(e.target.value);
    setPage(0);
  };
  const reset = () => {
    setPlayer("");
    setFaction("");
    setNode("");
    setKind("");
    setReason("");
    setPeriod("");
    setPage(0);
  };

  return (
    <div className="screen-grid">
      <Panel
        title="Фильтры"
        action={
          <AppButton onClick={reset} disabled={active.length === 0}>
            сбросить
          </AppButton>
        }
      >
        <div className="filter-row filter-wrap">
          <AppSelect value={player} onChange={change(setPlayer)} aria-label="игрок">
            <option value="">все игроки</option>
            {sortedPlayers.map((p) => (
              <option key={p.publicKeyB64} value={p.publicKeyB64}>
                {p.callsign || p.publicKeyB64.slice(0, 8)}
              </option>
            ))}
          </AppSelect>
          <AppSelect value={faction} onChange={change(setFaction)} aria-label="фракция">
            <option value="">все фракции</option>
            {factions.map((f) => (
              <option key={f || NO_FACTION} value={f || NO_FACTION}>
                {f || "без фракции"}
              </option>
            ))}
          </AppSelect>
          <AppSelect value={node} onChange={change(setNode)} aria-label="узел">
            <option value="">все узлы</option>
            {(nodes ?? []).map((n) => (
              <option key={n.id} value={n.id}>
                {n.name}
              </option>
            ))}
          </AppSelect>
          <AppSelect value={kind} onChange={change(setKind)} aria-label="тип события">
            <option value="">любой тип</option>
            {(meta?.kinds ?? []).map((k) => (
              <option key={k.code} value={k.code}>
                {k.label}
              </option>
            ))}
          </AppSelect>
          <AppSelect value={reason} onChange={change(setReason)} aria-label="причина">
            <option value="">любая причина</option>
            {(meta?.reasons ?? []).map((r) => (
              <option key={r.code} value={r.code}>
                {r.label}
              </option>
            ))}
          </AppSelect>
          <AppSelect value={period} onChange={change(setPeriod)} aria-label="период">
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

      <Panel title={`События${result ? ` (${result.total})` : ""}`}>
        {error && <ErrorNote>{error}</ErrorNote>}
        {result === null ? (
          <EmptyState>{error ? "" : "загрузка…"}</EmptyState>
        ) : result.records.length === 0 ? (
          <EmptyState>{active.length > 0 ? "под эти фильтры ничего не попало" : "событий пока нет"}</EmptyState>
        ) : (
          <>
            {result.records.map((r) => (
              <ChangeLine key={r.id} row={r} showSubject={!player} withDate />
            ))}
            <div className="pager">
              <AppButton onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0}>
                ← новее
              </AppButton>
              <span className="mono">стр. {page + 1}</span>
              <AppButton onClick={() => setPage((p) => p + 1)} disabled={(page + 1) * PAGE_SIZE >= result.total}>
                старше →
              </AppButton>
            </div>
          </>
        )}
      </Panel>
    </div>
  );
}
