import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "./client";

interface UseApiDataOptions {
  /** Если задано — перезапрашивать в фоне каждые pollMs, без сброса data в null между обновлениями (чтобы список не мигал пустотой). */
  pollMs?: number;
}

/**
 * Общий загрузчик для экранов-списков: раньше каждый экран сам писал
 * `api.get(...).then(setX)` без единого `.catch` — любая ошибка (не 401,
 * тот уже ловится в api/client.ts) оставляла экран на «загрузка…» навсегда,
 * без единого сообщения. Заодно даёт опциональный polling вместо того,
 * чтобы требовать от мастера жать F5.
 */
export function useApiData<T>(path: string, options: UseApiDataOptions = {}) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const reload = useCallback(() => setTick((t) => t + 1), []);
  const pollMs = options.pollMs;

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const res = await api.get<T>(path);
        if (!cancelled) {
          setData(res);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) setError(err instanceof ApiError ? err.message : "не удалось связаться с сервером");
      }
    }

    load();
    const id = pollMs ? setInterval(load, pollMs) : undefined;
    return () => {
      cancelled = true;
      if (id) clearInterval(id);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, tick, pollMs]);

  return { data, error, reload };
}
