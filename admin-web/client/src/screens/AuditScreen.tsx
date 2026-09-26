import { useState } from "react";
import type { AuditResponse } from "../api/types";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { Pager } from "../design/Pager";
import { AppSelect, Badge, Panel } from "../design/components";
import { formatDateTime } from "../format";

const PAGE_SIZE = 50;

/** Журнал действий мастеров: кто, когда и что правил — правки игроков, массовые правки, объявления, аннулирования слотов, созданные контейнеры. */
export function AuditScreen() {
  const [action, setAction] = useState("");
  const [page, setPage] = useState(0);
  const q = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
  if (action) q.set("action", action);
  const { data, error } = useApiData<AuditResponse>(`/api/audit?${q}`);

  return (
    <Panel
      title={`Журнал действий мастеров${data ? ` (${data.total})` : ""}`}
      action={
        <AppSelect
          value={action}
          onChange={(e) => {
            setAction(e.target.value);
            setPage(0);
          }}
        >
          <option value="">все действия</option>
          {(data?.actions ?? []).map((a) => (
            <option key={a.action} value={a.action}>
              {a.label}
            </option>
          ))}
        </AppSelect>
      }
    >
      <AsyncPanel data={data} error={error} isEmpty={(d) => d.records.length === 0} emptyLabel="действий пока не было">
        {(d) => (
          <>
            {d.records.map((r) => (
              <div key={r.id} className="attn-item">
                <span className="attn-time mono">{formatDateTime(r.at)}</span>
                <Badge tone="accent">{r.masterName}</Badge>
                <span className="attn-title" style={{ color: "var(--ink)" }}>
                  {r.actionLabel}
                </span>
                <span className="attn-detail">{r.summary}</span>
              </div>
            ))}
            <Pager page={page} pageSize={PAGE_SIZE} total={d.total} onPage={setPage} />
          </>
        )}
      </AsyncPanel>
    </Panel>
  );
}
