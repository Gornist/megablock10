import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "./client";

/** Дефолт для списковых экранов — раньше независимо объявлялся как POLL_MS в каждом из них. */
export const DEFAULT_POLL_MS = 8000;

interface UseApiDataOptions {
  /**
   * Перезапрашивать в фоне каждые pollMs, без сброса data в null между
   * обновлениями (чтобы список не мигал пустотой). По умолчанию — DEFAULT_POLL_MS;
   * передайте false, чтобы отключить polling (разовая загрузка).
   */
  pollMs?: number | false;
  /**
   * Нужен, когда path — функция: по ключу хук понимает, что запрос стал другим, и перезагружает данные.
   * Функция вызывается при каждой загрузке, поэтому в ней можно брать «сейчас» (например, since = «за последний час»).
   */
  key?: string;
}

/**
 * Общий загрузчик для экранов-списков: раньше каждый экран сам писал
 * `api.get(...).then(setX)` без единого `.catch` — любая ошибка (не 401,
 * тот уже ловится в api/client.ts) оставляла экран на «загрузка…» навсегда,
 * без единого сообщения. Заодно даёт polling по умолчанию вместо того,
 * чтобы требовать от мастера жать F5.
 */
export function useApiData<T>(path: string | (() => string), options: UseApiDataOptions = {}) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const reload = useCallback(() => setTick((t) => t + 1), []);
  const pollMs = options.pollMs === false ? undefined : (options.pollMs ?? DEFAULT_POLL_MS);
  const queryKey = typeof path === "string" ? path : (options.key ?? "");

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const res = await api.get<T>(typeof path === "string" ? path : path());
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
  }, [queryKey, tick, pollMs]);

  return { data, error, reload };
}
