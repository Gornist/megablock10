import type { EventsResponse } from "../api/types";
import { useApiData } from "../api/useApiData";
import { ChangeLine } from "../design/ChangeLine";
import { Pager } from "../design/Pager";
import { EmptyState, ErrorNote, Panel } from "../design/components";
import { EventFiltersPanel } from "./events/EventFiltersPanel";
import { eventsQuery, useEventFilters, type EventsPreset } from "./events/eventFilters";

const PAGE_SIZE = 50;
const POLL_MS = 5000;

/**
 * События с фильтрами: по игроку, фракции, типу, причине, узлу и периоду.
 * Фильтрует сервер (/api/events), а не браузер, поэтому работает и по истории,
 * которая давно вышла за живую ленту Обзора. Первая страница обновляется сама.
 * Состояние фильтров — screens/events/eventFilters.ts, панель — EventFiltersPanel.
 */
export function EventsScreen({ preset }: { preset: EventsPreset }) {
  const { filters, page, setPage, set, reset, anyActive } = useEventFilters(preset);

  // Первая страница обновляется сама; листая историю, страница не должна «плыть» под руками.
  const { data: result, error } = useApiData<EventsResponse>(() => eventsQuery(filters, page, PAGE_SIZE), {
    key: JSON.stringify([filters, page]),
    pollMs: page === 0 ? POLL_MS : false,
  });

  return (
    <div className="screen-grid">
      <EventFiltersPanel filters={filters} set={set} reset={reset} />

      <Panel title={`События${result ? ` (${result.total})` : ""}`}>
        {error && <ErrorNote>{error}</ErrorNote>}
        {result === null ? (
          <EmptyState>{error ? "" : "загрузка…"}</EmptyState>
        ) : result.records.length === 0 ? (
          <EmptyState>{anyActive ? "под эти фильтры ничего не попало" : "событий пока нет"}</EmptyState>
        ) : (
          <>
            {result.records.map((r) => (
              <ChangeLine key={r.id} row={r} showSubject={!filters.player} withDate />
            ))}
            <Pager page={page} pageSize={PAGE_SIZE} total={result.total} onPage={setPage} prevLabel="← новее" nextLabel="старше →" />
          </>
        )}
      </Panel>
    </div>
  );
}
