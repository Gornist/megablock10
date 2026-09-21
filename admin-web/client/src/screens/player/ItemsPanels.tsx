import type { CharacterSnapshot } from "../../api/types";
import { Badge, EmptyState, HexRow, Panel } from "../../design/components";

/** Демоны и шарды игрока (то, что сервер знает о предметах: название, тир, состояние). */
export function ItemsPanels({ snapshot }: { snapshot: CharacterSnapshot }) {
  return (
    <>
    <Panel title={`Демоны (${snapshot.daemons.length})`}>
      {snapshot.daemons.length === 0 ? (
        <EmptyState>нет</EmptyState>
      ) : (
        snapshot.daemons.map((d) => (
          <HexRow key={d.daemonId}>
            {d.name} <Badge>{d.tier}</Badge> вес {d.weight} · {d.sourceRef ?? "—"}
          </HexRow>
        ))
      )}
    </Panel>

    <Panel title={`Шарды (${snapshot.shards.length})`}>
      {snapshot.shards.length === 0 ? (
        <EmptyState>нет</EmptyState>
      ) : (
        snapshot.shards.map((s) => (
          <HexRow key={s.shardId}>
            {s.title} <Badge>{s.tier}</Badge> <Badge tone={s.decrypted ? "ok" : "neutral"}>{s.decrypted ? "расшифрован" : "зашифрован"}</Badge> ·{" "}
            {s.sourceRef ?? "—"}
          </HexRow>
        ))
      )}
    </Panel>
    </>
  );
}
