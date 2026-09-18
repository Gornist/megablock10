import { useCallback, useState } from "react";
import { ApiError } from "./client";

interface UseAsyncActionOptions {
  /** Сообщение, если ошибка не ApiError (сеть недоступна и т.п.). */
  fallbackError?: string;
}

export type AsyncActionResult<T> = { ok: true; value: T } | { ok: false };

/**
 * Общий busy/error/try-catch-finally для кнопок-действий: раньше в
 * MasterScreen.tsx этот блок вручную повторялся 4 раза (контейнер, шард,
 * RAM, создание мастера), в LoginScreen.tsx и OverridePanel — ещё по разу,
 * а в SlotsScreen.tsx его не было вовсе (ошибка сети тихо роняла диалог).
 * run() возвращает { ok: true, value } либо { ok: false } — так вызывающий
 * код не путает «действие вернуло undefined» с «действие упало».
 */
export function useAsyncAction(options: UseAsyncActionOptions = {}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fallbackError = options.fallbackError ?? "не удалось выполнить";

  const run = useCallback(
    async <T,>(action: () => Promise<T>): Promise<AsyncActionResult<T>> => {
      setBusy(true);
      setError(null);
      try {
        const value = await action();
        return { ok: true, value };
      } catch (err) {
        setError(err instanceof ApiError ? err.message : fallbackError);
        return { ok: false };
      } finally {
        setBusy(false);
      }
    },
    [fallbackError],
  );

  return { busy, error, setError, run };
}
