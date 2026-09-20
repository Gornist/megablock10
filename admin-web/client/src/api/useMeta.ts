import { useEffect, useState } from "react";
import { api } from "./client";
import type { Meta } from "./types";

/** Справочники (причины событий, типы) грузятся с сервера один раз на вкладку и делятся между экранами — единственный источник подписей. */
let cached: Meta | null = null;
let loading: Promise<void> | null = null;
const listeners = new Set<() => void>();

function load() {
  if (loading) return;
  loading = api
    .get<Meta>("/api/meta")
    .then((m) => {
      cached = m;
      listeners.forEach((l) => l());
    })
    .catch(() => {
      // Подписи не критичны: без них экраны показывают коды причин. Следующая попытка — при следующем монтировании.
    })
    .finally(() => {
      loading = null;
    });
}

export function useMeta(): Meta | null {
  const [, rerender] = useState(0);
  useEffect(() => {
    const listener = () => rerender((n) => n + 1);
    listeners.add(listener);
    if (!cached) load();
    return () => {
      listeners.delete(listener);
    };
  }, []);
  return cached;
}

/** Подпись причины; пока справочник не загружен — сам код. */
export function reasonLabel(meta: Meta | null, code: string): string {
  return meta?.reasons.find((r) => r.code === code)?.label ?? code;
}
