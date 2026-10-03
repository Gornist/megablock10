import { useCallback, useState } from "react";
import { ApiError } from "../../api/client";
import type { NetDoc, NetState } from "../../api/types";

/** Документы Моста одного типа (пусто, пока Моста нет: сервер тогда не отдаёт docs). */
export const docsOf = (s: NetState | null, type: string): NetDoc[] => s?.docs[type] ?? [];

export const text = (v: unknown): string => (typeof v === "string" ? v : "");
export const numOf = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
export const obj = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

/** Сколько осталось до срока в миллисекундах серверных часов («3:05»); null — срока нет. */
export function remainingLabel(untilMs: number | null, serverNow: number): string | null {
  if (!untilMs) return null;
  const left = Math.max(0, Math.round((untilMs - serverNow) / 1000));
  return `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`;
}

/** Новый короткий идентификатор действия (mid ответа, rid операции): создаётся один раз на нажатие и при повторе не меняется. */
export const newRef = (prefix: string): string => `${prefix}-${crypto.randomUUID().slice(0, 12)}`;

/**
 * Вызов REST «Сети» с общим состоянием «идёт / ошибка»: ответ Моста с отказом (503 «Мост недоступен», 409 конфликт версий…)
 * показывается мастеру как есть, а после успеха экран перечитывает снимок.
 */
export function useNetCall(onDone: () => void) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const call = useCallback(
    async (fn: () => Promise<unknown>): Promise<boolean> => {
      setBusy(true);
      setError(null);
      try {
        await fn();
        onDone();
        return true;
      } catch (e) {
        setError(e instanceof ApiError ? e.message : "не удалось связаться с сервером");
        return false;
      } finally {
        setBusy(false);
      }
    },
    [onDone],
  );
  return { busy, error, call, clearError: () => setError(null) };
}

/** Вид тревоги Моста → тон бейджа: аудитор (рассинхрон ценностей) — срочно, остальное — к сведению. */
export const alertTone = (kind: string): "danger" | "warn" => (kind.startsWith("auditor") ? "danger" : "warn");
