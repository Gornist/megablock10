import type { NetDoc, NetState } from "../../api/types";
import { AsyncPanel } from "../../design/AsyncPanel";
import { Badge, Panel } from "../../design/components";
import { DataTable, type Column } from "../../design/DataTable";
import { formatAgo } from "../../format";
import { docsOf, numOf, obj, text } from "./netUtil";

const STATE_LABEL: Record<string, { label: string; tone: "ok" | "warn" | "neutral" }> = {
  pending: { label: "подключается", tone: "warn" },
  active: { label: "в Сети", tone: "ok" },
};

/** Нетраннеры в Сети сейчас: сессии не в состоянии «закрыта» — позывной, терминал и узел, уровень трейса, сколько предметов в деке. */
export function SessionsPanel({ state }: { state: NetState }) {
  const decks = new Map(docsOf(state, "deck").map((d) => [d.id, Array.isArray(d.data.items) ? d.data.items.length : 0]));
  const rows = docsOf(state, "session").filter((s) => s.data.state === "pending" || s.data.state === "active");

  const columns: Column<NetDoc>[] = [
    { key: "callsign", label: "Нетраннер", render: (s) => text(s.data.callsign) || "—", sortValue: (s) => text(s.data.callsign) },
    { key: "state", label: "Состояние", render: (s) => <Badge tone={STATE_LABEL[text(s.data.state)]?.tone}>{STATE_LABEL[text(s.data.state)]?.label ?? text(s.data.state)}</Badge> },
    { key: "terminal", label: "Терминал", render: (s) => <span className="mono">{text(s.data.terminal) || "—"}</span>, sortValue: (s) => text(s.data.terminal) },
    { key: "node", label: "Узел", render: (s) => <span className="mono">{text(s.data.node) || "—"}</span>, sortValue: (s) => text(s.data.node) },
    {
      key: "trace",
      label: "Трейс",
      render: (s) => {
        const w = obj(s.data.world);
        const trace = numOf(w.trace);
        if (trace === null) return "—";
        return <Badge tone={trace >= 70 ? "danger" : trace >= 40 ? "warn" : "neutral"}>{`${trace}${text(w.level) ? ` · ${text(w.level)}` : ""}`}</Badge>;
      },
      sortValue: (s) => numOf(obj(s.data.world).trace) ?? -1,
    },
    { key: "deck", label: "Дека", render: (s) => decks.get(s.id) ?? "—", sortValue: (s) => decks.get(s.id) ?? -1 },
    { key: "loot", label: "Эдди добыто", render: (s) => numOf(s.data.loot_eddies) ?? 0 },
    { key: "since", label: "В Сети", render: (s) => formatAgo(numOf(s.data.confirmed_at) ?? s.created), sortValue: (s) => numOf(s.data.confirmed_at) ?? s.created },
  ];

  return (
    <Panel title={`Нетраннеры в Сети (${rows.length})`}>
      <AsyncPanel data={rows} isEmpty={(d) => d.length === 0} emptyLabel="в Сети никого нет">
        {(d) => <DataTable columns={columns} rows={d} rowKey={(s) => s.id} />}
      </AsyncPanel>
    </Panel>
  );
}
