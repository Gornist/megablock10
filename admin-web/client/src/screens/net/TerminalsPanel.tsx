import type { NetDoc, NetState } from "../../api/types";
import { AsyncPanel } from "../../design/AsyncPanel";
import { Badge, Panel } from "../../design/components";
import { DataTable, type Column } from "../../design/DataTable";
import { formatAgo } from "../../format";
import { docsOf, numOf, text } from "./netUtil";

/** Терминалы и очки: заряд, кадры в секунду, связь и когда в последний раз «били сердце». Флаг silent — очки молчат (правило Моста). */
export function TerminalsPanel({ state }: { state: NetState }) {
  const rows = docsOf(state, "terminal");
  const columns: Column<NetDoc>[] = [
    { key: "id", label: "Терминал", render: (t) => (<><span className="mono">{t.id}</span> {text(t.data.label)}</>), sortValue: (t) => t.id },
    { key: "node", label: "Узел", render: (t) => <span className="mono">{text(t.data.node) || "—"}</span>, sortValue: (t) => text(t.data.node) },
    {
      key: "state",
      label: "Очки",
      render: (t) => (t.data.silent === true ? <Badge tone="danger">молчат</Badge> : <Badge tone="ok">на связи</Badge>),
      sortValue: (t) => (t.data.silent === true ? 1 : 0),
    },
    {
      key: "battery",
      label: "Заряд",
      render: (t) => {
        const b = numOf(t.data.battery);
        return b === null ? "—" : <Badge tone={b < 20 ? "danger" : b < 40 ? "warn" : "neutral"}>{`${b}%`}</Badge>;
      },
      sortValue: (t) => numOf(t.data.battery) ?? -1,
    },
    { key: "fps", label: "Кадров/с", render: (t) => numOf(t.data.fps) ?? "—", sortValue: (t) => numOf(t.data.fps) ?? -1 },
    { key: "link", label: "Связь", render: (t) => (typeof t.data.link === "number" ? `${t.data.link}%` : text(t.data.link) || "—") },
    { key: "beat", label: "Сердце", render: (t) => formatAgo(numOf(t.data.beat_at)), sortValue: (t) => numOf(t.data.beat_at) ?? 0 },
  ];
  return (
    <Panel title={`Терминалы и очки (${rows.length})`}>
      <AsyncPanel data={rows} isEmpty={(d) => d.length === 0} emptyLabel="терминалов нет">
        {(d) => <DataTable columns={columns} rows={d} rowKey={(t) => t.id} />}
      </AsyncPanel>
    </Panel>
  );
}
