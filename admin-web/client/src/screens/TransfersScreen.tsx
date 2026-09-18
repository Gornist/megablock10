import type { Transfer } from "../api/types";
import { useApiData } from "../api/useApiData";
import { Badge, EmptyState, ErrorNote, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatAgo, formatTime, shortKey } from "../format";

const POLL_MS = 8000;

export function TransfersScreen() {
  const { data: transfers, error } = useApiData<Transfer[]>("/api/transfers", { pollMs: POLL_MS });

  const oneSided = (transfers ?? []).filter((t) => t.oneSided);

  const columns: Column<Transfer>[] = [
    { key: "from", label: "От", render: (t) => shortKey(t.from), sortValue: (t) => t.from },
    { key: "to", label: "Кому", render: (t) => shortKey(t.to), sortValue: (t) => t.to },
    { key: "amount", label: "Сумма", render: (t) => t.amount ?? "—", sortValue: (t) => Number(t.amount) || 0 },
    { key: "sentAt", label: "Отправлен", render: (t) => formatTime(t.sentAt), sortValue: (t) => t.sentAt ?? 0 },
    { key: "confirmedAt", label: "Подтверждён", render: (t) => formatTime(t.confirmedAt), sortValue: (t) => t.confirmedAt ?? 0 },
    {
      key: "status",
      label: "Статус",
      render: (t) => (t.oneSided ? <Badge tone="danger">односторонний, {formatAgo(t.sentAt ?? t.confirmedAt)}</Badge> : <Badge tone="ok">сведён</Badge>),
      sortValue: (t) => (t.oneSided ? 0 : 1),
    },
  ];

  return (
    <div className="screen-grid">
      {oneSided.length > 0 && (
        <Panel title={`Односторонние (${oneSided.length})`} className="warning-panel">
          <DataTable columns={columns} rows={oneSided} rowKey={(t) => t.txId} />
        </Panel>
      )}
      <Panel title={`Все переводы${transfers ? ` (${transfers.length})` : ""}`}>
        {error && <ErrorNote>{error}</ErrorNote>}
        {transfers === null ? (
          <EmptyState>загрузка…</EmptyState>
        ) : transfers.length === 0 ? (
          <EmptyState>переводов пока не было</EmptyState>
        ) : (
          <DataTable columns={columns} rows={transfers} rowKey={(t) => t.txId} />
        )}
      </Panel>
    </div>
  );
}
