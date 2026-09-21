import { useState } from "react";
import type { EventsResponse } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { useMeta } from "../../api/useMeta";
import { AppInput, AppSelect, EmptyState, ErrorNote, Panel } from "../../design/components";
import { ChangeLine } from "../../design/ChangeLine";
import { Pager } from "../../design/Pager";

const PAGE_SIZE = 50;

/** История игрока с фильтрами по причине и источнику; refreshTick перезагружает её после правки мастера (сервер параметр t игнорирует). */
export function HistoryPanel({ publicKeyB64, refreshTick }: { publicKeyB64: string; refreshTick: number }) {
  const meta = useMeta();
  const [reasonFilter, setReasonFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("");
  const [page, setPage] = useState(0);

  const query = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE), t: String(refreshTick) });
  if (reasonFilter) query.set("reason", reasonFilter);
  if (sourceFilter) query.set("source", sourceFilter);
  const { data, error } = useApiData<EventsResponse>(`/api/players/${encodeURIComponent(publicKeyB64)}/history?${query}`, { pollMs: false });
  const history = data?.records ?? null;
  const total = data?.total ?? 0;

  return (
    <Panel
      title={`История (${total})`}
      action={
        <div className="filter-row">
          <AppSelect
            value={reasonFilter}
            onChange={(e) => {
              setReasonFilter(e.target.value);
              setPage(0);
            }}
          >
            <option value="">все причины</option>
            {(meta?.reasons ?? []).map((r) => (
              <option key={r.code} value={r.code}>
                {r.label}
              </option>
            ))}
          </AppSelect>
          <AppInput
            placeholder="поиск по источнику"
            value={sourceFilter}
            onChange={(e) => {
              setSourceFilter(e.target.value);
              setPage(0);
            }}
          />
        </div>
      }
    >
      {error && <ErrorNote>{error}</ErrorNote>}
      {history === null ? (
        <EmptyState>загрузка…</EmptyState>
      ) : history.length === 0 ? (
        <EmptyState>нет записей</EmptyState>
      ) : (
        <>
          {history.map((r) => (
            <ChangeLine key={r.id} row={r} showSubject={false} time="happened" />
          ))}
          <Pager page={page} pageSize={PAGE_SIZE} total={total} onPage={setPage} />
        </>
      )}
    </Panel>
  );
}
