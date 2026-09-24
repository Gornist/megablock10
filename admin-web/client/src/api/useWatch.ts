import { useCallback, useMemo } from "react";
import { api } from "./client";
import type { WatchItem } from "./types";
import { useApiData } from "./useApiData";
import { POLL_BACKGROUND_MS } from "./pollIntervals";

/** Игроки «под наблюдением» — общий список всех мастеров (хранится на сервере). Опрашивается редко: меняется руками. */
export function useWatch() {
  const { data, error, reload } = useApiData<WatchItem[]>("/api/watch", { pollMs: POLL_BACKGROUND_MS });
  const byKey = useMemo(() => new Map((data ?? []).map((w) => [w.publicKeyB64, w])), [data]);

  const set = useCallback(
    async (key: string, note = "") => {
      await api.put(`/api/watch/${encodeURIComponent(key)}`, { note });
      reload();
    },
    [reload],
  );
  const remove = useCallback(
    async (key: string) => {
      await api.delete(`/api/watch/${encodeURIComponent(key)}`);
      reload();
    },
    [reload],
  );

  return { items: data ?? [], byKey, error, set, remove };
}
