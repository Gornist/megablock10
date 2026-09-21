import { useState } from "react";

/** Как в API: значение фильтра «игроки без фракции» (пустую строку в адресе не передать). */
export const NO_FACTION = "__none__";

export const PERIODS: { value: string; label: string }[] = [
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

export interface EventFilters {
  player: string;
  faction: string;
  node: string;
  kind: string;
  reason: string;
  /** Минуты назад или пусто — за всё время. */
  period: string;
}

export const EMPTY_FILTERS: EventFilters = { player: "", faction: "", node: "", kind: "", reason: "", period: "" };

export function filtersFromPreset(preset: EventsPreset): EventFilters {
  const f = { ...EMPTY_FILTERS };
  if (preset.type === "player" || preset.type === "faction" || preset.type === "node") f[preset.type] = preset.value ?? "";
  return f;
}

/** Адрес запроса к /api/events: пустые фильтры не передаются; «период» превращается в since по часам браузера в момент запроса. */
export function eventsQuery(f: EventFilters, page: number, pageSize: number, now = Date.now()): string {
  const q = new URLSearchParams({ page: String(page), pageSize: String(pageSize) });
  if (f.player) q.set("player", f.player);
  if (f.faction) q.set("faction", f.faction);
  if (f.node) q.set("node", f.node);
  if (f.kind) q.set("kind", f.kind);
  if (f.reason) q.set("reason", f.reason);
  if (f.period) q.set("since", String(now - Number(f.period) * 60_000));
  return `/api/events?${q}`;
}

/** Фильтры и страница вместе: смена любого фильтра возвращает на первую страницу. */
export function useEventFilters(preset: EventsPreset) {
  const [filters, setFilters] = useState<EventFilters>(() => filtersFromPreset(preset));
  const [page, setPage] = useState(0);
  return {
    filters,
    page,
    setPage,
    set: (key: keyof EventFilters) => (value: string) => {
      setFilters((f) => ({ ...f, [key]: value }));
      setPage(0);
    },
    reset: () => {
      setFilters(EMPTY_FILTERS);
      setPage(0);
    },
    anyActive: Object.values(filters).some(Boolean),
  };
}
