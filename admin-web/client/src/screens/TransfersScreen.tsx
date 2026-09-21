import type { Transfer } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { Badge, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { formatAgo, formatTime, shortKey } from "../format";

export function TransfersScreen() {
  const { data: transfers, error } = useApiData<Transfer[]>("/api/transfers");

  const oneSided = (transfers ?? []).filter((t) => t.oneSided);

  const columns: Column<Transfer>[] = [
    { key: "from", label: "От", render: (t) => <span title={t.from}>{t.fromName ?? shortKey(t.from)}</span>, sortValue: (t) => t.fromName ?? t.from },
    { key: "to", label: "Кому", render: (t) => (t.to ? <span title={t.to}>{t.toName ?? shortKey(t.to)}</span> : <span className="hint-text">не подтверждён получателем</span>), sortValue: (t) => t.toName ?? t.to ?? "" },
    { key: "amount", label: "Сумма", render: (t) => t.amount, sortValue: (t) => t.amount },
    { key: "sentAt", label: "Отправлен", render: (t) => formatTime(t.sentAt), sortValue: (t) => t.sentAt ?? 0 },
    { key: "confirmedAt", label: "Подтверждён", render: (t) => formatTime(t.confirmedAt), sortValue: (t) => t.confirmedAt ?? 0 },
    {
      key: "status",
      label: "Статус",
      render: (t) =>
        t.cancelledAt !== null ? (
          <Badge tone="neutral">отменён отправителем</Badge>
        ) : t.oneSided ? (
          <Badge tone="danger">односторонний, {formatAgo(t.sentAt ?? t.confirmedAt)}</Badge>
        ) : (
          <Badge tone="ok">сведён</Badge>
        ),
      sortValue: (t) => (t.cancelledAt !== null ? 2 : t.oneSided ? 0 : 1),
    },
  ];

  return (
    <div className="screen-grid">
      {oneSided.length > 0 && (
        <Panel title={`Односторонние (${oneSided.length})`} className="warning-panel">
          <p className="hint-text">
            Приложение такой платёж само не отменит. Если получатель не выходит на связь — поправьте баланс отправителя правкой мастера (карточка игрока).
          </p>
          <DataTable columns={columns} rows={oneSided} rowKey={(t) => t.txId} />
        </Panel>
      )}
      <Panel title={`Все переводы${transfers ? ` (${transfers.length})` : ""}`}>
        <AsyncPanel data={transfers} error={error} isEmpty={(d) => d.length === 0} emptyLabel="переводов пока не было">
          {(d) => <DataTable columns={columns} rows={d} rowKey={(t) => t.txId} />}
        </AsyncPanel>
      </Panel>
    </div>
  );
}
