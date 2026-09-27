import { useState } from "react";

const COLLAPSED_KEY = "mb10_display_groups_collapsed";

/** Какие группы свёрнуты — per-браузер удобство мастера: не пережило (приватный режим, чистка) — всё развёрнуто. */
export function useCollapsedGroups(): [Set<string>, (key: string) => void] {
  const [collapsed, setCollapsed] = useState<Set<string>>(() => {
    try {
      const raw = localStorage.getItem(COLLAPSED_KEY);
      return new Set(raw ? (JSON.parse(raw) as string[]) : []);
    } catch {
      return new Set();
    }
  });
  const toggle = (key: string) =>
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      try {
        localStorage.setItem(COLLAPSED_KEY, JSON.stringify([...next]));
      } catch {
        // localStorage недоступен — свёрнутость просто не запомнится
      }
      return next;
    });
  return [collapsed, toggle];
}
